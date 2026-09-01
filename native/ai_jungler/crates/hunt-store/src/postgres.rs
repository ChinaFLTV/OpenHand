use chrono::Utc;
use hunt_core::{ScanLogEntry, ScanProgress, ScanRequest, ScanResult, ScanStage};
use serde_json::{Map, Value, json};
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
const MAX_PAGE_SIZE: u32 = 200;
const MAX_QUERY_CHARS: usize = 20_000;
const MAX_QUERY_ROWS: u32 = 500;
const SENSITIVE_COLUMNS: &[&str] = &["encrypted_credential", "credential_fingerprint"];

#[derive(Clone, Copy)]
struct ManagedTable {
    name: &'static str,
    primary_keys: &'static [&'static str],
    order_by: &'static str,
}

const MANAGED_TABLES: &[ManagedTable] = &[
    ManagedTable {
        name: "hunt_jobs",
        primary_keys: &["id"],
        order_by: "created_at",
    },
    ManagedTable {
        name: "hunt_results",
        primary_keys: &["id"],
        order_by: "created_at",
    },
    ManagedTable {
        name: "hunt_job_logs",
        primary_keys: &["id"],
        order_by: "id",
    },
    ManagedTable {
        name: "hunt_scanned_targets",
        primary_keys: &["url"],
        order_by: "last_scanned_at",
    },
];

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
               event_id TEXT,
               job_id TEXT NOT NULL REFERENCES hunt_jobs(id) ON DELETE CASCADE,
               level TEXT NOT NULL,
               module TEXT,
               event_code TEXT,
               message TEXT NOT NULL,
               created_at TIMESTAMPTZ NOT NULL,
               trace_id TEXT,
               exception_type TEXT,
               stack_summary TEXT,
               metadata JSONB
             );
             ALTER TABLE hunt_job_logs ADD COLUMN IF NOT EXISTS event_id TEXT;
             ALTER TABLE hunt_job_logs ADD COLUMN IF NOT EXISTS module TEXT;
             ALTER TABLE hunt_job_logs ADD COLUMN IF NOT EXISTS event_code TEXT;
             ALTER TABLE hunt_job_logs ADD COLUMN IF NOT EXISTS trace_id TEXT;
             ALTER TABLE hunt_job_logs ADD COLUMN IF NOT EXISTS exception_type TEXT;
             ALTER TABLE hunt_job_logs ADD COLUMN IF NOT EXISTS stack_summary TEXT;
             ALTER TABLE hunt_job_logs ADD COLUMN IF NOT EXISTS metadata JSONB;
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

    pub(crate) async fn overview(&self) -> anyhow::Result<Value> {
        let telemetry = query_scalar::<Postgres, Value>(
            "SELECT jsonb_build_object(
               'serverVersion', current_setting('server_version'),
               'databaseSizeBytes', pg_database_size(current_database()),
               'activeConnections', (
                 SELECT COUNT(*) FROM pg_stat_activity
                 WHERE datname = current_database() AND state = 'active'
               ),
               'maxConnections', current_setting('max_connections')::BIGINT,
               'transactionsCommitted', xact_commit,
               'transactionsRolledBack', xact_rollback,
               'blocksRead', blks_read,
               'blocksHit', blks_hit,
               'temporaryBytes', temp_bytes,
               'deadlocks', deadlocks
             )
             FROM pg_stat_database WHERE datname = current_database()",
        )
        .fetch_one(&self.pool)
        .await?;
        let mut tables = Vec::with_capacity(MANAGED_TABLES.len());
        for table in MANAGED_TABLES {
            let sql = format!(
                "SELECT jsonb_build_object(
                   'name', '{}',
                   'rowCount', (SELECT COUNT(*) FROM {}),
                   'totalBytes', pg_total_relation_size('public.{}'::regclass),
                   'dataBytes', pg_relation_size('public.{}'::regclass)
                 )",
                table.name, table.name, table.name, table.name,
            );
            tables.push(
                query_scalar::<Postgres, Value>(&sql)
                    .fetch_one(&self.pool)
                    .await?,
            );
        }
        Ok(json!({
            "connected": true,
            "poolSize": self.pool.size(),
            "idleConnections": self.pool.num_idle(),
            "telemetry": telemetry,
            "tables": tables,
        }))
    }

    pub(crate) async fn rows(
        &self,
        table_name: &str,
        limit: u32,
        offset: u32,
    ) -> anyhow::Result<Value> {
        let table = managed_table(table_name)?;
        let limit = limit.clamp(1, MAX_PAGE_SIZE);
        let columns = query_scalar::<Postgres, Value>(
            "SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'name', column_name,
               'dataType', data_type,
               'nullable', is_nullable = 'YES',
               'defaultValue', column_default
             ) ORDER BY ordinal_position), '[]'::jsonb)
             FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = $1
               AND column_name NOT IN ('encrypted_credential', 'credential_fingerprint')",
        )
        .bind(table.name)
        .fetch_one(&self.pool)
        .await?;
        let total = query_scalar::<Postgres, i64>(&format!("SELECT COUNT(*) FROM {}", table.name))
            .fetch_one(&self.pool)
            .await?;
        let rows = query_scalar::<Postgres, Value>(&format!(
            "SELECT COALESCE(jsonb_agg(row_data), '[]'::jsonb) FROM (
               SELECT to_jsonb(item) - 'encrypted_credential' - 'credential_fingerprint' AS row_data
               FROM {} AS item ORDER BY {} DESC LIMIT $1 OFFSET $2
             ) AS page",
            table.name, table.order_by,
        ))
        .bind(i64::from(limit))
        .bind(i64::from(offset))
        .fetch_one(&self.pool)
        .await?;
        Ok(json!({
            "table": table.name,
            "primaryKeys": table.primary_keys,
            "columns": columns,
            "rows": rows,
            "total": total,
            "limit": limit,
            "offset": offset,
        }))
    }

    pub(crate) async fn insert_row(
        &self,
        table_name: &str,
        values: Map<String, Value>,
    ) -> anyhow::Result<Value> {
        let table = managed_table(table_name)?;
        let columns = self.mutable_columns(table, values.keys()).await?;
        anyhow::ensure!(!columns.is_empty(), "至少填写一个可写字段");
        let names = columns
            .iter()
            .map(|column| quote_identifier(column))
            .collect::<Vec<_>>()
            .join(", ");
        let sql = format!(
            "WITH input AS (
               SELECT * FROM jsonb_populate_record(NULL::{}, $1::jsonb)
             )
             INSERT INTO {} ({}) SELECT {} FROM input
             RETURNING to_jsonb({})",
            table.name, table.name, names, names, table.name,
        );
        let row = query_scalar::<Postgres, Value>(&sql)
            .bind(Value::Object(values))
            .fetch_one(&self.pool)
            .await?;
        Ok(sanitize_row(row))
    }

    pub(crate) async fn update_row(
        &self,
        table_name: &str,
        keys: Map<String, Value>,
        values: Map<String, Value>,
    ) -> anyhow::Result<Option<Value>> {
        let table = managed_table(table_name)?;
        validate_primary_keys(table, &keys)?;
        let columns = self.mutable_columns(table, values.keys()).await?;
        let columns = columns
            .into_iter()
            .filter(|column| !table.primary_keys.contains(&column.as_str()))
            .collect::<Vec<_>>();
        anyhow::ensure!(!columns.is_empty(), "至少填写一个非主键字段");
        let assignments = columns
            .iter()
            .map(|column| {
                let identifier = quote_identifier(column);
                format!("{identifier} = input.{identifier}")
            })
            .collect::<Vec<_>>()
            .join(", ");
        let predicates = primary_key_predicates(table);
        let sql = format!(
            "WITH input AS (
               SELECT * FROM jsonb_populate_record(NULL::{}, $1::jsonb)
             ), keys AS (
               SELECT * FROM jsonb_populate_record(NULL::{}, $2::jsonb)
             )
             UPDATE {} AS target SET {} FROM input, keys WHERE {}
             RETURNING to_jsonb(target)",
            table.name, table.name, table.name, assignments, predicates,
        );
        let row = query_scalar::<Postgres, Value>(&sql)
            .bind(Value::Object(values))
            .bind(Value::Object(keys))
            .fetch_optional(&self.pool)
            .await?;
        Ok(row.map(sanitize_row))
    }

    pub(crate) async fn delete_row(
        &self,
        table_name: &str,
        keys: Map<String, Value>,
    ) -> anyhow::Result<Option<Value>> {
        let table = managed_table(table_name)?;
        validate_primary_keys(table, &keys)?;
        let predicates = primary_key_predicates(table);
        let sql = format!(
            "WITH keys AS (
               SELECT * FROM jsonb_populate_record(NULL::{}, $1::jsonb)
             )
             DELETE FROM {} AS target USING keys WHERE {}
             RETURNING to_jsonb(target)",
            table.name, table.name, predicates,
        );
        let row = query_scalar::<Postgres, Value>(&sql)
            .bind(Value::Object(keys))
            .fetch_optional(&self.pool)
            .await?;
        Ok(row.map(sanitize_row))
    }

    pub(crate) async fn read_only_query(
        &self,
        statement: &str,
        limit: u32,
    ) -> anyhow::Result<Value> {
        let statement = statement.trim().trim_end_matches(';').trim();
        anyhow::ensure!(!statement.is_empty(), "查询不能为空");
        anyhow::ensure!(statement.len() <= MAX_QUERY_CHARS, "查询内容过长");
        anyhow::ensure!(!statement.contains(';'), "仅允许执行一条查询");
        let normalized = statement.to_ascii_lowercase();
        anyhow::ensure!(
            normalized.starts_with("select ") || normalized.starts_with("with "),
            "仅允许 SELECT 或 WITH 查询"
        );
        let limit = limit.clamp(1, MAX_QUERY_ROWS);
        let sql = format!(
            "SELECT COALESCE(jsonb_agg(to_jsonb(result)), '[]'::jsonb) FROM (
               SELECT * FROM ({statement}) AS source_query LIMIT {limit}
             ) AS result"
        );
        let mut transaction = self.pool.begin().await?;
        query("SET TRANSACTION READ ONLY")
            .execute(&mut *transaction)
            .await?;
        query("SET LOCAL statement_timeout = '5s'")
            .execute(&mut *transaction)
            .await?;
        let rows = query_scalar::<Postgres, Value>(&sql)
            .fetch_one(&mut *transaction)
            .await?;
        transaction.commit().await?;
        Ok(json!({"rows": rows, "limit": limit}))
    }

    async fn mutable_columns<'a>(
        &self,
        table: ManagedTable,
        requested: impl Iterator<Item = &'a String>,
    ) -> anyhow::Result<Vec<String>> {
        let available = query_scalar::<Postgres, String>(
            "SELECT column_name FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = $1",
        )
        .bind(table.name)
        .fetch_all(&self.pool)
        .await?
        .into_iter()
        .collect::<HashSet<_>>();
        let mut columns = Vec::new();
        for column in requested {
            anyhow::ensure!(available.contains(column), "字段 {column} 不存在");
            anyhow::ensure!(
                !SENSITIVE_COLUMNS.contains(&column.as_str()),
                "字段 {column} 受保护"
            );
            columns.push(column.clone());
        }
        columns.sort();
        Ok(columns)
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
        .bind(progress.stage.as_str())
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
        .bind(progress.stage.as_str())
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
        query(
            "UPDATE hunt_results SET category = 'suspicious'
             WHERE job_id = $1
               AND category IN ('valid', 'high_value')
               AND (duplicate_key_hosts >= $2 OR duplicate_response_hosts >= $2)",
        )
        .bind(job_id.to_string())
        .bind(crate::HONEYPOT_CROSS_HOST_THRESHOLD)
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
        let metadata = serde_json::to_value(&entry.metadata)?;
        query(
            "INSERT INTO hunt_job_logs (
               event_id, job_id, level, module, event_code, message, created_at,
               trace_id, exception_type, stack_summary, metadata
             ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        )
        .bind(entry.id.map(|value| value.to_string()))
        .bind(entry.job_id.to_string())
        .bind(&entry.level)
        .bind(&entry.module)
        .bind(&entry.event_code)
        .bind(&entry.message)
        .bind(entry.at)
        .bind(&entry.trace_id)
        .bind(&entry.exception_type)
        .bind(&entry.stack_summary)
        .bind(metadata)
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

fn managed_table(name: &str) -> anyhow::Result<ManagedTable> {
    MANAGED_TABLES
        .iter()
        .copied()
        .find(|table| table.name == name.trim())
        .ok_or_else(|| anyhow::anyhow!("不支持管理数据表：{}", name.trim()))
}

fn validate_primary_keys(table: ManagedTable, keys: &Map<String, Value>) -> anyhow::Result<()> {
    for key in table.primary_keys {
        anyhow::ensure!(
            keys.get(*key).is_some_and(|value| !value.is_null()),
            "缺少主键 {key}"
        );
    }
    Ok(())
}

fn primary_key_predicates(table: ManagedTable) -> String {
    table
        .primary_keys
        .iter()
        .map(|column| {
            let identifier = quote_identifier(column);
            format!("target.{identifier} = keys.{identifier}")
        })
        .collect::<Vec<_>>()
        .join(" AND ")
}

fn quote_identifier(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\"\""))
}

fn sanitize_row(mut row: Value) -> Value {
    if let Some(object) = row.as_object_mut() {
        for column in SENSITIVE_COLUMNS {
            object.remove(*column);
        }
    }
    row
}

fn json_enum<T: serde::Serialize>(value: T) -> anyhow::Result<String> {
    Ok(serde_json::to_value(value)?
        .as_str()
        .unwrap_or_default()
        .to_owned())
}
