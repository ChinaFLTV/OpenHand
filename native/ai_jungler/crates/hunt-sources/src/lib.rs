use async_trait::async_trait;
use base64::{Engine, engine::general_purpose::STANDARD};
use chrono::Utc;
use futures::{SinkExt, StreamExt, stream};
use hunt_core::{
    CANDIDATE_ARTIFACT_TEXT_KEY, CANDIDATE_ARTIFACT_URL_KEY, Candidate, ForumFetchMode, ScanMode,
    ScanRequest, SourceKind, SourceQuota,
};
use regex::Regex;
use reqwest::{Client, IntoUrl, Response, StatusCode, Url};
use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::{
    collections::{BTreeMap, BTreeSet},
    fmt,
    net::IpAddr,
    path::{Path, PathBuf},
    process::Stdio,
    sync::{
        Arc, LazyLock, Mutex, Once, RwLock,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use thiserror::Error;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    process::{Child, Command},
    sync::{Mutex as AsyncMutex, Semaphore},
    task::JoinHandle,
    time::{sleep, timeout},
};
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream, connect_async, tungstenite::Message};

const MAX_SOURCE_RESULTS: usize = 1_000;
const DEFAULT_PAGE_SIZE: usize = 100;
// 单个数据源的分页上限与页间延时：与 MAX_SOURCE_RESULTS 共同构成双重上界，
// 页间短暂延时以尊重外部配额/限速，杜绝无限翻页与无节制请求。
const MAX_DISCOVERY_PAGES: usize = 5;
const DISCOVERY_PAGE_DELAY: Duration = Duration::from_millis(300);
const MAX_SOURCE_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const MAX_GITHUB_FILE_BYTES: usize = 512 * 1024;
const MAX_ARTIFACT_CONTEXT_BYTES: usize = 16 * 1024;
const GITHUB_CONTENT_CONCURRENCY: usize = 6;
// 分页累积的 GitHub 公开检索项上限，约束后续逐项内容拉取对 GitHub API 的用量。
const MAX_GITHUB_SEARCH_RESULTS: usize = 300;
// 单个数据源解析的最大凭证数量，封顶多 key 轮询/故障转移的每页请求次数，防资源滥用。
const MAX_CREDENTIAL_KEYS: usize = 32;
const MAX_GIT_REPOSITORIES: usize = 5;
const MAX_GIT_FILES_PER_REPOSITORY: usize = 8;
const GIT_REPOSITORY_CONCURRENCY: usize = 3;
const GIT_CONTENT_CONCURRENCY: usize = 4;
const MAX_FORUM_TOPICS: usize = 5;
const FORUM_TOPIC_CONCURRENCY: usize = 3;
const JINA_READER_PRIMARY_TIMEOUT: Duration = Duration::from_secs(35);
const JINA_READER_FALLBACK_TIMEOUT: Duration = Duration::from_secs(35);
const JINA_READER_SERVER_TIMEOUT_SECONDS: &str = "25";
const JINA_READER_MAX_ATTEMPTS: u8 = 2;
const JINA_READER_RETRY_DELAY: Duration = Duration::from_millis(800);
const JINA_READER_ENDPOINT: &str = "https://r.jina.ai/";
const JINA_HEADER_OPTIONS: [(&str, &str); 42] = [
    ("engine", "X-Engine"),
    ("returnFormat", "X-Return-Format"),
    ("respondWith", "X-Respond-With"),
    ("timeout", "X-Timeout"),
    ("tokenBudget", "X-Token-Budget"),
    ("maxTokens", "X-Max-Tokens"),
    ("targetSelector", "X-Target-Selector"),
    ("waitForSelector", "X-Wait-For-Selector"),
    ("removeSelector", "X-Remove-Selector"),
    ("retainImages", "X-Retain-Images"),
    ("retainMedia", "X-Retain-Media"),
    ("retainLinks", "X-Retain-Links"),
    ("withLinksSummary", "X-With-Links-Summary"),
    ("withImagesSummary", "X-With-Images-Summary"),
    ("withGeneratedAlt", "X-With-Generated-Alt"),
    ("proxyUrl", "X-Proxy-Url"),
    ("proxy", "X-Proxy"),
    ("noCache", "X-No-Cache"),
    ("cacheTolerance", "X-Cache-Tolerance"),
    ("respondTiming", "X-Respond-Timing"),
    ("userAgent", "X-User-Agent"),
    ("referer", "X-Referer"),
    ("keepImgDataUrl", "X-Keep-Img-Data-Url"),
    ("dnt", "DNT"),
    ("noGfm", "X-No-Gfm"),
    ("locale", "X-Locale"),
    ("robotsTxt", "X-Robots-Txt"),
    ("withIframe", "X-With-Iframe"),
    ("withShadowDom", "X-With-Shadow-Dom"),
    ("base", "X-Base"),
    ("preset", "X-Preset"),
    ("removeOverlay", "X-Remove-Overlay"),
    ("detachInvisibles", "X-Detach-Invisibles"),
    ("markdownChunking", "X-Markdown-Chunking"),
    ("assertStatusCode", "X-Assert-Status-Code"),
    ("page", "X-Page"),
    ("preloadUrl", "X-Preload-Url"),
    ("noServiceWorker", "X-No-Service-Worker"),
    ("exportStorageState", "X-Export-Storage-State"),
    ("mdHeadingStyle", "X-Md-Heading-Style"),
    ("mdHr", "X-Md-Hr"),
    ("mdBulletListMarker", "X-Md-Bullet-List-Marker"),
];
const JINA_MARKDOWN_HEADER_OPTIONS: [(&str, &str); 4] = [
    ("mdEmDelimiter", "X-Md-Em-Delimiter"),
    ("mdStrongDelimiter", "X-Md-Strong-Delimiter"),
    ("mdLinkStyle", "X-Md-Link-Style"),
    ("mdLinkReferenceStyle", "X-Md-Link-Reference-Style"),
];
const MAX_BROWSER_CONCURRENCY: usize = 2;
const BROWSER_PROCESS_TIMEOUT: Duration = Duration::from_secs(25);
const MAX_BROWSER_OUTPUT_BYTES: usize = 2 * 1024 * 1024;
const MAX_CDP_CONCURRENCY: usize = 1;
const CDP_BROWSER_START_TIMEOUT: Duration = Duration::from_secs(20);
const CDP_PAGE_TIMEOUT: Duration = Duration::from_secs(35);
const CDP_COMMAND_TIMEOUT: Duration = Duration::from_secs(6);
const CDP_IDLE_DELAY: Duration = Duration::from_millis(1200);
const CDP_CHALLENGE_DELAY: Duration = Duration::from_secs(2);

pub fn ensure_rustls_crypto_provider() {
    static INITIALIZE: Once = Once::new();
    INITIALIZE.call_once(|| {
        if rustls::crypto::CryptoProvider::get_default().is_none() {
            let _ = rustls::crypto::ring::default_provider().install_default();
        }
    });
}
const CDP_PROCESS_STOP_TIMEOUT: Duration = Duration::from_secs(3);
const CDP_HTTP_TIMEOUT: Duration = Duration::from_secs(3);
const CDP_START_POLL_DELAY: Duration = Duration::from_millis(150);
const MAX_CDP_REQUESTS: usize = 160;
const MAX_CDP_RESPONSES: usize = 48;
const MAX_CDP_RESPONSE_BODIES: usize = 24;
const MAX_CDP_BODY_BYTES: usize = 512 * 1024;
const MAX_CDP_EVENT_BYTES: usize = 2 * 1024 * 1024;
const MAX_CDP_STDERR_BYTES: usize = 32 * 1024;
const MAX_CDP_FIELD_BYTES: usize = 16 * 1024;
const MAX_CDP_REQUEST_CAPTURE_BYTES: usize = 256 * 1024;
static CDP_PROFILE_SEQUENCE: AtomicU64 = AtomicU64::new(1);
static URL_PATTERN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"https?://[^\s\"'<>\\，。；：！？、（）【】]{4,2048}"#)
        .expect("内置 URL 正则必须有效")
});
static NODESEEK_TOPIC_PATTERN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^/post-\d+-\d+(?:\.html)?/?$").expect("NodeSeek 主题正则必须有效")
});
static LINUX_DO_TOPIC_PATTERN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^/t/topic/\d+(?:/\d+)?/?$").expect("LINUX DO 主题正则必须有效"));
static V2EX_TOPIC_PATTERN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^/t/\d+/?$").expect("V2EX 主题正则必须有效"));

const PLAYWRIGHT_READER_SCRIPT: &str = r#"
const fs = require('fs');

(async () => {
  let browser;
  try {
    const input = JSON.parse(fs.readFileSync(0, 'utf8'));
    const { chromium } = require(input.packageDirectory);
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({
      ignoreHTTPSErrors: false,
      locale: 'zh-CN',
      proxy: input.proxy || undefined,
      serviceWorkers: 'block',
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/136.0.0.0 Safari/537.36',
    });
    const page = await context.newPage();
    const targetUrl = new URL(input.url);
    await page.route('**/*', route => {
      const request = route.request();
      const resourceUrl = new URL(request.url());
      const type = request.resourceType();
      const expendable = ['font', 'image', 'media', 'stylesheet'].includes(type);
      const trustedAsset = targetUrl.hostname.endsWith('linux.do')
        && (resourceUrl.hostname === 'ldstatic.com' || resourceUrl.hostname.endsWith('.ldstatic.com'));
      const unrelated = resourceUrl.origin !== targetUrl.origin
        && resourceUrl.hostname !== 'challenges.cloudflare.com'
        && !trustedAsset
        && !request.isNavigationRequest();
      return expendable || unrelated ? route.abort() : route.continue();
    });
    const response = await page.goto(input.url, {
      timeout: 18000,
      waitUntil: 'domcontentloaded',
    });
    await page.waitForTimeout(700);
    const title = await page.title();
    const data = await page.evaluate(() => ({
      links: Array.from(document.querySelectorAll('a[href]'), link => link.href).slice(0, 600),
      text: (document.body?.innerText || document.documentElement?.innerText || '').slice(0, 300000),
    }));
    const challenge = `${title}\n${data.text}`.toLowerCase();
    if (challenge.includes('just a moment') || challenge.includes('enable javascript and cookies')) {
      throw new Error('站点安全验证未通过');
    }
    process.stdout.write(JSON.stringify({
      ok: true,
      status: response ? response.status() : 200,
      text: data.text,
      links: data.links,
    }));
  } catch (error) {
    process.stdout.write(JSON.stringify({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }));
    process.exitCode = 1;
  } finally {
    if (browser) await browser.close().catch(() => {});
  }
})();
"#;

#[derive(Clone, Copy, Debug)]
pub enum HttpRequestOutcome {
    Success(u16),
    Failure(u16),
    Timeout,
    TransportFailure,
}

pub struct HttpRequestObservation {
    pub ticket: Option<u64>,
    pub client: Client,
}

pub struct ExternalHttpRequestRoute {
    pub ticket: Option<u64>,
    pub proxy: Option<Url>,
}

pub trait HttpRequestObserver: Send + Sync {
    fn begin(&self, target: &reqwest::Url) -> reqwest::Result<Option<HttpRequestObservation>>;
    fn begin_request(
        &self,
        request: &reqwest::Request,
    ) -> reqwest::Result<Option<HttpRequestObservation>> {
        self.begin(request.url())
    }
    fn begin_external(&self, _target: &reqwest::Url) -> reqwest::Result<ExternalHttpRequestRoute> {
        Ok(ExternalHttpRequestRoute {
            ticket: None,
            proxy: None,
        })
    }
    fn begin_fallback(
        &self,
        _request: &reqwest::Request,
    ) -> reqwest::Result<Option<HttpRequestObservation>> {
        Ok(None)
    }
    fn begin_external_fallback(
        &self,
        _target: &reqwest::Url,
    ) -> reqwest::Result<ExternalHttpRequestRoute> {
        Ok(ExternalHttpRequestRoute {
            ticket: None,
            proxy: None,
        })
    }
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

    pub fn begin_external(
        &self,
        target: &Url,
        prefer_fallback: bool,
    ) -> reqwest::Result<ObservedExternalRequest> {
        let route = if prefer_fallback {
            self.observer.begin_external_fallback(target)?
        } else {
            self.observer.begin_external(target)?
        };
        Ok(ObservedExternalRequest {
            observer: self.observer.clone(),
            ticket: route.ticket,
            proxy: route.proxy,
            started: Instant::now(),
        })
    }
}

pub struct ObservedExternalRequest {
    observer: Arc<dyn HttpRequestObserver>,
    ticket: Option<u64>,
    proxy: Option<Url>,
    started: Instant,
}

impl ObservedExternalRequest {
    pub fn proxy(&self) -> Option<&Url> {
        self.proxy.as_ref()
    }

    pub fn complete(mut self, outcome: HttpRequestOutcome) {
        let ticket = self.ticket.take();
        self.observer
            .complete(ticket, self.started.elapsed(), outcome);
    }
}

