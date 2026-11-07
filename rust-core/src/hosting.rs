//! Application-owned hosting contracts, binding policy, and native credentials.
pub use gitlama_contract::hosting::*;

use devmil_git::activity::ActivityStatus;
use devmil_git::cancellation::Cancellation;
use devmil_git::hosting::binding::{
    connection_server_with_port as connection_server, normalize_authority, AuthorityScheme,
};
use devmil_git::hosting::cli::{
    github_cli_probe_command, github_cli_token_command, gitlab_cli_probe_command,
    gitlab_cli_token_command, parse_github_cli_token, parse_gitlab_cli_token,
};
use devmil_git::hosting::http::valid_api_base;
use devmil_git::hosting::model::{
    validate_connection, HostingCapability, HostingCapabilitySet, HostingConnection,
    HostingConnectionId, HostingError, HostingPreset, HostingRepositoryId,
};
use devmil_git::hosting::rest::safe_path_segment;
use devmil_git::process::ActivityGitRunner;
use devmil_git::refs::RemoteId;
use gitlama_application::activity::allocate_activity_id;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeSet, HashMap};
use std::fmt;
use std::sync::{Arc, Mutex, OnceLock, TryLockError, Weak};
use std::time::Duration;
use zeroize::Zeroize;

const CREDENTIAL_SERVICE: &str = "de.devmil.gitlama.hosting";
const MAX_CONNECTIONS: usize = 32;
const MAX_REMOTES: usize = 128;

#[must_use]
pub const fn empty_resources() -> NativeHostingResources {
    NativeHostingResources {
        change_requests: Vec::new(),
        issues: Vec::new(),
        remote_references: Vec::new(),
    }
}

#[must_use]
pub fn github_cli_available() -> bool {
    let mut discard = |_event| {};
    let result = ActivityGitRunner::run_private(
        github_cli_probe_command(),
        allocate_activity_id(),
        None,
        &mut discard,
    );
    matches!(result.activity.status, ActivityStatus::Succeeded { .. })
}

#[must_use]
pub fn gitlab_cli_available() -> bool {
    let mut discard = |_event| {};
    let result = ActivityGitRunner::run_private(
        gitlab_cli_probe_command(),
        allocate_activity_id(),
        None,
        &mut discard,
    );
    matches!(result.activity.status, ActivityStatus::Succeeded { .. })
}

#[must_use]
pub fn validate_native_connection(
    connection: NativeHostingConnection,
) -> NativeHostingConnectionResult {
    match normalized_connection(connection) {
        Ok(connection) => NativeHostingConnectionResult {
            connection: Some(connection),
            failure: None,
        },
        Err(failure) => NativeHostingConnectionResult {
            connection: None,
            failure: Some(failure),
        },
    }
}

/// The web origin, API base, capabilities and authentication methods a new connection of
/// `preset` starts with. Public presets ignore `web_base`; self-hosted presets need an `https`
/// origin without a path.
#[must_use]
pub fn preset_defaults(
    preset: NativeHostingPreset,
    web_base: Option<String>,
) -> NativeHostingPresetDefaultsResult {
    use devmil_git::hosting::binding::{hosting_preset_defaults, HostingAuthenticationMethod};
    match hosting_preset_defaults(shared_preset(preset), web_base.as_deref()) {
        Ok(defaults) => NativeHostingPresetDefaultsResult {
            defaults: Some(NativeHostingPresetDefaults {
                preset,
                web_base_url: defaults.web_base_url,
                api_base_url: defaults.api_base_url,
                github_tenant: defaults.github_tenant,
                capabilities: defaults
                    .capabilities
                    .supported
                    .iter()
                    .copied()
                    .map(native_capability)
                    .collect(),
                authentications: defaults
                    .authentications
                    .into_iter()
                    .map(|method| match method {
                        HostingAuthenticationMethod::OAuth => NativeHostingAuthentication::OAuth,
                        HostingAuthenticationMethod::GitHubCli => {
                            NativeHostingAuthentication::GitHubCli
                        }
                        HostingAuthenticationMethod::GitLabCli => {
                            NativeHostingAuthentication::GitLabCli
                        }
                    })
                    .collect(),
            }),
            failure: None,
        },
        Err(_) => NativeHostingPresetDefaultsResult {
            defaults: None,
            failure: Some(NativeHostingFailureKind::InvalidConnection),
        },
    }
}

const fn shared_preset(preset: NativeHostingPreset) -> HostingPreset {
    match preset {
        NativeHostingPreset::GitHub => HostingPreset::GitHub,
        NativeHostingPreset::GitLab => HostingPreset::GitLab,
        NativeHostingPreset::GitLabSelfManaged => HostingPreset::GitLabSelfManaged,
        NativeHostingPreset::Forgejo => HostingPreset::Forgejo,
        NativeHostingPreset::Codeberg => HostingPreset::Codeberg,
        NativeHostingPreset::GitHubEnterprise => HostingPreset::GitHubEnterprise,
    }
}

const fn native_capability(capability: HostingCapability) -> NativeHostingCapability {
    match capability {
        HostingCapability::ChangeRequests => NativeHostingCapability::ChangeRequests,
        HostingCapability::ChangeRequestCheckout => NativeHostingCapability::ChangeRequestCheckout,
        HostingCapability::ChangeRequestReview => NativeHostingCapability::ChangeRequestReview,
        HostingCapability::CommitStatuses => NativeHostingCapability::CommitStatuses,
        HostingCapability::CheckRuns => NativeHostingCapability::CheckRuns,
        HostingCapability::Issues => NativeHostingCapability::Issues,
        HostingCapability::RemoteReferences => NativeHostingCapability::RemoteReferences,
    }
}

