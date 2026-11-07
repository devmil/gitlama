//! Native conflict inspection, resolution, undo and sequencer continuation.
pub use gitlama_contract::conflict::*;

use crate::activity::{allocate_activity_id, ActivityStore};
use crate::domain::outcome::MutationState;
use crate::interrupted::{InterruptedOperation, Interruption};
use devmil_git::activity::ActivityStatus;
use devmil_git::diff::index::IndexStage;
use devmil_git::diff::model::{DiffPath, GitFileMode};
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::status::{BranchHead, OperationKind, WorkingTreeState};
use devmil_git::types::RepositoryRelativePath;
use devmil_git::{Repository, RepositorySnapshot};
use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::fs;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

const MAX_CONFLICT_FILES: usize = 256;
const MAX_TEXT_BYTES: u64 = 1024 * 1024;
const MAX_TEXT_LINES: usize = 50_000;
const MAX_UNDO_ENTRIES: usize = 256;
pub(crate) const MAX_EXTERNAL_MERGE_BYTES: u64 = 64 * 1024 * 1024;

/// The one place a continuation's outcome becomes a bridge state.
pub(crate) const fn native_continuation_state(
    state: MutationState,
) -> NativeConflictContinuationState {
    match state {
        MutationState::Completed
        | MutationState::AlreadyContained
        | MutationState::ReconciledWithWarning => NativeConflictContinuationState::Completed,
        MutationState::Aborted => NativeConflictContinuationState::Aborted,
        MutationState::Conflict => NativeConflictContinuationState::Conflict,
        MutationState::Interrupted | MutationState::EditStop | MutationState::Partial => {
            NativeConflictContinuationState::Interrupted
        }
        MutationState::Stale | MutationState::Canceled | MutationState::Failed => {
            NativeConflictContinuationState::Failed
        }
        MutationState::OutcomeUncertain => NativeConflictContinuationState::OutcomeUncertain,
    }
}

#[derive(Clone)]
struct ResolutionUndo {
    worktree: PathBuf,
    path: RepositoryRelativePath,
    result: Option<Vec<u8>>,
    result_mode: Option<u32>,
    stages: [Option<IndexStage>; 3],
}

#[derive(Default)]
struct UndoRegistry {
    entries: HashMap<(u64, Vec<u8>), ResolutionUndo>,
}

static UNDO: OnceLock<Mutex<UndoRegistry>> = OnceLock::new();
static NEXT_RESULT_TEMPORARY: AtomicU64 = AtomicU64::new(1);

pub(crate) struct ExternalMergeFiles {
    pub root: PathBuf,
    pub ancestor: PathBuf,
    pub current: PathBuf,
    pub incoming: PathBuf,
    pub result: PathBuf,
    pub path: Vec<u8>,
    pub fingerprint: u64,
}

fn lock_undo() -> std::sync::MutexGuard<'static, UndoRegistry> {
    UNDO.get_or_init(|| Mutex::new(UndoRegistry::default()))
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

pub(crate) fn inspect(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
) -> NativeConflictSnapshotResult {
    let snapshot = repository.snapshot();
    let Some((operation, current_step, total_steps)) =
        active_operation(snapshot.as_ref()).or_else(|| {
            lock_undo()
                .entries
                .keys()
                .any(|(owned_session, _)| *owned_session == session_id)
                .then_some((NativeConflictOperationKind::Standalone, None, None))
        })
    else {
        return snapshot_failure(NativeConflictFailureKind::NoActiveOperation);
    };
    let Some(discovered) = snapshot.repository.as_ref() else {
        return snapshot_failure(NativeConflictFailureKind::Read);
    };
    let worktree = discovered.worktree.worktree_root().as_path();
    let git_dir = discovered.worktree.git_dir().as_path();
    let mut activity_ids = Vec::new();
    let stages = match unmerged_index(repository, worktree, activity, &mut activity_ids) {
        Some(value) if value.len() <= MAX_CONFLICT_FILES => value,
        Some(_) => return snapshot_failure(NativeConflictFailureKind::TooLarge),
        None => return snapshot_failure(NativeConflictFailureKind::Read),
    };
    let (current_label, incoming_label) = operation_labels(
        snapshot.as_ref(),
        operation,
        git_dir,
        worktree,
        activity,
        &mut activity_ids,
    );
    let mut files = Vec::with_capacity(stages.len());
    for (path, entry_stages) in stages {
        let result = load_file(
            session_id,
            worktree,
            path,
            entry_stages,
            activity,
            &mut activity_ids,
        );
        match result {
            Ok(value) => files.push(value),
            Err(kind) => return snapshot_failure(kind),
        }
    }
    let mut resolved_undo_paths = lock_undo()
        .entries
        .keys()
        .filter_map(|(owned_session, path)| {
            (*owned_session == session_id
                && !files
                    .iter()
                    .any(|file| file.path.as_slice() == path.as_slice()))
            .then_some(path.clone())
        })
        .collect::<Vec<_>>();
    resolved_undo_paths.sort();
    NativeConflictSnapshotResult {
        snapshot: Some(NativeConflictSnapshot {
            operation,
            current_label,
            incoming_label,
            current_step,
            total_steps,
            can_continue: files.is_empty() && operation != NativeConflictOperationKind::Standalone,
            can_skip: !matches!(
                operation,
                NativeConflictOperationKind::Merge
                    | NativeConflictOperationKind::Snapshot
                    | NativeConflictOperationKind::Stash
                    | NativeConflictOperationKind::Standalone
            ),
            suggested_message: (operation == NativeConflictOperationKind::Merge)
                .then(|| git_dir.join("MERGE_MSG"))
                .and_then(|path| {
                    (fs::metadata(&path).ok()?.len() <= 64 * 1024)
                        .then(|| fs::read_to_string(path).ok())
                        .flatten()
                }),
            files,
            resolved_undo_paths,
        }),
        activity_ids: activity_ids.into_iter().map(|id| id.to_string()).collect(),
        failure: None,
    }
}

pub(crate) fn save_result(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    path: Vec<u8>,
    expected_fingerprint: u64,
    result: Vec<u8>,
) -> NativeConflictSnapshotResult {
    if result.len() as u64 > MAX_TEXT_BYTES {
        return snapshot_failure(NativeConflictFailureKind::TooLarge);
    }
    mutate_file(
        session_id,
        repository,
        activity,
        path,
        expected_fingerprint,
        |file, worktree| {
            if file.kind != NativeConflictFileKind::Text {
                return Err(match file.kind {
                    NativeConflictFileKind::Binary => NativeConflictFailureKind::Binary,
                    NativeConflictFileKind::Huge => NativeConflictFailureKind::TooLarge,
                    NativeConflictFileKind::Text => unreachable!(),
                });
            }
            write_result(
                file,
                worktree,
                Some(&result),
                file.result_mode
                    .or(file.current.mode)
                    .or(file.incoming.mode),
            )?;
            if marker_regions(&result).is_empty() && !contains_marker_lines(&result) {
                stage_path(repository, activity, &file.path)?;
            }
            Ok(())
        },
    )
}

pub(crate) fn prepare_external_merge(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    path: Vec<u8>,
    expected_fingerprint: u64,
) -> Result<ExternalMergeFiles, NativeConflictFailureKind> {
    let inspected = inspect(session_id, repository, activity);
    let snapshot = inspected.snapshot.ok_or_else(|| {
        inspected
            .failure
            .map_or(NativeConflictFailureKind::Read, |value| value.kind)
    })?;
    let file = snapshot
        .files
        .into_iter()
        .find(|value| value.path == path)
        .ok_or(NativeConflictFailureKind::MissingPath)?;
    if file.fingerprint != expected_fingerprint {
        return Err(NativeConflictFailureKind::Stale);
    }
    let discovered = repository
        .snapshot()
        .repository
        .as_ref()
        .cloned()
        .ok_or(NativeConflictFailureKind::Read)?;
    let worktree = discovered.worktree.worktree_root().as_path();
    let mut activity_ids = Vec::new();
    let index = unmerged_index(repository, worktree, activity, &mut activity_ids)
        .ok_or(NativeConflictFailureKind::Read)?;
    let diff_path = DiffPath::from_bytes(path.clone())
        .map_err(|_| NativeConflictFailureKind::InvalidRequest)?;
    let stages = index
        .get(&diff_path)
        .ok_or(NativeConflictFailureKind::Stale)?;
    let store = crate::private_store::PrivateDir::temporary("gitlama-merge")
        .map_err(|_| NativeConflictFailureKind::Write)?;
    let root = store.path().to_path_buf();
    let ancestor = store.entry_path("ancestor");
    let current = store.entry_path("current");
    let incoming = store.entry_path("incoming");
    let result = store.entry_path("result");
    let prepared = (|| {
        let current_bytes =
            external_side(worktree, stages[1].as_ref(), activity, &mut activity_ids)?;
        for (name, stage) in [
            ("ancestor", stages[0].as_ref()),
            ("incoming", stages[2].as_ref()),
        ] {
            let bytes = external_side(worktree, stage, activity, &mut activity_ids)?;
            store
                .write_new(name, &bytes)
                .map_err(|_| NativeConflictFailureKind::Write)?;
        }
        store
            .write_new("current", &current_bytes)
            .map_err(|_| NativeConflictFailureKind::Write)?;
        let result_bytes = if file.result_present {
            let relative = native_relative_path(path.clone())
                .ok_or(NativeConflictFailureKind::InvalidRequest)?;
            let native = confined_path(worktree, &relative)?;
            let metadata =
                fs::symlink_metadata(&native).map_err(|_| NativeConflictFailureKind::Read)?;
            if metadata.len() > MAX_EXTERNAL_MERGE_BYTES {
                return Err(NativeConflictFailureKind::TooLarge);
            }
            read_native_entry(&native, Some(&metadata))
                .map_err(|_| NativeConflictFailureKind::Read)?
                .unwrap_or_default()
        } else {
            current_bytes
        };
        store
            .write_new("result", &result_bytes)
            .map_err(|_| NativeConflictFailureKind::Write)
    })();
    // Windows cannot delete a directory with an open handle.
    drop(store);
    if let Err(error) = prepared {
        let _ = fs::remove_dir_all(&root);
        return Err(error);
    }
    Ok(ExternalMergeFiles {
        root,
        ancestor,
        current,
        incoming,
        result,
        path,
        fingerprint: expected_fingerprint,
    })
}

