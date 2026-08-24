use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

#[derive(Clone, Debug)]
pub struct FingerprintEvidence<'a> {
    pub headers: &'a BTreeMap<String, String>,
    pub body: &'a str,
}

pub fn identify_product(evidence: FingerprintEvidence<'_>) -> (String, Vec<String>, String) {
    let (body, headers) = normalized_evidence(&evidence);
    let server = evidence.headers.get("server").cloned().unwrap_or_default();
    let signatures: &[(&str, &[&str])] = &[
        ("Azure OpenAI", &["azure", "apim-request-id", "api-version"]),
        (
            "Anthropic",
            &["anthropic-version", "/v1/messages", "claude"],
        ),
        (
            "Gemini",
            &["generativelanguage", "generatecontent", "gemini"],
        ),
        ("DeepSeek", &["deepseek"]),
        ("Qwen", &["dashscope", "qwen", "compatible-mode"]),
        ("豆包", &["volcengine", "ark.cn", "doubao"]),
        ("可灵", &["klingai", "kling"]),
        ("GLM", &["bigmodel", "zhipu", "/api/paas/v4", "glm-"]),
        ("Mimo", &["xiaomi", "mimo"]),
        ("MiniMax", &["minimax"]),
        ("Kimi", &["moonshot", "kimi"]),
        ("LongCat", &["longcat"]),
        ("Grok", &["api.x.ai", "x.ai", "grok"]),
        ("Mistral", &["mistral"]),
        ("OpenRouter", &["openrouter", "openrouter.ai"]),
        ("Cohere", &["cohere.ai", "cohere.com"]),
        (
            "Together",
            &["together.ai", "together.xyz", "togethercomputer"],
        ),
        ("Replicate", &["replicate.com", "api.replicate"]),
        ("Fireworks", &["fireworks.ai"]),
        ("Groq", &["groq.com", "api.groq"]),
        ("SiliconFlow", &["siliconflow"]),
        ("NVIDIA", &["integrate.api.nvidia.com", "nvcf.nvidia"]),
        ("Windsurf", &["windsurf", "codeium"]),
        ("AWS Bedrock", &["bedrock-runtime", "bedrock.amazonaws"]),
        ("Ksyun", &["kspmas.ksyun", "ksyun"]),
        ("Qoder", &["qoder.com", "qoder"]),
        ("Kiro", &["kiro.dev", "kiro"]),
        ("Cursor", &["cursor.com", "cursor"]),
        ("OpenAI", &["openai.com", "oaiusercontent"]),
        ("Ollama", &["ollama", "/api/tags", "library/"]),
        ("vLLM", &["vllm", "served-model-name"]),
        (
            "OpenAI Compatible",
            &["/v1/models", "chat/completions", "openai"],
        ),
    ];
    let mut evidence_items = Vec::new();
    let mut product = "未知 AI 服务";
    let mut best_score = 0;
    for (name, needles) in signatures {
        if *name == "OpenAI Compatible" && best_score > 0 {
            continue;
        }
        let score = needles
            .iter()
            .filter(|needle| body.contains(**needle) || headers.contains(**needle))
            .count();
        if score > best_score {
            best_score = score;
            product = name;
        }
    }
    if best_score > 0 {
        evidence_items.push(format!("命中产品指纹：{product}"));
    }
    if !server.is_empty() {
        evidence_items.push(format!("Server: {server}"));
    }
    let mut hasher = Sha256::new();
    hasher.update(server.as_bytes());
    hasher.update(b"\0");
    hasher.update(evidence.body.as_bytes());
    let response_fingerprint = format!("{:x}", hasher.finalize());
    (product.to_owned(), evidence_items, response_fingerprint)
}

pub fn honeypot_evidence(evidence: FingerprintEvidence<'_>) -> Vec<String> {
    let (body, headers) = normalized_evidence(&evidence);
    [
        "canarytokens.com",
        "interact.sh",
        "burpcollaborator",
        "x-honeypot:",
        "\"honeypot\":true",
    ]
    .into_iter()
    .filter(|marker| body.contains(marker) || headers.contains(marker))
    .map(|marker| format!("命中蜜罐信号：{marker}"))
    .collect()
}

fn normalized_evidence(evidence: &FingerprintEvidence<'_>) -> (String, String) {
    let headers = evidence
        .headers
        .iter()
        .map(|(name, value)| format!("{name}:{value}"))
        .collect::<Vec<_>>()
        .join("\n")
        .to_ascii_lowercase();
    (evidence.body.to_ascii_lowercase(), headers)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefers_specific_openai_compatible_vendor() {
        let headers = BTreeMap::new();
        let (product, _, _) = identify_product(FingerprintEvidence {
            headers: &headers,
            body: "DeepSeek OpenAI compatible /v1/models",
        });
        assert_eq!(product, "DeepSeek");
    }

    #[test]
    fn identifies_extended_provider_fingerprints() {
        let headers = BTreeMap::new();
        let (product, _, _) = identify_product(FingerprintEvidence {
            headers: &headers,
            body: "https://openrouter.ai/api/v1/models",
        });
        assert_eq!(product, "OpenRouter");
    }

    #[test]
    fn detects_explicit_honeypot_marker() {
        let headers = BTreeMap::from([("x-honeypot".to_owned(), "true".to_owned())]);
        assert!(
            !honeypot_evidence(FingerprintEvidence {
                headers: &headers,
                body: "",
            })
            .is_empty()
        );
    }
}
