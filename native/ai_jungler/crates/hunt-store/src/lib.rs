mod postgres;

use aes_gcm::{
    Aes256Gcm, KeyInit, Nonce,
    aead::{Aead, OsRng, rand_core::RngCore},
};
use anyhow::Context;
use base64::{Engine, engine::general_purpose::STANDARD};
use chrono::{DateTime, Utc};
use hunt_core::{
    ScanJobSummary, ScanLogEntry, ScanProgress, ScanRequest, ScanResult, ScanRule, ScanStage,
};
use postgres::PostgresMirror;
use rusqlite::{Connection, OptionalExtension, params};
use serde_json::{Map, Value};
use std::{
    collections::HashSet,
    fs::{self, OpenOptions},
    future::Future,
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::Duration,
};
use thiserror::Error;
use tokio::sync::RwLock as AsyncRwLock;
use tracing::warn;
use uuid::Uuid;
use zeroize::Zeroizing;

const DATABASE_FILE: &str = "hunt.db";
const KEY_FILE: &str = "credential.key";
const KEY_LENGTH: usize = 32;
const NONCE_LENGTH: usize = 12;
const POSTGRES_OPERATION_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Clone)]
pub struct HuntStore {
    connection: Arc<Mutex<Connection>>,
    cipher: Arc<Aes256Gcm>,
    data_dir: Arc<PathBuf>,
    postgres: Arc<AsyncRwLock<Option<PostgresMirror>>>,
}

#[derive(Clone, Debug)]
pub struct PostgresStatus {
    pub configured: bool,
    pub connected: bool,
    pub message: String,
}

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("存储任务执行失败：{0}")]
    Task(String),
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

