use async_trait::async_trait;
use base64::{Engine, engine::general_purpose::STANDARD};
use chrono::Utc;
use futures::{StreamExt, stream};
use hunt_core::{
    CANDIDATE_ARTIFACT_TEXT_KEY, CANDIDATE_ARTIFACT_URL_KEY, Candidate, ScanRequest, SourceKind,
    SourceQuota,
};
use regex::Regex;
use reqwest::{Client, IntoUrl, Response, StatusCode};
use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::{
    collections::BTreeMap,
    fmt,
    net::IpAddr,
    sync::{Arc, LazyLock},
    time::{Duration, Instant},
};
use thiserror::Error;

const MAX_SOURCE_RESULTS: usize = 1_000;
const DEFAULT_PAGE_SIZE: usize = 100;
const MAX_SOURCE_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const MAX_GITHUB_FILE_BYTES: usize = 512 * 1024;
const MAX_ARTIFACT_CONTEXT_BYTES: usize = 16 * 1024;
const GITHUB_CONTENT_CONCURRENCY: usize = 6;
const MAX_GIT_REPOSITORIES: usize = 5;
const MAX_GIT_FILES_PER_REPOSITORY: usize = 8;
const GIT_REPOSITORY_CONCURRENCY: usize = 3;
const GIT_CONTENT_CONCURRENCY: usize = 4;
static URL_PATTERN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"https?://[^\s\"'<>\\]{4,2048}"#).expect("内置 URL 正则必须有效")
});

#[derive(Clone, Copy, Debug)]
pub enum HttpRequestOutcome {
    Success(u16),
    Failure(u16),
    Timeout,
    TransportFailure,
}

pub struct HttpRequestObservation {
    pub ticket: u64,
    pub client: Client,
}

pub trait HttpRequestObserver: Send + Sync {
    fn begin(&self, target: &reqwest::Url) -> reqwest::Result<Option<HttpRequestObservation>>;
    fn complete(&self, ticket: Option<u64>, elapsed: Duration, outcome: HttpRequestOutcome);
}

#[derive(Clone)]
pub struct ObservedHttpClient {
    client: Client,
    observer: Arc<dyn HttpRequestObserver>,
}

impl ObservedHttpClient {
    pub fn new(client: Client, observer: Arc<dyn HttpRequestObserver>) -> Self {
        Self { client, observer }
    }

    pub fn get(&self, url: impl IntoUrl) -> ObservedRequestBuilder {
        ObservedRequestBuilder::new(self.clone(), self.client.get(url))
    }

    pub fn post(&self, url: impl IntoUrl) -> ObservedRequestBuilder {
        ObservedRequestBuilder::new(self.clone(), self.client.post(url))
    }
}

pub struct ObservedRequestBuilder {
    client: ObservedHttpClient,
    request: reqwest::RequestBuilder,
}

struct HttpRequestCompletion {
    observer: Arc<dyn HttpRequestObserver>,
    ticket: Option<u64>,
    started: Instant,
}

impl HttpRequestCompletion {
    fn new(observer: Arc<dyn HttpRequestObserver>, ticket: Option<u64>) -> Self {
        Self {
            observer,
            ticket,
            started: Instant::now(),
        }
    }

    fn complete(mut self, outcome: HttpRequestOutcome) {
        let ticket = self.ticket.take();
        self.observer
            .complete(ticket, self.started.elapsed(), outcome);
    }
}

impl Drop for HttpRequestCompletion {
    fn drop(&mut self) {
        if let Some(ticket) = self.ticket.take() {
            self.observer.complete(
                Some(ticket),
                self.started.elapsed(),
                HttpRequestOutcome::TransportFailure,
            );
        }
    }
}

impl ObservedRequestBuilder {
    fn new(client: ObservedHttpClient, request: reqwest::RequestBuilder) -> Self {
        Self { client, request }
    }

    pub fn header(self, name: &str, value: &str) -> Self {
        Self {
            request: self.request.header(name, value),
            ..self
        }
    }

    pub fn bearer_auth<T: fmt::Display>(self, token: T) -> Self {
        Self {
            request: self.request.bearer_auth(token),
            ..self
        }
    }

    pub fn query<T: Serialize + ?Sized>(self, query: &T) -> Self {
        Self {
            request: self.request.query(query),
            ..self
        }
    }

    pub fn json<T: Serialize + ?Sized>(self, value: &T) -> Self {
        Self {
            request: self.request.json(value),
            ..self
        }
    }

    pub async fn send(self) -> reqwest::Result<Response> {
        let request = self.request.build()?;
        let observation = self.client.observer.begin(request.url())?;
        let ticket = observation.as_ref().map(|value| value.ticket);
        let client = observation
            .map(|value| value.client)
            .unwrap_or_else(|| self.client.client.clone());
        let completion = HttpRequestCompletion::new(self.client.observer.clone(), ticket);
        let response = client.execute(request).await;
        let outcome = match &response {
            Ok(response)
                if response.status().is_success() || response.status().is_redirection() =>
            {
                HttpRequestOutcome::Success(response.status().as_u16())
            }
            Ok(response) => HttpRequestOutcome::Failure(response.status().as_u16()),
            Err(error) if error.is_timeout() => HttpRequestOutcome::Timeout,
            Err(_) => HttpRequestOutcome::TransportFailure,
        };
        completion.complete(outcome);
        response
    }
}