pub(crate) fn finish_external_merge(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    prepared: &ExternalMergeFiles,
) -> Result<(), NativeConflictFailureKind> {
    let metadata =
        fs::symlink_metadata(&prepared.result).map_err(|_| NativeConflictFailureKind::Read)?;
    if !metadata.file_type().is_file() || metadata.len() > MAX_EXTERNAL_MERGE_BYTES {
        return Err(NativeConflictFailureKind::TooLarge);
    }
    let result = fs::read(&prepared.result).map_err(|_| NativeConflictFailureKind::Read)?;
    let updated = mutate_file(
        session_id,
        repository,
        activity,
        prepared.path.clone(),
        prepared.fingerprint,
        |file, worktree| {
            write_result(
                file,
                worktree,
                Some(&result),
                file.result_mode
                    .or(file.current.mode)
                    .or(file.incoming.mode),
            )?;
            stage_path(repository, activity, &file.path)
        },
    );
    updated.failure.map_or(Ok(()), |failure| Err(failure.kind))
}

/// The bytes of one conflict stage, bounded; empty when the stage is absent.
fn external_side(
    worktree: &Path,
    stage: Option<&IndexStage>,
    activity: &ActivityStore,
    activity_ids: &mut Vec<u64>,
) -> Result<Vec<u8>, NativeConflictFailureKind> {
    let Some(stage) = stage else {
        return Ok(Vec::new());
    };
    let size = run_read(
        worktree,
        ["cat-file", "-s", stage.object.as_str()],
        activity,
        activity_ids,
        Some(128),
    )
    .and_then(|value| String::from_utf8(value.bytes).ok())
    .and_then(|value| value.trim().parse::<u64>().ok())
    .ok_or(NativeConflictFailureKind::Read)?;
    if size > MAX_EXTERNAL_MERGE_BYTES {
        return Err(NativeConflictFailureKind::TooLarge);
    }
    Ok(run_read(
        worktree,
        ["cat-file", "blob", stage.object.as_str()],
        activity,
        activity_ids,
        Some(MAX_EXTERNAL_MERGE_BYTES as usize + 1),
    )
    .filter(|value| !value.truncated)
    .ok_or(NativeConflictFailureKind::Read)?
    .bytes)
}

pub(crate) fn choose_side(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    path: Vec<u8>,
    expected_fingerprint: u64,
    choice: NativeConflictSideChoice,
) -> NativeConflictSnapshotResult {
    mutate_file(
        session_id,
        repository,
        activity,
        path,
        expected_fingerprint,
        |file, worktree| {
            let side = match choice {
                NativeConflictSideChoice::Current => &file.current,
                NativeConflictSideChoice::Incoming => &file.incoming,
            };
            if side.present && side.content.is_none() {
                checkout_index_side(repository, activity, &file.path, choice)?;
            } else {
                write_result(file, worktree, side.content.as_deref(), side.mode)?;
            }
            stage_path(repository, activity, &file.path)
        },
    )
}

pub(crate) fn take_region(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    path: Vec<u8>,
    expected_fingerprint: u64,
    region_index: u32,
    choice: NativeConflictRegionChoice,
) -> NativeConflictSnapshotResult {
    mutate_file(
        session_id,
        repository,
        activity,
        path,
        expected_fingerprint,
        |file, worktree| {
            if file.kind != NativeConflictFileKind::Text {
                return Err(NativeConflictFailureKind::InvalidRequest);
            }
            let result = file
                .result
                .as_ref()
                .ok_or(NativeConflictFailureKind::MissingPath)?;
            let regions = marker_regions(result);
            let region = regions
                .get(region_index as usize)
                .ok_or(NativeConflictFailureKind::InvalidRequest)?;
            let replacement = match choice {
                NativeConflictRegionChoice::Current => region.current.clone(),
                NativeConflictRegionChoice::Incoming => region.incoming.clone(),
                NativeConflictRegionChoice::Both => {
                    let mut value = region.current.clone();
                    value.extend_from_slice(&region.incoming);
                    value
                }
            };
            let mut updated = Vec::with_capacity(
                result.len() - (region.block_end - region.block_start) + replacement.len(),
            );
            updated.extend_from_slice(&result[..region.block_start]);
            updated.extend_from_slice(&replacement);
            updated.extend_from_slice(&result[region.block_end..]);
            write_result(
                file,
                worktree,
                Some(&updated),
                file.result_mode
                    .or(file.current.mode)
                    .or(file.incoming.mode),
            )?;
            if marker_regions(&updated).is_empty() && !contains_marker_lines(&updated) {
                stage_path(repository, activity, &file.path)?;
            }
            Ok(())
        },
    )
}

pub(crate) fn undo_resolution(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    path: Vec<u8>,
) -> NativeConflictSnapshotResult {
    let undo_key = (session_id, path);
    let Some(undo) = lock_undo().entries.get(&undo_key).cloned() else {
        return snapshot_failure(NativeConflictFailureKind::MissingPath);
    };
    let cancellation = AtomicBool::new(false);
    let Ok(_lease) = repository.begin_mutation_with_cancellation(&cancellation) else {
        return snapshot_failure(NativeConflictFailureKind::Git);
    };
    if write_native_path(
        &undo.worktree,
        &undo.path,
        undo.result.as_deref(),
        undo.result_mode,
    )
    .is_err()
    {
        return snapshot_failure(NativeConflictFailureKind::Write);
    }
    if restore_stages(repository.git_executable(), &undo, activity).is_err() {
        return snapshot_failure(NativeConflictFailureKind::Git);
    }
    lock_undo().entries.remove(&undo_key);
    drop(_lease);
    reload(repository);
    inspect(session_id, repository, activity)
}

pub(crate) fn continue_operation(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    action: NativeConflictSequencerAction,
) -> NativeConflictContinuationResult {
    continue_operation_with_message(session_id, repository, activity, action, None)
}

pub(crate) fn continue_operation_with_message(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    action: NativeConflictSequencerAction,
    message: Option<&str>,
) -> NativeConflictContinuationResult {
    let snapshot = repository.snapshot();
    let Some((operation, _, _)) = active_operation(snapshot.as_ref()) else {
        return continuation_failure(NativeConflictFailureKind::NoActiveOperation);
    };
    // Conflicts no operation left have nothing to continue.
    let Some(family) = crate::interrupted::family(operation) else {
        return continuation_failure(NativeConflictFailureKind::Unsupported);
    };
    if message.is_some_and(|value| {
        operation != NativeConflictOperationKind::Merge
            || action != NativeConflictSequencerAction::Continue
            || value.trim().is_empty()
            || value.len() > 64 * 1024
            || value.contains('\0')
    }) {
        return continuation_failure(NativeConflictFailureKind::InvalidRequest);
    }
    let Some(discovered) = snapshot.repository.as_ref() else {
        return continuation_failure(NativeConflictFailureKind::Read);
    };
    if action == NativeConflictSequencerAction::Continue
        && snapshot
            .status
            .as_ref()
            .is_some_and(|status| status.entries.iter().any(|entry| entry.is_conflicted()))
    {
        return continuation_failure(NativeConflictFailureKind::Unresolved);
    }
    if !family.offers(action) {
        return continuation_failure(NativeConflictFailureKind::Unsupported);
    }
    let interruption = Interruption {
        repository,
        activity,
        snapshot: snapshot.as_ref(),
        worktree: discovered.worktree.worktree_root().as_path(),
        git_dir: discovered.worktree.git_dir().as_path(),
        common_git_dir: discovered.worktree.repository().common_git_dir().as_path(),
    };
    let result = family.resume(&interruption, action, message);
    if matches!(
        result.state,
        NativeConflictContinuationState::Completed | NativeConflictContinuationState::Aborted
    ) {
        dismiss_session(session_id);
    }
    result
}

