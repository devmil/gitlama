//! Isolated hosting network scheduler and OAuth session ownership.
pub use gitlama_contract::hosting_runtime::*;

use crate::hosting::{
    store_credential, to_shared, CredentialEnvelope, CredentialLoadError,
    NativeHostingAuthentication, NativeHostingChangeRequest, NativeHostingChangeRequestState,
    NativeHostingCheckState, NativeHostingCheckSummary, NativeHostingConnection,
    NativeHostingIssue, NativeHostingIssueState, NativeHostingMergeability,
    NativeHostingRemoteReference, NativeHostingRemoteReferenceKind, NativeHostingResources,
    NativeHostingReviewSummary,
};
use devmil_git::cancellation::Cancellation;
use devmil_git::hosting::http::curl_get_command;
use devmil_git::hosting::model::{
    CiStatus, HostingCapability, HostingConnection, HostingCredential, HostingError,
    HostingPullRequest, HostingRepositoryId, IssueState, Mergeability, PullRequestState,
};
use devmil_git::hosting::oauth::{
    base64_url, device_authorization_poll_form, device_authorization_request_form,
    device_authorization_url, oauth_authorization_code_form, oauth_authorize_url,
    oauth_refresh_token_form, oauth_token_url, parse_device_authorization,
    parse_device_authorization_poll, parse_oauth_token_response, validate_device_verification_uri,
    DeviceAuthorizationPoll, OAuthTokenResponse,
};
use devmil_git::hosting::providers::{
    provider_plugin, HostingHttpResponse, HostingProviderPlugin, HostingProviderRequester,
    OAuthIdentityField, OAuthLoginFlow,
};
use devmil_git::process::{ActivityGitRunner, GitProcessCommand};
use devmil_git::types::ObjectId;
use gitlama_application::activity::allocate_activity_id;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet, VecDeque};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use zeroize::Zeroize;

mod cache;
mod oauth;
mod resources;
mod scheduler;
mod transport;
pub use cache::{HostingCache, HostingCacheClass, HostingCacheSnapshot};
pub(crate) use oauth::refresh_credential;
use oauth::*;
use resources::*;
use scheduler::*;
use transport::*;

const GLOBAL_REQUEST_LIMIT: usize = 2;
const LOOPBACK_CALLBACK: &str = "http://127.0.0.1:49351/oauth/callback";
const LOOPBACK_ADDRESS: &str = "127.0.0.1:49351";
const OAUTH_SESSION_LIMIT: usize = 32;
/// Branches resolved by one lookup request; callers batch larger sets.
pub const PULL_REQUEST_LOOKUP_BRANCH_LIMIT: usize = 20;
/// Commits whose CI result one lookup request reads.
pub const PULL_REQUEST_LOOKUP_HEAD_LIMIT: usize = 4;
/// Finished sessions kept for a late poll before the oldest are dropped.
const FINISHED_SESSION_LIMIT: usize = 32;
const OAUTH_TIMEOUT: Duration = Duration::from_secs(15 * 60);
pub const HOSTING_PAGE_CAPACITY: usize = 50;
pub const CHANGE_REQUEST_FRESHNESS: Duration = Duration::from_secs(60);
pub const ISSUE_FRESHNESS: Duration = Duration::from_secs(5 * 60);

/// The snapshot of a sign-in that has not started yet.
fn queued_oauth_snapshot(request_id: u64) -> NativeHostingOAuthSnapshot {
    NativeHostingOAuthSnapshot {
        request_id,
        state: NativeHostingOAuthState::Queued,
        browser_url: None,
        user_code: None,
        authenticated_login: None,
        failure: None,
    }
}

struct OAuthSession {
    snapshot: NativeHostingOAuthSnapshot,
    cancellation: Arc<AtomicBool>,
}

struct ResourceSession {
    connection_id: String,
    repository_id: String,
    snapshot: NativeHostingResourceSnapshot,
    cancellation: Arc<AtomicBool>,
}

struct LookupSession {
    connection_id: String,
    repository_id: String,
    snapshot: NativeHostingPullRequestLookupSnapshot,
    cancellation: Arc<AtomicBool>,
}

struct HostingRuntime {
    scheduler: BoundedScheduler,
    sessions: Arc<Mutex<HashMap<u64, OAuthSession>>>,
    resource_sessions: Arc<Mutex<HashMap<u64, ResourceSession>>>,
    lookup_sessions: Arc<Mutex<HashMap<u64, LookupSession>>>,
    cache: Arc<HostingCache>,
}

impl HostingRuntime {
    fn new() -> Self {
        Self {
            scheduler: BoundedScheduler::new(),
            sessions: Arc::new(Mutex::new(HashMap::new())),
            resource_sessions: Arc::new(Mutex::new(HashMap::new())),
            lookup_sessions: Arc::new(Mutex::new(HashMap::new())),
            cache: Arc::new(HostingCache::default()),
        }
    }

    fn stop(self) {
        for session in self.sessions.lock().expect("OAuth sessions lock").values() {
            session.cancellation.store(true, Ordering::Release);
        }
        for session in self
            .resource_sessions
            .lock()
            .expect("hosting resource sessions lock")
            .values()
        {
            session.cancellation.store(true, Ordering::Release);
        }
        for session in self
            .lookup_sessions
            .lock()
            .expect("hosting lookup sessions lock")
            .values()
        {
            session.cancellation.store(true, Ordering::Release);
        }
        self.cache.shutdown();
        self.scheduler.stop();
    }
}

static NEXT_OAUTH_REQUEST: AtomicU64 = AtomicU64::new(1);
static NEXT_RESOURCE_REQUEST: AtomicU64 = AtomicU64::new(1);
static NEXT_LOOKUP_REQUEST: AtomicU64 = AtomicU64::new(1);
static HOSTING_RUNTIME: OnceLock<Mutex<Option<HostingRuntime>>> = OnceLock::new();

/// Loads a connection's credential, renewing an expiring OAuth token over the network.
pub(crate) fn load_credential(
    connection: &NativeHostingConnection,
    cancellation: &dyn Cancellation,
) -> Result<CredentialEnvelope, CredentialLoadError> {
    crate::hosting::load_credential(connection, cancellation, |connection, envelope| {
        refresh_credential(connection, envelope, cancellation)
    })
}

fn runtime() -> &'static Mutex<Option<HostingRuntime>> {
    HOSTING_RUNTIME.get_or_init(|| Mutex::new(Some(HostingRuntime::new())))
}

#[must_use]
pub fn oauth_start(connection: NativeHostingConnection) -> NativeHostingOAuthStartResult {
    let Some(connection) = crate::hosting::validate_native_connection(connection).connection else {
        return start_failure(NativeHostingOAuthFailure::InvalidConnection);
    };
    if connection.authentication != NativeHostingAuthentication::OAuth {
        return cli_authorization(connection);
    }
    if connection.oauth_client_id.is_empty() || connection.oauth_client_id.len() > 512 {
        return start_failure(NativeHostingOAuthFailure::InvalidConnection);
    }
    let request_id = NEXT_OAUTH_REQUEST.fetch_add(1, Ordering::Relaxed);
    let cancellation = Arc::new(AtomicBool::new(false));
    let snapshot = queued_oauth_snapshot(request_id);
    let mut runtime_guard = runtime().lock().expect("hosting runtime lock");
    if runtime_guard.is_none() {
        *runtime_guard = Some(HostingRuntime::new());
    }
    let runtime = runtime_guard.as_ref().expect("hosting runtime exists");
    {
        let mut sessions = runtime.sessions.lock().expect("OAuth sessions lock");
        sessions.retain(|_, session| {
            matches!(
                session.snapshot.state,
                NativeHostingOAuthState::Queued
                    | NativeHostingOAuthState::WaitingForBrowser
                    | NativeHostingOAuthState::WaitingForDevice
                    | NativeHostingOAuthState::Exchanging
            )
        });
        if sessions.len() >= OAUTH_SESSION_LIMIT {
            return start_failure(NativeHostingOAuthFailure::Busy);
        }
        sessions.insert(
            request_id,
            OAuthSession {
                snapshot: snapshot.clone(),
                cancellation: Arc::clone(&cancellation),
            },
        );
    }
    let sessions = Arc::clone(&runtime.sessions);
    let task = ScheduledTask {
        connection_id: connection.id.clone(),
        cancellation: Arc::clone(&cancellation),
        operation: Box::new(move |cancellation| {
            run_oauth(request_id, connection, cancellation, &sessions);
        }),
    };
    if !runtime.scheduler.schedule(task) {
        runtime
            .sessions
            .lock()
            .expect("OAuth sessions lock")
            .remove(&request_id);
        return start_failure(NativeHostingOAuthFailure::Unavailable);
    }
    NativeHostingOAuthStartResult {
        snapshot: Some(snapshot),
        failure: None,
    }
}