impl Drop for ObservedExternalRequest {
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

pub struct ObservedRequestBuilder {
    client: ObservedHttpClient,
    request: reqwest::RequestBuilder,
    prefer_fallback: bool,
    automatic_fallback: bool,
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

fn request_outcome(response: &reqwest::Result<Response>) -> HttpRequestOutcome {
    match response {
        Ok(response) if response.status().is_success() || response.status().is_redirection() => {
            HttpRequestOutcome::Success(response.status().as_u16())
        }
        Ok(response) => HttpRequestOutcome::Failure(response.status().as_u16()),
        Err(error) if error.is_timeout() => HttpRequestOutcome::Timeout,
        Err(_) => HttpRequestOutcome::TransportFailure,
    }
}

impl ObservedRequestBuilder {
    fn new(client: ObservedHttpClient, request: reqwest::RequestBuilder) -> Self {
        Self {
            client,
            request,
            prefer_fallback: false,
            automatic_fallback: true,
        }
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

    pub fn timeout(self, duration: Duration) -> Self {
        Self {
            request: self.request.timeout(duration),
            ..self
        }
    }

    pub fn prefer_fallback(mut self, value: bool) -> Self {
        self.prefer_fallback = value;
        self
    }

    pub fn automatic_fallback(mut self, value: bool) -> Self {
        self.automatic_fallback = value;
        self
    }

    pub async fn send(self) -> reqwest::Result<Response> {
        let request = self.request.build()?;
        let observation = if self.prefer_fallback {
            self.client.observer.begin_fallback(&request)?
        } else {
            self.client.observer.begin_request(&request)?
        };
        let ticket = observation.as_ref().and_then(|value| value.ticket);
        let client = observation
            .map(|value| value.client)
            .unwrap_or_else(|| self.client.client.clone());
        let fallback_request = (self.automatic_fallback
            && !self.prefer_fallback
            && ticket.is_some()
            && (request.method() == reqwest::Method::GET
                || request.method() == reqwest::Method::HEAD))
            .then(|| request.try_clone())
            .flatten();
        let completion = HttpRequestCompletion::new(self.client.observer.clone(), ticket);
        let mut response = client.execute(request).await;
        completion.complete(request_outcome(&response));
        if response.is_err()
            && let Some(request) = fallback_request
        {
            let observation = self.client.observer.begin_fallback(&request)?;
            let ticket = observation.as_ref().and_then(|value| value.ticket);
            let client = observation
                .map(|value| value.client)
                .unwrap_or_else(|| self.client.client.clone());
            let completion = HttpRequestCompletion::new(self.client.observer.clone(), ticket);
            response = client.execute(request).await;
            completion.complete(request_outcome(&response));
        }
        response
    }
}

const MAX_TOOL_PROFILES: usize = 32;

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd)]
#[serde(rename_all = "snake_case")]
pub enum SourceToolKind {
    Github,
    Gitee,
    Gitcode,
    Fofa,
    Shodan,
    Jina,
}

impl SourceToolKind {
    fn platform(self) -> &'static str {
        match self {
            Self::Github => "GitHub",
            Self::Gitee => "Gitee",
            Self::Gitcode => "GitCode",
            Self::Fofa => "FOFA",
            Self::Shodan => "Shodan",
            Self::Jina => "Jina Reader",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolSelectionStrategy {
    #[default]
    RoundRobin,
    Random,
    LeastUsed,
    LeastBusy,
    HighestSuccessRate,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolProfileInput {
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub values: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolConfigurationInput {
    pub tool: SourceToolKind,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub strategy: ToolSelectionStrategy,
    #[serde(default)]
    pub profiles: Vec<ToolProfileInput>,
}

fn default_true() -> bool {
    true
}

#[derive(Clone)]
pub struct ToolProfile {
    id: String,
    values: BTreeMap<String, SecretString>,
}

impl ToolProfile {
    pub fn value(&self, key: &str) -> Option<&str> {
        self.values.get(key).map(|value| value.expose_secret())
    }

    fn has_required_values(&self, tool: SourceToolKind) -> bool {
        let has = |key| {
            self.value(key)
                .is_some_and(|value| !value.trim().is_empty())
        };
        match tool {
            SourceToolKind::Github | SourceToolKind::Gitee | SourceToolKind::Gitcode => {
                has("token")
            }
            SourceToolKind::Fofa => has("email") && has("key"),
            SourceToolKind::Shodan => has("key"),
            SourceToolKind::Jina => true,
        }
    }
}

#[derive(Clone)]
struct ToolConfiguration {
    enabled: bool,
    strategy: ToolSelectionStrategy,
    profiles: Vec<ToolProfile>,
}

#[derive(Clone, Default)]
struct ToolProfileStatistics {
    requests: u64,
    successes: u64,
    failures: u64,
    in_flight: u64,
    last_used: u64,
}

#[derive(Default)]
struct ToolRuntimeState {
    cursor: usize,
    sequence: u64,
    profiles: BTreeMap<String, ToolProfileStatistics>,
}

#[derive(Clone)]
pub struct SourceCredentials {
    configurations: BTreeMap<SourceToolKind, ToolConfiguration>,
    runtime: Arc<Mutex<BTreeMap<SourceToolKind, ToolRuntimeState>>>,
    active_profile: Option<ToolProfile>,
}

impl Default for SourceCredentials {
    fn default() -> Self {
        Self::from_configurations(vec![ToolConfigurationInput {
            tool: SourceToolKind::Jina,
            enabled: true,
            strategy: ToolSelectionStrategy::RoundRobin,
            profiles: vec![ToolProfileInput {
                id: "jina-default".to_owned(),
                name: "默认配置".to_owned(),
                enabled: true,
                values: BTreeMap::new(),
            }],
        }])
    }
}

impl SourceCredentials {
    pub fn from_configurations(inputs: Vec<ToolConfigurationInput>) -> Self {
        let mut configurations = BTreeMap::new();
        for input in inputs {
            if configurations.contains_key(&input.tool) {
                continue;
            }
            let mut seen = BTreeSet::new();
            let profiles = input
                .profiles
                .into_iter()
                .filter(|profile| profile.enabled)
                .filter_map(|profile| {
                    let id = profile.id.trim();
                    if id.is_empty() || !seen.insert(id.to_owned()) {
                        return None;
                    }
                    let values = profile
                        .values
                        .into_iter()
                        .filter_map(|(key, value)| {
                            let key = key.trim();
                            let value = value.trim();
                            (!key.is_empty() && !value.is_empty())
                                .then(|| (key.to_owned(), SecretString::from(value.to_owned())))
                        })
                        .collect();
                    Some(ToolProfile {
                        id: id.to_owned(),
                        values,
                    })
                })
                .take(MAX_TOOL_PROFILES)
                .collect();
            configurations.insert(
                input.tool,
                ToolConfiguration {
                    enabled: input.enabled,
                    strategy: input.strategy,
                    profiles,
                },
            );
        }
        Self {
            configurations,
            runtime: Arc::new(Mutex::new(BTreeMap::new())),
            active_profile: None,
        }
    }

    pub fn set_legacy_profile(&mut self, tool: SourceToolKind, values: BTreeMap<String, String>) {
        let values = values
            .into_iter()
            .filter_map(|(key, value)| {
                let value = value.trim();
                (!value.is_empty()).then(|| (key, SecretString::from(value.to_owned())))
            })
            .collect();
        self.configurations.insert(
            tool,
            ToolConfiguration {
                enabled: true,
                strategy: ToolSelectionStrategy::RoundRobin,
                profiles: vec![ToolProfile {
                    id: format!("legacy-{}", tool.platform().to_ascii_lowercase()),
                    values,
                }],
            },
        );
        self.runtime = Arc::new(Mutex::new(BTreeMap::new()));
    }

    pub fn configured(&self, tool: SourceToolKind) -> bool {
        self.configurations.get(&tool).is_some_and(|configuration| {
            configuration.enabled
                && configuration
                    .profiles
                    .iter()
                    .any(|profile| profile.has_required_values(tool))
        })
    }

    fn begin(&self, tool: SourceToolKind) -> Result<ToolProfileSelection, SourceError> {
        let configuration = self
            .configurations
            .get(&tool)
            .filter(|configuration| configuration.enabled)
            .ok_or(SourceError::MissingCredential(tool.platform()))?;
        let eligible = configuration
            .profiles
            .iter()
            .filter(|profile| profile.has_required_values(tool))
            .collect::<Vec<_>>();
        if eligible.is_empty() {
            return Err(SourceError::MissingCredential(tool.platform()));
        }
        let mut runtimes = self
            .runtime
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let runtime = runtimes.entry(tool).or_default();
        let index = match configuration.strategy {
            ToolSelectionStrategy::RoundRobin => runtime.cursor % eligible.len(),
            ToolSelectionStrategy::Random => {
                let nanos = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map_or(0, |duration| duration.as_nanos() as u64);
                ((nanos ^ runtime.sequence.rotate_left(17)) as usize) % eligible.len()
            }
            ToolSelectionStrategy::LeastUsed => eligible
                .iter()
                .enumerate()
                .min_by_key(|(_, profile)| {
                    let statistics = runtime
                        .profiles
                        .get(&profile.id)
                        .cloned()
                        .unwrap_or_default();
                    (statistics.requests, statistics.last_used)
                })
                .map_or(0, |(index, _)| index),
            ToolSelectionStrategy::LeastBusy => eligible
                .iter()
                .enumerate()
                .min_by_key(|(_, profile)| {
                    let statistics = runtime
                        .profiles
                        .get(&profile.id)
                        .cloned()
                        .unwrap_or_default();
                    (
                        statistics.in_flight,
                        statistics.requests,
                        statistics.last_used,
                    )
                })
                .map_or(0, |(index, _)| index),
            ToolSelectionStrategy::HighestSuccessRate => eligible
                .iter()
                .enumerate()
                .max_by(|(_, left), (_, right)| {
                    let left = runtime.profiles.get(&left.id).cloned().unwrap_or_default();
                    let right = runtime.profiles.get(&right.id).cloned().unwrap_or_default();
                    let left_rate = (left.successes + 1) as f64 / (left.requests + 2) as f64;
                    let right_rate = (right.successes + 1) as f64 / (right.requests + 2) as f64;
                    left_rate
                        .total_cmp(&right_rate)
                        .then_with(|| right.requests.cmp(&left.requests))
                })
                .map_or(0, |(index, _)| index),
        };
        runtime.cursor = (index + 1) % eligible.len();
        runtime.sequence = runtime.sequence.wrapping_add(1);
        let profile = eligible[index].clone();
        let statistics = runtime.profiles.entry(profile.id.clone()).or_default();
        statistics.requests = statistics.requests.saturating_add(1);
        statistics.in_flight = statistics.in_flight.saturating_add(1);
        statistics.last_used = runtime.sequence;
        drop(runtimes);
        Ok(ToolProfileSelection {
            tool,
            profile,
            runtime: self.runtime.clone(),
            completed: false,
        })
    }

    fn with_active_profile(&self, profile: ToolProfile) -> Self {
        let mut scoped = self.clone();
        scoped.active_profile = Some(profile);
        scoped
    }

    fn active_profile(&self) -> Result<&ToolProfile, SourceError> {
        self.active_profile
            .as_ref()
            .ok_or(SourceError::Other(anyhow::anyhow!(
                "扫描工具配置选择状态无效"
            )))
    }
}

struct ToolProfileSelection {
    tool: SourceToolKind,
    profile: ToolProfile,
    runtime: Arc<Mutex<BTreeMap<SourceToolKind, ToolRuntimeState>>>,
    completed: bool,
}

impl ToolProfileSelection {
    fn complete(mut self, success: bool) {
        self.record(success);
        self.completed = true;
    }

    fn record(&self, success: bool) {
        let mut runtimes = self
            .runtime
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let statistics = runtimes
            .entry(self.tool)
            .or_default()
            .profiles
            .entry(self.profile.id.clone())
            .or_default();
        statistics.in_flight = statistics.in_flight.saturating_sub(1);
        if success {
            statistics.successes = statistics.successes.saturating_add(1);
        } else {
            statistics.failures = statistics.failures.saturating_add(1);
        }
    }
}

impl Drop for ToolProfileSelection {
    fn drop(&mut self) {
        if !self.completed {
            self.record(false);
        }
    }
}

#[derive(Clone, Debug)]
pub struct BrowserAutomationConfiguration {
    pub node_executable: PathBuf,
    pub package_directory: PathBuf,
    pub browsers_path: Option<PathBuf>,
    pub version: String,
}

#[derive(Clone, Debug)]
pub struct BrowserAutomationStatus {
    pub configured: bool,
    pub available: bool,
    pub message: String,
    pub version: Option<String>,
}

#[derive(Clone, Debug)]
pub struct CdpBrowserConfiguration {
    pub executable: PathBuf,
    pub version: String,
}

#[derive(Clone, Debug)]
pub struct CdpBrowserStatus {
    pub configured: bool,
    pub available: bool,
    pub message: String,
    pub version: Option<String>,
}

#[derive(Clone, Debug)]
pub struct SourceDiscovery {
    pub candidates: Vec<Candidate>,
    pub warnings: Vec<String>,
}

impl SourceDiscovery {
    fn new(candidates: Vec<Candidate>) -> Self {
        Self {
            candidates,
            warnings: Vec::new(),
        }
    }
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
    #[error("论坛入口无效：{0}")]
    InvalidForumEntry(String),
    #[error("{platform} 页面读取失败：Jina Reader {reader}；Playwright {browser}")]
    ForumFetch {
        platform: &'static str,
        reader: String,
        browser: String,
    },
    #[error("Playwright 浏览器通道未就绪。")]
    BrowserUnavailable,
    #[error("Playwright 浏览器读取失败：{0}")]
    Browser(String),
    #[error("未检测到 Google Chrome，CDP 论坛读取通道不可用。")]
    CdpUnavailable,
    #[error("Chrome CDP 页面读取失败：{0}")]
    Cdp(String),
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
    ) -> Result<SourceDiscovery, SourceError>;
    async fn quota(&self, credentials: &SourceCredentials) -> Result<SourceQuota, SourceError>;
}

#[derive(Clone)]
struct BrowserAutomation {
    client: ObservedHttpClient,
    configuration: Arc<RwLock<Option<BrowserAutomationConfiguration>>>,
    slots: Arc<Semaphore>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BrowserReaderInput {
    url: String,
    package_directory: String,
    proxy: Option<BrowserProxyInput>,
}

#[derive(Serialize)]
struct BrowserProxyInput {
    server: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    password: Option<String>,
}

#[derive(Deserialize)]
struct BrowserReaderOutput {
    ok: bool,
    status: Option<u16>,
    #[serde(default)]
    text: String,
    #[serde(default)]
    links: Vec<String>,
    error: Option<String>,
}

impl BrowserAutomation {
    fn new(client: ObservedHttpClient) -> Self {
        Self {
            client,
            configuration: Arc::new(RwLock::new(None)),
            slots: Arc::new(Semaphore::new(MAX_BROWSER_CONCURRENCY)),
        }
    }

    fn configure(
        &self,
        configuration: Option<BrowserAutomationConfiguration>,
    ) -> Result<(), String> {
        if let Some(value) = &configuration {
            validate_browser_path(&value.node_executable, true, "Node.js 可执行文件")?;
            validate_browser_path(&value.package_directory, false, "Playwright 安装目录")?;
            if !value.package_directory.join("package.json").is_file() {
                return Err("Playwright 安装目录缺少 package.json".to_owned());
            }
            if let Some(path) = &value.browsers_path {
                validate_browser_path(path, false, "Playwright 浏览器目录")?;
            }
        }
        *self
            .configuration
            .write()
            .map_err(|_| "Playwright 配置状态不可用".to_owned())? = configuration;
        Ok(())
    }

    fn status(&self) -> BrowserAutomationStatus {
        let configuration = self
            .configuration
            .read()
            .ok()
            .and_then(|value| value.clone());
        match configuration {
            Some(value) => BrowserAutomationStatus {
                configured: true,
                available: true,
                message: if value.version.trim().is_empty() {
                    "Playwright 浏览器通道已就绪。".to_owned()
                } else {
                    format!("Playwright {} 浏览器通道已就绪。", value.version.trim())
                },
                version: (!value.version.trim().is_empty())
                    .then(|| value.version.trim().to_owned()),
            },
            None => BrowserAutomationStatus {
                configured: false,
                available: false,
                message: "未检测到可用的 Playwright 插件。".to_owned(),
                version: None,
            },
        }
    }

    async fn fetch(&self, target: &Url, prefer_fallback: bool) -> Result<String, SourceError> {
        let configuration = self
            .configuration
            .read()
            .map_err(|_| SourceError::Browser("运行配置不可用".to_owned()))?
            .clone()
            .ok_or(SourceError::BrowserUnavailable)?;
        let _permit = self
            .slots
            .acquire()
            .await
            .map_err(|_| SourceError::Browser("浏览器并发控制器已关闭".to_owned()))?;
        let observation = self
            .client
            .begin_external(target, prefer_fallback)
            .map_err(|_| SourceError::Browser("代理选路失败".to_owned()))?;
        let proxy = observation.proxy().map(browser_proxy_input);
        let input = BrowserReaderInput {
            url: target.as_str().to_owned(),
            package_directory: configuration
                .package_directory
                .to_string_lossy()
                .into_owned(),
            proxy,
        };
        let payload = serde_json::to_vec(&input)
            .map_err(|_| SourceError::Browser("浏览器输入编码失败".to_owned()))?;
        let mut command = Command::new(&configuration.node_executable);
        command
            .arg("-e")
            .arg(PLAYWRIGHT_READER_SCRIPT)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        if let Some(path) = configuration.browsers_path {
            command.env("PLAYWRIGHT_BROWSERS_PATH", path);
        }
        let mut child = command
            .spawn()
            .map_err(|_| SourceError::Browser("无法启动 Node.js".to_owned()))?;
        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| SourceError::Browser("无法写入浏览器输入".to_owned()))?;
        if stdin.write_all(&payload).await.is_err() {
            let _ = child.start_kill();
            return Err(SourceError::Browser("写入浏览器输入失败".to_owned()));
        }
        drop(stdin);
        let output = match timeout(BROWSER_PROCESS_TIMEOUT, child.wait_with_output()).await {
            Ok(Ok(output)) => output,
            Ok(Err(_)) => {
                observation.complete(HttpRequestOutcome::TransportFailure);
                return Err(SourceError::Browser("浏览器进程执行失败".to_owned()));
            }
            Err(_) => {
                observation.complete(HttpRequestOutcome::Timeout);
                return Err(SourceError::Browser("页面读取超时".to_owned()));
            }
        };
        if output.stdout.len() > MAX_BROWSER_OUTPUT_BYTES {
            observation.complete(HttpRequestOutcome::TransportFailure);
            return Err(SourceError::Browser("浏览器返回内容超过限制".to_owned()));
        }
        let result: BrowserReaderOutput = serde_json::from_slice(&output.stdout)
            .map_err(|_| SourceError::Browser("浏览器返回内容格式无效".to_owned()))?;
        if !result.ok || !output.status.success() {
            observation.complete(
                result
                    .status
                    .map_or(HttpRequestOutcome::TransportFailure, |status| {
                        HttpRequestOutcome::Failure(status)
                    }),
            );
            return Err(SourceError::Browser(normalize_browser_error(
                result.error.as_deref(),
            )));
        }
        observation.complete(HttpRequestOutcome::Success(result.status.unwrap_or(200)));
        if result.text.trim().is_empty() && result.links.is_empty() {
            return Err(SourceError::Browser("页面未返回可解析内容".to_owned()));
        }
        Ok(format!("{}\n{}", result.text, result.links.join("\n")))
    }
}

#[derive(Clone)]
struct CdpAutomation {
    client: ObservedHttpClient,
    configuration: Arc<RwLock<Option<CdpBrowserConfiguration>>>,
    generation: Arc<AtomicU64>,
    session: Arc<AsyncMutex<Option<CdpBrowserProcess>>>,
    slots: Arc<Semaphore>,
}

struct CdpBrowserProcess {
    child: Option<Child>,
    port: u16,
    profile_directory: PathBuf,
    generation: u64,
    proxy: Option<CdpProxy>,
    http: Client,
    stderr: Arc<AsyncMutex<String>>,
    stderr_task: Option<JoinHandle<()>>,
}

#[derive(Clone, Eq, PartialEq)]
struct CdpProxy {
    server: String,
    username: Option<String>,
    password: Option<String>,
}

#[derive(Clone)]
struct CdpResponseCapture {
    request_id: String,
    url: String,
    status: u16,
    mime_type: String,
    headers: String,
}

struct CdpNetworkCapture {
    requests: Vec<String>,
    request_bytes: usize,
    responses: Vec<CdpResponseCapture>,
    loaded: bool,
    last_network_event: Instant,
}

struct CdpPageClient {
    socket: WebSocketStream<MaybeTlsStream<TcpStream>>,
    next_id: u64,
    received_bytes: usize,
    capture: CdpNetworkCapture,
    proxy_credentials: Option<(String, String)>,
}

#[derive(Deserialize)]
struct CdpDomSnapshot {
    #[serde(default)]
    title: String,
    #[serde(default)]
    text: String,
    #[serde(default)]
    links: Vec<String>,
}

impl CdpAutomation {
    fn new(client: ObservedHttpClient) -> Self {
        Self {
            client,
            configuration: Arc::new(RwLock::new(None)),
            generation: Arc::new(AtomicU64::new(1)),
            session: Arc::new(AsyncMutex::new(None)),
            slots: Arc::new(Semaphore::new(MAX_CDP_CONCURRENCY)),
        }
    }

    fn configure(&self, configuration: Option<CdpBrowserConfiguration>) -> Result<(), String> {
        if let Some(value) = &configuration {
            validate_browser_path(&value.executable, true, "Google Chrome 可执行文件")?;
        }
        *self
            .configuration
            .write()
            .map_err(|_| "Chrome CDP 配置状态不可用".to_owned())? = configuration;
        self.generation.fetch_add(1, Ordering::AcqRel);
        Ok(())
    }

    fn status(&self) -> CdpBrowserStatus {
        let configuration = self
            .configuration
            .read()
            .ok()
            .and_then(|value| value.clone());
        match configuration {
            Some(value) => CdpBrowserStatus {
                configured: true,
                available: true,
                message: if value.version.trim().is_empty() {
                    "Google Chrome CDP 通道已就绪。".to_owned()
                } else {
                    format!("Google Chrome {} CDP 通道已就绪。", value.version.trim())
                },
                version: (!value.version.trim().is_empty())
                    .then(|| value.version.trim().to_owned()),
            },
            None => CdpBrowserStatus {
                configured: false,
                available: false,
                message: "未检测到本机 Google Chrome。".to_owned(),
                version: None,
            },
        }
    }

    async fn close_session(&self) {
        let session = timeout(Duration::from_secs(5), self.session.lock()).await;
        if let Ok(mut session) = session
            && let Some(process) = session.take()
        {
            process.shutdown().await;
        }
    }

    async fn fetch(&self, target: &Url, prefer_fallback: bool) -> Result<String, SourceError> {
        let configuration = self
            .configuration
            .read()
            .map_err(|_| SourceError::Cdp("运行配置不可用".to_owned()))?
            .clone()
            .ok_or(SourceError::CdpUnavailable)?;
        let _permit = timeout(Duration::from_secs(60), self.slots.acquire())
            .await
            .map_err(|_| SourceError::Cdp("等待 CDP 浏览器通道超时".to_owned()))?
            .map_err(|_| SourceError::Cdp("CDP 浏览器并发控制器已关闭".to_owned()))?;
        let observation = self
            .client
            .begin_external(target, prefer_fallback)
            .map_err(|_| SourceError::Cdp("代理选路失败".to_owned()))?;
        let proxy = observation.proxy().map(cdp_proxy_input);
        let generation = self.generation.load(Ordering::Acquire);
        let mut session = timeout(Duration::from_secs(10), self.session.lock())
            .await
            .map_err(|_| SourceError::Cdp("获取 CDP 浏览器会话超时".to_owned()))?;
        let reusable = match session.as_mut() {
            Some(process) => {
                process.generation == generation
                    && process.proxy == proxy
                    && process.is_alive().unwrap_or(false)
            }
            None => false,
        };
        if !reusable {
            if let Some(process) = session.take() {
                process.shutdown().await;
            }
            *session = Some(
                CdpBrowserProcess::launch(configuration, generation, proxy.clone())
                    .await
                    .map_err(SourceError::Cdp)?,
            );
        }
        let result = session
            .as_mut()
            .ok_or_else(|| SourceError::Cdp("Chrome 进程未就绪".to_owned()))?
            .fetch_page(target)
            .await;
        match result {
            Ok(content) => {
                observation.complete(HttpRequestOutcome::Success(200));
                Ok(content)
            }
            Err(error) => {
                observation.complete(HttpRequestOutcome::TransportFailure);
                if let Some(process) = session.take() {
                    process.shutdown().await;
                }
                Err(SourceError::Cdp(error))
            }
        }
    }
}

impl CdpBrowserProcess {
    async fn launch(
        configuration: CdpBrowserConfiguration,
        generation: u64,
        proxy: Option<CdpProxy>,
    ) -> Result<Self, String> {
        ensure_rustls_crypto_provider();
        let http = Client::builder()
            .no_proxy()
            .timeout(CDP_HTTP_TIMEOUT)
            .build()
            .map_err(|error| format!("创建 CDP 本地客户端失败：{error}"))?;
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .map_err(|error| format!("无法分配 CDP 调试端口：{error}"))?;
        let port = listener
            .local_addr()
            .map_err(|error| format!("无法读取 CDP 调试端口：{error}"))?
            .port();
        drop(listener);
        let sequence = CDP_PROFILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let profile_directory = std::env::temp_dir().join(format!(
            "openhand-hunt-cdp-{}-{timestamp}-{sequence}",
            std::process::id()
        ));
        tokio::fs::create_dir(&profile_directory)
            .await
            .map_err(|error| format!("无法创建 Chrome 隔离配置目录：{error}"))?;
        let mut command = Command::new(&configuration.executable);
        command
            .arg(format!("--remote-debugging-port={port}"))
            .arg("--remote-debugging-address=127.0.0.1")
            .arg("--remote-allow-origins=*")
            .arg(format!(
                "--user-data-dir={}",
                profile_directory.to_string_lossy()
            ))
            .arg("--no-first-run")
            .arg("--no-default-browser-check")
            .arg("--no-service-autorun")
            .arg("--disable-component-update")
            .arg("--disable-translate")
            .arg("--disable-popup-blocking")
            .arg("--password-store=basic")
            .arg("--use-mock-keychain")
            .arg("--window-size=1280,900")
            .arg("about:blank")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        if let Some(value) = &proxy {
            command.arg(format!("--proxy-server={}", value.server));
        }
        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(error) => {
                let _ = tokio::fs::remove_dir_all(&profile_directory).await;
                return Err(format!("无法启动 Google Chrome：{error}"));
            }
        };
        let stderr = Arc::new(AsyncMutex::new(String::new()));
        let stderr_task = child
            .stderr
            .take()
            .map(|stream| tokio::spawn(drain_cdp_stderr(stream, Arc::clone(&stderr))));
        let mut process = Self {
            child: Some(child),
            port,
            profile_directory,
            generation,
            proxy,
            http,
            stderr,
            stderr_task,
        };
        let started = Instant::now();
        while started.elapsed() < CDP_BROWSER_START_TIMEOUT {
            if !process.is_alive().unwrap_or(false) {
                let detail = process.stderr_summary().await;
                process.shutdown().await;
                return Err(if detail.is_empty() {
                    "Google Chrome 在 CDP 握手前退出。".to_owned()
                } else {
                    format!("Google Chrome 在 CDP 握手前退出：{detail}")
                });
            }
            let endpoint = format!("http://127.0.0.1:{port}/json/version");
            if process
                .http
                .get(endpoint)
                .send()
                .await
                .is_ok_and(|response| response.status().is_success())
            {
                return Ok(process);
            }
            sleep(CDP_START_POLL_DELAY).await;
        }
        let detail = process.stderr_summary().await;
        process.shutdown().await;
        Err(if detail.is_empty() {
            "Google Chrome CDP 握手超时。".to_owned()
        } else {
            format!("Google Chrome CDP 握手超时：{detail}")
        })
    }

    fn is_alive(&mut self) -> std::io::Result<bool> {
        match self.child.as_mut() {
            Some(child) => child.try_wait().map(|status| status.is_none()),
            None => Ok(false),
        }
    }

    async fn fetch_page(&mut self, target: &Url) -> Result<String, String> {
        let new_target = format!(
            "http://127.0.0.1:{}/json/new?{}",
            self.port,
            urlencoding::encode(target.as_str())
        );
        let response = self
            .http
            .put(new_target)
            .send()
            .await
            .map_err(|error| format!("创建 CDP 页面失败：{error}"))?;
        if !response.status().is_success() {
            return Err(format!("创建 CDP 页面失败：HTTP {}", response.status()));
        }
        let page: serde_json::Value = response
            .json()
            .await
            .map_err(|_| "CDP 页面描述格式无效".to_owned())?;
        let target_id = page["id"]
            .as_str()
            .filter(|value| !value.is_empty())
            .ok_or_else(|| "CDP 页面缺少目标标识".to_owned())?
            .to_owned();
        let websocket = page["webSocketDebuggerUrl"]
            .as_str()
            .filter(|value| !value.is_empty())
            .ok_or_else(|| "CDP 页面缺少 WebSocket 地址".to_owned())?
            .to_owned();
        let result = self.capture_page(target, &websocket).await;
        let close_target = format!("http://127.0.0.1:{}/json/close/{}", self.port, target_id);
        let _ = self.http.get(close_target).send().await;
        result
    }

    async fn capture_page(&self, target: &Url, websocket: &str) -> Result<String, String> {
        let (socket, _) = timeout(CDP_COMMAND_TIMEOUT, connect_async(websocket))
            .await
            .map_err(|_| "连接 CDP WebSocket 超时".to_owned())?
            .map_err(|error| format!("连接 CDP WebSocket 失败：{error}"))?;
        let credentials = self.proxy.as_ref().and_then(|proxy| {
            proxy
                .username
                .as_ref()
                .map(|username| (username.clone(), proxy.password.clone().unwrap_or_default()))
        });
        let mut page = CdpPageClient::new(socket, credentials);
        let deadline = Instant::now() + CDP_PAGE_TIMEOUT;
        page.command("Page.enable", serde_json::json!({}), deadline)
            .await?;
        page.command("Runtime.enable", serde_json::json!({}), deadline)
            .await?;
        if page.proxy_credentials.is_some() {
            page.command(
                "Fetch.enable",
                serde_json::json!({"handleAuthRequests": true}),
                deadline,
            )
            .await?;
        }
        page.command(
            "Network.enable",
            serde_json::json!({
                "maxTotalBufferSize": MAX_CDP_BODY_BYTES,
                "maxResourceBufferSize": MAX_CDP_FIELD_BYTES,
                "maxPostDataSize": MAX_CDP_FIELD_BYTES,
            }),
            deadline,
        )
        .await?;
        let navigation = page
            .command(
                "Page.navigate",
                serde_json::json!({"url": target.as_str()}),
                deadline,
            )
            .await?;
        if let Some(error) = navigation
            .pointer("/result/errorText")
            .and_then(serde_json::Value::as_str)
            .filter(|value| !value.trim().is_empty())
        {
            return Err(format!("页面导航失败：{}", clip_utf8_bytes(error, 160)));
        }
        page.pump_until_ready(deadline).await?;
        let mut snapshot = page.dom_snapshot(deadline).await?;
        while is_cdp_challenge(&snapshot) && Instant::now() < deadline {
            sleep(CDP_CHALLENGE_DELAY.min(cdp_remaining(deadline)?)).await;
            page.pump_available(deadline).await?;
            snapshot = page.dom_snapshot(deadline).await?;
        }
        if is_cdp_challenge(&snapshot) {
            return Err("站点安全验证未在限定时间内完成".to_owned());
        }
        let bodies = page.response_bodies(deadline).await;
        let content = render_cdp_content(snapshot, &page.capture, &bodies);
        if content.trim().is_empty() {
            return Err("CDP 页面未返回可解析内容".to_owned());
        }
        Ok(content)
    }

    async fn stderr_summary(&self) -> String {
        let value = self.stderr.lock().await;
        value.lines().rev().take(4).collect::<Vec<_>>().join(" | ")
    }

    async fn shutdown(mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.start_kill();
            let _ = timeout(CDP_PROCESS_STOP_TIMEOUT, child.wait()).await;
        }
        if let Some(task) = self.stderr_task.take() {
            task.abort();
        }
        let _ = timeout(
            CDP_PROCESS_STOP_TIMEOUT,
            tokio::fs::remove_dir_all(&self.profile_directory),
        )
        .await;
        self.profile_directory.clear();
    }
}

impl Drop for CdpBrowserProcess {
    fn drop(&mut self) {
        let Some(mut child) = self.child.take() else {
            return;
        };
        let _ = child.start_kill();
        if let Some(task) = self.stderr_task.take() {
            task.abort();
        }
        let directory = std::mem::take(&mut self.profile_directory);
        if let Ok(runtime) = tokio::runtime::Handle::try_current() {
            runtime.spawn(async move {
                let _ = timeout(CDP_PROCESS_STOP_TIMEOUT, child.wait()).await;
                let _ = tokio::fs::remove_dir_all(directory).await;
            });
        } else {
            let _ = std::fs::remove_dir_all(directory);
        }
    }
}

impl CdpPageClient {
    fn new(
        socket: WebSocketStream<MaybeTlsStream<TcpStream>>,
        proxy_credentials: Option<(String, String)>,
    ) -> Self {
        Self {
            socket,
            next_id: 1,
            received_bytes: 0,
            capture: CdpNetworkCapture {
                requests: Vec::new(),
                request_bytes: 0,
                responses: Vec::new(),
                loaded: false,
                last_network_event: Instant::now(),
            },
            proxy_credentials,
        }
    }

