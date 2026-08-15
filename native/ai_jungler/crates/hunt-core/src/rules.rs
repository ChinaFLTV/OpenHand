use crate::{ContentEncoding, ScanRule};
use base64::{Engine, engine::general_purpose};
use regex::Regex;
use std::{
    collections::{HashMap, HashSet},
    sync::LazyLock,
};
use thiserror::Error;

pub struct CompiledRuleSet {
    rules: Vec<(ScanRule, Vec<Regex>)>,
}

#[derive(Clone, Debug)]
pub struct CredentialFinding {
    pub vendor: String,
    pub secret: String,
    pub model_paths: Vec<String>,
    pub balance_paths: Vec<String>,
    pub assisted: bool,
}

const MAX_DECODE_INPUT_BYTES: usize = 512 * 1024;
const MAX_DECODED_VARIANTS: usize = 32;
/// 文档/示例中常见的占位符片段。命中即视为噪声，不作为凭证线索，
/// 降低"示例密钥/模板变量"造成的误报。
const NOISE_SUBSTRINGS: &[&str] = &[
    "example",
    "changeme",
    "change_me",
    "placeholder",
    "your-",
    "your_",
    "yourkey",
    "yourapikey",
    "dummy",
    "sample",
    "test-key",
    "testkey",
    "redacted",
    "<your",
    "insert-",
    "replace-",
    "xxxxxx",
];
/// 同一字符连续出现达到此长度即判为占位符（如 sk-aaaaaaaa、000000...）。
const MAX_REPEATED_RUN: usize = 8;
static BASE64_FRAGMENT_PATTERN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"[A-Za-z0-9+/_-]{20,}={0,2}").expect("内置 Base64 正则必须有效"));
static HEX_FRAGMENT_PATTERN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"[A-Fa-f0-9]{16,}").expect("内置十六进制正则必须有效"));

#[derive(Debug, Error)]
pub enum RuleError {
    #[error("规则 {rule_id} 的正则无效：{message}")]
    InvalidRegex { rule_id: String, message: String },
    #[error("规则 {rule_id} 的 {field} 端点无效：{path}")]
    InvalidEndpointPath {
        rule_id: String,
        field: &'static str,
        path: String,
    },
}

impl CompiledRuleSet {
    pub fn compile(rules: Vec<ScanRule>) -> Result<Self, RuleError> {
        let mut compiled = Vec::new();
        for rule in rules.into_iter().filter(|rule| rule.enabled) {
            validate_paths(&rule.id, "模型", &rule.model_paths)?;
            validate_paths(&rule.id, "余额", &rule.balance_paths)?;
            let patterns = rule
                .credential_patterns
                .iter()
                .map(|pattern| {
                    Regex::new(pattern).map_err(|error| RuleError::InvalidRegex {
                        rule_id: rule.id.clone(),
                        message: error.to_string(),
                    })
                })
                .collect::<Result<Vec<_>, _>>()?;
            compiled.push((rule, patterns));
        }
        Ok(Self { rules: compiled })
    }

    pub fn extract(&self, text: &str) -> Vec<CredentialFinding> {
        let mut findings = Vec::new();
        let mut seen = HashSet::new();
        let mut decoded_cache = HashMap::<Vec<ContentEncoding>, Vec<String>>::new();
        for (rule, patterns) in &self.rules {
            let candidates = decoded_cache
                .entry(rule.content_encodings.clone())
                .or_insert_with(|| decoded_variants(text, &rule.content_encodings));
            for candidate in candidates {
                extract_from_candidate(rule, patterns, candidate, &mut seen, &mut findings);
            }
        }
        findings
    }

