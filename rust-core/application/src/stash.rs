//! Stable-identity stash workflows built on the shared stash command family.
pub use gitlama_contract::stash::*;

use crate::activity::ActivityStore;
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::dto::NativeConflictContinuationResult;
use crate::dto::NativeConflictFailure;
use crate::dto::NativeConflictFailureKind;
use crate::dto::NativeConflictSequencerAction;
use crate::operations::{coordinate_mutation, ExecutionFailure};
use crate::preview_store::PreviewStore;
use devmil_git::activity::ActivityStatus;
use devmil_git::commands::stash::{entry_arguments, push_arguments_with_options, EntryOperation};
use devmil_git::commands::{branch_arguments, BranchRequest};
use devmil_git::loading::refs::RefsSectionData;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::status::WorkingTreeState;
use devmil_git::types::{ObjectId, RepositoryRelativePath};
use devmil_git::{Repository, RepositorySnapshot};
use serde::{Deserialize, Serialize};
use std::sync::atomic::AtomicBool;

use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, OnceLock};

type EventSink = Arc<dyn Fn(devmil_git::activity::ActivityEvent) + Send + Sync>;

const PREVIEW_CAPACITY_PER_SESSION: usize = 8;
const MAX_MESSAGE_BYTES: usize = 256;
const MAX_PATHS: usize = 256;
const ACTIVE_CONFLICT_SCHEMA: &str = "gitlama.stash-conflict.v1";
const ACTIVE_CONFLICT_PATH: &str = "gitlama/stash-conflict-v1.json";

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum ActiveStashConflictKind {
    Apply,
    Pop,
    AutoStashCheckout,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ActiveStashConflict {
    schema: String,
    pub kind: ActiveStashConflictKind,
    pub stash_oid: String,
    pub original_head: String,
    pub original_branch: Option<String>,
}

const fn native_state(state: MutationState) -> NativeStashExecutionState {
    match state {
        MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
            NativeStashExecutionState::Completed
        }
        MutationState::ReconciledWithWarning => NativeStashExecutionState::ReconciledWithWarning,
        MutationState::Conflict
        | MutationState::Interrupted
        | MutationState::EditStop
        | MutationState::Partial => NativeStashExecutionState::Conflict,
        MutationState::Stale => NativeStashExecutionState::Stale,
        MutationState::Canceled | MutationState::Failed => NativeStashExecutionState::Failed,
        MutationState::OutcomeUncertain => NativeStashExecutionState::OutcomeUncertain,
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct StashEntryFact {
    selector: Vec<u8>,
    object_id: ObjectId,
    subject: Vec<u8>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct StashFacts {
    revision: u64,
    worktree: PathBuf,
    common_git_dir: PathBuf,
    head_object_id: Option<ObjectId>,
    head_branch: Option<String>,
    working_tree: WorkingTreeState,
    status_paths: Vec<Vec<u8>>,
    branches: Vec<Vec<u8>>,
    stashes: Vec<StashEntryFact>,
}

#[derive(Clone)]
struct StashPlan {
    request: NativeStashRequest,
    paths: Vec<RepositoryRelativePath>,
    entry: Option<StashEntryFact>,
    commands: Vec<Vec<OsString>>,
    facts: StashFacts,
}

static STASHES: OnceLock<Mutex<PreviewStore<StashPlan>>> = OnceLock::new();

fn lock_stashes() -> std::sync::MutexGuard<'static, PreviewStore<StashPlan>> {
    crate::preview_store::lock(
        STASHES.get_or_init(|| Mutex::new(PreviewStore::new(PREVIEW_CAPACITY_PER_SESSION))),
    )
}

pub(crate) fn preview(
    session_id: u64,
    repository: &Repository,
    request: NativeStashRequest,
) -> NativeStashPreviewResult {
    let plan = match build_plan(request, &repository.snapshot()) {
        Ok(value) => value,
        Err(kind) => return preview_failure(kind),
    };
    let token = lock_stashes().issue(session_id, plan.clone());
    NativeStashPreviewResult {
        preview: Some(NativeStashPreview {
            token,
            kind: plan.request.kind,
            commands: plan
                .commands
                .iter()
                .map(|arguments| NativeStashCommandPreview {
                    arguments: arguments
                        .iter()
                        .map(|value| value.to_string_lossy().into_owned())
                        .collect(),
                })
                .collect(),
            affected_paths: if plan.paths.is_empty()
                && matches!(
                    plan.request.kind,
                    NativeStashKind::Push
                        | NativeStashKind::AutoStashCheckout
                        | NativeStashKind::StashCheckoutCommit
                        | NativeStashKind::AutoStashCheckoutCommit
                ) {
                plan.facts.status_paths.len().try_into().unwrap_or(u32::MAX)
            } else {
                plan.paths.len().try_into().unwrap_or(u32::MAX)
            },
            includes_untracked: plan.request.include_untracked
                || matches!(
                    plan.request.kind,
                    NativeStashKind::AutoStashCheckout
                        | NativeStashKind::StashCheckoutCommit
                        | NativeStashKind::AutoStashCheckoutCommit
                ),
            keeps_index: plan.request.keep_index,
            selected_object_id: plan
                .entry
                .as_ref()
                .map(|entry| entry.object_id.as_str().to_owned()),
            target_branch: plan.request.target_branch.clone(),
            destructive: matches!(plan.request.kind, NativeStashKind::Drop),
        }),
        failure: None,
    }
}

pub(crate) fn execute(
    session_id: u64,
    token: u64,
    repository: &Repository,
    activity: &ActivityStore,
) -> NativeStashExecutionResult {
    let (plan, cancellation) = {
        let mut registry = lock_stashes();
        let Some(owned) = registry.get_mut(session_id, token) else {
            return execution_failure(NativeStashFailureKind::InvalidRequest);
        };
        if owned.running {
            return execution_failure(NativeStashFailureKind::InvalidRequest);
        }
        owned.running = true;
        owned.cancellation.store(false, Ordering::Release);
        (owned.value.clone(), Arc::clone(&owned.cancellation))
    };
    let current = match stash_facts(&repository.snapshot()) {
        Some(value) => value,
        None => {
            finish(session_id, token);
            return execution_failure(NativeStashFailureKind::Read);
        }
    };
    if current != plan.facts || !entry_still_matches(&plan, &current) {
        finish(session_id, token);
        return stale_result();
    }

    let mut activity_ids = Vec::new();
    let mut failure = None;
    let mut progress = StepProgress::default();
    let sink = activity.sink();
    let outcome = coordinate_mutation(repository, cancellation.as_ref(), |cancellation| {
        execute_plan(
            &plan,
            cancellation,
            &sink,
            &mut activity_ids,
            &mut failure,
            &mut progress,
        )
    });
    finish(session_id, token);
    let mut outcome = MutationOutcome::from_terminal(outcome).with_failure(failure);
    if outcome.state == MutationState::Canceled {
        outcome.failure = Some(NativeStashFailureKind::Canceled);
    } else if outcome.state == MutationState::Failed
        && outcome.failure == Some(NativeStashFailureKind::Conflict)
    {
        outcome.state = MutationState::Conflict;
    }
    execution_result(outcome, activity_ids, &progress)
}

/// The bridge result of a stash execution: the one place its outcome becomes a state.
fn execution_result(
    outcome: MutationOutcome<NativeStashFailureKind>,
    activity_ids: Vec<u64>,
    progress: &StepProgress,
) -> NativeStashExecutionResult {
    NativeStashExecutionResult {
        state: native_state(outcome.state),
        failure: outcome.failure.map(|kind| NativeStashFailure { kind }),
        activity_ids: activity_ids
            .into_iter()
            .map(|value| value.to_string())
            .collect(),
        stash_created: progress.stash_created,
        checkout_completed: progress.checkout_completed,
        reapply_completed: progress.reapply_completed,
        stash_retained: progress.stash_retained,
    }
}

#[derive(Default)]
struct StepProgress {
    stash_created: bool,
    checkout_completed: bool,
    reapply_completed: bool,
    stash_retained: bool,
}

fn execute_plan(
    plan: &StashPlan,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &mut Vec<u64>,
    failure: &mut Option<NativeStashFailureKind>,
    progress: &mut StepProgress,
) -> Result<(), ExecutionFailure> {
    match plan.request.kind {
        NativeStashKind::Push | NativeStashKind::Drop => {
            let result = run(
                &plan.facts.worktree,
                plan.commands[0].clone(),
                cancellation,
                sink,
                activity_ids,
            );
            if result.is_err() {
                *failure = Some(
                    if matches!(
                        plan.request.kind,
                        NativeStashKind::Apply | NativeStashKind::Pop
                    ) && has_unmerged_paths(&plan.facts.worktree)
                    {
                        progress.stash_retained = true;
                        NativeStashFailureKind::Conflict
                    } else {
                        NativeStashFailureKind::Failed
                    },
                );
            }
            result
        }
        NativeStashKind::Apply | NativeStashKind::Pop => {
            let entry = plan.entry.as_ref().expect("stash plan has an entry");
            let kind = if plan.request.kind == NativeStashKind::Pop {
                ActiveStashConflictKind::Pop
            } else {
                ActiveStashConflictKind::Apply
            };
            if write_active_conflict(
                &plan.facts.common_git_dir,
                ActiveStashConflict {
                    schema: ACTIVE_CONFLICT_SCHEMA.to_owned(),
                    kind,
                    stash_oid: entry.object_id.as_str().to_owned(),
                    original_head: plan
                        .facts
                        .head_object_id
                        .as_ref()
                        .expect("stash apply requires HEAD")
                        .as_str()
                        .to_owned(),
                    original_branch: plan.facts.head_branch.clone(),
                },
            )
            .is_err()
            {
                *failure = Some(NativeStashFailureKind::Write);
                return Err(ExecutionFailure::Definite);
            }
            let result = run(
                &plan.facts.worktree,
                plan.commands[0].clone(),
                cancellation,
                sink,
                activity_ids,
            );
            if result.is_ok() {
                if !finish_active_conflict(&plan.facts.common_git_dir) {
                    *failure = Some(NativeStashFailureKind::Write);
                    return Err(ExecutionFailure::Uncertain);
                }
            } else if has_unmerged_paths(&plan.facts.worktree) {
                progress.stash_retained = true;
                *failure = Some(NativeStashFailureKind::Conflict);
            } else {
                let _ = finish_active_conflict(&plan.facts.common_git_dir);
                *failure = Some(NativeStashFailureKind::Failed);
            }
            result
        }
        NativeStashKind::Rename => {
            execute_rename(plan, cancellation, sink, activity_ids, failure, progress)
        }
        NativeStashKind::AutoStashCheckout
        | NativeStashKind::StashCheckoutCommit
        | NativeStashKind::AutoStashCheckoutCommit => {
            execute_auto_stash_checkout(plan, cancellation, sink, activity_ids, failure, progress)
        }
    }
}

fn execute_rename(
    plan: &StashPlan,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &mut Vec<u64>,
    failure: &mut Option<NativeStashFailureKind>,
    progress: &mut StepProgress,
) -> Result<(), ExecutionFailure> {
    let entry = plan.entry.as_ref().expect("rename plan has an entry");
    run(
        &plan.facts.worktree,
        plan.commands[0].clone(),
        cancellation,
        sink,
        activity_ids,
    )?;
    let store = run(
        &plan.facts.worktree,
        plan.commands[1].clone(),
        cancellation,
        sink,
        activity_ids,
    );
    if store.is_err() {
        let original_subject = String::from_utf8_lossy(&entry.subject);
        let rollback = vec![
            OsString::from("stash"),
            OsString::from("store"),
            OsString::from("-m"),
            OsString::from(original_subject.as_ref()),
            OsString::from(entry.object_id.as_str()),
        ];
        if run(
            &plan.facts.worktree,
            rollback,
            cancellation,
            sink,
            activity_ids,
        )
        .is_ok()
        {
            progress.stash_retained = true;
        }
        *failure = Some(NativeStashFailureKind::Failed);
        return store;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn execute_auto_stash_checkout(
    plan: &StashPlan,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &mut Vec<u64>,
    failure: &mut Option<NativeStashFailureKind>,
    progress: &mut StepProgress,
) -> Result<(), ExecutionFailure> {
    let dirty = plan.facts.working_tree != WorkingTreeState::Clean;
    let restore_index = plan.request.kind != NativeStashKind::AutoStashCheckout;
    let mut auto_oid = None;
    if dirty {
        let previous_stash = resolve_object(&plan.facts.worktree, "refs/stash");
        run(
            &plan.facts.worktree,
            plan.commands[0].clone(),
            cancellation,
            sink,
            activity_ids,
        )?;
        auto_oid = resolve_object(&plan.facts.worktree, "refs/stash");
        // A successful stash push can be a no-op (for example, only a submodule
        // is dirty). Never apply or drop a pre-existing stash in that case.
        if auto_oid == previous_stash {
            *failure = Some(NativeStashFailureKind::NothingToStash);
            return Err(ExecutionFailure::Definite);
        }
        progress.stash_created = true;
        progress.stash_retained = true;
        if auto_oid.is_none() {
            *failure = Some(NativeStashFailureKind::Read);
            return Err(ExecutionFailure::Uncertain);
        }
        if write_active_conflict(
            &plan.facts.common_git_dir,
            ActiveStashConflict {
                schema: ACTIVE_CONFLICT_SCHEMA.to_owned(),
                kind: ActiveStashConflictKind::AutoStashCheckout,
                stash_oid: auto_oid
                    .as_ref()
                    .expect("checked above")
                    .as_str()
                    .to_owned(),
                original_head: plan
                    .facts
                    .head_object_id
                    .as_ref()
                    .expect("auto-stash checkout requires HEAD")
                    .as_str()
                    .to_owned(),
                original_branch: plan.facts.head_branch.clone(),
            },
        )
        .is_err()
        {
            *failure = Some(NativeStashFailureKind::Write);
            return Err(ExecutionFailure::Uncertain);
        }
    }
    let checkout_index = usize::from(dirty);
    let checkout = run(
        &plan.facts.worktree,
        plan.commands[checkout_index].clone(),
        cancellation,
        sink,
        activity_ids,
    );
    if checkout.is_err() {
        if let Some(oid) = &auto_oid {
            if reapply_and_drop(
                &plan.facts.worktree,
                oid,
                restore_index,
                cancellation,
                sink,
                activity_ids,
            ) {
                progress.reapply_completed = true;
                progress.stash_retained = false;
                let _ = finish_active_conflict(&plan.facts.common_git_dir);
            }
        }
        *failure = Some(NativeStashFailureKind::Failed);
        return checkout;
    }
    progress.checkout_completed = true;
    let Some(oid) = auto_oid else {
        progress.reapply_completed = true;
        return Ok(());
    };
    if plan.request.kind == NativeStashKind::StashCheckoutCommit {
        if !finish_active_conflict(&plan.facts.common_git_dir) {
            *failure = Some(NativeStashFailureKind::Write);
            return Err(ExecutionFailure::Uncertain);
        }
        return Ok(());
    }
    if reapply_and_drop(
        &plan.facts.worktree,
        &oid,
        restore_index,
        cancellation,
        sink,
        activity_ids,
    ) {
        progress.reapply_completed = true;
        progress.stash_retained = false;
        if !finish_active_conflict(&plan.facts.common_git_dir) {
            *failure = Some(NativeStashFailureKind::Write);
            return Err(ExecutionFailure::Uncertain);
        }
        return Ok(());
    }
    *failure = Some(if has_unmerged_paths(&plan.facts.worktree) {
        NativeStashFailureKind::Conflict
    } else {
        NativeStashFailureKind::Failed
    });
    Err(ExecutionFailure::Definite)
}

fn reapply_and_drop(
    worktree: &Path,
    oid: &ObjectId,
    restore_index: bool,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &mut Vec<u64>,
) -> bool {
    let apply = entry_arguments(
        if restore_index {
            EntryOperation::ApplyWithIndex
        } else {
            EntryOperation::Apply
        },
        oid,
        "stash@{0}",
    )
    .expect("constant selector is valid");
    if run(worktree, apply, cancellation, sink, activity_ids).is_err() {
        return false;
    }
    if resolve_object(worktree, "stash@{0}").as_ref() != Some(oid) {
        return false;
    }
    let drop = entry_arguments(EntryOperation::Drop, oid, "stash@{0}")
        .expect("constant selector is valid");
    run(worktree, drop, cancellation, sink, activity_ids).is_ok()
}

fn run(
    worktree: &Path,
    arguments: Vec<OsString>,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &EventSink,
    activity_ids: &mut Vec<u64>,
) -> Result<(), ExecutionFailure> {
    // Every command this runs changes the stash list, the index or the worktree.
    let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
    activity_ids.push(id.get());
    let command = GitProcessCommand::git("git")
        .args(arguments.into_iter().map(ProcessArgument::visible))
        .current_dir(worktree)
        .redact_output();
    let mut publish = |event| sink(event);
    let result = ActivityGitRunner::run_private(command, id, Some(cancellation), &mut publish);
    match result.activity.status {
        ActivityStatus::Succeeded { .. } => Ok(()),
        ActivityStatus::Canceled { .. } => Err(ExecutionFailure::Canceled),
        ActivityStatus::Running
        | ActivityStatus::Failed { .. }
        | ActivityStatus::TimedOut { .. }
        | ActivityStatus::LaunchError { .. } => Err(ExecutionFailure::Definite),
    }
}

fn build_plan(
    request: NativeStashRequest,
    snapshot: &RepositorySnapshot,
) -> Result<StashPlan, NativeStashFailureKind> {
    validate_request(&request)?;
    let facts = stash_facts(snapshot).ok_or(NativeStashFailureKind::Read)?;
    let paths = request
        .paths
        .iter()
        .cloned()
        .map(relative_path)
        .collect::<Result<Vec<_>, _>>()?;
    // Git can create a tracked partial stash and then fail while rejecting an
    // untracked pathspec. Reject that ambiguous combination before mutation;
    // include-untracked remains available for the complete repository scope.
    if request.kind == NativeStashKind::Push && request.include_untracked && !paths.is_empty() {
        return Err(NativeStashFailureKind::InvalidRequest);
    }
    if !paths.is_empty()
        && request
            .paths
            .iter()
            .any(|path| !facts.status_paths.contains(path))
    {
        return Err(NativeStashFailureKind::InvalidRequest);
    }
    let entry = match (&request.selector, &request.object_id) {
        (Some(selector), Some(object_id)) => {
            let object_id = ObjectId::parse(object_id.clone())
                .map_err(|_| NativeStashFailureKind::InvalidRequest)?;
            Some(
                facts
                    .stashes
                    .iter()
                    .find(|entry| {
                        entry.selector == selector.as_bytes() && entry.object_id == object_id
                    })
                    .cloned()
                    .ok_or(NativeStashFailureKind::MissingStash)?,
            )
        }
        (None, Some(_))
            if matches!(
                request.kind,
                NativeStashKind::StashCheckoutCommit | NativeStashKind::AutoStashCheckoutCommit
            ) =>
        {
            None
        }
        (None, None) => None,
        _ => return Err(NativeStashFailureKind::InvalidRequest),
    };
    let commands = match request.kind {
        NativeStashKind::Push => {
            if facts.working_tree == WorkingTreeState::Clean {
                return Err(NativeStashFailureKind::NothingToStash);
            }
            vec![push_arguments_with_options(
                request.message.as_deref(),
                &paths,
                request.include_untracked,
                request.keep_index,
            )
            .map_err(|_| NativeStashFailureKind::InvalidRequest)?]
        }
        NativeStashKind::Apply | NativeStashKind::Pop | NativeStashKind::Drop => {
            if matches!(request.kind, NativeStashKind::Apply | NativeStashKind::Pop)
                && facts.working_tree != WorkingTreeState::Clean
            {
                return Err(NativeStashFailureKind::InvalidRequest);
            }
            if matches!(request.kind, NativeStashKind::Apply | NativeStashKind::Pop)
                && facts.head_object_id.is_none()
            {
                return Err(NativeStashFailureKind::InvalidRequest);
            }
            let entry = entry.as_ref().ok_or(NativeStashFailureKind::MissingStash)?;
            let operation = match request.kind {
                NativeStashKind::Apply => EntryOperation::Apply,
                NativeStashKind::Pop => EntryOperation::Pop,
                NativeStashKind::Drop => EntryOperation::Drop,
                _ => unreachable!(),
            };
            vec![entry_arguments(
                operation,
                &entry.object_id,
                std::str::from_utf8(&entry.selector)
                    .map_err(|_| NativeStashFailureKind::InvalidRequest)?,
            )
            .map_err(|_| NativeStashFailureKind::InvalidRequest)?]
        }
        NativeStashKind::Rename => {
            let entry = entry.as_ref().ok_or(NativeStashFailureKind::MissingStash)?;
            let message = request
                .message
                .as_ref()
                .ok_or(NativeStashFailureKind::InvalidRequest)?;
            vec![
                entry_arguments(
                    EntryOperation::Drop,
                    &entry.object_id,
                    std::str::from_utf8(&entry.selector)
                        .map_err(|_| NativeStashFailureKind::InvalidRequest)?,
                )
                .map_err(|_| NativeStashFailureKind::InvalidRequest)?,
                vec![
                    OsString::from("stash"),
                    OsString::from("store"),
                    OsString::from("-m"),
                    OsString::from(message),
                    OsString::from(entry.object_id.as_str()),
                ],
            ]
        }
        NativeStashKind::AutoStashCheckout
        | NativeStashKind::StashCheckoutCommit
        | NativeStashKind::AutoStashCheckoutCommit => {
            let checkout_request = if request.kind == NativeStashKind::AutoStashCheckout {
                let target = request
                    .target_branch
                    .as_ref()
                    .ok_or(NativeStashFailureKind::InvalidRequest)?;
                let full = format!("refs/heads/{target}");
                if !facts
                    .branches
                    .iter()
                    .any(|branch| branch == full.as_bytes())
                {
                    return Err(NativeStashFailureKind::InvalidRequest);
                }
                BranchRequest::Checkout {
                    name: target.clone(),
                }
            } else {
                BranchRequest::CheckoutDetached {
                    target: ObjectId::parse(
                        request
                            .object_id
                            .clone()
                            .ok_or(NativeStashFailureKind::InvalidRequest)?,
                    )
                    .map_err(|_| NativeStashFailureKind::InvalidRequest)?,
                }
            };
            let checkout = branch_arguments(&checkout_request)
                .map_err(|_| NativeStashFailureKind::InvalidRequest)?
                .into_iter()
                .map(OsString::from)
                .collect::<Vec<_>>();
            if facts.working_tree == WorkingTreeState::Clean {
                vec![checkout]
            } else {
                if facts.head_object_id.is_none() {
                    return Err(NativeStashFailureKind::InvalidRequest);
                }
                vec![
                    push_arguments_with_options(Some("GitLama auto-stash"), &[], true, false)
                        .map_err(|_| NativeStashFailureKind::InvalidRequest)?,
                    checkout,
                ]
            }
        }
    };
    Ok(StashPlan {
        request,
        paths,
        entry,
        commands,
        facts,
    })
}

fn validate_request(request: &NativeStashRequest) -> Result<(), NativeStashFailureKind> {
    if request.paths.len() > MAX_PATHS
        || request.message.as_ref().is_some_and(|message| {
            message.is_empty()
                || message.len() > MAX_MESSAGE_BYTES
                || message.chars().any(char::is_control)
        })
    {
        return Err(NativeStashFailureKind::InvalidRequest);
    }
    let push = request.kind == NativeStashKind::Push;
    let entry = matches!(
        request.kind,
        NativeStashKind::Apply
            | NativeStashKind::Pop
            | NativeStashKind::Drop
            | NativeStashKind::Rename
    );
    let auto = request.kind == NativeStashKind::AutoStashCheckout;
    if push {
        if request.selector.is_some()
            || request.object_id.is_some()
            || request.target_branch.is_some()
        {
            return Err(NativeStashFailureKind::InvalidRequest);
        }
    } else if entry {
        if request.selector.is_none()
            || request.object_id.is_none()
            || !request.paths.is_empty()
            || request.include_untracked
            || request.keep_index
            || request.target_branch.is_some()
            || (request.kind == NativeStashKind::Rename) != request.message.is_some()
        {
            return Err(NativeStashFailureKind::InvalidRequest);
        }
    } else if matches!(
        request.kind,
        NativeStashKind::StashCheckoutCommit | NativeStashKind::AutoStashCheckoutCommit
    ) {
        if request
            .object_id
            .as_ref()
            .is_none_or(|id| ObjectId::parse(id.clone()).is_err())
            || request.target_branch.is_some()
            || request.message.is_some()
            || request.selector.is_some()
            || !request.paths.is_empty()
            || request.include_untracked
            || request.keep_index
        {
            return Err(NativeStashFailureKind::InvalidRequest);
        }
    } else if auto
        && (request.target_branch.is_none()
            || request.message.is_some()
            || request.selector.is_some()
            || request.object_id.is_some()
            || !request.paths.is_empty()
            || request.include_untracked
            || request.keep_index)
    {
        return Err(NativeStashFailureKind::InvalidRequest);
    }
    Ok(())
}

fn stash_facts(snapshot: &RepositorySnapshot) -> Option<StashFacts> {
    let repository = snapshot.repository.as_ref()?;
    let status = snapshot.status.as_ref()?;
    let mut status_paths = status
        .entries
        .iter()
        .map(|entry| native_path_bytes(entry.path().as_path()))
        .collect::<Vec<_>>();
    status_paths.sort();
    let mut branches = Vec::new();
    let mut stashes = Vec::new();
    for section in snapshot.refs.iter() {
        match section {
            RefsSectionData::Branches { rows, .. } => {
                branches.extend(rows.iter().map(|row| row.id.as_bytes().to_vec()));
            }
            RefsSectionData::Stashes(rows) => {
                stashes.extend(rows.iter().map(|entry| StashEntryFact {
                    selector: entry.selector.clone(),
                    object_id: entry.id.0.clone(),
                    subject: entry.subject.clone(),
                }));
            }
            _ => {}
        }
    }
    Some(StashFacts {
        revision: snapshot.revision,
        worktree: repository.worktree.worktree_root().as_path().to_path_buf(),
        common_git_dir: repository
            .worktree
            .repository()
            .common_git_dir()
            .as_path()
            .to_path_buf(),
        head_object_id: match &repository.head {
            devmil_git::types::HeadState::Attached { target, .. }
            | devmil_git::types::HeadState::Detached { target } => Some(target.clone()),
            devmil_git::types::HeadState::Unborn { .. } => None,
        },
        head_branch: match &status.branch.head {
            devmil_git::status::BranchHead::Attached(name) => {
                String::from_utf8(name.as_bytes().to_vec()).ok()
            }
            devmil_git::status::BranchHead::Detached
            | devmil_git::status::BranchHead::Unborn { .. } => None,
        },
        working_tree: status.working_tree,
        status_paths,
        branches,
        stashes,
    })
}

fn entry_still_matches(plan: &StashPlan, current: &StashFacts) -> bool {
    plan.entry
        .as_ref()
        .is_none_or(|expected| current.stashes.iter().any(|entry| entry == expected))
}

fn resolve_object(worktree: &Path, revision: &str) -> Option<ObjectId> {
    devmil_git::probes::resolve(
        std::ffi::OsStr::new("git"),
        worktree,
        revision,
        &mut crate::git_probe::ProbeExecutor::new(None),
    )
    .ok()
    .flatten()
}

fn has_unmerged_paths(worktree: &Path) -> bool {
    devmil_git::probes::unmerged_paths(
        std::ffi::OsStr::new("git"),
        worktree,
        &mut crate::git_probe::ProbeExecutor::new(None),
    )
    .is_ok_and(|paths| !paths.is_empty())
}

pub(crate) fn active_conflict(common_git_dir: &Path) -> Option<ActiveStashConflict> {
    let path = common_git_dir.join(ACTIVE_CONFLICT_PATH);
    let metadata = fs::symlink_metadata(&path).ok()?;
    if metadata.file_type().is_symlink() || !metadata.is_file() || metadata.len() > 16 * 1024 {
        return None;
    }
    let value: ActiveStashConflict = serde_json::from_slice(&fs::read(path).ok()?).ok()?;
    (value.schema == ACTIVE_CONFLICT_SCHEMA
        && ObjectId::parse(value.stash_oid.clone()).is_ok()
        && ObjectId::parse(value.original_head.clone()).is_ok())
    .then_some(value)
}

pub(crate) fn finish_active_conflict(common_git_dir: &Path) -> bool {
    let path = common_git_dir.join(ACTIVE_CONFLICT_PATH);
    match fs::remove_file(path) {
        Ok(()) => true,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => true,
        Err(_) => false,
    }
}

/// Reapplying after pull keeps the new HEAD on abort and retains the recovery stash.
pub(crate) fn begin_pull_reapply(
    common_git_dir: &Path,
    stash_oid: &str,
    head: &str,
    branch: Option<String>,
) -> bool {
    if active_conflict(common_git_dir).is_some() {
        return false;
    }
    write_active_conflict(
        common_git_dir,
        ActiveStashConflict {
            schema: ACTIVE_CONFLICT_SCHEMA.to_owned(),
            kind: ActiveStashConflictKind::Apply,
            stash_oid: stash_oid.to_owned(),
            original_head: head.to_owned(),
            original_branch: branch,
        },
    )
    .is_ok()
}

fn write_active_conflict(common_git_dir: &Path, value: ActiveStashConflict) -> Result<(), ()> {
    let bytes = serde_json::to_vec(&value).map_err(|_| ())?;
    let name = ACTIVE_CONFLICT_PATH
        .strip_prefix("gitlama/")
        .expect("the active stash conflict lives in the repository store");
    crate::private_store::PrivateDir::repository(common_git_dir, &[])
        // Never replace another in-flight stash recovery (including one from
        // a different linked worktree), or an unreadable recovery marker.
        .and_then(|store| store.write_new(name, &bytes))
        .map_err(|_| ())
}

fn relative_path(bytes: Vec<u8>) -> Result<RepositoryRelativePath, NativeStashFailureKind> {
    devmil_git::native_bytes::bytes_to_path_buf(&bytes)
        .ok()
        .and_then(|path| RepositoryRelativePath::new(path).ok())
        .ok_or(NativeStashFailureKind::InvalidRequest)
}

fn native_path_bytes(path: &Path) -> Vec<u8> {
    devmil_git::native_bytes::path_to_bytes(path)
}

pub(crate) fn cancel(session_id: u64, token: u64) -> bool {
    lock_stashes().cancel(session_id, token)
}

pub(crate) fn dismiss_session(session_id: u64) {
    lock_stashes().dismiss_session(session_id);
}

fn finish(session_id: u64, token: u64) {
    lock_stashes().finish(session_id, token);
}

fn preview_failure(kind: NativeStashFailureKind) -> NativeStashPreviewResult {
    NativeStashPreviewResult {
        preview: None,
        failure: Some(NativeStashFailure { kind }),
    }
}

fn execution_failure(kind: NativeStashFailureKind) -> NativeStashExecutionResult {
    NativeStashExecutionResult {
        state: NativeStashExecutionState::Failed,
        failure: Some(NativeStashFailure { kind }),
        activity_ids: Vec::new(),
        stash_created: false,
        checkout_completed: false,
        reapply_completed: false,
        stash_retained: false,
    }
}

fn stale_result() -> NativeStashExecutionResult {
    NativeStashExecutionResult {
        state: NativeStashExecutionState::Stale,
        failure: Some(NativeStashFailure {
            kind: NativeStashFailureKind::Stale,
        }),
        activity_ids: Vec::new(),
        stash_created: false,
        checkout_completed: false,
        reapply_completed: false,
        stash_retained: false,
    }
}

/// A stash apply, pop or auto-stash checkout stops at conflicts; continuing drops the applied
/// stash, aborting restores the state before it.
pub(crate) struct StashConflict;

pub(crate) static STASH_CONFLICT: StashConflict = StashConflict;

impl crate::interrupted::InterruptedOperation for StashConflict {
    fn kind(&self) -> crate::conflict::NativeConflictOperationKind {
        crate::conflict::NativeConflictOperationKind::Stash
    }

    fn offers(&self, action: crate::conflict::NativeConflictSequencerAction) -> bool {
        action != crate::conflict::NativeConflictSequencerAction::Skip
    }

    fn active(&self, common_git_dir: &Path) -> bool {
        active_conflict(common_git_dir).is_some()
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

        use crate::stash::ActiveStashConflictKind;

        let Some(active) = crate::stash::active_conflict(common_git_dir) else {
            return crate::conflict::continuation_failure(
                NativeConflictFailureKind::NoActiveOperation,
            );
        };
        let selector = matches!(
            active.kind,
            ActiveStashConflictKind::Pop | ActiveStashConflictKind::AutoStashCheckout
        )
        .then(|| stash_selector_for_oid(worktree, &active.stash_oid))
        .flatten();
        if action == NativeConflictSequencerAction::Continue
            && matches!(
                active.kind,
                ActiveStashConflictKind::Pop | ActiveStashConflictKind::AutoStashCheckout
            )
            && selector.is_none()
        {
            return crate::conflict::continuation_failure(NativeConflictFailureKind::Stale);
        }

        let mut commands = Vec::<Vec<String>>::new();
        match action {
            NativeConflictSequencerAction::Continue => {
                if let Some(selector) = selector {
                    commands.push(vec!["stash".to_owned(), "drop".to_owned(), selector]);
                }
            }
            NativeConflictSequencerAction::Abort => match active.kind {
                ActiveStashConflictKind::Apply | ActiveStashConflictKind::Pop => {
                    commands.push(vec![
                        "reset".to_owned(),
                        "--hard".to_owned(),
                        active.original_head.clone(),
                    ]);
                }
                ActiveStashConflictKind::AutoStashCheckout => {
                    commands.push(vec![
                        "reset".to_owned(),
                        "--hard".to_owned(),
                        "HEAD".to_owned(),
                    ]);
                    commands.push(if let Some(branch) = active.original_branch.as_ref() {
                        vec!["switch".to_owned(), branch.clone()]
                    } else {
                        vec![
                            "checkout".to_owned(),
                            "--detach".to_owned(),
                            active.original_head.clone(),
                        ]
                    });
                    commands.push(vec![
                        "stash".to_owned(),
                        "apply".to_owned(),
                        "--index".to_owned(),
                        active.stash_oid.clone(),
                    ]);
                    let Some(selector) = selector else {
                        return crate::conflict::continuation_failure(
                            NativeConflictFailureKind::Stale,
                        );
                    };
                    commands.push(vec!["stash".to_owned(), "drop".to_owned(), selector]);
                }
            },
            NativeConflictSequencerAction::Skip => unreachable!(),
        }

        let cancellation = AtomicBool::new(false);
        let Ok(lease) = repository.begin_mutation_with_cancellation(&cancellation) else {
            return crate::conflict::continuation_failure(NativeConflictFailureKind::Git);
        };
        let sink = activity.sink();
        let mut activity_ids = Vec::new();
        let mut succeeded = true;
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
            succeeded = crate::stash::finish_active_conflict(common_git_dir);
        }
        crate::conflict::reload(repository);
        let conflicts = repository
            .snapshot()
            .status
            .as_ref()
            .is_some_and(|status| status.entries.iter().any(|entry| entry.is_conflicted()));
        let state = crate::conflict::native_continuation_state(
            if succeeded && action == NativeConflictSequencerAction::Abort {
                MutationState::Aborted
            } else if succeeded {
                MutationState::Completed
            } else if conflicts {
                MutationState::Conflict
            } else {
                MutationState::Failed
            },
        );
        NativeConflictContinuationResult {
            state,
            activity_ids,
            failure: (!succeeded && !conflicts).then_some(NativeConflictFailure {
                kind: NativeConflictFailureKind::Git,
            }),
        }
    }
}

fn stash_selector_for_oid(worktree: &Path, oid: &str) -> Option<String> {
    let mut executor = crate::git_probe::ProbeExecutor::new(None);
    for index in 0..64 {
        let selector = format!("stash@{{{index}}}");
        let object = devmil_git::probes::resolve(
            std::ffi::OsStr::new("git"),
            worktree,
            &selector,
            &mut executor,
        )
        .ok()??;
        if object.as_str() == oid {
            return Some(selector);
        }
    }
    None
}

crate::family_failures!(NativeStashFailureKind, "stash", {
    InvalidRequest => InvalidRequest,
    NothingToStash => Precondition,
    MissingStash => NotFound,
    Stale => Stale,
    Conflict => Conflict,
    Canceled => Canceled,
    TimedOut => TimedOut,
    MissingGit => Unavailable,
    Failed => Git,
    Read => Read,
    Write => Write,
});

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::outcome::MutationTerminalState;

    #[test]
    fn pull_reapply_does_not_overwrite_another_or_malformed_recovery_marker() {
        let fixture = crate::test_support::GitFixture::new();
        let common = fixture.0.join(".git");
        let first = "a".repeat(40);
        assert!(begin_pull_reapply(
            &common,
            &first,
            &"b".repeat(40),
            Some("main".into())
        ));
        assert!(!begin_pull_reapply(
            &common,
            &"c".repeat(40),
            &"d".repeat(40),
            Some("main".into())
        ));
        assert_eq!(active_conflict(&common).unwrap().stash_oid, first);
        let path = common.join(ACTIVE_CONFLICT_PATH);
        fs::write(&path, b"interrupted marker").unwrap();
        assert!(!begin_pull_reapply(
            &common,
            &first,
            &"b".repeat(40),
            Some("main".into())
        ));
        assert_eq!(fs::read(path).unwrap(), b"interrupted marker");
    }

    #[test]
    fn an_uncertain_stash_stays_uncertain() {
        let outcome = MutationOutcome::from_terminal(MutationTerminalState::OutcomeUncertain)
            .with_failure(Some(NativeStashFailureKind::Write));
        assert_eq!(
            outcome.product_failure(),
            Some(crate::domain::failure::ProductFailure {
                category: crate::domain::failure::FailureCategory::Write,
                detail: "stash.Write",
            })
        );
        let result = execution_result(outcome, vec![7], &StepProgress::default());
        assert_eq!(result.state, NativeStashExecutionState::OutcomeUncertain);
        assert_eq!(
            result.failure.map(|failure| failure.kind),
            Some(NativeStashFailureKind::Write)
        );
        assert_eq!(result.activity_ids, ["7"]);
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{conflicts::*, history::*, session::*, stash::*};
    use crate::dto::*;

    use crate::conflict::{
        NativeConflictContinuationState, NativeConflictOperationKind,
        NativeConflictSequencerAction, NativeConflictSideChoice,
    };

    use crate::graph::HISTORY_PAGE_CAPACITY;

    use crate::stash::{
        NativeStashExecutionState, NativeStashFailureKind, NativeStashKind, NativeStashRequest,
    };

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[test]
    fn stash_scope_rename_and_selector_races_preserve_oid_identity() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        fs::write(fixture.0.join("other.txt"), b"other base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        fs::write(fixture.0.join("tracked.txt"), b"staged\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        fs::write(fixture.0.join("tracked.txt"), b"unstaged after staged\n").unwrap();
        fs::write(fixture.0.join("untracked.bin"), b"untracked\n").unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_207,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let push = repository_session_stash_preview(
            session.session_id,
            session.generation,
            NativeStashRequest {
                kind: NativeStashKind::Push,
                message: Some("mixed scope".into()),
                selector: None,
                object_id: None,
                paths: Vec::new(),
                include_untracked: true,
                keep_index: true,
                target_branch: None,
            },
        )
        .preview
        .unwrap();
        assert_eq!(push.affected_paths, 2);
        assert_eq!(
            push.commands[0].arguments,
            [
                "stash",
                "push",
                "--include-untracked",
                "--keep-index",
                "-m",
                "mixed scope",
            ]
        );
        assert_eq!(
            repository_session_stash_execute(session.session_id, session.generation, push.token,)
                .state,
            NativeStashExecutionState::Completed
        );
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"staged\n"
        );
        assert!(!fixture.0.join("untracked.bin").exists());
        assert_eq!(
            fs::read(fixture.0.join("other.txt")).unwrap(),
            b"other base\n"
        );

        let refreshed = refresh_session(&session);
        assert_eq!(refreshed.refs.stashes.len(), 1);
        let stash = refreshed.refs.stashes[0].clone();
        let history = repository_session_history_load(
            session.session_id,
            session.generation,
            true,
            HISTORY_PAGE_CAPACITY as u32,
            false,
        );
        let history_page = history.page.expect("history page");
        let index_id = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "stash@{0}^2"]))
            .unwrap()
            .trim()
            .to_owned();
        let untracked_id =
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "stash@{0}^3"]))
                .unwrap()
                .trim()
                .to_owned();
        assert!(!history_page
            .rows
            .iter()
            .any(|row| row.object_id == index_id));
        assert!(!history_page
            .rows
            .iter()
            .any(|row| row.object_id == untracked_id));
        assert_eq!(history_page.collapsed_commits, 0);
        let stash_row = history_page
            .rows
            .iter()
            .find(|row| row.object_id == stash.object_id)
            .expect("stash commit is part of all-reference history");
        assert!(stash_row.refs.contains(&b"stash@{0}".to_vec()));
        assert_eq!(stash_row.shape, NativeHistoryNodeShape::Stash);
        // A collapsed stash is a leaf on its base commit: no edge to its
        // index or untracked commits, and no lane held for them below it.
        let stash_segments = history_page
            .segments
            .iter()
            .filter(|segment| segment.from_object_id == stash.object_id)
            .collect::<Vec<_>>();
        assert_eq!(stash_segments.len(), 1);
        assert_eq!(stash_segments[0].to_object_id, stash_row.parents[0]);
        assert_eq!(history_page.lane_count, 2);
        let expanded = repository_session_history_collapse(
            session.session_id,
            session.generation,
            history_page.request_id,
            stash.object_id.clone(),
            0,
            HISTORY_PAGE_CAPACITY as u32,
        )
        .page
        .expect("expanded stash history");
        assert!(expanded.rows.iter().any(|row| row.object_id == index_id));
        assert!(expanded
            .rows
            .iter()
            .any(|row| row.object_id == untracked_id));
        let combined = repository_session_history_collapse(
            session.session_id,
            session.generation,
            history_page.request_id,
            stash.object_id.clone(),
            0,
            HISTORY_PAGE_CAPACITY as u32,
        )
        .page
        .expect("combined stash history");
        assert!(!combined.rows.iter().any(|row| row.object_id == index_id));
        assert!(!combined
            .rows
            .iter()
            .any(|row| row.object_id == untracked_id));
        let rename = repository_session_stash_preview(
            session.session_id,
            session.generation,
            NativeStashRequest {
                kind: NativeStashKind::Rename,
                message: Some("renamed checkpoint".into()),
                selector: Some(String::from_utf8(stash.selector.clone()).unwrap()),
                object_id: Some(stash.object_id.clone()),
                paths: Vec::new(),
                include_untracked: false,
                keep_index: false,
                target_branch: None,
            },
        )
        .preview
        .unwrap();
        assert_eq!(rename.commands.len(), 2);
        assert_eq!(
            repository_session_stash_execute(session.session_id, session.generation, rename.token,)
                .state,
            NativeStashExecutionState::Completed
        );
        assert!(
            String::from_utf8(transfer_git(&fixture.0, &["stash", "list"]))
                .unwrap()
                .contains("renamed checkpoint")
        );

        let refreshed = refresh_session(&session);
        let renamed = refreshed.refs.stashes[0].clone();
        let drop_preview = repository_session_stash_preview(
            session.session_id,
            session.generation,
            NativeStashRequest {
                kind: NativeStashKind::Drop,
                message: None,
                selector: Some(String::from_utf8(renamed.selector).unwrap()),
                object_id: Some(renamed.object_id),
                paths: Vec::new(),
                include_untracked: false,
                keep_index: false,
                target_branch: None,
            },
        )
        .preview
        .unwrap();
        fs::write(fixture.0.join("newer.txt"), b"newer\n").unwrap();
        transfer_git(&fixture.0, &["stash", "push", "-u", "-m", "newer"]);
        refresh_session(&session);
        assert_eq!(
            repository_session_stash_execute(
                session.session_id,
                session.generation,
                drop_preview.token,
            )
            .state,
            NativeStashExecutionState::Stale
        );
        let list = String::from_utf8(transfer_git(&fixture.0, &["stash", "list"])).unwrap();
        assert!(list.contains("newer"));
        assert!(list.contains("renamed checkpoint"));
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn selected_stash_preserves_unselected_changes_and_rejects_ambiguous_untracked_scope() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(fixture.0.join("selected.txt"), b"selected base\n").unwrap();
        fs::write(fixture.0.join("remaining.txt"), b"remaining base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        fs::write(fixture.0.join("selected.txt"), b"selected dirty\n").unwrap();
        fs::write(fixture.0.join("remaining.txt"), b"remaining dirty\n").unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_212,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let ambiguous = repository_session_stash_preview(
            session.session_id,
            session.generation,
            NativeStashRequest {
                kind: NativeStashKind::Push,
                message: None,
                selector: None,
                object_id: None,
                paths: vec![b"selected.txt".to_vec()],
                include_untracked: true,
                keep_index: false,
                target_branch: None,
            },
        );
        assert_eq!(
            ambiguous.failure.unwrap().kind,
            NativeStashFailureKind::InvalidRequest
        );
        let preview = repository_session_stash_preview(
            session.session_id,
            session.generation,
            NativeStashRequest {
                kind: NativeStashKind::Push,
                message: Some("selected only".into()),
                selector: None,
                object_id: None,
                paths: vec![b"selected.txt".to_vec()],
                include_untracked: false,
                keep_index: false,
                target_branch: None,
            },
        )
        .preview
        .unwrap();
        assert_eq!(preview.affected_paths, 1);
        assert_eq!(
            repository_session_stash_execute(session.session_id, session.generation, preview.token)
                .state,
            NativeStashExecutionState::Completed
        );
        assert_eq!(
            fs::read(fixture.0.join("selected.txt")).unwrap(),
            b"selected base\n"
        );
        assert_eq!(
            fs::read(fixture.0.join("remaining.txt")).unwrap(),
            b"remaining dirty\n"
        );
        assert_eq!(
            transfer_git(&fixture.0, &["show", "stash@{0}:selected.txt"]),
            b"selected dirty\n"
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn detached_commit_checkout_stash_choices_preserve_index_worktree_and_untracked() {
        for kind in [
            NativeStashKind::StashCheckoutCommit,
            NativeStashKind::AutoStashCheckoutCommit,
        ] {
            let fixture = GitFixture::new();
            let git = |args: &[&str]| transfer_git(&fixture.0, args);
            git(&["config", "user.name", "GitLama Test"]);
            git(&["config", "user.email", "gitlama@example.invalid"]);
            fs::write(fixture.0.join("tracked"), b"base\n").unwrap();
            git(&["add", "."]);
            git(&["commit", "-qm", "base"]);
            let target = String::from_utf8(git(&["rev-parse", "HEAD"]))
                .unwrap()
                .trim()
                .to_owned();
            fs::write(fixture.0.join("other"), b"new commit\n").unwrap();
            git(&["add", "."]);
            git(&["commit", "-qm", "newer"]);
            let branch = String::from_utf8(git(&["branch", "--show-current"]))
                .unwrap()
                .trim()
                .to_owned();
            let branch_head = git(&["rev-parse", "HEAD"]);
            fs::write(fixture.0.join("tracked"), b"staged\n").unwrap();
            git(&["add", "tracked"]);
            fs::write(fixture.0.join("tracked"), b"unstaged\n").unwrap();
            fs::write(fixture.0.join("untracked"), b"untracked\n").unwrap();
            let session = repository_session_open_with_options(
                fixture.0.clone(),
                1601,
                RepositoryOptions {
                    watch: false,
                    ..RepositoryOptions::default()
                },
                ActivityStore::default(),
            )
            .session
            .unwrap();
            wait_for_ready(&session);
            let preview = repository_session_stash_preview(
                session.session_id,
                session.generation,
                NativeStashRequest {
                    kind,
                    message: None,
                    selector: None,
                    object_id: Some(target.clone()),
                    paths: vec![],
                    include_untracked: false,
                    keep_index: false,
                    target_branch: None,
                },
            )
            .preview
            .unwrap();
            assert!(preview.includes_untracked);
            assert_eq!(preview.affected_paths, 2);
            assert_eq!(
                preview.commands[1].arguments,
                ["checkout", "--detach", &target]
            );
            let result = repository_session_stash_execute(
                session.session_id,
                session.generation,
                preview.token,
            );
            assert_eq!(result.state, NativeStashExecutionState::Completed);
            assert!(result.stash_created && result.checkout_completed);
            assert!(git(&["branch", "--show-current"]).is_empty());
            assert_eq!(git(&["rev-parse", &branch]), branch_head);
            assert_eq!(
                String::from_utf8(git(&["rev-parse", "HEAD"]))
                    .unwrap()
                    .trim(),
                target
            );
            if kind == NativeStashKind::StashCheckoutCommit {
                assert!(result.stash_retained && !result.reapply_completed);
                assert_eq!(fs::read(fixture.0.join("tracked")).unwrap(), b"base\n");
                assert!(!fixture.0.join("untracked").exists());
                assert_eq!(git(&["show", "stash@{0}:tracked"]), b"unstaged\n");
                assert_eq!(git(&["show", "stash@{0}^2:tracked"]), b"staged\n");
                assert_eq!(git(&["show", "stash@{0}^3:untracked"]), b"untracked\n");
            } else {
                assert!(!result.stash_retained && result.reapply_completed);
                assert_eq!(git(&["show", ":tracked"]), b"staged\n");
                assert_eq!(fs::read(fixture.0.join("tracked")).unwrap(), b"unstaged\n");
                assert_eq!(
                    fs::read(fixture.0.join("untracked")).unwrap(),
                    b"untracked\n"
                );
                assert!(git(&["stash", "list"]).is_empty());
            }
            assert!(repository_session_close(session.session_id, session.generation).accepted);
        }
    }

    #[test]
    fn detached_commit_checkout_does_not_consume_an_old_stash_for_submodule_only_edits() {
        let fixture = GitFixture::new();
        let git = |args: &[&str]| transfer_git(&fixture.0, args);
        git(&["config", "user.name", "GitLama Test"]);
        git(&["config", "user.email", "gitlama@example.invalid"]);
        fs::create_dir(fixture.0.join("sub")).unwrap();
        git(&["-C", "sub", "init", "-q"]);
        git(&["-C", "sub", "config", "user.name", "GitLama Test"]);
        git(&[
            "-C",
            "sub",
            "config",
            "user.email",
            "gitlama@example.invalid",
        ]);
        fs::write(fixture.0.join("sub/file"), b"sub base\n").unwrap();
        git(&["-C", "sub", "add", "."]);
        git(&["-C", "sub", "commit", "-qm", "sub base"]);
        fs::write(fixture.0.join("tracked"), b"base\n").unwrap();
        git(&["add", "."]);
        git(&["commit", "-qm", "base"]);
        let target = String::from_utf8(git(&["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(fixture.0.join("tracked"), b"old saved edits\n").unwrap();
        git(&["stash", "push", "-qm", "existing stash"]);
        let old_stash = git(&["rev-parse", "refs/stash"]);
        fs::write(fixture.0.join("sub/file"), b"sub local edits\n").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1603,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let preview = repository_session_stash_preview(
            session.session_id,
            session.generation,
            NativeStashRequest {
                kind: NativeStashKind::AutoStashCheckoutCommit,
                message: None,
                selector: None,
                object_id: Some(target),
                paths: vec![],
                include_untracked: false,
                keep_index: false,
                target_branch: None,
            },
        )
        .preview
        .unwrap();
        let result =
            repository_session_stash_execute(session.session_id, session.generation, preview.token);
        assert_eq!(result.state, NativeStashExecutionState::Failed);
        assert_eq!(
            result.failure.unwrap().kind,
            NativeStashFailureKind::NothingToStash
        );
        assert!(!result.stash_created && !result.checkout_completed && !result.reapply_completed);
        assert_eq!(git(&["rev-parse", "refs/stash"]), old_stash);
        assert_eq!(fs::read(fixture.0.join("tracked")).unwrap(), b"base\n");
        assert_eq!(
            fs::read(fixture.0.join("sub/file")).unwrap(),
            b"sub local edits\n"
        );
        assert!(!git(&["branch", "--show-current"]).is_empty());
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn detached_commit_checkout_retains_stash_on_reapply_conflict() {
        let fixture = GitFixture::new();
        let git = |args: &[&str]| transfer_git(&fixture.0, args);
        git(&["config", "user.name", "GitLama Test"]);
        git(&["config", "user.email", "gitlama@example.invalid"]);
        fs::write(fixture.0.join("tracked"), b"older\n").unwrap();
        git(&["add", "."]);
        git(&["commit", "-qm", "older"]);
        let target = String::from_utf8(git(&["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(fixture.0.join("tracked"), b"newer\n").unwrap();
        git(&["add", "."]);
        git(&["commit", "-qm", "newer"]);
        fs::write(fixture.0.join("tracked"), b"local edits\n").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1602,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let preview = repository_session_stash_preview(
            session.session_id,
            session.generation,
            NativeStashRequest {
                kind: NativeStashKind::AutoStashCheckoutCommit,
                message: None,
                selector: None,
                object_id: Some(target),
                paths: vec![],
                include_untracked: false,
                keep_index: false,
                target_branch: None,
            },
        )
        .preview
        .unwrap();
        let result =
            repository_session_stash_execute(session.session_id, session.generation, preview.token);
        assert_eq!(result.state, NativeStashExecutionState::Conflict);
        assert!(result.stash_created && result.checkout_completed && result.stash_retained);
        assert!(!result.reapply_completed);
        assert_eq!(git(&["show", "stash@{0}:tracked"]), b"local edits\n");
        assert!(git(&["branch", "--show-current"]).is_empty());
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn auto_stash_checkout_reapplies_tracked_and_untracked_bytes() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&fixture.0, &["branch", "topic"]);
        fs::write(fixture.0.join("tracked.txt"), b"dirty tracked\n").unwrap();
        fs::write(fixture.0.join("untracked.bin"), b"dirty untracked\n").unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_208,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let preview = repository_session_stash_preview(
            session.session_id,
            session.generation,
            NativeStashRequest {
                kind: NativeStashKind::AutoStashCheckout,
                message: None,
                selector: None,
                object_id: None,
                paths: Vec::new(),
                include_untracked: false,
                keep_index: false,
                target_branch: Some("topic".into()),
            },
        )
        .preview
        .unwrap();
        assert_eq!(preview.commands.len(), 2);
        let result =
            repository_session_stash_execute(session.session_id, session.generation, preview.token);
        assert_eq!(result.state, NativeStashExecutionState::Completed);
        assert!(result.stash_created);
        assert!(result.checkout_completed);
        assert!(result.reapply_completed);
        assert!(!result.stash_retained);
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["branch", "--show-current"]))
                .unwrap()
                .trim(),
            "topic"
        );
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"dirty tracked\n"
        );
        assert_eq!(
            fs::read(fixture.0.join("untracked.bin")).unwrap(),
            b"dirty untracked\n"
        );
        assert!(
            String::from_utf8(transfer_git(&fixture.0, &["stash", "list"]))
                .unwrap()
                .is_empty()
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn auto_stash_checkout_recovers_failed_checkout_and_retains_failed_reapply() {
        let checkout_fixture = GitFixture::new();
        transfer_git(
            &checkout_fixture.0,
            &["config", "user.name", "GitLama Test"],
        );
        transfer_git(
            &checkout_fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(checkout_fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&checkout_fixture.0, &["add", "."]);
        transfer_git(&checkout_fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&checkout_fixture.0, &["branch", "vanishing"]);
        fs::write(checkout_fixture.0.join("tracked.txt"), b"dirty\n").unwrap();
        let checkout_session = repository_session_open_with_options(
            checkout_fixture.0.clone(),
            1_210,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&checkout_session);
        let checkout_preview = repository_session_stash_preview(
            checkout_session.session_id,
            checkout_session.generation,
            NativeStashRequest {
                kind: NativeStashKind::AutoStashCheckout,
                message: None,
                selector: None,
                object_id: None,
                paths: Vec::new(),
                include_untracked: false,
                keep_index: false,
                target_branch: Some("vanishing".into()),
            },
        )
        .preview
        .unwrap();
        transfer_git(&checkout_fixture.0, &["branch", "-D", "vanishing"]);
        let checkout_result = repository_session_stash_execute(
            checkout_session.session_id,
            checkout_session.generation,
            checkout_preview.token,
        );
        assert_eq!(checkout_result.state, NativeStashExecutionState::Failed);
        assert!(checkout_result.stash_created);
        assert!(!checkout_result.checkout_completed);
        assert!(checkout_result.reapply_completed);
        assert!(!checkout_result.stash_retained);
        assert_eq!(
            fs::read(checkout_fixture.0.join("tracked.txt")).unwrap(),
            b"dirty\n"
        );
        assert!(
            String::from_utf8(transfer_git(&checkout_fixture.0, &["stash", "list"]))
                .unwrap()
                .is_empty()
        );
        assert!(
            repository_session_close(checkout_session.session_id, checkout_session.generation)
                .accepted
        );

        let reapply_fixture = GitFixture::new();
        transfer_git(&reapply_fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &reapply_fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(reapply_fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&reapply_fixture.0, &["add", "."]);
        transfer_git(&reapply_fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&reapply_fixture.0, &["switch", "-c", "topic"]);
        fs::write(reapply_fixture.0.join("tracked.txt"), b"topic\n").unwrap();
        transfer_git(&reapply_fixture.0, &["add", "tracked.txt"]);
        transfer_git(&reapply_fixture.0, &["commit", "-qm", "topic"]);
        transfer_git(&reapply_fixture.0, &["switch", "main"]);
        fs::write(reapply_fixture.0.join("tracked.txt"), b"dirty main\n").unwrap();
        let reapply_session = repository_session_open_with_options(
            reapply_fixture.0.clone(),
            1_211,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&reapply_session);
        let reapply_preview = repository_session_stash_preview(
            reapply_session.session_id,
            reapply_session.generation,
            NativeStashRequest {
                kind: NativeStashKind::AutoStashCheckout,
                message: None,
                selector: None,
                object_id: None,
                paths: Vec::new(),
                include_untracked: false,
                keep_index: false,
                target_branch: Some("topic".into()),
            },
        )
        .preview
        .unwrap();
        let reapply_result = repository_session_stash_execute(
            reapply_session.session_id,
            reapply_session.generation,
            reapply_preview.token,
        );
        assert_eq!(reapply_result.state, NativeStashExecutionState::Conflict);
        assert!(reapply_result.stash_created);
        assert!(reapply_result.checkout_completed);
        assert!(!reapply_result.reapply_completed);
        assert!(reapply_result.stash_retained);
        assert!(!transfer_git(&reapply_fixture.0, &["stash", "list"]).is_empty());
        assert!(!transfer_git(
            &reapply_fixture.0,
            &["diff", "--name-only", "--diff-filter=U"],
        )
        .is_empty());
        assert!(
            repository_session_close(reapply_session.session_id, reapply_session.generation)
                .accepted
        );
        let reopened = repository_session_open_with_options(
            reapply_fixture.0.clone(),
            1_212,
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
        assert_eq!(conflicts.operation, NativeConflictOperationKind::Stash);
        let aborted = repository_session_conflict_continue(
            reopened.session_id,
            reopened.generation,
            NativeConflictSequencerAction::Abort,
        );
        assert_eq!(aborted.state, NativeConflictContinuationState::Aborted);
        assert_eq!(
            String::from_utf8(transfer_git(
                &reapply_fixture.0,
                &["branch", "--show-current"]
            ))
            .unwrap()
            .trim(),
            "main"
        );
        assert_eq!(
            fs::read(reapply_fixture.0.join("tracked.txt")).unwrap(),
            b"dirty main\n"
        );
        assert!(transfer_git(&reapply_fixture.0, &["stash", "list"]).is_empty());
        assert!(repository_session_close(reopened.session_id, reopened.generation).accepted);
    }

    #[test]
    fn conflicted_stash_apply_keeps_the_selected_oid() {
        let fixture = GitFixture::new();
        transfer_git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        transfer_git(
            &fixture.0,
            &["config", "user.email", "gitlama@example.invalid"],
        );
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&fixture.0, &["branch", "topic"]);
        fs::write(fixture.0.join("tracked.txt"), b"stash version\n").unwrap();
        transfer_git(&fixture.0, &["stash", "push", "-m", "conflicting"]);
        let stash_oid = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "stash@{0}"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&fixture.0, &["switch", "topic"]);
        fs::write(fixture.0.join("tracked.txt"), b"topic version\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "topic conflict"]);

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_209,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let snapshot = wait_for_ready(&session);
        let stash = snapshot.refs.stashes[0].clone();
        assert_eq!(stash.object_id, stash_oid);
        let preview = repository_session_stash_preview(
            session.session_id,
            session.generation,
            NativeStashRequest {
                kind: NativeStashKind::Apply,
                message: None,
                selector: Some(String::from_utf8(stash.selector).unwrap()),
                object_id: Some(stash.object_id),
                paths: Vec::new(),
                include_untracked: false,
                keep_index: false,
                target_branch: None,
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            preview.selected_object_id.as_deref(),
            Some(stash_oid.as_str())
        );
        let result =
            repository_session_stash_execute(session.session_id, session.generation, preview.token);
        assert_eq!(result.state, NativeStashExecutionState::Conflict);
        assert!(result.stash_retained);
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "stash@{0}"],))
                .unwrap()
                .trim(),
            stash_oid
        );
        assert!(!transfer_git(&fixture.0, &["diff", "--name-only", "--diff-filter=U"],).is_empty());
        assert!(repository_session_close(session.session_id, session.generation).accepted);
        let reopened = repository_session_open_with_options(
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
        wait_for_ready(&reopened);
        let conflicts = repository_session_conflicts(reopened.session_id, reopened.generation)
            .snapshot
            .unwrap();
        assert_eq!(conflicts.operation, NativeConflictOperationKind::Stash);
        let aborted = repository_session_conflict_continue(
            reopened.session_id,
            reopened.generation,
            NativeConflictSequencerAction::Abort,
        );
        assert_eq!(aborted.state, NativeConflictContinuationState::Aborted);
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"topic version\n"
        );
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "stash@{0}"]))
                .unwrap()
                .trim(),
            stash_oid
        );
        assert!(transfer_git(&fixture.0, &["diff", "--name-only", "--diff-filter=U"]).is_empty());
        let pop_preview = repository_session_stash_preview(
            reopened.session_id,
            reopened.generation,
            NativeStashRequest {
                kind: NativeStashKind::Pop,
                message: None,
                selector: Some("stash@{0}".to_owned()),
                object_id: Some(stash_oid.clone()),
                paths: Vec::new(),
                include_untracked: false,
                keep_index: false,
                target_branch: None,
            },
        )
        .preview
        .unwrap();
        let popped = repository_session_stash_execute(
            reopened.session_id,
            reopened.generation,
            pop_preview.token,
        );
        assert_eq!(popped.state, NativeStashExecutionState::Conflict);
        let conflicts = repository_session_conflicts(reopened.session_id, reopened.generation)
            .snapshot
            .unwrap();
        let file = conflicts.files[0].clone();
        assert!(repository_session_conflict_choose_side(
            reopened.session_id,
            reopened.generation,
            file.path,
            file.fingerprint,
            NativeConflictSideChoice::Incoming,
        )
        .failure
        .is_none());
        let continued = repository_session_conflict_continue(
            reopened.session_id,
            reopened.generation,
            NativeConflictSequencerAction::Continue,
        );
        assert_eq!(continued.state, NativeConflictContinuationState::Completed);
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"stash version\n"
        );
        assert!(transfer_git(&fixture.0, &["stash", "list"]).is_empty());
        assert!(repository_session_close(reopened.session_id, reopened.generation).accepted);
    }
}
