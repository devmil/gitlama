//! Hosting accounts and the active repository's hosting state (the Dart
//! HostingConnectionService and HostingRepositorySession): accounts live in
//! the settings with their credentials in the system store; a repository is
//! bound to one account and provider repository, automatically from its
//! remotes or by an override; its pull requests, issues and references load
//! in pages; pull requests are linked to the branches views show in small
//! batches, plus the ones the account authored, and the CI result of one
//! commit can be asked for. Nothing here logs a URL, login or path.

use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::settings::SettingsService;
use gitlama_contract::dto::NativePathIdentity;
use gitlama_contract::hosting::{
    NativeHostingAuthentication, NativeHostingBindingResult, NativeHostingBindingState, NativeHostingCapability,
    NativeHostingChangeRequest, NativeHostingChangeRequestState, NativeHostingCheckState, NativeHostingConnection,
    NativeHostingCredentialState, NativeHostingFailureKind, NativeHostingMergeability, NativeHostingPreset, NativeHostingRemote,
    NativeHostingResourceKind, NativeHostingResources,
};
use gitlama_contract::hosting_runtime::{
    NativeHostingOAuthSnapshot, NativeHostingOAuthState, NativeHostingResourceFailure, NativeHostingResourceLoadState,
    NativeHostingResourceSnapshot,
};
use gitlama_contract::hosting_settings::{NativeHostingBindingSettings, NativeHostingConnectionSettings};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};
use std::time::Duration;

/// Most accounts the settings keep.
pub const MAXIMUM_CONNECTIONS: usize = 32;
/// Most branches one lookup resolves.
pub const LOOKUP_BATCH: usize = 20;
/// Branches waiting for a lookup; older requests go first.
const LOOKUP_QUEUE_LIMIT: usize = 200;
/// An unsettled answer (running checks, mergeability being computed) is
/// asked again after this long.
const PENDING_RECHECK: Duration = Duration::from_secs(60);
/// A pull request whose head is at none of its branch's refs is asked
/// again after this long, a few times.
const MOVED_RECHECK: Duration = Duration::from_secs(10);
const MOVED_RECHECK_LIMIT: u32 = 3;

// ---------------------------------------------------------------- names

pub fn preset_name(preset: NativeHostingPreset) -> &'static str {
    match preset {
        NativeHostingPreset::GitHub => "github",
        NativeHostingPreset::GitLab => "gitlab",
        NativeHostingPreset::GitLabSelfManaged => "gitlabSelfManaged",
        NativeHostingPreset::Forgejo => "forgejo",
        NativeHostingPreset::Codeberg => "codeberg",
        NativeHostingPreset::GitHubEnterprise => "gitHubEnterprise",
    }
}

pub fn parse_preset(name: &str) -> Option<NativeHostingPreset> {
    Some(match name {
        "github" => NativeHostingPreset::GitHub,
        "gitlab" => NativeHostingPreset::GitLab,
        "gitlabSelfManaged" => NativeHostingPreset::GitLabSelfManaged,
        "forgejo" => NativeHostingPreset::Forgejo,
        "codeberg" => NativeHostingPreset::Codeberg,
        "gitHubEnterprise" => NativeHostingPreset::GitHubEnterprise,
        _ => return None,
    })
}

pub fn authentication_name(authentication: NativeHostingAuthentication) -> &'static str {
    match authentication {
        NativeHostingAuthentication::OAuth => "oauth",
        NativeHostingAuthentication::GitHubCli => "gitHubCli",
        NativeHostingAuthentication::GitLabCli => "gitLabCli",
    }
}

pub fn parse_authentication(name: &str) -> Option<NativeHostingAuthentication> {
    Some(match name {
        "oauth" => NativeHostingAuthentication::OAuth,
        "gitHubCli" => NativeHostingAuthentication::GitHubCli,
        "gitLabCli" => NativeHostingAuthentication::GitLabCli,
        _ => return None,
    })
}

pub fn capability_name(capability: NativeHostingCapability) -> &'static str {
    match capability {
        NativeHostingCapability::ChangeRequests => "changeRequests",
        NativeHostingCapability::ChangeRequestCheckout => "changeRequestCheckout",
        NativeHostingCapability::ChangeRequestReview => "changeRequestReview",
        NativeHostingCapability::CommitStatuses => "commitStatuses",
        NativeHostingCapability::CheckRuns => "checkRuns",
        NativeHostingCapability::Issues => "issues",
        NativeHostingCapability::RemoteReferences => "remoteReferences",
    }
}

pub fn parse_capability(name: &str) -> Option<NativeHostingCapability> {
    Some(match name {
        "changeRequests" => NativeHostingCapability::ChangeRequests,
        "changeRequestCheckout" => NativeHostingCapability::ChangeRequestCheckout,
        "changeRequestReview" => NativeHostingCapability::ChangeRequestReview,
        "commitStatuses" => NativeHostingCapability::CommitStatuses,
        "checkRuns" => NativeHostingCapability::CheckRuns,
        "issues" => NativeHostingCapability::Issues,
        "remoteReferences" => NativeHostingCapability::RemoteReferences,
        _ => return None,
    })
}

/// A stored account as the core takes it; None for unknown names.
pub fn connection_of(settings: &NativeHostingConnectionSettings) -> Option<NativeHostingConnection> {
    Some(NativeHostingConnection {
        id: settings.id.clone(),
        preset: parse_preset(&settings.preset)?,
        login: settings.login.clone(),
        web_base_url: settings.web_base_url.clone(),
        api_base_url: settings.api_base_url.clone(),
        oauth_client_id: settings.oauth_client_id.clone(),
        authentication: parse_authentication(&settings.authentication)?,
        enabled: settings.enabled,
        refresh_enabled: settings.refresh_enabled,
        capabilities: settings.capabilities.iter().filter_map(|name| parse_capability(name)).collect(),
        credential_identity: settings.credential_identity.clone(),
        allow_split_origin: settings.allow_split_origin,
    })
}

pub fn settings_of(connection: &NativeHostingConnection) -> NativeHostingConnectionSettings {
    NativeHostingConnectionSettings {
        id: connection.id.clone(),
        preset: preset_name(connection.preset).to_owned(),
        login: connection.login.clone(),
        web_base_url: connection.web_base_url.clone(),
        api_base_url: connection.api_base_url.clone(),
        oauth_client_id: connection.oauth_client_id.clone(),
        authentication: authentication_name(connection.authentication).to_owned(),
        enabled: connection.enabled,
        refresh_enabled: connection.refresh_enabled,
        capabilities: connection.capabilities.iter().map(|capability| capability_name(*capability).to_owned()).collect(),
        credential_identity: connection.credential_identity.clone(),
        allow_split_origin: connection.allow_split_origin,
    }
}

