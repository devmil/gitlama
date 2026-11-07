//! Repository extension inventory and mutation workflows.
pub use gitlama_contract::extensions::*;

use crate::activity::{allocate_activity_id, ActivityStore};
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::domain::path_identity::{native_path, native_path_identity};
use crate::operations::{coordinate_mutation, ExecutionFailure};
use devmil_git::activity::ActivityStatus;
use devmil_git::loading::extensions::{LfsPathState, SubmoduleCheckoutState};
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::types::RepositoryRelativePath;
use devmil_git::{Repository, RepositoryErrorKind};
use std::ffi::OsString;
use std::path::Path;
use std::sync::atomic::AtomicBool;
use std::time::Duration;

const READ_TIMEOUT: Duration = Duration::from_secs(30);

pub(crate) fn inventory(repository: &Repository) -> NativeExtensionInventoryResult {
    let snapshot = repository.snapshot();
    let Some(current) = snapshot.repository.as_ref() else {
        return inventory_failure(NativeExtensionFailureKind::Read);
    };
    let current_root = current.worktree.worktree_root().as_path();
    let worktrees = match repository
        .worktrees()
        .ok()
        .and_then(|ticket| ticket.recv_timeout(READ_TIMEOUT))
    {
        Some(Ok(value)) => value,
        Some(Err(error)) => return inventory_failure(map_error(error.kind)),
        None => return inventory_failure(NativeExtensionFailureKind::Read),
    };
    let submodules = match repository
        .submodules()
        .ok()
        .and_then(|ticket| ticket.recv_timeout(READ_TIMEOUT))
    {
        Some(Ok(value)) => value,
        Some(Err(error)) => return inventory_failure(map_error(error.kind)),
        None => return inventory_failure(NativeExtensionFailureKind::Read),
    };
    let lfs = match repository
        .lfs_status()
        .ok()
        .and_then(|ticket| ticket.recv_timeout(READ_TIMEOUT))
    {
        Some(Ok(value)) => value,
        Some(Err(error)) => return inventory_failure(map_error(error.kind)),
        None => return inventory_failure(NativeExtensionFailureKind::Read),
    };
    let mut activity_ids = worktrees
        .activities
        .iter()
        .chain(submodules.activities.iter())
        .chain(lfs.activities.iter())
        .map(|record| record.id.get().to_string())
        .collect::<Vec<_>>();
    activity_ids.sort();
    activity_ids.dedup();
    NativeExtensionInventoryResult {
        inventory: Some(NativeExtensionInventory {
            worktrees: worktrees
                .worktrees
                .iter()
                .map(|entry| NativeWorktreeEntry {
                    worktree_root: native_path_identity(entry.identity.worktree_root().as_path()),
                    git_dir: native_path_identity(entry.identity.git_dir().as_path()),
                    common_git_dir: native_path_identity(
                        entry.identity.repository().common_git_dir().as_path(),
                    ),
                    head: entry.head.as_ref().map(|value| value.as_str().to_owned()),
                    branch: entry.branch.as_ref().map(|value| value.as_bytes().to_vec()),
                    locked: entry.locked,
                    prunable: entry.prunable,
                    current: same_worktree_path(
                        entry.identity.worktree_root().as_path(),
                        current_root,
                    ),
                })
                .collect(),
            submodules: submodules
                .submodules
                .iter()
                .map(|entry| NativeSubmoduleEntry {
                    path: native_path_bytes(entry.path.as_path()),
                    commit: entry.commit.as_str().to_owned(),
                    state: match entry.checkout {
                        SubmoduleCheckoutState::AtRecordedCommit => {
                            NativeSubmoduleState::AtRecordedCommit
                        }
                        SubmoduleCheckoutState::DifferentCommit => {
                            NativeSubmoduleState::DifferentCommit
                        }
                        SubmoduleCheckoutState::Uninitialized => {
                            NativeSubmoduleState::Uninitialized
                        }
                        SubmoduleCheckoutState::Conflicted => NativeSubmoduleState::Conflicted,
                    },
                })
                .collect(),
            lfs_available: lfs.available,
            lfs_unavailable_reason: !lfs.available,
            lfs_entries: lfs
                .entries
                .iter()
                .map(|entry| NativeLfsEntry {
                    path: native_path_bytes(entry.path.as_path()),
                    state: match entry.state {
                        LfsPathState::Pointer => NativeLfsPathState::Pointer,
                        LfsPathState::Materialized => NativeLfsPathState::Materialized,
                        LfsPathState::Missing => NativeLfsPathState::Missing,
                    },
                    pointer: entry.pointer.as_ref().map(|pointer| NativeLfsPointer {
                        oid_sha256: pointer.oid_sha256.clone(),
                        size: pointer.size,
                    }),
                })
                .collect(),
            activity_ids,
        }),
        failure: None,
    }
}

