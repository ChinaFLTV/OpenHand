use anyhow::{Context, bail};
use axum::{
    Json, Router,
    body::Body,
    extract::{Path, Query, Request, State},
    http::{StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Response, Sse, sse::Event},
    routing::{delete, get, post},
};
use futures::StreamExt;
use hunt_core::{ScanRequest, ScanRule};
use hunt_engine::{
    AiExtractorInput, DependencyConfigurationInput, EngineError, EngineEvent, HuntEngine,
    PostgresQueryInput, PostgresRowMutationInput, ProxyConfigurationInput, RedisRecordInput,
    SourceCredentialInput,
};
use hunt_store::HuntStore;
use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize};
use std::{
    io::{self, Read},
    net::SocketAddr,
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};
use subtle::ConstantTimeEq;
use tokio::{net::TcpListener, signal};
use tokio_stream::wrappers::BroadcastStream;
use tower_http::limit::RequestBodyLimitLayer;
use tracing::{error, info};
use uuid::Uuid;

const MAX_TOKEN_BYTES: usize = 4096;
const MIN_TOKEN_BYTES: usize = 32;
const MAX_REQUEST_BYTES: usize = 2 * 1024 * 1024;
const DEFAULT_LIST_LIMIT: usize = 200;
const MAX_LIST_LIMIT: usize = 2_000;
const DEFAULT_LISTEN_ADDRESS: &str = "127.0.0.1:0";
const SSE_KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(15);

#[derive(Clone)]
struct AppState {
    engine: HuntEngine,
    token: Arc<SecretString>,
    started_at: Instant,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct HealthResponse {
    status: &'static str,
    version: &'static str,
    database_path: String,
    uptime_seconds: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ReadyMessage {
    event: &'static str,
    address: String,
    version: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct JobCreatedResponse {
    job_id: Uuid,
}

#[derive(Deserialize)]
struct ListQuery {
    limit: Option<usize>,
    #[serde(rename = "jobId")]
    job_id: Option<Uuid>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PostgresPageQuery {
    limit: Option<u32>,
    offset: Option<u32>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RedisPageQuery {
    cursor: Option<u64>,
    search: Option<String>,
    limit: Option<u32>,
}

#[derive(Deserialize)]
struct RedisDeleteInput {
    key: String,
}

#[derive(Debug)]
struct ApiError {
    status: StatusCode,
    message: String,
}

#[derive(Serialize)]
struct ApiErrorBody {
    error: String,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (
            self.status,
            Json(ApiErrorBody {
                error: self.message,
            }),
        )
            .into_response()
    }
}

impl From<EngineError> for ApiError {
    fn from(error: EngineError) -> Self {
        let status = match error {
            EngineError::JobNotFound => StatusCode::NOT_FOUND,
            EngineError::JobRunning | EngineError::JobFinished => StatusCode::CONFLICT,
            EngineError::TooManyTargets
            | EngineError::NoSource
            | EngineError::InvalidConcurrency
            | EngineError::TooManyActiveJobs
            | EngineError::AiExtractorNotConfigured
            | EngineError::InvalidAiExtractor(_)
            | EngineError::InvalidProxy(_)
            | EngineError::InvalidDependency(_)
            | EngineError::DependencyData(_) => StatusCode::BAD_REQUEST,
            EngineError::Other(_) => StatusCode::INTERNAL_SERVER_ERROR,
        };
        Self {
            status,
            message: error.to_string(),
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "hunt_daemon=info".into()),
        )
        .with_writer(io::stderr)
        .init();
    let config = parse_args()?;
    let token = read_session_token()?;
    let address: SocketAddr = config.listen.parse().context("监听地址无效")?;
    if !address.ip().is_loopback() {
        bail!("扫描守护进程只能监听本机回环地址。");
    }
    let store = HuntStore::open(&config.data_dir).await?;
    let engine = HuntEngine::new(store).await?;
    let state = AppState {
        engine,
        token: Arc::new(SecretString::from(token)),
        started_at: Instant::now(),
    };
    let app = routes(state.clone())
        .layer(RequestBodyLimitLayer::new(MAX_REQUEST_BYTES))
        .route_layer(middleware::from_fn_with_state(state, authenticate));
    let listener = TcpListener::bind(address)
        .await
        .context("绑定本地端口失败")?;
    let local_address = listener.local_addr()?;
    println!(
        "{}",
        serde_json::to_string(&ReadyMessage {
            event: "ready",
            address: format!("http://{local_address}"),
            version: env!("CARGO_PKG_VERSION"),
        })?
    );
    info!("扫描守护进程已启动：{local_address}");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("扫描守护进程异常退出")?;
    info!("扫描守护进程已停止");
    Ok(())
}

fn routes(state: AppState) -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/jobs", post(create_job))
        .route("/v1/jobs/{id}", get(job_progress))
        .route("/v1/jobs/{id}/stop", post(stop_job))
        .route("/v1/jobs/{id}/resume", post(resume_job))
        .route("/v1/jobs/{id}/events", get(job_events))
        .route("/v1/jobs/{id}/logs", get(job_logs))
        .route("/v1/history", get(history))
        .route("/v1/history/{id}", delete(delete_history))
        .route("/v1/results", get(results))
        .route("/v1/rules", get(rules).put(save_rules))
        .route("/v1/sources", get(source_status).put(update_sources))
        .route("/v1/sources/quotas", get(source_quotas))
        .route(
            "/v1/proxy",
            get(proxy_status).put(update_proxy).delete(clear_proxy),
        )
        .route(
            "/v1/ai-extractor",
            get(ai_extractor_status)
                .put(update_ai_extractor)
                .delete(clear_ai_extractor),
        )
        .route(
            "/v1/dependencies",
            get(dependency_status)
                .put(update_dependencies)
                .delete(clear_dependencies),
        )
        .route("/v1/dependencies/data", get(dependency_data_overview))
        .route("/v1/dependencies/postgresql/query", post(query_postgresql))
        .route(
            "/v1/dependencies/postgresql/{table}",
            get(postgresql_rows)
                .post(insert_postgresql_row)
                .put(update_postgresql_row)
                .delete(delete_postgresql_row),
        )
        .route(
            "/v1/dependencies/redis",
            get(redis_records)
                .put(put_redis_record)
                .delete(delete_redis_record),
        )
        .with_state(state)
}

async fn authenticate(
    State(state): State<AppState>,
    request: Request<Body>,
    next: Next,
) -> Result<Response, ApiError> {
    let supplied = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .unwrap_or_default();
    let expected = state.token.expose_secret().as_bytes();
    let supplied = supplied.as_bytes();
    let authorized = expected.len() == supplied.len() && expected.ct_eq(supplied).into();
    if !authorized {
        return Err(ApiError {
            status: StatusCode::UNAUTHORIZED,
            message: "访问令牌无效。".to_owned(),
        });
    }
    Ok(next.run(request).await)
}

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ready",
        version: env!("CARGO_PKG_VERSION"),
        database_path: state.engine.database_path().to_string_lossy().into_owned(),
        uptime_seconds: state.started_at.elapsed().as_secs(),
    })
}