/// A hosting failure's code, as the page words it ("settings" for a
/// refused settings write).
pub fn failure_key(kind: NativeHostingFailureKind) -> &'static str {
    match kind {
        NativeHostingFailureKind::InvalidConnection => "invalidConnection",
        NativeHostingFailureKind::InvalidRemote => "invalidRemote",
        NativeHostingFailureKind::InvalidLink => "invalidLink",
        NativeHostingFailureKind::Ambiguous => "ambiguous",
        NativeHostingFailureKind::CredentialMissing => "credentialMissing",
        NativeHostingFailureKind::CredentialUnreadable => "credentialUnreadable",
        NativeHostingFailureKind::CredentialExpired => "credentialExpired",
        NativeHostingFailureKind::CredentialStore => "credentialStore",
    }
}

pub fn resource_failure_name(failure: NativeHostingResourceFailure) -> &'static str {
    use NativeHostingResourceFailure::*;
    match failure {
        InvalidRequest => "invalidRequest",
        IntegrationDisabled => "integrationDisabled",
        CredentialMissing => "credentialMissing",
        CredentialUnreadable => "credentialUnreadable",
        CredentialExpired => "credentialExpired",
        Unauthorized => "unauthorized",
        PermissionDenied => "permissionDenied",
        RateLimited => "rateLimited",
        MalformedResponse => "malformedResponse",
        Unavailable => "unavailable",
        NotFound => "notFound",
        Redirected => "redirected",
        ServerError => "serverError",
        Network => "network",
        Certificate => "certificate",
        TimedOut => "timedOut",
    }
}

pub fn oauth_failure_name(failure: gitlama_contract::hosting_runtime::NativeHostingOAuthFailure) -> &'static str {
    use gitlama_contract::hosting_runtime::NativeHostingOAuthFailure::*;
    match failure {
        InvalidConnection => "invalidConnection",
        Busy => "busy",
        Unavailable => "unavailable",
        Unauthorized => "unauthorized",
        RateLimited => "rateLimited",
        MalformedResponse => "malformedResponse",
        Expired => "expired",
        Denied => "denied",
        SecureStore => "secureStore",
        NotFound => "notFound",
        Redirected => "redirected",
        ServerError => "serverError",
        Network => "network",
        Certificate => "certificate",
        TimedOut => "timedOut",
    }
}

fn oauth_terminal(state: NativeHostingOAuthState) -> bool {
    matches!(state, NativeHostingOAuthState::Succeeded | NativeHostingOAuthState::Failed | NativeHostingOAuthState::Canceled)
}

fn resource_terminal(state: NativeHostingResourceLoadState) -> bool {
    !matches!(state, NativeHostingResourceLoadState::Loading)
}

/// Whether `url` may open in a browser: https (or http on the loopback
/// interface), with a host and no user information.
pub fn openable_url(url: &str) -> bool {
    let Some((scheme, rest)) = url.split_once("://") else { return false };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or_default();
    if authority.is_empty() || authority.contains('@') {
        return false;
    }
    let host = authority.rsplit_once(':').map_or(authority, |(host, _)| host);
    scheme == "https" || (scheme == "http" && matches!(host, "localhost" | "127.0.0.1"))
}

/// The defaults a new account of `preset` starts with, for the form:
/// {preset, webBaseUrl, apiBaseUrl, capabilities, authentications}, or
/// null when a self-hosted preset has no valid `https` `web_base`.
pub fn preset_defaults_value(preset: NativeHostingPreset, web_base: Option<String>) -> serde_json::Value {
    let result = gitlama_core::api::hosting_preset_defaults(preset, web_base);
    result.defaults.filter(|_| result.failure.is_none()).map_or(serde_json::Value::Null, |defaults| {
        serde_json::json!({
            "preset": preset_name(defaults.preset),
            "webBaseUrl": defaults.web_base_url,
            "apiBaseUrl": defaults.api_base_url,
            "capabilities": defaults.capabilities.iter().map(|capability| capability_name(*capability)).collect::<Vec<_>>(),
            "authentications": defaults.authentications.iter().map(|method| authentication_name(*method)).collect::<Vec<_>>(),
        })
    })
}

// ---------------------------------------------------------------- accounts

/// The sign-in in progress, for the accounts page.
#[derive(Clone, Debug, Default)]
pub struct Authorization {
    pub connection_id: String,
    pub snapshot: Option<NativeHostingOAuthSnapshot>,
    /// The sign-in adds a new account: the form closes once it succeeds.
    pub new_connection: bool,
}

/// Accounts and their sign-ins (the Dart HostingConnectionService).
pub struct Hosting {
    settings: Rc<SettingsService>,
    notifier: Notifier,
    authorization: RefCell<Option<Authorization>>,
    /// Bumps when the accounts or bindings change.
    revision: Cell<u64>,
    runtime_used: Cell<bool>,
    cli: Cell<(bool, bool)>,
    /// Each account's credential state, read after the accounts change.
    credentials: RefCell<Vec<(String, NativeHostingCredentialState)>>,
}

impl Hosting {
    /// Starts with the stored accounts; ones the core no longer accepts are
    /// removed (their credential items are left alone).
    pub async fn new(settings: Rc<SettingsService>, notifier: Notifier) -> Rc<Self> {
        let this = Rc::new(Self {
            settings,
            notifier,
            authorization: RefCell::new(None),
            revision: Cell::new(0),
            runtime_used: Cell::new(false),
            cli: Cell::new((false, false)),
            credentials: RefCell::new(Vec::new()),
        });
        let stored = this.settings.with(|document| document.hosting_connections.clone());
        let mut retained = Vec::new();
        for settings in stored.iter() {
            let Some(connection) = connection_of(settings) else { continue };
            let result = rt::blocking(move || gitlama_core::api::hosting_connection_validate(connection)).await;
            if let (Some(connection), None) = (result.connection, result.failure) {
                retained.push(settings_of(&connection));
            }
        }
        if retained.len() != stored.len() {
            let ids: HashSet<String> = retained.iter().map(|connection| connection.id.clone()).collect();
            let _ = this
                .save_hosting(move |document| {
                    document.hosting_connections = retained;
                    document.hosting_bindings.retain(|binding| ids.contains(&binding.connection_id));
                })
                .await;
        }
        this.read_credentials();
        let weak = Rc::downgrade(&this);
        rt::spawn_detached(async move {
            let found = rt::blocking(|| (gitlama_core::api::hosting_github_cli_available(), gitlama_core::api::hosting_gitlab_cli_available())).await;
            if let Some(this) = weak.upgrade() {
                this.cli.set(found);
                this.changed();
            }
        });
        this
    }

    fn changed(&self) {
        self.notifier.notify(Topics::HOSTING);
    }

    pub fn revision(&self) -> u64 {
        self.revision.get()
    }

    /// Whether the GitHub and GitLab command-line tools are installed.
    pub fn cli_available(&self) -> (bool, bool) {
        self.cli.get()
    }