pub(crate) use devmil_git::commands::worktree::same_worktree_path;

pub(crate) fn enter_submodule(
    repository: &Repository,
    path: Vec<u8>,
) -> NativeSubmoduleEnterResult {
    let Ok(path) = relative_path(path) else {
        return enter_failure(NativeExtensionFailureKind::InvalidRequest);
    };
    match repository
        .enter_submodule(path)
        .ok()
        .and_then(|ticket| ticket.recv_timeout(READ_TIMEOUT))
    {
        Some(Ok(identity)) => NativeSubmoduleEnterResult {
            worktree_root: Some(native_path_identity(identity.worktree_root().as_path())),
            failure: None,
        },
        Some(Err(error)) => enter_failure(map_error(error.kind)),
        None => enter_failure(NativeExtensionFailureKind::Read),
    }
}

pub(crate) fn lfs_pointer(repository: &Repository, path: Vec<u8>) -> NativeLfsPointerResult {
    let Ok(path) = relative_path(path) else {
        return pointer_failure(NativeExtensionFailureKind::InvalidRequest);
    };
    match repository
        .lfs_pointer_preview(path)
        .ok()
        .and_then(|ticket| ticket.recv_timeout(READ_TIMEOUT))
    {
        Some(Ok(value)) => NativeLfsPointerResult {
            pointer: value.as_ref().as_ref().map(|pointer| NativeLfsPointer {
                oid_sha256: pointer.oid_sha256.clone(),
                size: pointer.size,
            }),
            failure: None,
        },
        Some(Err(error)) => pointer_failure(map_error(error.kind)),
        None => pointer_failure(NativeExtensionFailureKind::Read),
    }
}

pub(crate) fn execute(
    repository: &Repository,
    activity: &ActivityStore,
    request: NativeExtensionMutationRequest,
) -> NativeExtensionMutationResult {
    let snapshot = repository.snapshot();
    let Some(discovered) = snapshot.repository.as_ref() else {
        return mutation_failure(NativeExtensionFailureKind::Read);
    };
    let worktree = discovered.worktree.worktree_root().as_path().to_path_buf();
    if request.kind == NativeExtensionMutationKind::IgnoreAdd {
        return add_ignore_pattern(repository, &worktree, &request);
    }
    let arguments = if request.kind == NativeExtensionMutationKind::WorktreeDelete {
        None
    } else {
        match arguments(&request, repository) {
            Ok(value) => Some(value),
            Err(kind) => return mutation_failure(kind),
        }
    };
    let cancellation = AtomicBool::new(false);
    let sink = activity.sink();
    let mut activity_ids = Vec::new();
    let mut failure = None;
    let outcome = coordinate_mutation(repository, &cancellation, |cancellation| {
        let arguments = match arguments {
            Some(value) => value,
            None => {
                let mut executor = |command| {
                    let id = allocate_activity_id();
                    activity_ids.push(id.get().to_string());
                    ActivityGitRunner::run_private(command, id, Some(cancellation), &mut |event| {
                        sink(event)
                    })
                };
                match worktree_remove_arguments(
                    &request,
                    repository,
                    &discovered.worktree,
                    &mut executor,
                    cancellation,
                ) {
                    Ok(value) => value,
                    Err(kind) => {
                        failure = Some(kind);
                        return Err(if kind == NativeExtensionFailureKind::Canceled {
                            ExecutionFailure::Canceled
                        } else {
                            ExecutionFailure::Definite
                        });
                    }
                }
            }
        };
        let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
        activity_ids.push(id.get().to_string());
        let command = GitProcessCommand::git(repository.git_executable().to_owned())
            .current_dir(&worktree)
            .args(arguments.into_iter().map(ProcessArgument::visible))
            .redact_output();
        let mut publish = |event| sink(event);
        let result = ActivityGitRunner::run_private(command, id, Some(cancellation), &mut publish);
        match result.activity.status {
            ActivityStatus::Succeeded { .. } => Ok(()),
            ActivityStatus::Canceled { .. } => {
                failure = Some(NativeExtensionFailureKind::Canceled);
                Err(ExecutionFailure::Canceled)
            }
            _ => {
                failure = Some(NativeExtensionFailureKind::Git);
                Err(ExecutionFailure::Definite)
            }
        }
    });
    terminal_result(outcome, failure, activity_ids)
}