#[derive(Clone, Default)]
pub struct SourceCredentials {
    pub github_token: Option<SecretString>,
    pub gitee_token: Option<SecretString>,
    pub gitcode_token: Option<SecretString>,
    pub fofa_email: Option<SecretString>,
    pub fofa_key: Option<SecretString>,
    pub shodan_key: Option<SecretString>,
}

#[derive(Debug, Error)]
pub enum SourceError {
    #[error("{0} 未配置 API 凭证。")]
    MissingCredential(&'static str),
    #[error("{platform} 请求失败：HTTP {status}")]
    Http { platform: &'static str, status: u16 },
    #[error("{0} 网络请求失败。")]
    Transport(&'static str),
    #[error("{platform} 返回数据超过 {limit} 字节限制。")]
    ResponseTooLarge {
        platform: &'static str,
        limit: usize,
    },
    #[error("{0} 返回的数据格式无效。")]
    InvalidResponse(&'static str),
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

#[async_trait]
pub trait AssetSource: Send + Sync {
    fn kind(&self) -> SourceKind;
    async fn discover(
        &self,
        request: &ScanRequest,
        credentials: &SourceCredentials,
    ) -> Result<Vec<Candidate>, SourceError>;
    async fn quota(&self, credentials: &SourceCredentials) -> Result<SourceQuota, SourceError>;
}

pub struct SourceRegistry {
    sources: BTreeMap<SourceKind, Box<dyn AssetSource>>,
}

impl SourceRegistry {
    pub fn new(client: ObservedHttpClient) -> Self {
        let mut sources: BTreeMap<SourceKind, Box<dyn AssetSource>> = BTreeMap::new();
        sources.insert(SourceKind::Manual, Box::new(ManualSource));
        sources.insert(
            SourceKind::Github,
            Box::new(GithubSource::new(client.clone(), SourceKind::Github)),
        );
        sources.insert(
            SourceKind::GithubArtifact,
            Box::new(GithubSource::new(
                client.clone(),
                SourceKind::GithubArtifact,
            )),
        );
        sources.insert(
            SourceKind::Gitee,
            Box::new(GitPlatformSource::new(
                client.clone(),
                SourceKind::Gitee,
                "Gitee",
                "https://gitee.com/api/v5",
                "https://gitee.com",
            )),
        );
        sources.insert(
            SourceKind::Gitcode,
            Box::new(GitPlatformSource::new(
                client.clone(),
                SourceKind::Gitcode,
                "GitCode",
                "https://api.gitcode.com/api/v5",
                "https://gitcode.com",
            )),
        );
        sources.insert(SourceKind::Fofa, Box::new(FofaSource::new(client.clone())));
        sources.insert(SourceKind::Shodan, Box::new(ShodanSource::new(client)));
        Self { sources }
    }

    pub async fn discover(
        &self,
        kind: SourceKind,
        request: &ScanRequest,
        credentials: &SourceCredentials,
    ) -> Result<Vec<Candidate>, SourceError> {
        let source = self
            .sources
            .get(&kind)
            .ok_or_else(|| SourceError::Other(anyhow::anyhow!("未知扫描数据源")))?;
        source.discover(request, credentials).await
    }

    pub async fn quotas(&self, credentials: &SourceCredentials) -> Vec<SourceQuota> {
        let github = self
            .sources
            .get(&SourceKind::Github)
            .expect("内置 GitHub 数据源必须存在")
            .as_ref();
        let gitee = self
            .sources
            .get(&SourceKind::Gitee)
            .expect("内置 Gitee 数据源必须存在")
            .as_ref();
        let gitcode = self
            .sources
            .get(&SourceKind::Gitcode)
            .expect("内置 GitCode 数据源必须存在")
            .as_ref();
        let fofa = self
            .sources
            .get(&SourceKind::Fofa)
            .expect("内置 FOFA 数据源必须存在")
            .as_ref();
        let shodan = self
            .sources
            .get(&SourceKind::Shodan)
            .expect("内置 Shodan 数据源必须存在")
            .as_ref();
        let (github, gitee, gitcode, fofa, shodan) = futures::join!(
            quota_or_status(github, credentials),
            quota_or_status(gitee, credentials),
            quota_or_status(gitcode, credentials),
            quota_or_status(fofa, credentials),
            quota_or_status(shodan, credentials),
        );
        vec![github, gitee, gitcode, fofa, shodan]
    }
}

async fn quota_or_status(source: &dyn AssetSource, credentials: &SourceCredentials) -> SourceQuota {
    source
        .quota(credentials)
        .await
        .unwrap_or_else(|error| SourceQuota {
            source: source.kind(),
            configured: !matches!(&error, SourceError::MissingCredential(_)),
            available: false,
            remaining: None,
            limit: None,
            resets_at: None,
            message: error.to_string(),
        })
}

struct ManualSource;

#[async_trait]
impl AssetSource for ManualSource {
    fn kind(&self) -> SourceKind {
        SourceKind::Manual
    }

    async fn discover(
        &self,
        request: &ScanRequest,
        _credentials: &SourceCredentials,
    ) -> Result<Vec<Candidate>, SourceError> {
        Ok(request
            .targets
            .iter()
            .take(MAX_SOURCE_RESULTS)
            .map(|target| Candidate {
                source: SourceKind::Manual,
                target: target.clone(),
                discovered_at: Utc::now(),
                metadata: BTreeMap::new(),
            })
            .collect())
    }

    async fn quota(&self, _credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        Ok(unlimited_quota(
            SourceKind::Manual,
            "手工目标不消耗第三方配额。",
        ))
    }
}

struct GithubSource {
    client: ObservedHttpClient,
    kind: SourceKind,
}

impl GithubSource {
    fn new(client: ObservedHttpClient, kind: SourceKind) -> Self {
        Self { client, kind }
    }
}

#[derive(Deserialize)]
struct GithubSearchResponse {
    items: Vec<GithubCodeItem>,
}

#[derive(Deserialize)]
struct GithubCodeItem {
    url: String,
    html_url: String,
}

#[derive(Deserialize)]
struct GithubContentResponse {
    content: Option<String>,
    encoding: Option<String>,
}

#[derive(Deserialize)]
struct GithubRateLimitResponse {
    resources: GithubResources,
}

#[derive(Deserialize)]
struct GithubResources {
    code_search: GithubRateLimit,
}

#[derive(Deserialize)]
struct GithubRateLimit {
    limit: u64,
    remaining: u64,
    reset: i64,
}

#[async_trait]
impl AssetSource for GithubSource {
    fn kind(&self) -> SourceKind {
        self.kind
    }

    async fn discover(
        &self,
        request: &ScanRequest,
        credentials: &SourceCredentials,
    ) -> Result<Vec<Candidate>, SourceError> {
        let token = credentials
            .github_token
            .as_ref()
            .ok_or(SourceError::MissingCredential("GitHub"))?;
        let query_key = if self.kind == SourceKind::GithubArtifact {
            "github_artifact"
        } else {
            "github"
        };
        let query = source_query(request, query_key)
            .or_else(|| source_query(request, "github"))
            .unwrap_or_else(|| default_github_query(request));
        let response = self
            .client
            .get("https://api.github.com/search/code")
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .bearer_auth(token.expose_secret())
            .query(&[("q", query), ("per_page", DEFAULT_PAGE_SIZE.to_string())])
            .send()
            .await
            .map_err(|_| SourceError::Transport("GitHub"))?;
        ensure_success("GitHub", response.status())?;
        let search = parse_json_limited::<GithubSearchResponse>("GitHub", response).await?;
        let client = self.client.clone();
        let kind = self.kind;
        let token = token.expose_secret().to_owned();
        let batches = stream::iter(
            search
                .items
                .into_iter()
                .take(DEFAULT_PAGE_SIZE)
                .map(|item| {
                    let client = client.clone();
                    let token = token.clone();
                    async move { github_item_candidates(client, kind, token, item).await }
                }),
        )
        .buffer_unordered(GITHUB_CONTENT_CONCURRENCY);
        futures::pin_mut!(batches);
        let mut candidates = Vec::new();
        while let Some(batch) = batches.next().await {
            for candidate in batch.into_iter().flatten() {
                candidates.push(candidate);
                if candidates.len() >= MAX_SOURCE_RESULTS {
                    return Ok(candidates);
                }
            }
        }
        Ok(candidates)
    }

    async fn quota(&self, credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        let token = credentials
            .github_token
            .as_ref()
            .ok_or(SourceError::MissingCredential("GitHub"))?;
        let response = self
            .client
            .get("https://api.github.com/rate_limit")
            .header("Accept", "application/vnd.github+json")
            .bearer_auth(token.expose_secret())
            .send()
            .await
            .map_err(|_| SourceError::Transport("GitHub"))?;
        ensure_success("GitHub", response.status())?;
        let quota = parse_json_limited::<GithubRateLimitResponse>("GitHub", response)
            .await?
            .resources
            .code_search;
        Ok(SourceQuota {
            source: self.kind,
            configured: true,
            available: true,
            remaining: Some(quota.remaining),
            limit: Some(quota.limit),
            resets_at: chrono::DateTime::from_timestamp(quota.reset, 0),
            message: "GitHub Code Search 配额正常。".to_owned(),
        })
    }
}

struct GitPlatformSource {
    client: ObservedHttpClient,
    kind: SourceKind,
    platform: &'static str,
    api_base: &'static str,
    web_base: &'static str,
}

impl GitPlatformSource {
    fn new(
        client: ObservedHttpClient,
        kind: SourceKind,
        platform: &'static str,
        api_base: &'static str,
        web_base: &'static str,
    ) -> Self {
        Self {
            client,
            kind,
            platform,
            api_base,
            web_base,
        }
    }

    fn token<'a>(&self, credentials: &'a SourceCredentials) -> Option<&'a SecretString> {
        match self.kind {
            SourceKind::Gitee => credentials.gitee_token.as_ref(),
            SourceKind::Gitcode => credentials.gitcode_token.as_ref(),
            _ => None,
        }
    }

    fn authorized_get(&self, url: impl reqwest::IntoUrl, token: &str) -> ObservedRequestBuilder {
        let request = self.client.get(url);
        match self.kind {
            SourceKind::Gitee => request.query(&[("access_token", token)]),
            SourceKind::Gitcode => request.header("PRIVATE-TOKEN", token).bearer_auth(token),
            _ => request,
        }
    }
}

#[derive(Deserialize)]
#[serde(untagged)]
enum GitPlatformSearchResponse {
    Items { items: Vec<GitPlatformRepository> },
    List(Vec<GitPlatformRepository>),
}

impl GitPlatformSearchResponse {
    fn into_repositories(self) -> Vec<GitPlatformRepository> {
        match self {
            Self::Items { items } | Self::List(items) => items,
        }
    }
}

#[derive(Clone, Deserialize)]
struct GitPlatformRepository {
    full_name: Option<String>,
    html_url: Option<String>,
    default_branch: Option<String>,
}

#[derive(Clone, Deserialize)]
struct GitTreeEntry {
    path: String,
    #[serde(rename = "type")]
    kind: String,
    sha: String,
    size: Option<u64>,
}

#[derive(Deserialize)]
struct GitTreeResponse {
    #[serde(default)]
    tree: Vec<GitTreeEntry>,
}

#[async_trait]
impl AssetSource for GitPlatformSource {
    fn kind(&self) -> SourceKind {
        self.kind
    }

    async fn discover(
        &self,
        request: &ScanRequest,
        credentials: &SourceCredentials,
    ) -> Result<Vec<Candidate>, SourceError> {
        let token = self
            .token(credentials)
            .ok_or(SourceError::MissingCredential(self.platform))?;
        let query = source_query(
            request,
            match self.kind {
                SourceKind::Gitee => "gitee",
                SourceKind::Gitcode => "gitcode",
                _ => unreachable!("代码托管数据源类型固定"),
            },
        )
        .unwrap_or_else(|| default_repository_query(request));
        let repositories = self
            .repositories_for_query(&query, token.expose_secret())
            .await?;
        let source = self.clone_for_tasks();
        let token = token.expose_secret().to_owned();
        let batches = stream::iter(repositories.into_iter().take(MAX_GIT_REPOSITORIES).map(
            |repository| {
                let source = source.clone_for_tasks();
                let token = token.clone();
                async move { source.repository_candidates(&token, repository).await }
            },
        ))
        .buffer_unordered(GIT_REPOSITORY_CONCURRENCY);
        futures::pin_mut!(batches);
        let mut candidates = Vec::new();
        while let Some(batch) = batches.next().await {
            for candidate in batch.into_iter().flatten() {
                candidates.push(candidate);
                if candidates.len() >= MAX_SOURCE_RESULTS {
                    return Ok(candidates);
                }
            }
        }
        Ok(candidates)
    }

    async fn quota(&self, credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        let token = self
            .token(credentials)
            .ok_or(SourceError::MissingCredential(self.platform))?;
        let response = self
            .authorized_get(format!("{}/user", self.api_base), token.expose_secret())
            .send()
            .await
            .map_err(|_| SourceError::Transport(self.platform))?;
        ensure_success(self.platform, response.status())?;
        let remaining = response
            .headers()
            .get("x-ratelimit-remaining")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse().ok());
        let limit = response
            .headers()
            .get("x-ratelimit-limit")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse().ok());
        let resets_at = response
            .headers()
            .get("x-ratelimit-reset")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse().ok())
            .and_then(|value| chrono::DateTime::from_timestamp(value, 0));
        Ok(SourceQuota {
            source: self.kind,
            configured: true,
            available: true,
            remaining,
            limit,
            resets_at,
            message: format!("{} 访问令牌有效。", self.platform),
        })
    }
}

