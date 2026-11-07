//! The repository session registry: opening, events, refresh, activity and closing.
#![allow(clippy::wildcard_imports)]
use crate::activity::{allocate_activity_id, ActivityStore, ACTIVITY_PAGE_CAPACITY};
use crate::application::index_lock::IndexLockState;
use crate::application::operation_center::OperationCenterState;
use crate::application::repository_locks::RepositoryLockState;
use crate::application::{
    commit::*, diff::*, discard::*, history::*, inspection::*, patch::*, refs::*, restore::*,
    snapshot::*, staging::*,
};
use crate::domain::ids::SessionKey;
use crate::domain::path_identity::NativePathIdentity;
use crate::domain::session_policy::SessionPolicy;
use crate::dto::*;
use crate::preview_store::SessionPreviews;
use devmil_git::process::ActivityGitRunner;
use devmil_git::repository::{DiscoveryRequest, RepositoryDiscovery};
use devmil_git::types::RepositoryPath;
use devmil_git::{
    Repository, RepositoryEvent, RepositoryOptions, RepositorySnapshot, RepositorySubscription,
};
use std::collections::{HashMap, VecDeque};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

/// One open repository session. Each feature keeps its own state; the registry owns the
/// sessions and [`with_session`] is the one way to reach one.
pub(crate) struct OwnedRepositorySession {
    pub(crate) generation: u64,
    pub(crate) repository: Arc<Repository>,
    pub(crate) subscription: RepositorySubscription,
    pub(crate) activity: ActivityStore,
    pub(crate) index_lock: IndexLockState,
    pub(crate) repository_locks: RepositoryLockState,
    pub(crate) operations: OperationCenterState,
    pub(crate) history: HistoryState,
    pub(crate) inspection: InspectionState,
    pub(crate) diff: DiffState,
    pub(crate) staging: StagingState,
    pub(crate) restore: SessionPreviews<OwnedRestorePreview>,
    pub(crate) refs: SessionPreviews<OwnedRefMutationPreview>,
    pub(crate) commit: SessionPreviews<OwnedCommitPreview>,
    pub(crate) discard: SessionPreviews<OwnedDiscardPreview>,
    pub(crate) patch: PatchState,
    pub(crate) archives: crate::application::archive::ArchiveState,
}

/// Previews a session keeps per family; the oldest goes first.
const SESSION_PREVIEWS: usize = 4;

impl OwnedRepositorySession {
    fn new(
        generation: u64,
        repository: Arc<Repository>,
        subscription: RepositorySubscription,
        activity: ActivityStore,
    ) -> Self {
        Self {
            generation,
            repository,
            subscription,
            activity,
            index_lock: IndexLockState::default(),
            repository_locks: RepositoryLockState::default(),
            operations: OperationCenterState::default(),
            history: HistoryState::default(),
            inspection: InspectionState::default(),
            diff: DiffState::default(),
            staging: StagingState::default(),
            restore: SessionPreviews::new(SESSION_PREVIEWS),
            refs: SessionPreviews::new(SESSION_PREVIEWS),
            commit: SessionPreviews::new(SESSION_PREVIEWS),
            discard: SessionPreviews::new(SESSION_PREVIEWS),
            patch: PatchState::default(),
            archives: crate::application::archive::ArchiveState::default(),
        }
    }
}

pub(crate) struct UserRefreshAttempt {
    pub(crate) id: u64,
    pub(crate) started_at_unix_ms: u64,
    pub(crate) start_id: u64,
    pub(crate) end_id: Option<u64>,
    pub(crate) ticket: Option<devmil_git::model::ReadTicket<RepositorySnapshot>>,
    pub(crate) result: Option<NativeOperationCenterState>,
    pub(crate) finished_at_unix_ms: Option<u64>,
}

pub(crate) struct RepositorySessions {
    pub(crate) next_id: u64,
    pub(crate) active: HashMap<u64, OwnedRepositorySession>,
    pub(crate) retired: VecDeque<SessionKey>,
}

impl RepositorySessions {
    /// The session `session_id` of `generation`. A session that is gone or was reopened is
    /// stale for every caller: unknown, retired or of another generation.
    pub(crate) fn session(
        &self,
        key: SessionKey,
    ) -> Result<&OwnedRepositorySession, NativeRepositoryFailureKind> {
        match self.active.get(&key.id) {
            Some(session) if session.generation == key.generation => Ok(session),
            Some(_) => Err(NativeRepositoryFailureKind::StaleGeneration),
            None => Err(missing_session_kind(self, key.id, key.generation)),
        }
    }

    /// [`Self::session`] for a change to the session's state.
    pub(crate) fn session_mut(
        &mut self,
        key: SessionKey,
    ) -> Result<&mut OwnedRepositorySession, NativeRepositoryFailureKind> {
        let missing = missing_session_kind(self, key.id, key.generation);
        match self.active.get_mut(&key.id) {
            Some(session) if session.generation == key.generation => Ok(session),
            Some(_) => Err(NativeRepositoryFailureKind::StaleGeneration),
            None => Err(missing),
        }
    }
}

