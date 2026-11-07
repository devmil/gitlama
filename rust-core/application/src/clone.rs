//! Application-owned clone attempts around the shared process and validation contracts.
pub use gitlama_contract::clone::*;

use crate::activity::{allocate_activity_id, ActivityStore};
use crate::credentials::AskpassLease;
use crate::dto::NativeCloneCommandResult;
use crate::dto::NativeCloneFailure;
use crate::dto::NativeCloneFailureKind;
use crate::dto::NativeHostKeyResult;
use crate::dto::{NativeRepositoryFailureKind, NativeRepositoryOpenResult};
use crate::ssh_trust::ensure_strict_ssh_wrapper;
use crate::ssh_trust::probe_host_key_with_executables;
use crate::ssh_trust::trust_host_key;
use crate::ssh_trust::PendingHostKey;
use devmil_git::activity::ActivityStatus;
use devmil_git::auth::{
    shell_command_path, transfer_configuration, transfer_environment, Credentials,
    TransferAuthentication,
};
use devmil_git::clone::{CloneDestination, CloneSource, CloneValidationError, InitialBranch};
use devmil_git::commands::remote::{RemoteEnvironment, RemoteOperationError};
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument, SemanticTimeout};
use devmil_git::repository::{DiscoveryRequest, RepositoryDiscovery};
use devmil_git::transfer::{classify_clone_stderr, TransferFailureKind};
use devmil_git::types::RepositoryPath;
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

const ATTEMPT_CAPACITY: usize = 64;

struct OwnedCloneAttempt {
    generation: u64,
    source: CloneSource,
    destination: CloneDestination,
    initial_branch: Option<InitialBranch>,
    state: NativeCloneState,
    failure: Option<NativeCloneFailureKind>,
    partial_destination: bool,
    cancellation: Arc<AtomicBool>,
    activity: ActivityStore,
    pending_host_key: Option<PendingHostKey>,
    host_key_accepted: bool,
}

struct CloneAttempts {
    next_id: u64,
    order: VecDeque<u64>,
    attempts: HashMap<u64, OwnedCloneAttempt>,
}

static CLONE_ATTEMPTS: OnceLock<Mutex<CloneAttempts>> = OnceLock::new();

fn attempts() -> &'static Mutex<CloneAttempts> {
    CLONE_ATTEMPTS.get_or_init(|| {
        Mutex::new(CloneAttempts {
            next_id: 0,
            order: VecDeque::new(),
            attempts: HashMap::new(),
        })
    })
}

fn lock_attempts() -> std::sync::MutexGuard<'static, CloneAttempts> {
    attempts()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

pub(crate) fn clone_operation_snapshots() -> Vec<NativeCloneSnapshot> {
    let registry = lock_attempts();
    registry
        .order
        .iter()
        .filter_map(|attempt_id| {
            registry
                .attempts
                .get(attempt_id)
                .map(|attempt| project_attempt(*attempt_id, attempt))
        })
        .collect()
}

pub(crate) fn dismiss_failed_clone_operations() {
    let mut registry = lock_attempts();
    let failed = registry
        .order
        .iter()
        .copied()
        .filter(|attempt_id| {
            registry
                .attempts
                .get(attempt_id)
                .is_some_and(|attempt| attempt.state == NativeCloneState::Failed)
        })
        .collect::<Vec<_>>();
    for attempt_id in failed {
        registry.attempts.remove(&attempt_id);
        registry.order.retain(|id| *id != attempt_id);
    }
}

#[must_use]
pub fn clone_create(
    source: String,
    destination: String,
    initial_branch: Option<String>,
    generation: u64,
) -> NativeCloneCreateResult {
    if generation == 0 {
        return create_failure(NativeCloneFailureKind::InvalidAttemptState);
    }
    let source = match CloneSource::parse(source) {
        Ok(source) => source,
        Err(error) => return create_failure(map_validation(error)),
    };
    let destination_path = PathBuf::from(destination);
    let repository_path = match RepositoryPath::new(&destination_path) {
        Ok(path) => path,
        Err(_) => return create_failure(NativeCloneFailureKind::InvalidDestination),
    };
    let destination = match CloneDestination::new(repository_path) {
        Ok(destination) => destination,
        Err(error) => return create_failure(map_validation(error)),
    };
    if !destination_available(destination.path().as_path()) {
        return create_failure(NativeCloneFailureKind::DestinationOccupied);
    }
    let initial_branch = match initial_branch {
        Some(branch) => match InitialBranch::parse(branch) {
            Ok(branch) => Some(branch),
            Err(error) => return create_failure(map_validation(error)),
        },
        None => None,
    };
    let mut registry = lock_attempts();
    evict_finished(&mut registry);
    if registry.attempts.len() >= ATTEMPT_CAPACITY {
        return create_failure(NativeCloneFailureKind::AttemptCapacity);
    }
    registry.next_id = registry.next_id.saturating_add(1).max(1);
    let attempt_id = registry.next_id;
    registry.order.push_back(attempt_id);
    registry.attempts.insert(
        attempt_id,
        OwnedCloneAttempt {
            generation,
            source,
            destination,
            initial_branch,
            state: NativeCloneState::Pending,
            failure: None,
            partial_destination: false,
            cancellation: Arc::new(AtomicBool::new(false)),
            activity: ActivityStore::default(),
            pending_host_key: None,
            host_key_accepted: false,
        },
    );
    NativeCloneCreateResult {
        snapshot: registry
            .attempts
            .get(&attempt_id)
            .map(|attempt| project_attempt(attempt_id, attempt)),
        failure: None,
    }
}