/// Writes the pattern without running Git; the repository reload afterwards shows its effect.
fn add_ignore_pattern(
    repository: &Repository,
    worktree: &Path,
    request: &NativeExtensionMutationRequest,
) -> NativeExtensionMutationResult {
    let pattern = match request.pattern.as_deref() {
        Some(pattern)
            if request.path.is_none()
                && request.reference.is_none()
                && request.worktree_root.is_none()
                && devmil_git::ignore::validate_pattern(pattern).is_ok() =>
        {
            pattern
        }
        _ => return mutation_failure(NativeExtensionFailureKind::InvalidRequest),
    };
    let cancellation = AtomicBool::new(false);
    let mut failure = None;
    let outcome = coordinate_mutation(repository, &cancellation, |_| {
        devmil_git::ignore::add_ignore_pattern(worktree, pattern)
            .map(|_| ())
            .map_err(|error| {
                use devmil_git::ignore::IgnoreError;
                failure = Some(match error {
                    IgnoreError::InvalidPattern => NativeExtensionFailureKind::InvalidRequest,
                    IgnoreError::TooLarge => NativeExtensionFailureKind::TooLarge,
                    IgnoreError::UnsafeFile | IgnoreError::Io => NativeExtensionFailureKind::Read,
                });
                ExecutionFailure::Definite
            })
    });
    terminal_result(outcome, failure, Vec::new())
}

fn terminal_result(
    outcome: crate::operations::MutationTerminalState,
    failure: Option<NativeExtensionFailureKind>,
    activity_ids: Vec<String>,
) -> NativeExtensionMutationResult {
    let outcome = MutationOutcome::from_terminal(outcome);
    // A failure the mutation did not name is a refusal, or a read for anything else.
    let failure = failure.or(match outcome.state {
        MutationState::Canceled => Some(NativeExtensionFailureKind::Canceled),
        MutationState::Failed | MutationState::OutcomeUncertain => {
            Some(NativeExtensionFailureKind::Read)
        }
        _ => None,
    });
    mutation_result(outcome.with_failure(failure), activity_ids)
}

/// The bridge result of an extension mutation: the one place its outcome becomes a state.
fn mutation_result(
    outcome: MutationOutcome<NativeExtensionFailureKind>,
    activity_ids: Vec<String>,
) -> NativeExtensionMutationResult {
    NativeExtensionMutationResult {
        state: match outcome.state {
            MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
                NativeExtensionMutationState::Completed
            }
            MutationState::ReconciledWithWarning => {
                NativeExtensionMutationState::ReconciledWithWarning
            }
            MutationState::Canceled => NativeExtensionMutationState::Canceled,
            MutationState::Conflict
            | MutationState::Interrupted
            | MutationState::EditStop
            | MutationState::Partial
            | MutationState::Stale
            | MutationState::Failed => NativeExtensionMutationState::Failed,
            MutationState::OutcomeUncertain => NativeExtensionMutationState::OutcomeUncertain,
        },
        activity_ids,
        failure: outcome.failure.map(|kind| NativeExtensionFailure { kind }),
    }
}

