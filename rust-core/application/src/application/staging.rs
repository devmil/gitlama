//! Staging and unstaging files and lines through a private index transaction.
#![allow(clippy::wildcard_imports)]
use crate::activity::allocate_activity_id;
use crate::application::{diff::*, paths::*, session::*};
use crate::diff::{selection_for_rows, DiffProjection};
use crate::domain::ids::SessionKey;
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::dto::*;
use devmil_git::activity::ActivityStatus;
use devmil_git::commands::invocation::GitInvocation;
use devmil_git::diff::model::ContextLines;
use devmil_git::diff::model::DiffDocument;
use devmil_git::diff::{BytePatchBuilder, PatchConstructionRequest};
use devmil_git::process::ActivityGitRunner;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};

use devmil_git::commands::index::read_tree_empty;
use devmil_git::index_transaction::IndexTransaction;

/// A session's working-tree diff projection that staging executes against.
#[derive(Default)]
pub(crate) struct StagingState {
    pub(crate) next_request: u64,
    phase: Arc<Mutex<NativeStagingPhase>>,
    pub(crate) projection: Option<OwnedStagingProjection>,
    /// A working diff whose caller stopped waiting before Git answered. Asking for the same
    /// diff again resumes it instead of starting over; any other request drops (cancels) it.
    pub(crate) pending_diff: Option<(
        devmil_git::loading::working_diff::WorkingDiffKey,
        devmil_git::model::working_diff::WorkingDiffTicket,
    )>,
}

/// Progress stays readable while Git holds the repository's exclusive mutation lease.
pub fn repository_session_staging_phase(
    session_id: u64,
    generation: u64,
) -> Option<NativeStagingPhase> {
    let sessions = lock_sessions();
    let session = sessions
        .session(SessionKey::new(session_id, generation))
        .ok()?;
    let phase = *session
        .staging
        .phase
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    Some(phase)
}

struct StagingProgress(Arc<Mutex<NativeStagingPhase>>);
impl StagingProgress {
    fn begin(session_id: u64, generation: u64) -> Result<Self, NativeRepositoryFailureKind> {
        let sessions = lock_sessions();
        let session = sessions.session(SessionKey::new(session_id, generation))?;
        let progress = Self(Arc::clone(&session.staging.phase));
        let mut phase = progress
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if *phase != NativeStagingPhase::Idle {
            return Err(NativeRepositoryFailureKind::InvalidOptions);
        }
        *phase = NativeStagingPhase::Waiting;
        drop(phase);
        Ok(progress)
    }

    fn set(&self, phase: NativeStagingPhase) {
        *self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = phase;
    }
}
impl Drop for StagingProgress {
    fn drop(&mut self) {
        self.set(NativeStagingPhase::Idle);
    }
}

pub fn repository_session_staging_execute(
    session_id: u64,
    generation: u64,
    request: NativeStagingRequest,
) -> NativeStagingExecutionResult {
    let valid_shape = match request.scope {
        NativeStagingScope::All => request.paths.is_empty() && request.row_ids.is_empty(),
        NativeStagingScope::Files => !request.paths.is_empty() && request.row_ids.is_empty(),
        NativeStagingScope::Rows => request.paths.is_empty() && !request.row_ids.is_empty(),
    };
    if !valid_shape
        || request.paths.len() > crate::domain::limits::STAGE_PATHS
        || request.row_ids.len() > crate::domain::limits::STAGE_ROWS
        || (request.request_id == 0 && request.scope == NativeStagingScope::Rows)
    {
        return staging_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let progress = match StagingProgress::begin(session_id, generation) {
        Ok(progress) => progress,
        Err(kind) => return staging_failure(kind),
    };
    if request.request_id == 0 {
        return execute_whole_file_staging(session_id, generation, request, &progress);
    }
    let (repository, activity, staging) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return staging_failure(kind),
        };
        let Some(staging) = session.staging.projection.as_ref() else {
            return staging_failure(NativeRepositoryFailureKind::InvalidOptions);
        };
        if staging.request_id != request.request_id || staging.side != request.side {
            return NativeStagingExecutionResult {
                state: NativeStagingExecutionState::Stale,
                failure: None,
                diagnostic: Some(staging_diagnostic(NativeStagingFailureCode::IndexChanged)),
            };
        }
        let staging = session.staging.projection.take().unwrap();
        (
            Arc::clone(&session.repository),
            session.activity.clone(),
            staging,
        )
    };
    let selected_paths = match staging_paths(
        &staging.document,
        request.scope,
        &request.paths,
        &staging.untracked_paths,
    ) {
        Some(value) => value,
        None => return staging_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let cancellation = AtomicBool::new(false);
    let diagnostic = std::cell::RefCell::new(None);
    let outcome = crate::operations::coordinate_leased_mutation_with_progress(
        &repository,
        &cancellation,
        || progress.set(NativeStagingPhase::Refreshing),
        |_, _| {
            progress.set(NativeStagingPhase::Updating);
            apply_staging_index(
                &repository,
                &activity,
                &staging,
                &request,
                &selected_paths,
                &cancellation,
            )
            .map_err(|failure| {
                *diagnostic.borrow_mut() = Some(failure);
                crate::operations::ExecutionFailure::Definite
            })
        },
    );
    finish_staging(outcome, diagnostic.into_inner(), &repository)
}