impl GitPlatformSource {
    fn clone_for_tasks(&self) -> Self {
        Self::new(
            self.client.clone(),
            self.kind,
            self.platform,
            self.api_base,
            self.web_base,
        )
    }

    async fn repositories_for_query(
        &self,
        query: &str,
        token: &str,
    ) -> Result<Vec<GitPlatformRepository>, SourceError> {
        if let Some((owner, repository)) = direct_repository(query) {
            let response = self
                .authorized_get(
                    format!(
                        "{}/repos/{}/{}",
                        self.api_base,
                        urlencoding::encode(owner),
                        urlencoding::encode(repository)
                    ),
                    token,
                )
                .send()
                .await
                .map_err(|_| SourceError::Transport(self.platform))?;
            ensure_success(self.platform, response.status())?;
            return parse_json_limited::<GitPlatformRepository>(self.platform, response)
                .await
                .map(|repository| vec![repository]);
        }

        let response = self
            .authorized_get(format!("{}/search/repositories", self.api_base), token)
            .query(&[
                ("q", query.to_owned()),
                ("page", "1".to_owned()),
                ("per_page", MAX_GIT_REPOSITORIES.to_string()),
            ])
            .send()
            .await
            .map_err(|_| SourceError::Transport(self.platform))?;
        ensure_success(self.platform, response.status())?;
        parse_json_limited::<GitPlatformSearchResponse>(self.platform, response)
            .await
            .map(GitPlatformSearchResponse::into_repositories)
    }

