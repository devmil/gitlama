//! Stable history mutations and isolated conflict prediction.
pub use gitlama_contract::history_operation::*;

use crate::activity::ActivityStore;
use crate::conflict::{
    NativeConflictFailureKind, NativeConflictOperationKind, NativeConflictSequencerAction,
};
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::interrupted::{InterruptedOperation, Interruption, SequencerStep};
use crate::operations::ExecutionFailure;
use crate::preview_store::PreviewStore;
use devmil_git::activity::ActivityStatus;
use devmil_git::loading::conflict_prediction::{
    ConflictPredictionKind, ConflictPredictionTarget, PredictionCompleteness,
};
use devmil_git::loading::refs::RefsSectionData;
use devmil_git::merge::{
    cherry_pick_arguments, merge_arguments_with_mode, revert_many_arguments_with_mode, MergeMode,
};
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::status::{BranchHead, OperationKind, WorkingTreeState};
use devmil_git::types::{ObjectId, RepositoryRelativePath};
use devmil_git::{Repository, RepositorySnapshot};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

type EventSink = Arc<dyn Fn(devmil_git::activity::ActivityEvent) + Send + Sync>;

const PREVIEW_CAPACITY_PER_SESSION: usize = 8;
const MAX_TARGETS: usize = 256;

const fn native_state(state: MutationState) -> NativeHistoryMutationExecutionState {
    match state {
        MutationState::Completed | MutationState::Aborted => {
            NativeHistoryMutationExecutionState::Completed
        }
        MutationState::AlreadyContained => NativeHistoryMutationExecutionState::AlreadyContained,
        MutationState::ReconciledWithWarning => {
            NativeHistoryMutationExecutionState::ReconciledWithWarning
        }
        MutationState::Conflict => NativeHistoryMutationExecutionState::Conflict,
        MutationState::Interrupted | MutationState::EditStop | MutationState::Partial => {
            NativeHistoryMutationExecutionState::Interrupted
        }
        MutationState::Stale => NativeHistoryMutationExecutionState::Stale,
        MutationState::Canceled | MutationState::Failed => {
            NativeHistoryMutationExecutionState::Failed
        }
        MutationState::OutcomeUncertain => NativeHistoryMutationExecutionState::OutcomeUncertain,
    }
}

type HistoryFacts = crate::domain::facts::BranchFacts;

#[derive(Clone)]
struct Plan {
    request: NativeHistoryMutationRequest,
    targets: Vec<ObjectId>,
    arguments: Vec<String>,
    facts: HistoryFacts,
    already_contained: bool,
}

struct Registry {
    previews: PreviewStore<Plan>,
    next_prediction_token: u64,
    predictions: HashMap<(u64, u64), Arc<AtomicBool>>,
}

static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();
static NEXT_APPLY_ONLY_RUNTIME: AtomicU64 = AtomicU64::new(1);

fn registry() -> &'static Mutex<Registry> {
    REGISTRY.get_or_init(|| {
        Mutex::new(Registry {
            previews: PreviewStore::new(PREVIEW_CAPACITY_PER_SESSION),
            next_prediction_token: 0,
            predictions: HashMap::new(),
        })
    })
}

fn lock_registry() -> std::sync::MutexGuard<'static, Registry> {
    registry()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

pub(crate) fn preview(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    request: NativeHistoryMutationRequest,
) -> NativeHistoryMutationPreviewResult {
    let plan = match build_plan(
        repository,
        repository.snapshot().as_ref(),
        activity,
        request,
    ) {
        Ok(value) => value,
        Err(kind) => return preview_failure(kind),
    };
    let token = lock_registry().previews.issue(session_id, plan.clone());
    NativeHistoryMutationPreviewResult {
        preview: Some(NativeHistoryMutationPreview {
            token,
            kind: plan.request.kind,
            arguments: plan.arguments.clone(),
            targets: plan
                .targets
                .iter()
                .map(|target| target.as_str().to_owned())
                .collect(),
            source_name: plan.request.source_name.clone(),
            current_branch: plan.facts.branch_name.clone(),
            current_head: plan.facts.head.as_str().to_owned(),
            published_history: plan.facts.published,
            already_contained: plan.already_contained,
            no_commit: plan.request.no_commit,
        }),
        failure: None,
    }
}