#[must_use]
pub fn resolve_binding(
    connections: Vec<NativeHostingConnection>,
    remotes: Vec<NativeHostingRemote>,
    override_connection_id: Option<String>,
) -> NativeHostingBindingResult {
    if connections.len() > MAX_CONNECTIONS || remotes.len() > MAX_REMOTES {
        return unmatched(Some(NativeHostingFailureKind::InvalidRemote));
    }
    let connections = match connections
        .into_iter()
        .map(normalized_connection)
        .collect::<Result<Vec<_>, _>>()
    {
        Ok(connections) => connections,
        Err(failure) => return unmatched(Some(failure)),
    };
    use devmil_git::hosting::binding::{resolve_connection_binding, ConnectionBindingResolution};
    let shared = connections.iter().map(to_shared).collect::<Vec<_>>();
    let remotes = remotes
        .into_iter()
        .filter(|remote| remote.name.len() <= 1024)
        .filter_map(|remote| Some((RemoteId::from_bytes(remote.name)?, remote.url)))
        .collect::<Vec<_>>();
    let preferred = match override_connection_id.map(HostingConnectionId::new) {
        None => None,
        Some(Ok(id)) => Some(id),
        // No connection can carry an invalid identity, so nothing binds.
        Some(Err(_)) => return unmatched(None),
    };
    match resolve_connection_binding(
        &shared,
        remotes.iter().map(|(name, url)| (name, url.as_str())),
        preferred.as_ref(),
    ) {
        ConnectionBindingResolution::Unmatched => unmatched(None),
        ConnectionBindingResolution::Ambiguous { remote, server } => NativeHostingBindingResult {
            state: NativeHostingBindingState::Ambiguous,
            remote: remote.as_bytes().to_vec(),
            server,
            connection_id: None,
            provider_repository: None,
            web_url: None,
            failure: Some(NativeHostingFailureKind::Ambiguous),
        },
        ConnectionBindingResolution::Bound(binding) => NativeHostingBindingResult {
            state: NativeHostingBindingState::Bound,
            remote: binding.remote.as_bytes().to_vec(),
            server: binding.server,
            connection_id: Some(binding.connection.as_str().to_owned()),
            provider_repository: Some(binding.provider_repository.as_str().to_owned()),
            web_url: Some(binding.web_url),
            failure: None,
        },
    }
}

fn unmatched(failure: Option<NativeHostingFailureKind>) -> NativeHostingBindingResult {
    NativeHostingBindingResult {
        state: NativeHostingBindingState::Unmatched,
        remote: Vec::new(),
        server: String::new(),
        connection_id: None,
        provider_repository: None,
        web_url: None,
        failure,
    }
}

#[must_use]
pub fn canonical_resource_link(
    connection: NativeHostingConnection,
    provider_repository: String,
    kind: NativeHostingResourceKind,
    number: Option<u64>,
) -> NativeHostingLinkResult {
    let connection = match normalized_connection(connection) {
        Ok(connection) => connection,
        Err(failure) => {
            return NativeHostingLinkResult {
                url: None,
                failure: Some(failure),
            };
        }
    };
    use devmil_git::hosting::rest::{web_link, HostingWebResource};
    let resource = match (kind, number) {
        (NativeHostingResourceKind::Repository, None) => HostingWebResource::Repository,
        (NativeHostingResourceKind::ChangeRequest, Some(number)) => {
            HostingWebResource::ChangeRequest(number)
        }
        (NativeHostingResourceKind::CreateChangeRequest, None) => {
            HostingWebResource::CreateChangeRequest
        }
        (NativeHostingResourceKind::Issue, Some(number)) => HostingWebResource::Issue(number),
        _ => return link_failure(),
    };
    let Ok(repository) = HostingRepositoryId::new(provider_repository) else {
        return link_failure();
    };
    match web_link(&to_shared(&connection), &repository, resource) {
        Ok(url) => NativeHostingLinkResult {
            url: Some(url),
            failure: None,
        },
        Err(_) => link_failure(),
    }
}

#[must_use]
pub fn credential_state(connection: NativeHostingConnection) -> NativeHostingCredentialResult {
    let connection = match normalized_connection(connection) {
        Ok(connection) => connection,
        Err(failure) => {
            return NativeHostingCredentialResult {
                state: NativeHostingCredentialState::Unreadable,
                failure: Some(failure),
            };
        }
    };
    if connection.authentication != NativeHostingAuthentication::OAuth {
        return match load_cli_credential(&connection) {
            Ok(_) => NativeHostingCredentialResult {
                state: NativeHostingCredentialState::Available,
                failure: None,
            },
            Err(failure) => NativeHostingCredentialResult {
                state: NativeHostingCredentialState::Missing,
                failure: Some(failure),
            },
        };
    }
    credential_state_with(
        &KeyringCredentialBackend,
        &connection,
        gitlama_application::clock::unix_seconds(),
    )
}

#[must_use]
pub fn remove_credential(connection: NativeHostingConnection) -> NativeHostingCredentialResult {
    let connection = match normalized_connection(connection) {
        Ok(connection) => connection,
        Err(failure) => {
            return NativeHostingCredentialResult {
                state: NativeHostingCredentialState::Unreadable,
                failure: Some(failure),
            };
        }
    };
    if connection.authentication != NativeHostingAuthentication::OAuth {
        return NativeHostingCredentialResult {
            state: NativeHostingCredentialState::Missing,
            failure: None,
        };
    }
    let backend = KeyringCredentialBackend;
    remove_credential_with(
        &backend,
        &connection,
        gitlama_application::clock::unix_seconds(),
    )
}

fn remove_credential_with(
    backend: &impl CredentialBackend,
    connection: &NativeHostingConnection,
    now: u64,
) -> NativeHostingCredentialResult {
    let lock = credential_lock(connection);
    let _guard = lock.lock().expect("hosting credential lock");
    let state = credential_state_with(backend, connection, now);
    match state.state {
        NativeHostingCredentialState::Missing => NativeHostingCredentialResult {
            state: NativeHostingCredentialState::Missing,
            failure: None,
        },
        NativeHostingCredentialState::Unreadable => state,
        NativeHostingCredentialState::Available | NativeHostingCredentialState::Expired => {
            match backend.delete(&credential_key(connection)) {
                Ok(()) => NativeHostingCredentialResult {
                    state: NativeHostingCredentialState::Missing,
                    failure: None,
                },
                Err(_) => NativeHostingCredentialResult {
                    state: NativeHostingCredentialState::Unreadable,
                    failure: Some(NativeHostingFailureKind::CredentialStore),
                },
            }
        }
    }
}

#[derive(Serialize, Deserialize)]
pub struct CredentialEnvelope {
    access_token: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    refresh_token: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    expires_at: Option<u64>,
}

