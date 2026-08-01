use crate::{Candidate, NormalizedTarget};
use thiserror::Error;
use url::Url;

#[derive(Debug, Error)]
pub enum NormalizeUrlError {
    #[error("目标 URL 无效。")]
    Invalid,
    #[error("仅支持 HTTP 或 HTTPS 目标。")]
    UnsupportedScheme,
    #[error("目标 URL 缺少主机名。")]
    MissingHost,
    #[error("目标 URL 不能包含账号或密码。")]
    EmbeddedCredentials,
}

pub fn normalize_target_url(candidate: &Candidate) -> Result<NormalizedTarget, NormalizeUrlError> {
    let raw = candidate.target.trim();
    let with_scheme = if raw.contains("://") {
        raw.to_owned()
    } else {
        format!("https://{raw}")
    };
    let mut url = Url::parse(&with_scheme).map_err(|_| NormalizeUrlError::Invalid)?;
    if url.scheme() != "http" && url.scheme() != "https" {
        return Err(NormalizeUrlError::UnsupportedScheme);
    }
    let host = url
        .host_str()
        .ok_or(NormalizeUrlError::MissingHost)?
        .to_ascii_lowercase();
    if !url.username().is_empty() || url.password().is_some() {
        return Err(NormalizeUrlError::EmbeddedCredentials);
    }
    url.set_query(None);
    url.set_fragment(None);
    if url.path().is_empty() {
        url.set_path("/");
    }
    let canonical_url = url.to_string();
    Ok(NormalizedTarget {
        source: candidate.source,
        url,
        canonical_url,
        host,
        metadata: candidate.metadata.clone(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use std::collections::BTreeMap;

    #[test]
    fn adds_https_and_removes_fragment() {
        let target = normalize_target_url(&Candidate {
            source: crate::SourceKind::Manual,
            target: "api.example.com/v1#token".to_owned(),
            discovered_at: Utc::now(),
            metadata: BTreeMap::new(),
        })
        .unwrap();
        assert_eq!(target.canonical_url, "https://api.example.com/v1");
    }

    #[test]
    fn removes_query_and_rejects_embedded_credentials() {
        let target = normalize_target_url(&Candidate {
            source: crate::SourceKind::Manual,
            target: "https://api.example.com/v1?key=secret".to_owned(),
            discovered_at: Utc::now(),
            metadata: BTreeMap::new(),
        })
        .unwrap();
        assert_eq!(target.canonical_url, "https://api.example.com/v1");
        assert!(matches!(
            normalize_target_url(&Candidate {
                source: crate::SourceKind::Manual,
                target: "https://user:secret@api.example.com".to_owned(),
                discovered_at: Utc::now(),
                metadata: BTreeMap::new(),
            }),
            Err(NormalizeUrlError::EmbeddedCredentials)
        ));
    }
}