    pub fn credentials(&self) -> Vec<(String, NativeHostingCredentialState)> {
        self.credentials.borrow().clone()
    }

    /// Reads every account's credential state away from the interface.
    pub fn read_credentials(self: &Rc<Self>) {
        let connections = self.connections();
        let weak = Rc::downgrade(self);
        rt::spawn_detached(async move {
            let states = rt::blocking(move || {
                connections
                    .into_iter()
                    .map(|connection| (connection.id.clone(), gitlama_core::api::hosting_credential_state(connection).state))
                    .collect::<Vec<_>>()
            })
            .await;
            if let Some(this) = weak.upgrade() {
                *this.credentials.borrow_mut() = states;
                this.changed();
            }
        });
    }

    pub fn connections(&self) -> Vec<NativeHostingConnection> {
        self.settings.with(|document| document.hosting_connections.iter().filter_map(connection_of).collect())
    }

    pub fn connection(&self, id: &str) -> Option<NativeHostingConnection> {
        self.connections().into_iter().find(|connection| connection.id == id)
    }

    pub fn binding_for(&self, repository: &NativePathIdentity) -> Option<NativeHostingBindingSettings> {
        self.settings.with(|document| document.hosting_bindings.iter().find(|binding| &binding.repository == repository).cloned())
    }

    pub fn authorization(&self) -> Option<Authorization> {
        self.authorization.borrow().clone()
    }

    async fn save_hosting(&self, change: impl FnOnce(&mut gitlama_contract::storage::NativeSettingsDocument)) -> Result<(), ()> {
        let saved = self
            .settings
            .update_durable(change, |current, previous| {
                current.hosting_connections = previous.hosting_connections.clone();
                current.hosting_bindings = previous.hosting_bindings.clone();
            })
            .await
            .map_err(|_| ());
        self.revision.set(self.revision.get() + 1);
        self.changed();
        saved
    }

    async fn validate(connection: NativeHostingConnection) -> Result<NativeHostingConnection, NativeHostingFailureKind> {
        let result = rt::blocking(move || gitlama_core::api::hosting_connection_validate(connection)).await;
        match (result.connection, result.failure) {
            (Some(connection), None) => Ok(connection),
            (_, failure) => Err(failure.unwrap_or(NativeHostingFailureKind::InvalidConnection)),
        }
    }

    /// Stores `connection` in place of the account with its name.
    pub async fn save_connection(&self, connection: NativeHostingConnection) -> Result<NativeHostingConnection, &'static str> {
        let normalized = Self::validate(connection).await.map_err(failure_key)?;
        let current = self.connections();
        if current.len() >= MAXIMUM_CONNECTIONS && !current.iter().any(|value| value.id == normalized.id) {
            return Err("settings");
        }
        if current.iter().any(|value| value.id != normalized.id && value.credential_identity == normalized.credential_identity) {
            return Err("settings");
        }
        let mut next: Vec<NativeHostingConnection> = current.into_iter().filter(|value| value.id != normalized.id).collect();
        next.push(normalized.clone());
        next.sort_by(|left, right| left.id.cmp(&right.id));
        let stored: Vec<NativeHostingConnectionSettings> = next.iter().map(settings_of).collect();
        self.save_hosting(move |document| document.hosting_connections = stored).await.map_err(|_| "settings")?;
        Ok(normalized)
    }

    /// Removes account `id` with its credential; the account comes back
    /// when the credential cannot be removed.
    pub async fn remove_connection(&self, id: &str) -> Result<(), &'static str> {
        let Some(connection) = self.connection(id) else { return Ok(()) };
        let probe = connection.clone();
        let state = rt::blocking(move || gitlama_core::api::hosting_credential_state(probe)).await.state;
        if state == NativeHostingCredentialState::Unreadable {
            return Err(failure_key(NativeHostingFailureKind::CredentialUnreadable));
        }
        let (previous_connections, previous_bindings) =
            self.settings.with(|document| (document.hosting_connections.clone(), document.hosting_bindings.clone()));
        let id = id.to_owned();
        let removed_id = id.clone();
        self.save_hosting(move |document| {
            document.hosting_connections.retain(|value| value.id != removed_id);
            document.hosting_bindings.retain(|value| value.connection_id != removed_id);
        })
        .await
        .map_err(|_| "settings")?;
        let removed = rt::blocking(move || gitlama_core::api::hosting_credential_remove(connection)).await;
        if let Some(failure) = removed.failure {
            let _ = self
                .save_hosting(move |document| {
                    document.hosting_connections = previous_connections;
                    document.hosting_bindings = previous_bindings;
                })
                .await;
            return Err(failure_key(failure));
        }
        Ok(())
    }

    pub async fn save_binding(&self, binding: NativeHostingBindingSettings) -> Result<(), &'static str> {
        if !self.connections().iter().any(|connection| connection.id == binding.connection_id) {
            return Err("settings");
        }
        self.save_hosting(move |document| {
            document.hosting_bindings.retain(|existing| existing.repository != binding.repository);
            document.hosting_bindings.push(binding);
        })
        .await
        .map_err(|_| "settings")
    }

    pub async fn clear_binding(&self, repository: NativePathIdentity) -> Result<(), &'static str> {
        self.save_hosting(move |document| document.hosting_bindings.retain(|binding| binding.repository != repository))
            .await
            .map_err(|_| "settings")
    }

    pub fn expanded_nodes(&self) -> Vec<String> {
        self.settings.with(|document| document.hosting_expanded_nodes.clone())
    }

    pub fn set_expanded_nodes(&self, nodes: Vec<String>) {
        let mut nodes: Vec<String> = nodes.into_iter().collect::<HashSet<_>>().into_iter().take(256).collect();
        nodes.sort();
        let _ = self.settings.update(|document| document.hosting_expanded_nodes = nodes);
    }

    pub async fn credential_state(&self, id: &str) -> Option<NativeHostingCredentialState> {
        let connection = self.connection(id)?;
        Some(rt::blocking(move || gitlama_core::api::hosting_credential_state(connection)).await.state)
    }

    /// Signs `connection` in. A sign-in the core finishes at once (a
    /// command-line tool) stores the account; otherwise it is followed every
    /// half second until it ends.
    pub async fn authorize(self: &Rc<Self>, connection: NativeHostingConnection, new_connection: bool) -> Result<(), String> {
        if let Some(previous) = self.authorization.borrow_mut().take()
            && let Some(snapshot) = previous.snapshot.filter(|snapshot| !oauth_terminal(snapshot.state))
        {
            let request = snapshot.request_id;
            rt::spawn_detached(async move {
                rt::blocking(move || gitlama_core::api::hosting_oauth_cancel(request)).await;
            });
        }
        let normalized = Self::validate(connection).await.map_err(|failure| failure_key(failure).to_owned())?;
        let start = normalized.clone();
        let result = rt::blocking(move || gitlama_core::api::hosting_oauth_start(start)).await;
        if let Some(failure) = result.failure {
            return Err(format!("oauth:{}", oauth_failure_name(failure)));
        }
        let Some(snapshot) = result.snapshot else { return Err("malformedResponse".to_owned()) };
        self.runtime_used.set(true);
        *self.authorization.borrow_mut() =
            Some(Authorization { connection_id: normalized.id.clone(), snapshot: Some(snapshot.clone()), new_connection });
        self.changed();
        if snapshot.state == NativeHostingOAuthState::Succeeded {
            return self.finish_authorization(&normalized, &snapshot).await;
        }
        if !oauth_terminal(snapshot.state) {
            let weak = Rc::downgrade(self);
            rt::spawn_detached(Self::follow(weak, normalized, snapshot.request_id));
        }
        Ok(())
    }

    async fn finish_authorization(&self, connection: &NativeHostingConnection, snapshot: &NativeHostingOAuthSnapshot) -> Result<(), String> {
        let Some(login) = snapshot.authenticated_login.clone() else { return Err("malformedResponse".to_owned()) };
        let mut signed_in = connection.clone();
        signed_in.login = login;
        self.save_connection(signed_in).await.map_err(str::to_owned)?;
        Ok(())
    }

    async fn follow(this: Weak<Self>, connection: NativeHostingConnection, request: u64) {
        loop {
            rt::sleep(Duration::from_millis(500)).await;
            let Some(hosting) = this.upgrade() else { return };
            let current = hosting
                .authorization
                .borrow()
                .as_ref()
                .and_then(|authorization| authorization.snapshot.as_ref().map(|snapshot| snapshot.request_id));
            if current != Some(request) {
                return;
            }
            let polled = rt::blocking(move || gitlama_core::api::hosting_oauth_poll(request)).await;
            let Some(snapshot) = polled.snapshot else {
                hosting.authorization.borrow_mut().take();
                hosting.changed();
                return;
            };
            if snapshot.state == NativeHostingOAuthState::Succeeded
                && let Err(failure) = hosting.finish_authorization(&connection, &snapshot).await
            {
                let mut failed = snapshot.clone();
                failed.state = NativeHostingOAuthState::Failed;
                if let Some(authorization) = hosting.authorization.borrow_mut().as_mut() {
                    authorization.snapshot = Some(failed);
                }
                let _ = failure;
                hosting.changed();
                return;
            }
            let terminal = oauth_terminal(snapshot.state);
            if let Some(authorization) = hosting.authorization.borrow_mut().as_mut() {
                authorization.snapshot = Some(snapshot);
            }
            hosting.changed();
            if terminal {
                return;
            }
        }
    }

    /// Forgets a finished sign-in; a running one is canceled.
    pub async fn end_authorization(&self) {
        let ended = self.authorization.borrow_mut().take();
        if let Some(snapshot) = ended.and_then(|authorization| authorization.snapshot).filter(|snapshot| !oauth_terminal(snapshot.state)) {
            let request = snapshot.request_id;
            rt::blocking(move || gitlama_core::api::hosting_oauth_cancel(request)).await;
        }
        self.changed();
    }

    pub fn resolve_binding(&self, remotes: Vec<NativeHostingRemote>) -> NativeHostingBindingResult {
        gitlama_core::api::hosting_binding_resolve(self.connections(), remotes, None)
    }

    /// The web page of a resource, or why there is none.
    pub fn resource_link(
        &self,
        connection_id: &str,
        provider_repository: &str,
        kind: NativeHostingResourceKind,
        number: Option<u64>,
    ) -> Result<String, &'static str> {
        let Some(connection) = self.connection(connection_id) else { return Err("settings") };
        let result = gitlama_core::api::hosting_resource_link(connection, provider_repository.to_owned(), kind, number);
        match (result.url, result.failure) {
            (Some(url), None) if openable_url(&url) => Ok(url),
            (_, Some(failure)) => Err(failure_key(failure)),
            _ => Err(failure_key(NativeHostingFailureKind::InvalidLink)),
        }
    }

    pub fn note_runtime_used(&self) {
        self.runtime_used.set(true);
    }

    pub async fn dispose(&self) {
        self.end_authorization().await;
        if self.runtime_used.get() {
            rt::blocking(gitlama_core::api::hosting_runtime_shutdown).await;
        }
    }
}