/// Resumes an operation Git's sequencer drives: runs the family's sequencer command under the
/// mutation lease and decides the outcome from the repository Git leaves behind.
pub(crate) fn resume_sequencer<F: InterruptedOperation + ?Sized>(
    family: &F,
    interruption: &Interruption<'_>,
    action: NativeConflictSequencerAction,
    message: Option<&str>,
) -> NativeConflictContinuationResult {
    let repository = interruption.repository;
    let step = match family.sequencer(interruption, action) {
        Ok(step) => step,
        Err(kind) => return continuation_failure(kind),
    };
    let cancellation = AtomicBool::new(false);
    let Ok(lease) = repository.begin_mutation_with_cancellation(&cancellation) else {
        return continuation_failure(NativeConflictFailureKind::Git);
    };
    if let Err(kind) = family.check_under_lease(interruption, &step, &lease, &cancellation) {
        return continuation_failure(kind);
    }
    let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
    let mut command = GitProcessCommand::git(repository.git_executable())
        .current_dir(interruption.worktree)
        .args(step.arguments.iter().cloned().map(ProcessArgument::visible))
        .redact_output();
    if let Some(message) = message {
        let Ok(invocation) = devmil_git::commands::commit::commit_invocation_with_message(
            &devmil_git::commands::commit::CommitRequest::default(),
            message.as_bytes().to_vec(),
        ) else {
            return continuation_failure(NativeConflictFailureKind::InvalidRequest);
        };
        command = invocation
            .process_command(repository.git_executable(), interruption.worktree)
            .redact_output();
    }
    if step.environment.is_empty() {
        command = match command.env("GIT_EDITOR", "true") {
            Ok(updated) => updated,
            Err(_) => return continuation_failure(NativeConflictFailureKind::Git),
        };
    } else {
        for (name, value) in &step.environment {
            let Ok(updated) = command.env_redacted(name, value) else {
                return continuation_failure(NativeConflictFailureKind::Git);
            };
            command = updated;
        }
    }
    let sink = interruption.activity.sink();
    let mut publish = |event| sink(event);
    let result = ActivityGitRunner::run_private(command, id, Some(&cancellation), &mut publish);
    drop(lease);
    reload(repository);
    let current = repository.snapshot();
    let still_active = active_operation(current.as_ref()).is_some();
    let conflicts = current
        .status
        .as_ref()
        .is_some_and(|status| status.entries.iter().any(|entry| entry.is_conflicted()));
    let succeeded = matches!(result.activity.status, ActivityStatus::Succeeded { .. });
    let state = native_continuation_state(
        if action == NativeConflictSequencerAction::Abort && succeeded && !still_active {
            MutationState::Aborted
        } else if conflicts {
            MutationState::Conflict
        } else if still_active {
            MutationState::Interrupted
        } else if succeeded {
            MutationState::Completed
        } else {
            MutationState::Failed
        },
    );
    if state == NativeConflictContinuationState::Completed {
        family.completed(interruption, &step, current.as_ref());
    }
    if state == NativeConflictContinuationState::Aborted {
        family.aborted(interruption, &step);
    }
    if matches!(
        state,
        NativeConflictContinuationState::Completed | NativeConflictContinuationState::Aborted
    ) {
        if let Some(runtime) = &step.runtime {
            let _ = fs::remove_dir_all(runtime);
        }
    }
    NativeConflictContinuationResult {
        state,
        activity_ids: vec![id.get().to_string()],
        failure: (!succeeded && state == NativeConflictContinuationState::Failed).then_some(
            NativeConflictFailure {
                kind: NativeConflictFailureKind::Git,
            },
        ),
    }
}

pub(crate) fn dismiss_session(session_id: u64) {
    lock_undo()
        .entries
        .retain(|(owned_session, _), _| *owned_session != session_id);
}

fn mutate_file(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    path: Vec<u8>,
    expected_fingerprint: u64,
    mutation: impl FnOnce(&NativeConflictFile, &Path) -> Result<(), NativeConflictFailureKind>,
) -> NativeConflictSnapshotResult {
    let before = inspect(session_id, repository, activity);
    let Some(snapshot) = before.snapshot else {
        return before;
    };
    let Some(file) = snapshot.files.into_iter().find(|file| file.path == path) else {
        return snapshot_failure(NativeConflictFailureKind::MissingPath);
    };
    if file.fingerprint != expected_fingerprint {
        return snapshot_failure(NativeConflictFailureKind::Stale);
    }
    let cancellation = AtomicBool::new(false);
    let Ok(lease) = repository.begin_mutation_with_cancellation(&cancellation) else {
        return snapshot_failure(NativeConflictFailureKind::Git);
    };
    let relative = match native_relative_path(path.clone()) {
        Some(value) => value,
        None => return snapshot_failure(NativeConflictFailureKind::InvalidRequest),
    };
    let Some(discovered) = repository.snapshot().repository.as_ref().cloned() else {
        return snapshot_failure(NativeConflictFailureKind::Read);
    };
    let mut activity_ids = Vec::new();
    let Some(index) = unmerged_index(
        repository,
        discovered.worktree.worktree_root().as_path(),
        activity,
        &mut activity_ids,
    ) else {
        return snapshot_failure(NativeConflictFailureKind::Read);
    };
    let diff_path = match DiffPath::from_bytes(file.path.clone()) {
        Ok(value) => value,
        Err(_) => return snapshot_failure(NativeConflictFailureKind::InvalidRequest),
    };
    let Some(stages) = index.get(&diff_path).cloned() else {
        return snapshot_failure(NativeConflictFailureKind::Stale);
    };
    let undo_key = (session_id, path);
    let mut undo = lock_undo();
    let inserted_undo = !undo.entries.contains_key(&undo_key);
    undo.entries
        .entry(undo_key.clone())
        .or_insert_with(|| ResolutionUndo {
            worktree: discovered.worktree.worktree_root().as_path().to_path_buf(),
            path: relative,
            result: file.result.clone(),
            result_mode: file.result_mode,
            stages,
        });
    if undo.entries.len() > MAX_UNDO_ENTRIES {
        if let Some(key) = undo.entries.keys().next().cloned() {
            undo.entries.remove(&key);
        }
    }
    drop(undo);
    let worktree = discovered.worktree.worktree_root().as_path();
    if let Err(kind) = mutation(&file, worktree) {
        if inserted_undo {
            lock_undo().entries.remove(&undo_key);
        }
        return snapshot_failure(kind);
    }
    drop(lease);
    reload(repository);
    inspect(session_id, repository, activity)
}

fn load_file(
    session_id: u64,
    worktree: &Path,
    path: DiffPath,
    stages: [Option<IndexStage>; 3],
    activity: &ActivityStore,
    activity_ids: &mut Vec<u64>,
) -> Result<NativeConflictFile, NativeConflictFailureKind> {
    let ancestor = load_side(worktree, stages[0].as_ref(), activity, activity_ids)?;
    let current = load_side(worktree, stages[1].as_ref(), activity, activity_ids)?;
    let incoming = load_side(worktree, stages[2].as_ref(), activity, activity_ids)?;
    let relative = native_relative_path(path.as_bytes().to_vec())
        .ok_or(NativeConflictFailureKind::InvalidRequest)?;
    let native = confined_path(worktree, &relative)?;
    let metadata = fs::symlink_metadata(&native).ok();
    let result_present = metadata.is_some();
    let result_mode = metadata.as_ref().map(native_mode);
    let result_size = metadata.as_ref().map_or(0, fs::Metadata::len);
    let result = if result_size <= MAX_TEXT_BYTES {
        read_native_entry(&native, metadata.as_ref()).ok().flatten()
    } else {
        None
    };
    let huge = result_size > MAX_TEXT_BYTES
        || [ancestor.byte_count, current.byte_count, incoming.byte_count]
            .into_iter()
            .any(|size| size > MAX_TEXT_BYTES)
        || result
            .as_ref()
            .is_some_and(|bytes| bytes.split(|byte| *byte == b'\n').count() > MAX_TEXT_LINES);
    let binary = !huge
        && [
            &ancestor.content,
            &current.content,
            &incoming.content,
            &result,
        ]
        .into_iter()
        .flatten()
        .any(|bytes| bytes.contains(&0) || std::str::from_utf8(bytes).is_err());
    let kind = if huge {
        NativeConflictFileKind::Huge
    } else if binary {
        NativeConflictFileKind::Binary
    } else {
        NativeConflictFileKind::Text
    };
    let regions = result
        .as_deref()
        .filter(|_| kind == NativeConflictFileKind::Text)
        .map(marker_regions)
        .unwrap_or_default();
    let marker_free = result
        .as_deref()
        .is_some_and(|bytes| regions.is_empty() && !contains_marker_lines(bytes));
    let path_bytes = path.as_bytes().to_vec();
    let fingerprint = fingerprint(
        &path_bytes,
        &stages,
        result.as_deref(),
        result_mode,
        result_present,
    );
    let can_undo_resolution = lock_undo()
        .entries
        .contains_key(&(session_id, path_bytes.clone()));
    Ok(NativeConflictFile {
        path: path_bytes,
        kind,
        ancestor,
        current,
        incoming,
        result,
        result_present,
        result_mode,
        marker_free,
        regions: regions
            .into_iter()
            .enumerate()
            .map(|(index, region)| NativeConflictRegion {
                index: index.try_into().unwrap_or(u32::MAX),
                current: region.current,
                incoming: region.incoming,
                ancestor: region.ancestor,
            })
            .collect(),
        fingerprint,
        can_undo_resolution,
    })
}

