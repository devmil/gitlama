//! Durable named worktree snapshots backed by hidden Git refs.
pub use gitlama_contract::named_snapshot::*;

use crate::activity::{allocate_activity_id, ActivityStore};
use crate::domain::outcome::{MutationOutcome, MutationState, MutationTerminalState};
use crate::dto::NativeConflictContinuationResult;
use crate::dto::NativeConflictContinuationState;
use crate::dto::NativeConflictFailure;
use crate::dto::NativeConflictFailureKind;
use crate::dto::NativeConflictSequencerAction;
use crate::operations::{coordinate_mutation, ExecutionFailure};
use crate::preview_store::PreviewStore;
use devmil_git::activity::ActivityStatus;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::status::{BranchHead, ChangeKind, StatusEntry, WorkingTreeState};
use devmil_git::{Repository, RepositorySnapshot};
use serde::{Deserialize, Serialize};
#[cfg(test)]
use std::cell::Cell;

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

type EventSink = Arc<dyn Fn(devmil_git::activity::ActivityEvent) + Send + Sync>;

const SCHEMA: &str = "gitlama.named-snapshots.v1";
const STORE_RELATIVE: &str = "gitlama/snapshots/v1";
const MAX_STORE_BYTES: u64 = 2 * 1024 * 1024;
const MAX_NAME_BYTES: usize = 128;
const MAX_ENTRIES: usize = 64;
const MAX_PREVIEW_PATHS: usize = 256;
const PREVIEW_CAPACITY_PER_SESSION: usize = 8;