// ---------------------------------------------------------------- repository session

/// A pull request linked to what the repository shows.
#[derive(Clone, Debug)]
pub struct Linked {
    pub pull: NativeHostingChangeRequest,
    pub authored: bool,
    pub via_branch: bool,
}

struct SessionState {
    repository: Option<NativePathIdentity>,
    remotes: Vec<NativeHostingRemote>,
    binding: Option<NativeHostingBindingResult>,
    resources: NativeHostingResources,
    snapshot: Option<NativeHostingResourceSnapshot>,
    failure: Option<String>,
    busy: bool,
    /// Known pull requests by branch, least recently learned first.
    branch_pulls: Vec<(String, Vec<NativeHostingChangeRequest>)>,
    fresh: HashSet<String>,
    queued: Vec<String>,
    in_flight: HashSet<String>,
    failed: HashSet<String>,
    authored: Option<Vec<NativeHostingChangeRequest>>,
    authored_requested: bool,
    authored_fresh: bool,
    lookup_running: bool,
    lookup_failure: Option<NativeHostingResourceFailure>,
    moved_refs: HashMap<String, (String, u32)>,
    moved: HashSet<String>,
    head: Option<String>,
    head_checks: Option<NativeHostingCheckState>,
    head_queued: bool,
    head_in_flight: bool,
    head_failed: bool,
    pending_recheck: bool,
    moved_recheck: bool,
    debounce: bool,
}

fn empty_resources() -> NativeHostingResources {
    NativeHostingResources { change_requests: Vec::new(), issues: Vec::new(), remote_references: Vec::new() }
}

impl Default for SessionState {
    fn default() -> Self {
        Self {
            repository: None,
            remotes: Vec::new(),
            binding: None,
            resources: empty_resources(),
            snapshot: None,
            failure: None,
            busy: false,
            branch_pulls: Vec::new(),
            fresh: HashSet::new(),
            queued: Vec::new(),
            in_flight: HashSet::new(),
            failed: HashSet::new(),
            authored: None,
            authored_requested: false,
            authored_fresh: false,
            lookup_running: false,
            lookup_failure: None,
            moved_refs: HashMap::new(),
            moved: HashSet::new(),
            head: None,
            head_checks: None,
            head_queued: false,
            head_in_flight: false,
            head_failed: false,
            pending_recheck: false,
            moved_recheck: false,
            debounce: false,
        }
    }
}