fn load_side(
    worktree: &Path,
    stage: Option<&IndexStage>,
    activity: &ActivityStore,
    activity_ids: &mut Vec<u64>,
) -> Result<NativeConflictSide, NativeConflictFailureKind> {
    let Some(stage) = stage else {
        return Ok(NativeConflictSide {
            present: false,
            mode: None,
            content: None,
            byte_count: 0,
        });
    };
    let size = run_read(
        worktree,
        ["cat-file", "-s", stage.object.as_str()],
        activity,
        activity_ids,
        Some(128),
    )
    .and_then(|result| String::from_utf8(result.bytes).ok())
    .and_then(|value| value.trim().parse::<u64>().ok())
    .ok_or(NativeConflictFailureKind::Read)?;
    let content = if size <= MAX_TEXT_BYTES {
        Some(
            run_read(
                worktree,
                ["cat-file", "blob", stage.object.as_str()],
                activity,
                activity_ids,
                Some(MAX_TEXT_BYTES as usize + 1),
            )
            .filter(|result| !result.truncated)
            .ok_or(NativeConflictFailureKind::Read)?
            .bytes,
        )
    } else {
        None
    };
    Ok(NativeConflictSide {
        present: true,
        mode: Some(stage.mode.value()),
        content,
        byte_count: size,
    })
}

/// The unmerged index entries, read through the shared probe as activities of this operation.
fn unmerged_index(
    repository: &Repository,
    worktree: &Path,
    activity: &ActivityStore,
    activity_ids: &mut Vec<u64>,
) -> Option<devmil_git::probes::UnmergedIndex> {
    let sink = activity.sink();
    let publish = |event| sink(event);
    let mut record = |id: devmil_git::activity::ActivityId| activity_ids.push(id.get());
    devmil_git::probes::unmerged_index(
        repository.git_executable(),
        worktree,
        &mut crate::git_probe::ProbeExecutor::publishing(None, &publish, &mut record),
    )
    .ok()
}

struct ReadOutput {
    bytes: Vec<u8>,
    truncated: bool,
}

fn run_read<'a>(
    worktree: &Path,
    arguments: impl IntoIterator<Item = &'a str>,
    activity: &ActivityStore,
    activity_ids: &mut Vec<u64>,
    output_limit: Option<usize>,
) -> Option<ReadOutput> {
    let id = allocate_activity_id();
    activity_ids.push(id.get());
    let mut command = GitProcessCommand::git("git")
        .current_dir(worktree)
        .args(arguments.into_iter().map(ProcessArgument::visible))
        .redact_output();
    if let Some(limit) = output_limit {
        command = command.output_limit(limit);
    }
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let mut result = ActivityGitRunner::run_private(command, id, None, &mut publish);
    matches!(result.activity.status, ActivityStatus::Succeeded { .. }).then(|| ReadOutput {
        truncated: result.stdout.truncated,
        bytes: result.stdout.take_bytes(),
    })
}

#[derive(Clone)]
struct MarkerRegion {
    block_start: usize,
    block_end: usize,
    current: Vec<u8>,
    incoming: Vec<u8>,
    ancestor: Option<Vec<u8>>,
}

/// The complete conflict regions of a merge result, from the shared byte-level parser. Git's
/// default marker size applies.
fn marker_regions(bytes: &[u8]) -> Vec<MarkerRegion> {
    use devmil_git::merge::markers::{parse, DEFAULT_MARKER_SIZE};
    parse(bytes, DEFAULT_MARKER_SIZE)
        .regions
        .into_iter()
        .map(|region| MarkerRegion {
            block_start: region.block.start,
            block_end: region.block.end,
            current: bytes[region.current].to_vec(),
            incoming: bytes[region.incoming].to_vec(),
            ancestor: region.ancestor.map(|range| bytes[range].to_vec()),
        })
        .collect()
}

/// Whether any line is a conflict marker as Git writes one (the shared parser's rule, at Git's
/// default marker size). Longer runs, such as a Markdown heading underline, are content. The
/// resolver applies the same rule before it offers Resolve.
fn contains_marker_lines(bytes: &[u8]) -> bool {
    !devmil_git::merge::markers::marker_free(bytes, devmil_git::merge::markers::DEFAULT_MARKER_SIZE)
}

fn active_operation(
    snapshot: &RepositorySnapshot,
) -> Option<(NativeConflictOperationKind, Option<u32>, Option<u32>)> {
    snapshot
        .status
        .as_ref()?
        .operations
        .iter()
        .find_map(|state| {
            let kind = match state.kind {
                OperationKind::Merge => NativeConflictOperationKind::Merge,
                OperationKind::Rebase => NativeConflictOperationKind::Rebase,
                OperationKind::CherryPick => NativeConflictOperationKind::CherryPick,
                OperationKind::Revert => NativeConflictOperationKind::Revert,
                OperationKind::Bisect => return None,
            };
            Some((kind, state.current, state.total))
        })
        .or_else(|| {
            let common = snapshot
                .repository
                .as_ref()?
                .worktree
                .repository()
                .common_git_dir()
                .as_path();
            crate::interrupted::own_interruption(common).map(|kind| (kind, None, None))
        })
        .or_else(|| {
            snapshot
                .status
                .as_ref()
                .is_some_and(|status| {
                    status.working_tree == WorkingTreeState::Conflicted
                        || status.entries.iter().any(|entry| entry.is_conflicted())
                })
                .then_some((NativeConflictOperationKind::Standalone, None, None))
        })
}

fn operation_labels(
    snapshot: &RepositorySnapshot,
    operation: NativeConflictOperationKind,
    git_dir: &Path,
    worktree: &Path,
    activity: &ActivityStore,
    activity_ids: &mut Vec<u64>,
) -> (Vec<u8>, Vec<u8>) {
    let branch = snapshot
        .status
        .as_ref()
        .and_then(|status| match &status.branch.head {
            BranchHead::Attached(name) => Some(name.as_bytes().to_vec()),
            _ => None,
        })
        .unwrap_or_else(|| b"current".to_vec());
    match operation {
        NativeConflictOperationKind::Rebase => {
            // Either rebase backend: devmil-git parses `rebase-merge` and `rebase-apply`.
            let state = devmil_git::status::discover_operations_checked(git_dir)
                .ok()
                .and_then(|found| found.rebase);
            let incoming = state
                .as_ref()
                .and_then(|state| state.head_name())
                .map(|name| trim_ref(name.as_bytes().to_vec()))
                .unwrap_or_else(|| b"rebased commit".to_vec());
            let onto = state
                .as_ref()
                .and_then(|state| state.onto())
                .and_then(|oid| ref_name_for_oid(snapshot, oid.as_str()))
                .unwrap_or_else(|| b"onto".to_vec());
            (onto, incoming)
        }
        NativeConflictOperationKind::Merge => {
            let incoming = devmil_git::status::operation_heads(git_dir, OperationKind::Merge)
                .ok()
                .and_then(|heads| heads.into_iter().next())
                .and_then(|head| {
                    let oid = head.as_str();
                    snapshot.refs.iter().find_map(|section| match section {
                        devmil_git::loading::refs::RefsSectionData::Remotes {
                            references, ..
                        } => references.iter().find_map(|reference| {
                            (reference.target.as_str() == oid)
                                .then(|| reference.id.as_bytes().strip_prefix(b"refs/remotes/"))
                                .flatten()
                                .map(Vec::from)
                        }),
                        _ => None,
                    })
                })
                .or_else(|| {
                    run_read(
                        worktree,
                        [
                            "name-rev",
                            "--name-only",
                            "--refs=refs/heads/*",
                            "MERGE_HEAD",
                        ],
                        activity,
                        activity_ids,
                        Some(1024),
                    )
                    .map(|value| trim_ref(value.bytes))
                    .filter(|label| label != b"undefined")
                })
                .unwrap_or_else(|| b"incoming".to_vec());
            (branch, incoming)
        }
        NativeConflictOperationKind::CherryPick => (branch, b"cherry-picked commit".to_vec()),
        NativeConflictOperationKind::Revert => (branch, b"reverted commit".to_vec()),
        NativeConflictOperationKind::Snapshot => (branch, b"snapshot".to_vec()),
        NativeConflictOperationKind::Stash => (branch, b"stashed changes".to_vec()),
        NativeConflictOperationKind::Standalone => (branch, b"incoming changes".to_vec()),
    }
}