/// Opens the repository session of a finished clone. The application's session registry
/// implements it, so the clone never reaches the registry or an adapter itself.
pub trait SessionOpener {
    fn open(
        &self,
        discovered: devmil_git::repository::DiscoveredRepository,
        generation: u64,
        activity: ActivityStore,
    ) -> NativeRepositoryOpenResult;
}

#[must_use]
pub fn clone_run(
    opener: &dyn SessionOpener,
    attempt_id: u64,
    generation: u64,
) -> NativeCloneRunResult {
    clone_run_with_executable(opener, attempt_id, generation, "git")
}

#[must_use]
pub fn clone_run_with_credentials(
    opener: &dyn SessionOpener,
    attempt_id: u64,
    generation: u64,
    username: Option<String>,
    password: Option<String>,
    token: Option<String>,
) -> NativeCloneRunResult {
    let Some(credentials) = Credentials::new(username, password, token) else {
        return run_failure(NativeCloneFailureKind::CredentialBrokerUnavailable);
    };
    let lease = match AskpassLease::new(attempt_id, &credentials) {
        Ok(lease) => lease,
        Err(_) => return run_failure(NativeCloneFailureKind::CredentialBrokerUnavailable),
    };
    let ssh_wrapper = {
        let registry = lock_attempts();
        registry
            .attempts
            .get(&attempt_id)
            .is_some_and(|attempt| attempt.host_key_accepted)
            .then(ensure_strict_ssh_wrapper)
            .transpose()
    };
    let ssh_wrapper = match ssh_wrapper {
        Ok(wrapper) => wrapper,
        Err(failure) => return run_failure(failure),
    };
    clone_run_configured(
        opener,
        attempt_id,
        generation,
        "git",
        Some(lease.executable()),
        ssh_wrapper.as_deref(),
        None,
    )
}

#[must_use]
pub fn clone_run_with_host_key(
    opener: &dyn SessionOpener,
    attempt_id: u64,
    generation: u64,
) -> NativeCloneRunResult {
    let wrapper = {
        let registry = lock_attempts();
        let Some(attempt) = registry.attempts.get(&attempt_id) else {
            return run_failure(NativeCloneFailureKind::UnknownAttempt);
        };
        if attempt.generation != generation || !attempt.host_key_accepted {
            return run_failure(NativeCloneFailureKind::InvalidAttemptState);
        }
        match ensure_strict_ssh_wrapper() {
            Ok(wrapper) => wrapper,
            Err(failure) => return run_failure(failure),
        }
    };
    clone_run_configured(
        opener,
        attempt_id,
        generation,
        "git",
        None,
        Some(wrapper.as_path()),
        None,
    )
}

fn clone_run_with_executable(
    opener: &dyn SessionOpener,
    attempt_id: u64,
    generation: u64,
    executable: impl Into<std::ffi::OsString>,
) -> NativeCloneRunResult {
    clone_run_configured(opener, attempt_id, generation, executable, None, None, None)
}

#[cfg(all(test, unix))]
fn clone_run_with_executable_and_idle_timeout(
    opener: &dyn SessionOpener,
    attempt_id: u64,
    generation: u64,
    executable: impl Into<std::ffi::OsString>,
    idle_timeout: Duration,
) -> NativeCloneRunResult {
    clone_run_configured(
        opener,
        attempt_id,
        generation,
        executable,
        None,
        None,
        Some(idle_timeout),
    )
}