/// Whole-file intent uses status metadata, never a display patch. Fresh status, content
/// guards and installation share one lease, so the repository worker cannot refresh the
/// index between preparation and execution. The real index is still compared under Git's lock.
fn execute_whole_file_staging(
    session_id: u64,
    generation: u64,
    request: NativeStagingRequest,
    progress: &StagingProgress,
) -> NativeStagingExecutionResult {
    use devmil_git::commands::index::{status_paths, IndexSelectionSide};
    let (repository, activity) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return staging_failure(kind),
        };
        (Arc::clone(&session.repository), session.activity.clone())
    };
    let cancellation = AtomicBool::new(false);
    let diagnostic = std::cell::RefCell::new(None);
    let outcome = crate::operations::coordinate_leased_mutation_with_progress(
        &repository,
        &cancellation,
        || progress.set(NativeStagingPhase::Refreshing),
        |_, lease| {
            progress.set(NativeStagingPhase::Preparing);
            let execute = || -> Result<(), NativeStagingDiagnostic> {
                let discovered = repository.snapshot().repository.clone().ok_or_else(|| {
                    staging_diagnostic(NativeStagingFailureCode::RepositoryUnavailable)
                })?;
                let worktree = discovered.worktree.worktree_root().as_path().to_path_buf();
                let git_dir = discovered.worktree.git_dir().as_path().to_path_buf();
                let index_bytes =
                    devmil_git::index_transaction::read_index_bytes(&git_dir.join("index"))
                        .map_err(|_| staging_diagnostic(NativeStagingFailureCode::IndexRead))?;
                let status = lease
                    .fresh_status(Some(&cancellation))
                    .map_err(|_| staging_diagnostic(NativeStagingFailureCode::StatusRead))?
                    .ok_or_else(|| {
                        staging_diagnostic(NativeStagingFailureCode::RepositoryUnavailable)
                    })?;
                if status
                    .entries
                    .iter()
                    .any(devmil_git::status::StatusEntry::is_conflicted)
                {
                    return Err(staging_diagnostic(NativeStagingFailureCode::InvalidRequest));
                }
                let side = match request.side {
                    NativeStagingSide::Staged => IndexSelectionSide::Staged,
                    NativeStagingSide::Unstaged => IndexSelectionSide::Unstaged,
                };
                let available = status_paths(&status, side)
                    .map_err(|_| staging_diagnostic(NativeStagingFailureCode::InvalidRequest))?
                    .into_iter()
                    .map(|path| path.as_bytes().to_vec())
                    .collect::<Vec<_>>();
                let selected_paths = match request.scope {
                    NativeStagingScope::All
                        if request.paths.is_empty() && request.row_ids.is_empty() =>
                    {
                        available
                    }
                    NativeStagingScope::Files
                        if !request.paths.is_empty() && request.row_ids.is_empty() =>
                    {
                        let selected = request
                            .paths
                            .iter()
                            .map(|path| devmil_git::commands::index::status_path(path))
                            .collect::<Result<Vec<_>, _>>()
                            .map_err(|_| {
                                staging_diagnostic(NativeStagingFailureCode::InvalidRequest)
                            })?;
                        devmil_git::commands::index::selected_status_paths(&status, side, &selected)
                            .map_err(|_| {
                                staging_diagnostic(NativeStagingFailureCode::InvalidRequest)
                            })?
                            .into_iter()
                            .map(|path| path.as_bytes().to_vec())
                            .collect()
                    }
                    _ => return Err(staging_diagnostic(NativeStagingFailureCode::InvalidRequest)),
                };
                if selected_paths.is_empty() {
                    return Ok(());
                }
                let document = Arc::new(DiffDocument {
                    files: vec![],
                    layout: devmil_git::diff::model::DiffLayout::Unified,
                });
                let staging = OwnedStagingProjection {
                    request_id: 0,
                    side: request.side,
                    projection: DiffProjection::from_document(0, &document),
                    document,
                    worktree,
                    git_dir,
                    unborn: matches!(
                        status.branch.head,
                        devmil_git::status::BranchHead::Unborn { .. }
                    ),
                    index_bytes,
                    worktree_states: HashMap::new(),
                    untracked_paths: HashSet::new(),
                    force_text: false,
                };
                progress.set(NativeStagingPhase::Updating);
                apply_staging_index(
                    &repository,
                    &activity,
                    &staging,
                    &request,
                    &selected_paths,
                    &cancellation,
                )
            };
            execute().map_err(|failure| {
                *diagnostic.borrow_mut() = Some(failure);
                crate::operations::ExecutionFailure::Definite
            })
        },
    );
    finish_staging(outcome, diagnostic.into_inner(), &repository)
}

fn staging_diagnostic(code: NativeStagingFailureCode) -> NativeStagingDiagnostic {
    NativeStagingDiagnostic {
        code,
        activity_id: None,
        exit_code: None,
        git_version: None,
    }
}

fn apply_staging_index(
    repository: &devmil_git::model::Repository,
    activity: &crate::activity::ActivityStore,
    staging: &OwnedStagingProjection,
    request: &NativeStagingRequest,
    selected_paths: &[Vec<u8>],
    cancellation: &AtomicBool,
) -> Result<(), NativeStagingDiagnostic> {
    use NativeStagingFailureCode as Code;
    if !staging_preconditions_match(staging) {
        return Err(staging_diagnostic(Code::IndexChanged));
    }
    let exact_states = capture_staging_fingerprints(
        &staging.worktree,
        if staging.side == NativeStagingSide::Unstaged {
            selected_paths.iter().cloned().collect()
        } else {
            HashSet::new()
        },
        false,
    )
    .map_err(|_| staging_diagnostic(Code::ContentRead))?;
    let invocation = staging_invocation(staging, request, selected_paths)
        .map_err(|_| staging_diagnostic(Code::PatchUnavailable))?;
    let transaction = IndexTransaction::begin(&staging.git_dir, staging.index_bytes.clone())
        .map_err(|_| staging_diagnostic(Code::IndexPrepare))?;
    let mut invocations = Vec::with_capacity(2);
    if transaction.starts_empty() {
        invocations.push(read_tree_empty());
    }
    invocations.push(invocation);
    let staged = invocations.len() - 1;
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let mut last_activity = None;
    for (index, invocation) in invocations.into_iter().enumerate() {
        let command = transaction
            .wrap(invocation)
            .process_command(repository.git_executable(), &staging.worktree)
            .redact_output();
        let activity_id = if index == staged {
            crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change)
        } else {
            allocate_activity_id()
        };
        last_activity = Some(activity_id.get());
        let process =
            ActivityGitRunner::run_private(command, activity_id, Some(cancellation), &mut publish);
        if !matches!(process.activity.status, ActivityStatus::Succeeded { .. }) {
            let (code, exit_code) = match process.activity.status {
                ActivityStatus::LaunchError { .. } => (Code::GitLaunch, None),
                ActivityStatus::TimedOut { .. } => (Code::GitTimeout, None),
                ActivityStatus::Failed { exit_code } => (Code::GitFailed, exit_code),
                _ => (Code::GitFailed, None),
            };
            return Err(NativeStagingDiagnostic {
                code,
                activity_id: Some(activity_id.get()),
                exit_code,
                git_version: None,
            });
        }
    }
    if !staging_preconditions_match(staging) {
        return Err(staging_diagnostic(Code::IndexChanged));
    }
    if !staging_states_match(&staging.worktree, &exact_states) {
        return Err(staging_diagnostic(Code::ContentChanged));
    }
    transaction.install().map_err(|error| {
        use devmil_git::index_transaction::IndexTransactionError as Error;
        let mut diagnostic = staging_diagnostic(match error {
            Error::Locked => Code::IndexLocked,
            Error::Changed => Code::IndexChanged,
            Error::UnsafeFile => Code::IndexUnsafe,
            Error::Missing | Error::Io => Code::IndexInstall,
        });
        diagnostic.activity_id = last_activity;
        diagnostic
    })
}

fn finish_staging(
    terminal: crate::domain::outcome::MutationTerminalState,
    diagnostic: Option<NativeStagingDiagnostic>,
    repository: &devmil_git::model::Repository,
) -> NativeStagingExecutionResult {
    let outcome = MutationOutcome::from_terminal(terminal);
    let stale = diagnostic.as_ref().is_some_and(|failure| {
        matches!(
            failure.code,
            NativeStagingFailureCode::IndexChanged | NativeStagingFailureCode::ContentChanged
        )
    });
    let mut result = staging_result(if !outcome.committed && stale {
        MutationOutcome::stale()
    } else if matches!(
        outcome.state,
        MutationState::Canceled | MutationState::Failed
    ) {
        outcome.with_failure(Some(NativeRepositoryFailureKind::Read))
    } else {
        outcome
    });
    result.diagnostic = diagnostic.or_else(|| {
        (result.state == NativeStagingExecutionState::Failed)
            .then(|| staging_diagnostic(NativeStagingFailureCode::RepositoryUnavailable))
    });
    if let Some(diagnostic) = &mut result.diagnostic {
        diagnostic.git_version = repository.snapshot().repository.as_ref().map(|repo| {
            let version = repo.git_version;
            format!("{}.{}.{}", version.major, version.minor, version.patch)
        });
    }
    result
}