impl CredentialEnvelope {
    pub fn new(
        access_token: String,
        refresh_token: Option<String>,
        expires_at: Option<u64>,
    ) -> Result<Self, NativeHostingFailureKind> {
        if access_token.is_empty()
            || access_token.len() > 16 * 1024
            || refresh_token
                .as_ref()
                .is_some_and(|value| value.len() > 16 * 1024)
        {
            return Err(NativeHostingFailureKind::CredentialStore);
        }
        Ok(Self {
            access_token,
            refresh_token,
            expires_at,
        })
    }

    pub(crate) fn refresh_token(&self) -> Option<&str> {
        self.refresh_token
            .as_deref()
            .filter(|token| !token.is_empty())
    }

    pub fn access_token(&self) -> &[u8] {
        self.access_token.as_bytes()
    }
}

impl Drop for CredentialEnvelope {
    fn drop(&mut self) {
        self.access_token.zeroize();
        if let Some(refresh_token) = &mut self.refresh_token {
            refresh_token.zeroize();
        }
    }
}

impl fmt::Debug for CredentialEnvelope {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("CredentialEnvelope([REDACTED])")
    }
}

pub fn store_credential(
    connection: &NativeHostingConnection,
    envelope: &CredentialEnvelope,
) -> Result<(), NativeHostingFailureKind> {
    let connection = normalized_connection(connection.clone())?;
    store_credential_locked_with(&KeyringCredentialBackend, &connection, envelope)
}

fn store_credential_locked_with(
    backend: &impl CredentialBackend,
    connection: &NativeHostingConnection,
    envelope: &CredentialEnvelope,
) -> Result<(), NativeHostingFailureKind> {
    let lock = credential_lock(connection);
    let _guard = lock.lock().expect("hosting credential lock");
    store_credential_with(backend, connection, envelope)
}

fn store_credential_with(
    backend: &impl CredentialBackend,
    connection: &NativeHostingConnection,
    envelope: &CredentialEnvelope,
) -> Result<(), NativeHostingFailureKind> {
    let mut encoded =
        serde_json::to_vec(envelope).map_err(|_| NativeHostingFailureKind::CredentialStore)?;
    let result = backend
        .put(&credential_key(connection), &encoded)
        .map_err(|_| NativeHostingFailureKind::CredentialStore);
    encoded.zeroize();
    result
}

#[derive(Debug)]
pub(crate) enum CredentialLoadError {
    Store(NativeHostingFailureKind),
    Refresh(HostingError),
}

/// What a failed credential load means for a request, shared by every hosting feature.
pub(crate) enum CredentialFailure {
    Missing,
    Expired,
    Unreadable,
    Invalid,
    /// Refreshing an expired OAuth token failed with this provider error.
    Refresh(HostingError),
}

impl CredentialLoadError {
    pub(crate) fn classify(self) -> CredentialFailure {
        match self {
            Self::Refresh(error) => CredentialFailure::Refresh(error),
            Self::Store(NativeHostingFailureKind::CredentialMissing) => CredentialFailure::Missing,
            Self::Store(NativeHostingFailureKind::CredentialExpired) => CredentialFailure::Expired,
            Self::Store(
                NativeHostingFailureKind::CredentialUnreadable
                | NativeHostingFailureKind::CredentialStore,
            ) => CredentialFailure::Unreadable,
            Self::Store(_) => CredentialFailure::Invalid,
        }
    }
}

impl From<NativeHostingFailureKind> for CredentialLoadError {
    fn from(value: NativeHostingFailureKind) -> Self {
        Self::Store(value)
    }
}

// Weak entries keep account churn bounded without retaining tokens. All writes,
// deletion and refresh use the same credential key, including aliased connections.
fn credential_lock(connection: &NativeHostingConnection) -> Arc<Mutex<()>> {
    static LOCKS: OnceLock<Mutex<HashMap<String, Weak<Mutex<()>>>>> = OnceLock::new();
    let mut locks = LOCKS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .expect("hosting credential locks");
    locks.retain(|_, lock| lock.strong_count() != 0);
    let key = credential_key(connection);
    if let Some(lock) = locks.get(&key).and_then(Weak::upgrade) {
        return lock;
    }
    let lock = Arc::new(Mutex::new(()));
    locks.insert(key, Arc::downgrade(&lock));
    lock
}

/// Loads the credential of `connection`. An OAuth credential that is about to expire is renewed
/// through `refresh`, which the hosting runtime supplies; hosting performs no network calls.
pub(crate) fn load_credential(
    connection: &NativeHostingConnection,
    cancellation: &dyn Cancellation,
    refresh: impl FnOnce(
        &NativeHostingConnection,
        &CredentialEnvelope,
    ) -> Result<CredentialEnvelope, HostingError>,
) -> Result<CredentialEnvelope, CredentialLoadError> {
    let connection = normalized_connection(connection.clone())?;
    if cancellation.is_cancelled() {
        return Err(CredentialLoadError::Refresh(HostingError::Canceled));
    }
    if connection.authentication != NativeHostingAuthentication::OAuth {
        return load_cli_credential(&connection).map_err(Into::into);
    }
    load_credential_with(
        &KeyringCredentialBackend,
        &connection,
        cancellation,
        gitlama_application::clock::unix_seconds,
        |envelope| refresh(&connection, envelope),
    )
}

fn load_credential_with(
    backend: &impl CredentialBackend,
    connection: &NativeHostingConnection,
    cancellation: &dyn Cancellation,
    now: impl Fn() -> u64,
    refresh: impl FnOnce(&CredentialEnvelope) -> Result<CredentialEnvelope, HostingError>,
) -> Result<CredentialEnvelope, CredentialLoadError> {
    let lock = credential_lock(connection);
    let _guard = loop {
        if cancellation.is_cancelled() {
            return Err(CredentialLoadError::Refresh(HostingError::Canceled));
        }
        match lock.try_lock() {
            Ok(guard) => break guard,
            Err(TryLockError::WouldBlock) => std::thread::sleep(Duration::from_millis(10)),
            Err(TryLockError::Poisoned(_)) => {
                return Err(NativeHostingFailureKind::CredentialUnreadable.into())
            }
        }
    };
    // Read only after acquiring the lock. Another request may have rotated both tokens.
    let mut encoded = backend
        .get(&credential_key(connection))
        .map_err(|_| NativeHostingFailureKind::CredentialUnreadable)?
        .ok_or(NativeHostingFailureKind::CredentialMissing)?;
    let envelope = serde_json::from_slice::<CredentialEnvelope>(&encoded)
        .map_err(|_| NativeHostingFailureKind::CredentialUnreadable);
    encoded.zeroize();
    let envelope = envelope?;
    let now = now();
    let renewable = envelope
        .refresh_token
        .as_ref()
        .is_some_and(|token| !token.is_empty());
    if envelope
        .expires_at
        .is_some_and(|expiry| expiry <= now.saturating_add(60))
        && renewable
    {
        let renewed = refresh(&envelope).map_err(CredentialLoadError::Refresh)?;
        // Persist a successful rotation even if cancellation arrives with the response.
        // The previous refresh token may already be invalidated at the provider.
        store_credential_with(backend, connection, &renewed)?;
        Ok(renewed)
    } else if envelope.expires_at.is_some_and(|expiry| expiry <= now) {
        Err(NativeHostingFailureKind::CredentialExpired.into())
    } else {
        Ok(envelope)
    }
}