impl HuntStore {
    pub async fn open(data_dir: impl AsRef<Path>) -> Result<Self, StoreError> {
        let data_dir = data_dir.as_ref().to_path_buf();
        let initialized = tokio::task::spawn_blocking(move || {
            fs::create_dir_all(&data_dir).context("创建扫描数据目录失败")?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                fs::set_permissions(&data_dir, fs::Permissions::from_mode(0o700))?;
            }
            let key = load_or_create_key(&data_dir.join(KEY_FILE))?;
            let cipher = Aes256Gcm::new_from_slice(key.as_slice())
                .map_err(|_| anyhow::anyhow!("初始化凭证加密器失败"))?;
            let database_path = data_dir.join(DATABASE_FILE);
            let connection = Connection::open(&database_path).context("打开扫描数据库失败")?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                fs::set_permissions(&database_path, fs::Permissions::from_mode(0o600))?;
            }
            migrate(&connection)?;
            Ok::<_, anyhow::Error>((data_dir, connection, cipher))
        })
        .await
        .map_err(|error| StoreError::Task(error.to_string()))??;
        Ok(Self {
            data_dir: Arc::new(initialized.0),
            connection: Arc::new(Mutex::new(initialized.1)),
            cipher: Arc::new(initialized.2),
            postgres: Arc::new(AsyncRwLock::new(None)),
        })
    }

    pub fn database_path(&self) -> PathBuf {
        self.data_dir.join(DATABASE_FILE)
    }

    pub async fn configure_postgres(&self, url: &str) -> Result<(), StoreError> {
        let url = url.trim();
        if url.is_empty() {
            return Err(StoreError::Other(anyhow::anyhow!(
                "PostgreSQL 连接串不能为空"
            )));
        }
        let mirror = postgres_operation(PostgresMirror::connect(url))
            .await
            .context("连接 PostgreSQL 失败")?;
        let previous = self.postgres.write().await.replace(mirror);
        if let Some(previous) = previous {
            let _ = tokio::time::timeout(POSTGRES_OPERATION_TIMEOUT, previous.close()).await;
        }
        Ok(())
    }

    pub async fn clear_postgres(&self) {
        if let Some(mirror) = self.postgres.write().await.take() {
            let _ = tokio::time::timeout(POSTGRES_OPERATION_TIMEOUT, mirror.close()).await;
        }
    }

    pub async fn postgres_status(&self) -> PostgresStatus {
        let mirror = self.postgres.read().await.clone();
        let Some(mirror) = mirror else {
            return PostgresStatus {
                configured: false,
                connected: false,
                message: "未启用".to_owned(),
            };
        };
        match postgres_operation(mirror.ping()).await {
            Ok(()) => PostgresStatus {
                configured: true,
                connected: true,
                message: "连接正常".to_owned(),
            },
            Err(_) => PostgresStatus {
                configured: true,
                connected: false,
                message: "连接不可用".to_owned(),
            },
        }
    }

    pub async fn postgres_overview(&self) -> Result<Value, StoreError> {
        let mirror = self.configured_postgres().await?;
        Ok(postgres_operation(mirror.overview()).await?)
    }

    pub async fn postgres_rows(
        &self,
        table: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Value, StoreError> {
        let mirror = self.configured_postgres().await?;
        Ok(postgres_operation(mirror.rows(table, limit, offset)).await?)
    }

    pub async fn insert_postgres_row(
        &self,
        table: &str,
        values: Map<String, Value>,
    ) -> Result<Value, StoreError> {
        let mirror = self.configured_postgres().await?;
        Ok(postgres_operation(mirror.insert_row(table, values)).await?)
    }

    pub async fn update_postgres_row(
        &self,
        table: &str,
        keys: Map<String, Value>,
        values: Map<String, Value>,
    ) -> Result<Option<Value>, StoreError> {
        let mirror = self.configured_postgres().await?;
        Ok(postgres_operation(mirror.update_row(table, keys, values)).await?)
    }

    pub async fn delete_postgres_row(
        &self,
        table: &str,
        keys: Map<String, Value>,
    ) -> Result<Option<Value>, StoreError> {
        let mirror = self.configured_postgres().await?;
        Ok(postgres_operation(mirror.delete_row(table, keys)).await?)
    }

    pub async fn query_postgres(&self, statement: &str, limit: u32) -> Result<Value, StoreError> {
        let mirror = self.configured_postgres().await?;
        Ok(postgres_operation(mirror.read_only_query(statement, limit)).await?)
    }

    async fn configured_postgres(&self) -> Result<PostgresMirror, StoreError> {
        self.postgres
            .read()
            .await
            .clone()
            .ok_or_else(|| StoreError::Other(anyhow::anyhow!("PostgreSQL 尚未启用")))
    }

    pub async fn create_job(
        &self,
        id: Uuid,
        request: &ScanRequest,
        progress: &ScanProgress,
    ) -> Result<(), StoreError> {
        let request_json = serde_json::to_string(request).context("编码扫描请求失败")?;
        let progress_json = serde_json::to_string(progress).context("编码扫描进度失败")?;
        let created_at = Utc::now().to_rfc3339();
        self.with_connection(move |connection| {
            connection.execute(
                "INSERT INTO jobs (id, name, request_json, stage, progress_json, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![id.to_string(), request_name(&request_json), request_json, ScanStage::Queued.as_str(), progress_json, created_at],
            )?;
            Ok(())
        }).await?;
        if let Some(mirror) = self.postgres.read().await.clone()
            && mirror.is_available()
            && let Err(error) = postgres_operation(mirror.create_job(id, request, progress)).await
        {
            report_postgres_failure(&mirror, "同步扫描任务", error);
        }
        Ok(())
    }

    pub async fn update_progress(&self, progress: &ScanProgress) -> Result<(), StoreError> {
        let job_id = progress.job_id.to_string();
        let stage = progress.stage.as_str();
        let progress_json = serde_json::to_string(progress).context("编码扫描进度失败")?;
        let finished_at = matches!(
            progress.stage,
            ScanStage::Completed | ScanStage::Cancelled | ScanStage::Failed
        )
        .then(|| Utc::now().to_rfc3339());
        self.with_connection(move |connection| {
            connection.execute(
                "UPDATE jobs SET stage = ?2, progress_json = ?3, finished_at = COALESCE(?4, finished_at) WHERE id = ?1",
                params![job_id, stage, progress_json, finished_at],
            )?;
            Ok(())
        }).await?;
        if let Some(mirror) = self.postgres.read().await.clone()
            && mirror.is_available()
            && let Err(error) = postgres_operation(mirror.update_progress(progress)).await
        {
            report_postgres_failure(&mirror, "同步扫描进度", error);
        }
        Ok(())
    }

    pub async fn set_job_error(&self, id: Uuid, message: String) -> Result<(), StoreError> {
        let mirror_message = message.clone();
        self.with_connection(move |connection| {
            connection.execute(
                "UPDATE jobs SET stage = 'failed', error_message = ?2, finished_at = ?3 WHERE id = ?1",
                params![id.to_string(), message, Utc::now().to_rfc3339()],
            )?;
            Ok(())
        }).await?;
        if let Some(mirror) = self.postgres.read().await.clone()
            && mirror.is_available()
            && let Err(error) = postgres_operation(mirror.set_job_error(id, &mirror_message)).await
        {
            report_postgres_failure(&mirror, "同步任务错误", error);
        }
        Ok(())
    }

    pub async fn insert_result(&self, result: &ScanResult) -> Result<(), StoreError> {
        let mut result = result.clone();
        let raw_credential = result.raw_credential.take();
        let encrypted_credential = raw_credential
            .as_deref()
            .map(|secret| encrypt(self.cipher.as_ref(), secret.as_bytes()))
            .transpose()?;
        let evidence_json = serde_json::to_string(&result.evidence).context("编码扫描证据失败")?;
        let category = serde_json::to_value(result.category)
            .context("编码结果分类失败")?
            .as_str()
            .unwrap_or("suspicious")
            .to_owned();
        let credential_state = serde_json::to_value(result.credential_state)
            .context("编码凭证状态失败")?
            .as_str()
            .unwrap_or("candidate")
            .to_owned();
        let sqlite_result = result.clone();
        let sqlite_encrypted_credential = encrypted_credential.clone();
        self.with_connection(move |connection| {
            connection.execute(
                "INSERT OR REPLACE INTO results (
                    id, job_id, source, url, host, product, category, credential_state,
                    masked_credential, encrypted_credential, credential_fingerprint,
                    response_fingerprint, duplicate_response_hosts, duplicate_key_hosts,
                    model_count, balance_summary, evidence_json, created_at
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)",
                params![
                    sqlite_result.id.to_string(), sqlite_result.job_id.to_string(),
                    serde_json::to_value(sqlite_result.source)?.as_str().unwrap_or("manual"),
                    sqlite_result.url, sqlite_result.host, sqlite_result.product, category, credential_state,
                    sqlite_result.masked_credential, sqlite_encrypted_credential,
                    sqlite_result.credential_fingerprint, sqlite_result.response_fingerprint,
                    sqlite_result.duplicate_response_hosts, sqlite_result.duplicate_key_hosts,
                    sqlite_result.model_count, sqlite_result.balance_summary,
                    evidence_json, sqlite_result.created_at.to_rfc3339(),
                ],
            )?;
            Ok(())
        }).await?;
        if let Some(mirror) = self.postgres.read().await.clone()
            && mirror.is_available()
            && let Err(error) =
                postgres_operation(mirror.insert_result(&result, encrypted_credential.as_deref()))
                    .await
        {
            report_postgres_failure(&mirror, "同步扫描结果", error);
        }
        Ok(())
    }

    pub async fn list_jobs(&self, limit: usize) -> Result<Vec<ScanJobSummary>, StoreError> {
        let bounded_limit = limit.clamp(1, 500) as i64;
        self.with_connection(move |connection| {
            let mut statement = connection.prepare(
                "SELECT id, name, request_json, stage, progress_json, created_at, finished_at, error_message
                 FROM jobs ORDER BY created_at DESC LIMIT ?1",
            )?;
            let rows = statement.query_map([bounded_limit], |row| {
                let id: String = row.get(0)?;
                let name: String = row.get(1)?;
                let request_json: String = row.get(2)?;
                let stage: String = row.get(3)?;
                let progress_json: String = row.get(4)?;
                let created_at: String = row.get(5)?;
                let finished_at: Option<String> = row.get(6)?;
                let error_message: Option<String> = row.get(7)?;
                Ok((id, name, request_json, stage, progress_json, created_at, finished_at, error_message))
            })?;
            let mut jobs = Vec::new();
            for row in rows {
                let (id, name, request_json, stage, progress_json, created_at, finished_at, error_message) = row?;
                let request: ScanRequest = serde_json::from_str(&request_json)?;
                let progress: ScanProgress = serde_json::from_str(&progress_json)?;
                let stage = parse_stage(&stage);
                let created_at = DateTime::parse_from_rfc3339(&created_at)?.with_timezone(&Utc);
                let finished_at = finished_at
                    .map(|value| DateTime::parse_from_rfc3339(&value).map(|time| time.with_timezone(&Utc)))
                    .transpose()?;
                let started_at = progress
                    .stage_timings
                    .iter()
                    .find(|timing| timing.stage != ScanStage::Queued)
                    .map(|timing| timing.started_at)
                    .or_else(|| (stage != ScanStage::Queued).then_some(created_at));
                jobs.push(ScanJobSummary {
                    id: Uuid::parse_str(&id)?,
                    name,
                    stage,
                    sources: request.sources,
                    mode: request.mode,
                    authorized_scope: request.authorized_scope,
                    started_at,
                    cancelled_at: (stage == ScanStage::Cancelled).then_some(finished_at).flatten(),
                    cancel_reason: (stage == ScanStage::Cancelled).then(|| progress.message.clone()),
                    last_checkpoint_at: Some(progress.updated_at),
                    failure_stage: progress.failure_stage,
                    retry_count: Some(0),
                    concurrency: Some(request.concurrency),
                    validation_mode: Some(request.validation_mode),
                    forum_fetch_mode: Some(request.forum_fetch_mode),
                    gpt_assisted: Some(request.gpt_assisted),
                    stage_timings: progress.stage_timings.clone(),
                    progress,
                    created_at,
                    finished_at,
                    error_message,
                });
            }
            Ok(jobs)
        }).await
    }

    /// 精确按 id 读取单个任务进度，替代对最近若干条的线性扫描，
    /// 避免历史超过上限后旧任务查进度返回 JobNotFound。
    pub async fn job_progress(&self, id: Uuid) -> Result<Option<ScanProgress>, StoreError> {
        self.with_connection(move |connection| {
            let progress_json: Option<String> = connection
                .query_row(
                    "SELECT progress_json FROM jobs WHERE id = ?1",
                    [id.to_string()],
                    |row| row.get(0),
                )
                .optional()?;
            progress_json
                .map(|json| Ok(serde_json::from_str(&json)?))
                .transpose()
        })
        .await
    }

    /// 引擎启动时把上次异常退出遗留的非终态任务标记为中断（Failed），
    /// 同时改写 progress_json 使前端不再显示"运行中"、可正常新建扫描。
    /// 返回被清理的任务数量。
    pub async fn mark_interrupted_jobs(&self) -> Result<usize, StoreError> {
        const INTERRUPT_MESSAGE: &str = "扫描引擎已重启，未完成的任务已标记为中断。";
        let finished_at = Utc::now().to_rfc3339();
        self.with_connection(move |connection| {
            let mut statement = connection.prepare(
                "SELECT id, progress_json FROM jobs
                 WHERE stage NOT IN ('completed', 'cancelled', 'failed')",
            )?;
            let rows = statement
                .query_map([], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
                })?
                .collect::<Result<Vec<_>, _>>()?;
            let mut interrupted = 0;
            for (id, progress_json) in rows {
                let mut progress: ScanProgress = serde_json::from_str(&progress_json)?;
                if progress.failure_stage.is_none() {
                    progress.failure_stage = Some(progress.stage);
                }
                progress.transition_to(ScanStage::Failed, INTERRUPT_MESSAGE);
                let updated_json = serde_json::to_string(&progress)?;
                connection.execute(
                    "UPDATE jobs SET stage = 'failed', progress_json = ?2,
                       error_message = COALESCE(error_message, ?3),
                       finished_at = COALESCE(finished_at, ?4)
                     WHERE id = ?1",
                    params![id, updated_json, INTERRUPT_MESSAGE, finished_at],
                )?;
                interrupted += 1;
            }
            Ok(interrupted)
        })
        .await
    }

    pub async fn load_request(
        &self,
        id: Uuid,
    ) -> Result<Option<(ScanRequest, ScanStage)>, StoreError> {
        self.with_connection(move |connection| {
            let row: Option<(String, String)> = connection
                .query_row(
                    "SELECT request_json, stage FROM jobs WHERE id = ?1",
                    [id.to_string()],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )
                .optional()?;
            row.map(|(request, stage)| Ok((serde_json::from_str(&request)?, parse_stage(&stage))))
                .transpose()
        })
        .await
    }

    pub async fn list_results(
        &self,
        job_id: Option<Uuid>,
        limit: usize,
    ) -> Result<Vec<ScanResult>, StoreError> {
        let job_id = job_id.map(|id| id.to_string());
        let bounded_limit = limit.clamp(1, 2_000) as i64;
        self.with_connection(move |connection| {
            let sql = if job_id.is_some() {
                "SELECT id, job_id, source, url, host, product, category, credential_state,
                 masked_credential, response_fingerprint, duplicate_response_hosts,
                 duplicate_key_hosts, model_count, balance_summary, evidence_json, created_at FROM results
                 WHERE job_id = ?1 ORDER BY created_at DESC LIMIT ?2"
            } else {
                "SELECT id, job_id, source, url, host, product, category, credential_state,
                 masked_credential, response_fingerprint, duplicate_response_hosts,
                 duplicate_key_hosts, model_count, balance_summary, evidence_json, created_at FROM results
                 WHERE ?1 IS NULL ORDER BY created_at DESC LIMIT ?2"
            };
            let mut statement = connection.prepare(sql)?;
            let rows = statement.query_map(params![job_id, bounded_limit], result_from_row)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
        })
        .await
    }

    pub async fn delete_job(&self, id: Uuid) -> Result<bool, StoreError> {
        let deleted = self
            .with_connection(move |connection| {
                let changed =
                    connection.execute("DELETE FROM jobs WHERE id = ?1", [id.to_string()])?;
                Ok(changed > 0)
            })
            .await?;
        if let Some(mirror) = self.postgres.read().await.clone()
            && mirror.is_available()
            && let Err(error) = postgres_operation(mirror.delete_job(id)).await
        {
            report_postgres_failure(&mirror, "同步删除扫描历史", error);
        }
        Ok(deleted)
    }

    pub async fn finalize_correlations(&self, job_id: Uuid) -> Result<(), StoreError> {
        let job_id_text = job_id.to_string();
        self.with_connection(move |connection| {
            connection.execute(
                "UPDATE results AS current
                 SET duplicate_key_hosts = (
                   SELECT MAX(COUNT(DISTINCT duplicate.host) - 1, 0)
                   FROM results AS duplicate
                   WHERE duplicate.job_id = current.job_id
                     AND duplicate.credential_fingerprint = current.credential_fingerprint
                 )
                 WHERE current.job_id = ?1 AND current.credential_fingerprint IS NOT NULL",
                [&job_id_text],
            )?;
            connection.execute(
                "UPDATE results AS current
                 SET duplicate_response_hosts = (
                   SELECT MAX(COUNT(DISTINCT duplicate.host) - 1, 0)
                   FROM results AS duplicate
                   WHERE duplicate.job_id = current.job_id
                     AND duplicate.response_fingerprint = current.response_fingerprint
                 )
                 WHERE current.job_id = ?1",
                [&job_id_text],
            )?;
            // 跨多主机复现的凭证/响应属蜜罐诱饵或广撒的低可信线索，降级为可疑，
            // 与 count_models 的 fail-closed 一并抑制“高价值密钥”误报。
            connection.execute(
                "UPDATE results SET category = 'suspicious'
                 WHERE job_id = ?1
                   AND category IN ('valid', 'high_value')
                   AND (duplicate_key_hosts >= ?2 OR duplicate_response_hosts >= ?2)",
                params![&job_id_text, HONEYPOT_CROSS_HOST_THRESHOLD],
            )?;
            Ok(())
        })
        .await?;
        if let Some(mirror) = self.postgres.read().await.clone()
            && mirror.is_available()
            && let Err(error) = postgres_operation(mirror.finalize_correlations(job_id)).await
        {
            report_postgres_failure(&mirror, "同步关联统计", error);
        }
        Ok(())
    }

    pub async fn insert_log(&self, entry: &ScanLogEntry) -> Result<(), StoreError> {
        let sqlite_entry = entry.clone();
        self.with_connection(move |connection| {
            let metadata_json = serde_json::to_string(&sqlite_entry.metadata)?;
            connection.execute(
                "INSERT INTO job_logs (
                    event_id, job_id, level, module, event_code, message, created_at,
                    trace_id, exception_type, stack_summary, metadata_json
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
                params![
                    sqlite_entry.id.map(|value| value.to_string()),
                    sqlite_entry.job_id.to_string(),
                    sqlite_entry.level,
                    sqlite_entry.module,
                    sqlite_entry.event_code,
                    sqlite_entry.message,
                    sqlite_entry.at.to_rfc3339(),
                    sqlite_entry.trace_id,
                    sqlite_entry.exception_type,
                    sqlite_entry.stack_summary,
                    metadata_json,
                ],
            )?;
            Ok(())
        })
        .await?;
        if let Some(mirror) = self.postgres.read().await.clone()
            && mirror.is_available()
            && let Err(error) = postgres_operation(mirror.insert_log(entry)).await
        {
            report_postgres_failure(&mirror, "同步扫描日志", error);
        }
        Ok(())
    }

    pub async fn list_logs(
        &self,
        job_id: Uuid,
        limit: usize,
    ) -> Result<Vec<ScanLogEntry>, StoreError> {
        let bounded_limit = limit.clamp(1, 5_000) as i64;
        self.with_connection(move |connection| {
            let mut statement = connection.prepare(
                "SELECT event_id, level, module, event_code, message, created_at,
                        trace_id, exception_type, stack_summary, metadata_json
                 FROM job_logs
                 WHERE job_id = ?1 ORDER BY id ASC LIMIT ?2",
            )?;
            let rows = statement.query_map(params![job_id.to_string(), bounded_limit], |row| {
                Ok((
                    row.get::<_, Option<String>>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<String>>(2)?,
                    row.get::<_, Option<String>>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, String>(5)?,
                    row.get::<_, Option<String>>(6)?,
                    row.get::<_, Option<String>>(7)?,
                    row.get::<_, Option<String>>(8)?,
                    row.get::<_, Option<String>>(9)?,
                ))
            })?;
            let mut logs = Vec::new();
            for row in rows {
                let (
                    id,
                    level,
                    module,
                    event_code,
                    message,
                    at,
                    trace_id,
                    exception_type,
                    stack_summary,
                    metadata_json,
                ) = row?;
                logs.push(ScanLogEntry {
                    id: id.map(|value| Uuid::parse_str(&value)).transpose()?,
                    job_id,
                    level,
                    message,
                    at: DateTime::parse_from_rfc3339(&at)?.with_timezone(&Utc),
                    module,
                    event_code,
                    trace_id,
                    exception_type,
                    stack_summary,
                    metadata: metadata_json
                        .as_deref()
                        .map(serde_json::from_str)
                        .transpose()?
                        .unwrap_or_default(),
                });
            }
            Ok(logs)
        })
        .await
    }

    pub async fn seen_urls(&self, urls: Vec<String>) -> Result<HashSet<String>, StoreError> {
        let postgres_urls = urls.clone();
        let mut seen = self
            .with_connection(move |connection| {
                let mut statement =
                    connection.prepare("SELECT 1 FROM scanned_targets WHERE url = ?1 LIMIT 1")?;
                let mut seen = HashSet::new();
                for url in urls {
                    if statement.exists([&url])? {
                        seen.insert(url);
                    }
                }
                Ok(seen)
            })
            .await?;
        if let Some(mirror) = self.postgres.read().await.clone()
            && mirror.is_available()
        {
            match postgres_operation(mirror.seen_urls(&postgres_urls)).await {
                Ok(urls) => seen.extend(urls),
                Err(error) => report_postgres_failure(&mirror, "查询增量目标", error),
            }
        }
        Ok(seen)
    }

    pub async fn record_scanned_target(
        &self,
        job_id: Uuid,
        url: String,
        response_fingerprint: String,
    ) -> Result<(), StoreError> {
        let postgres_url = url.clone();
        let postgres_fingerprint = response_fingerprint.clone();
        self.with_connection(move |connection| {
            connection.execute(
                "INSERT INTO scanned_targets (url, last_job_id, last_scanned_at, response_fingerprint)
                 VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(url) DO UPDATE SET
                   last_job_id = excluded.last_job_id,
                   last_scanned_at = excluded.last_scanned_at,
                   response_fingerprint = excluded.response_fingerprint",
                params![
                    url,
                    job_id.to_string(),
                    Utc::now().to_rfc3339(),
                    response_fingerprint,
                ],
            )?;
            Ok(())
        })
        .await?;
        if let Some(mirror) = self.postgres.read().await.clone()
            && mirror.is_available()
            && let Err(error) = postgres_operation(mirror.record_scanned_target(
                job_id,
                &postgres_url,
                &postgres_fingerprint,
            ))
            .await
        {
            report_postgres_failure(&mirror, "同步增量目标", error);
        }
        Ok(())
    }

    pub async fn load_rules(&self) -> Result<Vec<ScanRule>, StoreError> {
        self.with_connection(move |connection| {
            let json: Option<String> = connection
                .query_row(
                    "SELECT value FROM settings WHERE key = 'rules'",
                    [],
                    |row| row.get(0),
                )
                .optional()?;
            json.map(|value| serde_json::from_str(&value).map_err(Into::into))
                .unwrap_or_else(|| Ok(hunt_core::default_rules()))
        })
        .await
    }

    pub async fn save_rules(&self, rules: &[ScanRule]) -> Result<(), StoreError> {
        let json = serde_json::to_string(rules).context("编码扫描规则失败")?;
        self.with_connection(move |connection| {
            connection.execute(
                "INSERT INTO settings (key, value) VALUES ('rules', ?1)
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [json],
            )?;
            Ok(())
        })
        .await
    }

    async fn with_connection<T, F>(&self, action: F) -> Result<T, StoreError>
    where
        T: Send + 'static,
        F: FnOnce(&Connection) -> anyhow::Result<T> + Send + 'static,
    {
        let connection = Arc::clone(&self.connection);
        tokio::task::spawn_blocking(move || {
            let guard = connection
                .lock()
                .map_err(|_| anyhow::anyhow!("扫描数据库锁已损坏"))?;
            action(&guard)
        })
        .await
        .map_err(|error| StoreError::Task(error.to_string()))?
        .map_err(StoreError::Other)
    }
}