/// The active repository's hosting state (the Dart HostingRepositorySession).
pub struct RepositoryHosting {
    hosting: Rc<Hosting>,
    notifier: Notifier,
    state: RefCell<SessionState>,
    generation: Cell<u64>,
    epoch: Cell<u64>,
    seen_revision: Cell<u64>,
}

fn same_pulls(left: Option<&Vec<NativeHostingChangeRequest>>, right: Option<&Vec<NativeHostingChangeRequest>>) -> bool {
    match (left, right) {
        (Some(left), Some(right)) => {
            left.len() == right.len()
                && left.iter().zip(right).all(|(a, b)| {
                    a.number == b.number
                        && a.state == b.state
                        && a.draft == b.draft
                        && a.title == b.title
                        && a.head_sha == b.head_sha
                        && a.checks.state == b.checks.state
                        && a.mergeability == b.mergeability
                })
        }
        (None, None) => true,
        _ => false,
    }
}

fn unsettled(pulls: Option<&Vec<NativeHostingChangeRequest>>) -> bool {
    pulls.is_some_and(|pulls| {
        pulls.iter().any(|pull| {
            pull.state == NativeHostingChangeRequestState::Open
                && (pull.checks.state == NativeHostingCheckState::Pending || pull.mergeability == NativeHostingMergeability::Checking)
        })
    })
}

impl RepositoryHosting {
    pub fn new(hosting: Rc<Hosting>, notifier: Notifier) -> Rc<Self> {
        Rc::new(Self {
            hosting,
            notifier,
            state: RefCell::new(SessionState::default()),
            generation: Cell::new(0),
            epoch: Cell::new(0),
            seen_revision: Cell::new(0),
        })
    }

    fn changed(&self) {
        self.notifier.notify(Topics::HOSTING);
    }

    fn current(&self, generation: u64) -> bool {
        self.generation.get() == generation
    }

    pub fn binding(&self) -> Option<NativeHostingBindingResult> {
        self.state.borrow().binding.clone()
    }

    fn bound(&self) -> Option<(String, String)> {
        let state = self.state.borrow();
        let binding = state.binding.as_ref().filter(|binding| binding.state == NativeHostingBindingState::Bound)?;
        Some((binding.connection_id.clone()?, binding.provider_repository.clone()?))
    }

    fn connection(&self) -> Option<NativeHostingConnection> {
        let (connection_id, _) = self.bound()?;
        self.hosting.connection(&connection_id)
    }

    fn lookups(&self, capability: NativeHostingCapability) -> bool {
        self.connection().is_some_and(|connection| {
            connection.enabled && connection.refresh_enabled && connection.capabilities.contains(&capability)
        })
    }

    fn lookups_enabled(&self) -> bool {
        self.lookups(NativeHostingCapability::ChangeRequests)
    }

    fn head_checks_enabled(&self) -> bool {
        self.lookups(NativeHostingCapability::CommitStatuses) || self.lookups(NativeHostingCapability::CheckRuns)
    }

    fn authored_login(&self) -> Option<String> {
        self.connection().map(|connection| connection.login).filter(|login| !login.is_empty())
    }

    /// Follows the active repository and its remotes; accounts or bindings
    /// that changed resolve the binding again.
    pub fn update(self: &Rc<Self>, repository: Option<NativePathIdentity>, remotes: Vec<NativeHostingRemote>) {
        let revision = self.hosting.revision();
        {
            let state = self.state.borrow();
            if state.repository == repository && state.remotes == remotes && self.seen_revision.get() == revision {
                return;
            }
        }
        self.seen_revision.set(revision);
        {
            let mut state = self.state.borrow_mut();
            state.repository = repository;
            state.remotes = remotes;
        }
        let this = Rc::clone(self);
        rt::spawn_detached(async move { this.resolve(true).await });
    }

    /// Resolves the binding again and, when bound, loads the first page.
    pub async fn resolve(self: &Rc<Self>, refresh: bool) {
        let generation = self.generation.get() + 1;
        self.generation.set(generation);
        let previous = self.bound();
        {
            let mut state = self.state.borrow_mut();
            state.binding = None;
            state.resources = empty_resources();
            state.snapshot = None;
            state.failure = None;
            state.busy = false;
        }
        self.reset_lookups(false);
        self.changed();
        if let Some((connection_id, provider_repository)) = previous {
            rt::blocking(move || gitlama_core::api::hosting_resources_deactivate(connection_id, provider_repository)).await;
        }
        let (repository, remotes) = {
            let state = self.state.borrow();
            (state.repository.clone(), state.remotes.clone())
        };
        if !self.current(generation) || remotes.is_empty() {
            return;
        }
        let Some(repository) = repository else { return };
        let resolution = match self.hosting.binding_for(&repository) {
            Some(binding) => NativeHostingBindingResult {
                state: NativeHostingBindingState::Bound,
                remote: binding.remote,
                server: String::new(),
                connection_id: Some(binding.connection_id),
                provider_repository: Some(binding.provider_repository),
                web_url: None,
                failure: None,
            },
            None => self.hosting.resolve_binding(remotes),
        };
        if !self.current(generation) {
            return;
        }
        let bound = resolution.state == NativeHostingBindingState::Bound;
        self.state.borrow_mut().binding = Some(resolution);
        self.changed();
        self.schedule_lookups();
        if refresh && bound {
            self.refresh(false, 1).await;
        }
    }

    pub async fn refresh(self: &Rc<Self>, manual: bool, page: u32) {
        let Some((connection_id, provider_repository)) = self.bound() else { return };
        if self.state.borrow().busy {
            return;
        }
        let Some(connection) = self.hosting.connection(&connection_id) else { return };
        let generation = self.generation.get();
        {
            let mut state = self.state.borrow_mut();
            state.busy = true;
            state.failure = None;
        }
        if manual && page == 1 {
            // Visible branches ask again; what is known stays shown.
            self.reset_lookups(true);
            self.schedule_lookups();
        }
        self.changed();
        self.hosting.note_runtime_used();
        let started =
            rt::blocking(move || gitlama_core::api::hosting_resources_start(connection, provider_repository, page, manual)).await;
        if !self.current(generation) {
            if let Some(snapshot) = started.snapshot {
                let request = snapshot.request_id;
                rt::blocking(move || gitlama_core::api::hosting_resources_cancel(request)).await;
            }
            return;
        }
        match (started.snapshot, started.failure) {
            (Some(snapshot), None) => {
                let terminal = resource_terminal(snapshot.state);
                let request = snapshot.request_id;
                self.apply(snapshot, page > 1);
                if !terminal {
                    let this = Rc::clone(self);
                    rt::spawn_detached(async move { this.poll(request, page > 1, generation).await });
                }
            }
            (_, failure) => {
                self.state.borrow_mut().failure =
                    Some(resource_failure_name(failure.unwrap_or(NativeHostingResourceFailure::Unavailable)).to_owned());
            }
        }
        if self.current(generation) {
            self.state.borrow_mut().busy = false;
            self.changed();
        }
    }