fn load_cli_credential(
    connection: &NativeHostingConnection,
) -> Result<CredentialEnvelope, NativeHostingFailureKind> {
    let host = connection_server(&connection.web_base_url)
        .ok_or(NativeHostingFailureKind::InvalidConnection)?;
    let command = match connection.authentication {
        NativeHostingAuthentication::GitHubCli => github_cli_token_command(&host),
        NativeHostingAuthentication::GitLabCli => gitlab_cli_token_command(&host),
        NativeHostingAuthentication::OAuth => {
            return Err(NativeHostingFailureKind::InvalidConnection)
        }
    }
    .map_err(|_| NativeHostingFailureKind::InvalidConnection)?;
    let mut discard = |_event| {};
    let mut result =
        ActivityGitRunner::run_private(command, allocate_activity_id(), None, &mut discard);
    if !matches!(result.activity.status, ActivityStatus::Succeeded { .. }) {
        return Err(NativeHostingFailureKind::CredentialMissing);
    }
    let token = match connection.authentication {
        NativeHostingAuthentication::GitHubCli => {
            parse_github_cli_token(result.stdout.take_bytes())
        }
        NativeHostingAuthentication::GitLabCli => {
            parse_gitlab_cli_token(result.stdout.take_bytes())
        }
        NativeHostingAuthentication::OAuth => {
            return Err(NativeHostingFailureKind::InvalidConnection)
        }
    }
    .map_err(|_| NativeHostingFailureKind::CredentialUnreadable)?;
    CredentialEnvelope::new(token, None, None)
}

trait CredentialBackend {
    fn put(&self, key: &str, secret: &[u8]) -> Result<(), ()>;
    fn get(&self, key: &str) -> Result<Option<Vec<u8>>, ()>;
    fn delete(&self, key: &str) -> Result<(), ()>;
}

struct KeyringCredentialBackend;

impl KeyringCredentialBackend {
    fn entry(key: &str) -> Result<keyring::Entry, ()> {
        keyring::Entry::new(CREDENTIAL_SERVICE, key).map_err(|_| ())
    }
}

impl CredentialBackend for KeyringCredentialBackend {
    fn put(&self, key: &str, secret: &[u8]) -> Result<(), ()> {
        Self::entry(key)?.set_secret(secret).map_err(|_| ())
    }

    fn get(&self, key: &str) -> Result<Option<Vec<u8>>, ()> {
        match Self::entry(key)?.get_secret() {
            Ok(secret) => Ok(Some(secret)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(_) => Err(()),
        }
    }

    fn delete(&self, key: &str) -> Result<(), ()> {
        match Self::entry(key)?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(_) => Err(()),
        }
    }
}

fn credential_state_with(
    backend: &impl CredentialBackend,
    connection: &NativeHostingConnection,
    now: u64,
) -> NativeHostingCredentialResult {
    let mut encoded = match backend.get(&credential_key(connection)) {
        Ok(Some(value)) => value,
        Ok(None) => {
            return NativeHostingCredentialResult {
                state: NativeHostingCredentialState::Missing,
                failure: Some(NativeHostingFailureKind::CredentialMissing),
            };
        }
        Err(()) => {
            return NativeHostingCredentialResult {
                state: NativeHostingCredentialState::Unreadable,
                failure: Some(NativeHostingFailureKind::CredentialUnreadable),
            };
        }
    };
    let envelope = serde_json::from_slice::<CredentialEnvelope>(&encoded);
    encoded.zeroize();
    let Ok(envelope) = envelope else {
        return NativeHostingCredentialResult {
            state: NativeHostingCredentialState::Unreadable,
            failure: Some(NativeHostingFailureKind::CredentialUnreadable),
        };
    };
    if envelope
        .expires_at
        .is_some_and(|expires_at| expires_at <= now)
    {
        NativeHostingCredentialResult {
            state: NativeHostingCredentialState::Expired,
            failure: Some(NativeHostingFailureKind::CredentialExpired),
        }
    } else {
        NativeHostingCredentialResult {
            state: NativeHostingCredentialState::Available,
            failure: None,
        }
    }
}

fn normalized_connection(
    mut connection: NativeHostingConnection,
) -> Result<NativeHostingConnection, NativeHostingFailureKind> {
    connection.web_base_url = normalize_base(&connection.web_base_url, false)?;
    connection.api_base_url = normalize_base(&connection.api_base_url, true)?;
    let web_server = connection_server(&connection.web_base_url);
    let api_server = connection_server(&connection.api_base_url);
    let fixed_github_split = connection.preset == NativeHostingPreset::GitHub
        && web_server.as_deref() == Some("github.com")
        && api_server.as_deref() == Some("api.github.com");
    // GitHub Enterprise Cloud tenants serve their API from a fixed sibling host.
    let tenant_split = connection.preset == NativeHostingPreset::GitHubEnterprise
        && HostingPreset::GitHubEnterprise
            .api_base_for(&connection.web_base_url)
            .is_some_and(|expected| expected == connection.api_base_url);
    if !connection.allow_split_origin
        && !fixed_github_split
        && !tenant_split
        && web_server != api_server
    {
        return Err(NativeHostingFailureKind::InvalidConnection);
    }
    if connection.authentication == NativeHostingAuthentication::GitHubCli
        && !matches!(
            connection.preset,
            NativeHostingPreset::GitHub | NativeHostingPreset::GitHubEnterprise
        )
    {
        return Err(NativeHostingFailureKind::InvalidConnection);
    }
    if connection.authentication == NativeHostingAuthentication::GitLabCli
        && !matches!(
            connection.preset,
            NativeHostingPreset::GitLab | NativeHostingPreset::GitLabSelfManaged
        )
    {
        return Err(NativeHostingFailureKind::InvalidConnection);
    }
    if !safe_identity(&connection.id)
        || !safe_identity(&connection.credential_identity)
        || connection.capabilities.len() > 32
        || connection
            .capabilities
            .iter()
            .collect::<BTreeSet<_>>()
            .len()
            != connection.capabilities.len()
    {
        return Err(NativeHostingFailureKind::InvalidConnection);
    }
    if connection.login.len() > 512 || connection.login.chars().any(char::is_control) {
        return Err(NativeHostingFailureKind::InvalidConnection);
    }
    let mut shared = to_shared(&connection);
    if shared.login.is_empty() {
        shared.login = "_".into();
    }
    shared.enabled = true;
    validate_connection(&shared).map_err(|_| NativeHostingFailureKind::InvalidConnection)?;
    Ok(connection)
}