pub(crate) fn execute(
    session_id: u64,
    token: u64,
    repository: &Repository,
    activity: &ActivityStore,
) -> NativeHistoryMutationExecutionResult {
    let (plan, cancellation) = {
        let mut registry = lock_registry();
        let Some(owned) = registry.previews.get_mut(session_id, token) else {
            return execution_failure(NativeHistoryMutationFailureKind::InvalidRequest);
        };
        if owned.running {
            return execution_failure(NativeHistoryMutationFailureKind::InvalidRequest);
        }
        owned.running = true;
        owned.cancellation.store(false, Ordering::Release);
        (owned.value.clone(), Arc::clone(&owned.cancellation))
    };
    let Some(current) = history_facts(repository.snapshot().as_ref()) else {
        finish(session_id, token);
        return execution_failure(NativeHistoryMutationFailureKind::Read);
    };
    if current != plan.facts {
        finish(session_id, token);
        return NativeHistoryMutationExecutionResult {
            state: NativeHistoryMutationExecutionState::Stale,
            failure: Some(NativeHistoryMutationFailure {
                kind: NativeHistoryMutationFailureKind::Stale,
            }),
            activity_ids: Vec::new(),
            conflicting_paths: Vec::new(),
            sequencer: None,
        };
    }
    if plan.already_contained {
        finish(session_id, token);
        return NativeHistoryMutationExecutionResult {
            state: NativeHistoryMutationExecutionState::AlreadyContained,
            failure: None,
            activity_ids: Vec::new(),
            conflicting_paths: Vec::new(),
            sequencer: None,
        };
    }

    let sink = activity.sink();
    let activity_ids = Mutex::new(Vec::new());
    let interruption = Mutex::new(None);
    let operation_failure = Mutex::new(None);
    let git_started = AtomicBool::new(false);
    let outcome = crate::operations::coordinate_leased_mutation(
        repository,
        cancellation.as_ref(),
        |cancellation, lease| {
            // Watchers may not have observed an external edit since the preview.
            // Read fresh status under the mutation lease before Git runs.
            if let Err(kind) = validate_live_preconditions(&plan, lease, cancellation) {
                *operation_failure.lock().unwrap() = Some(kind);
                return Err(ExecutionFailure::Definite);
            }
            // Save apply-only intent before Git can leave a conflict or the app exits.
            if plan.request.no_commit && persist_apply_only(&plan).is_err() {
                *operation_failure.lock().unwrap() = Some(NativeHistoryMutationFailureKind::Read);
                return Err(ExecutionFailure::Definite);
            }
            let id =
                crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
            activity_ids.lock().unwrap().push(id.get());
            let command = GitProcessCommand::git(repository.git_executable())
                .current_dir(&plan.facts.worktree)
                .args(plan.arguments.iter().cloned().map(ProcessArgument::visible))
                .env("GIT_EDITOR", "true")
                .expect("constant environment is valid")
                .redact_output();
            let mut publish = |event| sink(event);
            git_started.store(true, Ordering::Release);
            let result =
                ActivityGitRunner::run_private(command, id, Some(cancellation), &mut publish);
            match result.activity.status {
                ActivityStatus::Succeeded { .. } => Ok(()),
                ActivityStatus::Canceled { .. } => {
                    *operation_failure.lock().unwrap() =
                        Some(NativeHistoryMutationFailureKind::Canceled);
                    Err(ExecutionFailure::Canceled)
                }
                ActivityStatus::Running
                | ActivityStatus::Failed { .. }
                | ActivityStatus::TimedOut { .. }
                | ActivityStatus::LaunchError { .. } => {
                    if let Some(state) =
                        inspect_interruption(&plan, cancellation, &sink, &activity_ids)
                    {
                        *interruption.lock().unwrap() = Some(state);
                        Ok(())
                    } else {
                        *operation_failure.lock().unwrap() =
                            Some(NativeHistoryMutationFailureKind::Failed);
                        Err(ExecutionFailure::Definite)
                    }
                }
            }
        },
    );
    finish(session_id, token);
    let mut interruption = *interruption.lock().unwrap();
    if !outcome.committed() {
        // Cancellation and nonzero exits can leave a sequencer or staged changes.
        // Inspect without the canceled token, then reconcile before offering another action.
        let reconcile = AtomicBool::new(false);
        if git_started.load(Ordering::Acquire) && interruption.is_none() {
            interruption = inspect_interruption(&plan, &reconcile, &sink, &activity_ids);
        }
        if let Ok(ticket) = repository.reload() {
            let _ = ticket.recv_timeout(Duration::from_secs(30));
        }
    }
    if interruption.is_none() && plan.request.no_commit && git_started.load(Ordering::Acquire) {
        discard_apply_only(
            &plan.facts.common_git_dir,
            &plan.facts.git_dir,
            plan.request.kind,
        );
    }
    let conflicting_paths = repository
        .snapshot()
        .status
        .as_ref()
        .map(|status| {
            status
                .entries
                .iter()
                .filter(|entry| entry.is_conflicted())
                .map(|entry| native_path(entry.path()))
                .collect()
        })
        .unwrap_or_default();
    let mut result = MutationOutcome::from_terminal(outcome)
        .with_failure(operation_failure.into_inner().unwrap());
    if result.failure == Some(NativeHistoryMutationFailureKind::Stale) {
        result.state = MutationState::Stale;
    } else if let Some((_, conflicted)) = interruption {
        // The repository's own state decides: the operation ran and stopped.
        result.state = if conflicted {
            MutationState::Conflict
        } else {
            MutationState::Interrupted
        };
    }
    NativeHistoryMutationExecutionResult {
        state: native_state(result.state),
        failure: result
            .failure
            .map(|kind| NativeHistoryMutationFailure { kind }),
        activity_ids: activity_ids
            .into_inner()
            .unwrap()
            .into_iter()
            .map(|value| value.to_string())
            .collect(),
        conflicting_paths,
        sequencer: interruption.map(|(kind, _)| kind),
    }
}

/// Forgets the apply-only intent of a finished or abandoned `operation`.
pub(crate) fn discard_apply_only(
    common_git_dir: &Path,
    git_dir: &Path,
    operation: NativeHistoryMutationKind,
) {
    if let Some(runtime) = find_apply_only(common_git_dir, git_dir, operation) {
        let _ = fs::remove_dir_all(runtime);
    }
}

fn persist_apply_only(plan: &Plan) -> std::io::Result<()> {
    let root =
        crate::private_store::PrivateDir::repository(&plan.facts.common_git_dir, &["sequencer"])?;
    let sequence = NEXT_APPLY_ONLY_RUNTIME.fetch_add(1, Ordering::Relaxed);
    let runtime = root.child(&format!(
        "{}-{}-{sequence}",
        crate::clock::unix_millis(),
        std::process::id()
    ))?;
    runtime.write_new(
        "git-dir",
        &devmil_git::native_bytes::path_to_bytes(&plan.facts.git_dir),
    )?;
    runtime.write_new("before-head", plan.facts.head.as_str().as_bytes())?;
    runtime.write_new("kind", history_kind_name(plan.request.kind).as_bytes())?;
    runtime.write_new("target", plan.request.targets[0].as_bytes())?;
    runtime.write_new("no-commit", b"1")?;
    Ok(())
}

pub(crate) fn pending_revert_no_commit(
    common_git_dir: &Path,
    git_dir: &Path,
    head: Option<&ObjectId>,
) -> Result<bool, ()> {
    let Some(runtime) = find_apply_only(common_git_dir, git_dir, NativeHistoryMutationKind::Revert)
    else {
        return Ok(false);
    };
    if fs::read(runtime.join("no-commit")).ok().as_deref() != Some(b"1") {
        return Ok(false);
    }
    // An owned apply-only operation must never fall back to a committing continuation.
    let head = head.ok_or(())?;
    let target = fs::read(runtime.join("target")).map_err(|_| ())?;
    let reverted =
        devmil_git::status::operation_heads(git_dir, OperationKind::Revert).map_err(|_| ())?;
    if git_dir.join("sequencer").exists()
        || fs::read(runtime.join("before-head")).ok().as_deref() != Some(head.as_str().as_bytes())
        || reverted.len() != 1
        || reverted[0].as_str().as_bytes() != target
    {
        return Err(());
    }
    Ok(true)
}

fn find_apply_only(
    common_git_dir: &Path,
    git_dir: &Path,
    operation: NativeHistoryMutationKind,
) -> Option<PathBuf> {
    let expected_git_dir = devmil_git::native_bytes::path_to_bytes(git_dir);
    let expected_git_dir = expected_git_dir.as_slice();
    let expected_kind = history_kind_name(operation).as_bytes();
    fs::read_dir(common_git_dir.join("gitlama/sequencer"))
        .ok()?
        .filter_map(Result::ok)
        .take(64)
        .filter_map(|entry| {
            let path = entry.path();
            (entry.file_type().ok()?.is_dir()
                && fs::read(path.join("git-dir")).ok()?.as_slice() == expected_git_dir
                && fs::read(path.join("kind")).ok()?.as_slice() == expected_kind)
                .then_some(path)
        })
        .max_by_key(|path| fs::metadata(path).and_then(|value| value.modified()).ok())
}

