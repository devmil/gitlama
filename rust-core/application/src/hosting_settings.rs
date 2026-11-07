//! The stored hosting section of the settings document: connections, repository bindings
//! and the expanded tree nodes. Hosting owns its rules; the identity rules are the shared
//! hosting model's (`domain::hosting`).
pub use gitlama_contract::hosting_settings::*;
use std::collections::HashSet;

/// Stored preset names, as written by the Dart settings repository.
pub(crate) const HOSTING_PRESETS: [&str; 6] = [
    "github",
    "gitlab",
    "gitlabSelfManaged",
    "forgejo",
    "codeberg",
    "gitHubEnterprise",
];

/// Stored authentication names, as written by the Dart settings repository.
pub(crate) const HOSTING_AUTHENTICATIONS: [&str; 3] = ["oauth", "gitHubCli", "gitLabCli"];

/// Checks the stored hosting connections, bindings and expanded nodes.
pub(crate) fn validate_settings(
    connections: &[NativeHostingConnectionSettings],
    bindings: &[NativeHostingBindingSettings],
    expanded_nodes: &[String],
) -> Result<(), &'static str> {
    let connection_ids: HashSet<_> = connections
        .iter()
        .map(|connection| connection.id.as_str())
        .collect();
    let credential_ids: HashSet<_> = connections
        .iter()
        .map(|connection| connection.credential_identity.as_str())
        .collect();
    if connection_ids.len() != connections.len()
        || credential_ids.len() != connections.len()
        || connections.iter().any(|connection| {
            !crate::domain::hosting::valid_connection_identity(&connection.id)
                || !crate::domain::hosting::valid_connection_identity(
                    &connection.credential_identity,
                )
                || !HOSTING_PRESETS.contains(&connection.preset.as_str())
                || connection.login.len() > 512
                || connection.web_base_url.len() > 2048
                || connection.api_base_url.len() > 2048
                || connection.oauth_client_id.len() > 512
                || !HOSTING_AUTHENTICATIONS.contains(&connection.authentication.as_str())
                || connection.capabilities.len() > 32
                || connection.capabilities.iter().any(|value| {
                    value.len() > 64 || !value.bytes().all(|byte| byte.is_ascii_alphanumeric())
                })
        })
    {
        return Err("hosting_connections");
    }
    let binding_keys: HashSet<_> = bindings
        .iter()
        .map(|binding| (&binding.repository, binding.remote.as_slice()))
        .collect();
    if binding_keys.len() != bindings.len()
        || bindings.iter().any(|binding| {
            binding.remote.is_empty()
                || binding.remote.len() > 1024
                || binding.remote.contains(&0)
                || !connection_ids.contains(binding.connection_id.as_str())
                || !crate::domain::hosting::valid_provider_repository(&binding.provider_repository)
        })
    {
        return Err("hosting_bindings");
    }
    let unique_nodes: HashSet<_> = expanded_nodes.iter().collect();
    if unique_nodes.len() != expanded_nodes.len()
        || expanded_nodes
            .iter()
            .any(|node| node.is_empty() || node.len() > 512 || node.chars().any(char::is_control))
    {
        return Err("hosting_expanded_nodes");
    }
    Ok(())
}