    async fn poll(self: Rc<Self>, request: u64, append: bool, generation: u64) {
        loop {
            rt::sleep(Duration::from_millis(100)).await;
            if !self.current(generation) {
                return;
            }
            let polled = rt::blocking(move || gitlama_core::api::hosting_resources_poll(request)).await;
            if !self.current(generation) {
                return;
            }
            let Some(snapshot) = polled.snapshot else { return };
            let terminal = resource_terminal(snapshot.state);
            self.apply(snapshot, append);
            if terminal {
                return;
            }
        }
    }

    fn apply(&self, next: NativeHostingResourceSnapshot, append: bool) {
        {
            let mut state = self.state.borrow_mut();
            if !append {
                state.resources = next.resources.clone();
            } else if next.state == NativeHostingResourceLoadState::Ready {
                // A later page starts out showing the cached first page; only
                // its own rows are appended, once each.
                let seen: HashSet<String> = state.resources.change_requests.iter().map(|value| value.stable_id.clone()).collect();
                let pulls: Vec<_> = next.resources.change_requests.iter().filter(|value| !seen.contains(&value.stable_id)).cloned().collect();
                state.resources.change_requests.extend(pulls);
                let seen: HashSet<String> = state.resources.issues.iter().map(|value| value.stable_id.clone()).collect();
                let issues: Vec<_> = next.resources.issues.iter().filter(|value| !seen.contains(&value.stable_id)).cloned().collect();
                state.resources.issues.extend(issues);
                let key = |value: &gitlama_contract::hosting::NativeHostingRemoteReference| format!("{:?}:{}", value.kind, value.stable_id);
                let seen: HashSet<String> = state.resources.remote_references.iter().map(key).collect();
                let references: Vec<_> =
                    next.resources.remote_references.iter().filter(|value| !seen.contains(&key(value))).cloned().collect();
                state.resources.remote_references.extend(references);
            }
            state.failure = next.failure.map(|failure| resource_failure_name(failure).to_owned());
            state.snapshot = Some(next);
        }
        self.changed();
    }

    /// Open and merged pull requests from provider branch `branch`, or None
    /// while unknown.
    pub fn pull_requests_for_branch(&self, branch: &str) -> Option<Vec<NativeHostingChangeRequest>> {
        let state = self.state.borrow();
        if let Some((_, pulls)) = state.branch_pulls.iter().find(|(name, _)| name == branch) {
            return Some(pulls.clone());
        }
        let repository = state.binding.as_ref()?.provider_repository.as_ref()?;
        let listed: Vec<_> = state
            .resources
            .change_requests
            .iter()
            .filter(|pull| &pull.source_repository == repository && pull.source_branch == branch)
            .cloned()
            .collect();
        (!listed.is_empty()).then_some(listed)
    }

    /// Asks for the pull requests of provider `branches`; views may call
    /// this on every build of the rows that show them.
    pub fn request_branches(self: &Rc<Self>, branches: impl IntoIterator<Item = String>) {
        if !self.lookups_enabled() {
            return;
        }
        let mut added = false;
        {
            let mut state = self.state.borrow_mut();
            for branch in branches {
                if branch.is_empty() || state.fresh.contains(&branch) || state.in_flight.contains(&branch) || state.failed.contains(&branch) {
                    continue;
                }
                state.queued.retain(|queued| queued != &branch);
                state.queued.push(branch);
                added = true;
            }
            while state.queued.len() > LOOKUP_QUEUE_LIMIT {
                state.queued.remove(0);
            }
        }
        if added {
            self.schedule_lookups();
        }
    }

    /// Looks `branch` up again when its pull request's head is at none of
    /// the branch's refs (`refs` names their current targets).
    pub fn recheck_branch(self: &Rc<Self>, branch: &str, refs: &str) {
        if !self.lookups_enabled() {
            return;
        }
        let schedule = {
            let mut state = self.state.borrow_mut();
            if !state.fresh.contains(branch) || state.in_flight.contains(branch) {
                return;
            }
            match state.moved_refs.get(branch).cloned() {
                Some((known, attempts)) if known == refs => {
                    if attempts >= MOVED_RECHECK_LIMIT || !state.moved.insert(branch.to_owned()) {
                        return;
                    }
                    true
                }
                _ => {
                    state.moved_refs.insert(branch.to_owned(), (refs.to_owned(), 0));
                    state.moved.remove(branch);
                    state.fresh.remove(branch);
                    false
                }
            }
        };
        if schedule {
            self.schedule_moved_recheck();
        } else {
            self.request_branches([branch.to_owned()]);
        }
    }

    fn schedule_moved_recheck(self: &Rc<Self>) {
        if self.state.borrow().moved_recheck {
            return;
        }
        self.state.borrow_mut().moved_recheck = true;
        let epoch = self.epoch.get();
        let this = Rc::clone(self);
        rt::spawn_detached(async move {
            rt::sleep(MOVED_RECHECK).await;
            if this.epoch.get() != epoch {
                return;
            }
            let branches: Vec<String> = {
                let mut state = this.state.borrow_mut();
                state.moved_recheck = false;
                let moved: Vec<String> = state.moved.drain().collect();
                let branches: Vec<String> = moved.into_iter().filter(|branch| state.fresh.contains(branch)).collect();
                for branch in &branches {
                    if let Some(entry) = state.moved_refs.get_mut(branch) {
                        entry.1 += 1;
                    }
                    state.fresh.remove(branch);
                }
                branches
            };
            this.request_branches(branches);
        });
    }

    /// The CI result of commit `head`, asking for it when not looked up yet.
    pub fn request_head_checks(self: &Rc<Self>, head: &str) -> Option<NativeHostingCheckState> {
        if !self.head_checks_enabled() || head.is_empty() {
            return None;
        }
        let ask = {
            let mut state = self.state.borrow_mut();
            if state.head.as_deref() != Some(head) {
                state.head = Some(head.to_owned());
                state.head_checks = None;
                state.head_in_flight = false;
                state.head_failed = false;
                state.head_queued = true;
                true
            } else {
                false
            }
        };
        if ask {
            self.schedule_lookups();
        }
        self.state.borrow().head_checks
    }

    /// Pull requests the account authored, then the open and the merged ones
    /// of looked-up branches, newest first within each group.
    pub fn linked_pull_requests(&self) -> Vec<Linked> {
        let login = self.authored_login();
        let state = self.state.borrow();
        let mut by_number: Vec<Linked> = Vec::new();
        for pull in state.authored.iter().flatten() {
            if !by_number.iter().any(|linked| linked.pull.number == pull.number) {
                by_number.push(Linked { pull: pull.clone(), authored: true, via_branch: false });
            }
        }
        for (_, pulls) in &state.branch_pulls {
            for pull in pulls {
                if !by_number.iter().any(|linked| linked.pull.number == pull.number) {
                    let authored = login.as_deref().is_some_and(|login| pull.author == login);
                    by_number.push(Linked { pull: pull.clone(), authored, via_branch: true });
                }
            }
        }
        by_number.sort_by(|left, right| {
            right
                .authored
                .cmp(&left.authored)
                .then_with(|| {
                    let merged = |linked: &Linked| linked.pull.state == NativeHostingChangeRequestState::Merged;
                    merged(left).cmp(&merged(right))
                })
                .then_with(|| right.pull.number.cmp(&left.pull.number))
        });
        by_number
    }