fn cli_authorization(connection: NativeHostingConnection) -> NativeHostingOAuthStartResult {
    let request_id = NEXT_OAUTH_REQUEST.fetch_add(1, Ordering::Relaxed);
    let envelope = match load_credential(&connection, &AtomicBool::new(false)) {
        Ok(envelope) => envelope,
        Err(_) => return start_failure(NativeHostingOAuthFailure::Unauthorized),
    };
    let credential = match HostingCredential::new(envelope.access_token().to_vec()) {
        Ok(credential) => credential,
        Err(_) => return start_failure(NativeHostingOAuthFailure::Unavailable),
    };
    let shared = to_shared(&connection);
    let cancellation = AtomicBool::new(false);
    let requester = CurlTransport::first_page();
    let response = match requester.request(&shared, "/user".into(), &credential, &cancellation) {
        Ok(response) => response,
        Err(error) => return start_failure(map_hosting_error(error).into_native()),
    };
    if let Err(error) = require_success(response.status) {
        return start_failure(error.into_native());
    }
    let Some(login) = identity_login(shared.provider(), &response.body) else {
        return start_failure(NativeHostingOAuthFailure::MalformedResponse);
    };
    let mut snapshot = queued_oauth_snapshot(request_id);
    snapshot.state = NativeHostingOAuthState::Succeeded;
    snapshot.authenticated_login = Some(login);
    NativeHostingOAuthStartResult {
        snapshot: Some(snapshot),
        failure: None,
    }
}

#[must_use]
pub fn oauth_poll(request_id: u64) -> NativeHostingOAuthPollResult {
    let runtime_guard = runtime().lock().expect("hosting runtime lock");
    let snapshot = runtime_guard.as_ref().and_then(|runtime| {
        runtime
            .sessions
            .lock()
            .expect("OAuth sessions lock")
            .get(&request_id)
            .map(|session| session.snapshot.clone())
    });
    NativeHostingOAuthPollResult { snapshot }
}

#[must_use]
pub fn oauth_cancel(request_id: u64) -> bool {
    let runtime_guard = runtime().lock().expect("hosting runtime lock");
    let Some(runtime) = runtime_guard.as_ref() else {
        return false;
    };
    let sessions = runtime.sessions.lock().expect("OAuth sessions lock");
    let Some(session) = sessions.get(&request_id) else {
        return false;
    };
    session.cancellation.store(true, Ordering::Release);
    true
}

#[must_use]
pub fn resources_start(
    connection: NativeHostingConnection,
    repository_id: String,
    page: u32,
    manual: bool,
) -> NativeHostingResourceStartResult {
    let Some(connection) = crate::hosting::validate_native_connection(connection).connection else {
        return resource_start_failure(NativeHostingResourceFailure::InvalidRequest);
    };
    if !connection.enabled || (!manual && !connection.refresh_enabled) {
        return resource_start_failure(NativeHostingResourceFailure::IntegrationDisabled);
    }
    if !(1..=1000).contains(&page) || HostingRepositoryId::new(repository_id.clone()).is_err() {
        return resource_start_failure(NativeHostingResourceFailure::InvalidRequest);
    }
    let request_id = NEXT_RESOURCE_REQUEST.fetch_add(1, Ordering::Relaxed);
    let cancellation = Arc::new(AtomicBool::new(false));
    let mut runtime_guard = runtime().lock().expect("hosting runtime lock");
    if runtime_guard.is_none() {
        *runtime_guard = Some(HostingRuntime::new());
    }
    let runtime = runtime_guard.as_ref().expect("hosting runtime exists");
    runtime
        .cache
        .activate(connection.id.clone(), repository_id.clone());
    let cached = cached_resources(&runtime.cache, &connection.id, &repository_id);
    let snapshot = NativeHostingResourceSnapshot {
        request_id,
        state: NativeHostingResourceLoadState::Loading,
        page,
        resources: cached
            .as_ref()
            .map_or_else(crate::hosting::empty_resources, |value| value.0.clone()),
        stale: cached.as_ref().is_some_and(|value| value.1),
        has_more: false,
        failure: None,
    };
    let (change_generation, issue_generation) = if page == 1 {
        let change_generation = runtime.cache.begin_refresh_with(
            &connection.id,
            &repository_id,
            HostingCacheClass::ChangeRequests,
            Arc::clone(&cancellation),
        );
        let issue_generation = runtime.cache.begin_refresh_with(
            &connection.id,
            &repository_id,
            HostingCacheClass::Issues,
            Arc::clone(&cancellation),
        );
        let (Some(change_generation), Some(issue_generation)) =
            (change_generation, issue_generation)
        else {
            return resource_start_failure(NativeHostingResourceFailure::Unavailable);
        };
        (change_generation, issue_generation)
    } else {
        (0, 0)
    };
    {
        let mut sessions = runtime
            .resource_sessions
            .lock()
            .expect("hosting resource sessions lock");
        prune_finished(&mut sessions, |session| session.snapshot.state);
        sessions.insert(
            request_id,
            ResourceSession {
                connection_id: connection.id.clone(),
                repository_id: repository_id.clone(),
                snapshot: snapshot.clone(),
                cancellation: Arc::clone(&cancellation),
            },
        );
    }
    let sessions = Arc::clone(&runtime.resource_sessions);
    let cache = Arc::clone(&runtime.cache);
    let task = ScheduledTask {
        connection_id: connection.id.clone(),
        cancellation: Arc::clone(&cancellation),
        operation: Box::new(move |cancellation| {
            run_resource_load(
                request_id,
                connection,
                repository_id,
                page,
                change_generation,
                issue_generation,
                cancellation,
                &cache,
                &sessions,
            );
        }),
    };
    if !runtime.scheduler.schedule(task) {
        runtime
            .resource_sessions
            .lock()
            .expect("hosting resource sessions lock")
            .remove(&request_id);
        return resource_start_failure(NativeHostingResourceFailure::Unavailable);
    }
    NativeHostingResourceStartResult {
        snapshot: Some(snapshot),
        failure: None,
    }
}

/// Returns the request's progress. A finished request is handed out once and then forgotten.
#[must_use]
pub fn resources_poll(request_id: u64) -> NativeHostingResourcePollResult {
    let runtime_guard = runtime().lock().expect("hosting runtime lock");
    let snapshot = runtime_guard.as_ref().and_then(|runtime| {
        let mut sessions = runtime
            .resource_sessions
            .lock()
            .expect("hosting resource sessions lock");
        let snapshot = sessions.get(&request_id)?.snapshot.clone();
        if is_finished(snapshot.state) {
            sessions.remove(&request_id);
        }
        Some(snapshot)
    });
    NativeHostingResourcePollResult { snapshot }
}

const fn is_finished(state: NativeHostingResourceLoadState) -> bool {
    matches!(
        state,
        NativeHostingResourceLoadState::Ready
            | NativeHostingResourceLoadState::Failed
            | NativeHostingResourceLoadState::Canceled
    )
}

/// Drops the oldest finished sessions beyond [`FINISHED_SESSION_LIMIT`]. Finished sessions
/// otherwise wait for their poll, so a result that completes between two polls is not lost.
fn prune_finished<T>(
    sessions: &mut HashMap<u64, T>,
    state: impl Fn(&T) -> NativeHostingResourceLoadState,
) {
    let mut finished = sessions
        .iter()
        .filter(|(_, session)| is_finished(state(session)))
        .map(|(id, _)| *id)
        .collect::<Vec<_>>();
    if finished.len() <= FINISHED_SESSION_LIMIT {
        return;
    }
    finished.sort_unstable();
    for id in &finished[..finished.len() - FINISHED_SESSION_LIMIT] {
        sessions.remove(id);
    }
}

/// Starts an on-demand lookup of the CI result of up to [`PULL_REQUEST_LOOKUP_HEAD_LIMIT`]
/// commits, open pull requests for up to [`PULL_REQUEST_LOOKUP_BRANCH_LIMIT`] branches and,
/// when `authored_by` is set, the open pull requests that account authored. It runs on the connection's scheduler slot behind any list
/// refresh and does not touch the list cache.
#[must_use]
pub fn pull_request_lookup_start(
    connection: NativeHostingConnection,
    repository_id: String,
    heads: Vec<String>,
    branches: Vec<String>,
    authored_by: Option<String>,
) -> NativeHostingPullRequestLookupStartResult {
    let Some(connection) = crate::hosting::validate_native_connection(connection).connection else {
        return lookup_start_failure(NativeHostingResourceFailure::InvalidRequest);
    };
    if !connection.enabled {
        return lookup_start_failure(NativeHostingResourceFailure::IntegrationDisabled);
    }
    if HostingRepositoryId::new(repository_id.clone()).is_err()
        || branches.len() > PULL_REQUEST_LOOKUP_BRANCH_LIMIT
        || heads.len() > PULL_REQUEST_LOOKUP_HEAD_LIMIT
        || heads
            .iter()
            .any(|head| ObjectId::parse(head.clone()).is_err())
        || (heads.is_empty() && branches.is_empty() && authored_by.is_none())
    {
        return lookup_start_failure(NativeHostingResourceFailure::InvalidRequest);
    }
    let request_id = NEXT_LOOKUP_REQUEST.fetch_add(1, Ordering::Relaxed);
    let cancellation = Arc::new(AtomicBool::new(false));
    let snapshot = NativeHostingPullRequestLookupSnapshot {
        request_id,
        state: NativeHostingResourceLoadState::Loading,
        heads: Vec::new(),
        branches: Vec::new(),
        authored: None,
        failure: None,
    };
    let mut runtime_guard = runtime().lock().expect("hosting runtime lock");
    if runtime_guard.is_none() {
        *runtime_guard = Some(HostingRuntime::new());
    }
    let runtime = runtime_guard.as_ref().expect("hosting runtime exists");
    {
        let mut sessions = runtime
            .lookup_sessions
            .lock()
            .expect("hosting lookup sessions lock");
        prune_finished(&mut sessions, |session| session.snapshot.state);
        sessions.insert(
            request_id,
            LookupSession {
                connection_id: connection.id.clone(),
                repository_id: repository_id.clone(),
                snapshot: snapshot.clone(),
                cancellation: Arc::clone(&cancellation),
            },
        );
    }
    let sessions = Arc::clone(&runtime.lookup_sessions);
    let task = ScheduledTask {
        connection_id: connection.id.clone(),
        cancellation: Arc::clone(&cancellation),
        operation: Box::new(move |cancellation| {
            run_pull_request_lookup(
                request_id,
                &connection,
                &repository_id,
                &heads,
                &branches,
                authored_by.as_deref(),
                &cancellation,
                &sessions,
            );
        }),
    };
    if !runtime.scheduler.schedule(task) {
        runtime
            .lookup_sessions
            .lock()
            .expect("hosting lookup sessions lock")
            .remove(&request_id);
        return lookup_start_failure(NativeHostingResourceFailure::Unavailable);
    }
    NativeHostingPullRequestLookupStartResult {
        snapshot: Some(snapshot),
        failure: None,
    }
}