fn arguments(
    request: &NativeExtensionMutationRequest,
    repository: &Repository,
) -> Result<Vec<OsString>, NativeExtensionFailureKind> {
    match request.kind {
        NativeExtensionMutationKind::SubmoduleInit
        | NativeExtensionMutationKind::SubmoduleUpdate => {
            let path = request
                .path
                .clone()
                .ok_or(NativeExtensionFailureKind::InvalidRequest)
                .and_then(relative_path)?;
            if request.pattern.is_some()
                || request.reference.is_some()
                || request.worktree_root.is_some()
            {
                return Err(NativeExtensionFailureKind::InvalidRequest);
            }
            Ok(devmil_git::commands::submodule::submodule_update_arguments(
                &path,
                request.kind == NativeExtensionMutationKind::SubmoduleInit,
            ))
        }
        NativeExtensionMutationKind::LfsTrack | NativeExtensionMutationKind::LfsUntrack => {
            use devmil_git::commands::submodule::LfsRequest;
            let pattern = request
                .pattern
                .clone()
                .ok_or(NativeExtensionFailureKind::InvalidRequest)?;
            if request.path.is_some()
                || request.reference.is_some()
                || request.worktree_root.is_some()
            {
                return Err(NativeExtensionFailureKind::InvalidRequest);
            }
            let request = if request.kind == NativeExtensionMutationKind::LfsTrack {
                LfsRequest::Track(pattern)
            } else {
                LfsRequest::Untrack(pattern)
            };
            let arguments = devmil_git::commands::submodule::lfs_arguments(&request)
                .map_err(|_| NativeExtensionFailureKind::InvalidRequest)?;
            ensure_lfs(repository)?;
            Ok(arguments)
        }
        NativeExtensionMutationKind::LfsPull => {
            if request.path.is_some()
                || request.pattern.is_some()
                || request.reference.is_some()
                || request.worktree_root.is_some()
            {
                return Err(NativeExtensionFailureKind::InvalidRequest);
            }
            ensure_lfs(repository)?;
            devmil_git::commands::submodule::lfs_arguments(
                &devmil_git::commands::submodule::LfsRequest::Pull,
            )
            .map_err(|_| NativeExtensionFailureKind::InvalidRequest)
        }
        NativeExtensionMutationKind::WorktreeCreate => {
            let path = request
                .worktree_root
                .as_ref()
                .ok_or(NativeExtensionFailureKind::InvalidRequest)
                .and_then(|value| {
                    native_path(value).ok_or(NativeExtensionFailureKind::InvalidRequest)
                })?;
            if !path.is_absolute() {
                return Err(NativeExtensionFailureKind::InvalidRequest);
            }
            let reference = request
                .reference
                .as_deref()
                .ok_or(NativeExtensionFailureKind::InvalidRequest)?;
            if request.pattern.is_some() || path.exists() {
                return Err(NativeExtensionFailureKind::InvalidRequest);
            }
            devmil_git::commands::worktree::add_arguments(&path, reference)
                .map_err(|_| NativeExtensionFailureKind::InvalidRequest)
        }
        NativeExtensionMutationKind::WorktreeDelete | NativeExtensionMutationKind::IgnoreAdd => {
            Err(NativeExtensionFailureKind::InvalidRequest)
        }
    }
}

fn ensure_lfs(repository: &Repository) -> Result<(), NativeExtensionFailureKind> {
    let value = repository
        .lfs_status()
        .ok()
        .and_then(|ticket| ticket.recv_timeout(READ_TIMEOUT))
        .ok_or(NativeExtensionFailureKind::Read)?
        .map_err(|error| map_error(error.kind))?;
    value
        .available
        .then_some(())
        .ok_or(NativeExtensionFailureKind::Unavailable)
}

fn worktree_remove_arguments(
    request: &NativeExtensionMutationRequest,
    repository: &Repository,
    current: &devmil_git::types::WorktreeId,
    executor: &mut dyn devmil_git::loading::CommandExecutor,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
) -> Result<Vec<OsString>, NativeExtensionFailureKind> {
    if request.path.is_some() || request.pattern.is_some() || request.reference.is_some() {
        return Err(NativeExtensionFailureKind::InvalidRequest);
    }
    let path = request
        .worktree_root
        .as_ref()
        .and_then(native_path)
        .ok_or(NativeExtensionFailureKind::InvalidRequest)?;
    devmil_git::commands::worktree::remove_arguments(
        repository.git_executable(),
        current,
        &path,
        executor,
        cancellation,
    )
    .map_err(|error| match error {
        devmil_git::commands::worktree::RemoveError::InvalidTarget => {
            NativeExtensionFailureKind::InvalidRequest
        }
        devmil_git::commands::worktree::RemoveError::Stale => NativeExtensionFailureKind::Stale,
        devmil_git::commands::worktree::RemoveError::Protected => {
            NativeExtensionFailureKind::CurrentWorktree
        }
        devmil_git::commands::worktree::RemoveError::Locked => NativeExtensionFailureKind::Locked,
        devmil_git::commands::worktree::RemoveError::Dirty => NativeExtensionFailureKind::Dirty,
        devmil_git::commands::worktree::RemoveError::Canceled => {
            NativeExtensionFailureKind::Canceled
        }
        devmil_git::commands::worktree::RemoveError::Read => NativeExtensionFailureKind::Read,
        devmil_git::commands::worktree::RemoveError::Git => NativeExtensionFailureKind::Git,
    })
}