    pub fn looking_up(&self) -> bool {
        let state = self.state.borrow();
        state.lookup_running
            || !state.queued.is_empty()
            || state.head_queued
            || (self.lookups_enabled() && !state.authored_requested && self.authored_login().is_some())
    }

    fn reset_lookups(&self, keep_known: bool) {
        self.epoch.set(self.epoch.get() + 1);
        let mut state = self.state.borrow_mut();
        state.debounce = false;
        state.pending_recheck = false;
        state.moved_recheck = false;
        state.moved.clear();
        state.lookup_running = false;
        state.moved_refs.clear();
        if !keep_known {
            state.branch_pulls.clear();
            state.authored = None;
            state.head = None;
            state.head_checks = None;
        }
        state.head_queued = state.head.is_some();
        state.head_in_flight = false;
        state.head_failed = false;
        state.fresh.clear();
        state.queued.clear();
        state.in_flight.clear();
        state.failed.clear();
        state.authored_requested = false;
        state.authored_fresh = false;
        state.lookup_failure = None;
    }

    // Rows report their branches while they build; a short pause gathers one
    // scroll's worth into a batch.
    fn schedule_lookups(self: &Rc<Self>) {
        if self.state.borrow().debounce {
            return;
        }
        self.state.borrow_mut().debounce = true;
        let epoch = self.epoch.get();
        let this = Rc::clone(self);
        rt::spawn_detached(async move {
            rt::sleep(Duration::from_millis(250)).await;
            if this.epoch.get() != epoch {
                return;
            }
            this.state.borrow_mut().debounce = false;
            this.run_lookup().await;
        });
    }

    async fn run_lookup(self: &Rc<Self>) {
        if self.state.borrow().lookup_running {
            return;
        }
        let lookups = self.lookups_enabled();
        let login = self.authored_login();
        let Some((connection_id, provider_repository)) = self.bound() else { return };
        let Some(connection) = self.hosting.connection(&connection_id) else { return };
        let (batch, head, authored) = {
            let mut state = self.state.borrow_mut();
            let head = if state.head_queued && self.head_checks_enabled() { state.head.clone() } else { None };
            let authored = lookups && !state.authored_requested && login.is_some();
            let batch: Vec<String> = if lookups { state.queued.iter().take(LOOKUP_BATCH).cloned().collect() } else { Vec::new() };
            if batch.is_empty() && !authored && head.is_none() {
                return;
            }
            state.queued.retain(|branch| !batch.contains(branch));
            state.in_flight.extend(batch.iter().cloned());
            if lookups {
                state.authored_requested = true;
            }
            if head.is_some() {
                state.head_queued = false;
                state.head_in_flight = true;
            }
            state.lookup_running = true;
            (batch, head, authored)
        };
        let generation = self.generation.get();
        let epoch = self.epoch.get();
        let current = |this: &Self| this.current(generation) && this.epoch.get() == epoch;
        self.hosting.note_runtime_used();
        let (heads, branches, authored_by) = (head.into_iter().collect::<Vec<_>>(), batch.clone(), if authored { login } else { None });
        let started = rt::blocking(move || {
            gitlama_core::api::hosting_pull_request_lookup_start(connection, provider_repository, heads, branches, authored_by)
        })
        .await;
        let Some(mut snapshot) = started.snapshot.filter(|_| started.failure.is_none()) else {
            if current(self) {
                self.finish_lookup(&batch, Some(started.failure.unwrap_or(NativeHostingResourceFailure::Unavailable)));
            }
            return;
        };
        loop {
            if !current(self) {
                let request = snapshot.request_id;
                rt::blocking(move || gitlama_core::api::hosting_pull_request_lookup_cancel(request)).await;
                return;
            }
            let terminal = resource_terminal(snapshot.state);
            self.apply_lookup(&snapshot);
            if terminal {
                let failure = (snapshot.state == NativeHostingResourceLoadState::Failed)
                    .then(|| snapshot.failure.unwrap_or(NativeHostingResourceFailure::Unavailable));
                self.finish_lookup(&batch, failure);
                return;
            }
            rt::sleep(Duration::from_millis(150)).await;
            let request = snapshot.request_id;
            let polled = rt::blocking(move || gitlama_core::api::hosting_pull_request_lookup_poll(request)).await;
            match polled.snapshot {
                Some(next) => snapshot = next,
                None => {
                    if current(self) {
                        self.finish_lookup(&batch, Some(NativeHostingResourceFailure::Unavailable));
                    }
                    return;
                }
            }
        }
    }

    fn apply_lookup(&self, next: &gitlama_contract::hosting_runtime::NativeHostingPullRequestLookupSnapshot) {
        let mut changed = false;
        {
            let mut state = self.state.borrow_mut();
            if state.head_in_flight
                && let Some(checks) = next.heads.iter().find(|head| Some(&head.head) == state.head.as_ref()).map(|head| head.checks)
            {
                state.head_in_flight = false;
                changed |= Some(checks) != state.head_checks;
                state.head_checks = Some(checks);
            }
            for branch in &next.branches {
                if !state.fresh.insert(branch.branch.clone()) {
                    continue;
                }
                let previous = state.branch_pulls.iter().position(|(name, _)| name == &branch.branch).map(|index| state.branch_pulls.remove(index).1);
                changed |= !same_pulls(previous.as_ref(), Some(&branch.change_requests));
                state.branch_pulls.push((branch.branch.clone(), branch.change_requests.clone()));
                state.in_flight.remove(&branch.branch);
            }
            if let Some(authored) = &next.authored
                && !state.authored_fresh
            {
                state.authored_fresh = true;
                changed |= !same_pulls(state.authored.as_ref(), Some(authored));
                state.authored = Some(authored.clone());
            }
        }
        if changed {
            self.changed();
        }
    }

    // Branches a lookup left unanswered are not asked again until the next
    // manual refresh, so a failing provider is not called for every row.
    fn finish_lookup(self: &Rc<Self>, batch: &[String], failure: Option<NativeHostingResourceFailure>) {
        let again = {
            let mut state = self.state.borrow_mut();
            state.lookup_running = false;
            state.lookup_failure = failure;
            for branch in batch {
                if state.in_flight.remove(branch) {
                    state.failed.insert(branch.clone());
                }
            }
            if state.head_in_flight {
                state.head_in_flight = false;
                state.head_failed = true;
            }
            !state.queued.is_empty() || state.head_queued
        };
        self.changed();
        if again {
            self.schedule_lookups();
        }
        self.schedule_pending_recheck();
    }

