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
    Nodeseek,
    LinuxDo,
    V2ex,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ForumFetchMode {
    #[default]
    JinaFallback,
    Playwright,
    Cdp,
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
    pub forum_fetch_mode: ForumFetchMode,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_hash: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub created_at: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub snapshot_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub change_source: Option<String>,
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

impl ScanStage {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Queued => "queued",
            Self::Discovering => "discovering",
            Self::Normalizing => "normalizing",
            Self::Fingerprinting => "fingerprinting",
            Self::Extracting => "extracting",
            Self::Validating => "validating",
            Self::Persisting => "persisting",
            Self::Completed => "completed",
            Self::Cancelled => "cancelled",
            Self::Failed => "failed",
        }
    }
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub failure_stage: Option<ScanStage>,
    #[serde(default)]
    pub stage_timings: Vec<StageTiming>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StageTiming {
    pub stage: ScanStage,
    pub started_at: DateTime<Utc>,
    pub finished_at: Option<DateTime<Utc>>,
    pub duration_ms: Option<u64>,
    pub input_count: Option<u64>,
    pub output_count: Option<u64>,
    pub message: Option<String>,
}

impl ScanProgress {
    pub fn queued(job_id: Uuid) -> Self {
        let now = Utc::now();
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
            updated_at: now,
            failure_stage: None,
            stage_timings: vec![StageTiming {
                stage: ScanStage::Queued,
                started_at: now,
                finished_at: None,
                duration_ms: None,
                input_count: None,
                output_count: None,
                message: Some("任务已进入队列。".to_owned()),
            }],
        }
    }

    pub fn transition_to(&mut self, stage: ScanStage, message: &str) {
        let now = Utc::now();
        let previous_counts = self
            .stage_timings
            .last()
            .map(|timing| self.stage_counts(timing.stage));
        if let Some(previous) = self.stage_timings.last_mut()
            && previous.finished_at.is_none()
        {
            previous.finished_at = Some(now);
            previous.duration_ms = Some(
                now.signed_duration_since(previous.started_at)
                    .num_milliseconds()
                    .max(0) as u64,
            );
            if let Some((input_count, output_count)) = previous_counts {
                previous.input_count = previous.input_count.or(input_count);
                previous.output_count = output_count;
            }
        }
        let terminal = matches!(
            stage,
            ScanStage::Completed | ScanStage::Cancelled | ScanStage::Failed
        );
        let (input_count, output_count) = self.stage_counts(stage);
        self.stage_timings.push(StageTiming {
            stage,
            started_at: now,
            finished_at: terminal.then_some(now),
            duration_ms: terminal.then_some(0),
            input_count,
            output_count: if terminal { output_count } else { None },
            message: Some(message.to_owned()),
        });
        self.stage = stage;
        self.message = message.to_owned();
        self.updated_at = now;
    }

    fn stage_counts(&self, stage: ScanStage) -> (Option<u64>, Option<u64>) {
        match stage {
            ScanStage::Queued => (Some(0), Some(0)),
            ScanStage::Discovering => (Some(0), Some(self.discovered)),
            ScanStage::Normalizing => (Some(self.discovered), Some(self.candidates)),
            ScanStage::Fingerprinting | ScanStage::Extracting => {
                (Some(self.candidates), Some(self.processed))
            }
            ScanStage::Validating => (Some(self.processed), Some(self.valid)),
            ScanStage::Persisting => (Some(self.processed), Some(self.valid)),
            ScanStage::Completed | ScanStage::Cancelled | ScanStage::Failed => {
                (Some(self.processed), Some(self.valid))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{ForumFetchMode, ScanProgress, ScanStage};
    use uuid::Uuid;

    #[test]
    fn stage_timings_capture_input_and_output_counts() {
        let mut progress = ScanProgress::queued(Uuid::new_v4());

        progress.transition_to(ScanStage::Discovering, "开始发现目标。");
        progress.discovered = 12;
        progress.transition_to(ScanStage::Normalizing, "开始归一化目标。");
        assert_eq!(progress.stage_timings[1].input_count, Some(0));
        assert_eq!(progress.stage_timings[1].output_count, Some(12));

        progress.candidates = 7;
        progress.transition_to(ScanStage::Fingerprinting, "开始计算指纹。");
        assert_eq!(progress.stage_timings[2].input_count, Some(12));
        assert_eq!(progress.stage_timings[2].output_count, Some(7));

        progress.processed = 6;
        progress.transition_to(ScanStage::Extracting, "开始提取候选。");
        assert_eq!(progress.stage_timings[3].input_count, Some(7));
        assert_eq!(progress.stage_timings[3].output_count, Some(6));

        progress.valid = 4;
        progress.transition_to(ScanStage::Completed, "扫描任务已完成。");
        let completed = progress.stage_timings.last().expect("终态阶段应存在");
        assert_eq!(completed.input_count, Some(6));
        assert_eq!(completed.output_count, Some(4));
        assert!(completed.finished_at.is_some());
    }

    #[test]
    fn cdp_forum_mode_uses_stable_storage_value() {
        assert_eq!(
            serde_json::to_string(&ForumFetchMode::Cdp).unwrap(),
            "\"cdp\""
        );
        assert_eq!(
            serde_json::from_str::<ForumFetchMode>("\"cdp\"").unwrap(),
            ForumFetchMode::Cdp
        );
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<Uuid>,
    pub job_id: Uuid,
    pub level: String,
    pub message: String,
    pub at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub module: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub event_code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trace_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exception_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stack_summary: Option<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub metadata: BTreeMap<String, serde_json::Value>,
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
    pub started_at: Option<DateTime<Utc>>,
    pub cancelled_at: Option<DateTime<Utc>>,
    pub cancel_reason: Option<String>,
    pub last_checkpoint_at: Option<DateTime<Utc>>,
    pub failure_stage: Option<ScanStage>,
    pub retry_count: Option<u32>,
    pub concurrency: Option<usize>,
    pub validation_mode: Option<ValidationMode>,
    pub forum_fetch_mode: Option<ForumFetchMode>,
    pub gpt_assisted: Option<bool>,
    pub stage_timings: Vec<StageTiming>,
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
    pub checked_at: Option<DateTime<Utc>>,
    pub latency_ms: Option<u64>,
    pub http_status: Option<u16>,
    pub error_code: Option<String>,
    pub last_success_at: Option<DateTime<Utc>>,
    pub last_failure_at: Option<DateTime<Utc>>,
}