    async fn command(
        &mut self,
        method: &str,
        params: serde_json::Value,
        deadline: Instant,
    ) -> Result<serde_json::Value, String> {
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);
        let payload = serde_json::to_string(&serde_json::json!({
            "id": id,
            "method": method,
            "params": params,
        }))
        .map_err(|_| "CDP 命令编码失败".to_owned())?;
        timeout(
            CDP_COMMAND_TIMEOUT.min(cdp_remaining(deadline)?),
            self.socket.send(Message::Text(payload.into())),
        )
        .await
        .map_err(|_| format!("发送 CDP 命令 {method} 超时"))?
        .map_err(|error| format!("发送 CDP 命令 {method} 失败：{error}"))?;
        loop {
            let wait = CDP_COMMAND_TIMEOUT.min(cdp_remaining(deadline)?);
            let value = self
                .receive(wait)
                .await?
                .ok_or_else(|| format!("等待 CDP 命令 {method} 响应超时"))?;
            self.capture.observe(&value);
            if value["id"].as_u64() != Some(id) {
                continue;
            }
            if let Some(error) = value.get("error") {
                let message = error["message"].as_str().unwrap_or("未知错误");
                return Err(format!("CDP 命令 {method} 失败：{message}"));
            }
            return Ok(value);
        }
    }

    async fn receive(&mut self, wait: Duration) -> Result<Option<serde_json::Value>, String> {
        loop {
            let message = match timeout(wait, self.socket.next()).await {
                Err(_) => return Ok(None),
                Ok(Some(Ok(message))) => message,
                Ok(Some(Err(error))) => return Err(format!("CDP 连接读取失败：{error}")),
                Ok(None) => return Err("CDP 连接已关闭".to_owned()),
            };
            self.received_bytes = self.received_bytes.saturating_add(message.len());
            if self.received_bytes > MAX_CDP_EVENT_BYTES {
                return Err("CDP 事件数据超过限制".to_owned());
            }
            match message {
                Message::Text(text) => {
                    let value = serde_json::from_str(text.as_str())
                        .map_err(|_| "CDP 事件格式无效".to_owned())?;
                    self.handle_fetch_event(&value).await?;
                    return Ok(Some(value));
                }
                Message::Ping(value) => {
                    self.socket
                        .send(Message::Pong(value))
                        .await
                        .map_err(|error| format!("CDP 心跳响应失败：{error}"))?;
                }
                Message::Close(_) => return Err("CDP 连接已关闭".to_owned()),
                _ => {}
            }
        }
    }