    // Checks still running and mergeability being computed settle on their
    // own; their branches are asked again later.
    fn schedule_pending_recheck(self: &Rc<Self>) {
        {
            let state = self.state.borrow();
            if state.pending_recheck {
                return;
            }
            let head_pending = state.head_checks == Some(NativeHostingCheckState::Pending)
                && !state.head_queued
                && !state.head_in_flight
                && !state.head_failed;
            let any = state.fresh.iter().any(|branch| unsettled(state.branch_pulls.iter().find(|(name, _)| name == branch).map(|(_, pulls)| pulls)));
            if !head_pending && !any {
                return;
            }
        }
        self.state.borrow_mut().pending_recheck = true;
        let epoch = self.epoch.get();
        let this = Rc::clone(self);
        rt::spawn_detached(async move {
            rt::sleep(PENDING_RECHECK).await;
            if this.epoch.get() != epoch {
                return;
            }
            let unsettled_branches: Vec<String> = {
                let mut state = this.state.borrow_mut();
                state.pending_recheck = false;
                let head_pending = state.head_checks == Some(NativeHostingCheckState::Pending)
                    && !state.head_queued
                    && !state.head_in_flight
                    && !state.head_failed;
                if head_pending {
                    state.head_queued = true;
                }
                let branches: Vec<String> = state
                    .fresh
                    .iter()
                    .filter(|branch| unsettled(state.branch_pulls.iter().find(|(name, _)| name == *branch).map(|(_, pulls)| pulls)))
                    .cloned()
                    .collect();
                for branch in &branches {
                    state.fresh.remove(branch);
                }
                branches
            };
            this.schedule_lookups();
            this.request_branches(unsettled_branches);
        });
    }

    /// The bound repository's resources and state for the presentation.
    pub fn state_value(&self) -> serde_json::Value {
        use serde_json::json;
        let state = self.state.borrow();
        let binding = state.binding.as_ref().map(|binding| {
            json!({
                "state": match binding.state {
                    NativeHostingBindingState::Unmatched => "unmatched",
                    NativeHostingBindingState::Ambiguous => "ambiguous",
                    NativeHostingBindingState::Bound => "bound",
                },
                "remote": String::from_utf8_lossy(&binding.remote),
                "connectionId": binding.connection_id,
                "providerRepository": binding.provider_repository,
                "webUrl": binding.web_url,
            })
        });
        let connection = self.connection();
        json!({
            "binding": binding,
            "busy": state.busy,
            "failure": state.failure,
            "stale": state.snapshot.as_ref().is_some_and(|snapshot| snapshot.stale),
            "loading": state.snapshot.as_ref().is_some_and(|snapshot| snapshot.state == NativeHostingResourceLoadState::Loading),
            "hasMore": state.snapshot.as_ref().is_some_and(|snapshot| snapshot.has_more),
            "page": state.snapshot.as_ref().map_or(1, |snapshot| snapshot.page),
            "capabilities": connection.map(|connection| connection.capabilities.iter().map(|capability| capability_name(*capability)).collect::<Vec<_>>()).unwrap_or_default(),
            "changeRequests": state.resources.change_requests.iter().map(pull_value).collect::<Vec<_>>(),
            "issues": state.resources.issues.iter().map(|issue| json!({
                "number": issue.number,
                "title": issue.title,
                "open": issue.state == gitlama_contract::hosting::NativeHostingIssueState::Open,
                "author": issue.author,
                "labels": issue.labels,
                "webUrl": issue.web_url,
            })).collect::<Vec<_>>(),
            "lookingUp": state.lookup_running || !state.queued.is_empty(),
            "lookupFailure": state.lookup_failure.map(resource_failure_name),
        })
    }
}

pub fn check_state_name(state: NativeHostingCheckState) -> &'static str {
    match state {
        NativeHostingCheckState::Pending => "pending",
        NativeHostingCheckState::Passing => "passing",
        NativeHostingCheckState::Failing => "failing",
        NativeHostingCheckState::Canceled => "canceled",
        NativeHostingCheckState::Skipped => "skipped",
        NativeHostingCheckState::Unknown => "unknown",
    }
}

pub fn pull_value(pull: &NativeHostingChangeRequest) -> serde_json::Value {
    serde_json::json!({
        "stableId": pull.stable_id,
        "number": pull.number,
        "title": pull.title,
        "author": pull.author,
        "state": match pull.state {
            NativeHostingChangeRequestState::Open => "open",
            NativeHostingChangeRequestState::Closed => "closed",
            NativeHostingChangeRequestState::Merged => "merged",
        },
        "draft": pull.draft,
        "sourceRepository": pull.source_repository,
        "sourceBranch": pull.source_branch,
        "targetBranch": pull.target_branch,
        "headSha": pull.head_sha,
        "webUrl": pull.web_url,
        "review": match pull.review_summary {
            gitlama_contract::hosting::NativeHostingReviewSummary::None => "none",
            gitlama_contract::hosting::NativeHostingReviewSummary::Pending => "pending",
            gitlama_contract::hosting::NativeHostingReviewSummary::Approved => "approved",
            gitlama_contract::hosting::NativeHostingReviewSummary::ChangesRequested => "changesRequested",
            gitlama_contract::hosting::NativeHostingReviewSummary::Unknown => "unknown",
        },
        "mergeability": match pull.mergeability {
            NativeHostingMergeability::Mergeable => "mergeable",
            NativeHostingMergeability::Conflicting => "conflicting",
            NativeHostingMergeability::Checking => "checking",
            NativeHostingMergeability::Unknown => "unknown",
        },
        "checks": check_state_name(pull.checks.state),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn storage_names_round_trip() {
        for name in ["github", "gitlab", "gitlabSelfManaged", "forgejo", "codeberg", "gitHubEnterprise"] {
            assert_eq!(preset_name(parse_preset(name).unwrap()), name);
        }
        for name in ["oauth", "gitHubCli", "gitLabCli"] {
            assert_eq!(authentication_name(parse_authentication(name).unwrap()), name);
        }
        for name in ["changeRequests", "changeRequestCheckout", "changeRequestReview", "commitStatuses", "checkRuns", "issues", "remoteReferences"] {
            assert_eq!(capability_name(parse_capability(name).unwrap()), name);
        }
    }

    #[test]
    fn only_safe_links_open() {
        assert!(openable_url("https://github.com/team/project"));
        assert!(openable_url("http://localhost:8080/callback"));
        assert!(!openable_url("http://github.com/"));
        assert!(!openable_url("https://user@github.com/"));
        assert!(!openable_url("file:///etc/passwd"));
        assert!(!openable_url("https:///nohost"));
    }
}