/// Returns the lookup's progress. A finished lookup is handed out once and then forgotten.
#[must_use]
pub fn pull_request_lookup_poll(request_id: u64) -> NativeHostingPullRequestLookupPollResult {
    let runtime_guard = runtime().lock().expect("hosting runtime lock");
    let snapshot = runtime_guard.as_ref().and_then(|runtime| {
        let mut sessions = runtime
            .lookup_sessions
            .lock()
            .expect("hosting lookup sessions lock");
        let snapshot = sessions.get(&request_id)?.snapshot.clone();
        if is_finished(snapshot.state) {
            sessions.remove(&request_id);
        }
        Some(snapshot)
    });
    NativeHostingPullRequestLookupPollResult { snapshot }
}

#[must_use]
pub fn pull_request_lookup_cancel(request_id: u64) -> bool {
    let runtime_guard = runtime().lock().expect("hosting runtime lock");
    let Some(runtime) = runtime_guard.as_ref() else {
        return false;
    };
    let sessions = runtime
        .lookup_sessions
        .lock()
        .expect("hosting lookup sessions lock");
    let Some(session) = sessions.get(&request_id) else {
        return false;
    };
    session.cancellation.store(true, Ordering::Release);
    true
}

fn lookup_start_failure(
    failure: NativeHostingResourceFailure,
) -> NativeHostingPullRequestLookupStartResult {
    NativeHostingPullRequestLookupStartResult {
        snapshot: None,
        failure: Some(failure),
    }
}

#[allow(clippy::too_many_arguments)]
fn run_pull_request_lookup(
    request_id: u64,
    connection: &NativeHostingConnection,
    repository_id: &str,
    heads: &[String],
    branches: &[String],
    authored_by: Option<&str>,
    cancellation: &AtomicBool,
    sessions: &Mutex<HashMap<u64, LookupSession>>,
) {
    let update = |mutate: &mut dyn FnMut(&mut NativeHostingPullRequestLookupSnapshot)| {
        if let Some(session) = sessions
            .lock()
            .expect("hosting lookup sessions lock")
            .get_mut(&request_id)
        {
            mutate(&mut session.snapshot);
        }
    };
    let result = load_credential(connection, cancellation)
        .map_err(map_credential_failure)
        .and_then(|envelope| {
            let credential = HostingCredential::new(envelope.access_token().to_vec())
                .map_err(|_| NativeHostingResourceFailure::CredentialUnreadable)?;
            lookup_pull_requests_with(
                &CurlTransport::first_page(),
                &to_shared(connection),
                repository_id,
                heads,
                branches,
                authored_by,
                &credential,
                cancellation,
                &mut |progress| match progress {
                    LookupProgress::Head(head) => {
                        update(&mut |snapshot| snapshot.heads.push(head.clone()));
                    }
                    LookupProgress::Branch(branch) => {
                        update(&mut |snapshot| snapshot.branches.push(branch.clone()));
                    }
                    LookupProgress::Authored(authored) => {
                        update(&mut |snapshot| snapshot.authored = Some(authored.clone()));
                    }
                },
            )
        });
    update(&mut |snapshot| {
        if cancellation.load(Ordering::Acquire) {
            snapshot.state = NativeHostingResourceLoadState::Canceled;
            snapshot.failure = None;
            return;
        }
        match result {
            Ok(()) => snapshot.state = NativeHostingResourceLoadState::Ready,
            Err(failure) => {
                snapshot.state = NativeHostingResourceLoadState::Failed;
                snapshot.failure = Some(failure);
            }
        }
    });
}

enum LookupProgress {
    Head(NativeHostingHeadChecks),
    Branch(NativeHostingBranchPullRequests),
    Authored(Vec<NativeHostingChangeRequest>),
}

/// Resolves the CI result of the heads first, then the authored query, then the branches,
/// reporting each result as it lands so a failure later in the batch keeps what already
/// resolved. A head's CI result is optional and stays unknown when it cannot be read. Branch
/// results include merged pull requests. Open pull requests carry the CI result of their head
/// and their mergeability where the provider reports them.
#[allow(clippy::too_many_arguments)]
fn lookup_pull_requests_with(
    requester: &dyn HostingProviderRequester,
    connection: &HostingConnection,
    repository_id: &str,
    heads: &[String],
    branches: &[String],
    authored_by: Option<&str>,
    credential: &HostingCredential,
    cancellation: &dyn Cancellation,
    progress: &mut dyn FnMut(LookupProgress),
) -> Result<(), NativeHostingResourceFailure> {
    let repository = HostingRepositoryId::new(repository_id.to_owned())
        .map_err(|_| NativeHostingResourceFailure::InvalidRequest)?;
    let plugin = provider_plugin(connection.provider());
    for head in heads {
        let id = ObjectId::parse(head.clone())
            .map_err(|_| NativeHostingResourceFailure::InvalidRequest)?;
        let checks = plugin
            .commit_ci_status(
                requester,
                connection,
                &repository,
                &id,
                credential,
                cancellation,
            )
            .map_err(map_resource_error)?;
        progress(LookupProgress::Head(NativeHostingHeadChecks {
            head: head.clone(),
            checks: map_ci_state(checks),
        }));
    }
    if branches.is_empty() && authored_by.is_none() {
        return Ok(());
    }
    if !connection
        .capabilities
        .supports(HostingCapability::ChangeRequests)
    {
        return Err(NativeHostingResourceFailure::IntegrationDisabled);
    }
    if let Some(login) = authored_by {
        let authored = plugin
            .authored_pull_requests(
                requester,
                connection,
                &repository,
                login,
                credential,
                cancellation,
            )
            .map_err(map_resource_error)?;
        progress(LookupProgress::Authored(
            with_status(
                plugin,
                requester,
                connection,
                &repository,
                authored,
                credential,
                cancellation,
            )
            .into_iter()
            .map(|pull| map_pull_request(repository_id, pull))
            .collect(),
        ));
    }
    plugin
        .branches_pull_requests(
            requester,
            connection,
            &repository,
            branches,
            credential,
            cancellation,
            &mut |branch, pulls| {
                progress(LookupProgress::Branch(NativeHostingBranchPullRequests {
                    branch: branch.to_owned(),
                    change_requests: with_status(
                        plugin,
                        requester,
                        connection,
                        &repository,
                        pulls,
                        credential,
                        cancellation,
                    )
                    .into_iter()
                    .map(|pull| map_pull_request(repository_id, pull))
                    .collect(),
                }));
            },
        )
        .map_err(map_resource_error)
}

/// Adds the optional status of each open pull request. Cancellation stops the reads; the
/// lookup then ends as canceled.
fn with_status(
    plugin: &dyn HostingProviderPlugin,
    requester: &dyn HostingProviderRequester,
    connection: &HostingConnection,
    repository: &HostingRepositoryId,
    mut pulls: Vec<HostingPullRequest>,
    credential: &HostingCredential,
    cancellation: &dyn Cancellation,
) -> Vec<HostingPullRequest> {
    for pull in &mut pulls {
        if plugin
            .pull_request_status(
                requester,
                connection,
                repository,
                pull,
                credential,
                cancellation,
            )
            .is_err()
        {
            break;
        }
    }
    pulls
}

#[must_use]
pub fn resources_cancel(request_id: u64) -> bool {
    let runtime_guard = runtime().lock().expect("hosting runtime lock");
    let Some(runtime) = runtime_guard.as_ref() else {
        return false;
    };
    let sessions = runtime
        .resource_sessions
        .lock()
        .expect("hosting resource sessions lock");
    let Some(session) = sessions.get(&request_id) else {
        return false;
    };
    session.cancellation.store(true, Ordering::Release);
    true
}

pub fn resources_deactivate(connection_id: String, repository_id: String) {
    let runtime_guard = runtime().lock().expect("hosting runtime lock");
    let Some(runtime) = runtime_guard.as_ref() else {
        return;
    };
    runtime.cache.deactivate(&connection_id, &repository_id);
    for session in runtime
        .resource_sessions
        .lock()
        .expect("hosting resource sessions lock")
        .values()
    {
        if session.connection_id == connection_id && session.repository_id == repository_id {
            session.cancellation.store(true, Ordering::Release);
        }
    }
    for session in runtime
        .lookup_sessions
        .lock()
        .expect("hosting lookup sessions lock")
        .values()
    {
        if session.connection_id == connection_id && session.repository_id == repository_id {
            session.cancellation.store(true, Ordering::Release);
        }
    }
}