async fn postgres_operation<T>(
    operation: impl Future<Output = anyhow::Result<T>>,
) -> anyhow::Result<T> {
    tokio::time::timeout(POSTGRES_OPERATION_TIMEOUT, operation)
        .await
        .context("PostgreSQL 操作超时")?
}

fn report_postgres_failure(
    mirror: &PostgresMirror,
    operation: &str,
    error: impl std::fmt::Display,
) {
    mirror.mark_unavailable();
    warn!("PostgreSQL {operation}失败，已暂停镜像写入：{error}");
}

fn request_name(json: &str) -> String {
    serde_json::from_str::<ScanRequest>(json)
        .map(|request| request.name)
        .unwrap_or_else(|_| "未命名任务".to_owned())
}

fn result_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<ScanResult> {
    let source: String = row.get(2)?;
    let category: String = row.get(6)?;
    let credential_state: String = row.get(7)?;
    let evidence: String = row.get(14)?;
    let created_at: String = row.get(15)?;
    Ok(ScanResult {
        id: parse_uuid_column(row.get::<_, String>(0)?)?,
        job_id: parse_uuid_column(row.get::<_, String>(1)?)?,
        source: parse_json_enum(&source)?,
        url: row.get(3)?,
        host: row.get(4)?,
        product: row.get(5)?,
        category: parse_json_enum(&category)?,
        credential_state: parse_json_enum(&credential_state)?,
        masked_credential: row.get(8)?,
        raw_credential: None,
        credential_fingerprint: None,
        response_fingerprint: row.get(9)?,
        duplicate_response_hosts: row.get(10)?,
        duplicate_key_hosts: row.get(11)?,
        model_count: row.get(12)?,
        balance_summary: row.get(13)?,
        evidence: serde_json::from_str(&evidence).unwrap_or_default(),
        created_at: DateTime::parse_from_rfc3339(&created_at)
            .map(|value| value.with_timezone(&Utc))
            .map_err(|error| {
                rusqlite::Error::FromSqlConversionFailure(
                    15,
                    rusqlite::types::Type::Text,
                    Box::new(error),
                )
            })?,
    })
}

