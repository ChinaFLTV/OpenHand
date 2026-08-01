use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use url::Url;
use uuid::Uuid;

pub const MAX_SCAN_TARGETS: usize = 10_000;
pub const MAX_SCAN_CONCURRENCY: usize = 128;
pub const CANDIDATE_ARTIFACT_TEXT_KEY: &str = "artifact_text";
pub const CANDIDATE_ARTIFACT_URL_KEY: &str = "artifact_url";

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ScanMode {
    #[default]
    Incremental,
    Full,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceKind {
    Manual,
    Github,
    GithubArtifact,
    Gitee,
    Gitcode,
    Fofa,
    Shodan,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ContentEncoding {
    Base64,
    Base64Url,
    Url,
    Hex,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ValidationMode {
    #[default]
    Passive,
    AuthorizedActive,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanRequest {
    pub name: String,
    pub sources: Vec<SourceKind>,
    pub mode: ScanMode,
    pub authorized_scope: Vec<String>,
    pub authorization_confirmed: bool,
    #[serde(default)]
    pub targets: Vec<String>,
    #[serde(default)]
    pub vendors: Vec<String>,
    #[serde(default)]
    pub source_queries: BTreeMap<String, String>,
    #[serde(default)]
    pub validation_mode: ValidationMode,
    #[serde(default = "default_concurrency")]
    pub concurrency: usize,
    #[serde(default)]
    pub gpt_assisted: bool,
}

const fn default_concurrency() -> usize {
    24
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanRule {
    pub id: String,
    pub vendor: String,
    pub protocol: String,
    pub enabled: bool,
    pub credential_patterns: Vec<String>,
    pub context_terms: Vec<String>,
    #[serde(default)]
    pub content_encodings: Vec<ContentEncoding>,
    pub model_paths: Vec<String>,
    #[serde(default)]
    pub balance_paths: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Candidate {
    pub source: SourceKind,
    pub target: String,
    pub discovered_at: DateTime<Utc>,
    #[serde(default)]
    pub metadata: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NormalizedTarget {
    pub source: SourceKind,
    pub url: Url,
    pub canonical_url: String,
    pub host: String,
    #[serde(default)]
    pub metadata: BTreeMap<String, String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ScanStage {
    Queued,
    Discovering,
    Normalizing,
    Fingerprinting,
    Extracting,
    Validating,
    Persisting,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanProgress {
    pub job_id: Uuid,
    pub stage: ScanStage,
    pub discovered: u64,
    pub candidates: u64,
    pub valid: u64,
    pub high_value: u64,
    pub processed: u64,
    pub total: u64,
    pub message: String,
    pub updated_at: DateTime<Utc>,
}

impl ScanProgress {
    pub fn queued(job_id: Uuid) -> Self {
        Self {
            job_id,
            stage: ScanStage::Queued,
            discovered: 0,
            candidates: 0,
            valid: 0,
            high_value: 0,
            processed: 0,
            total: 0,
            message: "任务已进入队列。".to_owned(),
            updated_at: Utc::now(),
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ResultCategory {
    Valid,
    Suspicious,
    HighValue,
    Honeypot,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CredentialState {
    NotFound,
    Candidate,
    Valid,
    Invalid,
    Unreachable,
    RateLimited,
    Unauthorized,
    Duplicate,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanResult {
    pub id: Uuid,
    pub job_id: Uuid,
    pub source: SourceKind,
    pub url: String,
    pub host: String,
    pub product: String,
    pub category: ResultCategory,
    pub credential_state: CredentialState,
    pub masked_credential: Option<String>,
    #[serde(skip_serializing)]
    pub raw_credential: Option<String>,
    #[serde(skip)]
    pub credential_fingerprint: Option<String>,
    pub response_fingerprint: String,
    pub duplicate_response_hosts: u32,
    pub duplicate_key_hosts: u32,
    pub model_count: u32,
    pub balance_summary: Option<String>,
    pub evidence: Vec<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanLogEntry {
    pub job_id: Uuid,
    pub level: String,
    pub message: String,
    pub at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanJobSummary {
    pub id: Uuid,
    pub name: String,
    pub stage: ScanStage,
    pub sources: Vec<SourceKind>,
    pub mode: ScanMode,
    pub authorized_scope: Vec<String>,
    pub progress: ScanProgress,
    pub created_at: DateTime<Utc>,
    pub finished_at: Option<DateTime<Utc>>,
    pub error_message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SourceQuota {
    pub source: SourceKind,
    pub configured: bool,
    pub available: bool,
    pub remaining: Option<u64>,
    pub limit: Option<u64>,
    pub resets_at: Option<DateTime<Utc>>,
    pub message: String,
}
