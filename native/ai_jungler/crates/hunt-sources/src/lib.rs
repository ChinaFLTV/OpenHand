use async_trait::async_trait;
use base64::{Engine, engine::general_purpose::STANDARD};
use chrono::Utc;
use futures::{StreamExt, stream};
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
    sync::{Arc, LazyLock, RwLock},
    time::{Duration, Instant},
};
use thiserror::Error;
use tokio::{io::AsyncWriteExt, process::Command, sync::Semaphore, time::timeout};

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
const MAX_FORUM_TOPICS: usize = 5;
const FORUM_TOPIC_CONCURRENCY: usize = 3;
const JINA_READER_TIMEOUT: Duration = Duration::from_secs(45);
const MAX_BROWSER_CONCURRENCY: usize = 2;
const BROWSER_PROCESS_TIMEOUT: Duration = Duration::from_secs(25);
const MAX_BROWSER_OUTPUT_BYTES: usize = 2 * 1024 * 1024;
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
    fn begin_external(&self, _target: &reqwest::Url) -> reqwest::Result<ExternalHttpRequestRoute> {
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

    pub fn begin_external(&self, target: &Url) -> reqwest::Result<ObservedExternalRequest> {
        let route = self.observer.begin_external(target)?;
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

    pub fn timeout(self, duration: Duration) -> Self {
        Self {
            request: self.request.timeout(duration),
            ..self
        }
    }

    pub async fn send(self) -> reqwest::Result<Response> {
        let request = self.request.build()?;
        let observation = self.client.observer.begin(request.url())?;
        let ticket = observation.as_ref().and_then(|value| value.ticket);
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
            },
            None => BrowserAutomationStatus {
                configured: false,
                available: false,
                message: "未检测到可用的 Playwright 插件。".to_owned(),
            },
        }
    }

    async fn fetch(&self, target: &Url) -> Result<String, SourceError> {
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
            .begin_external(target)
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
    let port = url.port_or_known_default().unwrap_or_default();
    BrowserProxyInput {
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
        "Playwright 模块不可用".to_owned()
    } else {
        "浏览器运行异常".to_owned()
    }
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
    specification: ForumSpecification,
}

impl ForumSource {
    fn new(
        client: ObservedHttpClient,
        browser: BrowserAutomation,
        specification: ForumSpecification,
    ) -> Self {
        Self {
            client,
            browser,
            specification,
        }
    }

    async fn fetch_page(
        &self,
        target: &Url,
        mode: ForumFetchMode,
    ) -> Result<(String, Option<String>, bool), SourceError> {
        if mode == ForumFetchMode::Playwright {
            return self
                .browser
                .fetch(target)
                .await
                .map(|content| (content, None, false));
        }
        match self.fetch_jina(target).await {
            Ok(content) => Ok((content, None, false)),
            Err(reader) => match self.browser.fetch(target).await {
                Ok(content) => Ok((
                    content,
                    Some(format!(
                        "{} 的 Jina Reader 读取失败，已切换 Playwright：{reader}",
                        self.specification.platform
                    )),
                    true,
                )),
                Err(browser) => Err(SourceError::ForumFetch {
                    platform: self.specification.platform,
                    reader,
                    browser: browser.to_string(),
                }),
            },
        }
    }

    async fn fetch_jina(&self, target: &Url) -> Result<String, String> {
        let reader_url = Url::parse(&format!("https://r.jina.ai/{}", target.as_str()))
            .map_err(|_| "请求地址无效".to_owned())?;
        let response = self
            .client
            .get(reader_url)
            .header("Accept", "text/plain")
            .header("X-Return-Format", "markdown")
            .timeout(JINA_READER_TIMEOUT)
            .send()
            .await
            .map_err(|error| {
                if error.is_timeout() {
                    "请求超时".to_owned()
                } else {
                    "网络请求失败".to_owned()
                }
            })?;
        if !response.status().is_success() {
            return Err(format!("返回 HTTP {}", response.status().as_u16()));
        }
        let content = parse_text_limited(self.specification.platform, response)
            .await
            .map_err(|error| error.to_string())?;
        let trimmed = content.trim();
        if trimmed.is_empty() {
            return Err("返回内容为空".to_owned());
        }
        if trimmed.starts_with("{\"data\":null,") {
            return Err("拒绝读取目标站点".to_owned());
        }
        Ok(content)
    }
}