const fn history_kind_name(kind: NativeHistoryMutationKind) -> &'static str {
    match kind {
        NativeHistoryMutationKind::Merge => "merge",
        NativeHistoryMutationKind::CherryPick => "cherry-pick",
        NativeHistoryMutationKind::Revert => "revert",
    }
}

pub(crate) fn begin_prediction(session_id: u64) -> NativeConflictPredictionStartResult {
    let mut registry = lock_registry();
    registry.next_prediction_token = registry.next_prediction_token.saturating_add(1).max(1);
    let token = registry.next_prediction_token;
    registry
        .predictions
        .insert((session_id, token), Arc::new(AtomicBool::new(false)));
    NativeConflictPredictionStartResult {
        token: Some(token),
        failure: None,
    }
}

pub(crate) fn predict(
    session_id: u64,
    token: u64,
    repository: &Repository,
    kind: NativeConflictPredictionKind,
    target: String,
) -> NativeConflictPredictionResult {
    let cancellation = {
        let registry = lock_registry();
        registry.predictions.get(&(session_id, token)).cloned()
    };
    let Some(cancellation) = cancellation else {
        return prediction_failure(
            kind,
            target,
            NativeHistoryMutationFailureKind::InvalidRequest,
        );
    };
    if cancellation.load(Ordering::Acquire) {
        finish_prediction(session_id, token);
        return prediction_failure(kind, target, NativeHistoryMutationFailureKind::Canceled);
    }
    let target_id = match ObjectId::parse(target.clone()) {
        Ok(value) => value,
        Err(_) => {
            finish_prediction(session_id, token);
            return prediction_failure(
                kind,
                target,
                NativeHistoryMutationFailureKind::InvalidRequest,
            );
        }
    };
    let shared_kind = match kind {
        NativeConflictPredictionKind::Merge => ConflictPredictionKind::Merge,
        NativeConflictPredictionKind::Rebase => ConflictPredictionKind::Rebase,
    };
    let ticket = match repository
        .predict_conflicts(shared_kind, ConflictPredictionTarget::Commit(target_id))
    {
        Ok(value) => value,
        Err(error) => {
            finish_prediction(session_id, token);
            return prediction_failure(kind, target, map_repository_failure(error.kind));
        }
    };
    let deadline = Instant::now() + Duration::from_secs(35);
    let result = loop {
        if cancellation.load(Ordering::Acquire) {
            drop(ticket);
            finish_prediction(session_id, token);
            return prediction_failure(kind, target, NativeHistoryMutationFailureKind::Canceled);
        }
        if let Some(result) = ticket.recv_timeout(Duration::from_millis(20)) {
            break result;
        }
        if Instant::now() >= deadline {
            drop(ticket);
            finish_prediction(session_id, token);
            return prediction_failure(kind, target, NativeHistoryMutationFailureKind::Read);
        }
    };
    finish_prediction(session_id, token);
    match result {
        Ok(value) => NativeConflictPredictionResult {
            kind,
            target,
            conflicting_paths: value.conflicting_paths.iter().map(native_path).collect(),
            analyzed_commits: value.analyzed_commits.try_into().unwrap_or(u32::MAX),
            total_commits: value.total_commits.try_into().unwrap_or(u32::MAX),
            complete: matches!(value.completeness, PredictionCompleteness::Complete),
            activity_ids: value
                .activities
                .iter()
                .map(|id| id.get().to_string())
                .collect(),
            failure: None,
        },
        Err(error) => prediction_failure(kind, target, map_repository_failure(error.kind)),
    }
}

pub(crate) fn cancel_prediction(session_id: u64, token: u64) -> bool {
    let registry = lock_registry();
    let Some(cancellation) = registry.predictions.get(&(session_id, token)) else {
        return false;
    };
    cancellation.store(true, Ordering::Release);
    true
}

fn finish_prediction(session_id: u64, token: u64) {
    lock_registry().predictions.remove(&(session_id, token));
}

pub(crate) fn cancel(session_id: u64, token: u64) -> bool {
    lock_registry().previews.cancel(session_id, token)
}

pub(crate) fn dismiss_session(session_id: u64) {
    let mut registry = lock_registry();
    registry.previews.dismiss_session(session_id);
    registry
        .predictions
        .retain(|(owned_session, _), cancellation| {
            if *owned_session == session_id {
                cancellation.store(true, Ordering::Release);
                false
            } else {
                true
            }
        });
}