/// Runs `f` on the session `session_id` of `generation` under the registry lock. A missing or
/// reopened session fails the same way everywhere: as [`RepositorySessions::session`] says.
pub(crate) fn with_session<T>(
    session_id: u64,
    generation: u64,
    f: impl FnOnce(&mut OwnedRepositorySession) -> T,
) -> Result<T, NativeRepositoryFailureKind> {
    lock_sessions()
        .session_mut(SessionKey::new(session_id, generation))
        .map(f)
}

pub(crate) const RETIRED_SESSION_CAPACITY: usize = 128;
pub(crate) static REPOSITORY_SESSIONS: OnceLock<Mutex<RepositorySessions>> = OnceLock::new();

pub(crate) fn repository_sessions() -> &'static Mutex<RepositorySessions> {
    REPOSITORY_SESSIONS.get_or_init(|| {
        Mutex::new(RepositorySessions {
            next_id: 0,
            active: HashMap::new(),
            retired: VecDeque::new(),
        })
    })
}

pub(crate) fn lock_sessions() -> std::sync::MutexGuard<'static, RepositorySessions> {
    repository_sessions()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

#[must_use]
pub fn repository_session_open(path: String, generation: u64) -> NativeRepositoryOpenResult {
    repository_session_open_path(PathBuf::from(path), generation)
}