    async fn handle_fetch_event(&mut self, value: &serde_json::Value) -> Result<(), String> {
        let method = value["method"].as_str().unwrap_or_default();
        let request_id = value["params"]["requestId"].as_str().unwrap_or_default();
        if request_id.is_empty() {
            return Ok(());
        }
        let (method, params) = match method {
            "Fetch.requestPaused" => (
                "Fetch.continueRequest",
                serde_json::json!({"requestId": request_id}),
            ),
            "Fetch.authRequired" => {
                let response = match &self.proxy_credentials {
                    Some((username, password)) => serde_json::json!({
                        "response": "ProvideCredentials",
                        "username": username,
                        "password": password,
                    }),
                    None => serde_json::json!({"response": "Default"}),
                };
                (
                    "Fetch.continueWithAuth",
                    serde_json::json!({"requestId": request_id, "authChallengeResponse": response}),
                )
            }
            _ => return Ok(()),
        };
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);
        let payload = serde_json::to_string(&serde_json::json!({
            "id": id,
            "method": method,
            "params": params,
        }))
        .map_err(|_| "CDP 代理认证命令编码失败".to_owned())?;
        timeout(
            CDP_COMMAND_TIMEOUT,
            self.socket.send(Message::Text(payload.into())),
        )
        .await
        .map_err(|_| "发送 CDP 代理认证命令超时".to_owned())?
        .map_err(|error| format!("发送 CDP 代理认证命令失败：{error}"))
    }

    async fn pump_until_ready(&mut self, deadline: Instant) -> Result<(), String> {
        loop {
            let now = Instant::now();
            if now >= deadline {
                return Err("等待 CDP 页面载入超时".to_owned());
            }
            if self.capture.loaded
                && now.duration_since(self.capture.last_network_event) >= CDP_IDLE_DELAY
            {
                return Ok(());
            }
            if let Some(value) = self
                .receive(Duration::from_millis(250).min(cdp_remaining(deadline)?))
                .await?
            {
                self.capture.observe(&value);
            }
        }
    }

    async fn pump_available(&mut self, deadline: Instant) -> Result<(), String> {
        while let Some(value) = self
            .receive(Duration::from_millis(80).min(cdp_remaining(deadline)?))
            .await?
        {
            self.capture.observe(&value);
        }
        Ok(())
    }

    async fn dom_snapshot(&mut self, deadline: Instant) -> Result<CdpDomSnapshot, String> {
        let expression = r#"JSON.stringify({title:document.title||'',text:(document.body?.innerText||document.documentElement?.innerText||'').slice(0,300000),links:Array.from(document.querySelectorAll('a[href]'),a=>a.href).slice(0,600)})"#;
        let response = self
            .command(
                "Runtime.evaluate",
                serde_json::json!({
                    "expression": expression,
                    "returnByValue": true,
                    "awaitPromise": true,
                }),
                deadline,
            )
            .await?;
        let raw = response
            .pointer("/result/result/value")
            .and_then(serde_json::Value::as_str)
            .ok_or_else(|| "CDP 页面正文读取失败".to_owned())?;
        serde_json::from_str(raw).map_err(|_| "CDP 页面正文格式无效".to_owned())
    }

    async fn response_bodies(&mut self, deadline: Instant) -> BTreeMap<String, String> {
        let responses = self
            .capture
            .responses
            .iter()
            .filter(|response| cdp_textual_mime(&response.mime_type))
            .take(MAX_CDP_RESPONSE_BODIES)
            .cloned()
            .collect::<Vec<_>>();
        let mut bodies = BTreeMap::new();
        let mut total = 0_usize;
        for response in responses {
            if total >= MAX_CDP_BODY_BYTES || Instant::now() >= deadline {
                break;
            }
            let value = match self
                .command(
                    "Network.getResponseBody",
                    serde_json::json!({"requestId": response.request_id}),
                    deadline,
                )
                .await
            {
                Ok(value) => value,
                Err(_) => continue,
            };
            let Some(body) = value
                .pointer("/result/body")
                .and_then(serde_json::Value::as_str)
            else {
                continue;
            };
            let decoded = if value
                .pointer("/result/base64Encoded")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false)
            {
                STANDARD
                    .decode(body)
                    .ok()
                    .map(|bytes| String::from_utf8_lossy(&bytes).into_owned())
                    .unwrap_or_default()
            } else {
                body.to_owned()
            };
            let remaining = MAX_CDP_BODY_BYTES.saturating_sub(total);
            let clipped = clip_utf8_bytes(&decoded, remaining.min(MAX_CDP_FIELD_BYTES));
            total = total.saturating_add(clipped.len());
            if !clipped.trim().is_empty() {
                bodies.insert(response.request_id, clipped);
            }
        }
        bodies
    }
}

impl CdpNetworkCapture {
    fn observe(&mut self, value: &serde_json::Value) {
        let Some(method) = value["method"].as_str() else {
            return;
        };
        if method.starts_with("Network.") {
            self.last_network_event = Instant::now();
        }
        match method {
            "Page.loadEventFired" => self.loaded = true,
            "Network.requestWillBeSent" if self.requests.len() < MAX_CDP_REQUESTS => {
                if self.request_bytes >= MAX_CDP_REQUEST_CAPTURE_BYTES {
                    return;
                }
                let request = &value["params"]["request"];
                let url = request["url"].as_str().unwrap_or_default();
                if !url.starts_with("http://") && !url.starts_with("https://") {
                    return;
                }
                let method = request["method"].as_str().unwrap_or("GET");
                let headers = cdp_headers(&request["headers"], true);
                let post_data = request["postData"]
                    .as_str()
                    .map(|value| clip_utf8_bytes(value, MAX_CDP_FIELD_BYTES))
                    .unwrap_or_default();
                let request = format!(
                    "{method} {url}\n{headers}{}",
                    if post_data.is_empty() {
                        String::new()
                    } else {
                        format!("\n请求正文：{post_data}")
                    }
                );
                let remaining = MAX_CDP_REQUEST_CAPTURE_BYTES.saturating_sub(self.request_bytes);
                let request = clip_utf8_bytes(&request, remaining);
                self.request_bytes = self.request_bytes.saturating_add(request.len());
                if !request.is_empty() {
                    self.requests.push(request);
                }
            }
            "Network.responseReceived" if self.responses.len() < MAX_CDP_RESPONSES => {
                let params = &value["params"];
                let response = &params["response"];
                let request_id = params["requestId"].as_str().unwrap_or_default();
                let url = response["url"].as_str().unwrap_or_default();
                if request_id.is_empty()
                    || (!url.starts_with("http://") && !url.starts_with("https://"))
                {
                    return;
                }
                self.responses.push(CdpResponseCapture {
                    request_id: request_id.to_owned(),
                    url: url.to_owned(),
                    status: response["status"].as_f64().unwrap_or(0.0) as u16,
                    mime_type: response["mimeType"].as_str().unwrap_or_default().to_owned(),
                    headers: cdp_headers(&response["headers"], false),
                });
            }
            _ => {}
        }
    }
}

async fn drain_cdp_stderr(
    mut stream: tokio::process::ChildStderr,
    output: Arc<AsyncMutex<String>>,
) {
    let mut chunk = [0_u8; 4096];
    loop {
        let read = match stream.read(&mut chunk).await {
            Ok(0) | Err(_) => return,
            Ok(read) => read,
        };
        let text = String::from_utf8_lossy(&chunk[..read]);
        let mut output = output.lock().await;
        output.push_str(&text);
        if output.len() > MAX_CDP_STDERR_BYTES {
            *output = clip_utf8_tail(&output, MAX_CDP_STDERR_BYTES);
        }
    }
}

fn cdp_headers(value: &serde_json::Value, request: bool) -> String {
    let Some(headers) = value.as_object() else {
        return String::new();
    };
    headers
        .iter()
        .filter(|(name, _)| {
            let name = name.to_ascii_lowercase();
            name != "set-cookie"
                && (!request
                    || !matches!(
                        name.as_str(),
                        "authorization" | "cookie" | "proxy-authorization" | "x-api-key"
                    ))
        })
        .take(24)
        .map(|(name, value)| format!("{name}: {}", value.as_str().unwrap_or_default()))
        .collect::<Vec<_>>()
        .join("\n")
}

fn cdp_textual_mime(value: &str) -> bool {
    let value = value.to_ascii_lowercase();
    value.starts_with("text/")
        || value.contains("json")
        || value.contains("javascript")
        || value.contains("xml")
        || value.contains("graphql")
}

fn is_cdp_challenge(snapshot: &CdpDomSnapshot) -> bool {
    let content = format!("{}\n{}", snapshot.title, snapshot.text).to_ascii_lowercase();
    content.contains("just a moment")
        || content.contains("enable javascript and cookies")
        || content.contains("正在验证您是否是真人")
}

fn render_cdp_content(
    snapshot: CdpDomSnapshot,
    capture: &CdpNetworkCapture,
    bodies: &BTreeMap<String, String>,
) -> String {
    let mut output = String::new();
    append_cdp_content(&mut output, &snapshot.title);
    append_cdp_content(&mut output, "\n");
    append_cdp_content(&mut output, &snapshot.text);
    append_cdp_content(&mut output, "\n页面链接：\n");
    append_cdp_content(&mut output, &snapshot.links.join("\n"));
    append_cdp_content(&mut output, "\n网络请求：\n");
    for request in &capture.requests {
        append_cdp_content(&mut output, request);
        append_cdp_content(&mut output, "\n\n");
    }
    append_cdp_content(&mut output, "网络响应：\n");
    for response in &capture.responses {
        append_cdp_content(
            &mut output,
            &format!(
                "HTTP {} {}\n{}\n",
                response.status, response.url, response.headers
            ),
        );
        if let Some(body) = bodies.get(&response.request_id) {
            append_cdp_content(&mut output, body);
            append_cdp_content(&mut output, "\n");
        }
    }
    output
}

fn append_cdp_content(output: &mut String, value: &str) {
    let remaining = MAX_BROWSER_OUTPUT_BYTES.saturating_sub(output.len());
    if remaining > 0 {
        output.push_str(&clip_utf8_bytes(value, remaining));
    }
}

fn clip_utf8_bytes(value: &str, limit: usize) -> String {
    if value.len() <= limit {
        return value.to_owned();
    }
    let boundary = value
        .char_indices()
        .map(|(index, _)| index)
        .take_while(|index| *index <= limit)
        .last()
        .unwrap_or(0);
    value[..boundary].to_owned()
}

fn clip_utf8_tail(value: &str, limit: usize) -> String {
    if value.len() <= limit {
        return value.to_owned();
    }
    let start = value.len().saturating_sub(limit);
    let boundary = value
        .char_indices()
        .map(|(index, _)| index)
        .find(|index| *index >= start)
        .unwrap_or(value.len());
    value[boundary..].to_owned()
}

fn cdp_remaining(deadline: Instant) -> Result<Duration, String> {
    deadline
        .checked_duration_since(Instant::now())
        .filter(|remaining| !remaining.is_zero())
        .ok_or_else(|| "CDP 页面读取超过总时限".to_owned())
}

fn validate_browser_path(path: &Path, file: bool, label: &str) -> Result<(), String> {
    if !path.is_absolute() || path.to_string_lossy().len() > 4096 {
        return Err(format!("{label}路径无效"));
    }
    let metadata = path.metadata().map_err(|_| format!("{label}不存在"))?;
    if file && !metadata.is_file() || !file && !metadata.is_dir() {
        return Err(format!("{label}类型无效"));
    }
    Ok(())
}

fn browser_proxy_input(url: &Url) -> BrowserProxyInput {
    let host = url.host_str().unwrap_or_default();
    // socks5:// 等非标 scheme 没有 IANA 注册的默认端口，
    // port_or_known_default() 会返回 None；此时回退到显式端口或 1080。
    let port = url.port_or_known_default().or(url.port()).unwrap_or(1080);
    BrowserProxyInput {
        server: format!("{}://{host}:{port}", url.scheme()),
        username: (!url.username().is_empty()).then(|| decode_url_component(url.username())),
        password: url.password().map(decode_url_component),
    }
}

fn cdp_proxy_input(url: &Url) -> CdpProxy {
    let host = url.host_str().unwrap_or_default();
    let port = url.port_or_known_default().or(url.port()).unwrap_or(1080);
    CdpProxy {
        server: format!("{}://{host}:{port}", url.scheme()),
        username: (!url.username().is_empty()).then(|| decode_url_component(url.username())),
        password: url.password().map(decode_url_component),
    }
}

fn decode_url_component(value: &str) -> String {
    urlencoding::decode(value)
        .map(|value| value.into_owned())
        .unwrap_or_else(|_| value.to_owned())
}

fn normalize_browser_error(value: Option<&str>) -> String {
    let message = value.unwrap_or_default().trim();
    if message.is_empty() {
        "未知错误".to_owned()
    } else if message.contains("Executable doesn't exist") {
        "浏览器内核未安装".to_owned()
    } else if message.contains("站点安全验证未通过") {
        "站点安全验证未通过".to_owned()
    } else if message.contains("Timeout") || message.contains("timeout") {
        "页面载入超时".to_owned()
    } else if message.contains("Cannot find module") {
        "模块不可用".to_owned()
    } else if message.contains("ERR_PROXY")
        || message.contains("proxy") && message.contains("connection")
    {
        "代理连接失败".to_owned()
    } else if message.contains("ERR_NAME_NOT_RESOLVED") || message.contains("ENOTFOUND") {
        "DNS 解析失败".to_owned()
    } else if message.contains("ECONNREFUSED") || message.contains("connection refused") {
        "连接被拒".to_owned()
    } else {
        let truncated: String = message.chars().take(120).collect();
        format!("运行异常：{truncated}")
    }
}

/// 从 `SourceError` 中提取浏览器错误的内部原因描述，
/// 避免与 `ForumFetch` 的 Display 格式串二次拼接出重复前缀。
fn browser_error_reason(error: &SourceError) -> String {
    match error {
        SourceError::Browser(message) => message.clone(),
        SourceError::BrowserUnavailable => "浏览器通道未就绪".to_owned(),
        other => other.to_string(),
    }
}

fn cdp_error_reason(error: &SourceError) -> String {
    match error {
        SourceError::Cdp(message) => message.clone(),
        SourceError::CdpUnavailable => "未检测到 Google Chrome".to_owned(),
        other => other.to_string(),
    }
}

fn jina_route_label(fallback: bool) -> &'static str {
    if fallback {
        "系统代理/DIRECT 回退路由"
    } else {
        "首选路由"
    }
}

fn jina_status_retryable(status: StatusCode) -> bool {
    status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error()
}

fn jina_status_hint(status: StatusCode) -> &'static str {
    match status {
        StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => "（访问被拒绝）",
        StatusCode::TOO_MANY_REQUESTS => "（匿名额度受限，稍后重试）",
        StatusCode::REQUEST_TIMEOUT | StatusCode::GATEWAY_TIMEOUT => "（上游读取超时）",
        status if status.is_server_error() => "（Jina Reader 服务异常）",
        _ => "",
    }
}

fn concise_reqwest_error(error: &reqwest::Error) -> String {
    let message = error.to_string();
    let concise = message.lines().next().unwrap_or("未知错误");
    concise.chars().take(160).collect()
}

#[derive(Clone, Copy)]
struct ForumSpecification {
    kind: SourceKind,
    key: &'static str,
    platform: &'static str,
    host: &'static str,
    default_entry: &'static str,
}

impl ForumSpecification {
    fn all() -> [Self; 3] {
        [
            Self {
                kind: SourceKind::Nodeseek,
                key: "nodeseek",
                platform: "NodeSeek",
                host: "nodeseek.com",
                default_entry: "https://www.nodeseek.com/",
            },
            Self {
                kind: SourceKind::LinuxDo,
                key: "linux_do",
                platform: "LINUX DO",
                host: "linux.do",
                default_entry: "https://linux.do/c/welfare/36",
            },
            Self {
                kind: SourceKind::V2ex,
                key: "v2ex",
                platform: "V2EX",
                host: "v2ex.com",
                default_entry: "https://www.v2ex.com/go/openai",
            },
        ]
    }

    fn is_topic_path(self, path: &str) -> bool {
        match self.kind {
            SourceKind::Nodeseek => NODESEEK_TOPIC_PATTERN.is_match(path),
            SourceKind::LinuxDo => LINUX_DO_TOPIC_PATTERN.is_match(path),
            SourceKind::V2ex => V2EX_TOPIC_PATTERN.is_match(path),
            _ => false,
        }
    }
}

struct ForumSource {
    client: ObservedHttpClient,
    browser: BrowserAutomation,
    cdp: CdpAutomation,
    specification: ForumSpecification,
}

struct ForumPage {
    content: String,
    warning: Option<String>,
    mode: ForumFetchMode,
    fallback_route: bool,
}