fn build_plan(
    repository: &Repository,
    snapshot: &RepositorySnapshot,
    activity: &ActivityStore,
    request: NativeHistoryMutationRequest,
) -> Result<Plan, NativeHistoryMutationFailureKind> {
    if request.targets.is_empty() || request.targets.len() > MAX_TARGETS {
        return Err(NativeHistoryMutationFailureKind::InvalidRequest);
    }
    if request.no_commit
        && (request.kind != NativeHistoryMutationKind::Revert || request.targets.len() != 1)
    {
        return Err(NativeHistoryMutationFailureKind::InvalidRequest);
    }
    if request.source_name.as_ref().is_some_and(|name| {
        name.is_empty() || name.len() > 512 || name.contains(&0) || name.contains(&b'\n')
    }) {
        return Err(NativeHistoryMutationFailureKind::InvalidRequest);
    }
    if request.kind == NativeHistoryMutationKind::Merge && request.targets.len() != 1 {
        return Err(NativeHistoryMutationFailureKind::InvalidRequest);
    }
    let targets = request
        .targets
        .iter()
        .cloned()
        .map(ObjectId::parse)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| NativeHistoryMutationFailureKind::InvalidRequest)?;
    let facts = history_facts(snapshot).ok_or_else(|| {
        let detached = snapshot
            .status
            .as_ref()
            .is_some_and(|status| matches!(status.branch.head, BranchHead::Detached));
        if detached {
            NativeHistoryMutationFailureKind::DetachedHead
        } else {
            NativeHistoryMutationFailureKind::Read
        }
    })?;
    if request.kind == NativeHistoryMutationKind::Merge {
        if let Some(source_name) = request.source_name.as_ref() {
            let matches_target = snapshot.refs.iter().any(|section| match section {
                RefsSectionData::Branches { rows, .. } => rows.iter().any(|row| {
                    row.target == targets[0]
                        && row
                            .id
                            .as_bytes()
                            .strip_prefix(b"refs/heads/")
                            .is_some_and(|name| name == source_name)
                }),
                RefsSectionData::Remotes { references, .. } => references.iter().any(|row| {
                    row.target == targets[0]
                        && row
                            .id
                            .as_bytes()
                            .strip_prefix(b"refs/remotes/")
                            .is_some_and(|name| name == source_name)
                }),
                _ => false,
            });
            if !matches_target {
                return Err(NativeHistoryMutationFailureKind::Stale);
            }
        }
    }
    let status = snapshot
        .status
        .as_ref()
        .ok_or(NativeHistoryMutationFailureKind::Read)?;
    if status.working_tree != WorkingTreeState::Clean {
        return Err(NativeHistoryMutationFailureKind::DirtyWorktree);
    }
    if !status.operations.is_empty() {
        return Err(NativeHistoryMutationFailureKind::ActiveOperation);
    }
    if facts.published
        && matches!(request.kind, NativeHistoryMutationKind::CherryPick)
        && !request.acknowledge_published_history
    {
        return Err(NativeHistoryMutationFailureKind::PublicationConfirmationRequired);
    }
    let arguments = match request.kind {
        NativeHistoryMutationKind::Merge => merge_arguments_with_mode(
            targets[0].as_str(),
            match request.merge_mode {
                NativeHistoryMergeMode::FastForwardIfPossible => MergeMode::FastForwardIfPossible,
                NativeHistoryMergeMode::FastForwardOnly => MergeMode::FastForwardOnly,
                NativeHistoryMergeMode::NoFastForward => MergeMode::NoFastForward,
            },
        ),
        NativeHistoryMutationKind::CherryPick => cherry_pick_arguments(&targets),
        NativeHistoryMutationKind::Revert => {
            revert_many_arguments_with_mode(&targets, request.no_commit)
        }
    };
    if request.kind == NativeHistoryMutationKind::Revert {
        let details = repository
            .commit_details(targets.clone())
            .map_err(|_| NativeHistoryMutationFailureKind::Read)?
            .recv_timeout(Duration::from_secs(30))
            .ok_or(NativeHistoryMutationFailureKind::Read)?
            .map_err(|_| NativeHistoryMutationFailureKind::Read)?;
        if details.iter().any(|detail| detail.parents.len() > 1) {
            return Err(NativeHistoryMutationFailureKind::MergeCommit);
        }
    }
    let already_contained = request.kind == NativeHistoryMutationKind::Merge
        && is_ancestor(&facts.worktree, &targets[0], &facts.head, activity);
    Ok(Plan {
        request,
        targets,
        arguments,
        facts,
        already_contained,
    })
}

fn validate_live_preconditions(
    plan: &Plan,
    lease: &devmil_git::model::RepositoryMutation,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
) -> Result<(), NativeHistoryMutationFailureKind> {
    // Read under the lease, bypassing cached snapshots, without refreshing the user's index.
    let status = lease
        .fresh_status(Some(cancellation))
        .map_err(|_| NativeHistoryMutationFailureKind::Read)?
        .ok_or(NativeHistoryMutationFailureKind::Read)?;
    if status.branch.oid.as_ref() != Some(&plan.facts.head)
        || !matches!(&status.branch.head, BranchHead::Attached(name) if name.as_bytes() == plan.facts.branch_name)
    {
        return Err(NativeHistoryMutationFailureKind::Stale);
    }
    if !status.operations.is_empty() {
        return Err(NativeHistoryMutationFailureKind::ActiveOperation);
    }
    if status.working_tree != WorkingTreeState::Clean {
        return Err(NativeHistoryMutationFailureKind::DirtyWorktree);
    }
    Ok(())
}

fn history_facts(snapshot: &RepositorySnapshot) -> Option<HistoryFacts> {
    crate::domain::facts::BranchFacts::capture(snapshot)
}

fn is_ancestor(
    worktree: &Path,
    ancestor: &ObjectId,
    head: &ObjectId,
    activity: &ActivityStore,
) -> bool {
    crate::git_probe::run_published_probe(activity, |executor| {
        devmil_git::probes::is_ancestor(
            std::ffi::OsStr::new("git"),
            worktree,
            ancestor,
            head,
            executor,
        )
    })
    .unwrap_or(false)
}

fn inspect_interruption(
    plan: &Plan,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &Mutex<Vec<u64>>,
) -> Option<(NativeHistoryMutationKind, bool)> {
    let operation = match plan.request.kind {
        NativeHistoryMutationKind::Merge => OperationKind::Merge,
        NativeHistoryMutationKind::CherryPick => OperationKind::CherryPick,
        NativeHistoryMutationKind::Revert => OperationKind::Revert,
    };
    if !crate::branch_facts::operation_in_progress(&plan.facts.git_dir, operation) {
        return None;
    }
    let conflicted = has_unmerged_paths(&plan.facts.worktree, cancellation, sink, activity_ids);
    Some((plan.request.kind, conflicted))
}

fn has_unmerged_paths(
    worktree: &Path,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &Mutex<Vec<u64>>,
) -> bool {
    let publish = |event| sink(event);
    let mut record = |id: devmil_git::activity::ActivityId| {
        activity_ids
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(id.get());
    };
    devmil_git::probes::unmerged_paths(
        std::ffi::OsStr::new("git"),
        worktree,
        &mut crate::git_probe::ProbeExecutor::publishing(Some(cancellation), &publish, &mut record),
    )
    .is_ok_and(|paths| !paths.is_empty())
}

fn native_path(path: &RepositoryRelativePath) -> Vec<u8> {
    devmil_git::native_bytes::path_to_bytes(path.as_path())
}

fn map_repository_failure(
    kind: devmil_git::RepositoryErrorKind,
) -> NativeHistoryMutationFailureKind {
    match kind {
        devmil_git::RepositoryErrorKind::Canceled => NativeHistoryMutationFailureKind::Canceled,
        devmil_git::RepositoryErrorKind::InvalidOptions => {
            NativeHistoryMutationFailureKind::InvalidRequest
        }
        _ => NativeHistoryMutationFailureKind::Read,
    }
}

fn finish(session_id: u64, token: u64) {
    lock_registry().previews.finish(session_id, token);
}

fn preview_failure(kind: NativeHistoryMutationFailureKind) -> NativeHistoryMutationPreviewResult {
    NativeHistoryMutationPreviewResult {
        preview: None,
        failure: Some(NativeHistoryMutationFailure { kind }),
    }
}