pub(crate) fn to_shared(connection: &NativeHostingConnection) -> HostingConnection {
    HostingConnection {
        id: HostingConnectionId::new(connection.id.clone())
            .expect("validated native identity maps to the shared identity"),
        preset: shared_preset(connection.preset),
        login: connection.login.clone(),
        web_base_url: connection.web_base_url.clone(),
        api_base_url: connection.api_base_url.clone(),
        oauth_client_id: connection.oauth_client_id.clone(),
        enabled: connection.enabled,
        capabilities: HostingCapabilitySet {
            supported: connection
                .capabilities
                .iter()
                .copied()
                .map(|capability| match capability {
                    NativeHostingCapability::ChangeRequests => HostingCapability::ChangeRequests,
                    NativeHostingCapability::ChangeRequestCheckout => {
                        HostingCapability::ChangeRequestCheckout
                    }
                    NativeHostingCapability::ChangeRequestReview => {
                        HostingCapability::ChangeRequestReview
                    }
                    NativeHostingCapability::CommitStatuses => HostingCapability::CommitStatuses,
                    NativeHostingCapability::CheckRuns => HostingCapability::CheckRuns,
                    NativeHostingCapability::Issues => HostingCapability::Issues,
                    NativeHostingCapability::RemoteReferences => {
                        HostingCapability::RemoteReferences
                    }
                })
                .collect(),
        },
    }
}

fn normalize_base(value: &str, allow_path: bool) -> Result<String, NativeHostingFailureKind> {
    let value = value.trim().trim_end_matches('/');
    if !value.starts_with("https://") || value.len() > 2048 || value.contains(['@', '?', '#']) {
        return Err(NativeHostingFailureKind::InvalidConnection);
    }
    let rest = &value[8..];
    let (authority, path) = rest.split_once('/').map_or((rest, ""), |parts| parts);
    let authority = normalize_authority(authority, AuthorityScheme::Https)
        .ok_or(NativeHostingFailureKind::InvalidConnection)?;
    if !allow_path && !path.is_empty() {
        return Err(NativeHostingFailureKind::InvalidConnection);
    }
    if allow_path
        && (!valid_api_base(value)
            || (!path.is_empty()
                && path
                    .split('/')
                    .any(|part| part.is_empty() || !safe_path_segment(part))))
    {
        return Err(NativeHostingFailureKind::InvalidConnection);
    }
    Ok(if path.is_empty() {
        format!("https://{authority}")
    } else {
        format!("https://{authority}/{path}")
    })
}

fn link_failure() -> NativeHostingLinkResult {
    NativeHostingLinkResult {
        url: None,
        failure: Some(NativeHostingFailureKind::InvalidLink),
    }
}

fn safe_identity(value: &str) -> bool {
    gitlama_application::domain::hosting::valid_connection_identity(value)
}

