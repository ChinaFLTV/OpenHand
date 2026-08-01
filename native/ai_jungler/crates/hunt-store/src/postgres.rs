use chrono::Utc;
use hunt_core::{ScanLogEntry, ScanProgress, ScanRequest, ScanResult, ScanStage};
use sqlx_core::{query::query, query_scalar::query_scalar, raw_sql::raw_sql};
use sqlx_postgres::{PgPool, PgPoolOptions, Postgres};
use std::{
    collections::HashSet,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
use uuid::Uuid;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Clone)]
pub(crate) struct PostgresMirror {
    pool: PgPool,
    available: Arc<AtomicBool>,
}

impl PostgresMirror {
    pub(crate) async fn connect(url: &str) -> anyhow::Result<Self> {
        let pool = PgPoolOptions::new()
            .max_connections(4)
            .acquire_timeout(CONNECT_TIMEOUT)
            .connect(url)
            .await?;
        raw_sql(
            "CREATE TABLE IF NOT EXISTS hunt_jobs (
               id TEXT PRIMARY KEY,
               name TEXT NOT NULL,
               request_json JSONB NOT NULL,
               stage TEXT NOT NULL,
               progress_json JSONB NOT NULL,
               created_at TIMESTAMPTZ NOT NULL,
               finished_at TIMESTAMPTZ,
               error_message TEXT
             );
             CREATE TABLE IF NOT EXISTS hunt_results (
               id TEXT PRIMARY KEY,
               job_id TEXT NOT NULL REFERENCES hunt_jobs(id) ON DELETE CASCADE,
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
               evidence_json JSONB NOT NULL,
               created_at TIMESTAMPTZ NOT NULL
             );
             CREATE INDEX IF NOT EXISTS hunt_results_job_idx ON hunt_results(job_id, created_at DESC);
             CREATE INDEX IF NOT EXISTS hunt_results_response_idx ON hunt_results(response_fingerprint);
             CREATE INDEX IF NOT EXISTS hunt_results_credential_idx ON hunt_results(credential_fingerprint);
             CREATE TABLE IF NOT EXISTS hunt_job_logs (
               id BIGSERIAL PRIMARY KEY,
               job_id TEXT NOT NULL REFERENCES hunt_jobs(id) ON DELETE CASCADE,
               level TEXT NOT NULL,
               message TEXT NOT NULL,
               created_at TIMESTAMPTZ NOT NULL
             );
             CREATE INDEX IF NOT EXISTS hunt_job_logs_job_idx ON hunt_job_logs(job_id, id);
             CREATE TABLE IF NOT EXISTS hunt_scanned_targets (
               url TEXT PRIMARY KEY,
               last_job_id TEXT NOT NULL,
               last_scanned_at TIMESTAMPTZ NOT NULL,
               response_fingerprint TEXT NOT NULL
             );",
        )
        .execute(&pool)
        .await?;
        Ok(Self {
            pool,
            available: Arc::new(AtomicBool::new(true)),
        })
    }

    pub(crate) async fn ping(&self) -> anyhow::Result<()> {
        let result = query("SELECT 1").execute(&self.pool).await.map(|_| ());
        self.available.store(result.is_ok(), Ordering::Relaxed);
        result.map_err(Into::into)
    }

    pub(crate) fn is_available(&self) -> bool {
        self.available.load(Ordering::Relaxed)
    }

    pub(crate) fn mark_unavailable(&self) {
        self.available.store(false, Ordering::Relaxed);
    }

    pub(crate) async fn close(&self) {
        self.pool.close().await;
    }

    pub(crate) async fn create_job(
        &self,
        id: Uuid,
        request: &ScanRequest,
        progress: &ScanProgress,
    ) -> anyhow::Result<()> {
        query(
            "INSERT INTO hunt_jobs (id, name, request_json, stage, progress_json, created_at)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT(id) DO UPDATE SET
               name = excluded.name,
               request_json = excluded.request_json,
               stage = excluded.stage,
               progress_json = excluded.progress_json",
        )
        .bind(id.to_string())
        .bind(&request.name)
        .bind(serde_json::to_value(request)?)
        .bind(stage_name(progress.stage))
        .bind(serde_json::to_value(progress)?)
        .bind(Utc::now())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub(crate) async fn update_progress(&self, progress: &ScanProgress) -> anyhow::Result<()> {
        let finished_at = matches!(
            progress.stage,
            ScanStage::Completed | ScanStage::Cancelled | ScanStage::Failed
        )
        .then(Utc::now);
        query(
            "UPDATE hunt_jobs SET stage = $2, progress_json = $3,
               finished_at = COALESCE($4, finished_at) WHERE id = $1",
        )
        .bind(progress.job_id.to_string())
        .bind(stage_name(progress.stage))
        .bind(serde_json::to_value(progress)?)
        .bind(finished_at)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub(crate) async fn set_job_error(&self, id: Uuid, message: &str) -> anyhow::Result<()> {
        query(
            "UPDATE hunt_jobs SET stage = 'failed', error_message = $2, finished_at = $3
             WHERE id = $1",
        )
        .bind(id.to_string())
        .bind(message)
        .bind(Utc::now())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub(crate) async fn insert_result(
        &self,
        result: &ScanResult,
        encrypted_credential: Option<&str>,
    ) -> anyhow::Result<()> {
        query(
            "INSERT INTO hunt_results (
               id, job_id, source, url, host, product, category, credential_state,
               masked_credential, encrypted_credential, credential_fingerprint,
               response_fingerprint, duplicate_response_hosts, duplicate_key_hosts,
               model_count, balance_summary, evidence_json, created_at
             ) VALUES (
               $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
               $15, $16, $17, $18
             )
             ON CONFLICT(id) DO UPDATE SET
               category = excluded.category,
               credential_state = excluded.credential_state,
               duplicate_response_hosts = excluded.duplicate_response_hosts,
               duplicate_key_hosts = excluded.duplicate_key_hosts,
               model_count = excluded.model_count,
               balance_summary = excluded.balance_summary,
               evidence_json = excluded.evidence_json",
        )
        .bind(result.id.to_string())
        .bind(result.job_id.to_string())
        .bind(json_enum(result.source)?)
        .bind(&result.url)
        .bind(&result.host)
        .bind(&result.product)
        .bind(json_enum(result.category)?)
        .bind(json_enum(result.credential_state)?)
        .bind(result.masked_credential.as_deref())
        .bind(encrypted_credential)
        .bind(result.credential_fingerprint.as_deref())
        .bind(&result.response_fingerprint)
        .bind(result.duplicate_response_hosts as i64)
        .bind(result.duplicate_key_hosts as i64)
        .bind(result.model_count as i64)
        .bind(result.balance_summary.as_deref())
        .bind(serde_json::to_value(&result.evidence)?)
        .bind(result.created_at)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub(crate) async fn finalize_correlations(&self, job_id: Uuid) -> anyhow::Result<()> {
        let mut transaction = self.pool.begin().await?;
        query(
            "UPDATE hunt_results AS current SET duplicate_key_hosts = GREATEST((
               SELECT COUNT(DISTINCT duplicate.host) - 1 FROM hunt_results AS duplicate
               WHERE duplicate.job_id = current.job_id
                 AND duplicate.credential_fingerprint = current.credential_fingerprint
             ), 0)
             WHERE current.job_id = $1 AND current.credential_fingerprint IS NOT NULL",
        )
        .bind(job_id.to_string())
        .execute(&mut *transaction)
        .await?;
        query(
            "UPDATE hunt_results AS current SET duplicate_response_hosts = (
               SELECT GREATEST(COUNT(DISTINCT duplicate.host) - 1, 0)
               FROM hunt_results AS duplicate
               WHERE duplicate.job_id = current.job_id
                 AND duplicate.response_fingerprint = current.response_fingerprint
             ) WHERE current.job_id = $1",
        )
        .bind(job_id.to_string())
        .execute(&mut *transaction)
        .await?;
        transaction.commit().await?;
        Ok(())
    }

    pub(crate) async fn seen_urls(&self, urls: &[String]) -> anyhow::Result<HashSet<String>> {
        if urls.is_empty() {
            return Ok(HashSet::new());
        }
        let values = query_scalar::<Postgres, String>(
            "SELECT url FROM hunt_scanned_targets WHERE url = ANY($1)",
        )
        .bind(urls)
        .fetch_all(&self.pool)
        .await?;
        Ok(values.into_iter().collect())
    }

    pub(crate) async fn insert_log(&self, entry: &ScanLogEntry) -> anyhow::Result<()> {
        query(
            "INSERT INTO hunt_job_logs (job_id, level, message, created_at)
             VALUES ($1, $2, $3, $4)",
        )
        .bind(entry.job_id.to_string())
        .bind(&entry.level)
        .bind(&entry.message)
        .bind(entry.at)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub(crate) async fn record_scanned_target(
        &self,
        job_id: Uuid,
        url: &str,
        response_fingerprint: &str,
    ) -> anyhow::Result<()> {
        query(
            "INSERT INTO hunt_scanned_targets
               (url, last_job_id, last_scanned_at, response_fingerprint)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT(url) DO UPDATE SET
               last_job_id = excluded.last_job_id,
               last_scanned_at = excluded.last_scanned_at,
               response_fingerprint = excluded.response_fingerprint",
        )
        .bind(url)
        .bind(job_id.to_string())
        .bind(Utc::now())
        .bind(response_fingerprint)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub(crate) async fn delete_job(&self, id: Uuid) -> anyhow::Result<()> {
        query("DELETE FROM hunt_jobs WHERE id = $1")
            .bind(id.to_string())
            .execute(&self.pool)
            .await?;
        Ok(())
    }
}

fn json_enum<T: serde::Serialize>(value: T) -> anyhow::Result<String> {
    Ok(serde_json::to_value(value)?
        .as_str()
        .unwrap_or_default()
        .to_owned())
}

fn stage_name(stage: ScanStage) -> &'static str {
    match stage {
        ScanStage::Queued => "queued",
        ScanStage::Discovering => "discovering",
        ScanStage::Normalizing => "normalizing",
        ScanStage::Fingerprinting => "fingerprinting",
        ScanStage::Extracting => "extracting",
        ScanStage::Validating => "validating",
        ScanStage::Persisting => "persisting",
        ScanStage::Completed => "completed",
        ScanStage::Cancelled => "cancelled",
        ScanStage::Failed => "failed",
    }
}