impl ForumSource {
    fn new(
        client: ObservedHttpClient,
        browser: BrowserAutomation,
        cdp: CdpAutomation,
        specification: ForumSpecification,
    ) -> Self {
        Self {
            client,
            browser,
            cdp,
            specification,
        }
    }

    async fn fetch_page(
        &self,
        target: &Url,
        mode: ForumFetchMode,
        prefer_fallback: bool,
        credentials: &SourceCredentials,
    ) -> Result<ForumPage, SourceError> {
        if mode == ForumFetchMode::Cdp {
            return match self.cdp.fetch(target, prefer_fallback).await {
                Ok(content) => Ok(ForumPage {
                    content,
                    warning: None,
                    mode: ForumFetchMode::Cdp,
                    fallback_route: prefer_fallback,
                }),
                Err(error @ SourceError::CdpUnavailable) => Err(error),
                Err(primary) if !prefer_fallback => match self.cdp.fetch(target, true).await {
                    Ok(content) => Ok(ForumPage {
                        content,
                        warning: Some(format!(
                            "{} 的 CDP 首选路由失败，已通过系统代理/DIRECT 回退：{}",
                            self.specification.platform,
                            cdp_error_reason(&primary),
                        )),
                        mode: ForumFetchMode::Cdp,
                        fallback_route: true,
                    }),
                    Err(fallback) => Err(SourceError::Cdp(format!(
                        "首选路由 {}；系统代理/DIRECT 回退路由 {}",
                        cdp_error_reason(&primary),
                        cdp_error_reason(&fallback),
                    ))),
                },
                Err(error) => Err(error),
            };
        }
        if mode == ForumFetchMode::Playwright {
            return match self.browser.fetch(target, prefer_fallback).await {
                Ok(content) => Ok(ForumPage {
                    content,
                    warning: None,
                    mode: ForumFetchMode::Playwright,
                    fallback_route: prefer_fallback,
                }),
                Err(primary) if !prefer_fallback => match self.browser.fetch(target, true).await {
                    Ok(content) => Ok(ForumPage {
                        content,
                        warning: Some(format!(
                            "{} 的 Playwright 首选路由失败，已通过系统代理/DIRECT 回退：{}",
                            self.specification.platform,
                            browser_error_reason(&primary),
                        )),
                        mode: ForumFetchMode::Playwright,
                        fallback_route: true,
                    }),
                    Err(fallback) => Err(SourceError::Browser(format!(
                        "首选路由 {}；系统代理/DIRECT 回退路由 {}",
                        browser_error_reason(&primary),
                        browser_error_reason(&fallback),
                    ))),
                },
                Err(error) => Err(error),
            };
        }
        let selection = credentials.begin(SourceToolKind::Jina);
        let reader_result = match &selection {
            Ok(selection) => {
                self.fetch_jina(target, prefer_fallback, &selection.profile)
                    .await
            }
            Err(error) => Err(error.to_string()),
        };
        if let Ok(selection) = selection {
            selection.complete(reader_result.is_ok());
        }
        match reader_result {
            Ok((content, fallback_route, first_error)) => Ok(ForumPage {
                content,
                warning: first_error.map(|error| {
                    if prefer_fallback {
                        format!(
                            "{} 的 Jina Reader 回退路由首次读取失败，重试成功：{error}",
                            self.specification.platform
                        )
                    } else {
                        format!(
                            "{} 的 Jina Reader 首选路由失败，已通过系统代理/DIRECT 回退：{error}",
                            self.specification.platform
                        )
                    }
                }),
                mode: ForumFetchMode::JinaFallback,
                fallback_route,
            }),
            Err(reader) => match self.browser.fetch(target, true).await {
                Ok(content) => Ok(ForumPage {
                    content,
                    warning: Some(format!(
                        "{} 的 Jina Reader 读取失败，已通过回退路由切换 Playwright：{reader}",
                        self.specification.platform
                    )),
                    mode: ForumFetchMode::Playwright,
                    fallback_route: true,
                }),
                Err(browser) => Err(SourceError::ForumFetch {
                    platform: self.specification.platform,
                    reader,
                    browser: browser_error_reason(&browser),
                }),
            },
        }
    }

    async fn fetch_jina(
        &self,
        target: &Url,
        prefer_fallback: bool,
        profile: &ToolProfile,
    ) -> Result<(String, bool, Option<String>), String> {
        let max_attempts = profile
            .value("maxAttempts")
            .and_then(|value| value.parse::<u8>().ok())
            .unwrap_or(JINA_READER_MAX_ATTEMPTS)
            .clamp(1, 5);
        let retry_delay = Duration::from_millis(
            profile
                .value("retryDelayMs")
                .and_then(|value| value.parse::<u64>().ok())
                .unwrap_or(JINA_READER_RETRY_DELAY.as_millis() as u64)
                .min(5_000),
        );
        let mut errors = Vec::with_capacity(max_attempts as usize);
        for attempt in 1..=max_attempts {
            let fallback_route = prefer_fallback || attempt > 1;
            let default_timeout = if fallback_route {
                JINA_READER_FALLBACK_TIMEOUT
            } else {
                JINA_READER_PRIMARY_TIMEOUT
            };
            let request_timeout = profile
                .value("timeout")
                .and_then(|value| value.parse::<u64>().ok())
                .filter(|value| *value > 0)
                .map(|value| Duration::from_secs(value.min(180).saturating_add(5)))
                .unwrap_or(default_timeout);
            let response = jina_request(&self.client, target, profile)?
                .prefer_fallback(fallback_route)
                .automatic_fallback(false)
                .timeout(request_timeout)
                .send()
                .await;
            let response = match response {
                Ok(response) => response,
                Err(error) => {
                    let reason = if error.is_timeout() {
                        "请求超时".to_owned()
                    } else if error.is_connect() {
                        "连接失败（DNS/网络/代理不可达）".to_owned()
                    } else {
                        format!("网络请求失败：{}", concise_reqwest_error(&error))
                    };
                    errors.push(format!("{}：{reason}", jina_route_label(fallback_route)));
                    if attempt < max_attempts {
                        tokio::time::sleep(retry_delay).await;
                        continue;
                    }
                    return Err(errors.join("；"));
                }
            };
            let status = response.status();
            if !status.is_success() {
                let reason = format!(
                    "{}：返回 HTTP {}{}",
                    jina_route_label(fallback_route),
                    status.as_u16(),
                    jina_status_hint(status),
                );
                errors.push(reason);
                if attempt < max_attempts && jina_status_retryable(status) {
                    tokio::time::sleep(retry_delay).await;
                    continue;
                }
                return Err(errors.join("；"));
            }
            let content = match parse_jina_content(self.specification.platform, response).await {
                Ok(content) => content,
                Err(error) => {
                    errors.push(format!("{}：{}", jina_route_label(fallback_route), error));
                    if attempt < max_attempts {
                        tokio::time::sleep(retry_delay).await;
                        continue;
                    }
                    return Err(errors.join("；"));
                }
            };
            let trimmed = content.trim();
            if trimmed.is_empty() {
                errors.push(format!(
                    "{}：返回内容为空",
                    jina_route_label(fallback_route)
                ));
                if attempt < max_attempts {
                    tokio::time::sleep(retry_delay).await;
                    continue;
                }
                return Err(errors.join("；"));
            }
            if trimmed.starts_with("{\"data\":null,") {
                errors.push(format!(
                    "{}：拒绝读取目标站点",
                    jina_route_label(fallback_route)
                ));
                return Err(errors.join("；"));
            }
            return Ok((content, fallback_route, errors.into_iter().next()));
        }
        Err(errors.join("；"))
    }
}

fn jina_request(
    client: &ObservedHttpClient,
    target: &Url,
    profile: &ToolProfile,
) -> Result<ObservedRequestBuilder, String> {
    let mut body = serde_json::Map::from_iter([(
        "url".to_owned(),
        serde_json::Value::String(target.as_str().to_owned()),
    )]);
    for key in ["instruction"] {
        if let Some(value) = profile.value(key) {
            body.insert(key.to_owned(), serde_json::Value::String(value.to_owned()));
        }
    }
    for (key, body_key) in [
        ("injectPageScript", "injectPageScript"),
        ("injectFrameScript", "injectFrameScript"),
    ] {
        if let Some(value) = profile.value(key) {
            let scripts = if value.trim_start().starts_with('[') {
                let decoded = serde_json::from_str::<Vec<String>>(value)
                    .map_err(|_| format!("Jina Reader 参数 {key} 必须是字符串数组"))?;
                decoded
                    .into_iter()
                    .filter(|script| !script.trim().is_empty())
                    .map(serde_json::Value::String)
                    .collect::<Vec<_>>()
            } else {
                vec![serde_json::Value::String(value.to_owned())]
            };
            body.insert(body_key.to_owned(), serde_json::Value::Array(scripts));
        }
    }
    for key in ["jsonSchema", "customHeader", "storageState"] {
        if let Some(value) = profile.value(key) {
            let decoded = serde_json::from_str::<serde_json::Value>(value)
                .map_err(|_| format!("Jina Reader 参数 {key} 必须是有效 JSON"))?;
            if !decoded.is_object() {
                return Err(format!("Jina Reader 参数 {key} 必须是 JSON 对象"));
            }
            body.insert(key.to_owned(), decoded);
        }
    }
    let mut viewport = serde_json::Map::new();
    for (key, body_key) in [
        ("viewportWidth", "width"),
        ("viewportHeight", "height"),
        ("viewportDeviceScaleFactor", "deviceScaleFactor"),
    ] {
        if let Some(number) = profile
            .value(key)
            .and_then(|value| value.parse::<f64>().ok())
            .and_then(serde_json::Number::from_f64)
        {
            viewport.insert(body_key.to_owned(), serde_json::Value::Number(number));
        }
    }
    for (key, body_key) in [
        ("viewportIsMobile", "isMobile"),
        ("viewportIsLandscape", "isLandscape"),
        ("viewportHasTouch", "hasTouch"),
    ] {
        if let Some(value) = profile.value(key) {
            viewport.insert(
                body_key.to_owned(),
                serde_json::Value::Bool(jina_true(value)),
            );
        }
    }
    if !viewport.is_empty() {
        body.insert("viewport".to_owned(), serde_json::Value::Object(viewport));
    }
    let uses_post = body.len() > 1;
    let mut request = if uses_post {
        client
            .post(JINA_READER_ENDPOINT)
            .json(&serde_json::Value::Object(body))
    } else {
        let reader_url = Url::parse(&format!("{JINA_READER_ENDPOINT}{}", target.as_str()))
            .map_err(|_| "Jina Reader 请求地址无效".to_owned())?;
        client.get(reader_url)
    };
    request = request
        .header("Accept", profile.value("accept").unwrap_or("text/plain"))
        .header(
            "X-Timeout",
            profile
                .value("timeout")
                .unwrap_or(JINA_READER_SERVER_TIMEOUT_SECONDS),
        );
    if let Some(token) = profile.value("token") {
        request = request.bearer_auth(token);
    }
    for (key, header) in JINA_HEADER_OPTIONS
        .iter()
        .chain(JINA_MARKDOWN_HEADER_OPTIONS.iter())
    {
        if *key == "timeout" {
            continue;
        }
        if let Some(value) = profile.value(key) {
            request = request.header(header, if *key == "dnt" { "1" } else { value });
        }
    }
    if let Some(cookies) = profile.value("setCookies") {
        for cookie in cookies
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
        {
            request = request.header("X-Set-Cookie", cookie);
        }
    }
    Ok(request)
}

fn jina_true(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
    )
}

#[async_trait]
impl AssetSource for ForumSource {
    fn kind(&self) -> SourceKind {
        self.specification.kind
    }

    async fn discover(
        &self,
        request: &ScanRequest,
        credentials: &SourceCredentials,
    ) -> Result<SourceDiscovery, SourceError> {
        let entry = source_query(request, self.specification.key)
            .unwrap_or_else(|| self.specification.default_entry.to_owned());
        let entry = parse_forum_entry(&entry, self.specification)?;
        let index = self
            .fetch_page(&entry, request.forum_fetch_mode, false, credentials)
            .await?;
        let direct_topic = self.specification.is_topic_path(entry.path());
        let topics = if direct_topic {
            Vec::new()
        } else {
            extract_forum_topics(&index.content, self.specification)
        };
        if !direct_topic && topics.is_empty() {
            if request.forum_fetch_mode == ForumFetchMode::Cdp {
                self.cdp.close_session().await;
            }
            return Err(SourceError::InvalidResponse(self.specification.platform));
        }
        let mut warnings = index.warning.into_iter().collect::<Vec<_>>();
        let mut candidates = BTreeMap::new();
        let mut successful_pages = 0_usize;
        let mut last_error = None;
        if direct_topic {
            successful_pages = 1;
            for candidate in forum_candidates(&index.content, &entry, self.specification) {
                candidates
                    .entry(candidate.target.clone())
                    .or_insert(candidate);
            }
        } else {
            let source = self;
            let mode = index.mode;
            let pages = stream::iter(topics.into_iter().map(|topic| async move {
                let result = source
                    .fetch_page(&topic, mode, index.fallback_route, credentials)
                    .await;
                (topic, result)
            }))
            .buffer_unordered(if mode == ForumFetchMode::Cdp {
                1
            } else {
                FORUM_TOPIC_CONCURRENCY
            });
            futures::pin_mut!(pages);
            while let Some((topic, result)) = pages.next().await {
                match result {
                    Ok(page) => {
                        successful_pages += 1;
                        warnings.extend(page.warning);
                        for candidate in forum_candidates(&page.content, &topic, self.specification)
                        {
                            candidates
                                .entry(candidate.target.clone())
                                .or_insert(candidate);
                            if candidates.len() >= MAX_SOURCE_RESULTS {
                                break;
                            }
                        }
                    }
                    Err(error) => {
                        warnings.push(format!(
                            "{} 主题读取失败：{}；{error}",
                            self.specification.platform, topic
                        ));
                        last_error = Some(error);
                    }
                }
                if candidates.len() >= MAX_SOURCE_RESULTS {
                    break;
                }
            }
        }
        if successful_pages == 0 {
            if request.forum_fetch_mode == ForumFetchMode::Cdp {
                self.cdp.close_session().await;
            }
            return Err(
                last_error.unwrap_or(SourceError::InvalidResponse(self.specification.platform))
            );
        }
        if candidates.is_empty() {
            warnings.push(format!(
                "{} 已读取主题，但未提取到外部 HTTP/HTTPS 链接。",
                self.specification.platform
            ));
        }
        let discovery = SourceDiscovery {
            candidates: candidates.into_values().collect(),
            warnings,
        };
        if request.forum_fetch_mode == ForumFetchMode::Cdp {
            self.cdp.close_session().await;
        }
        Ok(discovery)
    }

    async fn quota(&self, _credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        let browser = self.browser.status();
        let cdp = self.cdp.status();
        Ok(unlimited_quota(
            self.specification.kind,
            &if browser.available && cdp.available {
                format!(
                    "无需 API 凭证；Jina Reader、{}、{}均可用。",
                    browser.message, cdp.message
                )
            } else {
                format!(
                    "无需 API 凭证；Jina Reader 可用，{}{}",
                    browser.message, cdp.message
                )
            },
        ))
    }
}

fn parse_forum_entry(value: &str, specification: ForumSpecification) -> Result<Url, SourceError> {
    let url = Url::parse(value.trim())
        .map_err(|_| SourceError::InvalidForumEntry("请输入完整的 HTTP/HTTPS 地址".to_owned()))?;
    let host = url.host_str().unwrap_or_default();
    if !matches!(url.scheme(), "http" | "https")
        || !same_forum_host(host, specification.host)
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err(SourceError::InvalidForumEntry(format!(
            "仅允许 {} 站内地址",
            specification.platform
        )));
    }
    Ok(url)
}

fn extract_forum_topics(content: &str, specification: ForumSpecification) -> Vec<Url> {
    let mut seen = BTreeSet::new();
    let mut topics = Vec::new();
    for found in URL_PATTERN.find_iter(content) {
        let value = trim_url_punctuation(found.as_str());
        let Ok(mut url) = Url::parse(&value) else {
            continue;
        };
        if !same_forum_host(url.host_str().unwrap_or_default(), specification.host)
            || !specification.is_topic_path(url.path())
        {
            continue;
        }
        normalize_topic_url(&mut url, specification);
        if seen.insert(url.as_str().to_owned()) {
            topics.push(url);
        }
        if topics.len() >= MAX_FORUM_TOPICS {
            break;
        }
    }
    topics
}