    async fn repository_candidates(
        &self,
        token: &str,
        repository: GitPlatformRepository,
    ) -> Option<Vec<Candidate>> {
        let full_name = repository.full_name?.trim().to_owned();
        let branch = repository.default_branch?.trim().to_owned();
        let (owner, name) = full_name.rsplit_once('/')?;
        if owner.is_empty() || name.is_empty() || branch.is_empty() {
            return None;
        }
        let response = self
            .authorized_get(
                format!(
                    "{}/repos/{}/{}/git/trees/{}",
                    self.api_base,
                    urlencoding::encode(owner),
                    urlencoding::encode(name),
                    urlencoding::encode(&branch)
                ),
                token,
            )
            .query(&[("recursive", "1")])
            .send()
            .await
            .ok()?;
        if !response.status().is_success() {
            return None;
        }
        let mut files = parse_json_limited::<GitTreeResponse>(self.platform, response)
            .await
            .ok()?
            .tree
            .into_iter()
            .filter(|entry| {
                entry.kind == "blob"
                    && entry
                        .size
                        .is_none_or(|size| size <= MAX_GITHUB_FILE_BYTES as u64)
                    && git_file_priority(&entry.path).is_some()
            })
            .collect::<Vec<_>>();
        files.sort_by_key(|entry| git_file_priority(&entry.path).unwrap_or(u8::MAX));
        files.truncate(MAX_GIT_FILES_PER_REPOSITORY);

        let source = self.clone_for_tasks();
        let token = token.to_owned();
        let artifact_root = repository
            .html_url
            .filter(|value| value.starts_with(self.web_base))
            .unwrap_or_else(|| format!("{}/{}", self.web_base, full_name));
        let batches = stream::iter(files.into_iter().map(|file| {
            let source = source.clone_for_tasks();
            let token = token.clone();
            let owner = owner.to_owned();
            let name = name.to_owned();
            let branch = branch.clone();
            let artifact_root = artifact_root.clone();
            async move {
                source
                    .file_candidates(&token, &owner, &name, &branch, &artifact_root, file)
                    .await
            }
        }))
        .buffer_unordered(GIT_CONTENT_CONCURRENCY);
        futures::pin_mut!(batches);
        let mut candidates = Vec::new();
        while let Some(batch) = batches.next().await {
            candidates.extend(batch.unwrap_or_default());
            if candidates.len() >= MAX_SOURCE_RESULTS {
                candidates.truncate(MAX_SOURCE_RESULTS);
                break;
            }
        }
        Some(candidates)
    }