fn parse_uuid_column(value: String) -> rusqlite::Result<Uuid> {
    Uuid::parse_str(&value).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(error))
    })
}

fn parse_json_enum<T: serde::de::DeserializeOwned>(value: &str) -> rusqlite::Result<T> {
    serde_json::from_str(&format!("\"{value}\"")).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(error))
    })
}

/// 同一凭证指纹或响应指纹在一次扫描中跨这么多其他主机复现时，
/// 视为蜜罐诱饵/广撒的低可信线索，将其有效性降级为可疑，避免误报“高价值密钥”。
pub(crate) const HONEYPOT_CROSS_HOST_THRESHOLD: i64 = 5;

fn parse_stage(value: &str) -> ScanStage {
    match value {
        "discovering" => ScanStage::Discovering,
        "normalizing" => ScanStage::Normalizing,
        "fingerprinting" => ScanStage::Fingerprinting,
        "extracting" => ScanStage::Extracting,
        "validating" => ScanStage::Validating,
        "persisting" => ScanStage::Persisting,
        "completed" => ScanStage::Completed,
        "cancelled" => ScanStage::Cancelled,
        "failed" => ScanStage::Failed,
        _ => ScanStage::Queued,
    }
}

fn encrypt(cipher: &Aes256Gcm, plaintext: &[u8]) -> Result<String, StoreError> {
    let mut nonce_bytes = [0_u8; NONCE_LENGTH];
    OsRng.fill_bytes(&mut nonce_bytes);
    let ciphertext = cipher
        .encrypt(Nonce::from_slice(&nonce_bytes), plaintext)
        .map_err(|_| anyhow::anyhow!("加密原始凭证失败"))?;
    let mut payload = nonce_bytes.to_vec();
    payload.extend(ciphertext);
    Ok(STANDARD.encode(payload))
}