fn normalize_topic_url(url: &mut Url, specification: ForumSpecification) {
    url.set_query(None);
    url.set_fragment(None);
    if specification.kind == SourceKind::LinuxDo {
        let segments = url
            .path_segments()
            .map(|items| items.take(3).collect::<Vec<_>>())
            .unwrap_or_default();
        if segments.len() == 3 {
            url.set_path(&format!("/{}/{}/{}", segments[0], segments[1], segments[2]));
        }
    }
}

fn forum_candidates(
    content: &str,
    topic: &Url,
    specification: ForumSpecification,
) -> Vec<Candidate> {
    URL_PATTERN
        .find_iter(content)
        .filter_map(|found| {
            let value = trim_url_punctuation(found.as_str());
            let url = Url::parse(&value).ok()?;
            let host = url.host_str()?;
            if !matches!(url.scheme(), "http" | "https")
                || same_forum_host(host, specification.host)
                || host.eq_ignore_ascii_case("r.jina.ai")
                || is_forum_asset_link(content, found.start(), &url)
            {
                return None;
            }
            Some(Candidate {
                source: specification.kind,
                target: url.to_string(),
                discovered_at: Utc::now(),
                metadata: BTreeMap::from([
                    (
                        CANDIDATE_ARTIFACT_URL_KEY.to_owned(),
                        topic.as_str().to_owned(),
                    ),
                    (
                        CANDIDATE_ARTIFACT_TEXT_KEY.to_owned(),
                        surrounding_text(
                            content,
                            found.start(),
                            found.end(),
                            MAX_ARTIFACT_CONTEXT_BYTES,
                        ),
                    ),
                ]),
            })
        })
        .take(MAX_SOURCE_RESULTS)
        .collect()
}

fn is_forum_asset_link(content: &str, url_start: usize, url: &Url) -> bool {
    let prefix = &content[..url_start];
    let markdown_image = prefix.ends_with("](")
        && prefix[..prefix.len() - 2]
            .rfind('[')
            .is_some_and(|start| start > 0 && prefix.as_bytes()[start - 1] == b'!');
    let path = url.path().to_ascii_lowercase();
    markdown_image
        || matches!(
            path.rsplit('.').next(),
            Some("avif" | "gif" | "ico" | "jpeg" | "jpg" | "png" | "svg" | "webp")
        )
}

fn same_forum_host(actual: &str, expected: &str) -> bool {
    actual
        .strip_prefix("www.")
        .unwrap_or(actual)
        .eq_ignore_ascii_case(expected)
}

pub struct SourceRegistry {
    sources: BTreeMap<SourceKind, Box<dyn AssetSource>>,
    browser: BrowserAutomation,
    cdp: CdpAutomation,
}

impl SourceRegistry {
    pub fn new(client: ObservedHttpClient) -> Self {
        let browser = BrowserAutomation::new(client.clone());
        let cdp = CdpAutomation::new(client.clone());
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
        sources.insert(
            SourceKind::Shodan,
            Box::new(ShodanSource::new(client.clone())),
        );
        for specification in ForumSpecification::all() {
            sources.insert(
                specification.kind,
                Box::new(ForumSource::new(
                    client.clone(),
                    browser.clone(),
                    cdp.clone(),
                    specification,
                )),
            );
        }
        Self {
            sources,
            browser,
            cdp,
        }
    }

    pub fn configure_browser(
        &self,
        configuration: Option<BrowserAutomationConfiguration>,
    ) -> Result<(), String> {
        self.browser.configure(configuration)
    }

    pub fn browser_status(&self) -> BrowserAutomationStatus {
        self.browser.status()
    }

    pub fn configure_cdp(
        &self,
        configuration: Option<CdpBrowserConfiguration>,
    ) -> Result<(), String> {
        self.cdp.configure(configuration)
    }

    pub fn cdp_status(&self) -> CdpBrowserStatus {
        self.cdp.status()
    }

    pub async fn close_cdp(&self) {
        self.cdp.close_session().await;
    }

    pub async fn discover(
        &self,
        kind: SourceKind,
        request: &ScanRequest,
        credentials: &SourceCredentials,
    ) -> Result<SourceDiscovery, SourceError> {
        let source = self
            .sources
            .get(&kind)
            .ok_or_else(|| SourceError::Other(anyhow::anyhow!("未知扫描数据源")))?;
        let Some(tool) = source_tool_kind(kind) else {
            return source.discover(request, credentials).await;
        };
        let selection = credentials.begin(tool)?;
        let scoped = credentials.with_active_profile(selection.profile.clone());
        let result = source.discover(request, &scoped).await;
        selection.complete(result.is_ok());
        result
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
        let nodeseek = self
            .sources
            .get(&SourceKind::Nodeseek)
            .expect("内置 NodeSeek 数据源必须存在")
            .as_ref();
        let linux_do = self
            .sources
            .get(&SourceKind::LinuxDo)
            .expect("内置 LINUX DO 数据源必须存在")
            .as_ref();
        let v2ex = self
            .sources
            .get(&SourceKind::V2ex)
            .expect("内置 V2EX 数据源必须存在")
            .as_ref();
        let (github, gitee, gitcode, fofa, shodan, nodeseek, linux_do, v2ex) = futures::join!(
            quota_or_status(github, credentials),
            quota_or_status(gitee, credentials),
            quota_or_status(gitcode, credentials),
            quota_or_status(fofa, credentials),
            quota_or_status(shodan, credentials),
            quota_or_status(nodeseek, credentials),
            quota_or_status(linux_do, credentials),
            quota_or_status(v2ex, credentials),
        );
        vec![
            github, gitee, gitcode, fofa, shodan, nodeseek, linux_do, v2ex,
        ]
    }
}

async fn quota_or_status(source: &dyn AssetSource, credentials: &SourceCredentials) -> SourceQuota {
    let checked_at = Utc::now();
    let started = Instant::now();
    let selection = source_tool_kind(source.kind()).map(|tool| credentials.begin(tool));
    let result = match &selection {
        Some(Ok(selection)) => {
            let scoped = credentials.with_active_profile(selection.profile.clone());
            source.quota(&scoped).await
        }
        Some(Err(error)) => Err(SourceError::MissingCredential(match error {
            SourceError::MissingCredential(platform) => platform,
            _ => "扫描工具",
        })),
        None => source.quota(credentials).await,
    };
    if let Some(Ok(selection)) = selection {
        selection.complete(result.is_ok());
    }
    match result {
        Ok(mut quota) => {
            quota.checked_at = Some(checked_at);
            quota.latency_ms = Some(started.elapsed().as_millis().min(u64::MAX as u128) as u64);
            quota.last_success_at = Some(checked_at);
            quota
        }
        Err(error) => {
            let (http_status, error_code) = match &error {
                SourceError::MissingCredential(_) => (None, "missing_credential".to_owned()),
                SourceError::Http { status, .. } => (Some(*status), format!("http_{status}")),
                SourceError::Transport(_) => (None, "transport".to_owned()),
                SourceError::ResponseTooLarge { .. } => (None, "response_too_large".to_owned()),
                SourceError::InvalidResponse(_) => (None, "invalid_response".to_owned()),
                SourceError::ForumFetch { .. } => (None, "forum_fetch".to_owned()),
                SourceError::BrowserUnavailable => (None, "browser_unavailable".to_owned()),
                SourceError::Browser(_) => (None, "browser".to_owned()),
                SourceError::CdpUnavailable => (None, "cdp_unavailable".to_owned()),
                SourceError::Cdp(_) => (None, "cdp".to_owned()),
                SourceError::InvalidForumEntry(_) => (None, "invalid_forum_entry".to_owned()),
                SourceError::Other(_) => (None, "internal".to_owned()),
            };
            SourceQuota {
                source: source.kind(),
                configured: !matches!(&error, SourceError::MissingCredential(_)),
                available: false,
                remaining: None,
                limit: None,
                resets_at: None,
                message: error.to_string(),
                checked_at: Some(checked_at),
                latency_ms: Some(started.elapsed().as_millis().min(u64::MAX as u128) as u64),
                http_status,
                error_code: Some(error_code),
                last_success_at: None,
                last_failure_at: Some(checked_at),
            }
        }
    }
}