    #[allow(clippy::too_many_arguments)]
    async fn file_candidates(
        &self,
        token: &str,
        owner: &str,
        repository: &str,
        branch: &str,
        artifact_root: &str,
        file: GitTreeEntry,
    ) -> Option<Vec<Candidate>> {
        let response = self
            .authorized_get(
                format!(
                    "{}/repos/{}/{}/git/blobs/{}",
                    self.api_base,
                    urlencoding::encode(owner),
                    urlencoding::encode(repository),
                    urlencoding::encode(&file.sha)
                ),
                token,
            )
            .send()
            .await
            .ok()?;
        if !response.status().is_success() {
            return None;
        }
        let content = parse_json_limited::<GithubContentResponse>(self.platform, response)
            .await
            .ok()?;
        let encoded = content.content?.replace(['\r', '\n'], "");
        let decoded = match content.encoding.as_deref() {
            Some("base64") | None => STANDARD.decode(encoded).ok()?,
            _ => return None,
        };
        if decoded.len() > MAX_GITHUB_FILE_BYTES {
            return None;
        }
        let text = String::from_utf8_lossy(&decoded);
        let artifact_url = format!(
            "{}/blob/{}/{}",
            artifact_root.trim_end_matches(".git").trim_end_matches('/'),
            encode_path(branch),
            encode_path(&file.path)
        );
        Some(
            URL_PATTERN
                .find_iter(&text)
                .take(50)
                .map(|url| Candidate {
                    source: self.kind,
                    target: trim_url_punctuation(url.as_str()),
                    discovered_at: Utc::now(),
                    metadata: BTreeMap::from([
                        (CANDIDATE_ARTIFACT_URL_KEY.to_owned(), artifact_url.clone()),
                        (
                            CANDIDATE_ARTIFACT_TEXT_KEY.to_owned(),
                            surrounding_text(
                                &text,
                                url.start(),
                                url.end(),
                                MAX_ARTIFACT_CONTEXT_BYTES,
                            ),
                        ),
                    ]),
                })
                .collect(),
        )
    }
}

struct FofaSource {
    client: ObservedHttpClient,
}

impl FofaSource {
    fn new(client: ObservedHttpClient) -> Self {
        Self { client }
    }
}

#[derive(Deserialize)]
struct FofaSearchResponse {
    error: bool,
    errmsg: Option<String>,
    #[serde(default)]
    results: Vec<Vec<serde_json::Value>>,
}

#[derive(Deserialize)]
struct FofaUserResponse {
    error: bool,
    fcoin: Option<u64>,
}

#[async_trait]
impl AssetSource for FofaSource {
    fn kind(&self) -> SourceKind {
        SourceKind::Fofa
    }

    async fn discover(
        &self,
        request: &ScanRequest,
        credentials: &SourceCredentials,
    ) -> Result<Vec<Candidate>, SourceError> {
        let (email, key) = fofa_credentials(credentials)?;
        let query = source_query(request, "fofa").unwrap_or_else(|| default_fofa_query(request));
        let response = self
            .client
            .get("https://fofa.info/api/v1/search/all")
            .query(&[
                ("email", email.expose_secret().to_owned()),
                ("key", key.expose_secret().to_owned()),
                ("qbase64", STANDARD.encode(query)),
                ("size", DEFAULT_PAGE_SIZE.to_string()),
                ("fields", "host,ip,port,protocol".to_owned()),
            ])
            .send()
            .await
            .map_err(|_| SourceError::Transport("FOFA"))?;
        ensure_success("FOFA", response.status())?;
        let body = parse_json_limited::<FofaSearchResponse>("FOFA", response).await?;
        if body.error {
            return Err(SourceError::Other(anyhow::anyhow!(
                "FOFA 查询失败：{}",
                body.errmsg.unwrap_or_else(|| "未知错误".to_owned())
            )));
        }
        Ok(body
            .results
            .into_iter()
            .filter_map(|row| row.first().and_then(value_as_string))
            .take(MAX_SOURCE_RESULTS)
            .map(|target| Candidate {
                source: SourceKind::Fofa,
                target,
                discovered_at: Utc::now(),
                metadata: BTreeMap::new(),
            })
            .collect())
    }