fn trim_ref(mut value: Vec<u8>) -> Vec<u8> {
    while value.last().is_some_and(u8::is_ascii_whitespace) {
        value.pop();
    }
    for prefix in [b"refs/heads/".as_slice(), b"heads/".as_slice()] {
        if let Some(short) = value.strip_prefix(prefix) {
            return short.to_vec();
        }
    }
    value
}

fn ref_name_for_oid(snapshot: &RepositorySnapshot, oid: &str) -> Option<Vec<u8>> {
    snapshot.refs.iter().find_map(|section| match section {
        devmil_git::loading::refs::RefsSectionData::Branches { rows, .. } => rows
            .iter()
            .find(|row| row.target.as_str() == oid)
            .and_then(|row| row.id.as_bytes().strip_prefix(b"refs/heads/"))
            .map(<[u8]>::to_vec),
        _ => None,
    })
}

fn write_result(
    file: &NativeConflictFile,
    worktree: &Path,
    content: Option<&[u8]>,
    mode: Option<u32>,
) -> Result<(), NativeConflictFailureKind> {
    let relative =
        native_relative_path(file.path.clone()).ok_or(NativeConflictFailureKind::InvalidRequest)?;
    write_native_path(worktree, &relative, content, mode)
}

fn write_native_path(
    worktree: &Path,
    path: &RepositoryRelativePath,
    content: Option<&[u8]>,
    mode: Option<u32>,
) -> Result<(), NativeConflictFailureKind> {
    let native = confined_path(worktree, path)?;
    if content.is_none() {
        match fs::symlink_metadata(&native) {
            Ok(metadata) if metadata.file_type().is_dir() => {
                return Err(NativeConflictFailureKind::Write)
            }
            Ok(_) => fs::remove_file(&native).map_err(|_| NativeConflictFailureKind::Write)?,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => return Err(NativeConflictFailureKind::Write),
        }
        return Ok(());
    }
    let content = content.unwrap();
    if let Some(parent) = native.parent() {
        ensure_confined_parents(worktree, parent)?;
        fs::create_dir_all(parent).map_err(|_| NativeConflictFailureKind::Write)?;
    }
    if mode == Some(GitFileMode::SYMLINK.value()) {
        #[cfg(unix)]
        {
            let target = devmil_git::native_bytes::bytes_to_os_string(content)
                .map_err(|_| NativeConflictFailureKind::InvalidRequest)?;
            let _ = fs::remove_file(&native);
            std::os::unix::fs::symlink(target, &native)
                .map_err(|_| NativeConflictFailureKind::Write)?;
            return Ok(());
        }
        #[cfg(windows)]
        {
            use std::os::windows::fs::{symlink_dir, symlink_file};

            let target = devmil_git::native_bytes::bytes_to_os_string(content)
                .map_err(|_| NativeConflictFailureKind::InvalidRequest)?;
            let _ = fs::remove_file(&native);
            let resolved_target = if Path::new(&target).is_absolute() {
                PathBuf::from(&target)
            } else {
                native
                    .parent()
                    .unwrap_or(worktree)
                    .join(PathBuf::from(&target))
            };
            let result = match fs::metadata(&resolved_target) {
                Ok(metadata) if metadata.is_dir() => symlink_dir(&target, &native),
                _ => symlink_file(&target, &native),
            };
            result.map_err(|_| NativeConflictFailureKind::Write)?;
            return Ok(());
        }
        #[cfg(not(any(unix, windows)))]
        return Err(NativeConflictFailureKind::Unsupported);
    }
    let temporary_id = NEXT_RESULT_TEMPORARY.fetch_add(1, Ordering::Relaxed);
    let temp = native.with_extension(format!("gitlama-{}-{temporary_id}", std::process::id()));
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let result = (|| {
        use std::io::Write;
        let mut output = options
            .open(&temp)
            .map_err(|_| NativeConflictFailureKind::Write)?;
        output
            .write_all(content)
            .map_err(|_| NativeConflictFailureKind::Write)?;
        output
            .sync_all()
            .map_err(|_| NativeConflictFailureKind::Write)?;
        fs::rename(&temp, &native).map_err(|_| NativeConflictFailureKind::Write)
    })();
    let _ = fs::remove_file(&temp);
    result?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let permissions = if mode == Some(GitFileMode::EXECUTABLE.value()) {
            0o755
        } else {
            0o644
        };
        fs::set_permissions(&native, fs::Permissions::from_mode(permissions))
            .map_err(|_| NativeConflictFailureKind::Write)?;
    }
    Ok(())
}

fn stage_path(
    repository: &Repository,
    activity: &ActivityStore,
    path: &[u8],
) -> Result<(), NativeConflictFailureKind> {
    let path = DiffPath::from_bytes(path.to_vec())
        .map_err(|_| NativeConflictFailureKind::InvalidRequest)?;
    let invocation = devmil_git::commands::index::stage_paths(
        std::slice::from_ref(&path),
        devmil_git::commands::index::PathspecForm::Arguments,
    )
    .map_err(|_| NativeConflictFailureKind::InvalidRequest)?;
    run_index_invocation(
        repository.git_executable(),
        &worktree_of(repository)?,
        activity,
        &invocation,
    )
}

fn checkout_index_side(
    repository: &Repository,
    activity: &ActivityStore,
    path: &[u8],
    choice: NativeConflictSideChoice,
) -> Result<(), NativeConflictFailureKind> {
    use devmil_git::commands::index::{checkout_conflict_side, ConflictSide};
    let path = DiffPath::from_bytes(path.to_vec())
        .map_err(|_| NativeConflictFailureKind::InvalidRequest)?;
    let side = match choice {
        NativeConflictSideChoice::Current => ConflictSide::Ours,
        NativeConflictSideChoice::Incoming => ConflictSide::Theirs,
    };
    let invocation = checkout_conflict_side(&path, side)
        .map_err(|_| NativeConflictFailureKind::InvalidRequest)?;
    run_index_invocation(
        repository.git_executable(),
        &worktree_of(repository)?,
        activity,
        &invocation,
    )
}

fn restore_stages(
    executable: &std::ffi::OsStr,
    undo: &ResolutionUndo,
    activity: &ActivityStore,
) -> Result<(), NativeConflictFailureKind> {
    use devmil_git::commands::index::{restore_conflict_stages, IndexStageEntry};
    let path = DiffPath::from_bytes(devmil_git::native_bytes::path_to_bytes(undo.path.as_path()))
        .map_err(|_| NativeConflictFailureKind::InvalidRequest)?;
    let stages = undo.stages.clone().map(|stage| {
        stage.map(|stage| IndexStageEntry {
            mode: stage.mode.value(),
            object: stage.object,
        })
    });
    let invocation = restore_conflict_stages(&path, &stages)
        .map_err(|_| NativeConflictFailureKind::InvalidRequest)?;
    run_index_invocation(executable, &undo.worktree, activity, &invocation)
}

fn worktree_of(repository: &Repository) -> Result<PathBuf, NativeConflictFailureKind> {
    repository
        .snapshot()
        .repository
        .as_ref()
        .map(|value| value.worktree.worktree_root().as_path().to_path_buf())
        .ok_or(NativeConflictFailureKind::Read)
}

fn run_index_invocation(
    executable: &std::ffi::OsStr,
    worktree: &Path,
    activity: &ActivityStore,
    invocation: &devmil_git::commands::invocation::GitInvocation,
) -> Result<(), NativeConflictFailureKind> {
    let command = invocation
        .process_command(executable, worktree)
        .redact_output();
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let result = ActivityGitRunner::run_private(
        command,
        crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change),
        None,
        &mut publish,
    );
    matches!(result.activity.status, ActivityStatus::Succeeded { .. })
        .then_some(())
        .ok_or(NativeConflictFailureKind::Git)
}

fn confined_path(
    worktree: &Path,
    relative: &RepositoryRelativePath,
) -> Result<PathBuf, NativeConflictFailureKind> {
    let path = worktree.join(relative.as_path());
    ensure_confined_parents(worktree, path.parent().unwrap_or(worktree))?;
    Ok(path)
}

fn ensure_confined_parents(
    worktree: &Path,
    parent: &Path,
) -> Result<(), NativeConflictFailureKind> {
    let relative = parent
        .strip_prefix(worktree)
        .map_err(|_| NativeConflictFailureKind::InvalidRequest)?;
    let mut current = worktree.to_path_buf();
    for component in relative.components() {
        current.push(component);
        match fs::symlink_metadata(&current) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                return Err(NativeConflictFailureKind::Write)
            }
            Ok(metadata) if !metadata.is_dir() => return Err(NativeConflictFailureKind::Write),
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => break,
            Err(_) => return Err(NativeConflictFailureKind::Write),
        }
    }
    Ok(())
}

