use ipnet::IpNet;
use std::net::IpAddr;
use thiserror::Error;

#[derive(Clone, Debug)]
pub struct AuthorizedScope {
    domains: Vec<String>,
    addresses: Vec<IpAddr>,
    networks: Vec<IpNet>,
}

#[derive(Debug, Error)]
pub enum ScopeError {
    #[error("必须确认已获得目标授权。")]
    AuthorizationNotConfirmed,
    #[error("授权目标范围不能为空。")]
    Empty,
    #[error("无法识别授权范围：{0}")]
    Invalid(String),
}

impl AuthorizedScope {
    pub fn parse(entries: &[String], confirmed: bool) -> Result<Self, ScopeError> {
        if !confirmed {
            return Err(ScopeError::AuthorizationNotConfirmed);
        }
        if entries.is_empty() {
            return Err(ScopeError::Empty);
        }
        let mut scope = Self {
            domains: Vec::new(),
            addresses: Vec::new(),
            networks: Vec::new(),
        };
        for raw in entries {
            let value = raw.trim().trim_end_matches('.').to_ascii_lowercase();
            if value.is_empty() {
                continue;
            }
            if let Ok(network) = value.parse::<IpNet>() {
                scope.networks.push(network);
            } else if let Ok(address) = value.parse::<IpAddr>() {
                scope.addresses.push(address);
            } else if is_valid_domain(&value) {
                scope.domains.push(value);
            } else {
                return Err(ScopeError::Invalid(raw.clone()));
            }
        }
        if scope.domains.is_empty() && scope.addresses.is_empty() && scope.networks.is_empty() {
            return Err(ScopeError::Empty);
        }
        Ok(scope)
    }

    pub fn contains_host(&self, host: &str) -> bool {
        let normalized = host.trim().trim_end_matches('.').to_ascii_lowercase();
        if let Ok(address) = normalized.parse::<IpAddr>() {
            return self.addresses.contains(&address)
                || self
                    .networks
                    .iter()
                    .any(|network| network.contains(&address));
        }
        self.domains
            .iter()
            .any(|domain| normalized == *domain || normalized.ends_with(&format!(".{domain}")))
    }
}

fn is_valid_domain(value: &str) -> bool {
    value.len() <= 253
        && value.contains('.')
        && value.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .chars()
                    .all(|ch| ch.is_ascii_alphanumeric() || ch == '-')
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn permits_declared_domain_and_subdomain() {
        let scope = AuthorizedScope::parse(&["example.com".to_owned()], true).unwrap();
        assert!(scope.contains_host("api.example.com"));
        assert!(!scope.contains_host("example.com.evil.test"));
    }

    #[test]
    fn requires_explicit_confirmation() {
        assert!(matches!(
            AuthorizedScope::parse(&["example.com".to_owned()], false),
            Err(ScopeError::AuthorizationNotConfirmed)
        ));
    }
}