    async fn quota(&self, credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        let (email, key) = fofa_credentials(credentials)?;
        let response = self
            .client
            .get("https://fofa.info/api/v1/info/my")
            .query(&[
                ("email", email.expose_secret()),
                ("key", key.expose_secret()),
            ])
            .send()
            .await
            .map_err(|_| SourceError::Transport("FOFA"))?;
        ensure_success("FOFA", response.status())?;
        let body = parse_json_limited::<FofaUserResponse>("FOFA", response).await?;
        if body.error {
            return Err(SourceError::InvalidResponse("FOFA"));
        }
        Ok(SourceQuota {
            source: SourceKind::Fofa,
            configured: true,
            available: true,
            remaining: body.fcoin,
            limit: None,
            resets_at: None,
            message: "FOFA 账户可用。".to_owned(),
        })
    }
}

struct ShodanSource {
    client: ObservedHttpClient,
}

impl ShodanSource {
    fn new(client: ObservedHttpClient) -> Self {
        Self { client }
    }
}

#[derive(Deserialize)]
struct ShodanSearchResponse {
    matches: Vec<ShodanMatch>,
}

#[derive(Deserialize)]
struct ShodanMatch {
    ip_str: String,
    port: u16,
    transport: Option<String>,
    hostnames: Option<Vec<String>>,
    ssl: Option<serde_json::Value>,
}

#[derive(Deserialize)]
struct ShodanAccountResponse {
    query_credits: Option<u64>,
    scan_credits: Option<u64>,
}

#[async_trait]
impl AssetSource for ShodanSource {
    fn kind(&self) -> SourceKind {
        SourceKind::Shodan
    }

    async fn discover(
        &self,
        request: &ScanRequest,
        credentials: &SourceCredentials,
    ) -> Result<Vec<Candidate>, SourceError> {
        let key = credentials
            .shodan_key
            .as_ref()
            .ok_or(SourceError::MissingCredential("Shodan"))?;
        let query =
            source_query(request, "shodan").unwrap_or_else(|| default_shodan_query(request));
        let response = self
            .client
            .get("https://api.shodan.io/shodan/host/search")
            .query(&[("key", key.expose_secret()), ("query", query.as_str())])
            .send()
            .await
            .map_err(|_| SourceError::Transport("Shodan"))?;
        ensure_success("Shodan", response.status())?;
        let body = parse_json_limited::<ShodanSearchResponse>("Shodan", response).await?;
        Ok(body
            .matches
            .into_iter()
            .flat_map(|item| {
                let scheme = if item.ssl.is_some() || matches!(item.port, 443 | 8443 | 9443) {
                    "https"
                } else {
                    "http"
                };
                let transport = item.transport.unwrap_or_else(|| "tcp".to_owned());
                let mut hosts = vec![item.ip_str];
                hosts.extend(item.hostnames.unwrap_or_default().into_iter().take(5));
                hosts.sort();
                hosts.dedup();
                hosts.into_iter().map(move |host| Candidate {
                    source: SourceKind::Shodan,
                    target: format!("{scheme}://{host}:{}", item.port),
                    discovered_at: Utc::now(),
                    metadata: BTreeMap::from([("transport".to_owned(), transport.clone())]),
                })
            })
            .take(MAX_SOURCE_RESULTS)
            .collect())
    }

    async fn quota(&self, credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        let key = credentials
            .shodan_key
            .as_ref()
            .ok_or(SourceError::MissingCredential("Shodan"))?;
        let response = self
            .client
            .get("https://api.shodan.io/api-info")
            .query(&[("key", key.expose_secret())])
            .send()
            .await
            .map_err(|_| SourceError::Transport("Shodan"))?;
        ensure_success("Shodan", response.status())?;
        let body = parse_json_limited::<ShodanAccountResponse>("Shodan", response).await?;
        Ok(SourceQuota {
            source: SourceKind::Shodan,
            configured: true,
            available: true,
            remaining: body.query_credits,
            limit: None,
            resets_at: None,
            message: format!(
                "Shodan 查询额度可用，扫描额度 {}。",
                body.scan_credits
                    .map_or_else(|| "未知".to_owned(), |value| value.to_string())
            ),
        })
    }
}