fn clone_run_configured(
    opener: &dyn SessionOpener,
    attempt_id: u64,
    generation: u64,
    executable: impl Into<std::ffi::OsString>,
    askpass: Option<&Path>,
    ssh_wrapper: Option<&Path>,
    idle_timeout: Option<Duration>,
) -> NativeCloneRunResult {
    let executable = executable.into();
    let (source, destination, initial_branch, cancellation, activity) = {
        let mut registry = lock_attempts();
        let Some(attempt) = registry.attempts.get_mut(&attempt_id) else {
            return run_failure(NativeCloneFailureKind::UnknownAttempt);
        };
        if attempt.generation != generation || attempt.state != NativeCloneState::Pending {
            return run_failure(NativeCloneFailureKind::InvalidAttemptState);
        }
        if !destination_available(attempt.destination.path().as_path()) {
            attempt.state = NativeCloneState::Failed;
            attempt.failure = Some(NativeCloneFailureKind::DestinationOccupied);
            return NativeCloneRunResult {
                snapshot: Some(project_attempt(attempt_id, attempt)),
                session: None,
                failure: None,
            };
        }
        attempt.state = NativeCloneState::Running;
        (
            attempt.source.clone(),
            attempt.destination.clone(),
            attempt.initial_branch.clone(),
            Arc::clone(&attempt.cancellation),
            attempt.activity.clone(),
        )
    };

    let parent = destination
        .path()
        .as_path()
        .parent()
        .expect("validated clone destination has a parent");
    let reject_helper = std::env::temp_dir().join(format!(
        "gitlama-reject-askpass-{}-{attempt_id}",
        std::process::id()
    ));
    let environment = match clone_transfer_environment(&reject_helper, askpass, ssh_wrapper) {
        Ok(environment) => environment,
        Err(_) => {
            return finish_failure(
                attempt_id,
                NativeCloneFailureKind::Git,
                destination.path().as_path(),
            );
        }
    };
    let mut arguments = transfer_configuration(clone_authentication(askpass, ssh_wrapper))
        .iter()
        .map(|argument| ProcessArgument::visible(argument.value()))
        .collect::<Vec<_>>();
    // `git clone` has no `--initial-branch`; the requested branch is the one checked out.
    arguments.extend(
        devmil_git::clone::clone_arguments(&source, &destination, initial_branch.as_ref())
            .into_iter()
            .map(ProcessArgument::visible),
    );
    let mut command = GitProcessCommand::git(executable)
        .args(arguments)
        .current_dir(parent)
        .parse_git_progress(true)
        .output_limit(crate::activity::ACTIVITY_STREAM_BYTE_CAPACITY);
    if let Some(duration) = idle_timeout {
        command = command.output_idle_timeout(
            SemanticTimeout::new(duration, "Git transfer stalled")
                .expect("test timeout is non-zero"),
        );
    }
    for variable in environment {
        command = match command.env(variable.name(), variable.value()) {
            Ok(command) => command,
            Err(_) => {
                return finish_failure(
                    attempt_id,
                    NativeCloneFailureKind::Git,
                    destination.path().as_path(),
                );
            }
        };
    }
    let activity_sink = activity.sink();
    let mut sink = move |event| activity_sink(event);
    let result = ActivityGitRunner::run_private(
        command,
        crate::activity::allocate_operation_id(crate::activity::OperationIntent::Clone),
        Some(cancellation.as_ref()),
        &mut sink,
    );
    let process_failure = match &result.activity.status {
        ActivityStatus::Succeeded { .. } => None,
        ActivityStatus::LaunchError { .. } => Some(NativeCloneFailureKind::MissingGit),
        ActivityStatus::Canceled { .. } => Some(NativeCloneFailureKind::Canceled),
        ActivityStatus::TimedOut { .. } => Some(NativeCloneFailureKind::TimedOut),
        ActivityStatus::Failed { .. } => Some(match classify_clone_stderr(&result.stderr.bytes) {
            TransferFailureKind::Launch => NativeCloneFailureKind::MissingGit,
            TransferFailureKind::Authentication => NativeCloneFailureKind::Authentication,
            TransferFailureKind::HostKey => NativeCloneFailureKind::HostKey,
            TransferFailureKind::Canceled => NativeCloneFailureKind::Canceled,
            TransferFailureKind::Git | TransferFailureKind::MissingObject => {
                NativeCloneFailureKind::Git
            }
        }),
        ActivityStatus::Running => Some(NativeCloneFailureKind::Git),
    };
    if let Some(failure) = process_failure {
        return finish_failure(attempt_id, failure, destination.path().as_path());
    }

    let request = DiscoveryRequest {
        path: destination.path().clone(),
        discover_parents: false,
    };
    let activity_sink = activity.sink();
    let mut sink = move |event| activity_sink(event);
    let discovered = match RepositoryDiscovery::new("git").discover(&request, &mut |command| {
        ActivityGitRunner::run(command, allocate_activity_id(), None, &mut sink)
    }) {
        Ok(discovered) => discovered,
        Err(_) => {
            return finish_failure(
                attempt_id,
                NativeCloneFailureKind::Discovery,
                destination.path().as_path(),
            );
        }
    };
    let opened = opener.open(discovered, generation, activity);
    if let Some(failure) = opened.failure {
        let kind = match failure.kind {
            NativeRepositoryFailureKind::MissingGit => NativeCloneFailureKind::MissingGit,
            NativeRepositoryFailureKind::TimedOut => NativeCloneFailureKind::TimedOut,
            _ => NativeCloneFailureKind::Discovery,
        };
        return finish_failure(attempt_id, kind, destination.path().as_path());
    }
    let snapshot = {
        let mut registry = lock_attempts();
        let Some(attempt) = registry.attempts.get_mut(&attempt_id) else {
            return run_failure(NativeCloneFailureKind::UnknownAttempt);
        };
        attempt.state = NativeCloneState::Succeeded;
        attempt.failure = None;
        attempt.partial_destination = false;
        project_attempt(attempt_id, attempt)
    };
    NativeCloneRunResult {
        snapshot: Some(snapshot),
        session: opened.session,
        failure: None,
    }
}

fn clone_authentication<'a>(
    askpass: Option<&'a Path>,
    ssh_wrapper: Option<&'a Path>,
) -> TransferAuthentication<'a> {
    askpass.map_or_else(
        || {
            ssh_wrapper.map_or(TransferAuthentication::Default, |ssh_wrapper| {
                TransferAuthentication::AcceptHostKey { ssh_wrapper }
            })
        },
        |executable| TransferAuthentication::ExternalAskpass { executable },
    )
}

fn clone_transfer_environment(
    reject_helper: &Path,
    askpass: Option<&Path>,
    ssh_wrapper: Option<&Path>,
) -> Result<Vec<RemoteEnvironment>, RemoteOperationError> {
    let authentication = clone_authentication(askpass, ssh_wrapper);
    let mut environment = transfer_environment(true, reject_helper, authentication)?;
    if askpass.is_some() {
        if let Some(ssh_wrapper) = ssh_wrapper {
            environment.push(RemoteEnvironment::new("GIT_SSH", ssh_wrapper.as_os_str())?);
            environment.push(RemoteEnvironment::new(
                "GIT_SSH_COMMAND",
                shell_command_path(ssh_wrapper),
            )?);
            environment.push(RemoteEnvironment::new("GIT_SSH_VARIANT", "ssh")?);
        }
    }
    Ok(environment)
}