fn execution_failure(
    kind: NativeHistoryMutationFailureKind,
) -> NativeHistoryMutationExecutionResult {
    NativeHistoryMutationExecutionResult {
        state: NativeHistoryMutationExecutionState::Failed,
        failure: Some(NativeHistoryMutationFailure { kind }),
        activity_ids: Vec::new(),
        conflicting_paths: Vec::new(),
        sequencer: None,
    }
}

fn prediction_failure(
    kind: NativeConflictPredictionKind,
    target: String,
    failure: NativeHistoryMutationFailureKind,
) -> NativeConflictPredictionResult {
    NativeConflictPredictionResult {
        kind,
        target,
        conflicting_paths: Vec::new(),
        analyzed_commits: 0,
        total_commits: 0,
        complete: false,
        activity_ids: Vec::new(),
        failure: Some(NativeHistoryMutationFailure { kind: failure }),
    }
}

crate::family_failures!(NativeHistoryMutationFailureKind, "historyMutation", {
    InvalidRequest => InvalidRequest,
    DirtyWorktree => Precondition,
    DetachedHead => Precondition,
    ActiveOperation => Precondition,
    PublicationConfirmationRequired => Precondition,
    Stale => Stale,
    Canceled => Canceled,
    Failed => Git,
    Read => Read,
    MergeCommit => Precondition,
});

#[cfg(test)]
mod outcome_tests {
    use super::*;