fn source_tool_kind(source: SourceKind) -> Option<SourceToolKind> {
    match source {
        SourceKind::Github | SourceKind::GithubArtifact => Some(SourceToolKind::Github),
        SourceKind::Gitee => Some(SourceToolKind::Gitee),
        SourceKind::Gitcode => Some(SourceToolKind::Gitcode),
        SourceKind::Fofa => Some(SourceToolKind::Fofa),
        SourceKind::Shodan => Some(SourceToolKind::Shodan),
        SourceKind::Manual | SourceKind::Nodeseek | SourceKind::LinuxDo | SourceKind::V2ex => None,
    }
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
    ) -> Result<SourceDiscovery, SourceError> {
        Ok(SourceDiscovery::new(
            request
                .targets
                .iter()
                .take(MAX_SOURCE_RESULTS)
                .map(|target| Candidate {
                    source: SourceKind::Manual,
                    target: target.clone(),
                    discovered_at: Utc::now(),
                    metadata: BTreeMap::new(),
                })
                .collect(),
        ))
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

    /// 以多 token 故障转移方式发起一次 GitHub 代码检索：命中限速(403/429)即切换下一 token，
    /// 无等待、最多尝试 token 数量次并推进轮询游标。
    /// Ok(Some) 成功、Ok(None) 全部 token 被限速、Err 传输错误。
    async fn search_page(
        &self,
        query: &str,
        per_page: &str,
        page: &str,
        tokens: &[String],
        cursor: &mut usize,
    ) -> Result<Option<Response>, SourceError> {
        for _ in 0..tokens.len() {
            let token = &tokens[*cursor % tokens.len()];
            let response = self
                .client
                .get("https://api.github.com/search/code")
                .header("Accept", "application/vnd.github+json")
                .header("X-GitHub-Api-Version", "2022-11-28")
                .bearer_auth(token)
                .query(&[("q", query), ("per_page", per_page), ("page", page)])
                .send()
                .await
                .map_err(|_| SourceError::Transport("GitHub"))?;
            if matches!(
                response.status(),
                StatusCode::FORBIDDEN | StatusCode::TOO_MANY_REQUESTS
            ) {
                *cursor = cursor.wrapping_add(1);
                continue;
            }
            return Ok(Some(response));
        }
        Ok(None)
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
    #[serde(default)]
    repository: Option<GithubRepositoryRef>,
}

#[derive(Deserialize)]
struct GithubRepositoryRef {
    #[serde(default)]
    private: Option<bool>,
    #[serde(default)]
    visibility: Option<String>,
}

impl GithubCodeItem {
    /// fail-closed：仅在仓库明确公开时才纳入检索结果；字段缺失一律按私有跳过，
    /// 避免凭证具备私库权限时把私有仓库内容拉入扫描。
    fn is_public(&self) -> bool {
        match &self.repository {
            Some(repository) => {
                repository.private == Some(false)
                    || repository.visibility.as_deref() == Some("public")
            }
            None => false,
        }
    }
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
    ) -> Result<SourceDiscovery, SourceError> {
        let credential = credentials
            .active_profile()?
            .value("token")
            .ok_or(SourceError::MissingCredential("GitHub"))?;
        // 支持在同一字段填入多把 token（逗号/空白分隔），用于轮询与限速故障转移。
        let tokens = parse_credential_list(credential);
        if tokens.is_empty() {
            return Err(SourceError::MissingCredential("GitHub"));
        }
        let mut token_cursor = 0_usize;
        let query_key = if self.kind == SourceKind::GithubArtifact {
            "github_artifact"
        } else {
            "github"
        };
        let query = source_query(request, query_key)
            .or_else(|| source_query(request, "github"))
            .unwrap_or_else(|| default_github_query(request));
        let per_page = DEFAULT_PAGE_SIZE.to_string();
        // fail-closed 过滤非公开仓库；有界分页跨页累积公开检索项，首页错误上抛、
        // 后续页错误保留已得项；页间延时；累积上限约束后续内容拉取对 GitHub API 的用量。
        let mut public_items = Vec::new();
        let mut skipped_private = 0_usize;
        for page in 1..=MAX_DISCOVERY_PAGES {
            if page > 1 {
                tokio::time::sleep(DISCOVERY_PAGE_DELAY).await;
            }
            let page_str = page.to_string();
            let response = match self
                .search_page(
                    query.as_str(),
                    per_page.as_str(),
                    page_str.as_str(),
                    &tokens,
                    &mut token_cursor,
                )
                .await
            {
                Ok(Some(response)) => response,
                // 全部 token 均被限速：首页视为不可用，后续页保留已获取结果。
                Ok(None) if page == 1 => {
                    return Err(SourceError::Http {
                        platform: "GitHub",
                        status: StatusCode::TOO_MANY_REQUESTS.as_u16(),
                    });
                }
                Ok(None) => break,
                Err(_) if page == 1 => return Err(SourceError::Transport("GitHub")),
                Err(_) => break,
            };
            let http_status = response.status();
            if !http_status.is_success() {
                if page == 1 {
                    ensure_success("GitHub", http_status)?;
                }
                break;
            }
            let search = match parse_json_limited::<GithubSearchResponse>("GitHub", response).await
            {
                Ok(search) => search,
                Err(error) if page == 1 => return Err(error),
                Err(_) => break,
            };
            let item_count = search.items.len();
            for item in search.items {
                if item.is_public() {
                    if public_items.len() < MAX_GITHUB_SEARCH_RESULTS {
                        public_items.push(item);
                    }
                } else {
                    skipped_private += 1;
                }
            }
            if public_items.len() >= MAX_GITHUB_SEARCH_RESULTS || item_count < DEFAULT_PAGE_SIZE {
                break;
            }
        }
        let client = self.client.clone();
        let kind = self.kind;
        // 逐项内容拉取按 token 轮询分摊，进一步降低单 token 触发限速的概率。
        let batches = stream::iter(public_items.into_iter().enumerate().map(|(index, item)| {
            let client = client.clone();
            let token = tokens[index % tokens.len()].clone();
            async move { github_item_candidates(client, kind, token, item).await }
        }))
        .buffer_unordered(GITHUB_CONTENT_CONCURRENCY);
        futures::pin_mut!(batches);
        let mut candidates = Vec::new();
        let mut fetch_failures = 0_usize;
        'collect: while let Some((batch, fetch_failed)) = batches.next().await {
            if fetch_failed {
                fetch_failures += 1;
            }
            for candidate in batch {
                candidates.push(candidate);
                if candidates.len() >= MAX_SOURCE_RESULTS {
                    break 'collect;
                }
            }
        }
        let mut discovery = SourceDiscovery::new(candidates);
        if skipped_private > 0 {
            discovery.warnings.push(format!(
                "已按 fail-closed 安全策略跳过 {skipped_private} 个非公开仓库的检索结果。"
            ));
        }
        if fetch_failures > 0 {
            discovery.warnings.push(format!(
                "有 {fetch_failures} 个 GitHub 检索结果的内容拉取失败，已跳过。"
            ));
        }
        Ok(discovery)
    }

    async fn quota(&self, credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        let credential = credentials
            .active_profile()?
            .value("token")
            .ok_or(SourceError::MissingCredential("GitHub"))?;
        // 多 token 场景取首把校验配额，避免把逗号分隔的整串当作单一 token 发送。
        let token = parse_credential_list(credential)
            .into_iter()
            .next()
            .ok_or(SourceError::MissingCredential("GitHub"))?;
        let response = self
            .client
            .get("https://api.github.com/rate_limit")
            .header("Accept", "application/vnd.github+json")
            .bearer_auth(&token)
            .send()
            .await
            .map_err(|_| SourceError::Transport("GitHub"))?;
        let http_status = response.status();
        ensure_success("GitHub", http_status)?;
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
            checked_at: None,
            latency_ms: None,
            http_status: Some(http_status.as_u16()),
            error_code: None,
            last_success_at: None,
            last_failure_at: None,
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

    fn token<'a>(&self, credentials: &'a SourceCredentials) -> Option<&'a str> {
        credentials.active_profile().ok()?.value("token")
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
    ) -> Result<SourceDiscovery, SourceError> {
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
        let repositories = self.repositories_for_query(&query, token).await?;
        let source = self.clone_for_tasks();
        let token = token.to_owned();
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
        let mut repository_failures = 0_usize;
        'collect: while let Some((batch, fetch_failed)) = batches.next().await {
            if fetch_failed {
                repository_failures += 1;
            }
            for candidate in batch {
                candidates.push(candidate);
                if candidates.len() >= MAX_SOURCE_RESULTS {
                    break 'collect;
                }
            }
        }
        let mut discovery = SourceDiscovery::new(candidates);
        if repository_failures > 0 {
            discovery.warnings.push(format!(
                "有 {repository_failures} 个 {} 仓库的内容拉取失败，已跳过。",
                self.platform
            ));
        }
        Ok(discovery)
    }

    async fn quota(&self, credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        let token = self
            .token(credentials)
            .ok_or(SourceError::MissingCredential(self.platform))?;
        let response = self
            .authorized_get(format!("{}/user", self.api_base), token)
            .send()
            .await
            .map_err(|_| SourceError::Transport(self.platform))?;
        let http_status = response.status();
        ensure_success(self.platform, http_status)?;
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
            checked_at: None,
            latency_ms: None,
            http_status: Some(http_status.as_u16()),
            error_code: None,
            last_success_at: None,
            last_failure_at: None,
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
    ) -> (Vec<Candidate>, bool) {
        // 返回 (候选, 是否仓库拉取失败)：树结构拉取的传输/非 2xx/解析失败计为失败并上报，
        // 仓库元数据缺失只作跳过、不计失败。
        let full_name = match repository.full_name {
            Some(value) if !value.trim().is_empty() => value.trim().to_owned(),
            _ => return (Vec::new(), false),
        };
        let branch = match repository.default_branch {
            Some(value) if !value.trim().is_empty() => value.trim().to_owned(),
            _ => return (Vec::new(), false),
        };
        let Some((owner, name)) = full_name.rsplit_once('/') else {
            return (Vec::new(), false);
        };
        if owner.is_empty() || name.is_empty() {
            return (Vec::new(), false);
        }
        let Ok(response) = self
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
        else {
            return (Vec::new(), true);
        };
        if !response.status().is_success() {
            return (Vec::new(), true);
        }
        let Ok(tree) = parse_json_limited::<GitTreeResponse>(self.platform, response).await else {
            return (Vec::new(), true);
        };
        let mut files = tree
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
        (candidates, false)
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

    /// 以多 key 故障转移方式发起一次 FOFA 检索（共用同一 email）：命中 401/403/429 或
    /// 响应体 error=true（key 无效/额度不足）即切换下一 key，无等待、最多尝试 key 数量次。
    /// 成功返回 error=false 的响应体；全部 key 失败时返回带最后原因的错误以便观测。
    async fn search_page(
        &self,
        email: &str,
        encoded_query: &str,
        size: &str,
        page: &str,
        keys: &[String],
        cursor: &mut usize,
    ) -> Result<FofaSearchResponse, SourceError> {
        let mut last_reason = None;
        for _ in 0..keys.len() {
            let key = &keys[*cursor % keys.len()];
            let response = self
                .client
                .get("https://fofa.info/api/v1/search/all")
                .query(&[
                    ("email", email),
                    ("key", key.as_str()),
                    ("qbase64", encoded_query),
                    ("size", size),
                    ("page", page),
                    (
                        "fields",
                        "host,ip,port,protocol,title,header,banner,server,product,link,domain,cert",
                    ),
                ])
                .send()
                .await
                .map_err(|_| SourceError::Transport("FOFA"))?;
            let status = response.status();
            if matches!(
                status,
                StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN | StatusCode::TOO_MANY_REQUESTS
            ) {
                last_reason = Some(format!("HTTP {}", status.as_u16()));
                *cursor = cursor.wrapping_add(1);
                continue;
            }
            if !status.is_success() {
                return Err(SourceError::Http {
                    platform: "FOFA",
                    status: status.as_u16(),
                });
            }
            let body = parse_json_limited::<FofaSearchResponse>("FOFA", response).await?;
            if body.error {
                last_reason = Some(body.errmsg.unwrap_or_else(|| "未知错误".to_owned()));
                *cursor = cursor.wrapping_add(1);
                continue;
            }
            return Ok(body);
        }
        Err(SourceError::Other(anyhow::anyhow!(
            "FOFA 所有 key 均不可用：{}",
            last_reason.unwrap_or_else(|| "额度不足/限速/无效".to_owned())
        )))
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
    ) -> Result<SourceDiscovery, SourceError> {
        let (email, key) = fofa_credentials(credentials)?;
        // 支持在 key 字段填入多把 key（逗号/空白分隔），共用同一 email 做 fcoin 池化与故障转移。
        let keys = parse_credential_list(key);
        if keys.is_empty() {
            return Err(SourceError::MissingCredential("FOFA"));
        }
        let mut key_cursor = 0_usize;
        let query = source_query(request, "fofa").unwrap_or_else(|| default_fofa_query(request));
        let encoded_query = STANDARD.encode(query);
        let size = DEFAULT_PAGE_SIZE.to_string();
        let mut candidates = Vec::new();
        // 有界分页 + 多 key 故障转移：首页错误视为数据源不可用向上返回，后续页错误保留已获取结果，
        // 页间延时并受 MAX_SOURCE_RESULTS 上界约束，避免丢弃已得数据与无限翻页。
        for page in 1..=MAX_DISCOVERY_PAGES {
            if page > 1 {
                tokio::time::sleep(DISCOVERY_PAGE_DELAY).await;
            }
            let page_str = page.to_string();
            let body = match self
                .search_page(
                    email,
                    &encoded_query,
                    size.as_str(),
                    page_str.as_str(),
                    &keys,
                    &mut key_cursor,
                )
                .await
            {
                Ok(body) => body,
                Err(error) if page == 1 => return Err(error),
                Err(_) => break,
            };
            let page_len = body.results.len();
            candidates.extend(body.results.into_iter().filter_map(|row| {
                let target = row.first().and_then(value_as_string)?;
                let mut metadata = BTreeMap::new();
                // 将 FOFA 历史快照中的 title/header/banner/server/product 拼接为
                // artifact_text，供探测阶段的正则提取直接消费引擎爬虫缓存内容，
                // 不必依赖"目标现在仍在暴露"这一脆弱假设。
                let artifact_parts: Vec<&str> = [4, 5, 6, 7, 8]
                    .iter()
                    .filter_map(|&i| row.get(i).and_then(|v| v.as_str()))
                    .filter(|s| !s.is_empty())
                    .collect();
                if !artifact_parts.is_empty() {
                    metadata.insert(
                        CANDIDATE_ARTIFACT_TEXT_KEY.to_owned(),
                        artifact_parts.join("\n"),
                    );
                }
                Some(Candidate {
                    source: SourceKind::Fofa,
                    target,
                    discovered_at: Utc::now(),
                    metadata,
                })
            }));
            if candidates.len() >= MAX_SOURCE_RESULTS || page_len < DEFAULT_PAGE_SIZE {
                break;
            }
        }
        candidates.truncate(MAX_SOURCE_RESULTS);
        Ok(SourceDiscovery::new(candidates))
    }

    async fn quota(&self, credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        let (email, key) = fofa_credentials(credentials)?;
        // 多 key 场景取首把校验账户，避免把逗号分隔的整串当作单一 key 发送。
        let key = parse_credential_list(key)
            .into_iter()
            .next()
            .ok_or(SourceError::MissingCredential("FOFA"))?;
        let response = self
            .client
            .get("https://fofa.info/api/v1/info/my")
            .query(&[("email", email), ("key", key.as_str())])
            .send()
            .await
            .map_err(|_| SourceError::Transport("FOFA"))?;
        let http_status = response.status();
        ensure_success("FOFA", http_status)?;
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
            checked_at: None,
            latency_ms: None,
            http_status: Some(http_status.as_u16()),
            error_code: None,
            last_success_at: None,
            last_failure_at: None,
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

    /// 以多 key 故障转移方式发起一次 Shodan 检索：命中 401/403/429(鉴权失败/信用不足/限速)
    /// 即切换下一 key，无等待、最多尝试 key 数量次并推进轮询游标。
    async fn search_page(
        &self,
        query: &str,
        page: &str,
        keys: &[String],
        cursor: &mut usize,
    ) -> Result<Option<Response>, SourceError> {
        for _ in 0..keys.len() {
            let key = &keys[*cursor % keys.len()];
            let response = self
                .client
                .get("https://api.shodan.io/shodan/host/search")
                .query(&[("key", key.as_str()), ("query", query), ("page", page)])
                .send()
                .await
                .map_err(|_| SourceError::Transport("Shodan"))?;
            if matches!(
                response.status(),
                StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN | StatusCode::TOO_MANY_REQUESTS
            ) {
                *cursor = cursor.wrapping_add(1);
                continue;
            }
            return Ok(Some(response));
        }
        Ok(None)
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
    /// Shodan 的 banner 原始内容（HTTP 响应头+体、SSH banner 等）。
    data: Option<String>,
    /// HTTP 模块返回的子结构，包含 title 和 html 字段。
    http: Option<ShodanHttp>,
    product: Option<String>,
}

#[derive(Deserialize)]
struct ShodanHttp {
    title: Option<String>,
    html: Option<String>,
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
    ) -> Result<SourceDiscovery, SourceError> {
        let key = credentials
            .active_profile()?
            .value("key")
            .ok_or(SourceError::MissingCredential("Shodan"))?;
        // 支持在同一字段填入多把 key（逗号/空白分隔）用于信用池化与限速故障转移。
        let keys = parse_credential_list(key);
        if keys.is_empty() {
            return Err(SourceError::MissingCredential("Shodan"));
        }
        let mut key_cursor = 0_usize;
        let query =
            source_query(request, "shodan").unwrap_or_else(|| default_shodan_query(request));
        let mut candidates = Vec::new();
        // 有界分页 + 多 key 故障转移：首页错误上抛，后续页错误保留已得结果；页间延时。
        for page in 1..=MAX_DISCOVERY_PAGES {
            if page > 1 {
                tokio::time::sleep(DISCOVERY_PAGE_DELAY).await;
            }
            let page_str = page.to_string();
            let response = match self
                .search_page(query.as_str(), page_str.as_str(), &keys, &mut key_cursor)
                .await
            {
                Ok(Some(response)) => response,
                Ok(None) if page == 1 => {
                    return Err(SourceError::Http {
                        platform: "Shodan",
                        status: StatusCode::TOO_MANY_REQUESTS.as_u16(),
                    });
                }
                Ok(None) => break,
                Err(_) if page == 1 => return Err(SourceError::Transport("Shodan")),
                Err(_) => break,
            };
            let http_status = response.status();
            if !http_status.is_success() {
                if page == 1 {
                    ensure_success("Shodan", http_status)?;
                }
                break;
            }
            let body = match parse_json_limited::<ShodanSearchResponse>("Shodan", response).await {
                Ok(body) => body,
                Err(error) if page == 1 => return Err(error),
                Err(_) => break,
            };
            let match_count = body.matches.len();
            candidates.extend(body.matches.into_iter().flat_map(|item| {
                let scheme = if item.ssl.is_some() || matches!(item.port, 443 | 8443 | 9443) {
                    "https"
                } else {
                    "http"
                };
                let transport = item.transport.unwrap_or_else(|| "tcp".to_owned());
                // 拼接 Shodan 历史快照中的 banner/title/product 作为 artifact_text，
                // 使探测阶段可直接对爬虫缓存做正则提取。
                let artifact_parts: Vec<&str> = [
                    item.data.as_deref(),
                    item.http.as_ref().and_then(|h| h.title.as_deref()),
                    item.http.as_ref().and_then(|h| h.html.as_deref()),
                    item.product.as_deref(),
                ]
                .into_iter()
                .flatten()
                .filter(|s| !s.is_empty())
                .collect();
                let artifact_text = if artifact_parts.is_empty() {
                    None
                } else {
                    Some(artifact_parts.join("\n"))
                };
                let mut hosts = vec![item.ip_str];
                hosts.extend(item.hostnames.unwrap_or_default().into_iter().take(5));
                hosts.sort();
                hosts.dedup();
                hosts.into_iter().map(move |host| {
                    let mut metadata =
                        BTreeMap::from([("transport".to_owned(), transport.clone())]);
                    if let Some(ref text) = artifact_text {
                        metadata.insert(CANDIDATE_ARTIFACT_TEXT_KEY.to_owned(), text.clone());
                    }
                    Candidate {
                        source: SourceKind::Shodan,
                        target: format!("{scheme}://{host}:{}", item.port),
                        discovered_at: Utc::now(),
                        metadata,
                    }
                })
            }));
            if candidates.len() >= MAX_SOURCE_RESULTS || match_count < DEFAULT_PAGE_SIZE {
                break;
            }
        }
        candidates.truncate(MAX_SOURCE_RESULTS);
        Ok(SourceDiscovery::new(candidates))
    }

    async fn quota(&self, credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        let key = credentials
            .active_profile()?
            .value("key")
            .ok_or(SourceError::MissingCredential("Shodan"))?;
        // 多 key 场景取首把校验配额，避免把逗号分隔的整串当作单一 key 发送。
        let key = parse_credential_list(key)
            .into_iter()
            .next()
            .ok_or(SourceError::MissingCredential("Shodan"))?;
        let response = self
            .client
            .get("https://api.shodan.io/api-info")
            .query(&[("key", key.as_str())])
            .send()
            .await
            .map_err(|_| SourceError::Transport("Shodan"))?;
        let http_status = response.status();
        ensure_success("Shodan", http_status)?;
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
            checked_at: None,
            latency_ms: None,
            http_status: Some(http_status.as_u16()),
            error_code: None,
            last_success_at: None,
            last_failure_at: None,
        })
    }
}