fn load_or_create_key(path: &Path) -> anyhow::Result<Zeroizing<Vec<u8>>> {
    if path.exists() {
        let mut key = Zeroizing::new(Vec::new());
        OpenOptions::new()
            .read(true)
            .open(path)?
            .read_to_end(&mut key)?;
        anyhow::ensure!(key.len() == KEY_LENGTH, "凭证密钥长度无效");
        return Ok(key);
    }
    let mut key = Zeroizing::new(vec![0_u8; KEY_LENGTH]);
    OsRng.fill_bytes(&mut key);
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(path).context("创建凭证密钥失败")?;
    file.write_all(&key)?;
    file.sync_all()?;
    Ok(key)
}

fn migrate(connection: &Connection) -> anyhow::Result<()> {
    connection.execute_batch(
        "PRAGMA journal_mode = WAL;
         PRAGMA foreign_keys = ON;
         PRAGMA busy_timeout = 5000;
         CREATE TABLE IF NOT EXISTS jobs (
           id TEXT PRIMARY KEY,
           name TEXT NOT NULL,
           request_json TEXT NOT NULL,
           stage TEXT NOT NULL,
           progress_json TEXT NOT NULL,
           created_at TEXT NOT NULL,
           finished_at TEXT,
           error_message TEXT
         );
         CREATE TABLE IF NOT EXISTS results (
           id TEXT PRIMARY KEY,
           job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
           source TEXT NOT NULL,
           url TEXT NOT NULL,
           host TEXT NOT NULL,
           product TEXT NOT NULL,
           category TEXT NOT NULL,
           credential_state TEXT NOT NULL,
           masked_credential TEXT,
           encrypted_credential TEXT,
           credential_fingerprint TEXT,
           response_fingerprint TEXT NOT NULL,
           duplicate_response_hosts INTEGER NOT NULL DEFAULT 0,
           duplicate_key_hosts INTEGER NOT NULL DEFAULT 0,
           model_count INTEGER NOT NULL DEFAULT 0,
           balance_summary TEXT,
           evidence_json TEXT NOT NULL,
           created_at TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS job_logs (
           id INTEGER PRIMARY KEY AUTOINCREMENT,
           event_id TEXT,
           job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
           level TEXT NOT NULL,
           module TEXT,
           event_code TEXT,
           message TEXT NOT NULL,
           created_at TEXT NOT NULL,
           trace_id TEXT,
           exception_type TEXT,
           stack_summary TEXT,
           metadata_json TEXT
         );
         CREATE INDEX IF NOT EXISTS idx_job_logs_job ON job_logs(job_id, id);
         CREATE TABLE IF NOT EXISTS scanned_targets (
           url TEXT PRIMARY KEY,
           last_job_id TEXT NOT NULL,
           last_scanned_at TEXT NOT NULL,
           response_fingerprint TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS settings (
           key TEXT PRIMARY KEY,
           value TEXT NOT NULL
         );",
    )?;
    ensure_column(connection, "results", "credential_fingerprint", "TEXT")?;
    ensure_column(
        connection,
        "results",
        "duplicate_response_hosts",
        "INTEGER NOT NULL DEFAULT 0",
    )?;
    ensure_column(connection, "job_logs", "event_id", "TEXT")?;
    ensure_column(connection, "job_logs", "module", "TEXT")?;
    ensure_column(connection, "job_logs", "event_code", "TEXT")?;
    ensure_column(connection, "job_logs", "trace_id", "TEXT")?;
    ensure_column(connection, "job_logs", "exception_type", "TEXT")?;
    ensure_column(connection, "job_logs", "stack_summary", "TEXT")?;
    ensure_column(connection, "job_logs", "metadata_json", "TEXT")?;
    ensure_column(
        connection,
        "results",
        "duplicate_key_hosts",
        "INTEGER NOT NULL DEFAULT 0",
    )?;
    ensure_column(
        connection,
        "results",
        "model_count",
        "INTEGER NOT NULL DEFAULT 0",
    )?;
    ensure_column(connection, "results", "balance_summary", "TEXT")?;
    connection.execute_batch(
        "CREATE INDEX IF NOT EXISTS idx_results_job ON results(job_id, created_at DESC);
         CREATE INDEX IF NOT EXISTS idx_results_category ON results(category, created_at DESC);
         CREATE INDEX IF NOT EXISTS idx_results_fingerprint ON results(response_fingerprint);
         CREATE INDEX IF NOT EXISTS idx_results_credential ON results(credential_fingerprint);
         INSERT OR IGNORE INTO scanned_targets (url, last_job_id, last_scanned_at, response_fingerprint)
         SELECT url, job_id, MAX(created_at), response_fingerprint FROM results GROUP BY url;",
    )?;
    Ok(())
}

fn ensure_column(
    connection: &Connection,
    table: &str,
    column: &str,
    definition: &str,
) -> anyhow::Result<()> {
    let mut statement = connection.prepare(&format!("PRAGMA table_info({table})"))?;
    let columns = statement
        .query_map([], |row| row.get::<_, String>(1))?
        .collect::<Result<Vec<_>, _>>()?;
    if !columns.iter().any(|value| value == column) {
        connection.execute(
            &format!("ALTER TABLE {table} ADD COLUMN {column} {definition}"),
            [],
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use hunt_core::{CredentialState, ResultCategory, ScanMode, SourceKind, ValidationMode};

    #[tokio::test]
    async fn creates_private_store_and_default_rules() {
        let path = temporary_store_path();
        let store = HuntStore::open(&path).await.unwrap();
        assert!(store.database_path().exists());
        assert!(store.load_rules().await.unwrap().len() >= 15);
        drop(store);
        fs::remove_dir_all(path).unwrap();
    }

    #[tokio::test]
    async fn reports_job_runtime_configuration_and_start_time() {
        let path = temporary_store_path();
        let store = HuntStore::open(&path).await.unwrap();
        let job_id = Uuid::new_v4();
        let request = sample_request();
        let mut progress = ScanProgress::queued(job_id);
        store.create_job(job_id, &request, &progress).await.unwrap();
        progress.transition_to(ScanStage::Discovering, "开始发现目标。");
        store.update_progress(&progress).await.unwrap();

        let job = store.list_jobs(1).await.unwrap().remove(0);
        assert!(job.started_at.is_some());
        assert_eq!(job.concurrency, Some(1));
        assert_eq!(job.validation_mode, Some(ValidationMode::Passive));
        assert_eq!(job.retry_count, Some(0));

        drop(store);
        fs::remove_dir_all(path).unwrap();
    }

    #[tokio::test]
    async fn encrypts_credentials_and_counts_other_hosts() {
        let path = temporary_store_path();
        let store = HuntStore::open(&path).await.unwrap();
        let job_id = Uuid::new_v4();
        let request = sample_request();
        store
            .create_job(job_id, &request, &ScanProgress::queued(job_id))
            .await
            .unwrap();
        for host in ["api.example.com", "edge.example.com"] {
            store
                .insert_result(&ScanResult {
                    id: Uuid::new_v4(),
                    job_id,
                    source: SourceKind::Manual,
                    url: format!("https://{host}/"),
                    host: host.to_owned(),
                    product: "OpenAI Compatible".to_owned(),
                    category: ResultCategory::Valid,
                    credential_state: CredentialState::Valid,
                    masked_credential: Some("sk-sec…7890".to_owned()),
                    raw_credential: Some("sk-secret-value-1234567890".to_owned()),
                    credential_fingerprint: Some("same-key".to_owned()),
                    response_fingerprint: "same-response".to_owned(),
                    duplicate_response_hosts: 0,
                    duplicate_key_hosts: 0,
                    model_count: 2,
                    balance_summary: Some("余额 10".to_owned()),
                    evidence: vec!["测试证据".to_owned()],
                    created_at: Utc::now(),
                })
                .await
                .unwrap();
        }
        store.finalize_correlations(job_id).await.unwrap();
        let rows = store
            .with_connection(move |connection| {
                let mut statement = connection.prepare(
                    "SELECT encrypted_credential, duplicate_response_hosts, duplicate_key_hosts
                     FROM results WHERE job_id = ?1",
                )?;
                statement
                    .query_map([job_id.to_string()], |row| {
                        Ok((
                            row.get::<_, String>(0)?,
                            row.get::<_, u32>(1)?,
                            row.get::<_, u32>(2)?,
                        ))
                    })?
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(Into::into)
            })
            .await
            .unwrap();
        assert_eq!(rows.len(), 2);
        assert!(rows.iter().all(|row| !row.0.contains("sk-secret")));
        assert!(rows.iter().all(|row| row.1 == 1 && row.2 == 1));
        drop(store);
        fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn migrates_legacy_result_columns_before_indexes() {
        let connection = Connection::open_in_memory().unwrap();
        connection
            .execute_batch(
                "CREATE TABLE results (
                   id TEXT PRIMARY KEY,
                   job_id TEXT NOT NULL,
                   source TEXT NOT NULL,
                   url TEXT NOT NULL,
                   host TEXT NOT NULL,
                   product TEXT NOT NULL,
                   category TEXT NOT NULL,
                   credential_state TEXT NOT NULL,
                   masked_credential TEXT,
                   encrypted_credential TEXT,
                   response_fingerprint TEXT NOT NULL,
                   evidence_json TEXT NOT NULL,
                   created_at TEXT NOT NULL
                 );",
            )
            .unwrap();
        migrate(&connection).unwrap();
        let mut statement = connection.prepare("PRAGMA table_info(results)").unwrap();
        let columns = statement
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<Result<HashSet<_>, _>>()
            .unwrap();
        for column in [
            "credential_fingerprint",
            "duplicate_response_hosts",
            "duplicate_key_hosts",
            "model_count",
            "balance_summary",
        ] {
            assert!(columns.contains(column));
        }
    }

    fn temporary_store_path() -> PathBuf {
        std::env::temp_dir().join(format!("openhand-hunt-store-{}", Uuid::new_v4()))
    }

    fn sample_request() -> ScanRequest {
        ScanRequest {
            name: "测试任务".to_owned(),
            sources: vec![SourceKind::Manual],
            mode: ScanMode::Full,
            authorized_scope: vec!["example.com".to_owned()],
            authorization_confirmed: true,
            targets: vec!["https://api.example.com".to_owned()],
            vendors: Vec::new(),
            source_queries: Default::default(),
            forum_fetch_mode: Default::default(),
            validation_mode: ValidationMode::Passive,
            concurrency: 1,
            gpt_assisted: false,
        }
    }
}