fn credential_key(connection: &NativeHostingConnection) -> String {
    format!(
        "{}@{}",
        connection.credential_identity,
        connection_server(&connection.web_base_url).unwrap_or_default()
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preset_defaults_follow_the_shared_rules_and_require_https() {
        let github = preset_defaults(NativeHostingPreset::GitHub, None)
            .defaults
            .unwrap();
        assert_eq!(github.web_base_url, "https://github.com");
        assert_eq!(github.api_base_url, "https://api.github.com");
        assert_eq!(
            github.authentications,
            [
                NativeHostingAuthentication::OAuth,
                NativeHostingAuthentication::GitHubCli
            ]
        );
        assert!(github
            .capabilities
            .contains(&NativeHostingCapability::CheckRuns));
        let tenant = preset_defaults(
            NativeHostingPreset::GitHubEnterprise,
            Some("octo.ghe.com".into()),
        )
        .defaults
        .unwrap();
        assert!(tenant.github_tenant);
        assert_eq!(tenant.api_base_url, "https://api.octo.ghe.com");
        let forgejo = preset_defaults(
            NativeHostingPreset::Forgejo,
            Some("https://Forge.Test:8443/".into()),
        )
        .defaults
        .unwrap();
        assert_eq!(forgejo.web_base_url, "https://forge.test:8443");
        assert_eq!(forgejo.api_base_url, "https://forge.test:8443/api/v1");
        assert_eq!(
            forgejo.authentications,
            [NativeHostingAuthentication::OAuth]
        );
        // Regression: the settings form accepted http://localhost, which a saved connection
        // can never use.
        for invalid in [None, Some("http://localhost:3000".to_owned())] {
            assert_eq!(
                preset_defaults(NativeHostingPreset::Forgejo, invalid).failure,
                Some(NativeHostingFailureKind::InvalidConnection)
            );
        }
    }
    use std::collections::BTreeMap;
    use std::sync::Mutex;

    fn connection(id: &str) -> NativeHostingConnection {
        NativeHostingConnection {
            id: id.into(),
            preset: NativeHostingPreset::GitLabSelfManaged,
            login: "fixture".into(),
            web_base_url: "https://Git.Example.test".into(),
            api_base_url: "https://git.example.test/api/v4".into(),
            oauth_client_id: "public-client".into(),
            authentication: NativeHostingAuthentication::OAuth,
            enabled: true,
            refresh_enabled: true,
            capabilities: vec![
                NativeHostingCapability::ChangeRequests,
                NativeHostingCapability::Issues,
            ],
            credential_identity: format!("credential:{id}"),
            allow_split_origin: false,
        }
    }

    #[test]
    fn normalization_binding_and_links_are_provider_safe() {
        let normalized = validate_native_connection(connection("gitlab:one"))
            .connection
            .unwrap();
        assert_eq!(normalized.web_base_url, "https://git.example.test");
        for url in [
            "ssh://git@GIT.EXAMPLE.TEST:22/group/nested/project.git",
            "https://git.example.test/group/nested/project.git",
            "git@Git.Example.Test:group/nested/project.git",
        ] {
            let remote = NativeHostingRemote {
                name: b"origin".to_vec(),
                url: url.into(),
            };
            let binding = resolve_binding(vec![normalized.clone()], vec![remote], None);
            assert_eq!(binding.state, NativeHostingBindingState::Bound);
            assert_eq!(
                binding.provider_repository.as_deref(),
                Some("group/nested/project")
            );
        }
        assert_eq!(
            canonical_resource_link(
                normalized.clone(),
                "group/nested/project".into(),
                NativeHostingResourceKind::ChangeRequest,
                Some(42),
            )
            .url
            .as_deref(),
            Some("https://git.example.test/group/nested/project/-/merge_requests/42")
        );
        assert_eq!(
            canonical_resource_link(
                normalized,
                "group/nested/project".into(),
                NativeHostingResourceKind::CreateChangeRequest,
                None,
            )
            .url
            .as_deref(),
            Some("https://git.example.test/group/nested/project/-/merge_requests/new")
        );
    }

    #[test]
    fn cli_authentication_is_limited_to_matching_providers() {
        let mut gitlab = connection("gitlab:cli");
        gitlab.oauth_client_id.clear();
        gitlab.authentication = NativeHostingAuthentication::GitLabCli;
        assert!(validate_native_connection(gitlab.clone())
            .connection
            .is_some());
        gitlab.authentication = NativeHostingAuthentication::GitHubCli;
        assert!(validate_native_connection(gitlab).connection.is_none());

        let mut enterprise = connection("github:cli");
        enterprise.preset = NativeHostingPreset::GitHubEnterprise;
        enterprise.web_base_url = "https://enterprise.example.test".into();
        enterprise.api_base_url = "https://enterprise.example.test/api/v3".into();
        enterprise.oauth_client_id.clear();
        enterprise.authentication = NativeHostingAuthentication::GitHubCli;
        assert!(validate_native_connection(enterprise.clone())
            .connection
            .is_some());
        assert_eq!(
            canonical_resource_link(
                enterprise,
                "team/project".into(),
                NativeHostingResourceKind::ChangeRequest,
                Some(3),
            )
            .url
            .as_deref(),
            Some("https://enterprise.example.test/team/project/pull/3")
        );
    }

    #[test]
    fn connection_name_accepts_internal_spaces() {
        let named = connection("My Work Forgejo");
        assert!(validate_native_connection(named).connection.is_some());
        assert!(!safe_identity(" Leading space"));
        assert!(!safe_identity("Trailing space "));
    }

    #[test]
    fn only_the_fixed_github_api_splits_bypass_enterprise_confirmation() {
        let mut github = connection("github:fixture");
        github.preset = NativeHostingPreset::GitHub;
        github.web_base_url = "https://github.com".into();
        github.api_base_url = "https://api.github.com".into();
        github.allow_split_origin = false;
        assert!(validate_native_connection(github.clone()).failure.is_none());
        github.api_base_url = "https://api.attacker.test".into();
        assert_eq!(
            validate_native_connection(github).failure,
            Some(NativeHostingFailureKind::InvalidConnection)
        );

        // A GitHub Enterprise Cloud tenant answers on api.<tenant>.ghe.com.
        let mut tenant = connection("github:tenant");
        tenant.preset = NativeHostingPreset::GitHubEnterprise;
        tenant.web_base_url = "https://octo.ghe.com".into();
        tenant.api_base_url = "https://api.octo.ghe.com".into();
        tenant.allow_split_origin = false;
        assert!(validate_native_connection(tenant.clone()).failure.is_none());
        for api in ["https://api.other.ghe.com", "https://api.attacker.test"] {
            tenant.api_base_url = api.into();
            assert_eq!(
                validate_native_connection(tenant.clone()).failure,
                Some(NativeHostingFailureKind::InvalidConnection)
            );
        }
        // An Enterprise Server keeps its API on the web origin.
        tenant.web_base_url = "https://enterprise.example.test".into();
        tenant.api_base_url = "https://api.enterprise.example.test".into();
        assert_eq!(
            validate_native_connection(tenant).failure,
            Some(NativeHostingFailureKind::InvalidConnection)
        );
    }

    #[test]
    fn ssh_ports_match_web_hosts_while_web_ports_and_changed_hosts_stay_distinct() {
        let first = connection("gitlab:first");
        let second = connection("gitlab:second");
        let remote = NativeHostingRemote {
            name: b"origin".to_vec(),
            url: "git@git.example.test:team/project.git".into(),
        };
        assert_eq!(
            resolve_binding(
                vec![first.clone(), second.clone()],
                vec![remote.clone()],
                None
            )
            .state,
            NativeHostingBindingState::Ambiguous
        );
        assert_eq!(
            resolve_binding(
                vec![first, second],
                vec![remote],
                Some("gitlab:second".into()),
            )
            .connection_id
            .as_deref(),
            Some("gitlab:second")
        );
        let different_port = NativeHostingRemote {
            name: b"upstream".to_vec(),
            url: "ssh://git@git.example.test:2222/team/project.git".into(),
        };
        let bound = resolve_binding(
            vec![connection("gitlab:one")],
            vec![different_port.clone()],
            None,
        );
        assert_eq!(bound.state, NativeHostingBindingState::Bound);
        assert_eq!(bound.remote, b"upstream");
        assert_eq!(bound.provider_repository.as_deref(), Some("team/project"));
        assert_eq!(
            bound.web_url.as_deref(),
            Some("https://git.example.test/team/project")
        );
        let mut other_web_port = connection("gitlab:other-port");
        other_web_port.web_base_url = "https://git.example.test:8443".into();
        other_web_port.api_base_url = "https://git.example.test:8443/api/v4".into();
        assert_eq!(
            resolve_binding(
                vec![connection("gitlab:one"), other_web_port.clone()],
                vec![different_port],
                None,
            )
            .state,
            NativeHostingBindingState::Ambiguous
        );
        assert_eq!(
            resolve_binding(
                vec![other_web_port],
                vec![NativeHostingRemote {
                    name: b"upstream".to_vec(),
                    url: "https://git.example.test/team/project.git".into(),
                }],
                None,
            )
            .state,
            NativeHostingBindingState::Unmatched
        );
        let changed_host = NativeHostingRemote {
            name: b"origin".to_vec(),
            url: "git@other.example.test:team/project.git".into(),
        };
        assert_eq!(
            resolve_binding(
                vec![connection("gitlab:one")],
                vec![changed_host],
                Some("gitlab:one".into()),
            )
            .state,
            NativeHostingBindingState::Unmatched
        );
    }

    #[derive(Default)]
    struct MemoryBackend {
        entries: Mutex<BTreeMap<String, Result<Vec<u8>, ()>>>,
        deletes: Mutex<Vec<String>>,
    }

    impl CredentialBackend for MemoryBackend {
        fn put(&self, key: &str, secret: &[u8]) -> Result<(), ()> {
            self.entries
                .lock()
                .unwrap()
                .insert(key.into(), Ok(secret.to_vec()));
            Ok(())
        }

        fn get(&self, key: &str) -> Result<Option<Vec<u8>>, ()> {
            self.entries.lock().unwrap().get(key).cloned().transpose()
        }

        fn delete(&self, key: &str) -> Result<(), ()> {
            self.deletes.lock().unwrap().push(key.into());
            self.entries.lock().unwrap().remove(key);
            Ok(())
        }
    }

    fn seed(
        backend: &MemoryBackend,
        connection: &NativeHostingConnection,
        expires: Option<u64>,
        refresh: Option<&str>,
    ) {
        let envelope =
            CredentialEnvelope::new("old-access".into(), refresh.map(str::to_owned), expires)
                .unwrap();
        store_credential_with(backend, connection, &envelope).unwrap();
    }

    #[test]
    fn credential_refresh_rotates_once_for_concurrent_requests_and_survives_reload() {
        use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
        let backend = MemoryBackend::default();
        let connection = connection("refresh:concurrent");
        seed(&backend, &connection, Some(99), Some("old-refresh"));
        let calls = AtomicUsize::new(0);
        let start = std::sync::Barrier::new(8);
        std::thread::scope(|scope| {
            for _ in 0..8 {
                let backend = &backend;
                let connection = &connection;
                let calls = &calls;
                let start = &start;
                scope.spawn(move || {
                    start.wait();
                    let loaded = load_credential_with(
                        backend,
                        connection,
                        &AtomicBool::new(false),
                        || 100,
                        |old| {
                            assert_eq!(old.refresh_token(), Some("old-refresh"));
                            calls.fetch_add(1, Ordering::SeqCst);
                            Ok(CredentialEnvelope::new(
                                "new-access".into(),
                                Some("new-refresh".into()),
                                Some(3700),
                            )
                            .unwrap())
                        },
                    )
                    .unwrap();
                    assert_eq!(loaded.access_token(), b"new-access");
                });
            }
        });
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        // A later request, as after restart, consumes the replacement refresh token.
        let loaded = load_credential_with(
            &backend,
            &connection,
            &AtomicBool::new(false),
            || 3690,
            |old| {
                assert_eq!(old.refresh_token(), Some("new-refresh"));
                Ok(CredentialEnvelope::new(
                    "third-access".into(),
                    Some("third-refresh".into()),
                    Some(7290),
                )
                .unwrap())
            },
        )
        .unwrap();
        assert_eq!(loaded.access_token(), b"third-access");
    }

    #[test]
    fn credential_refresh_is_lazy_and_preserves_original_on_failures() {
        use std::sync::atomic::AtomicBool;
        let backend = MemoryBackend::default();
        let connection = connection("refresh:lazy");
        for (expiry, refresh) in [
            (None, Some("refresh")),
            (Some(161), Some("refresh")),
            (Some(101), None),
        ] {
            seed(&backend, &connection, expiry, refresh);
            let loaded = load_credential_with(
                &backend,
                &connection,
                &AtomicBool::new(false),
                || 100,
                |_| panic!("must not refresh"),
            )
            .unwrap();
            assert_eq!(loaded.access_token(), b"old-access");
        }
        seed(&backend, &connection, Some(99), None);
        assert!(matches!(
            load_credential_with(
                &backend,
                &connection,
                &AtomicBool::new(false),
                || 100,
                |_| panic!("no refresh token")
            ),
            Err(CredentialLoadError::Store(
                NativeHostingFailureKind::CredentialExpired
            ))
        ));
        seed(&backend, &connection, Some(160), Some("refresh"));
        let before = backend.get(&credential_key(&connection)).unwrap();
        assert!(matches!(
            load_credential_with(
                &backend,
                &connection,
                &AtomicBool::new(false),
                || 100,
                |_| Err(HostingError::RateLimited)
            ),
            Err(CredentialLoadError::Refresh(HostingError::RateLimited))
        ));
        assert_eq!(backend.get(&credential_key(&connection)).unwrap(), before);
        assert!(backend.deletes.lock().unwrap().is_empty());
        assert!(matches!(
            load_credential_with(
                &backend,
                &connection,
                &AtomicBool::new(true),
                || 100,
                |_| panic!("cancelled")
            ),
            Err(CredentialLoadError::Refresh(HostingError::Canceled))
        ));
        backend
            .entries
            .lock()
            .unwrap()
            .insert(credential_key(&connection), Err(()));
        assert!(matches!(
            load_credential_with(
                &backend,
                &connection,
                &AtomicBool::new(false),
                || 100,
                |_| panic!("unreadable")
            ),
            Err(CredentialLoadError::Store(
                NativeHostingFailureKind::CredentialUnreadable
            ))
        ));
    }

    #[test]
    fn credential_wait_can_cancel_and_late_cancellation_keeps_rotated_tokens() {
        use std::sync::atomic::{AtomicBool, Ordering};
        let backend = MemoryBackend::default();
        let connection = connection("refresh:cancel");
        seed(&backend, &connection, Some(99), Some("refresh"));
        let cancel = AtomicBool::new(false);
        let lock = credential_lock(&connection);
        let guard = lock.lock().unwrap();
        let started = std::sync::Barrier::new(2);
        std::thread::scope(|scope| {
            let worker = scope.spawn(|| {
                started.wait();
                load_credential_with(
                    &backend,
                    &connection,
                    &cancel,
                    || 100,
                    |_| panic!("blocked"),
                )
            });
            started.wait();
            cancel.store(true, Ordering::Release);
            assert!(matches!(
                worker.join().unwrap(),
                Err(CredentialLoadError::Refresh(HostingError::Canceled))
            ));
        });
        drop(guard);
        cancel.store(false, Ordering::Release);
        load_credential_with(
            &backend,
            &connection,
            &cancel,
            || 100,
            |_| {
                cancel.store(true, Ordering::Release);
                Ok(CredentialEnvelope::new(
                    "new-access".into(),
                    Some("new-refresh".into()),
                    Some(3700),
                )
                .unwrap())
            },
        )
        .unwrap();
        let stored: CredentialEnvelope =
            serde_json::from_slice(&backend.get(&credential_key(&connection)).unwrap().unwrap())
                .unwrap();
        assert_eq!(stored.refresh_token(), Some("new-refresh"));
    }

    #[test]
    fn credential_refresh_cannot_overwrite_reauthentication_or_resurrect_removed_accounts() {
        for remove in [false, true] {
            let backend = MemoryBackend::default();
            let connection = connection(if remove {
                "refresh:remove"
            } else {
                "refresh:reauth"
            });
            let mut alias = connection.clone();
            alias.id = "alias".into();
            assert!(Arc::ptr_eq(
                &credential_lock(&connection),
                &credential_lock(&alias)
            ));
            seed(&backend, &connection, Some(99), Some("old-refresh"));
            let (started_tx, started_rx) = std::sync::mpsc::channel();
            let (release_tx, release_rx) = std::sync::mpsc::channel();
            std::thread::scope(|scope| {
                let backend_ref = &backend;
                let connection_ref = &connection;
                let refresh = scope.spawn(move || {
                    load_credential_with(
                        backend_ref,
                        connection_ref,
                        &std::sync::atomic::AtomicBool::new(false),
                        || 100,
                        |_| {
                            started_tx.send(()).unwrap();
                            release_rx.recv().unwrap();
                            Ok(CredentialEnvelope::new(
                                "rotated-access".into(),
                                Some("rotated-refresh".into()),
                                Some(3700),
                            )
                            .unwrap())
                        },
                    )
                    .unwrap()
                });
                started_rx.recv_timeout(Duration::from_secs(2)).unwrap();
                let (attempt_tx, attempt_rx) = std::sync::mpsc::channel();
                let backend_ref = &backend;
                let alias_ref = &alias;
                let writer = scope.spawn(move || {
                    attempt_tx.send(()).unwrap();
                    if remove {
                        assert_eq!(
                            remove_credential_with(backend_ref, alias_ref, 100).state,
                            NativeHostingCredentialState::Missing
                        );
                    } else {
                        let login = CredentialEnvelope::new(
                            "login-access".into(),
                            Some("login-refresh".into()),
                            Some(7200),
                        )
                        .unwrap();
                        store_credential_locked_with(backend_ref, alias_ref, &login).unwrap();
                    }
                });
                attempt_rx.recv_timeout(Duration::from_secs(2)).unwrap();
                release_tx.send(()).unwrap();
                refresh.join().unwrap();
                writer.join().unwrap();
            });
            let saved = backend.get(&credential_key(&connection)).unwrap();
            if remove {
                assert!(saved.is_none());
            } else {
                let saved: CredentialEnvelope = serde_json::from_slice(&saved.unwrap()).unwrap();
                assert_eq!(saved.access_token(), b"login-access");
                assert_eq!(saved.refresh_token(), Some("login-refresh"));
            }
        }
    }

    #[test]
    fn credential_refresh_save_failure_is_reported_without_publishing_new_access() {
        struct ReadOnlyBackend(MemoryBackend);
        impl CredentialBackend for ReadOnlyBackend {
            fn put(&self, _: &str, _: &[u8]) -> Result<(), ()> {
                Err(())
            }
            fn get(&self, key: &str) -> Result<Option<Vec<u8>>, ()> {
                self.0.get(key)
            }
            fn delete(&self, _: &str) -> Result<(), ()> {
                panic!("must not delete")
            }
        }
        let backend = ReadOnlyBackend(MemoryBackend::default());
        let connection = connection("refresh:save-failure");
        seed(&backend.0, &connection, Some(99), Some("refresh"));
        let result = load_credential_with(
            &backend,
            &connection,
            &std::sync::atomic::AtomicBool::new(false),
            || 100,
            |_| {
                Ok(CredentialEnvelope::new(
                    "new-access".into(),
                    Some("new-refresh".into()),
                    Some(3700),
                )
                .unwrap())
            },
        );
        assert!(matches!(
            result,
            Err(CredentialLoadError::Store(
                NativeHostingFailureKind::CredentialStore
            ))
        ));
    }

    #[test]
    fn credential_states_are_distinct_and_secrets_are_redacted() {
        let backend = MemoryBackend::default();
        let connection = normalized_connection(connection("gitlab:one")).unwrap();
        assert_eq!(
            credential_state_with(&backend, &connection, 100).state,
            NativeHostingCredentialState::Missing
        );
        let missing_removal = remove_credential_with(&backend, &connection, 100);
        assert_eq!(missing_removal.state, NativeHostingCredentialState::Missing);
        assert_eq!(missing_removal.failure, None);
        let envelope = CredentialEnvelope::new("sentinel-token".into(), None, Some(99)).unwrap();
        let mut encoded = serde_json::to_vec(&envelope).unwrap();
        backend.put(&credential_key(&connection), &encoded).unwrap();
        encoded.zeroize();
        assert_eq!(
            credential_state_with(&backend, &connection, 100).state,
            NativeHostingCredentialState::Expired
        );
        backend
            .entries
            .lock()
            .unwrap()
            .insert(credential_key(&connection), Err(()));
        assert_eq!(
            credential_state_with(&backend, &connection, 100).state,
            NativeHostingCredentialState::Unreadable
        );
        assert_eq!(
            remove_credential_with(&backend, &connection, 100).state,
            NativeHostingCredentialState::Unreadable
        );
        assert!(backend.deletes.lock().unwrap().is_empty());
        assert!(!format!("{envelope:?}").contains("sentinel-token"));
    }
}