pub fn shutdown() {
    let current = runtime().lock().expect("hosting runtime lock").take();
    if let Some(runtime) = current {
        runtime.stop();
    }
}

fn start_failure(failure: NativeHostingOAuthFailure) -> NativeHostingOAuthStartResult {
    NativeHostingOAuthStartResult {
        snapshot: None,
        failure: Some(failure),
    }
}

fn resource_start_failure(
    failure: NativeHostingResourceFailure,
) -> NativeHostingResourceStartResult {
    NativeHostingResourceStartResult {
        snapshot: None,
        failure: Some(failure),
    }
}

fn publish(
    sessions: &Mutex<HashMap<u64, OAuthSession>>,
    request_id: u64,
    mutate: impl FnOnce(&mut NativeHostingOAuthSnapshot),
) {
    if let Some(session) = sessions
        .lock()
        .expect("OAuth sessions lock")
        .get_mut(&request_id)
    {
        mutate(&mut session.snapshot);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;

    struct IdentityRequester {
        body: &'static [u8],
    }

    struct ProviderFixtureRequester {
        malformed_required: bool,
        permission_denied: bool,
        fork_source: bool,
    }

    impl HostingProviderRequester for ProviderFixtureRequester {
        fn request(
            &self,
            connection: &HostingConnection,
            path: String,
            credential: &HostingCredential,
            _: &dyn Cancellation,
        ) -> Result<HostingHttpResponse, HostingError> {
            assert_eq!(credential.expose(), b"private-token");
            if self.permission_denied {
                return Err(HostingError::PermissionDenied);
            }
            if self.malformed_required {
                return Ok(HostingHttpResponse {
                    status: 200,
                    body: b"[{\"number\":1}]".to_vec(),
                });
            }
            let body = match connection.provider() {
                devmil_git::hosting::HostingProvider::GitHub if path.contains("/pulls?") => {
                    if self.fork_source {
                        br#"[{"number":1,"title":"GitHub PR","draft":false,"html_url":"https://github.com/team/project/pull/1","user":{"login":"alice"},"head":{"ref":"topic","sha":"abc123","repo":{"full_name":"alice/project-fork"}},"base":{"ref":"main","repo":{"full_name":"team/project"}}}]"#.to_vec()
                    } else {
                        br#"[{"number":1,"title":"GitHub PR","draft":false,"html_url":"https://github.com/team/project/pull/1","user":{"login":"alice"},"head":{"ref":"topic","sha":"abc123","repo":{"full_name":"team/project"}},"base":{"ref":"main","repo":{"full_name":"team/project"}}}]"#.to_vec()
                    }
                }
                devmil_git::hosting::HostingProvider::GitHub
                    if path.contains("/actions/runs?") =>
                {
                    br#"{"workflow_runs":[{"head_sha":"abc123","status":"completed","conclusion":"success"}]}"#.to_vec()
                }
                devmil_git::hosting::HostingProvider::GitHub if path.contains("/issues?") => {
                    br#"[{"number":2,"title":"GitHub issue","state":"open","html_url":"https://github.com/team/project/issues/2","user":{"login":"bob"}},{"number":1,"title":"PR duplicate","state":"open","html_url":"https://github.com/team/project/pull/1","user":{"login":"alice"},"pull_request":{}}]"#.to_vec()
                }
                devmil_git::hosting::HostingProvider::GitLab
                    if path.contains("merge_requests") =>
                {
                    br#"[{"iid":1,"title":"GitLab MR","draft":false,"web_url":"https://gitlab.example/team/project/-/merge_requests/1","author":{"username":"alice"},"source_branch":"topic","target_branch":"main","source_project_id":42,"target_project_id":42,"sha":"abc123"}]"#.to_vec()
                }
                devmil_git::hosting::HostingProvider::GitLab if path.contains("pipelines") => {
                    b"malformed optional CI".to_vec()
                }
                devmil_git::hosting::HostingProvider::GitLab if path.contains("/issues?") => {
                    br#"[{"iid":2,"title":"GitLab issue","state":"closed","web_url":"https://gitlab.example/team/project/-/issues/2","author":{"username":"bob"}}]"#.to_vec()
                }
                devmil_git::hosting::HostingProvider::Forgejo if path.contains("/pulls?") => {
                    br#"[{"number":1,"title":"Forgejo PR","draft":true,"html_url":"https://codeberg.org/team/project/pulls/1","user":{"login":"alice"},"head":{"ref":"topic","sha":"abc123","repo":{"full_name":"team/project"}},"base":{"ref":"main","sha":"def456","repo":{"full_name":"team/project"}}}]"#.to_vec()
                }
                devmil_git::hosting::HostingProvider::Forgejo
                    if path.contains("/actions/runs?") =>
                {
                    br#"{"workflow_runs":[{"head_sha":"abc123","status":"completed","conclusion":"failure"}]}"#.to_vec()
                }
                devmil_git::hosting::HostingProvider::Forgejo if path.contains("/issues?") => {
                    br#"[{"number":2,"title":"Forgejo issue","state":"open","html_url":"https://codeberg.org/team/project/issues/2","user":{"login":"bob"}}]"#.to_vec()
                }
                _ => panic!("unexpected provider fixture path: {path}"),
            };
            Ok(HostingHttpResponse { status: 200, body })
        }
    }

    impl HostingProviderRequester for IdentityRequester {
        fn request(
            &self,
            _connection: &HostingConnection,
            path: String,
            credential: &HostingCredential,
            cancellation: &dyn Cancellation,
        ) -> Result<HostingHttpResponse, HostingError> {
            assert_eq!(path, "/user");
            assert_eq!(credential.expose(), b"sentinel-access");
            assert!(!cancellation.is_cancelled());
            Ok(HostingHttpResponse {
                status: 200,
                body: self.body.to_vec(),
            })
        }
    }

    #[derive(Default)]
    struct MemoryCredentialWriter {
        access_tokens: Mutex<Vec<Vec<u8>>>,
    }

    impl CredentialWriter for MemoryCredentialWriter {
        fn store(
            &self,
            _connection: &NativeHostingConnection,
            envelope: &CredentialEnvelope,
        ) -> Result<(), ()> {
            self.access_tokens
                .lock()
                .unwrap()
                .push(envelope.access_token().to_vec());
            Ok(())
        }
    }

    fn native_connection(
        preset: crate::hosting::NativeHostingPreset,
        web_base_url: String,
        api_base_url: String,
    ) -> NativeHostingConnection {
        NativeHostingConnection {
            id: "oauth:fixture".into(),
            preset,
            login: String::new(),
            web_base_url,
            api_base_url,
            oauth_client_id: "public-client".into(),
            authentication: NativeHostingAuthentication::OAuth,
            enabled: true,
            refresh_enabled: true,
            capabilities: vec![],
            credential_identity: "credential:oauth:fixture".into(),
            allow_split_origin: false,
        }
    }

    fn shared_connection(
        preset: devmil_git::hosting::HostingPreset,
        web_base_url: String,
        api_base_url: String,
    ) -> HostingConnection {
        HostingConnection {
            id: devmil_git::hosting::HostingConnectionId::new("oauth:fixture").unwrap(),
            preset,
            login: String::new(),
            web_base_url,
            api_base_url,
            oauth_client_id: "public-client".into(),
            enabled: true,
            capabilities: devmil_git::hosting::HostingCapabilitySet {
                supported: Default::default(),
            },
        }
    }

    fn fixture_connection(preset: devmil_git::hosting::HostingPreset) -> HostingConnection {
        let provider = preset.provider();
        HostingConnection {
            id: devmil_git::hosting::HostingConnectionId::new(format!("fixture:{preset:?}"))
                .unwrap(),
            preset,
            login: "fixture".into(),
            web_base_url: preset
                .default_web_base()
                .unwrap_or("https://gitlab.example")
                .into(),
            api_base_url: preset
                .default_api_base()
                .unwrap_or_else(|| match provider {
                    devmil_git::hosting::HostingProvider::GitLab => "https://gitlab.example/api/v4",
                    devmil_git::hosting::HostingProvider::Forgejo => {
                        "https://forgejo.example/api/v1"
                    }
                    devmil_git::hosting::HostingProvider::GitHub => unreachable!(),
                })
                .into(),
            oauth_client_id: "public-client".into(),
            enabled: true,
            capabilities: devmil_git::hosting::HostingCapabilitySet::baseline(provider),
        }
    }

    fn session_map(request_id: u64) -> Mutex<HashMap<u64, OAuthSession>> {
        Mutex::new(HashMap::from([(
            request_id,
            OAuthSession {
                snapshot: queued_oauth_snapshot(request_id),
                cancellation: Arc::new(AtomicBool::new(false)),
            },
        )]))
    }

    #[test]
    fn scheduler_limits_global_and_per_connection_concurrency() {
        let scheduler = BoundedScheduler::new();
        let active = Arc::new(AtomicUsize::new(0));
        let maximum = Arc::new(AtomicUsize::new(0));
        let same_connection = Arc::new(AtomicUsize::new(0));
        let same_maximum = Arc::new(AtomicUsize::new(0));
        let completed = Arc::new(AtomicUsize::new(0));
        for connection in ["one", "one", "two", "three"] {
            let active = Arc::clone(&active);
            let maximum = Arc::clone(&maximum);
            let same_connection = Arc::clone(&same_connection);
            let same_maximum = Arc::clone(&same_maximum);
            let completed = Arc::clone(&completed);
            let is_same = connection == "one";
            assert!(scheduler.schedule(ScheduledTask {
                connection_id: connection.into(),
                cancellation: Arc::new(AtomicBool::new(false)),
                operation: Box::new(move |_| {
                    let now = active.fetch_add(1, Ordering::SeqCst) + 1;
                    maximum.fetch_max(now, Ordering::SeqCst);
                    if is_same {
                        let same = same_connection.fetch_add(1, Ordering::SeqCst) + 1;
                        same_maximum.fetch_max(same, Ordering::SeqCst);
                    }
                    thread::sleep(Duration::from_millis(50));
                    if is_same {
                        same_connection.fetch_sub(1, Ordering::SeqCst);
                    }
                    active.fetch_sub(1, Ordering::SeqCst);
                    completed.fetch_add(1, Ordering::SeqCst);
                }),
            }));
        }
        let deadline = Instant::now() + Duration::from_secs(2);
        while completed.load(Ordering::SeqCst) != 4 && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(10));
        }
        assert_eq!(completed.load(Ordering::SeqCst), 4);
        assert_eq!(maximum.load(Ordering::SeqCst), 2);
        assert_eq!(same_maximum.load(Ordering::SeqCst), 1);
        scheduler.stop();
    }

    #[test]
    fn scheduler_shutdown_cancels_active_and_queued_work() {
        let scheduler = BoundedScheduler::new();
        let started = Arc::new(AtomicBool::new(false));
        let observed = Arc::new(AtomicBool::new(false));
        let started_for_task = Arc::clone(&started);
        let observed_for_task = Arc::clone(&observed);
        assert!(scheduler.schedule(ScheduledTask {
            connection_id: "one".into(),
            cancellation: Arc::new(AtomicBool::new(false)),
            operation: Box::new(move |cancellation| {
                started_for_task.store(true, Ordering::Release);
                while !cancellation.load(Ordering::Acquire) {
                    thread::sleep(Duration::from_millis(5));
                }
                observed_for_task.store(true, Ordering::Release);
            }),
        }));
        let deadline = Instant::now() + Duration::from_secs(1);
        while !started.load(Ordering::Acquire) && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(5));
        }
        assert!(started.load(Ordering::Acquire));
        scheduler.stop();
        assert!(observed.load(Ordering::Acquire));
    }

    #[test]
    fn callback_accepts_one_exact_state_and_rejects_mismatch() {
        fn exchange(request: &str, expected: &str) -> Result<String, FlowFailure> {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let address = listener.local_addr().unwrap();
            let request = request.to_owned();
            let client = thread::spawn(move || {
                let mut stream = TcpStream::connect(address).unwrap();
                stream.write_all(request.as_bytes()).unwrap();
            });
            let mut stream = crate::loopback_fixture::accept_client(&listener);
            let result = parse_callback(&mut stream, expected);
            client.join().unwrap();
            result
        }
        assert_eq!(
            exchange(
                "GET /oauth/callback?code=once&state=expected HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n",
                "expected"
            )
            .unwrap(),
            "once"
        );
        assert!(exchange(
            "GET /oauth/callback?code=once&state=replayed HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n",
            "expected"
        )
        .is_err());
    }

    #[test]
    fn cache_publishes_first_cancels_replaced_work_and_honors_ttls() {
        assert_eq!(
            HOSTING_PAGE_CAPACITY,
            devmil_git::hosting::providers::HOSTING_PAGE_SIZE
        );
        let cache = HostingCache::default();
        assert!(cache
            .begin_refresh("one", "group/project", HostingCacheClass::Issues)
            .is_none());
        cache.activate("one".into(), "group/project".into());
        let (first, first_cancel) = cache
            .begin_refresh("one", "group/project", HostingCacheClass::Issues)
            .unwrap();
        let (second, _) = cache
            .begin_refresh("one", "group/project", HostingCacheClass::Issues)
            .unwrap();
        assert!(first_cancel.load(Ordering::Acquire));
        let empty = || NativeHostingResources {
            change_requests: vec![],
            issues: vec![],
            remote_references: vec![],
        };
        assert!(!cache.publish(
            "one",
            "group/project",
            HostingCacheClass::Issues,
            first,
            empty(),
        ));
        assert!(cache.publish(
            "one",
            "group/project",
            HostingCacheClass::Issues,
            second,
            empty(),
        ));
        let fresh = cache
            .lookup(
                "one",
                "group/project",
                HostingCacheClass::Issues,
                Instant::now(),
            )
            .unwrap();
        assert!(!fresh.stale);
        let stale = cache
            .lookup(
                "one",
                "group/project",
                HostingCacheClass::Issues,
                Instant::now() + ISSUE_FRESHNESS + Duration::from_millis(1),
            )
            .unwrap();
        assert!(stale.stale);
        let (_, cancellation) = cache
            .begin_refresh("one", "group/project", HostingCacheClass::ChangeRequests)
            .unwrap();
        cache.deactivate("one", "group/project");
        assert!(cancellation.load(Ordering::Acquire));
        cache.activate("one".into(), "group/project".into());
        let (shutdown_generation, shutdown_cancellation) = cache
            .begin_refresh("one", "group/project", HostingCacheClass::Issues)
            .unwrap();
        cache.shutdown();
        assert!(shutdown_cancellation.load(Ordering::Acquire));
        assert!(!cache.publish(
            "one",
            "group/project",
            HostingCacheClass::Issues,
            shutdown_generation,
            empty(),
        ));
    }

    fn serve_once(status: u16, body: Vec<u8>) -> String {
        serve_once_after(status, body, Duration::ZERO)
    }

    fn serve_once_after(status: u16, body: Vec<u8>, delay: Duration) -> String {
        serve_once_after_signal(status, body, delay, None)
    }

    fn serve_once_after_signal(
        status: u16,
        body: Vec<u8>,
        delay: Duration,
        ready: Option<std::sync::mpsc::SyncSender<()>>,
    ) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        thread::spawn(move || {
            let mut stream = crate::loopback_fixture::accept_client(&listener);
            stream
                .set_read_timeout(Some(Duration::from_secs(2)))
                .unwrap();
            let mut request = [0_u8; 4096];
            let _ = stream.read(&mut request);
            if let Some(ready) = ready {
                ready.send(()).unwrap();
            }
            thread::sleep(delay);
            let header = format!(
                "HTTP/1.1 {status} Fixture\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len()
            );
            let _ = stream.write_all(header.as_bytes());
            let _ = stream.write_all(&body);
        });
        format!("http://{address}/oauth")
    }

    struct RefreshTransport {
        status: u16,
        body: &'static [u8],
        expected_url: &'static str,
        calls: AtomicUsize,
    }

    impl OAuthFormTransport for RefreshTransport {
        fn post_form(
            &self,
            url: &str,
            form: &str,
            cancellation: &dyn Cancellation,
        ) -> Result<HostingHttpResponse, HostingError> {
            assert!(!cancellation.is_cancelled());
            assert_eq!(url, self.expected_url);
            assert_eq!(
                form,
                "client_id=public-client&grant_type=refresh_token&refresh_token=old%2B%2F%26%3D"
            );
            self.calls.fetch_add(1, Ordering::SeqCst);
            Ok(HostingHttpResponse {
                status: self.status,
                body: self.body.to_vec(),
            })
        }
    }

    #[test]
    fn oauth_refresh_uses_provider_endpoint_and_keeps_or_rotates_refresh_token() {
        use crate::hosting::NativeHostingPreset;
        for (preset, base, api, endpoint) in [
            (
                NativeHostingPreset::Forgejo,
                "https://forge.example.test",
                "https://forge.example.test/api/v1",
                "https://forge.example.test/login/oauth/access_token",
            ),
            (
                NativeHostingPreset::GitLabSelfManaged,
                "https://gitlab.example.test",
                "https://gitlab.example.test/api/v4",
                "https://gitlab.example.test/oauth/token",
            ),
        ] {
            for (body, refresh) in [
                (
                    br#"{"access_token":"new-access","refresh_token":"rotated","expires_in":3600}"#
                        .as_slice(),
                    "rotated",
                ),
                (
                    br#"{"access_token":"new-access","expires_in":3600}"#.as_slice(),
                    "old+/&=",
                ),
            ] {
                let native = native_connection(preset, base.into(), api.into());
                let envelope =
                    CredentialEnvelope::new("old-access".into(), Some("old+/&=".into()), Some(99))
                        .unwrap();
                let transport = RefreshTransport {
                    status: 200,
                    body,
                    expected_url: endpoint,
                    calls: AtomicUsize::new(0),
                };
                let renewed = refresh_credential_with(
                    &transport,
                    &native,
                    &envelope,
                    &AtomicBool::new(false),
                    || 100,
                )
                .unwrap();
                assert_eq!(renewed.access_token(), b"new-access");
                assert_eq!(renewed.refresh_token(), Some(refresh));
                let value = serde_json::to_value(&renewed).unwrap();
                assert_eq!(value["expires_at"], 3700);
                assert_eq!(transport.calls.load(Ordering::SeqCst), 1);
                assert_eq!(envelope.access_token(), b"old-access");
            }
        }
    }

    #[test]
    fn oauth_refresh_reports_terminal_and_transient_failures_without_retries() {
        let native = native_connection(
            crate::hosting::NativeHostingPreset::Forgejo,
            "https://forge.example.test".into(),
            "https://forge.example.test/api/v1".into(),
        );
        let envelope =
            CredentialEnvelope::new("old-access".into(), Some("old+/&=".into()), Some(99)).unwrap();
        for (status, body, expected) in [
            (
                400,
                br#"{"error":"invalid_grant","error_description":"private response"}"#.as_slice(),
                NativeHostingResourceFailure::Unauthorized,
            ),
            (
                400,
                b"malformed".as_slice(),
                NativeHostingResourceFailure::MalformedResponse,
            ),
            (
                200,
                br#"{"access_token":"new-access"}"#.as_slice(),
                NativeHostingResourceFailure::MalformedResponse,
            ),
            (
                200,
                br#"{"access_token":"new-access","expires_in":0}"#.as_slice(),
                NativeHostingResourceFailure::MalformedResponse,
            ),
            (
                200,
                br#"{"access_token":"new-access","expires_in":18446744073709551615}"#.as_slice(),
                NativeHostingResourceFailure::MalformedResponse,
            ),
            (
                401,
                b"private response".as_slice(),
                NativeHostingResourceFailure::Unauthorized,
            ),
            (
                403,
                b"private response".as_slice(),
                NativeHostingResourceFailure::PermissionDenied,
            ),
            (
                429,
                b"private response".as_slice(),
                NativeHostingResourceFailure::RateLimited,
            ),
            (
                500,
                b"private response".as_slice(),
                NativeHostingResourceFailure::ServerError,
            ),
        ] {
            let transport = RefreshTransport {
                status,
                body,
                expected_url: "https://forge.example.test/login/oauth/access_token",
                calls: AtomicUsize::new(0),
            };
            let error = refresh_credential_with(
                &transport,
                &native,
                &envelope,
                &AtomicBool::new(false),
                || 100,
            )
            .unwrap_err();
            assert_eq!(map_resource_error(error), expected);
            assert_eq!(transport.calls.load(Ordering::SeqCst), 1);
            assert_eq!(envelope.refresh_token(), Some("old+/&="));
        }
    }

    #[test]
    fn oauth_refresh_runs_through_bounded_native_transport() {
        let base = serve_once(
            200,
            br#"{"access_token":"new-access","refresh_token":"rotated","expires_in":3600}"#
                .to_vec(),
        );
        let native = native_connection(
            crate::hosting::NativeHostingPreset::Forgejo,
            base.clone(),
            base,
        );
        let envelope =
            CredentialEnvelope::new("old-access".into(), Some("old+/&=".into()), Some(99)).unwrap();
        let renewed = refresh_credential_with(
            &CurlTransport::first_page(),
            &native,
            &envelope,
            &AtomicBool::new(false),
            || 100,
        )
        .unwrap();
        assert_eq!(renewed.access_token(), b"new-access");
        assert_eq!(renewed.refresh_token(), Some("rotated"));
    }

    #[test]
    fn local_transport_preserves_status_and_rejects_oversized_body() {
        let cancellation = AtomicBool::new(false);
        let rate_limited = CurlTransport::first_page()
            .post_form(
                &serve_once(429, b"{}".to_vec()),
                "client_id=fixture",
                &cancellation,
            )
            .unwrap();
        assert_eq!(rate_limited.status, 429);
        assert_eq!(
            require_success(rate_limited.status),
            Err(FlowFailure::Native(NativeHostingOAuthFailure::RateLimited))
        );
        let oversized = vec![b'x'; devmil_git::hosting::http::MAX_RESPONSE_BYTES + 1];
        assert!(CurlTransport::first_page()
            .post_form(
                &serve_once(200, oversized),
                "client_id=fixture",
                &cancellation,
            )
            .is_err());
    }

    #[test]
    fn transport_failures_name_the_cause_instead_of_a_generic_outage() {
        for (status, resource, oauth) in [
            (
                404,
                NativeHostingResourceFailure::NotFound,
                NativeHostingOAuthFailure::NotFound,
            ),
            (
                301,
                NativeHostingResourceFailure::Redirected,
                NativeHostingOAuthFailure::Redirected,
            ),
            (
                503,
                NativeHostingResourceFailure::ServerError,
                NativeHostingOAuthFailure::ServerError,
            ),
        ] {
            let error = TransportFailure::from_status(status).unwrap().into_error();
            assert_eq!(map_resource_error(error.clone()), resource);
            assert_eq!(map_hosting_error(error), FlowFailure::Native(oauth));
            assert_eq!(require_success(status), Err(FlowFailure::Native(oauth)));
        }
        assert_eq!(
            require_success(418),
            Err(FlowFailure::Native(NativeHostingOAuthFailure::Unavailable))
        );
        assert_eq!(
            TransportFailure::from_curl_exit(60),
            Some(TransportFailure::Certificate)
        );
        assert_eq!(
            TransportFailure::from_curl_exit(28),
            Some(TransportFailure::TimedOut)
        );
        assert_eq!(TransportFailure::from_curl_exit(2), None);
        assert_eq!(
            map_resource_error(HostingError::Unavailable("provider unavailable".into())),
            NativeHostingResourceFailure::Unavailable
        );

        // A closed loopback port: curl itself reports that nothing answered.
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        drop(listener);
        let refused = CurlTransport::first_page()
            .post_form(
                &format!("http://{address}/oauth"),
                "client_id=fixture",
                &AtomicBool::new(false),
            )
            .unwrap_err();
        assert_eq!(
            map_resource_error(refused.clone()),
            NativeHostingResourceFailure::Network
        );
        assert_eq!(
            map_hosting_error(refused),
            FlowFailure::Native(NativeHostingOAuthFailure::Network)
        );
    }

    #[test]
    fn delayed_local_response_is_canceled_without_late_completion() {
        let cancellation = Arc::new(AtomicBool::new(false));
        let cancel = Arc::clone(&cancellation);
        let (ready_tx, ready_rx) = std::sync::mpsc::sync_channel(1);
        let (canceled_tx, canceled_rx) = std::sync::mpsc::sync_channel(1);
        let cancel_thread = thread::spawn(move || {
            ready_rx.recv().unwrap();
            thread::sleep(Duration::from_millis(100));
            cancel.store(true, Ordering::Release);
            canceled_tx.send(Instant::now()).unwrap();
        });
        let result = CurlTransport::first_page().post_form(
            &serve_once_after_signal(200, b"{}".to_vec(), Duration::from_secs(5), Some(ready_tx)),
            "client_id=fixture",
            cancellation.as_ref(),
        );
        let canceled_at = canceled_rx.recv().unwrap();
        cancel_thread.join().unwrap();
        assert!(matches!(result, Err(HostingError::Canceled)));
        assert!(canceled_at.elapsed() < Duration::from_secs(3));
    }

    #[test]
    fn local_device_flow_responses_cover_slow_down_and_expiry() {
        let cancellation = AtomicBool::new(false);
        let connection = HostingConnection {
            id: devmil_git::hosting::HostingConnectionId::new("github:fixture").unwrap(),
            preset: devmil_git::hosting::HostingPreset::GitHub,
            login: "fixture".into(),
            web_base_url: "https://github.com".into(),
            api_base_url: "https://api.github.com".into(),
            oauth_client_id: "public-client".into(),
            enabled: true,
            capabilities: devmil_git::hosting::HostingCapabilitySet {
                supported: Default::default(),
            },
        };
        let specification = match provider_plugin(connection.provider()).login_flow() {
            OAuthLoginFlow::DeviceAuthorization(specification) => specification,
            OAuthLoginFlow::AuthorizationCodePkce(_) => panic!("GitHub must use device flow"),
        };
        let slow = CurlTransport::first_page()
            .post_form(
                &serve_once(400, br#"{"error":"slow_down","interval":2}"#.to_vec()),
                &device_authorization_poll_form(&connection, "private-device-code"),
                &cancellation,
            )
            .unwrap();
        assert!(matches!(
            parse_device_authorization_poll(&slow.body).unwrap(),
            DeviceAuthorizationPoll::SlowDown(Some(2))
        ));
        let expired = CurlTransport::first_page()
            .post_form(
                &serve_once(400, br#"{"error":"expired_token"}"#.to_vec()),
                &device_authorization_poll_form(&connection, "private-device-code"),
                &cancellation,
            )
            .unwrap();
        assert!(matches!(
            parse_device_authorization_poll(&expired.body).unwrap(),
            DeviceAuthorizationPoll::Expired
        ));
        assert_eq!(specification.device_code_path, "/login/device/code");
    }

    #[test]
    fn github_device_flow_completes_against_a_local_contract_server() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let base = format!("http://{address}");
        let verification_uri = format!("{base}/login/device");
        let server = thread::spawn(move || {
            let responses = [
                format!(
                    "{{\"device_code\":\"private-device-code\",\"user_code\":\"ABCD-EFGH\",\"verification_uri\":\"{verification_uri}\",\"expires_in\":10,\"interval\":1}}"
                ),
                "{\"error\":\"authorization_pending\"}".into(),
                "{\"access_token\":\"sentinel-access\",\"refresh_token\":\"sentinel-refresh\",\"expires_in\":3600}".into(),
            ];
            for body in responses {
                let mut stream = crate::loopback_fixture::accept_client(&listener);
                let mut request = [0_u8; 4096];
                let _ = stream.read(&mut request);
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                stream.write_all(response.as_bytes()).unwrap();
            }
        });
        let native = native_connection(
            crate::hosting::NativeHostingPreset::GitHub,
            base.clone(),
            base.clone(),
        );
        let connection = shared_connection(
            devmil_git::hosting::HostingPreset::GitHub,
            base.clone(),
            base,
        );
        let specification = match provider_plugin(connection.provider()).login_flow() {
            OAuthLoginFlow::DeviceAuthorization(specification) => specification,
            OAuthLoginFlow::AuthorizationCodePkce(_) => panic!("GitHub must use device flow"),
        };
        let sessions = session_map(41);
        let writer = MemoryCredentialWriter::default();
        let transport = CurlTransport::first_page();
        let login = run_device_flow_with(
            41,
            &native,
            &connection,
            specification,
            &AtomicBool::new(false),
            &sessions,
            &transport,
            &IdentityRequester {
                body: br#"{"login":"octocat"}"#,
            },
            &writer,
        )
        .unwrap();
        server.join().unwrap();
        assert_eq!(login, "octocat");
        assert_eq!(
            writer.access_tokens.lock().unwrap().as_slice(),
            &[b"sentinel-access".to_vec()]
        );
        assert_eq!(
            sessions.lock().unwrap()[&41].snapshot.user_code.as_deref(),
            Some("ABCD-EFGH")
        );
    }

    #[test]
    fn gitlab_pkce_flow_completes_once_against_a_local_contract_server() {
        for (preset, status, body, failure) in [
            (
                crate::hosting::NativeHostingPreset::GitLabSelfManaged,
                "200 OK",
                r#"{"access_token":"sentinel-access","expires_in":3600}"#,
                None,
            ),
            (
                crate::hosting::NativeHostingPreset::Forgejo,
                "200 OK",
                r#"{"access_token":"sentinel-access","expires_in":3600}"#,
                None,
            ),
            (
                crate::hosting::NativeHostingPreset::Forgejo,
                "400 Bad Request",
                r#"{"error":"unauthorized_client","error_description":"private-provider-detail"}"#,
                Some(NativeHostingOAuthFailure::InvalidConnection),
            ),
            (
                crate::hosting::NativeHostingPreset::Forgejo,
                "400 Bad Request",
                r#"{"error":"invalid_grant"}"#,
                Some(NativeHostingOAuthFailure::Unauthorized),
            ),
        ] {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let address = listener.local_addr().unwrap();
            let base = format!("http://{address}");
            let server = thread::spawn(move || {
                let mut stream = crate::loopback_fixture::accept_client(&listener);
                let mut request = [0_u8; 8192];
                let read = stream.read(&mut request).unwrap();
                let request = String::from_utf8_lossy(&request[..read]);
                assert!(request.contains("code=one-time-code"));
                assert!(request.contains("code_verifier="));
                let response = format!(
                "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
                stream.write_all(response.as_bytes()).unwrap();
            });
            let native = Arc::new(native_connection(preset, base.clone(), base.clone()));
            let connection = Arc::new(shared_connection(
                if preset == crate::hosting::NativeHostingPreset::Forgejo {
                    devmil_git::hosting::HostingPreset::Forgejo
                } else {
                    devmil_git::hosting::HostingPreset::GitLabSelfManaged
                },
                base.clone(),
                base,
            ));
            let specification = match provider_plugin(connection.provider()).login_flow() {
                OAuthLoginFlow::AuthorizationCodePkce(specification) => specification,
                OAuthLoginFlow::DeviceAuthorization(_) => panic!("GitLab must use PKCE"),
            };
            let sessions = Arc::new(session_map(42));
            let writer = Arc::new(MemoryCredentialWriter::default());
            let worker_sessions = Arc::clone(&sessions);
            let worker_writer = Arc::clone(&writer);
            let worker_native = Arc::clone(&native);
            let worker_connection = Arc::clone(&connection);
            let worker = thread::spawn(move || {
                let transport = CurlTransport::first_page();
                run_pkce_flow_with(
                    42,
                    &worker_native,
                    &worker_connection,
                    specification,
                    &AtomicBool::new(false),
                    &worker_sessions,
                    &transport,
                    &IdentityRequester {
                        body: br#"{"username":"gitlab-user","login":"forge-user"}"#,
                    },
                    worker_writer.as_ref(),
                )
            });
            let deadline = Instant::now() + Duration::from_secs(2);
            let browser_url = loop {
                if let Some(url) = sessions.lock().unwrap()[&42].snapshot.browser_url.clone() {
                    break url;
                }
                assert!(
                    Instant::now() < deadline,
                    "PKCE browser URL was not published"
                );
                thread::sleep(Duration::from_millis(10));
            };
            let query = browser_url.split_once('?').unwrap().1;
            let state = devmil_git::hosting::oauth::query_value(query, "state").unwrap();
            let mut callback = TcpStream::connect(LOOPBACK_ADDRESS).unwrap();
            write!(
            callback,
            "GET /oauth/callback?code=one-time-code&state={state} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        )
        .unwrap();
            let result = worker.join().unwrap();
            if let Some(failure) = failure {
                assert_eq!(result, Err(FlowFailure::Native(failure)));
            } else {
                assert_eq!(
                    result.unwrap(),
                    if preset == crate::hosting::NativeHostingPreset::Forgejo {
                        "forge-user"
                    } else {
                        "gitlab-user"
                    }
                );
            }
            server.join().unwrap();
            if failure.is_some() {
                assert!(writer.access_tokens.lock().unwrap().is_empty());
            } else {
                assert_eq!(
                    writer.access_tokens.lock().unwrap().as_slice(),
                    &[b"sentinel-access".to_vec()]
                );
            }
            drop(callback);
            let deadline = Instant::now() + Duration::from_secs(1);
            loop {
                match TcpListener::bind(LOOPBACK_ADDRESS) {
                    Ok(rebound) => {
                        drop(rebound);
                        break;
                    }
                    Err(_) => {
                        assert!(
                            Instant::now() < deadline,
                            "PKCE callback address was not released after completion"
                        );
                        thread::sleep(Duration::from_millis(10));
                    }
                }
            }
        }
    }

    #[test]
    fn accepted_callback_closes_listener_against_replay() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        listener.set_nonblocking(true).unwrap();
        let worker = thread::spawn(move || {
            wait_for_callback(&listener, "one-time-state", &AtomicBool::new(false))
        });
        let mut stream = loop {
            match TcpStream::connect(address) {
                Ok(stream) => break stream,
                Err(_) => thread::sleep(Duration::from_millis(10)),
            }
        };
        stream.write_all(b"GET /oauth/callback?code=once&").unwrap();
        thread::sleep(Duration::from_millis(10));
        stream
            .write_all(b"state=one-time-state HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
            .unwrap();
        assert_eq!(worker.join().unwrap().unwrap(), "once");
        // A process another test forks at this moment briefly inherits the listening socket
        // until it executes its program, so wait for the last copy to close.
        let deadline = Instant::now() + Duration::from_secs(2);
        while TcpStream::connect(address).is_ok() {
            assert!(
                Instant::now() < deadline,
                "the callback listener stayed open"
            );
            thread::sleep(Duration::from_millis(20));
        }
    }

    #[test]
    fn later_pages_are_explicit_and_bounded() {
        assert_eq!(
            page_path("/issues?per_page=50".into(), 1).unwrap(),
            "/issues?per_page=50"
        );
        assert_eq!(
            page_path("/issues?per_page=50".into(), 2).unwrap(),
            "/issues?per_page=50&page=2"
        );
        assert!(page_path("/issues?per_page=50".into(), 1001).is_err());
        assert!(page_path("/issues".into(), 2).is_err());
    }

    #[test]
    fn three_provider_units_project_all_five_presets_and_optional_ci() {
        let requester = ProviderFixtureRequester {
            malformed_required: false,
            permission_denied: false,
            fork_source: false,
        };
        for preset in [
            devmil_git::hosting::HostingPreset::GitHub,
            devmil_git::hosting::HostingPreset::GitLab,
            devmil_git::hosting::HostingPreset::GitLabSelfManaged,
            devmil_git::hosting::HostingPreset::Forgejo,
            devmil_git::hosting::HostingPreset::Codeberg,
        ] {
            let connection = fixture_connection(preset);
            let (resources, has_more) = load_resources_with(
                &requester,
                &connection,
                "team/project",
                &HostingCredential::new(b"private-token".to_vec()).unwrap(),
                &AtomicBool::new(false),
            )
            .unwrap();
            assert!(!has_more);
            assert_eq!(resources.change_requests.len(), 1, "{preset:?}");
            assert_eq!(resources.issues.len(), 1, "{preset:?}");
            assert_eq!(resources.remote_references.len(), 2, "{preset:?}");
            let pull = &resources.change_requests[0];
            assert_eq!(pull.stable_id, pull.web_url);
            assert_eq!(pull.source_repository, "team/project");
            assert_eq!(pull.target_repository, "team/project");
            assert_eq!(pull.head_sha, "abc123");
            assert_eq!(pull.review_summary, NativeHostingReviewSummary::Unknown);
            assert_eq!(pull.mergeability, NativeHostingMergeability::Unknown);
            if matches!(
                preset,
                devmil_git::hosting::HostingPreset::GitLab
                    | devmil_git::hosting::HostingPreset::GitLabSelfManaged
            ) {
                assert_eq!(pull.checks.state, NativeHostingCheckState::Unknown);
            }
        }
    }

    struct LookupRequester;

    impl HostingProviderRequester for LookupRequester {
        fn request(
            &self,
            _: &HostingConnection,
            path: String,
            _: &HostingCredential,
            _: &dyn Cancellation,
        ) -> Result<HostingHttpResponse, HostingError> {
            const PULL: &str = r#"{"number":7,"title":"Topic","draft":false,"html_url":"https://github.com/team/project/pull/7","user":{"login":"alice"},"head":{"ref":"feature/topic","sha":"abc123","repo":{"full_name":"team/project"}},"base":{"ref":"main","repo":{"full_name":"team/project"}}}"#;
            let body = match path.as_str() {
                "/repos/team/project/issues?state=open&creator=alice&per_page=50" => {
                    r#"[{"number":7,"title":"Topic","state":"open","html_url":"https://github.com/team/project/pull/7","user":{"login":"alice"},"pull_request":{}}]"#.to_owned()
                }
                "/repos/team/project/pulls/7" => PULL.to_owned(),
                "/repos/team/project/pulls?state=all&head=team%3Afeature%2Ftopic&per_page=50" => {
                    format!("[{PULL}]")
                }
                "/repos/team/project/pulls?state=all&head=team%3Amerged&per_page=50" => {
                    r#"[{"number":5,"title":"Done","draft":false,"state":"closed","merged_at":"2026-10-01T10:00:00Z","html_url":"https://github.com/team/project/pull/5","user":{"login":"bob"},"head":{"ref":"merged","sha":"def456","repo":{"full_name":"team/project"}},"base":{"ref":"main","repo":{"full_name":"team/project"}}}]"#.to_owned()
                }
                _ => return Err(HostingError::PermissionDenied),
            };
            Ok(HostingHttpResponse {
                status: 200,
                body: body.into_bytes(),
            })
        }
    }

    #[test]
    fn pull_request_lookup_reports_each_result_and_keeps_them_past_a_failure() {
        let connection = fixture_connection(devmil_git::hosting::HostingPreset::GitHub);
        let mut authored = Vec::new();
        let mut branches = Vec::new();
        let result = lookup_pull_requests_with(
            &LookupRequester,
            &connection,
            "team/project",
            &[],
            &["feature/topic".into(), "merged".into(), "denied".into()],
            Some("alice"),
            &HostingCredential::new(b"private-token".to_vec()).unwrap(),
            &AtomicBool::new(false),
            &mut |progress| match progress {
                LookupProgress::Authored(value) => authored = value,
                LookupProgress::Branch(value) => branches.push(value),
                LookupProgress::Head(_) => unreachable!(),
            },
        );
        assert_eq!(result, Err(NativeHostingResourceFailure::PermissionDenied));
        assert_eq!(authored.len(), 1);
        assert_eq!(authored[0].source_branch, "feature/topic");
        assert_eq!(
            branches
                .iter()
                .map(|value| (value.branch.as_str(), value.change_requests.len()))
                .collect::<Vec<_>>(),
            [("feature/topic", 1), ("merged", 1)]
        );
        assert_eq!(branches[0].change_requests[0].number, 7);
        assert_eq!(
            branches[0].change_requests[0].state,
            NativeHostingChangeRequestState::Open
        );
        assert_eq!(
            branches[1].change_requests[0].state,
            NativeHostingChangeRequestState::Merged
        );
    }

    struct StatusRequester;

    impl HostingProviderRequester for StatusRequester {
        fn request(
            &self,
            _: &HostingConnection,
            path: String,
            _: &HostingCredential,
            _: &dyn Cancellation,
        ) -> Result<HostingHttpResponse, HostingError> {
            const HEAD: &str = "0123456789abcdef0123456789abcdef01234567";
            let body = if path.starts_with("/repos/team/project/pulls?state=all") {
                format!(
                    r#"[{{"number":3,"title":"Topic","draft":false,"state":"open","mergeable":false,"html_url":"https://codeberg.org/team/project/pulls/3","user":{{"login":"alice"}},"head":{{"ref":"topic","sha":"{HEAD}","repo":{{"full_name":"team/project"}}}},"base":{{"ref":"main","sha":"def","repo":{{"full_name":"team/project"}}}}}}]"#
                )
            } else if path == format!("/repos/team/project/commits/{HEAD}/status") {
                r#"{"state":"pending","statuses":[{"id":1,"status":"pending","context":"ci / test"}]}"#
                    .to_owned()
            } else {
                return Err(HostingError::PermissionDenied);
            };
            Ok(HostingHttpResponse {
                status: 200,
                body: body.into_bytes(),
            })
        }
    }

    #[test]
    fn branch_lookup_reports_head_ci_and_mergeability_of_open_pull_requests() {
        let connection = fixture_connection(devmil_git::hosting::HostingPreset::Forgejo);
        let mut branches = Vec::new();
        let result = lookup_pull_requests_with(
            &StatusRequester,
            &connection,
            "team/project",
            &[],
            &["topic".into()],
            None,
            &HostingCredential::new(b"private-token".to_vec()).unwrap(),
            &AtomicBool::new(false),
            &mut |progress| {
                if let LookupProgress::Branch(value) = progress {
                    branches.push(value);
                }
            },
        );
        assert_eq!(result, Ok(()));
        let pull = &branches[0].change_requests[0];
        assert_eq!(pull.head_sha, "0123456789abcdef0123456789abcdef01234567");
        assert_eq!(pull.checks.state, NativeHostingCheckState::Pending);
        assert_eq!(pull.mergeability, NativeHostingMergeability::Conflicting);
    }

    #[test]
    fn head_lookup_reports_ci_of_a_commit_without_a_pull_request() {
        let connection = fixture_connection(devmil_git::hosting::HostingPreset::Forgejo);
        let mut heads = Vec::new();
        let result = lookup_pull_requests_with(
            &StatusRequester,
            &connection,
            "team/project",
            &[
                "0123456789abcdef0123456789abcdef01234567".into(),
                "ffffffffffffffffffffffffffffffffffffffff".into(),
            ],
            &[],
            None,
            &HostingCredential::new(b"private-token".to_vec()).unwrap(),
            &AtomicBool::new(false),
            &mut |progress| {
                if let LookupProgress::Head(value) = progress {
                    heads.push(value);
                }
            },
        );
        // An unreadable head stays unknown and does not fail the lookup.
        assert_eq!(result, Ok(()));
        assert_eq!(
            heads
                .iter()
                .map(|value| (&value.head[..4], value.checks))
                .collect::<Vec<_>>(),
            [
                ("0123", NativeHostingCheckState::Pending),
                ("ffff", NativeHostingCheckState::Unknown),
            ]
        );
    }

    #[test]
    fn finished_sessions_wait_for_their_poll_within_a_bound() {
        let mut sessions = HashMap::new();
        for id in 0..(FINISHED_SESSION_LIMIT as u64 + 5) {
            sessions.insert(id, NativeHostingResourceLoadState::Ready);
        }
        sessions.insert(1000, NativeHostingResourceLoadState::Loading);
        prune_finished(&mut sessions, |state| *state);
        assert_eq!(sessions.len(), FINISHED_SESSION_LIMIT + 1);
        assert!(!sessions.contains_key(&0));
        assert!(sessions.contains_key(&1000));
        assert!(sessions.contains_key(&(FINISHED_SESSION_LIMIT as u64 + 4)));
    }

    #[test]
    fn fork_pull_request_preserves_exact_source_repository() {
        let connection = fixture_connection(devmil_git::hosting::HostingPreset::GitHub);
        let (resources, _) = load_resources_with(
            &ProviderFixtureRequester {
                malformed_required: false,
                permission_denied: false,
                fork_source: true,
            },
            &connection,
            "team/project",
            &HostingCredential::new(b"private-token".to_vec()).unwrap(),
            &AtomicBool::new(false),
        )
        .unwrap();
        let pull = &resources.change_requests[0];
        assert_eq!(pull.source_repository, "alice/project-fork");
        assert_eq!(pull.target_repository, "team/project");
    }

    #[test]
    fn required_schema_and_permission_failures_remain_distinct() {
        let connection = fixture_connection(devmil_git::hosting::HostingPreset::GitHub);
        let credential = HostingCredential::new(b"private-token".to_vec()).unwrap();
        assert_eq!(
            load_resources_with(
                &ProviderFixtureRequester {
                    malformed_required: true,
                    permission_denied: false,
                    fork_source: false,
                },
                &connection,
                "team/project",
                &credential,
                &AtomicBool::new(false),
            ),
            Err(NativeHostingResourceFailure::MalformedResponse)
        );
        assert_eq!(
            load_resources_with(
                &ProviderFixtureRequester {
                    malformed_required: false,
                    permission_denied: true,
                    fork_source: false,
                },
                &connection,
                "team/project",
                &credential,
                &AtomicBool::new(false),
            ),
            Err(NativeHostingResourceFailure::PermissionDenied)
        );
        let unsupported = shared_connection(
            devmil_git::hosting::HostingPreset::GitHub,
            "https://github.com".into(),
            "https://api.github.com".into(),
        );
        let (resources, _) = load_resources_with(
            &ProviderFixtureRequester {
                malformed_required: true,
                permission_denied: true,
                fork_source: false,
            },
            &unsupported,
            "team/project",
            &credential,
            &AtomicBool::new(false),
        )
        .unwrap();
        assert!(resources.change_requests.is_empty());
        assert!(resources.issues.is_empty());
    }
}