fn map_error(kind: RepositoryErrorKind) -> NativeExtensionFailureKind {
    match kind {
        RepositoryErrorKind::InvalidOptions | RepositoryErrorKind::Unsupported => {
            NativeExtensionFailureKind::InvalidRequest
        }
        RepositoryErrorKind::Canceled | RepositoryErrorKind::Closed => {
            NativeExtensionFailureKind::Canceled
        }
        RepositoryErrorKind::TooLarge => NativeExtensionFailureKind::TooLarge,
        RepositoryErrorKind::MissingGit => NativeExtensionFailureKind::Unavailable,
        _ => NativeExtensionFailureKind::Read,
    }
}

fn inventory_failure(kind: NativeExtensionFailureKind) -> NativeExtensionInventoryResult {
    NativeExtensionInventoryResult {
        inventory: None,
        failure: Some(NativeExtensionFailure { kind }),
    }
}

fn enter_failure(kind: NativeExtensionFailureKind) -> NativeSubmoduleEnterResult {
    NativeSubmoduleEnterResult {
        worktree_root: None,
        failure: Some(NativeExtensionFailure { kind }),
    }
}

fn pointer_failure(kind: NativeExtensionFailureKind) -> NativeLfsPointerResult {
    NativeLfsPointerResult {
        pointer: None,
        failure: Some(NativeExtensionFailure { kind }),
    }
}

fn mutation_failure(kind: NativeExtensionFailureKind) -> NativeExtensionMutationResult {
    NativeExtensionMutationResult {
        state: NativeExtensionMutationState::Failed,
        activity_ids: Vec::new(),
        failure: Some(NativeExtensionFailure { kind }),
    }
}

fn relative_path(bytes: Vec<u8>) -> Result<RepositoryRelativePath, NativeExtensionFailureKind> {
    devmil_git::native_bytes::bytes_to_path_buf(&bytes)
        .ok()
        .and_then(|path| RepositoryRelativePath::new(path).ok())
        .ok_or(NativeExtensionFailureKind::InvalidRequest)
}

fn native_path_bytes(path: &Path) -> Vec<u8> {
    devmil_git::native_bytes::path_to_bytes(path)
}

crate::family_failures!(NativeExtensionFailureKind, "extension", {
    InvalidRequest => InvalidRequest,
    Unavailable => Unavailable,
    Dirty => Precondition,
    Locked => Busy,
    CurrentWorktree => Precondition,
    Stale => Stale,
    Canceled => Canceled,
    TooLarge => TooLarge,
    Read => Read,
    Git => Git,
});

#[cfg(test)]
mod outcome_tests {
    use super::*;
    use crate::domain::outcome::MutationTerminalState;

