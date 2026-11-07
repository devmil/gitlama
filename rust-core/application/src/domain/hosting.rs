//! Hosting identity rules, from the shared hosting model, for every place that stores or
//! checks a connection or a provider repository.
use devmil_git::hosting::rest::safe_path_segment;
use devmil_git::hosting::{HostingConnectionId, HostingRepositoryId};

/// A connection or credential identity the hosting model accepts.
#[must_use]
pub fn valid_connection_identity(value: &str) -> bool {
    HostingConnectionId::new(value.to_owned()).is_ok()
}

/// A provider repository path such as `owner/name` or `group/subgroup/name`: an identity
/// the hosting model accepts, made of at least two safe path segments.
#[must_use]
pub fn valid_provider_repository(value: &str) -> bool {
    HostingRepositoryId::new(value.to_owned()).is_ok()
        && value.split('/').count() >= 2
        && value.split('/').all(safe_path_segment)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hosting_identities_follow_the_shared_model() {
        assert!(valid_connection_identity("forgejo:team one"));
        assert!(!valid_connection_identity(" padded"));
        assert!(!valid_connection_identity(&"x".repeat(513)));
        assert!(valid_provider_repository("group/sub.group/name-1"));
        assert!(!valid_provider_repository("name"));
        assert!(!valid_provider_repository("owner/../name"));
        assert!(!valid_provider_repository("owner/na:me"));
        assert!(!valid_provider_repository("owner//name"));
    }
}