    pub fn assisted_finding(&self, vendor: &str, secret: &str) -> Option<CredentialFinding> {
        let vendor = vendor.trim();
        let secret = secret.trim();
        if vendor.is_empty()
            || secret.len() < 8
            || secret.len() > 4096
            || secret.contains(['\r', '\n'])
            || is_placeholder_secret(secret)
        {
            return None;
        }
        self.rules
            .iter()
            .find(|(rule, _)| rule.vendor.eq_ignore_ascii_case(vendor))
            .map(|(rule, _)| CredentialFinding {
                vendor: rule.vendor.clone(),
                secret: secret.to_owned(),
                model_paths: rule.model_paths.clone(),
                balance_paths: rule.balance_paths.clone(),
                assisted: true,
            })
    }
}

fn validate_paths(rule_id: &str, field: &'static str, paths: &[String]) -> Result<(), RuleError> {
    for path in paths {
        let value = path.trim();
        if !value.starts_with('/')
            || value.starts_with("//")
            || value.contains("://")
            || value.contains(['\r', '\n'])
        {
            return Err(RuleError::InvalidEndpointPath {
                rule_id: rule_id.to_owned(),
                field,
                path: path.clone(),
            });
        }
    }
    Ok(())
}

pub fn default_rules() -> Vec<ScanRule> {
    [
        // ── 唯一前缀 provider（高精度，优先匹配）──────────────────────
        ("anthropic", "Anthropic", "Anthropic", r#"(?i)(?:api[_-]?key|x-api-key|authorization)[\"' :=]+(?P<secret>sk-ant-[A-Za-z0-9_-]{20,})"#, &["anthropic", "claude", "x-api-key"][..], &["/v1/models"][..], &[][..]),
        ("gemini", "Gemini", "Google Gemini", r#"(?i)(?:api[_-]?key|key)[\"' :=]+(?P<secret>AIza[A-Za-z0-9_-]{24,})"#, &["gemini", "generativelanguage", "generatecontent"][..], &["/v1beta/models"][..], &[][..]),
        ("openai_official", "OpenAI", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>sk-(?:proj|admin|svcacct)-[A-Za-z0-9_-]{20,})"#, &["openai"][..], &["/v1/models"][..], &[][..]),
        ("grok", "Grok", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>xai-[A-Za-z0-9_-]{20,})"#, &["x.ai", "grok"][..], &["/v1/models"][..], &[][..]),
        ("nvidia", "NVIDIA", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>nvapi-[A-Za-z0-9_-]{20,})"#, &["nvidia", "integrate.api.nvidia"][..], &["/v1/models"][..], &[][..]),
        ("groq", "Groq", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>gsk_[A-Za-z0-9_-]{20,})"#, &["groq"][..], &["/openai/v1/models"][..], &[][..]),
        ("openrouter", "OpenRouter", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>sk-or-[A-Za-z0-9_-]{20,})"#, &["openrouter"][..], &["/api/v1/models"][..], &[][..]),
        ("replicate", "Replicate", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>r8_[A-Za-z0-9_-]{20,})"#, &["replicate"][..], &["/v1/models"][..], &[][..]),
        ("qoder", "Qoder", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>pt-[A-Za-z0-9_-]{20,})"#, &["qoder"][..], &["/v1/models"][..], &[][..]),
        ("kiro", "Kiro", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>ksk_[A-Za-z0-9_-]{20,})"#, &["kiro"][..], &[][..], &[][..]),
        ("aws_bedrock", "AWS Bedrock", "AWS Bedrock", r#"(?i)(?:access[_-]?key|aws[_-]?key|secret[_-]?key)[\"' :=]+(?P<secret>ABSK[A-Za-z0-9_-]{16,})"#, &["bedrock", "amazonaws"][..], &[][..], &[][..]),
        ("cursor", "Cursor", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization|token)[\"' :=]+(?P<secret>crsr_[A-Za-z0-9_-]{20,})"#, &["cursor"][..], &[][..], &[][..]),
        // ── 上下文门控 provider（无唯一前缀，靠域名/产品名区分）────────
        ("azure_openai", "Azure OpenAI", "Azure OpenAI", r#"(?i)(?:api[_-]?key)[\"' :=]+(?P<secret>[A-Fa-f0-9]{32})"#, &["azure", "openai", "api-version"][..], &["/openai/models?api-version=2024-10-21"][..], &[][..]),
        ("deepseek", "DeepSeek", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>sk-[A-Za-z0-9]{24,})"#, &["deepseek"][..], &["/v1/models"][..], &["/user/balance"][..]),
        ("qwen", "Qwen", "OpenAI Compatible", r#"(?i)(?:dashscope[_-]?api[_-]?key|api[_-]?key)[\"' :=]+(?P<secret>sk-[A-Za-z0-9]{24,})"#, &["dashscope", "qwen"][..], &["/compatible-mode/v1/models"][..], &[][..]),
        ("doubao", "豆包", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{32,})"#, &["doubao", "volcengine", "ark.cn"][..], &["/api/v3/models"][..], &[][..]),
        ("kling", "可灵", "Kling", r#"(?i)(?:access[_-]?key|api[_-]?key)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{20,})"#, &["kling", "klingai"][..], &[][..], &[][..]),
        ("glm", "GLM", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>[A-Za-z0-9._-]{30,})"#, &["bigmodel", "zhipu", "glm"][..], &["/api/paas/v4/models"][..], &[][..]),
        ("mimo", "Mimo", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{24,})"#, &["mimo"][..], &["/v1/models"][..], &[][..]),
        ("minimax", "MiniMax", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{24,})"#, &["minimax"][..], &["/v1/models"][..], &[][..]),
        ("kimi", "Kimi", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>sk-[A-Za-z0-9]{20,})"#, &["moonshot", "kimi"][..], &["/v1/models"][..], &["/v1/users/me/balance"][..]),
        ("longcat", "LongCat", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{24,})"#, &["longcat"][..], &["/v1/models"][..], &[][..]),
        ("mistral", "Mistral", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{30,})"#, &["mistral"][..], &["/v1/models"][..], &[][..]),
        ("cohere", "Cohere", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization|cohere[_-]?key)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{30,})"#, &["cohere"][..], &["/v1/models"][..], &[][..]),
        ("together", "Together", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{40,})"#, &["together"][..], &["/v1/models"][..], &[][..]),
        ("fireworks", "Fireworks", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{30,})"#, &["fireworks"][..], &["/inference/v1/models"][..], &[][..]),
        ("siliconflow", "SiliconFlow", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>sk-[A-Za-z0-9_-]{20,})"#, &["siliconflow"][..], &["/v1/models"][..], &[][..]),
        ("windsurf", "Windsurf", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization|token)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{24,})"#, &["windsurf", "codeium"][..], &[][..], &[][..]),
        ("ksyun", "Ksyun", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>[A-Za-z0-9_-]{24,})"#, &["ksyun", "kspmas"][..], &["/v1/models"][..], &[][..]),
        // ── 通用兜底（必须排在最后）──────────────────────────────────
        ("openai", "OpenAI Compatible", "OpenAI Compatible", r#"(?i)(?:api[_-]?key|authorization)[\"' :=]+(?P<secret>sk-[A-Za-z0-9_-]{20,})"#, &["openai", "chat/completions", "api_key"][..], &["/v1/models"][..], &[][..]),
    ]
    .into_iter()
    .map(|(id, vendor, protocol, pattern, terms, paths, balance_paths)| ScanRule {
        id: id.to_owned(),
        vendor: vendor.to_owned(),
        protocol: protocol.to_owned(),
        enabled: true,
        credential_patterns: vec![pattern.to_owned()],
        context_terms: terms.iter().map(|value| (*value).to_owned()).collect(),
        content_encodings: vec![
            ContentEncoding::Base64,
            ContentEncoding::Base64Url,
            ContentEncoding::Url,
            ContentEncoding::Hex,
        ],
        model_paths: paths.iter().map(|value| (*value).to_owned()).collect(),
        balance_paths: balance_paths
            .iter()
            .map(|value| (*value).to_owned())
            .collect(),
        version: None,
        content_hash: None,
        created_at: None,
        updated_at: None,
        snapshot_id: None,
        change_source: None,
    })
    .collect()
}

fn extract_from_candidate(
    rule: &ScanRule,
    patterns: &[Regex],
    text: &str,
    seen: &mut HashSet<String>,
    findings: &mut Vec<CredentialFinding>,
) {
    let lowered = text.to_ascii_lowercase();
    if !rule.context_terms.is_empty()
        && !rule
            .context_terms
            .iter()
            .any(|term| lowered.contains(&term.to_ascii_lowercase()))
    {
        return;
    }
    for pattern in patterns {
        for capture in pattern.captures_iter(text).take(20) {
            let Some(secret) = capture.name("secret").or_else(|| capture.get(1)) else {
                continue;
            };
            let secret = secret.as_str().to_owned();
            if is_placeholder_secret(&secret) {
                continue;
            }
            if seen.insert(secret.clone()) {
                findings.push(CredentialFinding {
                    vendor: rule.vendor.clone(),
                    secret,
                    model_paths: rule.model_paths.clone(),
                    balance_paths: rule.balance_paths.clone(),
                    assisted: false,
                });
            }
        }
    }
}

/// 判断提取到的密钥是否为占位符/模板噪声：命中已知占位子串，或存在超长同字符游程。
/// 真实随机密钥极少出现 8 个以上连续相同字符，因此该启发式不会误伤有效凭证。
fn is_placeholder_secret(secret: &str) -> bool {
    let lowered = secret.to_ascii_lowercase();
    if NOISE_SUBSTRINGS.iter().any(|noise| lowered.contains(noise)) {
        return true;
    }
    let mut run = 1;
    let mut previous = None;
    for character in lowered.chars() {
        if Some(character) == previous {
            run += 1;
            if run >= MAX_REPEATED_RUN {
                return true;
            }
        } else {
            run = 1;
            previous = Some(character);
        }
    }
    false
}

fn decoded_variants(text: &str, encodings: &[ContentEncoding]) -> Vec<String> {
    let mut variants = vec![text.to_owned()];
    if text.len() > MAX_DECODE_INPUT_BYTES || encodings.is_empty() {
        return variants;
    }
    let mut seen = HashSet::from([text.to_owned()]);
    for encoding in encodings {
        let current_len = variants.len();
        for index in 0..current_len {
            let candidate = variants[index].clone();
            for decoded in decode_candidates(&candidate, *encoding) {
                if !decoded.is_empty()
                    && decoded.len() <= MAX_DECODE_INPUT_BYTES
                    && seen.insert(decoded.clone())
                {
                    variants.push(decoded);
                    if variants.len() >= MAX_DECODED_VARIANTS {
                        return variants;
                    }
                }
            }
        }
    }
    variants
}

fn decode_candidates(value: &str, encoding: ContentEncoding) -> Vec<String> {
    match encoding {
        ContentEncoding::Base64 | ContentEncoding::Base64Url => {
            let url_safe = encoding == ContentEncoding::Base64Url;
            std::iter::once(value)
                .chain(
                    BASE64_FRAGMENT_PATTERN
                        .find_iter(value)
                        .map(|matched| matched.as_str()),
                )
                .filter_map(|candidate| decode_base64(candidate, url_safe))
                .take(MAX_DECODED_VARIANTS)
                .collect()
        }
        ContentEncoding::Url => urlencoding::decode(value)
            .ok()
            .map(|decoded| vec![decoded.into_owned()])
            .unwrap_or_default(),
        ContentEncoding::Hex => std::iter::once(value.trim())
            .chain(
                HEX_FRAGMENT_PATTERN
                    .find_iter(value)
                    .map(|matched| matched.as_str()),
            )
            .filter(|candidate| candidate.len() % 2 == 0)
            .filter_map(|candidate| hex::decode(candidate).ok())
            .filter_map(|decoded| String::from_utf8(decoded).ok())
            .take(MAX_DECODED_VARIANTS)
            .collect(),
    }
}

fn decode_base64(value: &str, url_safe: bool) -> Option<String> {
    let compact = value
        .chars()
        .filter(|character| !character.is_whitespace())
        .collect::<String>();
    let bytes = if url_safe {
        general_purpose::URL_SAFE
            .decode(&compact)
            .or_else(|_| general_purpose::URL_SAFE_NO_PAD.decode(&compact))
    } else {
        general_purpose::STANDARD
            .decode(&compact)
            .or_else(|_| general_purpose::STANDARD_NO_PAD.decode(&compact))
    }
    .ok()?;
    String::from_utf8(bytes).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_rules_compile() {
        CompiledRuleSet::compile(default_rules()).unwrap();
    }

    #[test]
    fn prefers_specific_vendor_for_shared_key_shape() {
        let rules = CompiledRuleSet::compile(default_rules()).unwrap();
        let findings = rules
            .extract(r#"deepseek api_key = "sk-123456789012345678901234567890" openai compatible"#);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].vendor, "DeepSeek");
    }

    #[test]
    fn extracts_credentials_from_common_encodings() {
        let rules = CompiledRuleSet::compile(default_rules()).unwrap();
        let plain = r#"deepseek api_key = "sk-123456789012345678901234567890""#;
        assert_eq!(
            rules.extract(&general_purpose::STANDARD.encode(plain))[0].vendor,
            "DeepSeek"
        );
        assert_eq!(
            rules.extract(&urlencoding::encode(plain))[0].vendor,
            "DeepSeek"
        );
        assert_eq!(
            rules.extract(&format!(
                r#"{{"payload":"{}"}}"#,
                general_purpose::URL_SAFE_NO_PAD.encode(plain)
            ))[0]
                .vendor,
            "DeepSeek"
        );
        assert_eq!(
            rules.extract(&format!(r#"{{"payload":"{}"}}"#, hex::encode(plain)))[0].vendor,
            "DeepSeek"
        );
    }

    #[test]
    fn extracts_unique_prefix_providers() {
        let rules = CompiledRuleSet::compile(default_rules()).unwrap();
        let cases: &[(&str, &str, &str)] = &[
            (r#"openai api_key = "sk-proj-abcdefghij1234567890ABCDEFGHIJ""#, "OpenAI", "openai_official"),
            (r#"nvidia api_key = "nvapi-abcdefghij1234567890A""#, "NVIDIA", "nvidia"),
            (r#"groq api_key = "gsk_abcdefghij1234567890A""#, "Groq", "groq"),
            (r#"openrouter api_key = "sk-or-abcdefghij1234567890""#, "OpenRouter", "openrouter"),
            (r#"replicate api_key = "r8_abcdefghij1234567890A""#, "Replicate", "replicate"),
            (r#"qoder api_key = "pt-abcdefghij1234567890A""#, "Qoder", "qoder"),
            (r#"kiro api_key = "ksk_abcdefghij1234567890A""#, "Kiro", "kiro"),
            (r#"bedrock aws_key = "ABSKabcdefghij12345678""#, "AWS Bedrock", "aws_bedrock"),
            (r#"cursor token = "crsr_abcdefghij1234567890A""#, "Cursor", "cursor"),
        ];
        for (input, expected_vendor, label) in cases {
            let findings = rules.extract(input);
            assert!(
                !findings.is_empty(),
                "{label}: 未提取到凭证"
            );
            assert_eq!(
                findings[0].vendor, *expected_vendor,
                "{label}: vendor 不匹配"
            );
        }
    }

    #[test]
    fn openai_official_precedes_generic() {
        let rules = CompiledRuleSet::compile(default_rules()).unwrap();
        let findings = rules
            .extract(r#"openai api_key = "sk-proj-abcdefghij1234567890ABCDEFGHIJ""#);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].vendor, "OpenAI");
    }
}