async fn github_item_candidates(
    client: ObservedHttpClient,
    kind: SourceKind,
    token: String,
    item: GithubCodeItem,
) -> (Vec<Candidate>, bool) {
    // 返回 (候选, 是否拉取失败)：区分“内容拉取失败”与“拉取成功但无命中”，
    // 使上层可对失败计数并告警，避免扫描无结果时无从诊断。
    let Ok(response) = client
        .get(&item.url)
        .header("Accept", "application/vnd.github+json")
        .header("X-GitHub-Api-Version", "2022-11-28")
        .bearer_auth(token)
        .send()
        .await
    else {
        return (Vec::new(), true);
    };
    if !response.status().is_success() {
        return (Vec::new(), true);
    }
    let Ok(content) = parse_json_limited::<GithubContentResponse>("GitHub", response).await else {
        return (Vec::new(), true);
    };
    let decoded = match (content.encoding.as_deref(), content.content.as_deref()) {
        (Some("base64"), Some(value)) => match STANDARD.decode(value.replace('\n', "")) {
            Ok(bytes) => bytes,
            Err(_) => return (Vec::new(), true),
        },
        _ => return (Vec::new(), false),
    };
    if decoded.len() > MAX_GITHUB_FILE_BYTES {
        return (Vec::new(), false);
    }
    let text = String::from_utf8_lossy(&decoded);
    let candidates = URL_PATTERN
        .find_iter(&text)
        .take(50)
        .map(|url| {
            let mut metadata =
                BTreeMap::from([(CANDIDATE_ARTIFACT_URL_KEY.to_owned(), item.html_url.clone())]);
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
        .collect();
    (candidates, false)
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

async fn parse_text_limited(
    platform: &'static str,
    response: Response,
) -> Result<String, SourceError> {
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
    String::from_utf8(body).map_err(|_| SourceError::InvalidResponse(platform))
}

async fn parse_jina_content(
    platform: &'static str,
    response: Response,
) -> Result<String, SourceError> {
    let raw = parse_text_limited(platform, response).await?;
    let trimmed = raw.trim();
    if let Ok(json) = serde_json::from_str::<serde_json::Value>(trimmed) {
        return jina_json_content(&json)
            .filter(|content| !content.trim().is_empty())
            .ok_or(SourceError::InvalidResponse(platform));
    }
    if trimmed.lines().any(|line| line.starts_with("data:")) {
        let content = trimmed
            .lines()
            .filter_map(|line| line.strip_prefix("data:").map(str::trim))
            .filter(|line| !line.is_empty() && *line != "[DONE]")
            .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
            .filter_map(|value| jina_json_content(&value))
            .collect::<Vec<_>>()
            .join("\n");
        if !content.trim().is_empty() {
            return Ok(content);
        }
    }
    Ok(raw)
}

fn jina_json_content(value: &serde_json::Value) -> Option<String> {
    value
        .pointer("/data/content")
        .or_else(|| value.pointer("/data/text"))
        .or_else(|| value.get("content"))
        .or_else(|| value.get("text"))
        .and_then(serde_json::Value::as_str)
        .map(ToOwned::to_owned)
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
    if request.mode == ScanMode::Full && request.authorized_scope.is_empty() {
        return "api_key OR authorization OR /v1/models".to_owned();
    }
    let scope = request
        .authorized_scope
        .first()
        .cloned()
        .unwrap_or_default();
    format!("\"{scope}\" (api_key OR authorization OR /v1/models)")
}

fn default_fofa_query(request: &ScanRequest) -> String {
    if request.mode == ScanMode::Full && request.authorized_scope.is_empty() {
        return "title=\"OpenAI\" || title=\"Anthropic\" || title=\"Gemini\"".to_owned();
    }
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
    if request.mode == ScanMode::Full && request.authorized_scope.is_empty() {
        return "http.title:\"OpenAI\" OR http.title:\"Anthropic\" OR http.title:\"Gemini\""
            .to_owned();
    }
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

fn fofa_credentials(credentials: &SourceCredentials) -> Result<(&str, &str), SourceError> {
    let profile = credentials.active_profile()?;
    Ok((
        profile
            .value("email")
            .ok_or(SourceError::MissingCredential("FOFA"))?,
        profile
            .value("key")
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

/// 将单个凭证字符串解析为多凭证列表：按逗号/空白切分、去空白、去重且保序。
/// 允许在同一输入框填入多把 key，配合轮询与限速故障转移提升稳健性。
/// 数量以 MAX_CREDENTIAL_KEYS 封顶，避免误粘贴海量 key 引发单页大量故障转移请求。
fn parse_credential_list(secret: &str) -> Vec<String> {
    let mut seen = BTreeSet::new();
    secret
        .split(|character: char| character == ',' || character.is_whitespace())
        .map(str::trim)
        .filter(|value| !value.is_empty() && seen.insert(value.to_owned()))
        .take(MAX_CREDENTIAL_KEYS)
        .map(ToOwned::to_owned)
        .collect()
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
        checked_at: None,
        latency_ms: None,
        http_status: None,
        error_code: None,
        last_success_at: None,
        last_failure_at: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scan_request(mode: ScanMode, authorized_scope: Vec<String>) -> ScanRequest {
        ScanRequest {
            name: "测试任务".to_owned(),
            sources: vec![SourceKind::Github],
            mode,
            authorized_scope,
            authorization_confirmed: true,
            targets: Vec::new(),
            vendors: Vec::new(),
            source_queries: BTreeMap::new(),
            forum_fetch_mode: Default::default(),
            validation_mode: Default::default(),
            concurrency: 1,
            gpt_assisted: false,
        }
    }

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

    struct FallbackObserver {
        primary_client: Client,
        fallback_count: std::sync::atomic::AtomicUsize,
        outcomes: std::sync::Mutex<Vec<HttpRequestOutcome>>,
    }

    impl HttpRequestObserver for FallbackObserver {
        fn begin(&self, _target: &reqwest::Url) -> reqwest::Result<Option<HttpRequestObservation>> {
            Ok(Some(HttpRequestObservation {
                ticket: Some(1),
                client: self.primary_client.clone(),
            }))
        }

        fn begin_fallback(
            &self,
            _request: &reqwest::Request,
        ) -> reqwest::Result<Option<HttpRequestObservation>> {
            self.fallback_count
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            Ok(None)
        }

        fn complete(&self, _ticket: Option<u64>, _elapsed: Duration, outcome: HttpRequestOutcome) {
            self.outcomes.lock().unwrap().push(outcome);
        }
    }

    fn fallback_observer() -> Arc<FallbackObserver> {
        ensure_rustls_crypto_provider();
        let proxy = reqwest::Proxy::all("http://127.0.0.1:1").unwrap();
        Arc::new(FallbackObserver {
            primary_client: Client::builder().no_proxy().proxy(proxy).build().unwrap(),
            fallback_count: std::sync::atomic::AtomicUsize::new(0),
            outcomes: std::sync::Mutex::new(Vec::new()),
        })
    }

    fn tool_credentials(strategy: ToolSelectionStrategy) -> SourceCredentials {
        SourceCredentials::from_configurations(vec![ToolConfigurationInput {
            tool: SourceToolKind::Github,
            enabled: true,
            strategy,
            profiles: ["profile-a", "profile-b"]
                .into_iter()
                .map(|id| ToolProfileInput {
                    id: id.to_owned(),
                    name: id.to_owned(),
                    enabled: true,
                    values: BTreeMap::from([("token".to_owned(), id.to_owned())]),
                })
                .collect(),
        }])
    }

    async fn local_response(content_type: &str, body: &str) -> Response {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};

        let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .unwrap();
        let address = listener.local_addr().unwrap();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut request = [0_u8; 1024];
            let _ = stream.read(&mut request).await.unwrap();
            stream.write_all(response.as_bytes()).await.unwrap();
        });
        ensure_rustls_crypto_provider();
        let response = Client::builder()
            .no_proxy()
            .build()
            .unwrap()
            .get(format!("http://{address}/"))
            .send()
            .await
            .unwrap();
        server.await.unwrap();
        response
    }

    fn cdp_capture() -> CdpNetworkCapture {
        CdpNetworkCapture {
            requests: Vec::new(),
            request_bytes: 0,
            responses: Vec::new(),
            loaded: false,
            last_network_event: Instant::now(),
        }
    }

    #[test]
    fn cdp_capture_redacts_browser_credentials() {
        let mut capture = cdp_capture();
        capture.observe(&serde_json::json!({
            "method": "Network.requestWillBeSent",
            "params": {
                "request": {
                    "url": "https://linux.do/session",
                    "method": "POST",
                    "headers": {
                        "Accept": "application/json",
                        "Authorization": "Bearer secret",
                        "Cookie": "session=secret",
                        "X-Api-Key": "secret"
                    },
                    "postData": "query=offer"
                }
            }
        }));
        let request = capture.requests.join("\n");
        assert!(request.contains("Accept: application/json"));
        assert!(request.contains("请求正文：query=offer"));
        assert!(!request.contains("Bearer secret"));
        assert!(!request.contains("session=secret"));
        assert!(!request.contains("X-Api-Key"));
    }

    #[test]
    fn cdp_proxy_keeps_credentials_out_of_process_arguments() {
        let proxy = cdp_proxy_input(&Url::parse("http://user:secret@127.0.0.1:8080").unwrap());
        assert_eq!(proxy.server, "http://127.0.0.1:8080");
        assert_eq!(proxy.username.as_deref(), Some("user"));
        assert_eq!(proxy.password.as_deref(), Some("secret"));
        assert!(!proxy.server.contains("secret"));
    }

    #[test]
    fn cdp_render_includes_dom_requests_and_response_bodies() {
        let mut capture = cdp_capture();
        capture
            .requests
            .push("GET https://linux.do/api/topic".to_owned());
        capture.responses.push(CdpResponseCapture {
            request_id: "42".to_owned(),
            url: "https://linux.do/api/topic".to_owned(),
            status: 200,
            mime_type: "application/json".to_owned(),
            headers: "content-type: application/json".to_owned(),
        });
        let content = render_cdp_content(
            CdpDomSnapshot {
                title: "LINUX DO".to_owned(),
                text: "页面正文".to_owned(),
                links: vec!["https://example.com/resource".to_owned()],
            },
            &capture,
            &BTreeMap::from([("42".to_owned(), "{\"token\":\"value\"}".to_owned())]),
        );
        assert!(content.contains("LINUX DO"));
        assert!(content.contains("GET https://linux.do/api/topic"));
        assert!(content.contains("HTTP 200 https://linux.do/api/topic"));
        assert!(content.contains("{\"token\":\"value\"}"));
    }

    #[test]
    fn round_robin_rotates_tool_profiles() {
        let credentials = tool_credentials(ToolSelectionStrategy::RoundRobin);
        let first = credentials.begin(SourceToolKind::Github).unwrap();
        assert_eq!(first.profile.id, "profile-a");
        first.complete(true);
        let second = credentials.begin(SourceToolKind::Github).unwrap();
        assert_eq!(second.profile.id, "profile-b");
        second.complete(true);
    }

    #[test]
    fn least_used_prefers_profile_with_fewer_requests() {
        let credentials = tool_credentials(ToolSelectionStrategy::LeastUsed);
        let first = credentials.begin(SourceToolKind::Github).unwrap();
        assert_eq!(first.profile.id, "profile-a");
        first.complete(true);
        let second = credentials.begin(SourceToolKind::Github).unwrap();
        assert_eq!(second.profile.id, "profile-b");
        second.complete(true);
    }

    #[test]
    fn least_busy_reclaims_cancelled_selection() {
        let credentials = tool_credentials(ToolSelectionStrategy::LeastBusy);
        let first = credentials.begin(SourceToolKind::Github).unwrap();
        let first_id = first.profile.id.clone();
        let second = credentials.begin(SourceToolKind::Github).unwrap();
        assert_ne!(first_id, second.profile.id);
        second.complete(true);
        drop(first);

        let runtimes = credentials.runtime.lock().unwrap();
        let statistics = &runtimes[&SourceToolKind::Github].profiles[&first_id];
        assert_eq!(statistics.in_flight, 0);
        assert_eq!(statistics.failures, 1);
    }

    #[test]
    fn highest_success_rate_reuses_successful_profile() {
        let credentials = tool_credentials(ToolSelectionStrategy::HighestSuccessRate);
        let first = credentials.begin(SourceToolKind::Github).unwrap();
        let successful_id = first.profile.id.clone();
        first.complete(true);
        let second = credentials.begin(SourceToolKind::Github).unwrap();
        assert_eq!(second.profile.id, successful_id);
        second.complete(true);
    }

    #[test]
    fn builds_jina_post_request_with_official_fields() {
        ensure_rustls_crypto_provider();
        let observer = Arc::new(CompletionObserver::default());
        let client = ObservedHttpClient::new(Client::new(), observer);
        let profile = ToolProfile {
            id: "jina".to_owned(),
            values: BTreeMap::from([
                ("token".to_owned(), SecretString::from("secret".to_owned())),
                (
                    "returnFormat".to_owned(),
                    SecretString::from("html".to_owned()),
                ),
                (
                    "respondWith".to_owned(),
                    SecretString::from("readerlm-v2".to_owned()),
                ),
                ("dnt".to_owned(), SecretString::from("true".to_owned())),
                (
                    "storageState".to_owned(),
                    SecretString::from(r#"{"cookies":[],"origins":[]}"#.to_owned()),
                ),
            ]),
        };
        let request = jina_request(
            &client,
            &Url::parse("https://linux.do/c/welfare/36").unwrap(),
            &profile,
        )
        .unwrap()
        .request
        .build()
        .unwrap();

        assert_eq!(request.method(), reqwest::Method::POST);
        assert_eq!(request.url().as_str(), JINA_READER_ENDPOINT);
        assert_eq!(request.headers()["X-Return-Format"], "html");
        assert_eq!(request.headers()["X-Respond-With"], "readerlm-v2");
        assert_eq!(request.headers()["DNT"], "1");
        assert_eq!(request.headers()["Authorization"], "Bearer secret");
        let body: serde_json::Value =
            serde_json::from_slice(request.body().and_then(reqwest::Body::as_bytes).unwrap())
                .unwrap();
        assert_eq!(body["url"], "https://linux.do/c/welfare/36");
        assert_eq!(body["storageState"]["cookies"], serde_json::json!([]));
    }

    #[tokio::test]
    async fn extracts_jina_json_and_sse_content() {
        let json =
            local_response("application/json", r#"{"data":{"content":"json content"}}"#).await;
        assert_eq!(
            parse_jina_content("Jina Reader", json).await.unwrap(),
            "json content"
        );

        let sse = local_response(
            "text/event-stream",
            "data: {\"data\":{\"content\":\"first\"}}\n\ndata: {\"content\":\"second\"}\n\ndata: [DONE]\n",
        )
        .await;
        assert_eq!(
            parse_jina_content("Jina Reader", sse).await.unwrap(),
            "first\nsecond"
        );
    }

    #[test]
    fn accepts_fofa_error_without_results() {
        let response: FofaSearchResponse =
            serde_json::from_str(r#"{"error":true,"errmsg":"额度不足"}"#).unwrap();
        assert!(response.error);
        assert!(response.results.is_empty());
    }

    #[test]
    fn full_scan_defaults_do_not_depend_on_authorized_scope() {
        let request = scan_request(ScanMode::Full, Vec::new());
        assert_eq!(
            default_github_query(&request),
            "api_key OR authorization OR /v1/models"
        );
        assert!(!default_fofa_query(&request).is_empty());
        assert!(!default_shodan_query(&request).is_empty());
    }

    #[test]
    fn incremental_defaults_remain_limited_to_authorized_scope() {
        let request = scan_request(ScanMode::Incremental, vec!["example.com".to_owned()]);
        assert!(default_github_query(&request).contains("example.com"));
        assert_eq!(default_fofa_query(&request), "domain=\"example.com\"");
        assert_eq!(default_shodan_query(&request), "hostname:example.com");
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

    #[tokio::test]
    async fn retries_idempotent_request_through_fallback_route() {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};

        let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut request = [0_u8; 1024];
            let _ = stream.read(&mut request).await.unwrap();
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
                .await
                .unwrap();
        });
        let observer = fallback_observer();
        let client = ObservedHttpClient::new(
            Client::builder().no_proxy().build().unwrap(),
            observer.clone(),
        );

        let response = client
            .get(format!("http://{address}/probe"))
            .send()
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.text().await.unwrap(), "ok");
        server.await.unwrap();
        assert_eq!(
            observer
                .fallback_count
                .load(std::sync::atomic::Ordering::Relaxed),
            1
        );
        let outcomes = observer.outcomes.lock().unwrap();
        assert_eq!(outcomes.len(), 2);
        assert!(matches!(outcomes[0], HttpRequestOutcome::TransportFailure));
        assert!(matches!(outcomes[1], HttpRequestOutcome::Success(200)));
    }

    #[tokio::test]
    async fn does_not_replay_non_idempotent_request() {
        let observer = fallback_observer();
        let client = ObservedHttpClient::new(
            Client::builder().no_proxy().build().unwrap(),
            observer.clone(),
        );

        let result = client
            .post("http://example.com/probe")
            .json(&serde_json::json!({"value": 1}))
            .send()
            .await;

        assert!(result.is_err());
        assert_eq!(
            observer
                .fallback_count
                .load(std::sync::atomic::Ordering::Relaxed),
            0
        );
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

    #[test]
    fn parses_forum_topics_and_preserves_page_order() {
        let [nodeseek, linux_do, v2ex] = ForumSpecification::all();
        let nodeseek_topics = extract_forum_topics(
            "https://www.nodeseek.com/post-345678-1.html https://nodeseek.com/post-123456-2",
            nodeseek,
        );
        assert_eq!(nodeseek_topics.len(), 2);
        assert_eq!(nodeseek_topics[0].path(), "/post-345678-1.html");

        let linux_topics = extract_forum_topics(
            "https://linux.do/t/topic/2697352/3?order=created#reply https://linux.do/t/topic/2687655",
            linux_do,
        );
        assert_eq!(linux_topics[0].as_str(), "https://linux.do/t/topic/2697352");
        assert_eq!(linux_topics[1].as_str(), "https://linux.do/t/topic/2687655");

        let v2ex_topics = extract_forum_topics(
            "https://www.v2ex.com/t/1231619#reply1 https://v2ex.com/t/1231500",
            v2ex,
        );
        assert_eq!(v2ex_topics[0].as_str(), "https://www.v2ex.com/t/1231619");
        assert_eq!(v2ex_topics[1].as_str(), "https://v2ex.com/t/1231500");
    }

    #[test]
    fn rejects_cross_site_forum_entries() {
        let [nodeseek, linux_do, v2ex] = ForumSpecification::all();
        assert!(parse_forum_entry("https://nodeseek.com/", nodeseek).is_ok());
        assert!(parse_forum_entry("https://www.linux.do/c/welfare/36", linux_do).is_ok());
        assert!(parse_forum_entry("https://v2ex.com/go/openai", v2ex).is_ok());
        assert!(parse_forum_entry("https://evil.example/t/123", v2ex).is_err());
        assert!(parse_forum_entry("https://user:secret@v2ex.com/t/123", v2ex).is_err());
    }

    #[test]
    fn extracts_external_candidates_with_topic_context() {
        let specification = ForumSpecification::all()[1];
        let topic = Url::parse("https://linux.do/t/topic/2687655").unwrap();
        let content = "模型入口 https://api.example.com/v1/models，站内链接 https://linux.do/t/topic/1，读取链接 https://r.jina.ai/https://linux.do/t/topic/1，头像 ![Image](https://cdn.example.com/avatar.png)，图标 https://static.example.com/logo.svg";
        let candidates = forum_candidates(content, &topic, specification);
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].target, "https://api.example.com/v1/models");
        assert_eq!(
            candidates[0].metadata.get(CANDIDATE_ARTIFACT_URL_KEY),
            Some(&topic.to_string())
        );
        assert!(
            candidates[0]
                .metadata
                .get(CANDIDATE_ARTIFACT_TEXT_KEY)
                .is_some_and(|value| value.contains("模型入口"))
        );
    }
}