const fn native_state(state: MutationState) -> NativeNamedSnapshotExecutionState {
    match state {
        MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
            NativeNamedSnapshotExecutionState::Completed
        }
        MutationState::ReconciledWithWarning => {
            NativeNamedSnapshotExecutionState::ReconciledWithWarning
        }
        MutationState::Conflict
        | MutationState::Interrupted
        | MutationState::EditStop
        | MutationState::Partial => NativeNamedSnapshotExecutionState::Conflict,
        MutationState::Stale => NativeNamedSnapshotExecutionState::Stale,
        MutationState::Canceled => NativeNamedSnapshotExecutionState::Canceled,
        MutationState::Failed => NativeNamedSnapshotExecutionState::Failed,
        MutationState::OutcomeUncertain => NativeNamedSnapshotExecutionState::OutcomeUncertain,
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StoredSnapshot {
    id: u64,
    name: String,
    created_at_unix_ms: u64,
    base_ref: Option<Vec<u8>>,
    base_oid: String,
    object_id: String,
    staged_count: u32,
    unstaged_count: u32,
    untracked_count: u32,
    includes_untracked: bool,
    keeps_index: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SnapshotStore {
    schema: String,
    next_id: u64,
    entries: Vec<StoredSnapshot>,
}

impl Default for SnapshotStore {
    fn default() -> Self {
        Self {
            schema: SCHEMA.to_owned(),
            next_id: 1,
            entries: Vec::new(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct SnapshotFacts {
    revision: u64,
    worktree: PathBuf,
    common_git_dir: PathBuf,
    branch: Option<Vec<u8>>,
    head: String,
    paths: Vec<Vec<u8>>,
}

#[derive(Clone)]
struct RestorePlan {
    facts: SnapshotFacts,
    entry: StoredSnapshot,
}

static RESTORES: OnceLock<Mutex<PreviewStore<RestorePlan>>> = OnceLock::new();
#[cfg(test)]
thread_local! {
    static FORCE_STORE_WRITE_FAILURE: Cell<bool> = const { Cell::new(false) };
}

fn lock_restores() -> std::sync::MutexGuard<'static, PreviewStore<RestorePlan>> {
    crate::preview_store::lock(
        RESTORES.get_or_init(|| Mutex::new(PreviewStore::new(PREVIEW_CAPACITY_PER_SESSION))),
    )
}

pub(crate) fn list(
    repository: &Repository,
    offset: u32,
    maximum: u32,
) -> NativeNamedSnapshotListResult {
    if maximum == 0 || maximum > MAX_ENTRIES as u32 {
        return list_failure(NativeNamedSnapshotFailureKind::InvalidRequest);
    }
    let Some(facts) = facts(&repository.snapshot()) else {
        return list_failure(NativeNamedSnapshotFailureKind::Read);
    };
    let store = match read_store(&facts.common_git_dir) {
        Ok(value) => value,
        Err(kind) => return list_failure(kind),
    };
    let total = store.entries.len();
    let start = usize::try_from(offset).unwrap_or(usize::MAX).min(total);
    let end = start.saturating_add(maximum as usize).min(total);
    let entries = store.entries[start..end]
        .iter()
        .map(|entry| map_entry(entry, &facts.common_git_dir))
        .collect();
    NativeNamedSnapshotListResult {
        entries,
        total: total.try_into().unwrap_or(u32::MAX),
        next_offset: (end < total).then_some(end.try_into().unwrap_or(u32::MAX)),
        failure: None,
    }
}

pub(crate) fn create(
    repository: &Repository,
    activity: &ActivityStore,
    name: String,
    include_untracked: bool,
    keep_index: bool,
) -> NativeNamedSnapshotExecutionResult {
    if !valid_name(&name) {
        return execution_failure(NativeNamedSnapshotFailureKind::InvalidRequest);
    }
    let snapshot = repository.snapshot();
    let Some(facts) = facts(&snapshot) else {
        return execution_failure(NativeNamedSnapshotFailureKind::Read);
    };
    let Some(status) = snapshot.status.as_ref() else {
        return execution_failure(NativeNamedSnapshotFailureKind::Read);
    };
    if status.working_tree == WorkingTreeState::Clean {
        return execution_failure(NativeNamedSnapshotFailureKind::NothingToCapture);
    }
    if status.working_tree == WorkingTreeState::Conflicted {
        return execution_failure(NativeNamedSnapshotFailureKind::DirtyConflict);
    }
    if !status.operations.is_empty() {
        return execution_failure(NativeNamedSnapshotFailureKind::ActiveOperation);
    }
    let (staged_count, unstaged_count, untracked_count) = counts(status);
    let mut store = match read_store(&facts.common_git_dir) {
        Ok(value) => value,
        Err(kind) => return execution_failure(kind),
    };
    let id = store.next_id.max(1);
    store.next_id = id.saturating_add(1);
    let reference = snapshot_ref(id);
    let cancellation = AtomicBool::new(false);
    let sink = activity.sink();
    let mut activity_ids = Vec::new();
    let mut created: Option<StoredSnapshot> = None;
    let mut failure = None;
    let outcome = coordinate_mutation(repository, &cancellation, |cancellation| {
        let message = format!("GitLama snapshot {id}");
        let mut push = vec!["stash".to_owned(), "push".to_owned()];
        if include_untracked {
            push.push("--include-untracked".to_owned());
        }
        if keep_index {
            push.push("--keep-index".to_owned());
        }
        push.extend(["--message".to_owned(), message]);
        if run(
            &facts.worktree,
            push,
            cancellation,
            &sink,
            &mut activity_ids,
        )
        .is_err()
        {
            failure = Some(NativeNamedSnapshotFailureKind::Git);
            return Err(ExecutionFailure::Definite);
        }
        let Some(object_id) = resolve(
            &facts.worktree,
            "refs/stash",
            cancellation,
            &sink,
            &mut activity_ids,
        ) else {
            failure = Some(NativeNamedSnapshotFailureKind::Git);
            return Err(ExecutionFailure::Definite);
        };
        if run(
            &facts.worktree,
            vec![
                "update-ref".to_owned(),
                reference.clone(),
                object_id.clone(),
            ],
            cancellation,
            &sink,
            &mut activity_ids,
        )
        .is_err()
        {
            failure = Some(NativeNamedSnapshotFailureKind::Write);
            return Err(ExecutionFailure::Definite);
        }
        let entry = StoredSnapshot {
            id,
            name: name.clone(),
            created_at_unix_ms: now_unix_ms(),
            base_ref: facts.branch.clone(),
            base_oid: facts.head.clone(),
            object_id,
            staged_count,
            unstaged_count,
            untracked_count,
            includes_untracked: include_untracked,
            keeps_index: keep_index,
        };
        store.entries.insert(0, entry.clone());
        let pruned = enforce_retention(&mut store.entries);
        if let Err(kind) = write_store(&facts.common_git_dir, &store) {
            failure = Some(kind);
            let removed_ref = run(
                &facts.worktree,
                vec!["update-ref".to_owned(), "-d".to_owned(), reference.clone()],
                cancellation,
                &sink,
                &mut activity_ids,
            )
            .is_ok();
            let restored = run(
                &facts.worktree,
                vec![
                    "stash".to_owned(),
                    "apply".to_owned(),
                    "--index".to_owned(),
                    "refs/stash".to_owned(),
                ],
                cancellation,
                &sink,
                &mut activity_ids,
            )
            .and_then(|()| {
                run(
                    &facts.worktree,
                    vec![
                        "stash".to_owned(),
                        "drop".to_owned(),
                        "stash@{0}".to_owned(),
                    ],
                    cancellation,
                    &sink,
                    &mut activity_ids,
                )
            })
            .is_ok();
            return Err(if removed_ref && restored {
                ExecutionFailure::Definite
            } else {
                ExecutionFailure::Uncertain
            });
        }
        created = Some(entry);
        let _ = run(
            &facts.worktree,
            vec![
                "stash".to_owned(),
                "drop".to_owned(),
                "stash@{0}".to_owned(),
            ],
            cancellation,
            &sink,
            &mut activity_ids,
        );
        if run(
            &facts.worktree,
            vec!["reset".to_owned(), "--hard".to_owned(), "HEAD".to_owned()],
            cancellation,
            &sink,
            &mut activity_ids,
        )
        .and_then(|()| {
            run(
                &facts.worktree,
                vec![
                    "stash".to_owned(),
                    "apply".to_owned(),
                    "--index".to_owned(),
                    reference.clone(),
                ],
                cancellation,
                &sink,
                &mut activity_ids,
            )
        })
        .is_err()
        {
            failure = Some(if has_unmerged_paths(&facts.worktree) {
                NativeNamedSnapshotFailureKind::Conflict
            } else {
                NativeNamedSnapshotFailureKind::Git
            });
            return Err(ExecutionFailure::Definite);
        }
        for expired in pruned {
            let _ = run(
                &facts.worktree,
                vec![
                    "update-ref".to_owned(),
                    "-d".to_owned(),
                    snapshot_ref(expired.id),
                ],
                cancellation,
                &sink,
                &mut activity_ids,
            );
        }
        Ok(())
    });
    map_outcome(
        outcome,
        created,
        None,
        &facts.worktree,
        &facts.common_git_dir,
        activity_ids,
        failure,
    )
}

pub(crate) fn preview_restore(
    session_id: u64,
    repository: &Repository,
    snapshot_id: u64,
) -> NativeNamedSnapshotRestorePreviewResult {
    let Some(facts) = facts(&repository.snapshot()) else {
        return preview_failure(NativeNamedSnapshotFailureKind::Read);
    };
    let store = match read_store(&facts.common_git_dir) {
        Ok(value) => value,
        Err(kind) => return preview_failure(kind),
    };
    let Some(entry) = store
        .entries
        .into_iter()
        .find(|entry| entry.id == snapshot_id)
    else {
        return preview_failure(NativeNamedSnapshotFailureKind::Missing);
    };
    if !ref_exists(&facts.common_git_dir, entry.id) {
        return preview_failure(NativeNamedSnapshotFailureKind::Corrupt);
    }
    let token = lock_restores().issue(
        session_id,
        RestorePlan {
            facts: facts.clone(),
            entry: entry.clone(),
        },
    );
    let replacement_paths_truncated = facts.paths.len() > MAX_PREVIEW_PATHS;
    let replacement_paths = facts
        .paths
        .iter()
        .take(MAX_PREVIEW_PATHS)
        .cloned()
        .collect();
    NativeNamedSnapshotRestorePreviewResult {
        preview: Some(NativeNamedSnapshotRestorePreview {
            token,
            snapshot: map_entry(&entry, &facts.common_git_dir),
            replacement_paths,
            replacement_paths_truncated,
            replaces_index: true,
            replaces_worktree: true,
        }),
        failure: None,
    }
}

pub(crate) fn execute_restore(
    session_id: u64,
    token: u64,
    repository: &Repository,
    activity: &ActivityStore,
) -> NativeNamedSnapshotExecutionResult {
    let (plan, cancellation) = {
        let mut registry = lock_restores();
        let Some(owned) = registry.get_mut(session_id, token) else {
            return execution_failure(NativeNamedSnapshotFailureKind::InvalidRequest);
        };
        if owned.running {
            return execution_failure(NativeNamedSnapshotFailureKind::InvalidRequest);
        }
        owned.running = true;
        owned.cancellation.store(false, Ordering::Release);
        (owned.value.clone(), Arc::clone(&owned.cancellation))
    };
    let Some(current) = facts(&repository.snapshot()) else {
        finish_restore(session_id, token);
        return execution_failure(NativeNamedSnapshotFailureKind::Read);
    };
    if current != plan.facts || !ref_exists(&current.common_git_dir, plan.entry.id) {
        finish_restore(session_id, token);
        return execution_failure(NativeNamedSnapshotFailureKind::Stale);
    }
    let recovery_ref = format!("refs/gitlama/recovery/snapshot-restore-{token}");
    let target_ref = snapshot_ref(plan.entry.id);
    let sink = activity.sink();
    let mut activity_ids = Vec::new();
    let mut failure = None;
    let mut retained_recovery = false;
    let outcome = coordinate_mutation(repository, cancellation.as_ref(), |cancellation| {
        let has_changes =
            match has_worktree_changes(&current.worktree, cancellation, &sink, &mut activity_ids) {
                Ok(value) => value,
                Err(error) => {
                    failure = Some(NativeNamedSnapshotFailureKind::Git);
                    return Err(error);
                }
            };
        if !has_changes {
            if run(
                &current.worktree,
                vec![
                    "stash".to_owned(),
                    "apply".to_owned(),
                    "--index".to_owned(),
                    target_ref.clone(),
                ],
                cancellation,
                &sink,
                &mut activity_ids,
            )
            .is_err()
            {
                failure = Some(if has_unmerged_paths(&current.worktree) {
                    let _ = write_active_restore(&current.common_git_dir, plan.entry.id, "-");
                    NativeNamedSnapshotFailureKind::Conflict
                } else {
                    NativeNamedSnapshotFailureKind::Git
                });
                return Err(ExecutionFailure::Definite);
            }
            return Ok(());
        }
        if run(
            &current.worktree,
            vec![
                "stash".to_owned(),
                "push".to_owned(),
                "--include-untracked".to_owned(),
                "--message".to_owned(),
                "Changes before restoring a snapshot".to_owned(),
            ],
            cancellation,
            &sink,
            &mut activity_ids,
        )
        .is_err()
        {
            failure = Some(NativeNamedSnapshotFailureKind::Git);
            return Err(ExecutionFailure::Definite);
        }
        let Some(recovery_oid) = resolve(
            &current.worktree,
            "refs/stash",
            cancellation,
            &sink,
            &mut activity_ids,
        ) else {
            failure = Some(NativeNamedSnapshotFailureKind::Git);
            return Err(ExecutionFailure::Definite);
        };
        if run(
            &current.worktree,
            vec!["update-ref".to_owned(), recovery_ref.clone(), recovery_oid],
            cancellation,
            &sink,
            &mut activity_ids,
        )
        .is_err()
        {
            failure = Some(NativeNamedSnapshotFailureKind::Write);
            return Err(ExecutionFailure::Definite);
        }
        // The stash stays in the list, where the user finds the changes the restore
        // replaced; the ref lets an abandoned restore put them back.
        retained_recovery = true;
        if run(
            &current.worktree,
            vec![
                "stash".to_owned(),
                "apply".to_owned(),
                "--index".to_owned(),
                target_ref.clone(),
            ],
            cancellation,
            &sink,
            &mut activity_ids,
        )
        .is_err()
        {
            failure = Some(if has_unmerged_paths(&current.worktree) {
                let _ = write_active_restore(&current.common_git_dir, plan.entry.id, &recovery_ref);
                NativeNamedSnapshotFailureKind::Conflict
            } else {
                NativeNamedSnapshotFailureKind::Git
            });
            return Err(ExecutionFailure::Definite);
        }
        Ok(())
    });
    finish_restore(session_id, token);
    map_outcome(
        outcome,
        Some(plan.entry),
        retained_recovery.then(|| recovery_ref.into_bytes()),
        &current.worktree,
        &current.common_git_dir,
        activity_ids,
        failure,
    )
}

pub(crate) fn create_branch(
    repository: &Repository,
    activity: &ActivityStore,
    snapshot_id: u64,
    branch: Vec<u8>,
) -> NativeNamedSnapshotExecutionResult {
    let Some(facts) = facts(&repository.snapshot()) else {
        return execution_failure(NativeNamedSnapshotFailureKind::Read);
    };
    let Ok(branch) = String::from_utf8(branch) else {
        return execution_failure(NativeNamedSnapshotFailureKind::InvalidRequest);
    };
    if branch.is_empty() || branch.starts_with('-') || branch.contains(char::is_whitespace) {
        return execution_failure(NativeNamedSnapshotFailureKind::InvalidRequest);
    }
    let store = match read_store(&facts.common_git_dir) {
        Ok(value) => value,
        Err(kind) => return execution_failure(kind),
    };
    let Some(entry) = store
        .entries
        .into_iter()
        .find(|entry| entry.id == snapshot_id)
    else {
        return execution_failure(NativeNamedSnapshotFailureKind::Missing);
    };
    let cancellation = AtomicBool::new(false);
    let sink = activity.sink();
    let mut activity_ids = Vec::new();
    if run(
        &facts.worktree,
        vec![
            "check-ref-format".to_owned(),
            "--branch".to_owned(),
            branch.clone(),
        ],
        &cancellation,
        &sink,
        &mut activity_ids,
    )
    .is_err()
        || resolve(
            &facts.worktree,
            &format!("refs/heads/{branch}"),
            &cancellation,
            &sink,
            &mut activity_ids,
        )
        .is_some()
    {
        return execution_failure(NativeNamedSnapshotFailureKind::InvalidRequest);
    }
    let tree = format!("{}^{{tree}}", snapshot_ref(snapshot_id));
    let Some(commit) = capture(
        &facts.worktree,
        vec![
            "commit-tree".to_owned(),
            tree,
            "-p".to_owned(),
            entry.base_oid.clone(),
            "-m".to_owned(),
            format!("Snapshot: {}", entry.name),
        ],
        &cancellation,
        &sink,
        &mut activity_ids,
    ) else {
        return execution_failure(NativeNamedSnapshotFailureKind::Git);
    };
    let missing = "0".repeat(commit.len());
    if run(
        &facts.worktree,
        vec![
            "update-ref".to_owned(),
            format!("refs/heads/{branch}"),
            commit,
            missing,
        ],
        &cancellation,
        &sink,
        &mut activity_ids,
    )
    .is_err()
    {
        return execution_failure(NativeNamedSnapshotFailureKind::Git);
    }
    map_outcome(
        MutationTerminalState::Succeeded,
        Some(entry),
        None,
        &facts.worktree,
        &facts.common_git_dir,
        activity_ids,
        None,
    )
}

pub(crate) fn delete(
    repository: &Repository,
    activity: &ActivityStore,
    snapshot_id: u64,
) -> NativeNamedSnapshotExecutionResult {
    let Some(facts) = facts(&repository.snapshot()) else {
        return execution_failure(NativeNamedSnapshotFailureKind::Read);
    };
    let mut store = match read_store(&facts.common_git_dir) {
        Ok(value) => value,
        Err(kind) => return execution_failure(kind),
    };
    let Some(index) = store
        .entries
        .iter()
        .position(|entry| entry.id == snapshot_id)
    else {
        return execution_failure(NativeNamedSnapshotFailureKind::Missing);
    };
    let entry = store.entries[index].clone();
    let cancellation = AtomicBool::new(false);
    let sink = activity.sink();
    let mut activity_ids = Vec::new();
    if run(
        &facts.worktree,
        vec![
            "update-ref".to_owned(),
            "-d".to_owned(),
            snapshot_ref(snapshot_id),
        ],
        &cancellation,
        &sink,
        &mut activity_ids,
    )
    .is_err()
    {
        return execution_failure(NativeNamedSnapshotFailureKind::Git);
    }
    store.entries.remove(index);
    if let Err(kind) = write_store(&facts.common_git_dir, &store) {
        return execution_failure(kind);
    }
    map_outcome(
        MutationTerminalState::Succeeded,
        Some(entry),
        None,
        &facts.worktree,
        &facts.common_git_dir,
        activity_ids,
        None,
    )
}

pub(crate) fn cancel_restore(session_id: u64, token: u64) -> bool {
    lock_restores().cancel(session_id, token)
}

pub(crate) fn dismiss_session(session_id: u64) {
    lock_restores().dismiss_session(session_id);
}

pub(crate) fn active_restore(common_git_dir: &Path) -> Option<String> {
    let directory = common_git_dir.join(STORE_RELATIVE).join("active-restore");
    let metadata = fs::symlink_metadata(&directory).ok()?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return None;
    }
    let value = fs::read(directory.join("recovery-ref")).ok()?;
    let value = String::from_utf8(value).ok()?;
    (value == "-" || value.starts_with("refs/gitlama/recovery/snapshot-restore-")).then_some(value)
}

pub(crate) fn finish_active_restore(common_git_dir: &Path) -> bool {
    let directory = common_git_dir.join(STORE_RELATIVE).join("active-restore");
    !directory.exists() || fs::remove_dir_all(directory).is_ok()
}

fn facts(snapshot: &RepositorySnapshot) -> Option<SnapshotFacts> {
    let repository = snapshot.repository.as_ref()?;
    let status = snapshot.status.as_ref()?;
    let head = status.branch.oid.as_ref()?.as_str().to_owned();
    let branch = match &status.branch.head {
        BranchHead::Attached(value) | BranchHead::Unborn { branch: value } => {
            Some(value.as_bytes().to_vec())
        }
        BranchHead::Detached => None,
    };
    Some(SnapshotFacts {
        revision: snapshot.revision,
        worktree: repository.worktree.worktree_root().as_path().to_path_buf(),
        common_git_dir: repository
            .worktree
            .repository()
            .common_git_dir()
            .as_path()
            .to_path_buf(),
        branch,
        head,
        paths: status
            .entries
            .iter()
            .filter(|entry| !matches!(entry, StatusEntry::Ignored(_)))
            .map(|entry| native_path_bytes(entry.path().as_path()))
            .collect(),
    })
}

fn counts(status: &devmil_git::status::RepositoryStatus) -> (u32, u32, u32) {
    let mut staged = 0u32;
    let mut unstaged = 0u32;
    let mut untracked = 0u32;
    for entry in &status.entries {
        match entry {
            StatusEntry::Untracked(_) => untracked = untracked.saturating_add(1),
            StatusEntry::Ordinary(value) => {
                staged =
                    staged.saturating_add(u32::from(value.state.index != ChangeKind::Unmodified));
                unstaged = unstaged
                    .saturating_add(u32::from(value.state.worktree != ChangeKind::Unmodified));
            }
            StatusEntry::Rename(value) => {
                staged =
                    staged.saturating_add(u32::from(value.state.index != ChangeKind::Unmodified));
                unstaged = unstaged
                    .saturating_add(u32::from(value.state.worktree != ChangeKind::Unmodified));
            }
            StatusEntry::Unmerged(_) => {}
            StatusEntry::Ignored(_) => {}
        }
    }
    (staged, unstaged, untracked)
}

/// The owner-only snapshot store, `<common>/gitlama/snapshots/v1`, created on first use.
fn open_store(
    common_git_dir: &Path,
) -> Result<crate::private_store::PrivateDir, NativeNamedSnapshotFailureKind> {
    crate::private_store::PrivateDir::repository(common_git_dir, &["snapshots", "v1"])
        .map_err(|_| NativeNamedSnapshotFailureKind::Write)
}

fn read_store(common_git_dir: &Path) -> Result<SnapshotStore, NativeNamedSnapshotFailureKind> {
    let store = crate::private_store::PrivateDir::repository(common_git_dir, &["snapshots", "v1"])
        .map_err(|_| NativeNamedSnapshotFailureKind::Read)?;
    let bytes = match store.read("index.json", MAX_STORE_BYTES) {
        Ok(Some(bytes)) => bytes,
        Ok(None) => return Ok(SnapshotStore::default()),
        Err(error) if error.kind() == std::io::ErrorKind::InvalidData => {
            return Err(NativeNamedSnapshotFailureKind::TooLarge)
        }
        Err(error) if error.kind() == std::io::ErrorKind::InvalidInput => {
            return Err(NativeNamedSnapshotFailureKind::Corrupt)
        }
        Err(_) => return Err(NativeNamedSnapshotFailureKind::Read),
    };
    let store: SnapshotStore =
        serde_json::from_slice(&bytes).map_err(|_| NativeNamedSnapshotFailureKind::Corrupt)?;
    if store.schema != SCHEMA || store.entries.len() > MAX_ENTRIES {
        return Err(NativeNamedSnapshotFailureKind::Corrupt);
    }
    Ok(store)
}

fn write_store(
    common_git_dir: &Path,
    store: &SnapshotStore,
) -> Result<(), NativeNamedSnapshotFailureKind> {
    #[cfg(test)]
    if FORCE_STORE_WRITE_FAILURE.with(|value| value.replace(false)) {
        return Err(NativeNamedSnapshotFailureKind::Write);
    }
    let bytes = serde_json::to_vec(store).map_err(|_| NativeNamedSnapshotFailureKind::Write)?;
    if bytes.len() as u64 > MAX_STORE_BYTES {
        return Err(NativeNamedSnapshotFailureKind::TooLarge);
    }
    open_store(common_git_dir)?
        .replace("index.json", &bytes)
        .map_err(|_| NativeNamedSnapshotFailureKind::Write)
}

fn enforce_retention(entries: &mut Vec<StoredSnapshot>) -> Vec<StoredSnapshot> {
    if entries.len() > MAX_ENTRIES {
        entries.split_off(MAX_ENTRIES)
    } else {
        Vec::new()
    }
}

#[cfg(test)]
pub(crate) fn fail_next_store_write() {
    FORCE_STORE_WRITE_FAILURE.with(|value| value.set(true));
}

fn write_active_restore(
    common_git_dir: &Path,
    snapshot_id: u64,
    recovery_ref: &str,
) -> Result<(), NativeNamedSnapshotFailureKind> {
    let store = open_store(common_git_dir)?;
    store
        .remove("active-restore")
        .and_then(|()| store.child("active-restore"))
        .and_then(|active| {
            active.write_new("snapshot-id", snapshot_id.to_string().as_bytes())?;
            active.write_new("recovery-ref", recovery_ref.as_bytes())
        })
        .map_err(|_| NativeNamedSnapshotFailureKind::Write)
}

fn run(
    worktree: &Path,
    arguments: Vec<String>,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &mut Vec<String>,
) -> Result<(), ExecutionFailure> {
    // Every command this runs changes the snapshot refs, the index or the worktree.
    let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
    activity_ids.push(id.get().to_string());
    let command = GitProcessCommand::git("git")
        .args(arguments.into_iter().map(ProcessArgument::visible))
        .current_dir(worktree)
        .redact_output();
    let mut publish = |event| sink(event);
    let result = ActivityGitRunner::run_private(command, id, Some(cancellation), &mut publish);
    match result.activity.status {
        ActivityStatus::Succeeded { .. } => Ok(()),
        ActivityStatus::Canceled { .. } => Err(ExecutionFailure::Canceled),
        _ => Err(ExecutionFailure::Definite),
    }
}

fn capture(
    worktree: &Path,
    arguments: Vec<String>,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &mut Vec<String>,
) -> Option<String> {
    let id = allocate_activity_id();
    activity_ids.push(id.get().to_string());
    let command = GitProcessCommand::git("git")
        .args(arguments.into_iter().map(ProcessArgument::visible))
        .current_dir(worktree)
        .redact_output();
    let mut publish = |event| sink(event);
    let mut result = ActivityGitRunner::run_private(command, id, Some(cancellation), &mut publish);
    matches!(result.activity.status, ActivityStatus::Succeeded { .. })
        .then(|| String::from_utf8(result.stdout.take_bytes()).ok())
        .flatten()
        .map(|value| value.trim().to_owned())
}

fn has_worktree_changes(
    worktree: &Path,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &mut Vec<String>,
) -> Result<bool, ExecutionFailure> {
    let id = allocate_activity_id();
    activity_ids.push(id.get().to_string());
    let command = GitProcessCommand::git("git")
        .args([
            ProcessArgument::visible("status"),
            ProcessArgument::visible("--porcelain=v1"),
            ProcessArgument::visible("--untracked-files=all"),
            ProcessArgument::visible("-z"),
        ])
        .current_dir(worktree)
        .redact_output();
    let mut publish = |event| sink(event);
    let mut result = ActivityGitRunner::run_private(command, id, Some(cancellation), &mut publish);
    match result.activity.status {
        ActivityStatus::Succeeded { .. } => Ok(!result.stdout.take_bytes().is_empty()),
        ActivityStatus::Canceled { .. } => Err(ExecutionFailure::Canceled),
        _ => Err(ExecutionFailure::Definite),
    }
}

fn resolve(
    worktree: &Path,
    value: &str,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &mut Vec<String>,
) -> Option<String> {
    let publish = |event| sink(event);
    let mut record = |id: devmil_git::activity::ActivityId| activity_ids.push(id.get().to_string());
    devmil_git::probes::resolve(
        std::ffi::OsStr::new("git"),
        worktree,
        value,
        &mut crate::git_probe::ProbeExecutor::publishing(Some(cancellation), &publish, &mut record),
    )
    .ok()
    .flatten()
    .map(|object| object.as_str().to_owned())
}

fn ref_exists(common_git_dir: &Path, id: u64) -> bool {
    if common_git_dir.join(snapshot_ref(id)).is_file() {
        return true;
    }
    // Packed refs: ask Git, through the runner, from the common directory.
    devmil_git::probes::resolve(
        std::ffi::OsStr::new("git"),
        common_git_dir,
        &snapshot_ref(id),
        &mut crate::git_probe::ProbeExecutor::new(None),
    )
    .is_ok_and(|object| object.is_some())
}

fn map_entry(entry: &StoredSnapshot, common_git_dir: &Path) -> NativeNamedSnapshot {
    NativeNamedSnapshot {
        id: entry.id,
        name: entry.name.clone(),
        created_at_unix_ms: entry.created_at_unix_ms,
        base_ref: entry.base_ref.clone(),
        base_oid: entry.base_oid.clone(),
        object_id: entry.object_id.clone(),
        staged_count: entry.staged_count,
        unstaged_count: entry.unstaged_count,
        untracked_count: entry.untracked_count,
        includes_untracked: entry.includes_untracked,
        keeps_index: entry.keeps_index,
        state: if ref_exists(common_git_dir, entry.id) {
            NativeNamedSnapshotState::Ready
        } else {
            NativeNamedSnapshotState::Missing
        },
    }
}

fn map_outcome(
    state: MutationTerminalState,
    entry: Option<StoredSnapshot>,
    recovery_ref: Option<Vec<u8>>,
    worktree: &Path,
    common_git_dir: &Path,
    activity_ids: Vec<String>,
    failure: Option<NativeNamedSnapshotFailureKind>,
) -> NativeNamedSnapshotExecutionResult {
    let mut outcome = MutationOutcome::from_terminal(state).with_failure(failure);
    if outcome.state == MutationState::Failed {
        match outcome.failure {
            Some(NativeNamedSnapshotFailureKind::Conflict) => {
                outcome.state = MutationState::Conflict
            }
            Some(NativeNamedSnapshotFailureKind::Stale) => outcome.state = MutationState::Stale,
            _ => {}
        }
    }
    NativeNamedSnapshotExecutionResult {
        state: native_state(outcome.state),
        snapshot: entry.map(|entry| map_entry(&entry, common_git_dir)),
        recovery_ref,
        conflicting_paths: conflict_paths(worktree),
        activity_ids,
        failure: outcome
            .failure
            .map(|kind| NativeNamedSnapshotFailure { kind }),
    }
}

fn conflict_paths(worktree: &Path) -> Vec<Vec<u8>> {
    devmil_git::probes::unmerged_paths(
        std::ffi::OsStr::new("git"),
        worktree,
        &mut crate::git_probe::ProbeExecutor::new(None),
    )
    .map(|paths| paths.iter().map(|path| path.as_bytes().to_vec()).collect())
    .unwrap_or_default()
}

fn has_unmerged_paths(worktree: &Path) -> bool {
    !conflict_paths(worktree).is_empty()
}

fn snapshot_ref(id: u64) -> String {
    format!("refs/gitlama/snapshots/{id}")
}

fn valid_name(name: &str) -> bool {
    !name.trim().is_empty() && name.len() <= MAX_NAME_BYTES && !name.chars().any(char::is_control)
}

fn finish_restore(session_id: u64, token: u64) {
    lock_restores().finish(session_id, token);
}

fn preview_failure(
    kind: NativeNamedSnapshotFailureKind,
) -> NativeNamedSnapshotRestorePreviewResult {
    NativeNamedSnapshotRestorePreviewResult {
        preview: None,
        failure: Some(NativeNamedSnapshotFailure { kind }),
    }
}

fn list_failure(kind: NativeNamedSnapshotFailureKind) -> NativeNamedSnapshotListResult {
    NativeNamedSnapshotListResult {
        entries: Vec::new(),
        total: 0,
        next_offset: None,
        failure: Some(NativeNamedSnapshotFailure { kind }),
    }
}

fn execution_failure(kind: NativeNamedSnapshotFailureKind) -> NativeNamedSnapshotExecutionResult {
    NativeNamedSnapshotExecutionResult {
        state: if kind == NativeNamedSnapshotFailureKind::Stale {
            NativeNamedSnapshotExecutionState::Stale
        } else {
            NativeNamedSnapshotExecutionState::Failed
        },
        snapshot: None,
        recovery_ref: None,
        conflicting_paths: Vec::new(),
        activity_ids: Vec::new(),
        failure: Some(NativeNamedSnapshotFailure { kind }),
    }
}

fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

fn native_path_bytes(path: &Path) -> Vec<u8> {
    devmil_git::native_bytes::path_to_bytes(path)
}

/// A named snapshot restore stops at conflicts; continuing keeps the restored changes,
/// aborting puts back the worktree it recorded before the restore.
pub(crate) struct SnapshotRestore;

pub(crate) static SNAPSHOT_RESTORE: SnapshotRestore = SnapshotRestore;

impl crate::interrupted::InterruptedOperation for SnapshotRestore {
    fn kind(&self) -> crate::conflict::NativeConflictOperationKind {
        crate::conflict::NativeConflictOperationKind::Snapshot
    }

    fn offers(&self, action: crate::conflict::NativeConflictSequencerAction) -> bool {
        action != crate::conflict::NativeConflictSequencerAction::Skip
    }

    fn active(&self, common_git_dir: &Path) -> bool {
        active_restore(common_git_dir).is_some()
    }

    fn resume(
        &self,
        interruption: &crate::interrupted::Interruption<'_>,
        action: crate::conflict::NativeConflictSequencerAction,
        _message: Option<&str>,
    ) -> crate::conflict::NativeConflictContinuationResult {
        let (repository, activity, worktree, common_git_dir) = (
            interruption.repository,
            interruption.activity,
            interruption.worktree,
            interruption.common_git_dir,
        );

        if action == NativeConflictSequencerAction::Continue {
            if !crate::named_snapshot::finish_active_restore(common_git_dir) {
                return crate::conflict::continuation_failure(NativeConflictFailureKind::Write);
            }
            crate::conflict::reload(repository);
            return NativeConflictContinuationResult {
                state: NativeConflictContinuationState::Completed,
                activity_ids: Vec::new(),
                failure: None,
            };
        }
        let Some(recovery_ref) = crate::named_snapshot::active_restore(common_git_dir) else {
            return crate::conflict::continuation_failure(
                NativeConflictFailureKind::NoActiveOperation,
            );
        };
        let cancellation = AtomicBool::new(false);
        let Ok(lease) = repository.begin_mutation_with_cancellation(&cancellation) else {
            return crate::conflict::continuation_failure(NativeConflictFailureKind::Git);
        };
        let sink = activity.sink();
        let mut activity_ids = Vec::new();
        let mut succeeded = true;
        let mut commands = vec![vec![
            "reset".to_owned(),
            "--hard".to_owned(),
            "HEAD".to_owned(),
        ]];
        if recovery_ref != "-" {
            commands.push(vec![
                "stash".to_owned(),
                "apply".to_owned(),
                "--index".to_owned(),
                recovery_ref,
            ]);
        }
        for arguments in commands {
            let id =
                crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
            activity_ids.push(id.get().to_string());
            let command = GitProcessCommand::git(repository.git_executable())
                .current_dir(worktree)
                .args(arguments.into_iter().map(ProcessArgument::visible))
                .redact_output();
            let mut publish = |event| sink(event);
            let result =
                ActivityGitRunner::run_private(command, id, Some(&cancellation), &mut publish);
            if !matches!(result.activity.status, ActivityStatus::Succeeded { .. }) {
                succeeded = false;
                break;
            }
        }
        drop(lease);
        if succeeded {
            succeeded = crate::named_snapshot::finish_active_restore(common_git_dir);
        }
        crate::conflict::reload(repository);
        let conflicts = repository
            .snapshot()
            .status
            .as_ref()
            .is_some_and(|status| status.entries.iter().any(|entry| entry.is_conflicted()));
        NativeConflictContinuationResult {
            state: crate::conflict::native_continuation_state(if succeeded {
                MutationState::Aborted
            } else if conflicts {
                MutationState::Conflict
            } else {
                MutationState::Failed
            }),
            activity_ids,
            failure: (!succeeded && !conflicts).then_some(NativeConflictFailure {
                kind: NativeConflictFailureKind::Git,
            }),
        }
    }
}

crate::family_failures!(NativeNamedSnapshotFailureKind, "namedSnapshot", {
    InvalidRequest => InvalidRequest,
    NothingToCapture => Precondition,
    Missing => NotFound,
    Corrupt => Read,
    DirtyConflict => Precondition,
    ActiveOperation => Precondition,
    Stale => Stale,
    Conflict => Conflict,
    Canceled => Canceled,
    TooLarge => TooLarge,
    Read => Read,
    Write => Write,
    Git => Git,
});

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retention_keeps_the_newest_sixty_four_entries() {
        let mut entries = (1..=65)
            .rev()
            .map(|id| StoredSnapshot {
                id,
                name: format!("snapshot {id}"),
                created_at_unix_ms: id,
                base_ref: Some(b"main".to_vec()),
                base_oid: "a".repeat(40),
                object_id: "b".repeat(40),
                staged_count: 0,
                unstaged_count: 1,
                untracked_count: 0,
                includes_untracked: false,
                keeps_index: false,
            })
            .collect::<Vec<_>>();
        let expired = enforce_retention(&mut entries);
        assert_eq!(entries.len(), MAX_ENTRIES);
        assert_eq!(entries.first().map(|entry| entry.id), Some(65));
        assert_eq!(entries.last().map(|entry| entry.id), Some(2));
        assert_eq!(
            expired.iter().map(|entry| entry.id).collect::<Vec<_>>(),
            [1]
        );
    }
}

#[cfg(test)]
mod outcome_tests {
    use super::*;

    #[test]
    fn an_uncertain_snapshot_operation_stays_uncertain() {
        assert_eq!(
            native_state(MutationState::OutcomeUncertain),
            NativeNamedSnapshotExecutionState::OutcomeUncertain
        );
        assert_eq!(
            native_state(
                MutationOutcome::<()>::from_terminal(MutationTerminalState::OutcomeUncertain).state
            ),
            NativeNamedSnapshotExecutionState::OutcomeUncertain
        );
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{conflicts::*, session::*, snapshots::*};

    use crate::conflict::{
        NativeConflictContinuationState, NativeConflictOperationKind, NativeConflictSequencerAction,
    };

    use crate::named_snapshot::{
        NativeNamedSnapshotExecutionState, NativeNamedSnapshotFailureKind, NativeNamedSnapshotState,
    };

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[test]
    fn named_snapshot_round_trips_index_worktree_untracked_and_retains_recovery() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        fs::write(fixture.0.join("tracked.txt"), b"staged\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        fs::write(fixture.0.join("tracked.txt"), b"unstaged\n").unwrap();
        fs::write(fixture.0.join("untracked.bin"), b"snapshot bytes\n").unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_220,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let captured = repository_session_named_snapshot_create(
            session.session_id,
            session.generation,
            "try parser rewrite".to_owned(),
            true,
            false,
        );
        assert_eq!(captured.state, NativeNamedSnapshotExecutionState::Completed);
        let saved = captured.snapshot.unwrap();
        assert_eq!(saved.staged_count, 1);
        assert_eq!(saved.unstaged_count, 1);
        assert_eq!(saved.untracked_count, 1);
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"unstaged\n"
        );
        assert_eq!(
            transfer_git(&fixture.0, &["show", ":tracked.txt"]),
            b"staged\n"
        );
        assert_eq!(
            fs::read(fixture.0.join("untracked.bin")).unwrap(),
            b"snapshot bytes\n"
        );
        let listed =
            repository_session_named_snapshots(session.session_id, session.generation, 0, 10);
        assert_eq!(listed.total, 1);
        assert_eq!(listed.entries[0].state, NativeNamedSnapshotState::Ready);

        transfer_git(&fixture.0, &["reset", "--hard", "HEAD"]);
        fs::remove_file(fixture.0.join("untracked.bin")).unwrap();
        fs::write(fixture.0.join("tracked.txt"), b"new idea\n").unwrap();
        fs::write(fixture.0.join("other.bin"), b"retain as recovery\n").unwrap();
        refresh_session(&session);
        let preview = repository_session_named_snapshot_restore_preview(
            session.session_id,
            session.generation,
            saved.id,
        )
        .preview
        .unwrap();
        assert!(preview.replaces_index);
        assert!(preview.replaces_worktree);
        let restored = repository_session_named_snapshot_restore_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert_eq!(restored.state, NativeNamedSnapshotExecutionState::Completed);
        assert!(restored.recovery_ref.is_some());
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"unstaged\n"
        );
        assert_eq!(
            transfer_git(&fixture.0, &["show", ":tracked.txt"]),
            b"staged\n"
        );
        assert_eq!(
            fs::read(fixture.0.join("untracked.bin")).unwrap(),
            b"snapshot bytes\n"
        );
        assert!(!fixture.0.join("other.bin").exists());
        // The replaced changes wait in the stash list.
        assert!(
            String::from_utf8(transfer_git(&fixture.0, &["stash", "list"]))
                .unwrap()
                .contains("Changes before restoring a snapshot")
        );
        assert_eq!(
            transfer_git(&fixture.0, &["show", "stash@{0}:tracked.txt"]),
            b"new idea\n"
        );

        let branched = repository_session_named_snapshot_branch(
            session.session_id,
            session.generation,
            saved.id,
            b"snapshot-idea".to_vec(),
        );
        assert_eq!(branched.state, NativeNamedSnapshotExecutionState::Completed);
        assert_eq!(
            transfer_git(&fixture.0, &["show", "snapshot-idea:tracked.txt"]),
            b"unstaged\n"
        );

        let raced = repository_session_named_snapshot_create(
            session.session_id,
            session.generation,
            "delete race".to_owned(),
            true,
            false,
        )
        .snapshot
        .unwrap();
        let raced_preview = repository_session_named_snapshot_restore_preview(
            session.session_id,
            session.generation,
            raced.id,
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_named_snapshot_delete(
                session.session_id,
                session.generation,
                raced.id,
            )
            .state,
            NativeNamedSnapshotExecutionState::Completed
        );
        assert_eq!(
            repository_session_named_snapshot_restore_execute(
                session.session_id,
                session.generation,
                raced_preview.token,
            )
            .state,
            NativeNamedSnapshotExecutionState::Stale
        );

        let deleted = repository_session_named_snapshot_delete(
            session.session_id,
            session.generation,
            saved.id,
        );
        assert_eq!(deleted.state, NativeNamedSnapshotExecutionState::Completed);
        assert_eq!(
            repository_session_named_snapshots(session.session_id, session.generation, 0, 10,)
                .total,
            0
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn named_snapshot_restore_conflict_continues_and_aborts_after_restart() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        fs::write(fixture.0.join("tracked.txt"), b"snapshot version\n").unwrap();
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
        let saved = repository_session_named_snapshot_create(
            session.session_id,
            session.generation,
            "conflicting idea".to_owned(),
            false,
            false,
        )
        .snapshot
        .unwrap();
        transfer_git(&fixture.0, &["reset", "--hard", "HEAD"]);
        fs::write(fixture.0.join("tracked.txt"), b"new head version\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "move head"]);
        refresh_session(&session);
        let preview = repository_session_named_snapshot_restore_preview(
            session.session_id,
            session.generation,
            saved.id,
        )
        .preview
        .unwrap();
        let conflicted = repository_session_named_snapshot_restore_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert_eq!(
            conflicted.state,
            NativeNamedSnapshotExecutionState::Conflict
        );
        assert_eq!(conflicted.conflicting_paths, [b"tracked.txt".to_vec()]);
        assert!(repository_session_close(session.session_id, session.generation).accepted);

        let reopened = repository_session_open_with_options(
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
        wait_for_ready(&reopened);
        let conflicts = repository_session_conflicts(reopened.session_id, reopened.generation)
            .snapshot
            .unwrap();
        assert_eq!(conflicts.operation, NativeConflictOperationKind::Snapshot);
        let file = conflicts.files[0].clone();
        let resolution = repository_session_conflict_save_result(
            reopened.session_id,
            reopened.generation,
            file.path,
            file.fingerprint,
            b"snapshot version\n".to_vec(),
        );
        assert!(resolution.snapshot.unwrap().files.is_empty());
        assert_eq!(
            repository_session_conflict_continue(
                reopened.session_id,
                reopened.generation,
                NativeConflictSequencerAction::Continue,
            )
            .state,
            NativeConflictContinuationState::Completed
        );
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"snapshot version\n"
        );
        transfer_git(&fixture.0, &["reset", "--hard", "HEAD"]);
        // Keep the repository snapshot deliberately one change behind disk.
        // Restore execution must re-read clean/dirty truth before deciding
        // whether a recovery stash is necessary.
        let retry = repository_session_named_snapshot_restore_preview(
            reopened.session_id,
            reopened.generation,
            saved.id,
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_named_snapshot_restore_execute(
                reopened.session_id,
                reopened.generation,
                retry.token,
            )
            .state,
            NativeNamedSnapshotExecutionState::Conflict
        );
        assert_eq!(
            repository_session_conflict_continue(
                reopened.session_id,
                reopened.generation,
                NativeConflictSequencerAction::Abort,
            )
            .state,
            NativeConflictContinuationState::Aborted
        );
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"new head version\n"
        );
        assert!(repository_session_close(reopened.session_id, reopened.generation).accepted);
    }

    #[test]
    fn named_snapshot_store_failure_rolls_back_hidden_ref_and_exact_worktree() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        fs::write(fixture.0.join("tracked.txt"), b"staged\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        fs::write(fixture.0.join("tracked.txt"), b"unstaged\n").unwrap();
        fs::write(fixture.0.join("untracked.bin"), b"untracked\n").unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_214,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        crate::named_snapshot::fail_next_store_write();
        let result = repository_session_named_snapshot_create(
            session.session_id,
            session.generation,
            "storage failure".to_owned(),
            true,
            false,
        );
        assert_eq!(result.state, NativeNamedSnapshotExecutionState::Failed);
        assert_eq!(
            result.failure.unwrap().kind,
            NativeNamedSnapshotFailureKind::Write
        );
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"unstaged\n"
        );
        assert_eq!(
            transfer_git(&fixture.0, &["show", ":tracked.txt"]),
            b"staged\n"
        );
        assert_eq!(
            fs::read(fixture.0.join("untracked.bin")).unwrap(),
            b"untracked\n"
        );
        assert!(transfer_git(&fixture.0, &["stash", "list"]).is_empty());
        assert!(transfer_git(&fixture.0, &["for-each-ref", "refs/gitlama/snapshots"]).is_empty());
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }
}