async fn github_item_candidates(
    client: ObservedHttpClient,
    kind: SourceKind,
    token: String,
    item: GithubCodeItem,
) -> Option<Vec<Candidate>> {
    let response = client
        .get(&item.url)
        .header("Accept", "application/vnd.github+json")
        .header("X-GitHub-Api-Version", "2022-11-28")
        .bearer_auth(token)
        .send()
        .await
        .ok()?;
    if !response.status().is_success() {
        return None;
    }
    let content = parse_json_limited::<GithubContentResponse>("GitHub", response)
        .await
        .ok()?;
    let decoded = match (content.encoding.as_deref(), content.content.as_deref()) {
        (Some("base64"), Some(value)) => STANDARD.decode(value.replace('\n', "")).ok()?,
        _ => return None,
    };
    if decoded.len() > MAX_GITHUB_FILE_BYTES {
        return None;
    }
    let text = String::from_utf8_lossy(&decoded);
    Some(
        URL_PATTERN
            .find_iter(&text)
            .take(50)
            .map(|url| {
                let mut metadata = BTreeMap::from([(
                    CANDIDATE_ARTIFACT_URL_KEY.to_owned(),
                    item.html_url.clone(),
                )]);
                if kind == SourceKind::GithubArtifact {
                    metadata.insert(
                        CANDIDATE_ARTIFACT_TEXT_KEY.to_owned(),
                        surrounding_text(&text, url.start(), url.end(), MAX_ARTIFACT_CONTEXT_BYTES),
                    );
                }
                Candidate {
                    source: kind,
                    target: trim_url_punctuation(url.as_str()),
                    discovered_at: Utc::now(),
                    metadata,
                }
            })
            .collect(),
    )
}

async fn parse_json_limited<T: DeserializeOwned>(
    platform: &'static str,
    response: Response,
) -> Result<T, SourceError> {
    if response
        .content_length()
        .is_some_and(|length| length > MAX_SOURCE_RESPONSE_BYTES as u64)
    {
        return Err(SourceError::ResponseTooLarge {
            platform,
            limit: MAX_SOURCE_RESPONSE_BYTES,
        });
    }
    let mut body = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|_| SourceError::Transport(platform))?;
        if body.len().saturating_add(chunk.len()) > MAX_SOURCE_RESPONSE_BYTES {
            return Err(SourceError::ResponseTooLarge {
                platform,
                limit: MAX_SOURCE_RESPONSE_BYTES,
            });
        }
        body.extend_from_slice(&chunk);
    }
    serde_json::from_slice(&body).map_err(|_| SourceError::InvalidResponse(platform))
}