    #[test]
    fn an_uncertain_extension_mutation_stays_uncertain() {
        let outcome = MutationOutcome::from_terminal(MutationTerminalState::OutcomeUncertain)
            .with_failure(Some(NativeExtensionFailureKind::Git));
        let result = mutation_result(outcome, vec!["3".to_owned()]);
        assert_eq!(result.state, NativeExtensionMutationState::OutcomeUncertain);
        assert_eq!(
            result.failure.map(|failure| failure.kind),
            Some(NativeExtensionFailureKind::Git)
        );
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{extensions::*, session::*};

    use crate::extensions::{
        NativeExtensionFailureKind, NativeExtensionMutationKind, NativeExtensionMutationRequest,
        NativeExtensionMutationState, NativeSubmoduleState,
    };

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[cfg(unix)]
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn repository_extensions_add_ignore_patterns_to_the_top_level_gitignore() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["commit", "--allow-empty", "-qm", "base"]);
        fs::create_dir_all(fixture.0.join("build")).unwrap();
        fs::write(fixture.0.join("build/out.log"), b"x").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_219,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let add = |pattern: &str, path: Option<Vec<u8>>| {
            repository_session_extension_execute(
                session.session_id,
                session.generation,
                NativeExtensionMutationRequest {
                    kind: NativeExtensionMutationKind::IgnoreAdd,
                    path,
                    worktree_root: None,
                    pattern: Some(pattern.to_owned()),
                    reference: None,
                },
            )
        };
        assert_eq!(
            add("/build/out.log", None).state,
            NativeExtensionMutationState::Completed
        );
        assert_eq!(
            add("/build/out.log", None).state,
            NativeExtensionMutationState::Completed
        );
        assert_eq!(
            fs::read(fixture.0.join(".gitignore")).unwrap(),
            b"/build/out.log\n"
        );
        for invalid in [
            add("# note", None),
            add("a\nb", None),
            add("/x", Some(b"x".to_vec())),
        ] {
            assert_eq!(
                invalid.failure.unwrap().kind,
                NativeExtensionFailureKind::InvalidRequest
            );
        }
        assert_eq!(
            fs::read(fixture.0.join(".gitignore")).unwrap(),
            b"/build/out.log\n"
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn repository_extensions_remove_only_selected_missing_worktree_registration() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["commit", "--allow-empty", "-qm", "base"]);
        let first = fixture.0.join("missing-first");
        let second = fixture.0.join("missing-second");
        for target in [&first, &second] {
            transfer_git(
                &fixture.0,
                &["worktree", "add", "--detach", target.to_str().unwrap()],
            );
            fs::remove_dir_all(target).unwrap();
        }
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_218,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let before = repository_session_extensions(session.session_id, session.generation)
            .inventory
            .unwrap();
        assert_eq!(before.worktrees.len(), 3);
        assert_eq!(
            before
                .worktrees
                .iter()
                .filter(|entry| entry.prunable)
                .count(),
            2
        );
        let result = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::WorktreeDelete,
                path: None,
                worktree_root: Some(crate::domain::path_identity::native_path_identity(&first)),
                pattern: None,
                reference: None,
            },
        );
        assert_eq!(result.state, NativeExtensionMutationState::Completed);
        assert!(result.failure.is_none());
        let after = repository_session_extensions(session.session_id, session.generation)
            .inventory
            .unwrap();
        assert_eq!(after.worktrees.len(), 2);
        assert!(after
            .worktrees
            .iter()
            .all(|entry| !crate::extensions::same_worktree_path(
                &crate::domain::path_identity::native_path(&entry.worktree_root).unwrap(),
                &first
            )));
        assert!(after
            .worktrees
            .iter()
            .any(|entry| crate::extensions::same_worktree_path(
                &crate::domain::path_identity::native_path(&entry.worktree_root).unwrap(),
                &second
            )));
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn repository_extensions_manage_worktrees_and_parse_lfs_pointers() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        let linked = fixture.0.with_extension("linked-worktree");
        let _ = fs::remove_dir_all(&linked);
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_215,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);

        let initial = repository_session_extensions(session.session_id, session.generation)
            .inventory
            .unwrap();
        assert_eq!(initial.worktrees.len(), 1);
        assert!(initial.worktrees[0].current);
        let only = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::WorktreeDelete,
                path: None,
                worktree_root: Some(crate::domain::path_identity::native_path_identity(
                    &fixture.0,
                )),
                pattern: None,
                reference: None,
            },
        );
        assert_eq!(
            only.failure.unwrap().kind,
            NativeExtensionFailureKind::CurrentWorktree
        );
        let created = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::WorktreeCreate,
                path: None,
                worktree_root: Some(crate::domain::path_identity::native_path_identity(&linked)),
                pattern: None,
                reference: Some("HEAD".to_owned()),
            },
        );
        assert_eq!(created.state, NativeExtensionMutationState::Completed);
        let inventory = repository_session_extensions(session.session_id, session.generation)
            .inventory
            .unwrap();
        assert_eq!(inventory.worktrees.len(), 2);
        assert!(inventory.worktrees.iter().any(|entry| {
            crate::domain::path_identity::native_path(&entry.worktree_root).is_some_and(|root| {
                crate::extensions::same_worktree_path(&root, &linked) && !entry.current
            })
        }));

        let linked_session = repository_session_open_with_options(
            linked.clone(),
            1_216,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&linked_session);
        let main = repository_session_extension_execute(
            linked_session.session_id,
            linked_session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::WorktreeDelete,
                path: None,
                worktree_root: Some(crate::domain::path_identity::native_path_identity(
                    &fixture.0,
                )),
                pattern: None,
                reference: None,
            },
        );
        assert_eq!(
            main.failure.unwrap().kind,
            NativeExtensionFailureKind::CurrentWorktree
        );
        assert!(
            repository_session_close(linked_session.session_id, linked_session.generation).accepted
        );

        fs::write(linked.join("dirty.txt"), b"dirty\n").unwrap();
        let dirty = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::WorktreeDelete,
                path: None,
                worktree_root: Some(crate::domain::path_identity::native_path_identity(&linked)),
                pattern: None,
                reference: None,
            },
        );
        assert_eq!(
            dirty.failure.unwrap().kind,
            NativeExtensionFailureKind::Dirty
        );
        fs::remove_file(linked.join("dirty.txt")).unwrap();
        transfer_git(&fixture.0, &["worktree", "lock", linked.to_str().unwrap()]);
        refresh_session(&session);
        let locked = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::WorktreeDelete,
                path: None,
                worktree_root: Some(crate::domain::path_identity::native_path_identity(&linked)),
                pattern: None,
                reference: None,
            },
        );
        assert_eq!(
            locked.failure.unwrap().kind,
            NativeExtensionFailureKind::Locked
        );
        transfer_git(
            &fixture.0,
            &["worktree", "unlock", linked.to_str().unwrap()],
        );
        refresh_session(&session);
        let removed = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::WorktreeDelete,
                path: None,
                worktree_root: Some(crate::domain::path_identity::native_path_identity(&linked)),
                pattern: None,
                reference: None,
            },
        );
        assert_eq!(removed.state, NativeExtensionMutationState::Completed);
        assert!(!linked.exists());
        assert_eq!(
            repository_session_extension_execute(
                session.session_id,
                session.generation,
                NativeExtensionMutationRequest {
                    kind: NativeExtensionMutationKind::WorktreeCreate,
                    path: None,
                    worktree_root: Some(crate::domain::path_identity::native_path_identity(
                        &linked
                    )),
                    pattern: None,
                    reference: Some("HEAD".to_owned()),
                },
            )
            .state,
            NativeExtensionMutationState::Completed
        );
        transfer_git(
            &fixture.0,
            &["worktree", "remove", linked.to_str().unwrap()],
        );
        let externally_deleted = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::WorktreeDelete,
                path: None,
                worktree_root: Some(crate::domain::path_identity::native_path_identity(&linked)),
                pattern: None,
                reference: None,
            },
        );
        assert_eq!(
            externally_deleted.failure.unwrap().kind,
            NativeExtensionFailureKind::Stale
        );

        let pointer_bytes = b"version https://git-lfs.github.com/spec/v1\noid sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\nsize 42\n";
        fs::write(fixture.0.join("asset.bin"), pointer_bytes).unwrap();
        refresh_session(&session);
        let pointer = repository_session_lfs_pointer(
            session.session_id,
            session.generation,
            b"asset.bin".to_vec(),
        );
        assert_eq!(pointer.pointer.unwrap().size, 42);
        fs::write(fixture.0.join("bad.bin"), b"not an lfs pointer\n").unwrap();
        refresh_session(&session);
        assert!(repository_session_lfs_pointer(
            session.session_id,
            session.generation,
            b"bad.bin".to_vec(),
        )
        .pointer
        .is_none());
        let tracked = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::LfsTrack,
                path: None,
                worktree_root: None,
                pattern: Some("*.bin".to_owned()),
                reference: None,
            },
        );
        assert_eq!(tracked.state, NativeExtensionMutationState::Completed);
        assert!(
            String::from_utf8(fs::read(fixture.0.join(".gitattributes")).unwrap())
                .unwrap()
                .contains("*.bin filter=lfs")
        );
        let untracked = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::LfsUntrack,
                path: None,
                worktree_root: None,
                pattern: Some("*.bin".to_owned()),
                reference: None,
            },
        );
        assert_eq!(untracked.state, NativeExtensionMutationState::Completed);
        assert!(
            !String::from_utf8(fs::read(fixture.0.join(".gitattributes")).unwrap())
                .unwrap()
                .contains("*.bin filter=lfs")
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
        let _ = fs::remove_dir_all(linked);
    }

    #[test]
    fn repository_extensions_initialize_update_and_enter_submodules() {
        let middle = GitFixture::new();
        fs::write(middle.0.join("middle.txt"), b"middle\n").unwrap();
        transfer_git(&middle.0, &["add", "middle.txt"]);
        transfer_git(&middle.0, &["commit", "-qm", "middle"]);

        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "protocol.file.allow", "always"]);
        fs::write(fixture.0.join("root.txt"), b"root\n").unwrap();
        transfer_git(&fixture.0, &["add", "root.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "root"]);
        transfer_git(
            &fixture.0,
            &[
                "-c",
                "protocol.file.allow=always",
                "submodule",
                "add",
                middle.0.to_str().unwrap(),
                "modules/middle",
            ],
        );
        transfer_git(&fixture.0, &["commit", "-qam", "add middle"]);
        transfer_git(&fixture.0, &["submodule", "deinit", "-f", "--all"]);

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_216,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let before = repository_session_extensions(session.session_id, session.generation)
            .inventory
            .unwrap();
        assert_eq!(before.submodules.len(), 1);
        assert_eq!(
            before.submodules[0].state,
            NativeSubmoduleState::Uninitialized
        );
        let initialized = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::SubmoduleInit,
                path: Some(b"modules/middle".to_vec()),
                worktree_root: None,
                pattern: None,
                reference: None,
            },
        );
        assert_eq!(initialized.state, NativeExtensionMutationState::Completed);
        assert!(fixture.0.join("modules/middle/middle.txt").is_file());
        let entered = repository_session_submodule_enter(
            session.session_id,
            session.generation,
            b"modules/middle".to_vec(),
        );
        assert_eq!(
            entered.worktree_root.unwrap(),
            crate::domain::path_identity::native_path_identity(
                &fs::canonicalize(fixture.0.join("modules/middle")).unwrap()
            )
        );
        let updated = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::SubmoduleUpdate,
                path: Some(b"modules/middle".to_vec()),
                worktree_root: None,
                pattern: None,
                reference: None,
            },
        );
        assert_eq!(updated.state, NativeExtensionMutationState::Completed);
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn repository_extensions_disable_lfs_when_configured_git_has_no_lfs() {
        use std::os::unix::fs::PermissionsExt;

        let fixture = GitFixture::new();
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        let actual_git = std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default())
            .map(|directory| directory.join("git"))
            .find(|candidate| candidate.is_file())
            .unwrap();
        let wrapper = fixture.0.join("git-without-lfs");
        let escaped_git = actual_git.to_string_lossy().replace('\'', "'\"'\"'");
        fs::write(
            &wrapper,
            format!(
                "#!/bin/sh\nif [ \"$1\" = \"lfs\" ]; then exit 1; fi\nexec '{escaped_git}' \"$@\"\n"
            ),
        )
        .unwrap();
        fs::set_permissions(&wrapper, fs::Permissions::from_mode(0o700)).unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_217,
            RepositoryOptions {
                git_executable: wrapper.into_os_string(),
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let inventory = repository_session_extensions(session.session_id, session.generation)
            .inventory
            .unwrap();
        assert!(!inventory.lfs_available);
        assert!(inventory.lfs_unavailable_reason);
        let result = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::LfsTrack,
                path: None,
                worktree_root: None,
                pattern: Some("*.bin".to_owned()),
                reference: None,
            },
        );
        assert_eq!(
            result.failure.unwrap().kind,
            NativeExtensionFailureKind::Unavailable
        );
        assert!(!fixture.0.join(".gitattributes").exists());
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn repository_extensions_initialize_nested_submodules_recursively() {
        let leaf = GitFixture::new();
        fs::write(leaf.0.join("leaf.txt"), b"leaf\n").unwrap();
        transfer_git(&leaf.0, &["add", "leaf.txt"]);
        transfer_git(&leaf.0, &["commit", "-qm", "leaf"]);

        let middle = GitFixture::new();
        fs::write(middle.0.join("middle.txt"), b"middle\n").unwrap();
        transfer_git(&middle.0, &["add", "middle.txt"]);
        transfer_git(&middle.0, &["commit", "-qm", "middle"]);
        transfer_git(
            &middle.0,
            &[
                "-c",
                "protocol.file.allow=always",
                "submodule",
                "add",
                leaf.0.to_str().unwrap(),
                "nested/leaf",
            ],
        );
        transfer_git(&middle.0, &["commit", "-qam", "add leaf"]);

        let fixture = GitFixture::new();
        fs::write(fixture.0.join("root.txt"), b"root\n").unwrap();
        transfer_git(&fixture.0, &["add", "root.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "root"]);
        transfer_git(
            &fixture.0,
            &[
                "-c",
                "protocol.file.allow=always",
                "submodule",
                "add",
                middle.0.to_str().unwrap(),
                "modules/middle",
            ],
        );
        transfer_git(&fixture.0, &["commit", "-qam", "add middle"]);
        transfer_git(
            &fixture.0,
            &[
                "-c",
                "protocol.file.allow=always",
                "submodule",
                "update",
                "--init",
                "--recursive",
            ],
        );
        let checked_out_middle = fixture.0.join("modules/middle");
        transfer_git(&checked_out_middle, &["submodule", "deinit", "-f", "--all"]);
        assert!(!checked_out_middle.join("nested/leaf/leaf.txt").exists());

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_218,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let initialized = repository_session_extension_execute(
            session.session_id,
            session.generation,
            NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::SubmoduleInit,
                path: Some(b"modules/middle".to_vec()),
                worktree_root: None,
                pattern: None,
                reference: None,
            },
        );
        assert_eq!(initialized.state, NativeExtensionMutationState::Completed);
        assert!(checked_out_middle.join("nested/leaf/leaf.txt").is_file());
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }
}