async fn create_job(
    State(state): State<AppState>,
    Json(request): Json<ScanRequest>,
) -> Result<(StatusCode, Json<JobCreatedResponse>), ApiError> {
    let job_id = state.engine.start_job(request).await?;
    Ok((StatusCode::CREATED, Json(JobCreatedResponse { job_id })))
}

async fn job_progress(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<hunt_core::ScanProgress>, ApiError> {
    Ok(Json(state.engine.progress(id).await?))
}

async fn stop_job(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, ApiError> {
    state.engine.stop_job(id).await?;
    Ok(StatusCode::ACCEPTED)
}

async fn resume_job(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<(StatusCode, Json<JobCreatedResponse>), ApiError> {
    let job_id = state.engine.resume_job(id).await?;
    Ok((StatusCode::CREATED, Json(JobCreatedResponse { job_id })))
}

async fn job_events(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Sse<impl futures::Stream<Item = Result<Event, std::convert::Infallible>>>, ApiError> {
    let receiver = state.engine.subscribe(id).await?;
    let initial = state.engine.progress(id).await?;
    let initial_stream = futures::stream::once(async move {
        Ok(event_to_sse(EngineEvent::Progress { progress: initial }))
    });
    let live_stream = BroadcastStream::new(receiver).filter_map(|item| async move {
        match item {
            Ok(event) => Some(Ok(event_to_sse(event))),
            Err(tokio_stream::wrappers::errors::BroadcastStreamRecvError::Lagged(skipped)) => {
                Some(Ok(Event::default().event("log").data(
                    serde_json::json!({
                        "type": "log",
                        "level": "warning",
                        "message": format!("客户端处理过慢，已跳过 {skipped} 条事件。"),
                    })
                    .to_string(),
                )))
            }
        }
    });
    let stream = initial_stream.chain(live_stream);
    Ok(Sse::new(stream).keep_alive(
        axum::response::sse::KeepAlive::new()
            .interval(SSE_KEEP_ALIVE_INTERVAL)
            .text("keep-alive"),
    ))
}

async fn job_logs(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Query(query): Query<ListQuery>,
) -> Result<Json<Vec<hunt_core::ScanLogEntry>>, ApiError> {
    Ok(Json(state.engine.logs(id, limit(query.limit)).await?))
}

async fn history(
    State(state): State<AppState>,
    Query(query): Query<ListQuery>,
) -> Result<Json<Vec<hunt_core::ScanJobSummary>>, ApiError> {
    Ok(Json(state.engine.history(limit(query.limit)).await?))
}

async fn delete_history(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, ApiError> {
    if state.engine.delete_history(id).await? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ApiError {
            status: StatusCode::NOT_FOUND,
            message: "扫描历史不存在。".to_owned(),
        })
    }
}

async fn results(
    State(state): State<AppState>,
    Query(query): Query<ListQuery>,
) -> Result<Json<Vec<hunt_core::ScanResult>>, ApiError> {
    Ok(Json(
        state
            .engine
            .results(query.job_id, limit(query.limit))
            .await?,
    ))
}

async fn rules(State(state): State<AppState>) -> Result<Json<Vec<ScanRule>>, ApiError> {
    Ok(Json(state.engine.rules().await?))
}

async fn save_rules(
    State(state): State<AppState>,
    Json(rules): Json<Vec<ScanRule>>,
) -> Result<StatusCode, ApiError> {
    state.engine.save_rules(rules).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn source_status(
    State(state): State<AppState>,
) -> Json<hunt_engine::SourceConfigurationStatus> {
    Json(state.engine.source_status().await)
}

async fn update_sources(
    State(state): State<AppState>,
    Json(input): Json<SourceCredentialInput>,
) -> StatusCode {
    state.engine.update_source_credentials(input).await;
    StatusCode::NO_CONTENT
}

async fn source_quotas(State(state): State<AppState>) -> Json<Vec<hunt_core::SourceQuota>> {
    Json(state.engine.quotas().await)
}

async fn proxy_status(
    State(state): State<AppState>,
) -> Json<hunt_engine::ProxyConfigurationStatus> {
    Json(state.engine.proxy_status())
}

async fn update_proxy(
    State(state): State<AppState>,
    Json(input): Json<ProxyConfigurationInput>,
) -> Result<StatusCode, ApiError> {
    state.engine.update_proxy(input)?;
    Ok(StatusCode::NO_CONTENT)
}

async fn clear_proxy(State(state): State<AppState>) -> Result<StatusCode, ApiError> {
    state
        .engine
        .update_proxy(ProxyConfigurationInput::default())?;
    Ok(StatusCode::NO_CONTENT)
}

async fn ai_extractor_status(
    State(state): State<AppState>,
) -> Json<hunt_engine::AiExtractorStatus> {
    Json(state.engine.ai_extractor_status().await)
}

async fn update_ai_extractor(
    State(state): State<AppState>,
    Json(input): Json<AiExtractorInput>,
) -> Result<StatusCode, ApiError> {
    state.engine.update_ai_extractor(input).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn clear_ai_extractor(State(state): State<AppState>) -> StatusCode {
    state.engine.clear_ai_extractor().await;
    StatusCode::NO_CONTENT
}

async fn dependency_status(State(state): State<AppState>) -> Json<hunt_engine::DependencyStatus> {
    Json(state.engine.dependency_status().await)
}

async fn update_dependencies(
    State(state): State<AppState>,
    Json(input): Json<DependencyConfigurationInput>,
) -> Result<StatusCode, ApiError> {
    state.engine.update_dependencies(input).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn clear_dependencies(State(state): State<AppState>) -> StatusCode {
    state.engine.clear_dependencies().await;
    StatusCode::NO_CONTENT
}

async fn dependency_data_overview(State(state): State<AppState>) -> Json<serde_json::Value> {
    Json(state.engine.dependency_data_overview().await)
}

async fn postgresql_rows(
    State(state): State<AppState>,
    Path(table): Path<String>,
    Query(query): Query<PostgresPageQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    Ok(Json(
        state
            .engine
            .postgresql_rows(&table, query.limit.unwrap_or(50), query.offset.unwrap_or(0))
            .await?,
    ))
}

async fn insert_postgresql_row(
    State(state): State<AppState>,
    Path(table): Path<String>,
    Json(input): Json<PostgresRowMutationInput>,
) -> Result<Json<serde_json::Value>, ApiError> {
    Ok(Json(
        state.engine.insert_postgresql_row(&table, input).await?,
    ))
}

async fn update_postgresql_row(
    State(state): State<AppState>,
    Path(table): Path<String>,
    Json(input): Json<PostgresRowMutationInput>,
) -> Result<Json<serde_json::Value>, ApiError> {
    Ok(Json(serde_json::json!({
        "row": state.engine.update_postgresql_row(&table, input).await?
    })))
}

async fn delete_postgresql_row(
    State(state): State<AppState>,
    Path(table): Path<String>,
    Json(input): Json<PostgresRowMutationInput>,
) -> Result<Json<serde_json::Value>, ApiError> {
    Ok(Json(serde_json::json!({
        "row": state.engine.delete_postgresql_row(&table, input).await?
    })))
}

async fn query_postgresql(
    State(state): State<AppState>,
    Json(input): Json<PostgresQueryInput>,
) -> Result<Json<serde_json::Value>, ApiError> {
    Ok(Json(state.engine.query_postgresql(input).await?))
}

async fn redis_records(
    State(state): State<AppState>,
    Query(query): Query<RedisPageQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    Ok(Json(
        state
            .engine
            .redis_records(
                query.cursor.unwrap_or(0),
                query.search.as_deref().unwrap_or_default(),
                query.limit.unwrap_or(50),
            )
            .await?,
    ))
}

async fn put_redis_record(
    State(state): State<AppState>,
    Json(input): Json<RedisRecordInput>,
) -> Result<Json<serde_json::Value>, ApiError> {
    Ok(Json(state.engine.put_redis_record(input).await?))
}

async fn delete_redis_record(
    State(state): State<AppState>,
    Json(input): Json<RedisDeleteInput>,
) -> Result<Json<serde_json::Value>, ApiError> {
    Ok(Json(serde_json::json!({
        "deleted": state.engine.delete_redis_record(&input.key).await?
    })))
}

fn event_to_sse(event: EngineEvent) -> Event {
    let name = match event {
        EngineEvent::Progress { .. } => "progress",
        EngineEvent::Log { .. } => "log",
        EngineEvent::Result { .. } => "result",
    };
    match serde_json::to_string(&event) {
        Ok(data) => Event::default().event(name).data(data),
        Err(error) => {
            error!("编码 SSE 事件失败：{error}");
            Event::default()
                .event("error")
                .data("{\"message\":\"编码实时事件失败。\"}")
        }
    }
}

fn limit(value: Option<usize>) -> usize {
    value.unwrap_or(DEFAULT_LIST_LIMIT).clamp(1, MAX_LIST_LIMIT)
}

struct Config {
    data_dir: PathBuf,
    listen: String,
}

fn parse_args() -> anyhow::Result<Config> {
    let mut arguments = std::env::args().skip(1);
    if arguments.next().as_deref() != Some("serve") {
        bail!("用法：ai_jungler serve --data-dir <目录> [--listen 127.0.0.1:0]");
    }
    let mut data_dir = None;
    let mut listen = DEFAULT_LISTEN_ADDRESS.to_owned();
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--data-dir" => {
                data_dir = Some(PathBuf::from(next_option_value(
                    &mut arguments,
                    "--data-dir",
                )?));
            }
            "--listen" => listen = next_option_value(&mut arguments, "--listen")?,
            _ => bail!("未知参数：{argument}"),
        }
    }
    Ok(Config {
        data_dir: data_dir.context("--data-dir 不能为空")?,
        listen,
    })
}

fn next_option_value(
    arguments: &mut impl Iterator<Item = String>,
    option: &str,
) -> anyhow::Result<String> {
    let value = arguments
        .next()
        .with_context(|| format!("{option} 缺少参数"))?;
    if value.trim().is_empty() || value.starts_with("--") {
        bail!("{option} 缺少参数");
    }
    Ok(value)
}

fn read_session_token() -> anyhow::Result<String> {
    let mut bytes = Vec::new();
    io::stdin()
        .lock()
        .take((MAX_TOKEN_BYTES + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() > MAX_TOKEN_BYTES {
        bail!("会话令牌过长。");
    }
    let token = String::from_utf8(bytes)?;
    let token = token.trim().to_owned();
    if token.len() < MIN_TOKEN_BYTES {
        bail!("会话令牌长度不足。");
    }
    Ok(token)
}

async fn shutdown_signal() {
    #[cfg(unix)]
    {
        match signal::unix::signal(signal::unix::SignalKind::terminate()) {
            Ok(mut terminate) => {
                tokio::select! {
                    result = signal::ctrl_c() => {
                        if let Err(error) = result {
                            error!("监听中断信号失败：{error}");
                        }
                    },
                    received = terminate.recv() => {
                        if received.is_none() {
                            error!("终止信号监听已关闭。");
                        }
                    },
                }
            }
            Err(error) => {
                error!("安装终止信号监听失败：{error}");
                if let Err(error) = signal::ctrl_c().await {
                    error!("监听中断信号失败：{error}");
                }
            }
        }
    }
    #[cfg(not(unix))]
    {
        if let Err(error) = signal::ctrl_c().await {
            error!("监听中断信号失败：{error}");
        }
    }
}