#[must_use]
pub fn clone_probe_host_key(attempt_id: u64, generation: u64) -> NativeHostKeyResult {
    clone_probe_host_key_with_executables(
        attempt_id,
        generation,
        std::ffi::OsStr::new("ssh-keyscan"),
        std::ffi::OsStr::new("ssh-keygen"),
    )
}

fn clone_probe_host_key_with_executables(
    attempt_id: u64,
    generation: u64,
    keyscan: &std::ffi::OsStr,
    keygen: &std::ffi::OsStr,
) -> NativeHostKeyResult {
    let (source, cancellation, activity) = {
        let registry = lock_attempts();
        let Some(attempt) = registry.attempts.get(&attempt_id) else {
            return host_key_failure(NativeCloneFailureKind::UnknownAttempt);
        };
        if attempt.generation != generation
            || attempt.state != NativeCloneState::Failed
            || attempt.failure != Some(NativeCloneFailureKind::HostKey)
        {
            return host_key_failure(NativeCloneFailureKind::InvalidAttemptState);
        }
        (
            attempt.source.clone(),
            Arc::clone(&attempt.cancellation),
            attempt.activity.clone(),
        )
    };
    let pending = match probe_host_key_with_executables(
        &source,
        cancellation.as_ref(),
        &activity,
        keyscan,
        keygen,
    ) {
        Ok(pending) => pending,
        Err(failure) => return host_key_failure(failure),
    };
    let challenge = pending.challenge.clone();
    let mut registry = lock_attempts();
    let Some(attempt) = registry.attempts.get_mut(&attempt_id) else {
        return host_key_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    if attempt.generation != generation
        || attempt.state != NativeCloneState::Failed
        || attempt.failure != Some(NativeCloneFailureKind::HostKey)
    {
        return host_key_failure(NativeCloneFailureKind::InvalidAttemptState);
    }
    attempt.pending_host_key = Some(pending);
    NativeHostKeyResult {
        challenge: Some(challenge),
        failure: None,
    }
}

#[must_use]
pub fn clone_accept_host_key(
    attempt_id: u64,
    generation: u64,
    challenge_id: u64,
) -> NativeCloneCommandResult {
    let mut registry = lock_attempts();
    let Some(attempt) = registry.attempts.get_mut(&attempt_id) else {
        return command_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    let Some(pending) = attempt.pending_host_key.as_ref() else {
        return command_failure(NativeCloneFailureKind::HostKeyChallengeExpired);
    };
    if attempt.generation != generation || pending.challenge.challenge_id != challenge_id {
        return command_failure(NativeCloneFailureKind::HostKeyChallengeExpired);
    }
    if let Err(failure) = trust_host_key(pending) {
        return command_failure(failure);
    }
    attempt.pending_host_key = None;
    attempt.host_key_accepted = true;
    NativeCloneCommandResult {
        accepted: true,
        failure: None,
    }
}

#[must_use]
pub fn clone_reject_host_key(
    attempt_id: u64,
    generation: u64,
    challenge_id: u64,
) -> NativeCloneCommandResult {
    let mut registry = lock_attempts();
    let Some(attempt) = registry.attempts.get_mut(&attempt_id) else {
        return command_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    let matches = attempt.generation == generation
        && attempt
            .pending_host_key
            .as_ref()
            .is_some_and(|pending| pending.challenge.challenge_id == challenge_id);
    if !matches {
        return command_failure(NativeCloneFailureKind::HostKeyChallengeExpired);
    }
    attempt.pending_host_key = None;
    NativeCloneCommandResult {
        accepted: true,
        failure: None,
    }
}

#[must_use]
pub fn clone_snapshot(attempt_id: u64, generation: u64) -> NativeCloneSnapshotResult {
    let registry = lock_attempts();
    let Some(attempt) = registry.attempts.get(&attempt_id) else {
        return snapshot_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    if attempt.generation != generation {
        return snapshot_failure(NativeCloneFailureKind::InvalidAttemptState);
    }
    NativeCloneSnapshotResult {
        snapshot: Some(project_attempt(attempt_id, attempt)),
        failure: None,
    }
}

#[must_use]
pub fn clone_cancel(attempt_id: u64, generation: u64) -> NativeCloneCommandResult {
    let registry = lock_attempts();
    let Some(attempt) = registry.attempts.get(&attempt_id) else {
        return command_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    if attempt.generation != generation || attempt.state != NativeCloneState::Running {
        return command_failure(NativeCloneFailureKind::InvalidAttemptState);
    }
    attempt.cancellation.store(true, Ordering::Release);
    NativeCloneCommandResult {
        accepted: true,
        failure: None,
    }
}

#[must_use]
pub fn clone_retry(attempt_id: u64, generation: u64) -> NativeCloneSnapshotResult {
    let mut registry = lock_attempts();
    let Some(attempt) = registry.attempts.get_mut(&attempt_id) else {
        return snapshot_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    if attempt.generation != generation
        || !matches!(
            attempt.state,
            NativeCloneState::Failed | NativeCloneState::Canceled
        )
        || attempt.partial_destination
        || !destination_available(attempt.destination.path().as_path())
    {
        return snapshot_failure(NativeCloneFailureKind::InvalidAttemptState);
    }
    attempt.state = NativeCloneState::Pending;
    attempt.failure = None;
    attempt.cancellation = Arc::new(AtomicBool::new(false));
    NativeCloneSnapshotResult {
        snapshot: Some(project_attempt(attempt_id, attempt)),
        failure: None,
    }
}

#[must_use]
pub fn clone_retry_at_destination(
    attempt_id: u64,
    generation: u64,
    destination: String,
) -> NativeCloneSnapshotResult {
    let destination_path = PathBuf::from(destination);
    let destination = RepositoryPath::new(&destination_path)
        .map_err(|_| NativeCloneFailureKind::InvalidDestination)
        .and_then(|path| CloneDestination::new(path).map_err(map_validation));
    let destination = match destination {
        Ok(destination) if destination_available(destination.path().as_path()) => destination,
        Ok(_) => return snapshot_failure(NativeCloneFailureKind::DestinationOccupied),
        Err(failure) => return snapshot_failure(failure),
    };
    let mut registry = lock_attempts();
    let Some(attempt) = registry.attempts.get_mut(&attempt_id) else {
        return snapshot_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    if attempt.generation != generation
        || !matches!(
            attempt.state,
            NativeCloneState::Failed | NativeCloneState::Canceled
        )
    {
        return snapshot_failure(NativeCloneFailureKind::InvalidAttemptState);
    }
    attempt.destination = destination;
    attempt.state = NativeCloneState::Pending;
    attempt.failure = None;
    attempt.partial_destination = false;
    attempt.cancellation = Arc::new(AtomicBool::new(false));
    NativeCloneSnapshotResult {
        snapshot: Some(project_attempt(attempt_id, attempt)),
        failure: None,
    }
}

#[must_use]
pub fn clone_dismiss(attempt_id: u64, generation: u64) -> NativeCloneCommandResult {
    let mut registry = lock_attempts();
    let Some(attempt) = registry.attempts.get(&attempt_id) else {
        return command_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    if attempt.generation != generation || attempt.state == NativeCloneState::Running {
        return command_failure(NativeCloneFailureKind::InvalidAttemptState);
    }
    registry.attempts.remove(&attempt_id);
    registry.order.retain(|id| *id != attempt_id);
    NativeCloneCommandResult {
        accepted: true,
        failure: None,
    }
}

fn finish_failure(
    attempt_id: u64,
    failure: NativeCloneFailureKind,
    destination: &Path,
) -> NativeCloneRunResult {
    let mut registry = lock_attempts();
    let Some(attempt) = registry.attempts.get_mut(&attempt_id) else {
        return run_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    attempt.state = if failure == NativeCloneFailureKind::Canceled {
        NativeCloneState::Canceled
    } else {
        NativeCloneState::Failed
    };
    attempt.failure = Some(failure);
    attempt.partial_destination = destination_is_partial(destination);
    NativeCloneRunResult {
        snapshot: Some(project_attempt(attempt_id, attempt)),
        session: None,
        failure: None,
    }
}

fn project_attempt(attempt_id: u64, attempt: &OwnedCloneAttempt) -> NativeCloneSnapshot {
    let progress = attempt
        .activity
        .page(1)
        .and_then(|page| page.records.into_iter().next())
        .and_then(|record| record.progress);
    NativeCloneSnapshot {
        attempt_id,
        generation: attempt.generation,
        state: attempt.state,
        failure: attempt.failure.map(|kind| NativeCloneFailure { kind }),
        partial_destination: attempt.partial_destination,
        progress,
        host_key_challenge: attempt
            .pending_host_key
            .as_ref()
            .map(|pending| pending.challenge.clone()),
    }
}

fn destination_available(path: &Path) -> bool {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_dir() => false,
        Ok(_) => std::fs::read_dir(path)
            .map(|mut entries| entries.next().is_none())
            .unwrap_or(false),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            path.parent().is_some_and(|parent| parent.is_dir())
        }
        Err(_) => false,
    }
}

fn destination_is_partial(path: &Path) -> bool {
    match std::fs::read_dir(path) {
        Ok(mut entries) => entries.next().is_some(),
        Err(error) => error.kind() != std::io::ErrorKind::NotFound,
    }
}

fn evict_finished(registry: &mut CloneAttempts) {
    while registry.attempts.len() >= ATTEMPT_CAPACITY {
        let Some(id) = registry.order.front().copied() else {
            break;
        };
        if registry
            .attempts
            .get(&id)
            .is_some_and(|attempt| attempt.state == NativeCloneState::Running)
        {
            break;
        }
        registry.order.pop_front();
        registry.attempts.remove(&id);
    }
}

const fn map_validation(error: CloneValidationError) -> NativeCloneFailureKind {
    match error {
        CloneValidationError::InvalidSource => NativeCloneFailureKind::InvalidSource,
        CloneValidationError::EmbeddedCredential => NativeCloneFailureKind::EmbeddedCredential,
        CloneValidationError::InvalidDestination | CloneValidationError::InvalidInitialBranch => {
            NativeCloneFailureKind::InvalidDestination
        }
    }
}

fn create_failure(kind: NativeCloneFailureKind) -> NativeCloneCreateResult {
    NativeCloneCreateResult {
        snapshot: None,
        failure: Some(NativeCloneFailure { kind }),
    }
}

fn run_failure(kind: NativeCloneFailureKind) -> NativeCloneRunResult {
    NativeCloneRunResult {
        snapshot: None,
        session: None,
        failure: Some(NativeCloneFailure { kind }),
    }
}

fn snapshot_failure(kind: NativeCloneFailureKind) -> NativeCloneSnapshotResult {
    NativeCloneSnapshotResult {
        snapshot: None,
        failure: Some(NativeCloneFailure { kind }),
    }
}

fn command_failure(kind: NativeCloneFailureKind) -> NativeCloneCommandResult {
    NativeCloneCommandResult {
        accepted: false,
        failure: Some(NativeCloneFailure { kind }),
    }
}

fn host_key_failure(kind: NativeCloneFailureKind) -> NativeHostKeyResult {
    NativeHostKeyResult {
        challenge: None,
        failure: Some(NativeCloneFailure { kind }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dto::NativeHostKeyChallenge;
    #[cfg(unix)]
    use crate::ssh_trust::shell_quote;
    use crate::test_support::ScratchDir as Fixture;
    use std::process::Command;

    #[test]
    fn rejects_credentials_relative_destinations_and_occupied_paths() {
        assert_eq!(
            clone_create(
                "https://user:secret@example.test/repo".into(),
                "/tmp/gitlama-never".into(),
                None,
                1,
            )
            .failure
            .unwrap()
            .kind,
            NativeCloneFailureKind::EmbeddedCredential
        );
        assert_eq!(
            clone_create(
                "https://example.test/repo".into(),
                "relative".into(),
                None,
                1
            )
            .failure
            .unwrap()
            .kind,
            NativeCloneFailureKind::InvalidDestination
        );
        let fixture = Fixture::new();
        std::fs::write(fixture.0.join("keep"), b"user data").unwrap();
        assert_eq!(
            clone_create(
                "https://example.test/repo".into(),
                fixture.0.to_string_lossy().into_owned(),
                None,
                1,
            )
            .failure
            .unwrap()
            .kind,
            NativeCloneFailureKind::DestinationOccupied
        );
        assert_eq!(std::fs::read(fixture.0.join("keep")).unwrap(), b"user data");
    }

    #[test]
    fn local_clone_hands_discovery_to_the_normal_session() {
        let fixture = Fixture::new();
        let source = fixture.0.join("source");
        let destination = fixture.0.join("destination with spaces");
        std::fs::create_dir(&source).unwrap();
        let initialized = Command::new("git")
            .args(["init", "-q", "-b", "main"])
            .current_dir(&source)
            .output()
            .unwrap();
        assert!(initialized.status.success());
        let created = clone_create(
            source.to_string_lossy().into_owned(),
            destination.to_string_lossy().into_owned(),
            None,
            81,
        );
        let attempt = created.snapshot.unwrap();
        let completed = clone_run(
            &crate::application::session::SessionRegistry,
            attempt.attempt_id,
            81,
        );
        assert_eq!(
            completed.snapshot.unwrap().state,
            NativeCloneState::Succeeded
        );
        let session = completed.session.unwrap();
        assert_eq!(session.generation, 81);
        assert!(
            crate::application::session::repository_session_close(session.session_id, 81).accepted
        );
        assert!(clone_dismiss(attempt.attempt_id, 81).accepted);
    }

    #[test]
    fn missing_git_is_typed_and_a_partial_destination_is_never_removed() {
        let fixture = Fixture::new();
        let destination = fixture.0.join("destination");
        let created = clone_create(
            "https://example.test/repo".into(),
            destination.to_string_lossy().into_owned(),
            None,
            82,
        );
        let attempt = created.snapshot.unwrap();
        let completed = clone_run_with_executable(
            &crate::application::session::SessionRegistry,
            attempt.attempt_id,
            82,
            "gitlama-definitely-missing-git",
        );
        let snapshot = completed.snapshot.unwrap();
        assert_eq!(
            snapshot.failure.unwrap().kind,
            NativeCloneFailureKind::MissingGit
        );
        assert!(!snapshot.partial_destination);
        assert!(!destination.exists());
        assert!(clone_dismiss(attempt.attempt_id, 82).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn credential_retry_preserves_accepted_host_key_policy() {
        let fixture = Fixture::new();
        let reject = fixture.0.join("reject");
        let askpass = fixture.0.join("askpass");
        let wrapper = fixture.0.join("ssh-wrapper");
        let environment =
            clone_transfer_environment(&reject, Some(&askpass), Some(&wrapper)).unwrap();
        let value = |name: &str| {
            environment
                .iter()
                .find(|entry| entry.name() == name)
                .map(|entry| entry.value().to_owned())
        };
        assert_eq!(value("GIT_ASKPASS").as_deref(), Some(askpass.as_os_str()));
        assert_eq!(value("SSH_ASKPASS").as_deref(), Some(askpass.as_os_str()));
        assert_eq!(
            value("SSH_ASKPASS_REQUIRE").as_deref(),
            Some(std::ffi::OsStr::new("force"))
        );
        assert_eq!(value("GIT_SSH").as_deref(), Some(wrapper.as_os_str()));
        assert_eq!(
            value("GIT_SSH_VARIANT").as_deref(),
            Some(std::ffi::OsStr::new("ssh"))
        );
        assert!(value("GIT_SSH_COMMAND")
            .unwrap()
            .to_string_lossy()
            .contains(&wrapper.to_string_lossy().to_string()));
        assert!(!format!("{environment:?}").contains(&askpass.to_string_lossy().to_string()));
    }

    #[test]
    fn loopback_http_denial_is_typed_without_interactive_fallback() {
        use std::io::{Read, Write};
        use std::net::TcpListener;

        let fixture = Fixture::new();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let mut stream = crate::loopback_fixture::accept_client(&listener);
            let mut request = [0_u8; 4096];
            let _ = stream.read(&mut request);
            stream
                .write_all(
                    b"HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"gitlama-test\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                )
                .unwrap();
        });
        let destination = fixture.0.join("http-destination");
        let attempt = clone_create(
            format!("http://{address}/repository.git"),
            destination.to_string_lossy().into_owned(),
            None,
            84,
        )
        .snapshot
        .unwrap();
        let completed = clone_run(
            &crate::application::session::SessionRegistry,
            attempt.attempt_id,
            84,
        )
        .snapshot
        .unwrap();
        server.join().unwrap();
        assert_eq!(
            completed.failure.unwrap().kind,
            NativeCloneFailureKind::Authentication
        );
        assert!(clone_dismiss(attempt.attempt_id, 84).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn ssh_unknown_host_failure_is_typed_before_trust_probe() {
        use std::os::unix::fs::PermissionsExt;

        let fixture = Fixture::new();
        let executable = fixture.0.join("ssh-denial-git");
        std::fs::write(
            &executable,
            b"#!/bin/sh\nprintf '%s\n' 'Host key verification failed.' >&2\nexit 128\n",
        )
        .unwrap();
        std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o700)).unwrap();
        let attempt = clone_create(
            "ssh://git@example.test/repository".into(),
            fixture.0.join("destination").to_string_lossy().into_owned(),
            None,
            88,
        )
        .snapshot
        .unwrap();
        let completed = clone_run_with_executable(
            &crate::application::session::SessionRegistry,
            attempt.attempt_id,
            88,
            executable,
        )
        .snapshot
        .unwrap();
        assert_eq!(
            completed.failure.unwrap().kind,
            NativeCloneFailureKind::HostKey
        );
        assert!(clone_dismiss(attempt.attempt_id, 88).accepted);
    }

    #[test]
    fn host_key_challenges_are_attempt_bound_and_rejection_writes_nothing() {
        let fixture = Fixture::new();
        let attempt = clone_create(
            "ssh://git@example.test/repository".into(),
            fixture.0.join("destination").to_string_lossy().into_owned(),
            None,
            85,
        )
        .snapshot
        .unwrap();
        {
            let mut registry = lock_attempts();
            let owned = registry.attempts.get_mut(&attempt.attempt_id).unwrap();
            owned.state = NativeCloneState::Failed;
            owned.failure = Some(NativeCloneFailureKind::HostKey);
            owned.pending_host_key = Some(PendingHostKey {
                challenge: NativeHostKeyChallenge {
                    challenge_id: 77,
                    host: "example.test".into(),
                    port: 22,
                    algorithm: "ssh-ed25519".into(),
                    fingerprint: "SHA256:abcdefghijklmnopqrstuvwxyzABCDEFGHijklmno".into(),
                },
                key_line: b"example.test ssh-ed25519 AAAA".to_vec(),
            });
        }
        assert_eq!(
            clone_reject_host_key(attempt.attempt_id, 85, 78)
                .failure
                .unwrap()
                .kind,
            NativeCloneFailureKind::HostKeyChallengeExpired
        );
        assert!(clone_snapshot(attempt.attempt_id, 85)
            .snapshot
            .unwrap()
            .host_key_challenge
            .is_some());
        assert!(clone_reject_host_key(attempt.attempt_id, 85, 77).accepted);
        assert!(clone_snapshot(attempt.attempt_id, 85)
            .snapshot
            .unwrap()
            .host_key_challenge
            .is_none());
        assert!(clone_dismiss(attempt.attempt_id, 85).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn process_backed_host_key_probe_publishes_only_bounded_display_fields() {
        use std::os::unix::fs::PermissionsExt;

        let fixture = Fixture::new();
        let keyscan = fixture.0.join("ssh-keyscan");
        let keygen = fixture.0.join("ssh-keygen");
        std::fs::write(
            &keyscan,
            b"#!/bin/sh\nprintf '%s\\n' '[127.0.0.1]:2222 ssh-ed25519 Zml4dHVyZS1rZXk='\n",
        )
        .unwrap();
        std::fs::write(
            &keygen,
            b"#!/bin/sh\ninput=$(cat)\n[ \"$input\" = '[127.0.0.1]:2222 ssh-ed25519 Zml4dHVyZS1rZXk=' ] || exit 9\nprintf '%s\\n' '256 SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA fixture (ED25519)'\n",
        )
        .unwrap();
        std::fs::set_permissions(&keyscan, std::fs::Permissions::from_mode(0o700)).unwrap();
        std::fs::set_permissions(&keygen, std::fs::Permissions::from_mode(0o700)).unwrap();
        let attempt = clone_create(
            "ssh://git@127.0.0.1:2222/repository".into(),
            fixture.0.join("destination").to_string_lossy().into_owned(),
            None,
            86,
        )
        .snapshot
        .unwrap();
        {
            let mut registry = lock_attempts();
            let owned = registry.attempts.get_mut(&attempt.attempt_id).unwrap();
            owned.state = NativeCloneState::Failed;
            owned.failure = Some(NativeCloneFailureKind::HostKey);
        }
        let result = clone_probe_host_key_with_executables(
            attempt.attempt_id,
            86,
            keyscan.as_os_str(),
            keygen.as_os_str(),
        );
        let challenge = result.challenge.unwrap();
        assert_eq!(challenge.host, "127.0.0.1");
        assert_eq!(challenge.port, 2222);
        assert_eq!(challenge.algorithm, "ssh-ed25519");
        assert_eq!(
            challenge.fingerprint,
            "SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        );
        let projected = clone_snapshot(attempt.attempt_id, 86).snapshot.unwrap();
        assert!(!format!("{projected:?}").contains("Zml4dHVyZS1rZXk="));
        assert!(clone_reject_host_key(attempt.attempt_id, 86, challenge.challenge_id).accepted);

        std::fs::write(
            &keyscan,
            b"#!/bin/sh\nprintf '%s\\n' '[other.test]:2222 ssh-ed25519 Zml4dHVyZS1rZXk='\n",
        )
        .unwrap();
        assert_eq!(
            clone_probe_host_key_with_executables(
                attempt.attempt_id,
                86,
                keyscan.as_os_str(),
                keygen.as_os_str(),
            )
            .failure
            .unwrap()
            .kind,
            NativeCloneFailureKind::HostKeyProbeFailed
        );
        assert!(clone_dismiss(attempt.attempt_id, 86).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn stalled_transfer_times_out_and_reaps_the_process() {
        use std::os::unix::fs::PermissionsExt;
        use std::time::{Duration, Instant};

        let fixture = Fixture::new();
        let executable = fixture.0.join("silent-git");
        let pid_file = fixture.0.join("silent-git.pid");
        let program = format!(
            "#!/bin/sh\nprintf '%s' \"$$\" > {}\nprintf 'started\\n'\nsleep 30\n",
            shell_quote(&pid_file)
        );
        std::fs::write(&executable, program).unwrap();
        std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o700)).unwrap();
        let destination = fixture.0.join("destination");
        let attempt = clone_create(
            "https://example.test/repository".into(),
            destination.to_string_lossy().into_owned(),
            None,
            87,
        )
        .snapshot
        .unwrap();
        let started = Instant::now();
        let completed = clone_run_with_executable_and_idle_timeout(
            &crate::application::session::SessionRegistry,
            attempt.attempt_id,
            87,
            &executable,
            Duration::from_secs(3),
        )
        .snapshot
        .unwrap();
        assert!(started.elapsed() < Duration::from_secs(10));
        assert_eq!(
            completed.failure.unwrap().kind,
            NativeCloneFailureKind::TimedOut
        );
        let pid = std::fs::read_to_string(&pid_file).unwrap();
        assert!(!Command::new("kill")
            .args(["-0", pid.trim()])
            .output()
            .unwrap()
            .status
            .success());
        assert!(clone_dismiss(attempt.attempt_id, 87).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn cancellation_terminates_the_process_and_retry_requires_an_empty_destination() {
        use std::os::unix::fs::PermissionsExt;
        use std::time::{Duration, Instant};

        let fixture = Fixture::new();
        let executable = fixture.0.join("slow-git");
        std::fs::write(
            &executable,
            // The destination is the last argument, whatever configuration precedes `clone`.
            b"#!/bin/sh\nfor destination; do :; done\nmkdir -p \"$destination\"\ntouch \"$destination/partial\"\nsleep 30\n",
        )
        .unwrap();
        std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o700)).unwrap();
        let destination = fixture.0.join("destination");
        let attempt = clone_create(
            "https://example.test/repository".into(),
            destination.to_string_lossy().into_owned(),
            None,
            83,
        )
        .snapshot
        .unwrap();
        let attempt_id = attempt.attempt_id;
        let executable_for_thread = executable.clone();
        let runner = std::thread::spawn(move || {
            clone_run_with_executable(
                &crate::application::session::SessionRegistry,
                attempt_id,
                83,
                executable_for_thread,
            )
        });
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            let snapshot = clone_snapshot(attempt_id, 83).snapshot.unwrap();
            if snapshot.state == NativeCloneState::Running && destination.join("partial").exists() {
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(clone_cancel(attempt_id, 83).accepted);
        let finished = runner.join().unwrap().snapshot.unwrap();
        assert_eq!(finished.state, NativeCloneState::Canceled);
        assert!(finished.partial_destination);
        assert!(destination.join("partial").exists());
        assert_eq!(
            clone_retry(attempt_id, 83).failure.unwrap().kind,
            NativeCloneFailureKind::InvalidAttemptState
        );
        let relocated = fixture.0.join("relocated");
        assert_eq!(
            clone_retry_at_destination(attempt_id, 83, relocated.to_string_lossy().into_owned())
                .snapshot
                .unwrap()
                .state,
            NativeCloneState::Pending
        );
        assert!(destination.join("partial").exists());
        assert!(clone_dismiss(attempt_id, 83).accepted);
    }
}