    #[test]
    fn an_uncertain_history_mutation_stays_uncertain() {
        assert_eq!(
            native_state(MutationState::OutcomeUncertain),
            NativeHistoryMutationExecutionState::OutcomeUncertain
        );
        assert_eq!(
            native_state(MutationState::Canceled),
            NativeHistoryMutationExecutionState::Failed
        );
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{conflicts::*, history_mutations::*, session::*};

    use crate::conflict::{
        NativeConflictContinuationState, NativeConflictFailureKind, NativeConflictOperationKind,
        NativeConflictSequencerAction, NativeConflictSideChoice,
    };

    use crate::history_operation::{
        NativeConflictPredictionKind, NativeHistoryMergeMode, NativeHistoryMutationExecutionState,
        NativeHistoryMutationFailureKind, NativeHistoryMutationKind, NativeHistoryMutationRequest,
    };

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[test]
    fn history_mutations_predict_merge_recover_and_preserve_order() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(fixture.0.join("base.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        let base = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("one.txt"), b"one\n").unwrap();
        transfer_git(&fixture.0, &["add", "one.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "one"]);
        let first = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(fixture.0.join("two.txt"), b"two\n").unwrap();
        transfer_git(&fixture.0, &["add", "two.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "two"]);
        let second = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&fixture.0, &["switch", "main"]);
        fs::write(fixture.0.join("main.txt"), b"main\n").unwrap();
        transfer_git(&fixture.0, &["add", "main.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "main"]);
        let before = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_213,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let ref_before = transfer_git(&fixture.0, &["show-ref"]);
        let index_before = fs::read(fixture.0.join(".git/index")).unwrap();
        let prediction_token =
            repository_session_conflict_prediction_begin(session.session_id, session.generation)
                .token
                .unwrap();
        let prediction = repository_session_conflict_prediction(
            session.session_id,
            session.generation,
            prediction_token,
            NativeConflictPredictionKind::Merge,
            second.clone(),
        );
        assert!(prediction.failure.is_none());
        assert!(prediction.complete);
        assert!(prediction.conflicting_paths.is_empty());
        assert_eq!(transfer_git(&fixture.0, &["show-ref"]), ref_before);
        assert_eq!(
            fs::read(fixture.0.join(".git/index")).unwrap(),
            index_before
        );
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim(),
            before
        );

        let canceled_token =
            repository_session_conflict_prediction_begin(session.session_id, session.generation)
                .token
                .unwrap();
        assert!(
            repository_session_conflict_prediction_cancel(
                session.session_id,
                session.generation,
                canceled_token,
            )
            .accepted
        );
        assert_eq!(
            repository_session_conflict_prediction(
                session.session_id,
                session.generation,
                canceled_token,
                NativeConflictPredictionKind::Merge,
                second.clone(),
            )
            .failure
            .unwrap()
            .kind,
            NativeHistoryMutationFailureKind::Canceled
        );

        let merge = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            NativeHistoryMutationRequest {
                kind: NativeHistoryMutationKind::Merge,
                targets: vec![second.clone()],
                source_name: Some(b"topic".to_vec()),
                merge_mode: NativeHistoryMergeMode::NoFastForward,
                acknowledge_published_history: false,
                no_commit: false,
            },
        )
        .preview
        .unwrap();
        assert_eq!(merge.arguments, ["merge", "--no-edit", "--no-ff", &second]);
        let merged = repository_session_history_mutation_execute(
            session.session_id,
            session.generation,
            merge.token,
        );
        assert_eq!(merged.state, NativeHistoryMutationExecutionState::Completed);
        assert_eq!(
            String::from_utf8(transfer_git(
                &fixture.0,
                &["rev-list", "--parents", "-n", "1", "HEAD"],
            ))
            .unwrap()
            .split_whitespace()
            .count(),
            3
        );
        let contained = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            NativeHistoryMutationRequest {
                kind: NativeHistoryMutationKind::Merge,
                targets: vec![second.clone()],
                source_name: Some(b"topic".to_vec()),
                merge_mode: NativeHistoryMergeMode::FastForwardIfPossible,
                acknowledge_published_history: false,
                no_commit: false,
            },
        )
        .preview
        .unwrap();
        assert!(contained.already_contained);
        assert_eq!(
            repository_session_history_mutation_execute(
                session.session_id,
                session.generation,
                contained.token,
            )
            .state,
            NativeHistoryMutationExecutionState::AlreadyContained
        );
        transfer_git(&fixture.0, &["reset", "--hard", &before]);
        refresh_session_at_head(&session, &before);
        let picks = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            NativeHistoryMutationRequest {
                kind: NativeHistoryMutationKind::CherryPick,
                targets: vec![first.clone(), second.clone()],
                source_name: None,
                merge_mode: NativeHistoryMergeMode::FastForwardIfPossible,
                acknowledge_published_history: false,
                no_commit: false,
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            picks.arguments,
            ["cherry-pick", first.as_str(), second.as_str()]
        );
        assert_eq!(
            repository_session_history_mutation_execute(
                session.session_id,
                session.generation,
                picks.token,
            )
            .state,
            NativeHistoryMutationExecutionState::Completed
        );
        let subjects = String::from_utf8(transfer_git(
            &fixture.0,
            &["log", "-2", "--reverse", "--format=%s"],
        ))
        .unwrap();
        assert_eq!(subjects.lines().collect::<Vec<_>>(), ["one", "two"]);
        refresh_session(&session);
        let empty_pick = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            NativeHistoryMutationRequest {
                kind: NativeHistoryMutationKind::CherryPick,
                targets: vec![first],
                source_name: None,
                merge_mode: NativeHistoryMergeMode::FastForwardIfPossible,
                acknowledge_published_history: false,
                no_commit: false,
            },
        )
        .preview
        .unwrap();
        let empty_result = repository_session_history_mutation_execute(
            session.session_id,
            session.generation,
            empty_pick.token,
        );
        assert_eq!(
            empty_result.state,
            NativeHistoryMutationExecutionState::Interrupted
        );
        assert_eq!(
            empty_result.sequencer,
            Some(NativeHistoryMutationKind::CherryPick)
        );
        transfer_git(&fixture.0, &["cherry-pick", "--abort"]);
        assert_ne!(base, before);
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn history_mutation_exposes_partial_pick_conflict_and_real_sequencer() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(fixture.0.join("conflict.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("first.txt"), b"first\n").unwrap();
        transfer_git(&fixture.0, &["add", "first.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "first pick"]);
        let first = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(fixture.0.join("conflict.txt"), b"topic\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "conflicting pick"]);
        let second = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&fixture.0, &["switch", "main"]);
        fs::write(fixture.0.join("conflict.txt"), b"main\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "main conflict"]);
        let original = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();

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
        let preview = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            NativeHistoryMutationRequest {
                kind: NativeHistoryMutationKind::CherryPick,
                targets: vec![first, second],
                source_name: None,
                merge_mode: NativeHistoryMergeMode::FastForwardIfPossible,
                acknowledge_published_history: false,
                no_commit: false,
            },
        )
        .preview
        .unwrap();
        let result = repository_session_history_mutation_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert_eq!(result.state, NativeHistoryMutationExecutionState::Conflict);
        assert_eq!(
            result.sequencer,
            Some(NativeHistoryMutationKind::CherryPick)
        );
        assert_eq!(result.conflicting_paths, [b"conflict.txt".to_vec()]);
        assert!(fixture.0.join("first.txt").is_file());
        assert!(fixture.0.join(".git/CHERRY_PICK_HEAD").is_file());
        transfer_git(&fixture.0, &["cherry-pick", "--abort"]);
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim(),
            original
        );
        assert!(!fixture.0.join("first.txt").exists());
        assert_eq!(fs::read(fixture.0.join("conflict.txt")).unwrap(), b"main\n");
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn history_mutation_reverts_multiple_commits_in_requested_order() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(fixture.0.join("base.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        fs::write(fixture.0.join("one.txt"), b"one\n").unwrap();
        transfer_git(&fixture.0, &["add", "one.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "one"]);
        let one = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(fixture.0.join("two.txt"), b"two\n").unwrap();
        transfer_git(&fixture.0, &["add", "two.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "two"]);
        let two = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
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
        let preview = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            NativeHistoryMutationRequest {
                kind: NativeHistoryMutationKind::Revert,
                targets: vec![two.clone(), one.clone()],
                source_name: None,
                merge_mode: NativeHistoryMergeMode::FastForwardIfPossible,
                acknowledge_published_history: false,
                no_commit: false,
            },
        )
        .preview
        .unwrap();
        assert_eq!(preview.arguments, ["revert", "--no-edit", &two, &one]);
        let result = repository_session_history_mutation_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert_eq!(result.state, NativeHistoryMutationExecutionState::Completed);
        assert!(!fixture.0.join("one.txt").exists());
        assert!(!fixture.0.join("two.txt").exists());
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn history_revert_apply_only_leaves_staged_changes_without_moving_head() {
        let (fixture, target, head) = revert_test_fixture(false);
        let session = revert_test_session(&fixture, 2301);
        let preview = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            revert_test_request(target.clone(), true),
        )
        .preview
        .unwrap();
        assert_eq!(preview.arguments, ["revert", "--no-commit", &target]);
        assert!(preview.no_commit);
        let result = repository_session_history_mutation_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert_eq!(result.state, NativeHistoryMutationExecutionState::Completed);
        assert_eq!(fs::read(fixture.0.join("tracked.txt")).unwrap(), b"base\n");
        assert_eq!(
            transfer_git(&fixture.0, &["status", "--porcelain"]),
            b"M  tracked.txt\n"
        );
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim(),
            head
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn history_revert_refuses_existing_and_unobserved_changes_in_both_modes() {
        for no_commit in [false, true] {
            for change in ["staged", "unstaged", "untracked", "operation", "head"] {
                let (fixture, target, head) = revert_test_fixture(false);
                let session = revert_test_session(&fixture, 2302);
                let preview = repository_session_history_mutation_preview(
                    session.session_id,
                    session.generation,
                    revert_test_request(target.clone(), no_commit),
                )
                .preview
                .unwrap();
                match change {
                    "untracked" => fs::write(fixture.0.join("untracked.txt"), b"keep\n").unwrap(),
                    "operation" => {
                        fs::write(fixture.0.join(".git/MERGE_HEAD"), format!("{head}\n")).unwrap()
                    }
                    "head" => {
                        transfer_git(&fixture.0, &["commit", "--allow-empty", "-qm", "external"]);
                    }
                    _ => {
                        fs::write(fixture.0.join("tracked.txt"), b"keep\n").unwrap();
                        if change == "staged" {
                            transfer_git(&fixture.0, &["add", "tracked.txt"]);
                        }
                    }
                }
                // Watchers are off and no reload occurred: admission must inspect live Git state.
                let before = transfer_git(&fixture.0, &["status", "--porcelain"]);
                let index = fs::read(fixture.0.join(".git/index")).unwrap();
                let result = repository_session_history_mutation_execute(
                    session.session_id,
                    session.generation,
                    preview.token,
                );
                let expected = match change {
                    "operation" => NativeHistoryMutationFailureKind::ActiveOperation,
                    "head" => NativeHistoryMutationFailureKind::Stale,
                    _ => NativeHistoryMutationFailureKind::DirtyWorktree,
                };
                assert_eq!(
                    result.failure.unwrap().kind,
                    expected,
                    "{change} no_commit={no_commit}"
                );
                assert_eq!(transfer_git(&fixture.0, &["status", "--porcelain"]), before);
                assert_eq!(fs::read(fixture.0.join(".git/index")).unwrap(), index);
                refresh_session(&session);
                let refused = repository_session_history_mutation_preview(
                    session.session_id,
                    session.generation,
                    revert_test_request(target, no_commit),
                );
                if change != "head" {
                    assert!(refused.preview.is_none());
                }
                assert!(repository_session_close(session.session_id, session.generation).accepted);
            }
        }
    }

    #[test]
    fn history_revert_apply_only_conflict_survives_restart_and_does_not_commit_on_continue() {
        for abort in [false, true] {
            let (fixture, target, head) = revert_test_fixture(true);
            let session = revert_test_session(&fixture, 2303);
            let preview = repository_session_history_mutation_preview(
                session.session_id,
                session.generation,
                revert_test_request(target, true),
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
            let reopened = revert_test_session(&fixture, 2304);
            let snapshot = repository_session_conflicts(reopened.session_id, reopened.generation)
                .snapshot
                .unwrap();
            assert_eq!(snapshot.operation, NativeConflictOperationKind::Revert);
            if !abort {
                let conflicted_index = fs::read(fixture.0.join(".git/index")).unwrap();
                let file = &snapshot.files[0];
                let resolved = repository_session_conflict_choose_side(
                    reopened.session_id,
                    reopened.generation,
                    file.path.clone(),
                    file.fingerprint,
                    NativeConflictSideChoice::Incoming,
                );
                assert!(resolved.snapshot.unwrap().can_continue);
                // An external index edit can restore conflicts after our last snapshot.
                fs::write(fixture.0.join(".git/index"), conflicted_index).unwrap();
                let refused = repository_session_conflict_continue(
                    reopened.session_id,
                    reopened.generation,
                    NativeConflictSequencerAction::Continue,
                );
                assert_eq!(
                    refused.failure.unwrap().kind,
                    NativeConflictFailureKind::Unresolved
                );
                assert!(fixture.0.join(".git/REVERT_HEAD").exists());
                transfer_git(&fixture.0, &["add", "tracked.txt"]);
            }
            let result = repository_session_conflict_continue(
                reopened.session_id,
                reopened.generation,
                if abort {
                    NativeConflictSequencerAction::Abort
                } else {
                    NativeConflictSequencerAction::Continue
                },
            );
            assert_eq!(
                result.state,
                if abort {
                    NativeConflictContinuationState::Aborted
                } else {
                    NativeConflictContinuationState::Completed
                }
            );
            assert_eq!(
                String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                    .unwrap()
                    .trim(),
                head
            );
            assert!(!fixture.0.join(".git/REVERT_HEAD").exists());
            if abort {
                assert_eq!(fs::read(fixture.0.join("tracked.txt")).unwrap(), b"later\n");
                assert!(transfer_git(&fixture.0, &["status", "--porcelain"]).is_empty());
            } else {
                assert_eq!(fs::read(fixture.0.join("tracked.txt")).unwrap(), b"base\n");
                assert_eq!(
                    transfer_git(&fixture.0, &["status", "--porcelain"]),
                    b"M  tracked.txt\n"
                );
            }
            assert!(repository_session_close(reopened.session_id, reopened.generation).accepted);
        }
    }

    #[test]
    fn history_revert_apply_only_repreviews_after_unchanged_snapshot_refresh() {
        let (fixture, target, head) = revert_test_fixture(false);
        let session = revert_test_session(&fixture, 2308);
        let request = revert_test_request(target, true);
        let preview = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            request.clone(),
        )
        .preview
        .unwrap();
        // A refresh is an observable revision change even when Git facts are unchanged.
        refresh_session(&session);
        let stale = repository_session_history_mutation_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert_eq!(stale.state, NativeHistoryMutationExecutionState::Stale);
        assert_eq!(
            stale.failure.unwrap().kind,
            NativeHistoryMutationFailureKind::Stale
        );
        assert!(stale.activity_ids.is_empty());
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim(),
            head
        );
        assert!(transfer_git(&fixture.0, &["status", "--porcelain"]).is_empty());
        let fresh = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            request,
        )
        .preview
        .unwrap();
        let completed = repository_session_history_mutation_execute(
            session.session_id,
            session.generation,
            fresh.token,
        );
        assert_eq!(
            completed.state,
            NativeHistoryMutationExecutionState::Completed
        );
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim(),
            head
        );
        assert_eq!(
            transfer_git(&fixture.0, &["status", "--porcelain"]),
            b"M  tracked.txt\n"
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn history_revert_apply_only_multi_selection_is_refused_before_mutation() {
        let (fixture, target, head) = revert_test_fixture(true);
        let session = revert_test_session(&fixture, 2306);
        let mut request = revert_test_request(target, true);
        request.targets.push(head.clone());
        let result = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            request,
        );
        assert!(result.preview.is_none());
        assert_eq!(
            result.failure.unwrap().kind,
            NativeHistoryMutationFailureKind::InvalidRequest
        );
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim(),
            head
        );
        assert!(transfer_git(&fixture.0, &["status", "--porcelain"]).is_empty());
        assert!(!fixture.0.join(".git/REVERT_HEAD").exists());
        assert!(!fixture.0.join(".git/sequencer").exists());
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn history_revert_rejects_merge_commits_before_any_mutation() {
        let (fixture, _, _) = revert_test_fixture(false);
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("topic.txt"), b"topic\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "topic"]);
        transfer_git(&fixture.0, &["switch", "main"]);
        transfer_git(&fixture.0, &["merge", "--no-ff", "-m", "merge", "topic"]);
        let target = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        let session = revert_test_session(&fixture, 2305);
        for no_commit in [false, true] {
            let result = repository_session_history_mutation_preview(
                session.session_id,
                session.generation,
                revert_test_request(target.clone(), no_commit),
            );
            assert_eq!(
                result.failure.unwrap().kind,
                NativeHistoryMutationFailureKind::MergeCommit
            );
            assert!(result.preview.is_none());
            assert!(transfer_git(&fixture.0, &["status", "--porcelain"]).is_empty());
        }
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn history_mutation_refuses_stale_dirty_and_detached_preconditions() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("topic.txt"), b"topic\n").unwrap();
        transfer_git(&fixture.0, &["add", "topic.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "topic"]);
        let topic = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&fixture.0, &["switch", "main"]);
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
        transfer_git(&fixture.0, &["branch", "--set-upstream-to=topic", "main"]);
        refresh_session(&session);
        let published_pick = || NativeHistoryMutationRequest {
            kind: NativeHistoryMutationKind::CherryPick,
            targets: vec![topic.clone()],
            source_name: None,
            merge_mode: NativeHistoryMergeMode::FastForwardIfPossible,
            acknowledge_published_history: false,
            no_commit: false,
        };
        assert_eq!(
            repository_session_history_mutation_preview(
                session.session_id,
                session.generation,
                published_pick(),
            )
            .failure
            .unwrap()
            .kind,
            NativeHistoryMutationFailureKind::PublicationConfirmationRequired
        );
        let mut acknowledged = published_pick();
        acknowledged.acknowledge_published_history = true;
        assert!(repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            acknowledged,
        )
        .preview
        .is_some());
        let request = || NativeHistoryMutationRequest {
            kind: NativeHistoryMutationKind::Merge,
            targets: vec![topic.clone()],
            source_name: Some(b"topic".to_vec()),
            merge_mode: NativeHistoryMergeMode::FastForwardIfPossible,
            acknowledge_published_history: false,
            no_commit: false,
        };
        let stale = repository_session_history_mutation_preview(
            session.session_id,
            session.generation,
            request(),
        )
        .preview
        .unwrap();
        fs::write(fixture.0.join("main.txt"), b"main\n").unwrap();
        transfer_git(&fixture.0, &["add", "main.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "external main"]);
        let external_head = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        refresh_session(&session);
        assert_eq!(
            repository_session_history_mutation_execute(
                session.session_id,
                session.generation,
                stale.token,
            )
            .state,
            NativeHistoryMutationExecutionState::Stale
        );
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim(),
            external_head
        );
        fs::write(fixture.0.join("tracked.txt"), b"dirty\n").unwrap();
        refresh_session(&session);
        assert_eq!(
            repository_session_history_mutation_preview(
                session.session_id,
                session.generation,
                request(),
            )
            .failure
            .unwrap()
            .kind,
            NativeHistoryMutationFailureKind::DirtyWorktree
        );
        transfer_git(&fixture.0, &["reset", "--hard", "HEAD"]);
        transfer_git(&fixture.0, &["switch", "--detach"]);
        refresh_session(&session);
        assert_eq!(
            repository_session_history_mutation_preview(
                session.session_id,
                session.generation,
                request(),
            )
            .failure
            .unwrap()
            .kind,
            NativeHistoryMutationFailureKind::DetachedHead
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }
}

/// Merge, cherry-pick and revert stop at conflicts and resume through Git's sequencer. An
/// apply-only revert finishes with `revert --quit` once its changes are staged.
pub(crate) struct HistorySequencer(NativeHistoryMutationKind);

pub(crate) static MERGE: HistorySequencer = HistorySequencer(NativeHistoryMutationKind::Merge);
pub(crate) static CHERRY_PICK: HistorySequencer =
    HistorySequencer(NativeHistoryMutationKind::CherryPick);
pub(crate) static REVERT: HistorySequencer = HistorySequencer(NativeHistoryMutationKind::Revert);

impl InterruptedOperation for HistorySequencer {
    fn kind(&self) -> NativeConflictOperationKind {
        match self.0 {
            NativeHistoryMutationKind::Merge => NativeConflictOperationKind::Merge,
            NativeHistoryMutationKind::CherryPick => NativeConflictOperationKind::CherryPick,
            NativeHistoryMutationKind::Revert => NativeConflictOperationKind::Revert,
        }
    }

    fn offers(&self, action: NativeConflictSequencerAction) -> bool {
        // A merge has a single step: there is nothing to skip to.
        !(self.0 == NativeHistoryMutationKind::Merge
            && action == NativeConflictSequencerAction::Skip)
    }

    fn sequencer(
        &self,
        interruption: &Interruption<'_>,
        action: NativeConflictSequencerAction,
    ) -> Result<SequencerStep, NativeConflictFailureKind> {
        let apply_only = self.0 == NativeHistoryMutationKind::Revert
            && action == NativeConflictSequencerAction::Continue
            && pending_revert_no_commit(
                interruption.common_git_dir,
                interruption.git_dir,
                interruption
                    .snapshot
                    .status
                    .as_ref()
                    .and_then(|status| status.branch.oid.as_ref()),
            )
            .map_err(|()| NativeConflictFailureKind::Read)?;
        if apply_only {
            let mut step =
                SequencerStep::new(devmil_git::merge::revert_no_commit_finish_arguments());
            step.apply_only = true;
            return Ok(step);
        }
        let operation = match self.0 {
            NativeHistoryMutationKind::Merge => devmil_git::merge::SequencerOperation::Merge,
            NativeHistoryMutationKind::CherryPick => {
                devmil_git::merge::SequencerOperation::CherryPick
            }
            NativeHistoryMutationKind::Revert => devmil_git::merge::SequencerOperation::Revert,
        };
        Ok(SequencerStep::new(devmil_git::merge::sequencer_arguments(
            operation,
            match action {
                NativeConflictSequencerAction::Continue => {
                    devmil_git::merge::SequencerAction::Continue
                }
                NativeConflictSequencerAction::Skip => devmil_git::merge::SequencerAction::Skip,
                NativeConflictSequencerAction::Abort => devmil_git::merge::SequencerAction::Abort,
            },
        )))
    }

    fn check_under_lease(
        &self,
        interruption: &Interruption<'_>,
        step: &SequencerStep,
        lease: &devmil_git::model::RepositoryMutation,
        cancellation: &AtomicBool,
    ) -> Result<(), NativeConflictFailureKind> {
        if !step.apply_only {
            return Ok(());
        }
        // Unlike --continue, --quit does not reject unmerged index entries itself.
        // Read the index under the lease rather than trusting the last watcher snapshot.
        let Ok(Some(status)) = lease.fresh_status(Some(cancellation)) else {
            return Err(NativeConflictFailureKind::Read);
        };
        if status.entries.iter().any(|entry| entry.is_conflicted()) {
            return Err(NativeConflictFailureKind::Unresolved);
        }
        if pending_revert_no_commit(
            interruption.common_git_dir,
            interruption.git_dir,
            status.branch.oid.as_ref(),
        ) != Ok(true)
        {
            return Err(NativeConflictFailureKind::Read);
        }
        Ok(())
    }

    fn completed(
        &self,
        interruption: &Interruption<'_>,
        _step: &SequencerStep,
        _current: &RepositorySnapshot,
    ) {
        discard_apply_only(interruption.common_git_dir, interruption.git_dir, self.0);
    }

    fn aborted(&self, interruption: &Interruption<'_>, _step: &SequencerStep) {
        discard_apply_only(interruption.common_git_dir, interruption.git_dir, self.0);
    }
}