fn source_query(request: &ScanRequest, key: &str) -> Option<String> {
    request
        .source_queries
        .get(key)
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn default_repository_query(request: &ScanRequest) -> String {
    request
        .authorized_scope
        .first()
        .map(|value| value.trim().trim_start_matches("*.").to_owned())
        .filter(|value| !value.is_empty())
        .or_else(|| request.vendors.first().cloned())
        .unwrap_or_else(|| "AI".to_owned())
}

fn direct_repository(query: &str) -> Option<(&str, &str)> {
    let value = query.trim();
    if value.contains(char::is_whitespace) || value.contains("://") {
        return None;
    }
    let (owner, repository) = value.rsplit_once('/')?;
    if owner.is_empty()
        || repository.is_empty()
        || owner.parse::<IpAddr>().is_ok()
        || !owner
            .split('/')
            .chain(std::iter::once(repository))
            .all(|segment| {
                !segment.is_empty()
                    && segment.chars().all(|character| {
                        character.is_ascii_alphanumeric() || "._-".contains(character)
                    })
            })
    {
        return None;
    }
    Some((owner, repository))
}

fn git_file_priority(path: &str) -> Option<u8> {
    let lowered = path.to_ascii_lowercase();
    if lowered.split('/').any(|segment| {
        matches!(
            segment,
            ".git" | "node_modules" | "vendor" | "target" | "build" | "dist" | "coverage"
        )
    }) {
        return None;
    }
    let name = lowered.rsplit('/').next().unwrap_or_default();
    if name == ".env"
        || name.starts_with(".env.")
        || lowered.contains("secret")
        || lowered.contains("credential")
        || lowered.contains("application.")
        || lowered.contains("config")
    {
        return Some(0);
    }
    let extension = name.rsplit_once('.').map(|(_, extension)| extension);
    if matches!(
        extension,
        Some("yaml" | "yml" | "json" | "toml" | "ini" | "conf" | "properties" | "xml")
    ) {
        return Some(1);
    }
    if matches!(extension, Some("md" | "txt" | "rst")) {
        return Some(2);
    }
    if matches!(
        extension,
        Some(
            "c" | "cc"
                | "cpp"
                | "cs"
                | "dart"
                | "go"
                | "h"
                | "hpp"
                | "java"
                | "js"
                | "jsx"
                | "kt"
                | "kts"
                | "m"
                | "mm"
                | "php"
                | "ps1"
                | "py"
                | "rb"
                | "rs"
                | "sh"
                | "swift"
                | "ts"
                | "tsx"
        )
    ) || matches!(name, "dockerfile" | "makefile")
    {
        return Some(3);
    }
    None
}

fn encode_path(value: &str) -> String {
    value
        .split('/')
        .map(|segment| urlencoding::encode(segment))
        .collect::<Vec<_>>()
        .join("/")
}

fn default_github_query(request: &ScanRequest) -> String {
    let scope = request
        .authorized_scope
        .first()
        .cloned()
        .unwrap_or_default();
    format!("\"{scope}\" (api_key OR authorization OR /v1/models)")
}

fn default_fofa_query(request: &ScanRequest) -> String {
    request
        .authorized_scope
        .iter()
        .map(|scope| {
            if scope.parse::<IpAddr>().is_ok() || scope.contains('/') {
                format!("ip=\"{scope}\"")
            } else {
                format!("domain=\"{scope}\"")
            }
        })
        .collect::<Vec<_>>()
        .join(" || ")
}

fn default_shodan_query(request: &ScanRequest) -> String {
    request
        .authorized_scope
        .iter()
        .map(|scope| {
            if scope.parse::<IpAddr>().is_ok() || scope.contains('/') {
                format!("net:{scope}")
            } else {
                format!("hostname:{scope}")
            }
        })
        .collect::<Vec<_>>()
        .join(" OR ")
}

fn fofa_credentials(
    credentials: &SourceCredentials,
) -> Result<(&SecretString, &SecretString), SourceError> {
    Ok((
        credentials
            .fofa_email
            .as_ref()
            .ok_or(SourceError::MissingCredential("FOFA"))?,
        credentials
            .fofa_key
            .as_ref()
            .ok_or(SourceError::MissingCredential("FOFA"))?,
    ))
}

fn ensure_success(source: &'static str, status: StatusCode) -> Result<(), SourceError> {
    if status.is_success() {
        Ok(())
    } else {
        Err(SourceError::Http {
            platform: source,
            status: status.as_u16(),
        })
    }
}

fn value_as_string(value: &serde_json::Value) -> Option<String> {
    value.as_str().map(ToOwned::to_owned)
}

fn trim_url_punctuation(value: &str) -> String {
    value
        .trim_end_matches([')', ']', '}', ',', ';', '.'])
        .to_owned()
}

fn surrounding_text(value: &str, match_start: usize, match_end: usize, max_bytes: usize) -> String {
    if value.len() <= max_bytes {
        return value.to_owned();
    }
    let match_length = match_end.saturating_sub(match_start).min(max_bytes);
    let before = (max_bytes - match_length) / 2;
    let mut start = match_start.saturating_sub(before);
    while !value.is_char_boundary(start) {
        start += 1;
    }
    let mut end = start.saturating_add(max_bytes).min(value.len());
    while !value.is_char_boundary(end) {
        end -= 1;
    }
    if end < match_end {
        end = match_end.min(value.len());
        while !value.is_char_boundary(end) {
            end -= 1;
        }
        start = end.saturating_sub(max_bytes);
        while !value.is_char_boundary(start) {
            start += 1;
        }
    }
    value[start..end].to_owned()
}

fn unlimited_quota(source: SourceKind, message: &str) -> SourceQuota {
    SourceQuota {
        source,
        configured: true,
        available: true,
        remaining: None,
        limit: None,
        resets_at: None,
        message: message.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct CompletionObserver {
        outcomes: std::sync::Mutex<Vec<HttpRequestOutcome>>,
    }

    impl HttpRequestObserver for CompletionObserver {
        fn begin(&self, _target: &reqwest::Url) -> reqwest::Result<Option<HttpRequestObservation>> {
            unreachable!()
        }

        fn complete(&self, _ticket: Option<u64>, _elapsed: Duration, outcome: HttpRequestOutcome) {
            self.outcomes.lock().unwrap().push(outcome);
        }
    }

    #[test]
    fn accepts_fofa_error_without_results() {
        let response: FofaSearchResponse =
            serde_json::from_str(r#"{"error":true,"errmsg":"额度不足"}"#).unwrap();
        assert!(response.error);
        assert!(response.results.is_empty());
    }

    #[test]
    fn transport_error_does_not_include_request_url() {
        assert_eq!(
            SourceError::Transport("FOFA").to_string(),
            "FOFA 网络请求失败。"
        );
    }

    #[test]
    fn cancelled_request_completes_observation() {
        let observer = Arc::new(CompletionObserver::default());
        let completion = HttpRequestCompletion::new(observer.clone(), Some(1));
        drop(completion);
        let outcomes = observer.outcomes.lock().unwrap();
        assert_eq!(outcomes.len(), 1);
        assert!(matches!(outcomes[0], HttpRequestOutcome::TransportFailure));
    }

    #[test]
    fn bounds_artifact_context_and_keeps_match() {
        let prefix = "前".repeat(20_000);
        let url = "https://api.example.com/v1";
        let text = format!("{prefix}{url}{}", "后".repeat(20_000));
        let start = text.find(url).unwrap();
        let context = surrounding_text(&text, start, start + url.len(), 16 * 1024);
        assert!(context.len() <= 16 * 1024);
        assert!(context.contains(url));
    }

    #[test]
    fn recognizes_direct_repository_and_prioritizes_configuration() {
        assert_eq!(direct_repository("team/project"), Some(("team", "project")));
        assert_eq!(direct_repository("10.10.0.0/16"), None);
        assert_eq!(git_file_priority("deploy/.env.production"), Some(0));
        assert_eq!(git_file_priority("src/main.rs"), Some(3));
        assert_eq!(git_file_priority("node_modules/pkg/index.js"), None);
    }

    #[test]
    fn accepts_git_platform_repository_response_shapes() {
        let list: GitPlatformSearchResponse =
            serde_json::from_str(r#"[{"full_name":"team/project","default_branch":"main"}]"#)
                .unwrap();
        let wrapped: GitPlatformSearchResponse = serde_json::from_str(
            r#"{"items":[{"full_name":"team/project","default_branch":"main"}]}"#,
        )
        .unwrap();
        assert_eq!(list.into_repositories().len(), 1);
        assert_eq!(wrapped.into_repositories().len(), 1);
    }
}