fn read_native_entry(
    path: &Path,
    metadata: Option<&fs::Metadata>,
) -> Result<Option<Vec<u8>>, NativeConflictFailureKind> {
    let Some(metadata) = metadata else {
        return Ok(None);
    };
    if metadata.file_type().is_symlink() {
        return Ok(Some(devmil_git::native_bytes::path_to_bytes(
            &fs::read_link(path).map_err(|_| NativeConflictFailureKind::Read)?,
        )));
    }
    if !metadata.is_file() {
        return Err(NativeConflictFailureKind::Read);
    }
    fs::read(path)
        .map(Some)
        .map_err(|_| NativeConflictFailureKind::Read)
}

fn native_mode(metadata: &fs::Metadata) -> u32 {
    if metadata.file_type().is_symlink() {
        return GitFileMode::SYMLINK.value();
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if metadata.permissions().mode() & 0o111 != 0 {
            return GitFileMode::EXECUTABLE.value();
        }
    }
    GitFileMode::REGULAR.value()
}

fn fingerprint(
    path: &[u8],
    stages: &[Option<IndexStage>; 3],
    result: Option<&[u8]>,
    mode: Option<u32>,
    present: bool,
) -> u64 {
    let mut hasher = DefaultHasher::new();
    path.hash(&mut hasher);
    for stage in stages {
        match stage {
            Some(stage) => {
                true.hash(&mut hasher);
                stage.mode.value().hash(&mut hasher);
                stage.object.as_str().hash(&mut hasher);
            }
            None => false.hash(&mut hasher),
        }
    }
    result.hash(&mut hasher);
    mode.hash(&mut hasher);
    present.hash(&mut hasher);
    hasher.finish()
}

pub(crate) fn reload(repository: &Repository) {
    let _ = repository.reload().ok().and_then(|ticket| {
        ticket
            .recv_timeout(Duration::from_secs(5))
            .and_then(Result::ok)
    });
}

fn native_relative_path(bytes: Vec<u8>) -> Option<RepositoryRelativePath> {
    devmil_git::native_bytes::bytes_to_path_buf(&bytes)
        .ok()
        .and_then(|path| RepositoryRelativePath::new(path).ok())
}

fn snapshot_failure(kind: NativeConflictFailureKind) -> NativeConflictSnapshotResult {
    NativeConflictSnapshotResult {
        snapshot: None,
        activity_ids: Vec::new(),
        failure: Some(NativeConflictFailure { kind }),
    }
}

pub(crate) fn continuation_failure(
    kind: NativeConflictFailureKind,
) -> NativeConflictContinuationResult {
    NativeConflictContinuationResult {
        state: NativeConflictContinuationState::Failed,
        activity_ids: Vec::new(),
        failure: Some(NativeConflictFailure { kind }),
    }
}

crate::family_failures!(NativeConflictFailureKind, "conflict", {
    NoActiveOperation => Precondition,
    MissingPath => NotFound,
    InvalidRequest => InvalidRequest,
    Stale => Stale,
    Unresolved => Conflict,
    TooLarge => TooLarge,
    Binary => Unsupported,
    Unsupported => Unsupported,
    Read => Read,
    Write => Write,
    Git => Git,
});

#[cfg(test)]
mod tests {
    use super::{contains_marker_lines, marker_regions};

    #[test]
    fn parses_merge_and_diff3_regions_without_inserting_separators() {
        let merge = b"before\n<<<<<<< HEAD\ncurrent\n=======\nincoming\n>>>>>>> topic\nafter\n";
        let regions = marker_regions(merge);
        assert_eq!(regions.len(), 1);
        assert_eq!(regions[0].current, b"current\n");
        assert_eq!(regions[0].incoming, b"incoming\n");
        assert_eq!(regions[0].ancestor, None);

        let diff3 =
            b"<<<<<<< HEAD\ncurrent\n||||||| base\nancestor\n=======\nincoming\n>>>>>>> topic\n";
        let regions = marker_regions(diff3);
        assert_eq!(regions.len(), 1);
        assert_eq!(regions[0].current, b"current\n");
        assert_eq!(regions[0].incoming, b"incoming\n");
        assert_eq!(
            regions[0].ancestor.as_deref(),
            Some(b"ancestor\n".as_slice())
        );
    }

    #[test]
    fn parses_multiple_and_empty_regions_and_rejects_marker_residue() {
        let value = b"<<<<<<< HEAD\n=======\none\n>>>>>>> topic\nmiddle\n<<<<<<< HEAD\ntwo\n=======\n>>>>>>> topic\n";
        let regions = marker_regions(value);
        assert_eq!(regions.len(), 2);
        assert!(regions[0].current.is_empty());
        assert_eq!(regions[0].incoming, b"one\n");
        assert_eq!(regions[1].current, b"two\n");
        assert!(regions[1].incoming.is_empty());
        assert!(contains_marker_lines(value));
        assert!(!contains_marker_lines(b"a clean, empty-capable result\n"));
        assert!(contains_marker_lines(b"text\n=======\n"));
        assert!(contains_marker_lines(b"<<<<<<< HEAD\r\n"));
        assert!(contains_marker_lines(b">>>>>>>\n"));
        // Markdown underlines and other runs of marker characters are content.
        assert!(!contains_marker_lines(b"Title\n==========\n"));
        assert!(!contains_marker_lines(b"<<<<<<<<\n>>>>>>>>>x\n"));
        assert!(marker_regions(b"").is_empty());
    }