/// The bridge result of a staging change: the one place its outcome becomes a state.
pub(crate) fn staging_result(
    outcome: MutationOutcome<NativeRepositoryFailureKind>,
) -> NativeStagingExecutionResult {
    NativeStagingExecutionResult {
        state: match outcome.state {
            MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
                NativeStagingExecutionState::Completed
            }
            MutationState::ReconciledWithWarning => {
                NativeStagingExecutionState::ReconciledWithWarning
            }
            MutationState::Stale => NativeStagingExecutionState::Stale,
            MutationState::Conflict
            | MutationState::Interrupted
            | MutationState::EditStop
            | MutationState::Partial
            | MutationState::Canceled
            | MutationState::Failed => NativeStagingExecutionState::Failed,
            MutationState::OutcomeUncertain => NativeStagingExecutionState::OutcomeUncertain,
        },
        failure: outcome.failure.map(|kind| NativeRepositoryFailure { kind }),
        diagnostic: None,
    }
}

pub(crate) struct OwnedStagingProjection {
    pub(crate) request_id: u64,
    pub(crate) side: NativeStagingSide,
    pub(crate) document: Arc<DiffDocument>,
    pub(crate) projection: DiffProjection,
    pub(crate) worktree: PathBuf,
    pub(crate) git_dir: PathBuf,
    pub(crate) unborn: bool,
    pub(crate) index_bytes: Option<Vec<u8>>,
    pub(crate) worktree_states: HashMap<Vec<u8>, StagingPathState>,
    pub(crate) untracked_paths: HashSet<Vec<u8>>,
    /// Rows of a diff Git was told to show as text cannot be applied back as a patch.
    pub(crate) force_text: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum StagingPathState {
    Missing,
    File(Vec<u8>),
    Fingerprint(devmil_git::filesystem::fingerprint::PathFingerprint),
    Symlink(Vec<u8>),
    Directory,
}

pub(crate) const fn staging_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeStagingExecutionResult {
    NativeStagingExecutionResult {
        state: NativeStagingExecutionState::Failed,
        failure: Some(NativeRepositoryFailure { kind }),
        diagnostic: Some(NativeStagingDiagnostic {
            code: if matches!(kind, NativeRepositoryFailureKind::InvalidOptions) {
                NativeStagingFailureCode::InvalidRequest
            } else {
                NativeStagingFailureCode::RepositoryUnavailable
            },
            activity_id: None,
            exit_code: None,
            git_version: None,
        }),
    }
}

pub(crate) fn capture_staging_paths(
    worktree: &Path,
    paths: HashSet<Vec<u8>>,
) -> Result<HashMap<Vec<u8>, StagingPathState>, NativeRepositoryFailureKind> {
    let mut result = HashMap::new();
    let mut total_bytes = 0_usize;
    for path in paths {
        let Some(native) = native_path_argument(path.clone()) else {
            return Err(NativeRepositoryFailureKind::InvalidOptions);
        };
        let absolute = worktree.join(native);
        let state = match fs::symlink_metadata(&absolute) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                StagingPathState::Symlink(native_link_bytes(
                    &fs::read_link(&absolute).map_err(|_| NativeRepositoryFailureKind::Read)?,
                ))
            }
            Ok(metadata) if metadata.is_file() => {
                if metadata.len() > 128 * 1024 * 1024 {
                    return Err(NativeRepositoryFailureKind::TooLarge);
                }
                total_bytes = total_bytes
                    .checked_add(metadata.len() as usize)
                    .filter(|value| *value <= 128 * 1024 * 1024)
                    .ok_or(NativeRepositoryFailureKind::TooLarge)?;
                StagingPathState::File(
                    fs::read(absolute).map_err(|_| NativeRepositoryFailureKind::Read)?,
                )
            }
            Ok(metadata) if metadata.is_dir() => StagingPathState::Directory,
            Ok(_) => return Err(NativeRepositoryFailureKind::Unsupported),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => StagingPathState::Missing,
            Err(_) => return Err(NativeRepositoryFailureKind::Read),
        };
        result.insert(path, state);
    }
    Ok(result)
}

pub(crate) fn native_link_bytes(path: &Path) -> Vec<u8> {
    devmil_git::native_bytes::path_to_bytes(path)
}

pub(crate) fn staging_preconditions_match(staging: &OwnedStagingProjection) -> bool {
    read_optional_bounded(&staging.git_dir.join("index"), 128 * 1024 * 1024)
        .is_ok_and(|current| current == staging.index_bytes)
        && staging_states_match(&staging.worktree, &staging.worktree_states)
}

pub(crate) fn staging_states_match(
    worktree: &Path,
    states: &HashMap<Vec<u8>, StagingPathState>,
) -> bool {
    states.iter().all(|(path, state)| {
        let Some(native) = native_path_argument(path.clone()) else {
            return false;
        };
        match state {
            StagingPathState::Fingerprint(expected) => {
                devmil_git::filesystem::fingerprint::fingerprint_matches(
                    &worktree.join(native),
                    expected,
                )
                .unwrap_or(false)
            }
            _ => capture_staging_paths(worktree, HashSet::from([path.clone()]))
                .is_ok_and(|current| current.get(path) == Some(state)),
        }
    })
}

pub(crate) fn capture_staging_fingerprints(
    worktree: &Path,
    paths: HashSet<Vec<u8>>,
    preview: bool,
) -> Result<HashMap<Vec<u8>, StagingPathState>, NativeRepositoryFailureKind> {
    paths
        .into_iter()
        .map(|path| {
            let native = native_path_argument(path.clone())
                .ok_or(NativeRepositoryFailureKind::InvalidOptions)?;
            let absolute = worktree.join(native);
            let fingerprint = if preview {
                devmil_git::filesystem::fingerprint::preview_fingerprint_path(
                    &absolute,
                    devmil_git::loading::diff_preview::MAX_INLINE_FILE_BYTES,
                )
            } else {
                devmil_git::filesystem::fingerprint::fingerprint_path(&absolute)
            }
            .map_err(|_| NativeRepositoryFailureKind::Read)?;
            Ok((path, StagingPathState::Fingerprint(fingerprint)))
        })
        .collect()
}

pub(crate) fn staging_paths(
    document: &DiffDocument,
    scope: NativeStagingScope,
    requested: &[Vec<u8>],
    untracked_paths: &HashSet<Vec<u8>>,
) -> Option<Vec<Vec<u8>>> {
    let mut available = document
        .files
        .iter()
        .flat_map(|file| [&file.id.old_path, &file.id.new_path])
        .flatten()
        .map(|path| path.as_bytes().to_vec())
        .collect::<HashSet<_>>();
    // Whole-file intent includes status-only untracked files. Folder actions
    // supply their descendant paths, which an index/worktree diff omits.
    // Row patches still require identities from the accepted diff document.
    if matches!(scope, NativeStagingScope::All | NativeStagingScope::Files) {
        available.extend(untracked_paths.iter().cloned());
    }
    let selected = match scope {
        NativeStagingScope::All if requested.is_empty() => available,
        NativeStagingScope::Files if !requested.is_empty() => {
            let selected = requested.iter().cloned().collect::<HashSet<_>>();
            if selected.len() != requested.len() || !selected.is_subset(&available) {
                return None;
            }
            selected
        }
        NativeStagingScope::Rows if document.files.len() == 1 && requested.is_empty() => available,
        _ => return None,
    };
    let mut selected = selected.into_iter().collect::<Vec<_>>();
    selected.sort();
    Some(selected)
}