#[must_use]
pub fn repository_session_open_identity(
    identity: NativePathIdentity,
    generation: u64,
) -> NativeRepositoryOpenResult {
    // A remote workspace opens through its helper, never as a local path.
    if identity.remote.is_some() {
        return open_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let Some(path) = crate::domain::path_identity::native_path(&identity) else {
        return open_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    repository_session_open_path(path, generation)
}

pub(crate) fn repository_session_open_path(
    path: PathBuf,
    generation: u64,
) -> NativeRepositoryOpenResult {
    open_path_with_policy(path, generation, SessionPolicy::DESKTOP)
}

/// Opens the local repository at `identity` for a session that follows `policy`.
pub(crate) fn open_identity_with_policy(
    identity: NativePathIdentity,
    generation: u64,
    policy: SessionPolicy,
) -> NativeRepositoryOpenResult {
    if identity.remote.is_some() {
        return open_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let Some(path) = crate::domain::path_identity::native_path(&identity) else {
        return open_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    open_path_with_policy(path, generation, policy)
}

/// GitLama's own temporary files inside a repository (`.gitlama-patch-*`);
/// writing them never triggers a refresh.
pub(crate) fn temporary_paths() -> devmil_git::watch::TemporaryPathRules {
    devmil_git::watch::TemporaryPathRules {
        prefixes: vec![".gitlama-".into()],
        suffixes: Vec::new(),
    }
}

pub(crate) fn open_path_with_policy(
    path: PathBuf,
    generation: u64,
    policy: SessionPolicy,
) -> NativeRepositoryOpenResult {
    let activity = ActivityStore::default();
    let options = RepositoryOptions {
        temporary_paths: temporary_paths(),
        activity_sink: Some(activity.sink()),
        activity_id: Some(Arc::new(allocate_activity_id)),
        cache_bytes: policy.cache_bytes,
        refresh_read_policy: devmil_git::model::RefreshReadPolicy::ConcurrentScoped,
        index_refresh: if policy.private_index_refresh {
            devmil_git::model::IndexRefreshPolicy::PrivateOnly
        } else {
            devmil_git::model::IndexRefreshPolicy::InstallOnce
        },
        ..RepositoryOptions::default()
    };
    repository_session_open_with_options(path, generation, options, activity)
}

#[must_use]
pub fn repository_initialize(
    path: String,
    initial_branch: String,
    bare: bool,
    generation: u64,
) -> NativeRepositoryOpenResult {
    if generation == 0 || !crate::repository_init::valid_initial_branch(&initial_branch) {
        return open_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let destination = PathBuf::from(path);
    let activity = ActivityStore::default();
    if let Err(kind) = crate::repository_init::initialize_repository(
        &destination,
        &initial_branch,
        bare,
        &activity,
    ) {
        return open_failure(kind);
    }
    let repository_path = match RepositoryPath::new(&destination) {
        Ok(path) => path,
        Err(_) => return open_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let request = DiscoveryRequest {
        path: repository_path,
        discover_parents: false,
    };
    let activity_sink = activity.sink();
    let mut sink = move |event| activity_sink(event);
    let discovered = match RepositoryDiscovery::default().discover(&request, &mut |command| {
        ActivityGitRunner::run(command, allocate_activity_id(), None, &mut sink)
    }) {
        Ok(discovered) => discovered,
        Err(error) => return open_failure(map_discovery_error_kind(error.kind)),
    };
    let options = RepositoryOptions {
        temporary_paths: temporary_paths(),
        activity_sink: Some(activity.sink()),
        activity_id: Some(Arc::new(allocate_activity_id)),
        cache_bytes: 512 * 1024 * 1024,
        refresh_read_policy: devmil_git::model::RefreshReadPolicy::ConcurrentScoped,
        ..RepositoryOptions::default()
    };
    let repository = match Repository::from_discovered(discovered, options) {
        Ok(repository) => repository,
        Err(error) => return open_failure(map_error_kind(error.kind)),
    };
    repository_session_start(repository, generation, activity)
}

pub(crate) fn repository_session_open_with_options(
    path: PathBuf,
    generation: u64,
    options: RepositoryOptions,
    activity: ActivityStore,
) -> NativeRepositoryOpenResult {
    if generation == 0 {
        return open_failure(NativeRepositoryFailureKind::InvalidGeneration);
    }
    let repository_path = match RepositoryPath::new(&path) {
        Ok(path) => path,
        Err(_) => return open_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let request = DiscoveryRequest {
        path: repository_path,
        discover_parents: options.discover_parents,
    };
    let discovery = RepositoryDiscovery::new(options.git_executable.clone());
    let activity_sink = activity.sink();
    let mut sink = move |event| activity_sink(event);
    let discovered = match discovery.discover(&request, &mut |command| {
        ActivityGitRunner::run(command, allocate_activity_id(), None, &mut sink)
    }) {
        Ok(discovered) => discovered,
        Err(error) => return open_failure(map_discovery_error_kind(error.kind)),
    };
    let repository = match Repository::from_discovered(discovered, options) {
        Ok(repository) => repository,
        Err(error) => return open_failure(map_error_kind(error.kind)),
    };
    repository_session_start(repository, generation, activity)
}

pub(crate) fn repository_session_start(
    repository: Repository,
    generation: u64,
    activity: ActivityStore,
) -> NativeRepositoryOpenResult {
    let repository = Arc::new(repository);
    let subscription = repository.subscribe();
    if let Err(error) = repository.load() {
        repository.close();
        return open_failure(map_error_kind(error.kind));
    }
    let snapshot = map_snapshot(&repository.snapshot());
    let mut sessions = lock_sessions();
    sessions.next_id = sessions.next_id.saturating_add(1).max(1);
    let session_id = sessions.next_id;
    sessions.active.insert(
        session_id,
        OwnedRepositorySession::new(generation, repository, subscription, activity),
    );
    NativeRepositoryOpenResult {
        session: Some(NativeRepositorySession {
            session_id,
            generation,
            snapshot,
        }),
        failure: None,
    }
}

pub(crate) fn open_discovered_repository(
    discovered: devmil_git::repository::DiscoveredRepository,
    generation: u64,
    activity: ActivityStore,
) -> NativeRepositoryOpenResult {
    if generation == 0 {
        return open_failure(NativeRepositoryFailureKind::InvalidGeneration);
    }
    let options = RepositoryOptions {
        temporary_paths: temporary_paths(),
        activity_sink: Some(activity.sink()),
        activity_id: Some(Arc::new(allocate_activity_id)),
        cache_bytes: 512 * 1024 * 1024,
        refresh_read_policy: devmil_git::model::RefreshReadPolicy::ConcurrentScoped,
        ..RepositoryOptions::default()
    };
    let repository = match Repository::from_discovered(discovered, options) {
        Ok(repository) => repository,
        Err(error) => return open_failure(map_error_kind(error.kind)),
    };
    repository_session_start(repository, generation, activity)
}

#[must_use]
pub fn repository_session_activity(
    session_id: u64,
    generation: u64,
    maximum_records: u32,
) -> NativeRepositoryActivityResult {
    if maximum_records == 0 || maximum_records > ACTIVITY_PAGE_CAPACITY {
        return activity_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return activity_failure(kind),
    };
    NativeRepositoryActivityResult {
        page: session.activity.page(maximum_records),
        failure: None,
    }
}

/// Loads one retained command, including its bounded output, by activity identity.
#[must_use]
pub fn repository_session_activity_record(
    session_id: u64,
    generation: u64,
    activity_id: u64,
) -> NativeRepositoryActivityResult {
    if activity_id == 0 {
        return activity_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return activity_failure(kind),
    };
    NativeRepositoryActivityResult {
        page: Some(session.activity.record(activity_id)),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_events(
    session_id: u64,
    generation: u64,
    maximum_events: u32,
) -> NativeRepositoryEventsResult {
    if maximum_events == 0 || maximum_events > 256 {
        return events_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return events_failure(kind),
    };
    let mut events = Vec::new();
    while events.len() < maximum_events as usize {
        let Some(event) = session.subscription.try_recv() else {
            break;
        };
        if let RepositoryEvent::Snapshot(snapshot) | RepositoryEvent::Resynchronize(snapshot) =
            &event
        {
            if let Some(history) = session.history.projection.as_mut() {
                history.stash_refs = history_ref_decorations(&snapshot.refs);
            }
        }
        events.push(map_event(event));
    }
    NativeRepositoryEventsResult {
        events,
        failure: None,
    }
}

#[must_use]
pub fn repository_session_refresh(
    session_id: u64,
    generation: u64,
) -> NativeRepositoryCommandResult {
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return command_failure(kind),
    };
    let id = allocate_activity_id().get();
    let start_id = crate::activity::next_activity_id();
    match session.repository.reload() {
        Ok(ticket) => {
            if session.operations.user_refreshes.len() >= 256 {
                let oldest = session.operations.user_refreshes.remove(0);
                session.operations.dismissed.remove(&oldest.id);
            }
            session.operations.user_refreshes.push(UserRefreshAttempt {
                id,
                started_at_unix_ms: crate::clock::unix_millis(),
                start_id,
                end_id: None,
                ticket: Some(ticket),
                result: None,
                finished_at_unix_ms: None,
            });
            NativeRepositoryCommandResult {
                accepted: true,
                failure: None,
            }
        }
        Err(error) => {
            session.operations.user_refreshes.push(UserRefreshAttempt {
                id,
                started_at_unix_ms: crate::clock::unix_millis(),
                start_id,
                end_id: Some(start_id),
                ticket: None,
                result: Some(NativeOperationCenterState::Failed),
                finished_at_unix_ms: Some(crate::clock::unix_millis()),
            });
            command_failure(map_error_kind(error.kind))
        }
    }
}

#[must_use]
pub fn repository_session_close(session_id: u64, generation: u64) -> NativeRepositoryCommandResult {
    let mut sessions = lock_sessions();
    if let Some(session) = sessions.active.get(&session_id) {
        if session.generation != generation {
            return command_failure(NativeRepositoryFailureKind::StaleGeneration);
        }
    } else if sessions
        .retired
        .iter()
        .any(|retired| *retired == SessionKey::new(session_id, generation))
    {
        return NativeRepositoryCommandResult {
            accepted: false,
            failure: None,
        };
    } else {
        return command_failure(missing_session_kind(&sessions, session_id, generation));
    }
    let session = sessions
        .active
        .remove(&session_id)
        .expect("session presence checked");
    sessions
        .retired
        .push_back(SessionKey::new(session_id, generation));
    while sessions.retired.len() > RETIRED_SESSION_CAPACITY {
        sessions.retired.pop_front();
    }
    drop(sessions);
    // The session's own previews go with it; the families' stores are dismissed here.
    dismiss_family_work(session_id);
    session.repository.close();
    NativeRepositoryCommandResult {
        accepted: true,
        failure: None,
    }
}

/// The one place a closed session's previews and running work end in every family: each
/// family's [`crate::preview_store::PreviewStore`] cancels running work and drops its previews.
fn dismiss_family_work(session_id: u64) {
    crate::transfer::dismiss_session(session_id);
    crate::stash::dismiss_session(session_id);
    crate::named_snapshot::dismiss_session(session_id);
    crate::history_operation::dismiss_session(session_id);
    crate::rebase_operation::dismiss_session(session_id);
    crate::conflict::dismiss_session(session_id);
    crate::advanced_rebase::dismiss_session(session_id);
    crate::integrations::dismiss_session(session_id);
    crate::power_tools::dismiss_session(session_id);
    crate::diff_renderer::dismiss_session(session_id);
    crate::image_decoder::cancel_session(session_id);
    crate::diff_syntax::cancel_session(session_id);
}

pub(crate) fn open_failure(kind: NativeRepositoryFailureKind) -> NativeRepositoryOpenResult {
    NativeRepositoryOpenResult {
        session: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) fn events_failure(kind: NativeRepositoryFailureKind) -> NativeRepositoryEventsResult {
    NativeRepositoryEventsResult {
        events: Vec::new(),
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) fn command_failure(kind: NativeRepositoryFailureKind) -> NativeRepositoryCommandResult {
    NativeRepositoryCommandResult {
        accepted: false,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) fn activity_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeRepositoryActivityResult {
    NativeRepositoryActivityResult {
        page: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) fn missing_session_kind(
    sessions: &RepositorySessions,
    session_id: u64,
    generation: u64,
) -> NativeRepositoryFailureKind {
    if sessions
        .retired
        .iter()
        .any(|retired| *retired == SessionKey::new(session_id, generation))
    {
        NativeRepositoryFailureKind::RetiredSession
    } else {
        NativeRepositoryFailureKind::UnknownSession
    }
}

pub(crate) fn map_event(event: RepositoryEvent) -> NativeRepositoryEvent {
    match event {
        RepositoryEvent::Snapshot(snapshot) => NativeRepositoryEvent {
            kind: NativeRepositoryEventKind::Snapshot,
            snapshot: Some(map_snapshot(&snapshot)),
            read_id: None,
            cache_hit: false,
            watch_overflow_revision: None,
        },
        RepositoryEvent::Resynchronize(snapshot) => NativeRepositoryEvent {
            kind: NativeRepositoryEventKind::Resynchronize,
            snapshot: Some(map_snapshot(&snapshot)),
            read_id: None,
            cache_hit: false,
            watch_overflow_revision: None,
        },
        RepositoryEvent::ReadCompleted { id, cache_hit } => NativeRepositoryEvent {
            kind: NativeRepositoryEventKind::ReadCompleted,
            snapshot: None,
            read_id: Some(id),
            cache_hit,
            watch_overflow_revision: None,
        },
        RepositoryEvent::WatchOverflow { revision } => NativeRepositoryEvent {
            kind: NativeRepositoryEventKind::WatchOverflow,
            snapshot: None,
            read_id: None,
            cache_hit: false,
            watch_overflow_revision: Some(revision),
        },
    }
}

/// The repository handle of a session.
pub(crate) fn repository_for_session(
    session_id: u64,
    generation: u64,
) -> Result<Arc<Repository>, NativeRepositoryFailureKind> {
    with_session(session_id, generation, |session| {
        Arc::clone(&session.repository)
    })
}

pub(crate) fn session_is_current(session_id: u64, generation: u64) -> bool {
    with_session(session_id, generation, |_| ()).is_ok()
}

/// The repository handle and activity store of a session, for use cases that run Git.
pub(crate) fn session_repository_and_activity(
    session_id: u64,
    generation: u64,
) -> Result<(Arc<Repository>, ActivityStore), NativeRepositoryFailureKind> {
    with_session(session_id, generation, |session| {
        (Arc::clone(&session.repository), session.activity.clone())
    })
}

pub(crate) fn repository_and_activity(
    session_id: u64,
    generation: u64,
) -> Option<(Arc<Repository>, ActivityStore)> {
    session_repository_and_activity(session_id, generation).ok()
}

/// The session registry as the clone's [`crate::clone::SessionOpener`].
pub struct SessionRegistry;

impl crate::clone::SessionOpener for SessionRegistry {
    fn open(
        &self,
        discovered: devmil_git::repository::DiscoveredRepository,
        generation: u64,
        activity: ActivityStore,
    ) -> NativeRepositoryOpenResult {
        open_discovered_repository(discovered, generation, activity)
    }
}

/// Opens the local repository at `identity` for a session that follows `policy`.
#[must_use]
pub fn open_identity(
    identity: NativePathIdentity,
    generation: u64,
    policy: SessionPolicy,
) -> NativeRepositoryOpenResult {
    open_identity_with_policy(identity, generation, policy)
}

/// Reloads a session's snapshot, waits for it and then until the repository worker has been
/// idle for a quiet period: a refresh the watcher schedules for an operation's own writes would
/// otherwise publish a newer revision right after this one. False when the session is gone or
/// the reload did not finish in time.
/// Brings a session's snapshot up to date before a write is previewed. The helper has no
/// file watcher, so a preview would otherwise plan against the state of the last refresh.
#[must_use]
pub fn reload_snapshot(session_id: u64, generation: u64) -> bool {
    /// Longer than two watcher debounce periods.
    const QUIET: Duration = Duration::from_millis(250);
    const SETTLE_LIMIT: u32 = 8;
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return false;
    };
    let reloaded = repository
        .reload()
        .ok()
        .and_then(|ticket| ticket.recv_timeout(Duration::from_secs(5)))
        .is_some_and(|result| result.is_ok());
    if !reloaded {
        return false;
    }
    // A worker that stays busy past the limit leaves the reloaded snapshot as it is.
    !matches!(
        repository.wait_until_idle(QUIET, QUIET * SETTLE_LIMIT),
        Err(error) if error.kind == devmil_git::RepositoryErrorKind::Closed
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_missing_session_is_stale_the_same_way_everywhere() {
        // No session has this identity; families report it as their stale state.
        let unknown = u64::MAX - 7;
        assert_eq!(
            repository_for_session(unknown, 1).err(),
            Some(NativeRepositoryFailureKind::UnknownSession)
        );
        assert_eq!(
            with_session(unknown, 1, |_| ()).err(),
            Some(NativeRepositoryFailureKind::UnknownSession)
        );
        let stash = crate::application::stash::repository_session_stash_preview(
            unknown,
            1,
            crate::stash::NativeStashRequest {
                kind: crate::stash::NativeStashKind::Push,
                message: None,
                selector: None,
                object_id: None,
                paths: Vec::new(),
                include_untracked: false,
                keep_index: false,
                target_branch: None,
            },
        );
        assert_eq!(
            stash.failure.map(|failure| failure.kind),
            Some(crate::stash::NativeStashFailureKind::Stale)
        );
        let conflicts = crate::application::conflicts::repository_session_conflicts(unknown, 1);
        assert_eq!(
            conflicts.failure.map(|failure| failure.kind),
            Some(crate::conflict::NativeConflictFailureKind::Stale)
        );
        let snapshots =
            crate::application::snapshots::repository_session_named_snapshot_delete(unknown, 1, 1);
        assert_eq!(
            snapshots.failure.map(|failure| failure.kind),
            Some(crate::named_snapshot::NativeNamedSnapshotFailureKind::Stale)
        );
    }

    #[test]
    fn a_retired_session_is_told_apart_from_an_unknown_one() {
        let mut sessions = RepositorySessions {
            next_id: 0,
            active: HashMap::new(),
            retired: VecDeque::from([SessionKey::new(5, 2)]),
        };
        assert_eq!(
            sessions.session(SessionKey::new(5, 2)).err(),
            Some(NativeRepositoryFailureKind::RetiredSession)
        );
        assert_eq!(
            sessions.session_mut(SessionKey::new(5, 3)).err(),
            Some(NativeRepositoryFailureKind::UnknownSession)
        );
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{paths::*, session::*};

    use devmil_git::repository::DiscoveryErrorKind;

    use devmil_git::{
        Repository, RepositoryErrorKind, RepositoryEvent, RepositoryOptions, RepositoryPhase,
        RepositorySnapshot,
    };

    use std::fs;

    use std::process::Command;
    use std::sync::atomic::AtomicU64;
    use std::sync::atomic::Ordering;
    use std::sync::Arc;
    use std::time::Duration;
    use std::time::Instant;

    #[test]
    fn session_subscribes_before_load_and_reaches_ready() {
        let fixture = GitFixture::new();
        let options = RepositoryOptions {
            watch: false,
            ..RepositoryOptions::default()
        };
        let opened = repository_session_open_with_options(
            fixture.0.clone(),
            11,
            options,
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        assert_eq!(session.generation, 11);
        let deadline = Instant::now() + Duration::from_secs(30);
        let mut phases = Vec::new();
        while Instant::now() < deadline {
            let result = repository_session_events(session.session_id, 11, 32);
            assert!(result.failure.is_none());
            for event in result.events {
                if let Some(snapshot) = event.snapshot {
                    phases.push(snapshot.phase);
                }
            }
            if phases.contains(&NativeRepositoryPhase::Ready) {
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(phases.first() == Some(&NativeRepositoryPhase::Unloaded));
        assert!(phases.contains(&NativeRepositoryPhase::Ready));
        assert!(repository_session_close(session.session_id, 11).accepted);
    }

    #[test]
    fn stale_and_retired_generations_cannot_publish() {
        let fixture = GitFixture::new();
        let opened = repository_session_open_with_options(
            fixture.0.clone(),
            21,
            RepositoryOptions::default(),
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        assert_eq!(
            repository_session_events(session.session_id, 22, 8)
                .failure
                .unwrap()
                .kind,
            NativeRepositoryFailureKind::StaleGeneration
        );
        assert!(repository_session_close(session.session_id, 21).accepted);
        assert_eq!(
            repository_session_events(session.session_id, 21, 8)
                .failure
                .unwrap()
                .kind,
            NativeRepositoryFailureKind::RetiredSession
        );
        let duplicate = repository_session_close(session.session_id, 21);
        assert!(!duplicate.accepted);
        assert!(duplicate.failure.is_none());
    }

    #[test]
    fn resynchronize_event_replaces_with_current_snapshot() {
        let snapshot = Arc::new(RepositorySnapshot {
            revision: 42,
            phase: RepositoryPhase::Ready,
            ..RepositorySnapshot::default()
        });
        let mapped = map_event(RepositoryEvent::Resynchronize(snapshot));
        assert_eq!(mapped.kind, NativeRepositoryEventKind::Resynchronize);
        assert_eq!(mapped.snapshot.unwrap().revision, 42);
    }

    #[test]
    fn initialize_opens_unborn_worktree_without_rediscovery() {
        let fixture = GitFixture::new();
        let destination = fixture.0.join("new repository ü");
        let opened = repository_initialize(
            destination.to_string_lossy().into_owned(),
            "main".into(),
            false,
            31,
        );
        let session = opened.session.unwrap();
        let snapshot = wait_for_ready(&session);
        let identity = snapshot.identity.unwrap();
        assert_eq!(identity.kind, NativeRepositoryKind::Worktree);
        assert_eq!(identity.head_kind, NativeHeadKind::Unborn);
        assert_eq!(identity.head_reference, Some(b"refs/heads/main".to_vec()));
        assert!(identity.git_major >= 2);
        assert!(repository_session_close(session.session_id, 31).accepted);
    }

    #[test]
    fn initialize_distinguishes_existing_nonempty_and_bare_destinations() {
        let fixture = GitFixture::new();
        assert_eq!(
            repository_initialize(
                fixture.0.to_string_lossy().into_owned(),
                "main".into(),
                false,
                41,
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::ExistingRepository
        );

        let occupied = fixture.0.join("occupied");
        fs::create_dir(&occupied).unwrap();
        fs::write(occupied.join("keep"), b"not a repository").unwrap();
        assert_eq!(
            repository_initialize(
                occupied.to_string_lossy().into_owned(),
                "main".into(),
                false,
                42,
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::DestinationNotEmpty
        );
        assert_eq!(
            fs::read(occupied.join("keep")).unwrap(),
            b"not a repository"
        );

        let bare = fixture.0.join("bare.git");
        let opened =
            repository_initialize(bare.to_string_lossy().into_owned(), "main".into(), true, 43);
        let session = opened.session.unwrap();
        let identity = wait_for_ready(&session).identity.unwrap();
        assert_eq!(identity.kind, NativeRepositoryKind::Bare);
        assert_eq!(identity.head_kind, NativeHeadKind::Unborn);
        assert!(repository_session_close(session.session_id, 43).accepted);
    }

    #[test]
    fn construction_is_lazy_and_missing_git_is_a_typed_load_failure() {
        let activity_count = Arc::new(AtomicU64::new(0));
        let observed = Arc::clone(&activity_count);
        let options = RepositoryOptions {
            git_executable: "gitlama-definitely-missing-git".into(),
            watch: false,
            activity_sink: Some(Arc::new(move |_| {
                observed.fetch_add(1, Ordering::Relaxed);
            })),
            ..RepositoryOptions::default()
        };
        let activity = ActivityStore::default();
        let repository = Repository::new("path-not-touched-during-construction", options).unwrap();
        assert_eq!(repository.snapshot().phase, RepositoryPhase::Unloaded);
        assert_eq!(activity_count.load(Ordering::Relaxed), 0);
        let opened = repository_session_start(repository, 51, activity);
        let session = opened.session.unwrap();
        let failed = wait_for_phase(&session, NativeRepositoryPhase::Failed);
        assert_eq!(
            failed.failure.unwrap().kind,
            NativeRepositoryFailureKind::Discovery
        );
        assert!(repository_session_close(session.session_id, 51).accepted);
    }

    #[test]
    fn open_projects_exact_discovery_failures_without_private_message_parsing() {
        assert_eq!(
            map_discovery_error_kind(DiscoveryErrorKind::NotFound),
            NativeRepositoryFailureKind::PathNotFound
        );
        assert_eq!(
            map_discovery_error_kind(DiscoveryErrorKind::AccessDenied),
            NativeRepositoryFailureKind::PermissionDenied
        );
        assert_eq!(
            map_discovery_error_kind(DiscoveryErrorKind::NotRepository),
            NativeRepositoryFailureKind::NotRepository
        );
        assert_eq!(
            map_discovery_error_kind(DiscoveryErrorKind::GitMissing),
            NativeRepositoryFailureKind::MissingGit
        );
        assert_eq!(
            map_error_kind(RepositoryErrorKind::Unsupported),
            NativeRepositoryFailureKind::Unsupported
        );

        let missing = fixture_path("missing-open");
        assert_eq!(
            repository_session_open_with_options(
                missing,
                52,
                RepositoryOptions::default(),
                ActivityStore::default(),
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::PathNotFound
        );

        let not_repository = fixture_path("not-repository");
        fs::create_dir(&not_repository).unwrap();
        assert_eq!(
            repository_session_open_with_options(
                not_repository.clone(),
                53,
                RepositoryOptions::default(),
                ActivityStore::default(),
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::NotRepository
        );
        fs::remove_dir(&not_repository).unwrap();

        let fixture = GitFixture::new();
        assert_eq!(
            repository_session_open_with_options(
                fixture.0.clone(),
                54,
                RepositoryOptions {
                    git_executable: "gitlama-definitely-missing-git".into(),
                    watch: false,
                    ..RepositoryOptions::default()
                },
                ActivityStore::default(),
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::MissingGit
        );
    }

    #[cfg(unix)]
    #[test]
    fn aliases_and_non_utf8_paths_resolve_to_native_canonical_identity() {
        use std::os::unix::fs::symlink;

        let fixture = GitFixture::new();
        let alias = fixture_path("session-alias");
        symlink(&fixture.0, &alias).unwrap();
        let first = repository_session_open_with_options(
            fixture.0.clone(),
            61,
            RepositoryOptions::default(),
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let second = repository_session_open_with_options(
            alias.clone(),
            62,
            RepositoryOptions::default(),
            ActivityStore::default(),
        )
        .session
        .unwrap();
        assert_eq!(
            wait_for_ready(&first).identity,
            wait_for_ready(&second).identity
        );
        assert!(repository_session_close(first.session_id, 61).accepted);
        assert!(repository_session_close(second.session_id, 62).accepted);
        fs::remove_file(alias).unwrap();

        #[cfg(target_os = "linux")]
        {
            use std::os::unix::ffi::OsStringExt;
            let native = fixture
                .0
                .join(std::ffi::OsString::from_vec(vec![b'n', 0x80, b'z']));
            fs::create_dir(&native).unwrap();
            let output = Command::new("git")
                .args(["init", "-q", "-b", "main"])
                .current_dir(&native)
                .output()
                .unwrap();
            assert!(output.status.success());
            let opened = repository_session_open_with_options(
                native,
                63,
                RepositoryOptions::default(),
                ActivityStore::default(),
            )
            .session
            .unwrap();
            assert_eq!(
                wait_for_ready(&opened).identity.unwrap().head_kind,
                NativeHeadKind::Unborn
            );
            assert!(repository_session_close(opened.session_id, 63).accepted);
        }
    }

    #[test]
    fn external_write_converges_through_shared_watcher_without_app_polling() {
        let fixture = GitFixture::new();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            72,
            RepositoryOptions::default(),
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let ready = wait_for_ready(&session);
        assert_eq!(ready.status.unwrap().total_entries, 0);

        fs::write(fixture.0.join("external.txt"), b"external\n").unwrap();
        let deadline = Instant::now() + Duration::from_secs(10);
        let mut converged = false;
        while Instant::now() < deadline {
            let result = repository_session_events(session.session_id, 72, 32);
            assert!(result.failure.is_none());
            for event in result.events {
                if let Some(snapshot) = event.snapshot {
                    if snapshot.phase == NativeRepositoryPhase::Ready
                        && snapshot
                            .status
                            .as_ref()
                            .is_some_and(|status| status.total_entries == 1)
                    {
                        converged = true;
                        break;
                    }
                }
            }
            if converged {
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let latest = repository_for_session(session.session_id, 72)
            .ok()
            .map(|repository| map_snapshot(&repository.snapshot()));
        assert!(
            converged,
            "shared watcher did not project external write: phase={:?}, status_entries={:?}, watch_failure={:?}",
            latest.as_ref().map(|snapshot| snapshot.phase),
            latest
                .as_ref()
                .and_then(|snapshot| snapshot.status.as_ref())
                .map(|status| status.total_entries),
            latest
                .as_ref()
                .and_then(|snapshot| snapshot.watch_failure.as_ref())
                .map(|failure| failure.kind),
        );
        assert!(repository_session_close(session.session_id, 72).accepted);
    }

    #[test]
    fn refresh_flood_after_external_git_stage_is_bounded_and_session_scoped() {
        let first_fixture = GitFixture::new();
        let second_fixture = GitFixture::new();
        let options = || RepositoryOptions {
            watch: false,
            ..RepositoryOptions::default()
        };
        let first = repository_session_open_with_options(
            first_fixture.0.clone(),
            73,
            options(),
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let second = repository_session_open_with_options(
            second_fixture.0.clone(),
            74,
            options(),
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let first_ready = wait_for_ready(&first);
        let second_ready = wait_for_ready(&second);

        fs::write(first_fixture.0.join("staged.txt"), b"staged\n").unwrap();
        assert!(Command::new("git")
            .args(["add", "--", "staged.txt"])
            .current_dir(&first_fixture.0)
            .output()
            .unwrap()
            .status
            .success());
        for _ in 0..128 {
            assert!(repository_session_refresh(first.session_id, 73).accepted);
        }

        let deadline = Instant::now() + Duration::from_secs(10);
        let mut snapshot_publications = 0;
        let mut converged = false;
        while Instant::now() < deadline {
            let result = repository_session_events(first.session_id, 73, 32);
            assert!(result.failure.is_none());
            for event in result.events {
                if let Some(snapshot) = event.snapshot {
                    snapshot_publications += 1;
                    if snapshot.revision > first_ready.revision
                        && snapshot.phase == NativeRepositoryPhase::Ready
                        && snapshot.status.as_ref().is_some_and(|status| {
                            status.total_entries == 1
                                && status.entries[0].index == NativeChangeKind::Added
                        })
                    {
                        converged = true;
                    }
                }
            }
            if converged {
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(converged, "refresh did not project externally staged file");
        assert!(
            snapshot_publications <= 8,
            "refresh flood published {snapshot_publications} snapshots"
        );
        let second_events = repository_session_events(second.session_id, 74, 32);
        assert!(second_events.failure.is_none());
        assert!(second_events.events.is_empty());
        assert_eq!(second_ready.status.unwrap().total_entries, 0);
        assert!(repository_session_close(first.session_id, 73).accepted);
        assert!(repository_session_close(second.session_id, 74).accepted);
    }

    #[test]
    fn remote_path_never_becomes_local_path_when_opening_identity() {
        let fixture = GitFixture::new();
        let local = crate::domain::path_identity::native_path_identity(&fixture.0);
        let remote = remote_identity_of(&local);

        // The same units name an existing local repository, yet the remote
        // identity is refused before any discovery.
        let refused = repository_session_open_identity(remote.clone(), 31_001);
        assert!(refused.session.is_none());
        assert_eq!(
            refused.failure.map(|failure| failure.kind),
            Some(NativeRepositoryFailureKind::InvalidOptions)
        );
        assert_eq!(crate::domain::path_identity::native_path(&remote), None);
        assert_eq!(native_identity_bytes(&remote), None);
        assert!(native_identity_bytes(&local).is_some());

        let session = repository_session_open_identity(local, 31_002)
            .session
            .expect("the local identity opens");
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }
}