    #[test]
    fn marker_lines_match_the_shared_fixture() {
        #[derive(serde::Deserialize)]
        struct Fixture {
            markers: Vec<String>,
            content: Vec<String>,
        }
        let fixture: Fixture =
            serde_json::from_str(include_str!("../../../test/fixtures/conflict_markers.json"))
                .unwrap();
        for text in &fixture.markers {
            assert!(contains_marker_lines(text.as_bytes()), "{text:?}");
        }
        for text in &fixture.content {
            assert!(!contains_marker_lines(text.as_bytes()), "{text:?}");
        }
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use crate::application::{conflicts::*, history_mutations::*, integrations::*, session::*};

    use crate::conflict::{
        NativeConflictContinuationState, NativeConflictFailureKind, NativeConflictFileKind,
        NativeConflictOperationKind, NativeConflictRegionChoice, NativeConflictSequencerAction,
        NativeConflictSideChoice,
    };

    use crate::history_operation::{
        NativeHistoryMergeMode, NativeHistoryMutationExecutionState, NativeHistoryMutationKind,
        NativeHistoryMutationRequest,
    };

    #[allow(unused_imports)] // Only some platforms' tests use all of them.
    use crate::integrations::{
        NativeIntegrationDefinition, NativeIntegrationExecution, NativeIntegrationExecutionState,
        NativeIntegrationFailureKind, NativeIntegrationKind, NativeIntegrationLaunchMode,
    };

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[cfg(unix)]
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::os::unix::fs::PermissionsExt;
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::path::{Path, PathBuf};

    #[test]
    fn conflict_resolver_takes_regions_undoes_staging_and_continues_merge() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("conflict.txt"), b"before\nbase\nafter\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("conflict.txt"), b"before\nincoming\nafter\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "topic"]);
        transfer_git(&fixture.0, &["switch", "main"]);
        fs::write(fixture.0.join("conflict.txt"), b"before\ncurrent\nafter\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "main"]);
        transfer_git(&fixture.0, &["remote", "add", "origin", "."]);
        transfer_git(
            &fixture.0,
            &["update-ref", "refs/remotes/origin/main", "topic"],
        );
        transfer_git_expect_failure(&fixture.0, &["merge", "origin/main"]);

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_221,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let loaded = repository_session_conflicts(session.session_id, session.generation);
        assert!(loaded.failure.is_none());
        let snapshot = loaded.snapshot.unwrap();
        assert_eq!(snapshot.operation, NativeConflictOperationKind::Merge);
        assert_eq!(snapshot.current_label, b"main");
        assert_eq!(snapshot.incoming_label, b"origin/main");
        assert!(snapshot
            .suggested_message
            .as_deref()
            .is_some_and(|message| message.contains("origin/main")));
        assert!(!snapshot.can_continue);
        assert!(!snapshot.can_skip);
        assert!(snapshot.resolved_undo_paths.is_empty());
        let file = &snapshot.files[0];
        assert_eq!(file.path, b"conflict.txt");
        assert_eq!(file.kind, NativeConflictFileKind::Text);
        assert_eq!(
            file.current.content.as_deref(),
            Some(b"before\ncurrent\nafter\n".as_slice())
        );
        assert_eq!(
            file.incoming.content.as_deref(),
            Some(b"before\nincoming\nafter\n".as_slice())
        );
        assert_eq!(file.regions.len(), 1);

        let resolved = repository_session_conflict_take_region(
            session.session_id,
            session.generation,
            file.path.clone(),
            file.fingerprint,
            0,
            NativeConflictRegionChoice::Both,
        );
        let snapshot = resolved.snapshot.unwrap();
        assert!(snapshot.files.is_empty());
        assert!(snapshot.can_continue);
        assert_eq!(snapshot.resolved_undo_paths, [b"conflict.txt".to_vec()]);
        assert_eq!(
            fs::read(fixture.0.join("conflict.txt")).unwrap(),
            b"before\ncurrent\nincoming\nafter\n"
        );

        let restored = repository_session_conflict_undo_resolution(
            session.session_id,
            session.generation,
            b"conflict.txt".to_vec(),
        );
        let snapshot = restored.snapshot.unwrap();
        assert_eq!(snapshot.files.len(), 1);
        assert!(snapshot.resolved_undo_paths.is_empty());
        assert!(!snapshot.can_continue);
        let file = &snapshot.files[0];
        let resolved = repository_session_conflict_save_result(
            session.session_id,
            session.generation,
            file.path.clone(),
            file.fingerprint,
            Vec::new(),
        );
        assert!(resolved.snapshot.unwrap().can_continue);
        assert_eq!(fs::read(fixture.0.join("conflict.txt")).unwrap(), b"");

        let completed = repository_session_conflict_continue_with_message(
            session.session_id,
            session.generation,
            NativeConflictSequencerAction::Continue,
            "Resolve topic changes\n\nReviewed both sides".to_owned(),
        );
        assert_eq!(completed.state, NativeConflictContinuationState::Completed);
        assert!(completed.failure.is_none());
        assert!(!fixture.0.join(".git/MERGE_HEAD").exists());
        assert_eq!(fs::read(fixture.0.join("conflict.txt")).unwrap(), b"");
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["log", "-1", "--format=%B"]))
                .unwrap()
                .trim(),
            "Resolve topic changes\n\nReviewed both sides"
        );
        assert_eq!(
            repository_session_conflicts(session.session_id, session.generation)
                .failure
                .unwrap()
                .kind,
            NativeConflictFailureKind::NoActiveOperation
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn unmerged_index_is_resolvable_without_a_sequencer_marker() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("conflict.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("conflict.txt"), b"incoming\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "topic"]);
        transfer_git(&fixture.0, &["switch", "main"]);
        fs::write(fixture.0.join("conflict.txt"), b"current\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "main"]);
        transfer_git_expect_failure(&fixture.0, &["merge", "topic"]);
        fs::remove_file(fixture.0.join(".git/MERGE_HEAD")).unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_241,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let snapshot = repository_session_conflicts(session.session_id, session.generation)
            .snapshot
            .unwrap();
        assert_eq!(snapshot.operation, NativeConflictOperationKind::Standalone);
        assert!(!snapshot.can_skip);
        assert_eq!(snapshot.files.len(), 1);
        assert_eq!(
            repository_session_conflict_continue(
                session.session_id,
                session.generation,
                NativeConflictSequencerAction::Abort,
            )
            .failure
            .unwrap()
            .kind,
            NativeConflictFailureKind::Unsupported
        );
        let file = &snapshot.files[0];
        let resolved = repository_session_conflict_choose_side(
            session.session_id,
            session.generation,
            file.path.clone(),
            file.fingerprint,
            NativeConflictSideChoice::Incoming,
        );
        assert!(resolved.snapshot.unwrap().files.is_empty());
        assert_eq!(
            fs::read(fixture.0.join("conflict.txt")).unwrap(),
            b"incoming\n"
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn conflicted_merge_continues_after_session_restart_with_recovery() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("conflict.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("conflict.txt"), b"incoming\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "topic"]);
        let topic = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&fixture.0, &["switch", "main"]);
        fs::write(fixture.0.join("conflict.txt"), b"current\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "main"]);

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_223,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let preview = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            NativeHistoryMutationRequest {
                kind: NativeHistoryMutationKind::Merge,
                targets: vec![topic],
                source_name: Some(b"topic".to_vec()),
                merge_mode: NativeHistoryMergeMode::FastForwardIfPossible,
                acknowledge_published_history: false,
                no_commit: false,
            },
        )
        .preview
        .unwrap();
        let started = repository_session_history_mutation_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert_eq!(started.state, NativeHistoryMutationExecutionState::Conflict);
        assert!(repository_session_close(session.session_id, session.generation).accepted);

        let reopened = repository_session_open_with_options(
            fixture.0.clone(),
            1_224,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&reopened);
        let conflicts = repository_session_conflicts(reopened.session_id, reopened.generation)
            .snapshot
            .unwrap();
        assert_eq!(conflicts.operation, NativeConflictOperationKind::Merge);
        let file = &conflicts.files[0];
        let resolved = repository_session_conflict_choose_side(
            reopened.session_id,
            reopened.generation,
            file.path.clone(),
            file.fingerprint,
            NativeConflictSideChoice::Incoming,
        );
        assert!(resolved.snapshot.unwrap().can_continue);
        let completed = repository_session_conflict_continue(
            reopened.session_id,
            reopened.generation,
            NativeConflictSequencerAction::Continue,
        );
        assert_eq!(completed.state, NativeConflictContinuationState::Completed);
        assert_eq!(
            fs::read(fixture.0.join("conflict.txt")).unwrap(),
            b"incoming\n"
        );
        assert!(repository_session_close(reopened.session_id, reopened.generation).accepted);
    }

    #[test]
    fn conflict_resolver_skips_cherry_pick_and_revert_sequences() {
        let cherry = GitFixture::new();
        fs::write(cherry.0.join("conflict.txt"), b"base\n").unwrap();
        transfer_git(&cherry.0, &["add", "."]);
        transfer_git(&cherry.0, &["commit", "-qm", "base"]);
        transfer_git(&cherry.0, &["switch", "-c", "topic"]);
        fs::write(cherry.0.join("conflict.txt"), b"picked\n").unwrap();
        transfer_git(&cherry.0, &["commit", "-qam", "picked"]);
        let picked = String::from_utf8(transfer_git(&cherry.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&cherry.0, &["switch", "main"]);
        fs::write(cherry.0.join("conflict.txt"), b"current\n").unwrap();
        transfer_git(&cherry.0, &["commit", "-qam", "current"]);
        transfer_git_expect_failure(&cherry.0, &["cherry-pick", &picked]);
        let session = repository_session_open_with_options(
            cherry.0.clone(),
            1_225,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let snapshot = repository_session_conflicts(session.session_id, session.generation)
            .snapshot
            .unwrap();
        assert_eq!(snapshot.operation, NativeConflictOperationKind::CherryPick);
        assert!(snapshot.can_skip);
        let skipped = repository_session_conflict_continue(
            session.session_id,
            session.generation,
            NativeConflictSequencerAction::Skip,
        );
        assert_eq!(skipped.state, NativeConflictContinuationState::Completed);
        assert!(repository_session_close(session.session_id, session.generation).accepted);

        let revert = GitFixture::new();
        fs::write(revert.0.join("conflict.txt"), b"base\n").unwrap();
        transfer_git(&revert.0, &["add", "."]);
        transfer_git(&revert.0, &["commit", "-qm", "base"]);
        fs::write(revert.0.join("conflict.txt"), b"target\n").unwrap();
        transfer_git(&revert.0, &["commit", "-qam", "target"]);
        let target = String::from_utf8(transfer_git(&revert.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(revert.0.join("conflict.txt"), b"later\n").unwrap();
        transfer_git(&revert.0, &["commit", "-qam", "later"]);
        transfer_git_expect_failure(&revert.0, &["revert", "--no-edit", &target]);
        let session = repository_session_open_with_options(
            revert.0.clone(),
            1_226,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let snapshot = repository_session_conflicts(session.session_id, session.generation)
            .snapshot
            .unwrap();
        assert_eq!(snapshot.operation, NativeConflictOperationKind::Revert);
        assert!(snapshot.can_skip);
        let skipped = repository_session_conflict_continue(
            session.session_id,
            session.generation,
            NativeConflictSequencerAction::Skip,
        );
        assert_eq!(skipped.state, NativeConflictContinuationState::Completed);
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn conflict_resolver_preserves_absence_binary_huge_executable_and_symlink_entries() {
        use std::os::unix::fs::{symlink, PermissionsExt};

        let fixture = GitFixture::new();
        fs::write(fixture.0.join("delete.txt"), b"base\n").unwrap();
        fs::write(fixture.0.join("binary.bin"), b"\0base").unwrap();
        fs::write(fixture.0.join("huge.txt"), vec![b'a'; 1_100_000]).unwrap();
        fs::write(fixture.0.join("script.sh"), b"#!/bin/sh\necho base\n").unwrap();
        fs::set_permissions(
            fixture.0.join("script.sh"),
            fs::Permissions::from_mode(0o755),
        )
        .unwrap();
        symlink("base-target", fixture.0.join("link")).unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);

        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("delete.txt"), b"incoming\n").unwrap();
        fs::write(fixture.0.join("binary.bin"), b"\0incoming").unwrap();
        fs::write(fixture.0.join("huge.txt"), vec![b'i'; 1_100_000]).unwrap();
        fs::write(fixture.0.join("script.sh"), b"#!/bin/sh\necho incoming\n").unwrap();
        fs::remove_file(fixture.0.join("link")).unwrap();
        symlink("incoming-target", fixture.0.join("link")).unwrap();
        fs::write(fixture.0.join("added.txt"), b"incoming add\n").unwrap();
        transfer_git(&fixture.0, &["add", "-A"]);
        transfer_git(&fixture.0, &["commit", "-qm", "topic"]);

        transfer_git(&fixture.0, &["switch", "main"]);
        fs::remove_file(fixture.0.join("delete.txt")).unwrap();
        fs::write(fixture.0.join("binary.bin"), b"\0current").unwrap();
        fs::write(fixture.0.join("huge.txt"), vec![b'c'; 1_100_000]).unwrap();
        fs::write(fixture.0.join("script.sh"), b"#!/bin/sh\necho current\n").unwrap();
        fs::remove_file(fixture.0.join("link")).unwrap();
        symlink("current-target", fixture.0.join("link")).unwrap();
        fs::write(fixture.0.join("added.txt"), b"current add\n").unwrap();
        transfer_git(&fixture.0, &["add", "-A"]);
        transfer_git(&fixture.0, &["commit", "-qm", "main"]);
        transfer_git_expect_failure(&fixture.0, &["merge", "topic"]);

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_222,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let loaded = repository_session_conflicts(session.session_id, session.generation)
            .snapshot
            .unwrap();
        let file = |path: &[u8]| loaded.files.iter().find(|file| file.path == path).unwrap();
        assert!(!file(b"delete.txt").current.present);
        assert!(file(b"delete.txt").incoming.present);
        assert!(!file(b"added.txt").ancestor.present);
        assert_eq!(file(b"binary.bin").kind, NativeConflictFileKind::Binary);
        assert_eq!(file(b"huge.txt").kind, NativeConflictFileKind::Huge);

        let deletion = file(b"delete.txt");
        assert!(repository_session_conflict_choose_side(
            session.session_id,
            session.generation,
            deletion.path.clone(),
            deletion.fingerprint,
            NativeConflictSideChoice::Current,
        )
        .failure
        .is_none());
        assert!(!fixture.0.join("delete.txt").exists());
        assert_eq!(
            repository_session_conflict_save_result(
                session.session_id,
                session.generation,
                deletion.path.clone(),
                deletion.fingerprint,
                b"stale flush\n".to_vec(),
            )
            .failure
            .unwrap()
            .kind,
            NativeConflictFailureKind::MissingPath
        );
        assert!(!fixture.0.join("delete.txt").exists());

        for (path, choice) in [
            (b"binary.bin".as_slice(), NativeConflictSideChoice::Incoming),
            (b"huge.txt".as_slice(), NativeConflictSideChoice::Current),
            (b"added.txt".as_slice(), NativeConflictSideChoice::Incoming),
            (b"script.sh".as_slice(), NativeConflictSideChoice::Incoming),
            (b"link".as_slice(), NativeConflictSideChoice::Incoming),
        ] {
            let snapshot = repository_session_conflicts(session.session_id, session.generation)
                .snapshot
                .unwrap();
            let file = snapshot
                .files
                .iter()
                .find(|file| file.path == path)
                .unwrap();
            assert!(repository_session_conflict_choose_side(
                session.session_id,
                session.generation,
                file.path.clone(),
                file.fingerprint,
                choice,
            )
            .failure
            .is_none());
        }
        assert_eq!(
            fs::read(fixture.0.join("binary.bin")).unwrap(),
            b"\0incoming"
        );
        assert_eq!(
            fs::read(fixture.0.join("huge.txt")).unwrap(),
            vec![b'c'; 1_100_000]
        );
        assert_eq!(
            fs::read(fixture.0.join("added.txt")).unwrap(),
            b"incoming add\n"
        );
        assert_ne!(
            fs::metadata(fixture.0.join("script.sh"))
                .unwrap()
                .permissions()
                .mode()
                & 0o111,
            0
        );
        assert_eq!(
            fs::read_link(fixture.0.join("link")).unwrap(),
            PathBuf::from("incoming-target")
        );
        assert!(
            repository_session_conflicts(session.session_id, session.generation)
                .snapshot
                .unwrap()
                .can_continue
        );
        let aborted = repository_session_conflict_continue(
            session.session_id,
            session.generation,
            NativeConflictSequencerAction::Abort,
        );
        assert_eq!(aborted.state, NativeConflictContinuationState::Aborted);
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn external_merge_tool_materializes_binary_and_huge_sides_then_stages_result() {
        use std::os::unix::fs::PermissionsExt;

        let fixture = GitFixture::new();
        fs::write(fixture.0.join("binary.bin"), b"\0base").unwrap();
        fs::write(fixture.0.join("huge.txt"), vec![b'a'; 1_100_000]).unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("binary.bin"), b"\0incoming").unwrap();
        fs::write(fixture.0.join("huge.txt"), vec![b'i'; 1_100_000]).unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "incoming"]);
        transfer_git(&fixture.0, &["switch", "main"]);
        fs::write(fixture.0.join("binary.bin"), b"\0current").unwrap();
        fs::write(fixture.0.join("huge.txt"), vec![b'c'; 1_100_000]).unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "current"]);
        transfer_git_expect_failure(&fixture.0, &["merge", "topic"]);

        let runner = fixture.0.join("merge tool");
        fs::write(&runner, "#!/bin/sh\ncp -- \"$1\" \"$2\"\n").unwrap();
        fs::set_permissions(&runner, fs::Permissions::from_mode(0o700)).unwrap();
        let definition = || NativeIntegrationDefinition {
            id: "fixture merge".to_owned(),
            kind: NativeIntegrationKind::MergeTool,
            executable: crate::domain::path_identity::native_path_identity(&runner),
            arguments: vec!["{merge_incoming}".to_owned(), "{merge_result}".to_owned()],
            execution: NativeIntegrationExecution::Direct,
            launch_mode: NativeIntegrationLaunchMode::Wait,
            requires_confirmation: true,
            timeout_seconds: 30,
        };
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_223,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);

        for (path, expected, kind) in [
            (
                b"binary.bin".as_slice(),
                b"\0incoming".to_vec(),
                NativeConflictFileKind::Binary,
            ),
            (
                b"huge.txt".as_slice(),
                vec![b'i'; 1_100_000],
                NativeConflictFileKind::Huge,
            ),
        ] {
            let snapshot = repository_session_conflicts(session.session_id, session.generation)
                .snapshot
                .unwrap();
            let file = snapshot
                .files
                .iter()
                .find(|file| file.path == path)
                .unwrap();
            assert_eq!(file.kind, kind);
            let mut preview = repository_session_conflict_external_merge_preview(
                session.session_id,
                session.generation,
                file.path.clone(),
                file.fingerprint,
                definition(),
            )
            .preview
            .unwrap();
            assert_eq!(preview.arguments.len(), 2);
            assert!(Path::new(&preview.arguments[0]).is_file());
            assert!(Path::new(&preview.arguments[1]).is_file());
            if path == b"binary.bin" {
                fs::write(fixture.0.join("binary.bin"), b"\0drift").unwrap();
                let stale = repository_session_integration_execute(
                    session.session_id,
                    session.generation,
                    preview.token,
                    true,
                );
                assert_eq!(stale.state, NativeIntegrationExecutionState::Stale);
                assert_eq!(
                    stale.failure.unwrap().kind,
                    NativeIntegrationFailureKind::Stale
                );
                assert!(!Path::new(&preview.arguments[0]).exists());
                let refreshed =
                    repository_session_conflicts(session.session_id, session.generation)
                        .snapshot
                        .unwrap();
                let refreshed_file = refreshed
                    .files
                    .iter()
                    .find(|file| file.path == path)
                    .unwrap();
                preview = repository_session_conflict_external_merge_preview(
                    session.session_id,
                    session.generation,
                    refreshed_file.path.clone(),
                    refreshed_file.fingerprint,
                    definition(),
                )
                .preview
                .unwrap();
            }
            let result = repository_session_integration_execute(
                session.session_id,
                session.generation,
                preview.token,
                true,
            );
            assert_eq!(result.state, NativeIntegrationExecutionState::Completed);
            assert_eq!(
                fs::read(fixture.0.join(std::str::from_utf8(path).unwrap())).unwrap(),
                expected
            );
            assert!(!Path::new(&preview.arguments[0]).exists());
        }
        assert!(
            repository_session_conflicts(session.session_id, session.generation)
                .snapshot
                .unwrap()
                .can_continue
        );
        let aborted = repository_session_conflict_continue(
            session.session_id,
            session.generation,
            NativeConflictSequencerAction::Abort,
        );
        assert_eq!(aborted.state, NativeConflictContinuationState::Aborted);
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }
}