/// The Git invocation that applies one staging request to a private index copy. Paths are
/// literal pathspecs, so a file named like a glob selects only itself.
pub(crate) fn staging_invocation(
    staging: &OwnedStagingProjection,
    request: &NativeStagingRequest,
    selected_paths: &[Vec<u8>],
) -> Result<GitInvocation, NativeRepositoryFailureKind> {
    use devmil_git::commands::index::{
        apply_to_index, stage_paths, unstage_paths, PathspecForm, UnstageBase,
    };
    match request.scope {
        NativeStagingScope::All | NativeStagingScope::Files if !request.row_ids.is_empty() => {
            return Err(NativeRepositoryFailureKind::InvalidOptions);
        }
        NativeStagingScope::Rows if request.row_ids.is_empty() || staging.force_text => {
            return Err(NativeRepositoryFailureKind::InvalidOptions);
        }
        _ => {}
    }
    let invocation = match request.scope {
        NativeStagingScope::Rows => {
            let file = staging
                .document
                .files
                .first()
                .ok_or(NativeRepositoryFailureKind::InvalidOptions)?;
            let selection = selection_for_rows(file, 0, &request.row_ids)
                .ok_or(NativeRepositoryFailureKind::InvalidOptions)?;
            let patch = BytePatchBuilder
                .construct_patch(&PatchConstructionRequest {
                    file: file.clone(),
                    selection,
                    context: ContextLines::new(3).expect("constant context is valid"),
                    reverse: request.side == NativeStagingSide::Staged,
                })
                .map_err(|error| map_diff_error_kind(error.kind))?
                .bytes;
            apply_to_index(patch)
        }
        NativeStagingScope::All | NativeStagingScope::Files => {
            let paths = selected_paths
                .iter()
                .map(|path| devmil_git::commands::index::status_path(path).ok())
                .collect::<Option<Vec<_>>>()
                .ok_or(NativeRepositoryFailureKind::InvalidOptions)?;
            match request.side {
                NativeStagingSide::Unstaged => stage_paths(&paths, PathspecForm::StdinNul),
                NativeStagingSide::Staged => unstage_paths(
                    &paths,
                    if staging.unborn {
                        UnstageBase::Unborn
                    } else {
                        UnstageBase::Head
                    },
                    PathspecForm::StdinNul,
                ),
            }
            .map_err(|_| NativeRepositoryFailureKind::InvalidOptions)?
        }
    };
    Ok(invocation)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::outcome::MutationTerminalState;

    #[test]
    fn an_uncertain_staging_change_stays_uncertain() {
        let result = staging_result(MutationOutcome::from_terminal(
            MutationTerminalState::OutcomeUncertain,
        ));
        assert_eq!(result.state, NativeStagingExecutionState::OutcomeUncertain);
        assert_eq!(result.failure, None);
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{diff::*, operation_center::*, session::*, staging::*};

    use crate::diff::DIFF_PAGE_CAPACITY;
    use crate::diff::{NativeDiffLayout, NativeDiffPage, NativeDiffRowKind};

    use devmil_git::status::StatusEntry;

    use devmil_git::RepositoryOptions;

    use std::fs;
    use std::io::Write as _;

    use std::path::Path;
    use std::process::Command;

    #[test]
    fn staging_progress_is_session_bound_exclusive_and_resets_on_drop() {
        let fixture = GitFixture::new();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            949,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let read = || repository_session_staging_phase(session.session_id, 949);
        assert_eq!(read(), Some(NativeStagingPhase::Idle));
        assert_eq!(
            repository_session_staging_phase(session.session_id, 950),
            None
        );
        {
            let progress = StagingProgress::begin(session.session_id, 949).unwrap();
            assert_eq!(read(), Some(NativeStagingPhase::Waiting));
            assert!(StagingProgress::begin(session.session_id, 949).is_err());
            for phase in [
                NativeStagingPhase::Preparing,
                NativeStagingPhase::Updating,
                NativeStagingPhase::Refreshing,
            ] {
                progress.set(phase);
                assert_eq!(read(), Some(phase));
            }
        }
        assert_eq!(read(), Some(NativeStagingPhase::Idle));
        assert!(repository_session_close(session.session_id, 949).accepted);
        assert_eq!(read(), None);
        assert!(StagingProgress::begin(session.session_id, 949).is_err());
    }

    #[test]
    fn whole_file_actions_do_not_need_an_aggregate_patch_and_report_index_locks() {
        let fixture = GitFixture::new();
        let git = |args: &[&str]| {
            let output = Command::new("git")
                .args(args)
                .current_dir(&fixture.0)
                .output()
                .unwrap();
            assert!(output.status.success());
            output.stdout
        };
        let old = b"old value 1234567890\n".repeat(22_000);
        let new = b"new value 1234567890\n".repeat(22_000);
        for i in 0..16 {
            fs::write(fixture.0.join(format!("file-{i}.txt")), &old).unwrap();
        }
        git(&["add", "."]);
        git(&["commit", "-qm", "base"]);
        for i in 0..16 {
            fs::write(fixture.0.join(format!("file-{i}.txt")), &new).unwrap();
        }
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1941,
            RepositoryOptions {
                watch: false,
                polling_fallback: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let execute = |side| {
            repository_session_staging_execute(
                session.session_id,
                session.generation,
                NativeStagingRequest {
                    request_id: 0,
                    side,
                    scope: NativeStagingScope::All,
                    paths: vec![],
                    row_ids: vec![],
                },
            )
        };
        assert_eq!(
            execute(NativeStagingSide::Unstaged).state,
            NativeStagingExecutionState::Completed
        );
        let viewed = repository_session_working_diff_load(
            session.session_id,
            session.generation,
            NativeWorkingDiffOptions {
                side: NativeStagingSide::Staged,
                old_path: None,
                new_path: None,
                context_lines: 3,
                whitespace: NativeDiffWhitespace::Preserve,
                layout: NativeDiffLayout::Unified,
                maximum_rows: 512,
                force_text: false,
            },
        );
        assert_eq!(
            viewed.failure.unwrap().kind,
            NativeRepositoryFailureKind::TooLarge
        );
        let before = fs::read(fixture.0.join(".git/index")).unwrap();
        fs::write(fixture.0.join(".git/index.lock"), b"other Git process").unwrap();
        let locked = execute(NativeStagingSide::Staged);
        assert_eq!(locked.state, NativeStagingExecutionState::Failed);
        let diagnostic = locked.diagnostic.unwrap();
        assert_eq!(diagnostic.code, NativeStagingFailureCode::IndexLocked);
        assert!(diagnostic.git_version.is_some());
        assert_eq!(fs::read(fixture.0.join(".git/index")).unwrap(), before);
        assert_eq!(
            fs::read(fixture.0.join(".git/index.lock")).unwrap(),
            b"other Git process"
        );
        fs::remove_file(fixture.0.join(".git/index.lock")).unwrap();
        assert_eq!(
            execute(NativeStagingSide::Staged).state,
            NativeStagingExecutionState::Completed
        );
        assert!(git(&["diff", "--cached", "--name-only"]).is_empty());
        for i in 0..16 {
            assert_eq!(
                fs::read(fixture.0.join(format!("file-{i}.txt"))).unwrap(),
                new
            );
        }
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn whole_file_actions_stream_large_files_and_handle_unborn_repositories() {
        let fixture = GitFixture::new();
        let path = fixture.0.join("large.bin");
        fs::File::create(&path)
            .unwrap()
            .set_len(129 * 1024 * 1024)
            .unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1942,
            RepositoryOptions {
                watch: false,
                polling_fallback: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        for side in [NativeStagingSide::Unstaged, NativeStagingSide::Staged] {
            let result = repository_session_staging_execute(
                session.session_id,
                session.generation,
                NativeStagingRequest {
                    request_id: 0,
                    side,
                    scope: NativeStagingScope::Files,
                    paths: vec![b"large.bin".to_vec()],
                    row_ids: vec![],
                },
            );
            assert_eq!(
                result.state,
                NativeStagingExecutionState::Completed,
                "{:?}",
                result.diagnostic
            );
            assert_eq!(fs::metadata(&path).unwrap().len(), 129 * 1024 * 1024);
        }
        let index = Command::new("git")
            .args(["ls-files", "--stage"])
            .current_dir(&fixture.0)
            .output()
            .unwrap();
        assert!(index.status.success() && index.stdout.is_empty());
        let preview = crate::application::discard::repository_session_discard_preview(
            session.session_id,
            session.generation,
            NativeDiscardRequest {
                kind: NativeDiscardKind::Clean,
                scope: NativeDiscardScope::Files,
                working_diff_request_id: None,
                paths: vec![b"large.bin".to_vec()],
                row_ids: vec![],
            },
        );
        let preview = preview.preview.unwrap();
        let cleaned = crate::application::discard::repository_session_discard_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert_eq!(cleaned.state, NativeDiscardExecutionState::Completed);
        assert!(!path.exists());
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn fresh_whole_file_intent_refuses_conflicts_without_touching_the_index() {
        let fixture = GitFixture::new();
        let git = |args: &[&str]| {
            Command::new("git")
                .args(args)
                .current_dir(&fixture.0)
                .output()
                .unwrap()
        };
        fs::write(fixture.0.join("file.txt"), b"base\n").unwrap();
        assert!(git(&["add", "."]).status.success());
        assert!(git(&["commit", "-qm", "base"]).status.success());
        assert!(git(&["checkout", "-qb", "other"]).status.success());
        fs::write(fixture.0.join("file.txt"), b"other\n").unwrap();
        assert!(git(&["commit", "-qam", "other"]).status.success());
        assert!(git(&["checkout", "-q", "main"]).status.success());
        fs::write(fixture.0.join("file.txt"), b"ours\n").unwrap();
        assert!(git(&["commit", "-qam", "ours"]).status.success());
        assert!(!git(&["merge", "other"]).status.success());
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1943,
            RepositoryOptions {
                watch: false,
                polling_fallback: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let before = fs::read(fixture.0.join(".git/index")).unwrap();
        for side in [NativeStagingSide::Unstaged, NativeStagingSide::Staged] {
            let result = repository_session_staging_execute(
                session.session_id,
                session.generation,
                NativeStagingRequest {
                    request_id: 0,
                    side,
                    scope: NativeStagingScope::All,
                    paths: vec![],
                    row_ids: vec![],
                },
            );
            assert_eq!(result.state, NativeStagingExecutionState::Failed);
            assert_eq!(
                result.diagnostic.unwrap().code,
                NativeStagingFailureCode::InvalidRequest
            );
            assert_eq!(fs::read(fixture.0.join(".git/index")).unwrap(), before);
        }
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[cfg(windows)]
    #[test]
    fn git_index_environment_uses_paths_accepted_by_git_for_windows() {
        assert_eq!(
            devmil_git::index_transaction::git_compatible_index_path(Path::new(
                r"\\?\C:\fixture\.git\index"
            )),
            PathBuf::from(r"C:\fixture\.git\index")
        );
        assert_eq!(
            devmil_git::index_transaction::git_compatible_index_path(Path::new(
                r"\\?\UNC\server\share\.git\index"
            )),
            PathBuf::from(r"\\server\share\.git\index")
        );
        assert_eq!(
            devmil_git::index_transaction::git_compatible_index_path(Path::new(
                r"C:\fixture\.git\index"
            )),
            PathBuf::from(r"C:\fixture\.git\index")
        );
    }

    #[test]
    fn large_release_files_do_not_block_staging_and_still_reject_drift() {
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .output()
                .unwrap();
            assert!(output.status.success());
            output.stdout
        };
        fs::write(fixture.0.join("readme.md"), b"release notes\n").unwrap();
        for name in ["app.apk", "app.aab"] {
            fs::File::create(fixture.0.join(name))
                .unwrap()
                .set_len(65 * 1024 * 1024)
                .unwrap();
        }
        let generation = 923;
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            generation,
            RepositoryOptions {
                watch: false,
                polling_fallback: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let load = |path: Option<Vec<u8>>| {
            repository_session_working_diff_load(
                session.session_id,
                generation,
                NativeWorkingDiffOptions {
                    side: NativeStagingSide::Unstaged,
                    old_path: None,
                    new_path: path,
                    context_lines: 3,
                    whitespace: NativeDiffWhitespace::Preserve,
                    layout: NativeDiffLayout::Unified,
                    maximum_rows: 512,
                    force_text: false,
                },
            )
            .page
            .unwrap()
        };
        let stage = |page: NativeDiffPage, scope, paths| {
            repository_session_staging_execute(
                session.session_id,
                generation,
                NativeStagingRequest {
                    request_id: page.request_id,
                    side: NativeStagingSide::Unstaged,
                    scope,
                    paths,
                    row_ids: vec![],
                },
            )
        };
        let information = load(Some(b"app.apk".to_vec()));
        assert!(information
            .rows
            .iter()
            .any(|row| row.kind == NativeDiffRowKind::TooLarge));
        assert!(information.rows.iter().all(|row| !row.selectable));
        assert_eq!(
            stage(
                load(None),
                NativeStagingScope::Files,
                vec![b"readme.md".to_vec()]
            )
            .state,
            NativeStagingExecutionState::Completed
        );
        assert_eq!(git(&["show", ":readme.md"]), b"release notes\n");
        assert!(git(&["ls-files", "--", "app.apk", "app.aab"]).is_empty());
        let accepted = load(None);
        fs::OpenOptions::new()
            .write(true)
            .open(fixture.0.join("app.apk"))
            .unwrap()
            .write_all(b"changed")
            .unwrap();
        assert_eq!(
            stage(
                accepted,
                NativeStagingScope::Files,
                vec![b"app.apk".to_vec()]
            )
            .state,
            NativeStagingExecutionState::Stale
        );
        assert!(git(&["ls-files", "--", "app.apk"]).is_empty());
        assert_eq!(
            stage(load(None), NativeStagingScope::All, vec![]).state,
            NativeStagingExecutionState::Completed
        );
        assert_eq!(
            git(&["cat-file", "-s", ":app.apk"]),
            format!("{}\n", 65 * 1024 * 1024).as_bytes()
        );
        assert_eq!(
            git(&["cat-file", "-s", ":app.aab"]),
            format!("{}\n", 65 * 1024 * 1024).as_bytes()
        );
        assert!(repository_session_close(session.session_id, generation).accepted);
    }

    #[test]
    fn selected_staging_includes_untracked_files_and_folders() {
        for unborn in [true, false] {
            let fixture = GitFixture::new();
            let git = |arguments: &[&str]| {
                let output = Command::new("git")
                    .args(arguments)
                    .current_dir(&fixture.0)
                    .output()
                    .unwrap();
                assert!(output.status.success());
                output.stdout
            };
            fs::write(fixture.0.join("already-staged.txt"), b"keep\n").unwrap();
            git(&["add", "already-staged.txt"]);
            if !unborn {
                git(&[
                    "-c",
                    "user.name=GitLama Test",
                    "-c",
                    "user.email=gitlama@example.invalid",
                    "commit",
                    "-qm",
                    "base",
                ]);
            }
            fs::create_dir_all(fixture.0.join("docs/nested")).unwrap();
            fs::write(fixture.0.join("docs/readme.md"), b"readme\n").unwrap();
            fs::write(fixture.0.join("docs/nested/plan.md"), b"plan\n").unwrap();
            fs::write(fixture.0.join("new.txt"), b"new\n").unwrap();
            fs::write(fixture.0.join("unselected.txt"), b"leave\n").unwrap();
            let generation = 922;
            let session = repository_session_open_with_options(
                fixture.0.clone(),
                generation,
                RepositoryOptions {
                    watch: false,
                    ..RepositoryOptions::default()
                },
                ActivityStore::default(),
            )
            .session
            .unwrap();
            wait_for_ready(&session);
            assert!(repository_for_session(session.session_id, generation)
                .unwrap()
                .snapshot()
                .status
                .as_ref()
                .unwrap()
                .entries
                .iter()
                .any(|entry| matches!(entry, StatusEntry::Untracked(_))
                    && entry.path().as_path() == Path::new("docs/readme.md")));
            let load = || {
                repository_session_working_diff_load(
                    session.session_id,
                    generation,
                    NativeWorkingDiffOptions {
                        side: NativeStagingSide::Unstaged,
                        old_path: None,
                        new_path: None,
                        context_lines: 3,
                        whitespace: NativeDiffWhitespace::Preserve,
                        layout: NativeDiffLayout::Unified,
                        maximum_rows: DIFF_PAGE_CAPACITY as u32,
                        force_text: false,
                    },
                )
                .page
                .unwrap()
            };
            let execute = |paths: Vec<Vec<u8>>| {
                let page = load();
                repository_session_staging_execute(
                    session.session_id,
                    generation,
                    NativeStagingRequest {
                        request_id: page.request_id,
                        side: NativeStagingSide::Unstaged,
                        scope: NativeStagingScope::Files,
                        paths,
                        row_ids: vec![],
                    },
                )
            };
            assert_eq!(
                execute(vec![
                    b"docs/readme.md".to_vec(),
                    b"docs/nested/plan.md".to_vec()
                ])
                .state,
                NativeStagingExecutionState::Completed
            );
            assert_eq!(git(&["show", ":docs/readme.md"]), b"readme\n");
            assert_eq!(git(&["show", ":docs/nested/plan.md"]), b"plan\n");
            assert_eq!(git(&["show", ":already-staged.txt"]), b"keep\n");
            assert_eq!(git(&["ls-files", "--", "new.txt", "unselected.txt"]), b"");
            assert_eq!(
                execute(vec![b"new.txt".to_vec()]).state,
                NativeStagingExecutionState::Completed
            );
            assert_eq!(git(&["show", ":new.txt"]), b"new\n");
            assert_eq!(git(&["ls-files", "--", "unselected.txt"]), b"");
            assert_eq!(
                execute(vec![b"not-in-status.txt".to_vec()])
                    .failure
                    .map(|failure| failure.kind),
                Some(NativeRepositoryFailureKind::InvalidOptions)
            );
            assert!(repository_session_close(session.session_id, generation).accepted);
        }
    }

    #[test]
    #[cfg(unix)]
    fn staging_a_file_named_like_a_glob_selects_only_that_file() {
        // Regression: staged paths are literal pathspecs, so `*.txt` does not stage `other.txt`.
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .output()
                .unwrap();
            assert!(output.status.success());
            output.stdout
        };
        fs::write(fixture.0.join("*.txt"), b"before\n").unwrap();
        fs::write(fixture.0.join("other.txt"), b"before\n").unwrap();
        git(&["add", "--", "*.txt", "other.txt"]);
        git(&[
            "-c",
            "user.name=GitLama Test",
            "-c",
            "user.email=gitlama@example.invalid",
            "commit",
            "-qm",
            "base",
        ]);
        fs::write(fixture.0.join("*.txt"), b"after\n").unwrap();
        fs::write(fixture.0.join("other.txt"), b"after\n").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            922,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let page = repository_session_working_diff_load(
            session.session_id,
            922,
            NativeWorkingDiffOptions {
                side: NativeStagingSide::Unstaged,
                old_path: None,
                new_path: None,
                context_lines: 3,
                whitespace: NativeDiffWhitespace::Preserve,
                layout: NativeDiffLayout::Unified,
                maximum_rows: DIFF_PAGE_CAPACITY as u32,
                force_text: false,
            },
        )
        .page
        .unwrap();
        assert_eq!(
            repository_session_staging_execute(
                session.session_id,
                922,
                NativeStagingRequest {
                    request_id: page.request_id,
                    side: NativeStagingSide::Unstaged,
                    scope: NativeStagingScope::Files,
                    paths: vec![b"*.txt".to_vec()],
                    row_ids: vec![],
                },
            )
            .state,
            NativeStagingExecutionState::Completed
        );
        assert_eq!(git(&["show", ":*.txt"]), b"after\n");
        assert_eq!(git(&["show", ":other.txt"]), b"before\n");
        assert!(repository_session_close(session.session_id, 922).accepted);
    }

    #[test]
    fn a_binary_file_shown_as_text_stages_only_as_a_whole_file() {
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .output()
                .unwrap();
            assert!(output.status.success());
            output.stdout
        };
        fs::write(fixture.0.join("data.bin"), b"old\0line\n").unwrap();
        git(&["add", "data.bin"]);
        git(&[
            "-c",
            "user.name=GitLama Test",
            "-c",
            "user.email=gitlama@example.invalid",
            "commit",
            "-qm",
            "base",
        ]);
        fs::write(fixture.0.join("data.bin"), b"new\0line\n").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            923,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let load = |force_text| {
            repository_session_working_diff_load(
                session.session_id,
                923,
                NativeWorkingDiffOptions {
                    side: NativeStagingSide::Unstaged,
                    old_path: Some(b"data.bin".to_vec()),
                    new_path: Some(b"data.bin".to_vec()),
                    context_lines: 3,
                    whitespace: NativeDiffWhitespace::Preserve,
                    layout: NativeDiffLayout::Unified,
                    maximum_rows: DIFF_PAGE_CAPACITY as u32,
                    force_text,
                },
            )
            .page
            .unwrap()
        };
        let detected = load(false);
        assert!(detected
            .rows
            .iter()
            .any(|row| row.kind == NativeDiffRowKind::Binary));
        let page = load(true);
        let added = page
            .rows
            .iter()
            .find(|row| row.kind == NativeDiffRowKind::Addition)
            .unwrap();
        assert_eq!(added.text, b"new\0line");
        // Each staging request consumes the diff it was accepted from.
        let stage = |scope, paths: Vec<Vec<u8>>, row_ids: Vec<String>| {
            repository_session_staging_execute(
                session.session_id,
                923,
                NativeStagingRequest {
                    request_id: load(true).request_id,
                    side: NativeStagingSide::Unstaged,
                    scope,
                    paths,
                    row_ids,
                },
            )
        };
        let rows = stage(
            NativeStagingScope::Rows,
            vec![],
            vec![added.stable_id.clone()],
        );
        assert_eq!(rows.state, NativeStagingExecutionState::Failed);
        assert_eq!(git(&["show", ":data.bin"]), b"old\0line\n");
        let files = stage(
            NativeStagingScope::Files,
            vec![b"data.bin".to_vec()],
            vec![],
        );
        assert_eq!(
            files.state,
            NativeStagingExecutionState::Completed,
            "{:?}",
            files.failure
        );
        assert_eq!(git(&["show", ":data.bin"]), b"new\0line\n");
        assert!(repository_session_close(session.session_id, 923).accepted);
    }

    #[test]
    fn stage_all_includes_untracked_files_alongside_tracked_changes() {
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .output()
                .unwrap();
            assert!(output.status.success());
            output.stdout
        };
        fs::write(fixture.0.join("tracked.txt"), b"before\n").unwrap();
        git(&["add", "tracked.txt"]);
        git(&[
            "-c",
            "user.name=GitLama Test",
            "-c",
            "user.email=gitlama@example.invalid",
            "commit",
            "-qm",
            "base",
        ]);
        fs::write(fixture.0.join("tracked.txt"), b"after\n").unwrap();
        fs::write(fixture.0.join("new.txt"), b"new\n").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            921,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let page = repository_session_working_diff_load(
            session.session_id,
            921,
            NativeWorkingDiffOptions {
                side: NativeStagingSide::Unstaged,
                old_path: None,
                new_path: None,
                context_lines: 3,
                whitespace: NativeDiffWhitespace::Preserve,
                layout: NativeDiffLayout::Unified,
                maximum_rows: DIFF_PAGE_CAPACITY as u32,
                force_text: false,
            },
        )
        .page
        .unwrap();
        assert_eq!(
            repository_session_staging_execute(
                session.session_id,
                921,
                NativeStagingRequest {
                    request_id: page.request_id,
                    side: NativeStagingSide::Unstaged,
                    scope: NativeStagingScope::All,
                    paths: vec![],
                    row_ids: vec![],
                },
            )
            .state,
            NativeStagingExecutionState::Completed
        );
        assert_eq!(git(&["show", ":tracked.txt"]), b"after\n");
        assert_eq!(git(&["show", ":new.txt"]), b"new\n");
        assert!(repository_session_close(session.session_id, 921).accepted);
    }

    #[test]
    fn staging_preserves_unselected_bytes_rejects_drift_and_handles_untracked_lines() {
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", fixture.0.join("empty-config"))
                .env("GIT_AUTHOR_NAME", "GitLama Test")
                .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
                .env("GIT_COMMITTER_NAME", "GitLama Test")
                .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "git {arguments:?}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            output.stdout
        };
        fs::write(fixture.0.join("file.txt"), b"one\ntwo\nthree\n").unwrap();
        git(&["add", "file.txt"]);
        git(&["commit", "-qm", "base"]);
        fs::write(fixture.0.join("file.txt"), b"ONE\ntwo\nTHREE\n").unwrap();
        fs::write(fixture.0.join("new.txt"), b"alpha\nbeta\n").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            920,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);

        let load = |side, old: Option<&[u8]>, new: Option<&[u8]>| {
            let loaded = repository_session_working_diff_load(
                session.session_id,
                920,
                NativeWorkingDiffOptions {
                    side,
                    old_path: old.map(<[u8]>::to_vec),
                    new_path: new.map(<[u8]>::to_vec),
                    context_lines: 3,
                    whitespace: NativeDiffWhitespace::Preserve,
                    layout: NativeDiffLayout::Unified,
                    maximum_rows: DIFF_PAGE_CAPACITY as u32,
                    force_text: false,
                },
            );
            match loaded.page {
                Some(page) => page,
                None => panic!(
                    "working diff failed for side {side:?}, old {old:?}, new {new:?}: {:?}",
                    loaded.failure
                ),
            }
        };
        let file = load(
            NativeStagingSide::Unstaged,
            Some(b"file.txt"),
            Some(b"file.txt"),
        );
        let first_replacement = file
            .rows
            .iter()
            .filter(|row| row.text == b"one" || row.text == b"ONE")
            .map(|row| row.stable_id.clone())
            .collect::<Vec<_>>();
        assert_eq!(first_replacement.len(), 2);
        let staged = repository_session_staging_execute(
            session.session_id,
            920,
            NativeStagingRequest {
                request_id: file.request_id,
                side: NativeStagingSide::Unstaged,
                scope: NativeStagingScope::Rows,
                paths: vec![],
                row_ids: first_replacement,
            },
        );
        assert_eq!(staged.state, NativeStagingExecutionState::Completed);
        let operations = application_operation_center(256).snapshot.unwrap();
        assert!(operations.entries.iter().any(|entry| entry.session_id
            == Some(session.session_id)
            && entry.origin == NativeOperationCenterOrigin::User
            && entry.action == NativeOperationCenterAction::Other
            && entry.state == NativeOperationCenterState::Succeeded));
        assert_eq!(git(&["show", ":file.txt"]), b"ONE\ntwo\nthree\n");
        assert_eq!(
            fs::read(fixture.0.join("file.txt")).unwrap(),
            b"ONE\ntwo\nTHREE\n"
        );

        assert_eq!(
            git(&[
                "--literal-pathspecs",
                "status",
                "--porcelain=v2",
                "-z",
                "--untracked-files=all",
                "--",
                "new.txt",
            ]),
            b"? new.txt\0"
        );
        let untracked = load(NativeStagingSide::Unstaged, None, Some(b"new.txt"));
        let alpha = untracked
            .rows
            .iter()
            .find(|row| row.kind == NativeDiffRowKind::Addition && row.text == b"alpha")
            .unwrap()
            .stable_id
            .clone();
        assert_eq!(
            repository_session_staging_execute(
                session.session_id,
                920,
                NativeStagingRequest {
                    request_id: untracked.request_id,
                    side: NativeStagingSide::Unstaged,
                    scope: NativeStagingScope::Rows,
                    paths: vec![],
                    row_ids: vec![alpha],
                },
            )
            .state,
            NativeStagingExecutionState::Completed
        );
        assert_eq!(git(&["show", ":new.txt"]), b"alpha\n");
        assert_eq!(
            fs::read(fixture.0.join("new.txt")).unwrap(),
            b"alpha\nbeta\n"
        );
        let staged_new = load(NativeStagingSide::Staged, None, Some(b"new.txt"));
        assert!(staged_new
            .rows
            .iter()
            .any(|row| { row.kind == NativeDiffRowKind::Addition && row.text == b"alpha" }));

        fs::write(fixture.0.join("hunk.txt"), b"left\nright\n").unwrap();
        let revision = repository_for_session(session.session_id, 920)
            .unwrap()
            .snapshot()
            .revision;
        assert!(repository_session_refresh(session.session_id, 920).accepted);
        wait_for_new_revision(&session, revision);
        let hunk_file = load(NativeStagingSide::Unstaged, None, Some(b"hunk.txt"));
        let hunk = hunk_file
            .rows
            .iter()
            .find(|row| row.kind == NativeDiffRowKind::Hunk)
            .unwrap()
            .stable_id
            .clone();
        assert_eq!(
            repository_session_staging_execute(
                session.session_id,
                920,
                NativeStagingRequest {
                    request_id: hunk_file.request_id,
                    side: NativeStagingSide::Unstaged,
                    scope: NativeStagingScope::Rows,
                    paths: vec![],
                    row_ids: vec![hunk],
                },
            )
            .state,
            NativeStagingExecutionState::Completed
        );
        assert_eq!(git(&["show", ":hunk.txt"]), b"left\nright\n");

        let staged_file = load(
            NativeStagingSide::Staged,
            Some(b"file.txt"),
            Some(b"file.txt"),
        );
        let one = staged_file
            .rows
            .iter()
            .filter(|row| row.text == b"one" || row.text == b"ONE")
            .map(|row| row.stable_id.clone())
            .collect::<Vec<_>>();
        assert_eq!(
            repository_session_staging_execute(
                session.session_id,
                920,
                NativeStagingRequest {
                    request_id: staged_file.request_id,
                    side: NativeStagingSide::Staged,
                    scope: NativeStagingScope::Rows,
                    paths: vec![],
                    row_ids: one,
                },
            )
            .state,
            NativeStagingExecutionState::Completed
        );
        assert_eq!(git(&["show", ":file.txt"]), b"one\ntwo\nthree\n");

        let raced = load(
            NativeStagingSide::Unstaged,
            Some(b"file.txt"),
            Some(b"file.txt"),
        );
        fs::write(fixture.0.join("other.txt"), b"other\n").unwrap();
        git(&["add", "other.txt"]);
        let before = fs::read(fixture.0.join(".git/index")).unwrap();
        let result = repository_session_staging_execute(
            session.session_id,
            920,
            NativeStagingRequest {
                request_id: raced.request_id,
                side: NativeStagingSide::Unstaged,
                scope: NativeStagingScope::Files,
                paths: vec![b"file.txt".to_vec()],
                row_ids: vec![],
            },
        );
        assert_eq!(result.state, NativeStagingExecutionState::Stale);
        assert_eq!(fs::read(fixture.0.join(".git/index")).unwrap(), before);
        assert_eq!(
            repository_session_staging_execute(
                session.session_id,
                920,
                NativeStagingRequest {
                    request_id: raced.request_id,
                    side: NativeStagingSide::Unstaged,
                    scope: NativeStagingScope::Files,
                    paths: vec![b"file.txt".to_vec()],
                    row_ids: vec![],
                },
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::InvalidOptions
        );

        fs::write(
            fixture.0.join(".gitattributes"),
            b"filtered.txt filter=fail\n",
        )
        .unwrap();
        fs::write(fixture.0.join("filtered.txt"), b"must not stage\n").unwrap();
        let revision = repository_for_session(session.session_id, 920)
            .unwrap()
            .snapshot()
            .revision;
        assert!(repository_session_refresh(session.session_id, 920).accepted);
        wait_for_new_revision(&session, revision);
        let filtered = load(NativeStagingSide::Unstaged, None, Some(b"filtered.txt"));
        git(&["config", "filter.fail.clean", "false"]);
        git(&["config", "filter.fail.required", "true"]);
        let before_failed_process = fs::read(fixture.0.join(".git/index")).unwrap();
        let failed_process = repository_session_staging_execute(
            session.session_id,
            920,
            NativeStagingRequest {
                request_id: filtered.request_id,
                side: NativeStagingSide::Unstaged,
                scope: NativeStagingScope::Files,
                paths: vec![b"filtered.txt".to_vec()],
                row_ids: vec![],
            },
        );
        assert_eq!(failed_process.state, NativeStagingExecutionState::Failed);
        assert_eq!(
            fs::read(fixture.0.join(".git/index")).unwrap(),
            before_failed_process
        );
        fs::remove_file(fixture.0.join("filtered.txt")).unwrap();
        fs::remove_file(fixture.0.join(".gitattributes")).unwrap();
        git(&["config", "--unset", "filter.fail.clean"]);
        git(&["config", "--unset", "filter.fail.required"]);

        let revision = repository_for_session(session.session_id, 920)
            .unwrap()
            .snapshot()
            .revision;
        assert!(repository_session_refresh(session.session_id, 920).accepted);
        wait_for_new_revision(&session, revision);
        let superseded = load(NativeStagingSide::Unstaged, None, None);
        let all = load(NativeStagingSide::Unstaged, None, None);
        assert_eq!(
            repository_session_staging_execute(
                session.session_id,
                920,
                NativeStagingRequest {
                    request_id: superseded.request_id,
                    side: NativeStagingSide::Unstaged,
                    scope: NativeStagingScope::All,
                    paths: vec![],
                    row_ids: vec![],
                },
            )
            .state,
            NativeStagingExecutionState::Stale
        );
        assert_eq!(
            repository_session_staging_execute(
                session.session_id,
                920,
                NativeStagingRequest {
                    request_id: all.request_id,
                    side: NativeStagingSide::Unstaged,
                    scope: NativeStagingScope::All,
                    paths: vec![],
                    row_ids: vec![],
                },
            )
            .state,
            NativeStagingExecutionState::Completed
        );
        assert_eq!(git(&["show", ":file.txt"]), b"ONE\ntwo\nTHREE\n");
        assert_eq!(git(&["show", ":new.txt"]), b"alpha\nbeta\n");
        let staged_all = load(NativeStagingSide::Staged, None, None);
        assert_eq!(
            repository_session_staging_execute(
                session.session_id,
                920,
                NativeStagingRequest {
                    request_id: staged_all.request_id,
                    side: NativeStagingSide::Staged,
                    scope: NativeStagingScope::All,
                    paths: vec![],
                    row_ids: vec![],
                },
            )
            .state,
            NativeStagingExecutionState::Completed
        );
        assert!(Command::new("git")
            .args(["diff", "--cached", "--quiet"])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());

        let locked = load(
            NativeStagingSide::Unstaged,
            Some(b"file.txt"),
            Some(b"file.txt"),
        );
        let index_before = fs::read(fixture.0.join(".git/index")).unwrap();
        fs::write(fixture.0.join(".git/index.lock"), b"owned elsewhere").unwrap();
        let failed = repository_session_staging_execute(
            session.session_id,
            920,
            NativeStagingRequest {
                request_id: locked.request_id,
                side: NativeStagingSide::Unstaged,
                scope: NativeStagingScope::Files,
                paths: vec![b"file.txt".to_vec()],
                row_ids: vec![],
            },
        );
        assert_eq!(failed.state, NativeStagingExecutionState::Failed);
        assert_eq!(
            fs::read(fixture.0.join(".git/index")).unwrap(),
            index_before
        );
        assert_eq!(
            fs::read(fixture.0.join(".git/index.lock")).unwrap(),
            b"owned elsewhere"
        );
        fs::remove_file(fixture.0.join(".git/index.lock")).unwrap();

        let viewed = repository_session_working_diff_load(
            session.session_id,
            920,
            NativeWorkingDiffOptions {
                side: NativeStagingSide::Unstaged,
                old_path: Some(b"file.txt".to_vec()),
                new_path: Some(b"file.txt".to_vec()),
                context_lines: 0,
                whitespace: NativeDiffWhitespace::IgnoreEndOfLine,
                layout: NativeDiffLayout::SideBySide,
                maximum_rows: DIFF_PAGE_CAPACITY as u32,
                force_text: false,
            },
        )
        .page
        .expect("working diff viewing options must load");
        assert_eq!(viewed.layout, NativeDiffLayout::SideBySide);

        let closed = load(
            NativeStagingSide::Unstaged,
            Some(b"file.txt"),
            Some(b"file.txt"),
        );
        assert!(repository_session_close(session.session_id, 920).accepted);
        assert_eq!(
            repository_session_staging_execute(
                session.session_id,
                920,
                NativeStagingRequest {
                    request_id: closed.request_id,
                    side: NativeStagingSide::Unstaged,
                    scope: NativeStagingScope::Files,
                    paths: vec![b"file.txt".to_vec()],
                    row_ids: vec![],
                },
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::RetiredSession
        );
    }
}