#[async_trait]
impl AssetSource for ForumSource {
    fn kind(&self) -> SourceKind {
        self.specification.kind
    }

    async fn discover(
        &self,
        request: &ScanRequest,
        _credentials: &SourceCredentials,
    ) -> Result<SourceDiscovery, SourceError> {
        let entry = source_query(request, self.specification.key)
            .unwrap_or_else(|| self.specification.default_entry.to_owned());
        let entry = parse_forum_entry(&entry, self.specification)?;
        let (index_content, index_warning, index_fallback) =
            self.fetch_page(&entry, request.forum_fetch_mode).await?;
        let direct_topic = self.specification.is_topic_path(entry.path());
        let topics = if direct_topic {
            Vec::new()
        } else {
            extract_forum_topics(&index_content, self.specification)
        };
        if !direct_topic && topics.is_empty() {
            return Err(SourceError::InvalidResponse(self.specification.platform));
        }
        let mut warnings = index_warning.into_iter().collect::<Vec<_>>();
        let mut candidates = BTreeMap::new();
        let mut successful_pages = 0_usize;
        let mut last_error = None;
        if direct_topic {
            successful_pages = 1;
            for candidate in forum_candidates(&index_content, &entry, self.specification) {
                candidates
                    .entry(candidate.target.clone())
                    .or_insert(candidate);
            }
        } else {
            let source = self;
            let mode = if index_fallback {
                ForumFetchMode::Playwright
            } else {
                request.forum_fetch_mode
            };
            let pages = stream::iter(topics.into_iter().map(|topic| async move {
                let result = source.fetch_page(&topic, mode).await;
                (topic, result)
            }))
            .buffer_unordered(FORUM_TOPIC_CONCURRENCY);
            futures::pin_mut!(pages);
            while let Some((topic, result)) = pages.next().await {
                match result {
                    Ok((content, warning, _)) => {
                        successful_pages += 1;
                        warnings.extend(warning);
                        for candidate in forum_candidates(&content, &topic, self.specification) {
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
        Ok(SourceDiscovery {
            candidates: candidates.into_values().collect(),
            warnings,
        })
    }

    async fn quota(&self, _credentials: &SourceCredentials) -> Result<SourceQuota, SourceError> {
        let browser = self.browser.status();
        Ok(unlimited_quota(
            self.specification.kind,
            &if browser.available {
                format!("无需 API 凭证；Jina Reader 与 {} 均可用。", browser.message)
            } else {
                format!("无需 API 凭证；Jina Reader 可用，{}", browser.message)
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
}

impl SourceRegistry {
    pub fn new(client: ObservedHttpClient) -> Self {
        let browser = BrowserAutomation::new(client.clone());
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
                    specification,
                )),
            );
        }
        Self { sources, browser }
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
    ) -> Result<SourceDiscovery, SourceError> {
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
                    return Ok(SourceDiscovery::new(candidates));
                }
            }
        }
        Ok(SourceDiscovery::new(candidates))
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
                    return Ok(SourceDiscovery::new(candidates));
                }
            }
        }
        Ok(SourceDiscovery::new(candidates))
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
    ) -> Result<SourceDiscovery, SourceError> {
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
        Ok(SourceDiscovery::new(
            body.results
                .into_iter()
                .filter_map(|row| row.first().and_then(value_as_string))
                .take(MAX_SOURCE_RESULTS)
                .map(|target| Candidate {
                    source: SourceKind::Fofa,
                    target,
                    discovered_at: Utc::now(),
                    metadata: BTreeMap::new(),
                })
                .collect(),
        ))
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
    ) -> Result<SourceDiscovery, SourceError> {
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
        Ok(SourceDiscovery::new(
            body.matches
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
                .collect(),
        ))
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
