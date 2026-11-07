//! Application-owned fetch, pull and push orchestration around shared typed Git commands.
pub use gitlama_contract::transfer::*;

use crate::activity::{allocate_activity_id, ActivityStore, ACTIVITY_STREAM_BYTE_CAPACITY};
use crate::credentials::AskpassLease;
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::dto::{
    NativeCloneCommandResult, NativeCloneFailure, NativeCloneFailureKind, NativeHostKeyResult,
};
use crate::operations::{coordinate_leased_mutation, coordinate_mutation, ExecutionFailure};
mod pull_stash;
use crate::preview_store::PreviewStore;
use crate::ssh_trust::{probe_host_key, trust_host_key, PendingHostKey};
use devmil_git::activity::{ActivityEventSink, ActivityStatus};
use devmil_git::auth::{
    shell_command_path, transfer_configuration, transfer_environment, Credentials,
    TransferAuthentication,
};
use devmil_git::clone::CloneSource;
use devmil_git::commands::remote::{
    command_shape, fetch_command_shape, parse_remote_ref_probe, prune_tracking_ref_command_shape,
    remote_ref_probe_command_shape, CommandShape, FetchOptions, FetchRequest, FetchScope,
    PullRequest, PullStrategy, PushForce, PushRefspec, PushRequest, RemoteName,
    RemoteOperationRequest,
};
use devmil_git::diagnosis::{
    confirm_case_collision, diagnose, updated_tracking_refs, DiagnosisKind,
};
use devmil_git::git_locks::is_lock_conflict;
use devmil_git::loading::refs::RefsSectionData;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::status::{BranchHead, WorkingTreeState};
use devmil_git::transfer::{
    classify_transfer_stderr, is_stale_lease_rejection, TransferFailureKind,
};
use devmil_git::types::{ObjectId, RefId};
use devmil_git::{Repository, RepositorySnapshot};
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, OnceLock};

const PREVIEW_CAPACITY_PER_SESSION: usize = 8;

#[derive(Clone, Debug, Eq, PartialEq)]
struct TransferFacts {
    worktree: PathBuf,
    common_git_dir: PathBuf,
    head_ref: Option<RefId>,
    head_oid: Option<ObjectId>,
    upstream: Option<Vec<u8>>,
    ahead: u64,
    behind: u64,
    working_tree: WorkingTreeState,
    remote_names: Vec<String>,
    remote_target: Option<ObjectId>,
}

#[derive(Clone)]
struct TransferPlan {
    request: NativeTransferRequest,
    remote: RemoteName,
    branch: Option<String>,
    operation: RemoteOperationRequest,
    facts: TransferFacts,
    expected_remote: Option<ObjectId>,
}

/// A previewed transfer and what a retry after an authentication or host-key failure needs.
struct OwnedTransfer {
    plan: TransferPlan,
    last_failure: Option<NativeTransferFailureKind>,
    pending_host_key: Option<PendingHostKey>,
    ssh_wrapper: Option<PathBuf>,
}

struct Transfers {
    previews: PreviewStore<OwnedTransfer>,
}

/// What a transfer of `kind` registers as its operation.
const fn operation_intent(kind: NativeTransferKind) -> crate::activity::OperationIntent {
    match kind {
        NativeTransferKind::Fetch => crate::activity::OperationIntent::Fetch,
        NativeTransferKind::Pull => crate::activity::OperationIntent::Pull,
        NativeTransferKind::Push
        | NativeTransferKind::PushTag
        | NativeTransferKind::DeleteTag
        | NativeTransferKind::DeleteBranch => crate::activity::OperationIntent::Push,
    }
}

static TRANSFERS: OnceLock<Mutex<Transfers>> = OnceLock::new();

fn transfers() -> &'static Mutex<Transfers> {
    TRANSFERS.get_or_init(|| {
        Mutex::new(Transfers {
            previews: PreviewStore::new(PREVIEW_CAPACITY_PER_SESSION),
        })
    })
}

fn lock_transfers() -> std::sync::MutexGuard<'static, Transfers> {
    transfers()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

pub(crate) fn preview(
    session_id: u64,
    _generation: u64,
    repository: &Repository,
    request: NativeTransferRequest,
) -> NativeTransferPreviewResult {
    let snapshot = repository.snapshot();
    let plan = match build_plan(request, &snapshot) {
        Ok(plan) => plan,
        Err(kind) => return preview_failure(kind),
    };
    let arguments = match preview_arguments(&plan) {
        Ok(arguments) => arguments,
        Err(kind) => return preview_failure(kind),
    };
    let token = lock_transfers().previews.issue(
        session_id,
        OwnedTransfer {
            plan: plan.clone(),
            last_failure: None,
            pending_host_key: None,
            ssh_wrapper: None,
        },
    );
    NativeTransferPreviewResult {
        preview: Some(NativeTransferPreview {
            token,
            kind: plan.request.kind,
            remote: plan.remote.as_str().to_owned(),
            branch: plan.branch.clone(),
            arguments,
            ahead: plan.facts.ahead,
            behind: plan.facts.behind,
            dirty: plan.facts.working_tree != WorkingTreeState::Clean,
            expected_remote_object_id: plan
                .expected_remote
                .as_ref()
                .map(|value| value.as_str().to_owned()),
            force_with_lease: plan.request.force_with_lease,
        }),
        failure: None,
    }
}

pub(crate) fn execute(
    session_id: u64,
    _generation: u64,
    token: u64,
    repository: &Repository,
    activity: &ActivityStore,
    credentials: Option<(Option<String>, Option<String>, Option<String>)>,
    background: bool,
) -> NativeTransferExecutionResult {
    let (plan, cancellation, ssh_wrapper) = {
        let mut registry = lock_transfers();
        let Some(owned) = registry.previews.get_mut(session_id, token) else {
            return execution_failure(NativeTransferFailureKind::InvalidRequest);
        };
        // Only a fetch leaves the work tree and the remote untouched.
        if owned.running
            || (background && owned.value.plan.request.kind != NativeTransferKind::Fetch)
        {
            return execution_failure(NativeTransferFailureKind::InvalidRequest);
        }
        owned.running = true;
        owned.cancellation.store(false, Ordering::Release);
        (
            owned.value.plan.clone(),
            Arc::clone(&owned.cancellation),
            owned.value.ssh_wrapper.clone(),
        )
    };
    let current = repository.snapshot();
    let current_plan = build_plan(plan.request.clone(), &current);
    if current_plan.as_ref().map(plan_signature).ok() != Some(plan_signature(&plan)) {
        finish_attempt(session_id, token, true);
        return execution_failure(NativeTransferFailureKind::Stale);
    }
    let credential_values = match credentials {
        Some((username, password, credential_token)) => {
            match Credentials::new(username, password, credential_token) {
                Some(value) => Some(value),
                None => {
                    finish_attempt(session_id, token, false);
                    return execution_failure(NativeTransferFailureKind::InvalidRequest);
                }
            }
        }
        None => None,
    };
    let lease = match credential_values.as_ref() {
        Some(credentials) => match AskpassLease::new(token, credentials) {
            Ok(lease) => Some(lease),
            Err(_) => {
                finish_attempt(session_id, token, false);
                return execution_failure(NativeTransferFailureKind::CredentialBrokerUnavailable);
            }
        },
        None => None,
    };
    let command = match command_for_plan(
        &plan,
        lease.as_ref().map(AskpassLease::executable),
        ssh_wrapper.as_deref(),
    ) {
        Ok(command) => command,
        Err(kind) => {
            finish_attempt(session_id, token, false);
            return execution_failure(kind);
        }
    };
    let activity_id = crate::activity::allocate_operation_id_from(
        operation_intent(plan.request.kind),
        if background {
            crate::activity::OperationOrigin::Background
        } else {
            crate::activity::OperationOrigin::User
        },
    );
    let sink = activity.sink();
    let mut publish = move |event| sink(event);
    let mut process_failure = None;
    let mut diagnosis = None;
    let mut stash = None;
    let outcome = coordinate_leased_mutation(
        repository,
        cancellation.as_ref(),
        |cancellation, mutation| {
            if plan.request.stash_before_pull {
                stash = pull_stash::prepare(
                    &plan,
                    repository,
                    mutation,
                    cancellation,
                    activity,
                    &mut process_failure,
                )?;
                let clean = mutation
                    .fresh_status(None)
                    .ok()
                    .flatten()
                    .is_some_and(|status| {
                        status.working_tree == WorkingTreeState::Clean
                            && status.operations.is_empty()
                    });
                if process_failure.is_some() || !clean {
                    if let Some(saved) = stash.as_mut() {
                        pull_stash::reapply(saved, &plan, repository, mutation, activity);
                    }
                    process_failure.get_or_insert(NativeTransferFailureKind::DirtyWorktree);
                    return Err(ExecutionFailure::Definite);
                }
            }
            let result = ActivityGitRunner::run_private(
                command,
                activity_id,
                Some(cancellation),
                &mut publish,
            );
            let pulled = match result.activity.status {
                ActivityStatus::Succeeded { .. } => Ok(()),
                ActivityStatus::Canceled { .. } => {
                    process_failure = Some(NativeTransferFailureKind::Canceled);
                    Err(ExecutionFailure::Canceled)
                }
                ActivityStatus::TimedOut { .. } => {
                    process_failure = Some(NativeTransferFailureKind::TimedOut);
                    Err(ExecutionFailure::Definite)
                }
                ActivityStatus::LaunchError { .. } => {
                    process_failure = Some(NativeTransferFailureKind::MissingGit);
                    Err(ExecutionFailure::Definite)
                }
                ActivityStatus::Failed { .. } | ActivityStatus::Running => {
                    #[cfg(test)]
                    if lease.is_some() {
                        let diagnostic =
                            String::from_utf8_lossy(&result.stderr.bytes).to_ascii_lowercase();
                        eprintln!(
                            "credential retry diagnostic: askpass={} spawn={} missing={} connect={} http401={} auth={} length={}",
                            diagnostic.contains("askpass"),
                            diagnostic.contains("spawn"),
                            diagnostic.contains("no such file"),
                            diagnostic.contains("connect"),
                            diagnostic.contains("401"),
                            diagnostic.contains("authentication"),
                            result.stderr.bytes.len(),
                        );
                    }
                    if plan.request.kind == NativeTransferKind::DeleteBranch
                        && is_stale_lease_rejection(&result.stderr.bytes)
                        && remote_branch_already_deleted(
                            &plan,
                            lease.as_ref().map(AskpassLease::executable),
                            ssh_wrapper.as_deref(),
                            cancellation,
                            &mut publish,
                        )
                    {
                        return Ok(());
                    }
                    diagnosis = transfer_diagnosis(&result.stderr.bytes, &plan, repository);
                    process_failure = Some(match classify_transfer_stderr(&result.stderr.bytes) {
                        TransferFailureKind::Authentication => {
                            NativeTransferFailureKind::Authentication
                        }
                        TransferFailureKind::HostKey => NativeTransferFailureKind::HostKey,
                        TransferFailureKind::Canceled => NativeTransferFailureKind::Canceled,
                        TransferFailureKind::Launch => NativeTransferFailureKind::MissingGit,
                        TransferFailureKind::Git if is_lock_conflict(&result.stderr.bytes) => {
                            NativeTransferFailureKind::Locked
                        }
                        TransferFailureKind::Git => NativeTransferFailureKind::Rejected,
                        TransferFailureKind::MissingObject => {
                            NativeTransferFailureKind::MissingObject
                        }
                    });
                    Err(ExecutionFailure::Definite)
                }
            };
            if let Some(saved) = stash.as_mut() {
                saved.pull_completed = pulled.is_ok();
                pull_stash::reapply(saved, &plan, repository, mutation, activity);
            }
            pulled
        },
    );
    drop(lease);
    let (ahead, behind) = repository
        .snapshot()
        .status
        .as_ref()
        .map_or((0, 0), |status| (status.branch.ahead, status.branch.behind));
    let retryable = matches!(
        process_failure,
        Some(NativeTransferFailureKind::Authentication | NativeTransferFailureKind::HostKey)
    );
    finish_attempt(session_id, token, !retryable);
    if retryable {
        if let Some(owned) = lock_transfers().previews.get_mut(session_id, token) {
            owned.value.last_failure = process_failure;
        }
    }
    let outcome = MutationOutcome::from_terminal(outcome);
    let failure = (!outcome.committed).then(|| {
        process_failure.unwrap_or(if outcome.state == MutationState::Canceled {
            NativeTransferFailureKind::Canceled
        } else {
            NativeTransferFailureKind::Read
        })
    });
    let mut result = execution_result(
        outcome.with_failure(failure),
        activity_id.get(),
        ahead,
        behind,
    );
    if result.failure.is_some() {
        result.diagnosis = diagnosis;
    }
    result.stash = stash;
    result
}

/// Deletes the named remote-tracking refs, each only while it still points
/// where the repository snapshot saw it; a ref already gone is skipped. It
/// repairs refs a fetch cannot update, such as two spellings of one branch on a
/// case-insensitive file system. The next fetch recreates what the remote has.
pub(crate) fn delete_tracking_refs(
    repository: &Repository,
    activity: &ActivityStore,
    references: &[String],
) -> NativeTransferExecutionResult {
    let snapshot = repository.snapshot();
    let Some(discovered) = snapshot.repository.as_ref() else {
        return execution_failure(NativeTransferFailureKind::Stale);
    };
    if references.is_empty() {
        return execution_failure(NativeTransferFailureKind::InvalidRequest);
    }
    let worktree = discovered.worktree.worktree_root().as_path().to_path_buf();
    let mut commands = Vec::with_capacity(references.len());
    for name in references {
        let Ok(id) = RefId::parse(name.clone()) else {
            return execution_failure(NativeTransferFailureKind::InvalidRequest);
        };
        if !name.starts_with("refs/remotes/") {
            return execution_failure(NativeTransferFailureKind::InvalidRequest);
        }
        let target = snapshot.refs.iter().find_map(|section| match section {
            RefsSectionData::Remotes { references, .. } => references
                .iter()
                .find(|reference| reference.id == id)
                .map(|reference| reference.target.clone()),
            _ => None,
        });
        let Some(target) = target else { continue };
        let Ok(shape) = prune_tracking_ref_command_shape(&id, &target) else {
            return execution_failure(NativeTransferFailureKind::InvalidRequest);
        };
        commands.push(
            GitProcessCommand::git("git").current_dir(&worktree).args(
                shape
                    .arguments
                    .iter()
                    .map(|argument| ProcessArgument::visible(argument.value())),
            ),
        );
    }
    let activity_id =
        crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
    let sink = activity.sink();
    let mut publish = move |event| sink(event);
    let cancellation = std::sync::atomic::AtomicBool::new(false);
    let mut failed = false;
    let outcome = coordinate_mutation(repository, &cancellation, |cancellation| {
        for (index, command) in commands.into_iter().enumerate() {
            let id = if index == 0 {
                activity_id
            } else {
                allocate_activity_id()
            };
            let result =
                ActivityGitRunner::run_private(command, id, Some(cancellation), &mut publish);
            if !matches!(result.activity.status, ActivityStatus::Succeeded { .. }) {
                failed = true;
                return Err(ExecutionFailure::Definite);
            }
        }
        Ok(())
    });
    let outcome = MutationOutcome::from_terminal(outcome);
    let failure = (!outcome.committed).then_some(if failed {
        NativeTransferFailureKind::Rejected
    } else {
        NativeTransferFailureKind::Read
    });
    execution_result(outcome.with_failure(failure), activity_id.get(), 0, 0)
}

/// What the diagnosis table recognises in a failed transfer's diagnostics.
fn transfer_diagnosis(
    stderr: &[u8],
    plan: &TransferPlan,
    repository: &Repository,
) -> Option<NativeTransferDiagnosis> {
    let mut local_refs = Vec::new();
    for section in repository.snapshot().refs.iter() {
        let references = match section {
            RefsSectionData::Branches { rows, .. } => rows,
            RefsSectionData::Remotes { references, .. } => references,
            RefsSectionData::Tags(tags) => tags,
            _ => continue,
        };
        local_refs.extend(
            references
                .iter()
                .filter_map(|reference| std::str::from_utf8(reference.id.as_bytes()).ok())
                .map(str::to_owned),
        );
    }
    diagnose_transfer(stderr, &plan.facts.remote_names, local_refs)
}

/// A lock conflict on a ref becomes a case collision when the refs the
/// transfer reported, or the repository's own refs, include another spelling
/// of it. On a case-insensitive file system both spellings share one loose
/// file, so the reported refs are usually the only place the other one shows.
fn diagnose_transfer(
    stderr: &[u8],
    remote_names: &[String],
    local_refs: Vec<String>,
) -> Option<NativeTransferDiagnosis> {
    let mut diagnosis = diagnose(stderr)?;
    if diagnosis.kind == DiagnosisKind::LockConflict {
        let mut known = updated_tracking_refs(stderr, remote_names);
        known.extend(local_refs);
        diagnosis = confirm_case_collision(diagnosis, known.iter().map(String::as_str));
    }
    Some(NativeTransferDiagnosis {
        kind: match diagnosis.kind {
            DiagnosisKind::HostKey => NativeTransferDiagnosisKind::HostKey,
            DiagnosisKind::MissingObject => NativeTransferDiagnosisKind::MissingObject,
            DiagnosisKind::Authentication => NativeTransferDiagnosisKind::Authentication,
            DiagnosisKind::LockConflict => NativeTransferDiagnosisKind::LockConflict,
            DiagnosisKind::RefCaseCollision => NativeTransferDiagnosisKind::RefCaseCollision,
            DiagnosisKind::RemoteAhead => NativeTransferDiagnosisKind::RemoteAhead,
            DiagnosisKind::StaleLease => NativeTransferDiagnosisKind::StaleLease,
        },
        reference: diagnosis.reference,
        related: diagnosis.related,
    })
}

/// The bridge result of a transfer: the one place its outcome becomes a state.
fn execution_result(
    outcome: MutationOutcome<NativeTransferFailureKind>,
    activity_id: u64,
    ahead: u64,
    behind: u64,
) -> NativeTransferExecutionResult {
    NativeTransferExecutionResult {
        state: match outcome.state {
            MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
                NativeTransferExecutionState::Completed
            }
            MutationState::ReconciledWithWarning => {
                NativeTransferExecutionState::ReconciledWithWarning
            }
            MutationState::Stale => NativeTransferExecutionState::Stale,
            MutationState::Conflict
            | MutationState::Interrupted
            | MutationState::EditStop
            | MutationState::Partial
            | MutationState::Canceled
            | MutationState::Failed => NativeTransferExecutionState::Failed,
            MutationState::OutcomeUncertain => NativeTransferExecutionState::OutcomeUncertain,
        },
        failure: outcome.failure.map(|kind| NativeTransferFailure { kind }),
        diagnosis: None,
        stash: None,
        activity_id: Some(activity_id),
        ahead,
        behind,
    }
}

pub(crate) fn cancel(session_id: u64, token: u64) -> bool {
    lock_transfers().previews.cancel(session_id, token)
}

pub(crate) fn probe_transfer_host_key(
    session_id: u64,
    token: u64,
    activity: &ActivityStore,
) -> NativeHostKeyResult {
    let (plan, cancellation) = {
        let registry = lock_transfers();
        let Some(owned) = registry.previews.get(session_id, token) else {
            return host_key_failure(NativeCloneFailureKind::UnknownAttempt);
        };
        if owned.running
            || owned.value.last_failure != Some(NativeTransferFailureKind::HostKey)
            || owned.value.pending_host_key.is_some()
        {
            return host_key_failure(NativeCloneFailureKind::InvalidAttemptState);
        }
        (owned.value.plan.clone(), Arc::clone(&owned.cancellation))
    };
    let source = match remote_source(&plan, activity) {
        Ok(source) => source,
        Err(failure) => return host_key_failure(failure),
    };
    let pending = match probe_host_key(&source, cancellation.as_ref(), activity) {
        Ok(pending) => pending,
        Err(failure) => return host_key_failure(failure),
    };
    let challenge = pending.challenge.clone();
    let mut registry = lock_transfers();
    let Some(owned) = registry.previews.get_mut(session_id, token) else {
        return host_key_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    if owned.running || owned.value.last_failure != Some(NativeTransferFailureKind::HostKey) {
        return host_key_failure(NativeCloneFailureKind::InvalidAttemptState);
    }
    owned.value.pending_host_key = Some(pending);
    NativeHostKeyResult {
        challenge: Some(challenge),
        failure: None,
    }
}

pub(crate) fn resolve_transfer_host_key(
    session_id: u64,
    token: u64,
    challenge_id: u64,
    accept: bool,
) -> NativeCloneCommandResult {
    let mut registry = lock_transfers();
    let Some(owned) = registry.previews.get_mut(session_id, token) else {
        return host_key_command_failure(NativeCloneFailureKind::UnknownAttempt);
    };
    let Some(pending) = owned.value.pending_host_key.as_ref() else {
        return host_key_command_failure(NativeCloneFailureKind::HostKeyChallengeExpired);
    };
    if pending.challenge.challenge_id != challenge_id {
        return host_key_command_failure(NativeCloneFailureKind::HostKeyChallengeExpired);
    }
    if !accept {
        owned.value.pending_host_key = None;
        return NativeCloneCommandResult {
            accepted: true,
            failure: None,
        };
    }
    let wrapper = match trust_host_key(pending) {
        Ok(wrapper) => wrapper,
        Err(failure) => return host_key_command_failure(failure),
    };
    owned.value.pending_host_key = None;
    owned.value.ssh_wrapper = Some(wrapper);
    owned.value.last_failure = None;
    NativeCloneCommandResult {
        accepted: true,
        failure: None,
    }
}

pub(crate) fn dismiss_session(session_id: u64) {
    lock_transfers().previews.discard_session(session_id);
}

fn build_plan(
    request: NativeTransferRequest,
    snapshot: &RepositorySnapshot,
) -> Result<TransferPlan, NativeTransferFailureKind> {
    if request.stash_before_pull
        && (request.kind != NativeTransferKind::Pull || request.allow_dirty)
    {
        return Err(NativeTransferFailureKind::InvalidRequest);
    }
    let facts = transfer_facts(snapshot)?;
    if request.refetch && request.kind != NativeTransferKind::Fetch {
        return Err(NativeTransferFailureKind::InvalidRequest);
    }
    let (upstream_remote, upstream_branch) = facts
        .upstream
        .as_deref()
        .and_then(|upstream| split_upstream(upstream, &facts.remote_names))
        .map_or((None, None), |(remote, branch)| {
            (Some(remote.to_owned()), Some(branch.to_owned()))
        });
    let remote_text = request
        .remote
        .as_deref()
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .or(upstream_remote)
        .or_else(|| {
            facts
                .remote_names
                .iter()
                .find(|name| *name == "origin")
                .cloned()
        })
        .or_else(|| facts.remote_names.first().cloned())
        .ok_or(NativeTransferFailureKind::MissingUpstream)?;
    if !facts.remote_names.contains(&remote_text) {
        return Err(NativeTransferFailureKind::InvalidRequest);
    }
    let remote =
        RemoteName::new(remote_text).map_err(|_| NativeTransferFailureKind::InvalidRequest)?;
    let local_branch = facts.head_ref.clone();
    let local_short = local_branch
        .as_ref()
        .and_then(|reference| reference.as_bytes().strip_prefix(b"refs/heads/"))
        .map(std::str::from_utf8)
        .transpose()
        .map_err(|_| NativeTransferFailureKind::InvalidRequest)?
        .map(str::to_owned);
    let branch = if matches!(
        request.kind,
        NativeTransferKind::PushTag
            | NativeTransferKind::DeleteTag
            | NativeTransferKind::DeleteBranch
    ) {
        request.branch.clone().filter(|value| !value.is_empty())
    } else {
        request.branch.clone().or(upstream_branch).or(local_short)
    };
    if matches!(facts.working_tree, WorkingTreeState::Conflicted)
        && request.kind == NativeTransferKind::Pull
    {
        return Err(NativeTransferFailureKind::ConflictedWorktree);
    }
    if facts.working_tree != WorkingTreeState::Clean
        && request.kind == NativeTransferKind::Pull
        && !request.allow_dirty
        && !request.stash_before_pull
    {
        return Err(NativeTransferFailureKind::DirtyWorktree);
    }
    let branch_ref = branch
        .as_ref()
        .map(|branch| {
            RefId::parse(
                if matches!(
                    request.kind,
                    NativeTransferKind::PushTag | NativeTransferKind::DeleteTag
                ) {
                    format!("refs/tags/{branch}")
                } else {
                    format!("refs/heads/{branch}")
                },
            )
        })
        .transpose()
        .map_err(|_| NativeTransferFailureKind::InvalidRequest)?;
    if request.kind == NativeTransferKind::PushTag {
        let tag_ref = branch_ref
            .as_ref()
            .ok_or(NativeTransferFailureKind::InvalidRequest)?;
        let tag_exists = snapshot.refs.iter().any(|section| match section {
            RefsSectionData::Tags(tags) => tags.iter().any(|tag| tag.id == *tag_ref),
            _ => false,
        });
        if !tag_exists || request.force_with_lease || request.set_upstream {
            return Err(NativeTransferFailureKind::InvalidRequest);
        }
    }
    if matches!(
        request.kind,
        NativeTransferKind::DeleteTag | NativeTransferKind::DeleteBranch
    ) && (branch_ref.is_none() || request.force_with_lease || request.set_upstream)
    {
        return Err(NativeTransferFailureKind::InvalidRequest);
    }
    let expected_remote = if request.kind == NativeTransferKind::DeleteTag {
        let tag_ref = branch_ref
            .as_ref()
            .ok_or(NativeTransferFailureKind::InvalidRequest)?;
        snapshot
            .refs
            .iter()
            .find_map(|section| match section {
                RefsSectionData::Tags(tags) => tags
                    .iter()
                    .find(|tag| tag.id == *tag_ref)
                    .map(|tag| tag.target.clone()),
                _ => None,
            })
            .ok_or(NativeTransferFailureKind::InvalidRequest)
            .map(Some)?
    } else if request.kind == NativeTransferKind::DeleteBranch {
        // The lease is the fetched remote-tracking ref: a remote branch that
        // moved since the last fetch is not deleted.
        let branch = branch
            .as_ref()
            .ok_or(NativeTransferFailureKind::InvalidRequest)?;
        Some(
            remote_ref_target(snapshot, remote.as_str(), branch)
                .ok_or(NativeTransferFailureKind::MissingUpstream)?,
        )
    } else if request.kind == NativeTransferKind::Push {
        branch
            .as_ref()
            .and_then(|branch| remote_ref_target(snapshot, remote.as_str(), branch))
    } else {
        None
    };
    if request.force_with_lease && expected_remote.is_none() {
        return Err(NativeTransferFailureKind::MissingUpstream);
    }
    let operation = match request.kind {
        NativeTransferKind::Fetch => RemoteOperationRequest::Fetch(FetchRequest {
            scope: if request.remote.as_deref() == Some("*") {
                FetchScope::All
            } else {
                FetchScope::Remote(remote.clone())
            },
        }),
        NativeTransferKind::Pull => RemoteOperationRequest::Pull(PullRequest {
            remote: remote.clone(),
            local_branch: local_branch
                .clone()
                .ok_or(NativeTransferFailureKind::DetachedHead)?,
            branch: branch_ref,
            strategy: match request.pull_strategy {
                NativePullStrategy::FastForwardOnly => PullStrategy::FastForwardOnly,
                NativePullStrategy::FastForwardIfPossible => PullStrategy::FastForwardIfPossible,
                NativePullStrategy::Rebase => PullStrategy::Rebase,
            },
        }),
        NativeTransferKind::Push => RemoteOperationRequest::Push(PushRequest {
            remote: remote.clone(),
            refspecs: vec![PushRefspec::new(
                local_branch.ok_or(NativeTransferFailureKind::DetachedHead)?,
                branch_ref.ok_or(NativeTransferFailureKind::InvalidRequest)?,
                expected_remote.clone(),
            )
            .map_err(|_| NativeTransferFailureKind::InvalidRequest)?],
            force: if request.force_with_lease {
                PushForce::WithLease
            } else {
                PushForce::Never
            },
            set_upstream: request.set_upstream,
        }),
        NativeTransferKind::PushTag => {
            let tag_ref = branch_ref.ok_or(NativeTransferFailureKind::InvalidRequest)?;
            RemoteOperationRequest::Push(PushRequest {
                remote: remote.clone(),
                refspecs: vec![PushRefspec::new(tag_ref.clone(), tag_ref, None)
                    .map_err(|_| NativeTransferFailureKind::InvalidRequest)?],
                force: PushForce::Never,
                set_upstream: false,
            })
        }
        NativeTransferKind::DeleteTag | NativeTransferKind::DeleteBranch => {
            let remote_ref = branch_ref.ok_or(NativeTransferFailureKind::InvalidRequest)?;
            RemoteOperationRequest::Push(PushRequest {
                remote: remote.clone(),
                refspecs: vec![PushRefspec::delete(remote_ref, expected_remote.clone())
                    .map_err(|_| NativeTransferFailureKind::InvalidRequest)?],
                force: PushForce::WithLease,
                set_upstream: false,
            })
        }
    };
    Ok(TransferPlan {
        request,
        remote,
        branch,
        operation,
        facts: TransferFacts {
            remote_target: expected_remote.clone(),
            ..facts
        },
        expected_remote,
    })
}

fn transfer_facts(
    snapshot: &RepositorySnapshot,
) -> Result<TransferFacts, NativeTransferFailureKind> {
    let repository = snapshot
        .repository
        .as_ref()
        .ok_or(NativeTransferFailureKind::Read)?;
    let status = snapshot
        .status
        .as_ref()
        .ok_or(NativeTransferFailureKind::Read)?;
    let (head_ref, head_oid) = match &status.branch.head {
        BranchHead::Attached(branch) => (
            RefId::from_bytes([b"refs/heads/".as_slice(), branch.as_bytes()].concat()).ok(),
            status.branch.oid.clone(),
        ),
        BranchHead::Detached => (None, status.branch.oid.clone()),
        BranchHead::Unborn { branch } => (
            RefId::from_bytes([b"refs/heads/".as_slice(), branch.as_bytes()].concat()).ok(),
            None,
        ),
    };
    let mut remote_names = Vec::new();
    for section in snapshot.refs.iter() {
        if let RefsSectionData::Remotes { remotes, .. } = section {
            for remote in remotes {
                if let Ok(name) = std::str::from_utf8(remote.id.as_bytes()) {
                    remote_names.push(name.to_owned());
                }
            }
        }
    }
    remote_names.sort();
    remote_names.dedup();
    Ok(TransferFacts {
        worktree: repository.worktree.worktree_root().as_path().to_path_buf(),
        common_git_dir: repository
            .worktree
            .repository()
            .common_git_dir()
            .as_path()
            .to_path_buf(),
        head_ref,
        head_oid,
        upstream: status
            .branch
            .upstream
            .as_ref()
            .map(|value| value.as_bytes().to_vec()),
        ahead: status.branch.ahead,
        behind: status.branch.behind,
        working_tree: status.working_tree,
        remote_names,
        remote_target: None,
    })
}

fn remote_ref_target(
    snapshot: &RepositorySnapshot,
    remote: &str,
    branch: &str,
) -> Option<ObjectId> {
    let expected = format!("refs/remotes/{remote}/{branch}");
    snapshot.refs.iter().find_map(|section| match section {
        RefsSectionData::Remotes { references, .. } => references
            .iter()
            .find(|reference| reference.id.as_bytes() == expected.as_bytes())
            .map(|reference| reference.target.clone()),
        _ => None,
    })
}

/// Splits a short upstream such as `team/origin/topic` into its configured remote and branch.
/// Remote names may contain `/`, so the longest configured remote that prefixes the upstream
/// wins instead of the first slash.
fn split_upstream<'a>(value: &'a [u8], remotes: &[String]) -> Option<(&'a str, &'a str)> {
    let value = std::str::from_utf8(value).ok()?;
    remotes
        .iter()
        .filter_map(|remote| {
            let branch = value.strip_prefix(remote.as_str())?.strip_prefix('/')?;
            (!branch.is_empty()).then(|| (&value[..remote.len()], branch))
        })
        .max_by_key(|(remote, _)| remote.len())
}

fn transfer_shape(plan: &TransferPlan) -> Result<CommandShape, NativeTransferFailureKind> {
    if let RemoteOperationRequest::Fetch(request) = &plan.operation {
        // Pruning, on unless the user turns it off, keeps remote branches deleted on the
        // server, for example after a merged pull request, from lingering as
        // remote-tracking refs.
        fetch_command_shape(
            request,
            FetchOptions {
                prune: plan.request.prune,
                refetch: plan.request.refetch,
            },
        )
        .map_err(|_| NativeTransferFailureKind::InvalidRequest)
    } else if plan.request.refetch {
        Err(NativeTransferFailureKind::InvalidRequest)
    } else if let RemoteOperationRequest::Pull(request) = &plan.operation {
        devmil_git::commands::remote::pull_without_autostash_command_shape(request)
            .map_err(|_| NativeTransferFailureKind::InvalidRequest)
    } else {
        command_shape(&plan.operation).map_err(|_| NativeTransferFailureKind::InvalidRequest)
    }
}

/// After a leased remote-branch delete is refused as stale, asks the remote whether the branch
/// still exists. A branch the server already deleted, for example after a merged pull request,
/// satisfies the request: its remote-tracking ref is then pruned while it still holds the lease.
/// A branch that moved on the remote stays refused.
fn remote_branch_already_deleted(
    plan: &TransferPlan,
    askpass: Option<&Path>,
    ssh_wrapper: Option<&Path>,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    publish: &mut dyn ActivityEventSink,
) -> bool {
    let (Some(branch), Some(expected)) = (plan.branch.as_deref(), plan.expected_remote.as_ref())
    else {
        return false;
    };
    let (Ok(remote_ref), Ok(tracking_ref)) = (
        RefId::parse(format!("refs/heads/{branch}")),
        RefId::parse(format!("refs/remotes/{}/{branch}", plan.remote.as_str())),
    ) else {
        return false;
    };
    let Ok(probe) = remote_ref_probe_command_shape(&plan.remote, &remote_ref)
        .map_err(|_| NativeTransferFailureKind::InvalidRequest)
        .and_then(|shape| transfer_command(&shape, plan, askpass, ssh_wrapper))
    else {
        return false;
    };
    let result =
        ActivityGitRunner::run_private(probe, allocate_activity_id(), Some(cancellation), publish);
    if !matches!(result.activity.status, ActivityStatus::Succeeded { .. })
        || !matches!(
            parse_remote_ref_probe(&result.stdout.bytes, &remote_ref),
            Ok(None)
        )
    {
        return false;
    }
    // The remote outcome is settled; a tracking ref that changed meanwhile is left to fetch.
    if let Ok(shape) = prune_tracking_ref_command_shape(&tracking_ref, expected) {
        let command = GitProcessCommand::git("git")
            .current_dir(&plan.facts.worktree)
            .args(
                shape
                    .arguments
                    .iter()
                    .map(|argument| ProcessArgument::visible(argument.value())),
            );
        // The deletion's own tracking ref goes with it.
        let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
        ActivityGitRunner::run_private(command, id, None, publish);
    }
    true
}

fn preview_arguments(plan: &TransferPlan) -> Result<Vec<String>, NativeTransferFailureKind> {
    let shape = transfer_shape(plan)?;
    Ok(transfer_configuration(TransferAuthentication::Default)
        .iter()
        .chain(&shape.arguments)
        .map(|argument| argument.display().to_owned())
        .collect())
}

fn remote_source(
    plan: &TransferPlan,
    activity: &ActivityStore,
) -> Result<CloneSource, NativeCloneFailureKind> {
    let command = GitProcessCommand::git("git")
        .current_dir(&plan.facts.worktree)
        .args([
            ProcessArgument::visible("remote"),
            ProcessArgument::visible("get-url"),
            ProcessArgument::visible("--"),
            ProcessArgument::visible(plan.remote.as_str()),
        ])
        .output_limit(4 * 1024)
        .redact_output();
    let sink = activity.sink();
    let mut publish = move |event| sink(event);
    let result =
        ActivityGitRunner::run_private(command, allocate_activity_id(), None, &mut publish);
    if !matches!(result.activity.status, ActivityStatus::Succeeded { .. }) {
        return Err(NativeCloneFailureKind::HostKeyProbeFailed);
    }
    let source = std::str::from_utf8(&result.stdout.bytes)
        .ok()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or(NativeCloneFailureKind::HostKeyProbeFailed)?;
    CloneSource::parse(source.to_owned()).map_err(|_| NativeCloneFailureKind::HostKeyProbeFailed)
}

fn command_for_plan(
    plan: &TransferPlan,
    askpass: Option<&Path>,
    ssh_wrapper: Option<&Path>,
) -> Result<GitProcessCommand, NativeTransferFailureKind> {
    transfer_command(&transfer_shape(plan)?, plan, askpass, ssh_wrapper)
}

fn transfer_command(
    shape: &CommandShape,
    plan: &TransferPlan,
    askpass: Option<&Path>,
    ssh_wrapper: Option<&Path>,
) -> Result<GitProcessCommand, NativeTransferFailureKind> {
    let reject =
        std::env::temp_dir().join(format!("gitlama-reject-transfer-{}", std::process::id()));
    let authentication = askpass.map_or_else(
        || {
            ssh_wrapper.map_or(TransferAuthentication::Default, |ssh_wrapper| {
                TransferAuthentication::AcceptHostKey { ssh_wrapper }
            })
        },
        |executable| TransferAuthentication::ExternalAskpass { executable },
    );
    let mut environment = transfer_environment(true, &reject, authentication)
        .map_err(|_| NativeTransferFailureKind::InvalidRequest)?;
    if askpass.is_some() {
        if let Some(ssh_wrapper) = ssh_wrapper {
            environment.push(
                devmil_git::commands::remote::RemoteEnvironment::new(
                    "GIT_SSH",
                    ssh_wrapper.as_os_str(),
                )
                .map_err(|_| NativeTransferFailureKind::InvalidRequest)?,
            );
            environment.push(
                devmil_git::commands::remote::RemoteEnvironment::new(
                    "GIT_SSH_COMMAND",
                    shell_command_path(ssh_wrapper),
                )
                .map_err(|_| NativeTransferFailureKind::InvalidRequest)?,
            );
            environment.push(
                devmil_git::commands::remote::RemoteEnvironment::new("GIT_SSH_VARIANT", "ssh")
                    .map_err(|_| NativeTransferFailureKind::InvalidRequest)?,
            );
        }
    }
    let arguments = transfer_configuration(authentication)
        .iter()
        .chain(&shape.arguments)
        .map(|argument| {
            if argument.is_redacted() {
                ProcessArgument::redacted(argument.value(), argument.display())
            } else {
                ProcessArgument::visible(argument.value())
            }
        })
        .collect::<Vec<_>>();
    let mut command = GitProcessCommand::git("git")
        .current_dir(&plan.facts.worktree)
        .args(arguments)
        .parse_git_progress(shape.parse_progress)
        .output_limit(ACTIVITY_STREAM_BYTE_CAPACITY)
        .publish_sanitized_output();
    for variable in environment {
        command = if variable.is_redacted() {
            command.env_redacted(variable.name(), variable.value())
        } else {
            command.env(variable.name(), variable.value())
        }
        .map_err(|_| NativeTransferFailureKind::InvalidRequest)?;
    }
    Ok(command)
}

fn plan_signature(
    plan: &TransferPlan,
) -> (&NativeTransferRequest, &TransferFacts, Option<&ObjectId>) {
    (&plan.request, &plan.facts, plan.expected_remote.as_ref())
}

fn finish_attempt(session_id: u64, token: u64, remove: bool) {
    let mut registry = lock_transfers();
    if remove {
        registry.previews.finish(session_id, token);
    } else if let Some(owned) = registry.previews.get_mut(session_id, token) {
        owned.running = false;
    }
}

fn preview_failure(kind: NativeTransferFailureKind) -> NativeTransferPreviewResult {
    NativeTransferPreviewResult {
        preview: None,
        failure: Some(NativeTransferFailure { kind }),
    }
}

fn execution_failure(kind: NativeTransferFailureKind) -> NativeTransferExecutionResult {
    NativeTransferExecutionResult {
        state: if kind == NativeTransferFailureKind::Stale {
            NativeTransferExecutionState::Stale
        } else {
            NativeTransferExecutionState::Failed
        },
        failure: Some(NativeTransferFailure { kind }),
        diagnosis: None,
        stash: None,
        activity_id: None,
        ahead: 0,
        behind: 0,
    }
}

fn host_key_failure(kind: NativeCloneFailureKind) -> NativeHostKeyResult {
    NativeHostKeyResult {
        challenge: None,
        failure: Some(NativeCloneFailure { kind }),
    }
}

fn host_key_command_failure(kind: NativeCloneFailureKind) -> NativeCloneCommandResult {
    NativeCloneCommandResult {
        accepted: false,
        failure: Some(NativeCloneFailure { kind }),
    }
}

crate::family_failures!(NativeTransferFailureKind, "transfer", {
    InvalidRequest => InvalidRequest,
    DetachedHead => Precondition,
    MissingUpstream => Precondition,
    DirtyWorktree => Precondition,
    ConflictedWorktree => Precondition,
    Stale => Stale,
    Authentication => Authentication,
    CredentialBrokerUnavailable => Unavailable,
    HostKey => Authentication,
    Rejected => Rejected,
    TimedOut => TimedOut,
    Canceled => Canceled,
    MissingGit => Unavailable,
    Read => Read,
    MissingObject => NotFound,
    Locked => Busy,
});

#[cfg(test)]
mod tests {
    #[test]
    fn a_reported_case_variant_confirms_a_collision_without_local_refs() {
        use super::*;
        // The shape of a macOS fetch whose prune deletes two spellings of one
        // branch: only the reported refs name the second one.
        let stderr = b"error: could not delete references: cannot lock ref \
'refs/remotes/origin/npt/chore/sync': Unable to create \
'/r/.git/refs/remotes/origin/npt/chore/sync.lock': File exists.\n\n\
Another git process seems to be running in this repository\n\
From https://example.invalid/repo\n \
- [deleted]               (none)     -> origin/NPT/chore/sync\n \
- [deleted]               (none)     -> origin/other\n";
        let diagnosis = diagnose_transfer(
            stderr,
            &["origin".to_owned()],
            vec!["refs/heads/main".to_owned()],
        )
        .unwrap();
        assert_eq!(
            diagnosis.kind,
            NativeTransferDiagnosisKind::RefCaseCollision
        );
        assert_eq!(
            diagnosis.reference.as_deref(),
            Some("refs/remotes/origin/npt/chore/sync")
        );
        assert_eq!(diagnosis.related, ["refs/remotes/origin/NPT/chore/sync"]);
        let plain = diagnose_transfer(
            b"fatal: Unable to create '/r/.git/index.lock': File exists.",
            &["origin".to_owned()],
            Vec::new(),
        )
        .unwrap();
        assert_eq!(plain.kind, NativeTransferDiagnosisKind::LockConflict);
    }

    #[test]
    fn an_uncertain_transfer_stays_uncertain() {
        use super::*;
        use crate::domain::outcome::MutationTerminalState;
        let outcome = MutationOutcome::from_terminal(MutationTerminalState::OutcomeUncertain)
            .with_failure(Some(NativeTransferFailureKind::Read));
        let result = execution_result(outcome, 9, 1, 2);
        assert_eq!(result.state, NativeTransferExecutionState::OutcomeUncertain);
        assert_eq!(
            result.failure.map(|failure| failure.kind),
            Some(NativeTransferFailureKind::Read)
        );
        assert_eq!(result.activity_id, Some(9));
    }

    #[test]
    fn an_upstream_splits_at_its_configured_remote_name() {
        let remotes = vec!["origin".to_owned(), "team/origin".to_owned()];
        assert_eq!(
            super::split_upstream(b"team/origin/feature/x", &remotes),
            Some(("team/origin", "feature/x"))
        );
        assert_eq!(
            super::split_upstream(b"origin/main", &remotes),
            Some(("origin", "main"))
        );
        assert_eq!(super::split_upstream(b"unknown/main", &remotes), None);
        assert_eq!(super::split_upstream(b"origin/", &remotes), None);
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{session::*, transfer::*};
    use crate::dto::*;

    use crate::transfer::{
        NativePullStrategy, NativeTransferExecutionState, NativeTransferFailureKind,
        NativeTransferKind, NativeTransferRequest,
    };

    use devmil_git::RepositoryOptions;

    use std::fs;
    #[cfg(unix)]
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::os::unix::fs::PermissionsExt;

    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::time::Duration;
    use std::time::Instant;

    #[test]
    fn transfers_execute_exact_shared_commands_and_reject_stale_force_lease() {
        let fixture = TransferFixture::new();
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_203,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);

        let fetch = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::Fetch,
                remote: Some("origin".into()),
                branch: None,
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        // Configured credential helpers stay in effect; only prompting is ruled out.
        assert_eq!(
            fetch.arguments,
            [
                "-c",
                "core.askPass=",
                "-c",
                "credential.interactive=false",
                "fetch",
                "--progress",
                "--prune",
                "origin"
            ]
        );
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                fetch.token,
            )
            .state,
            NativeTransferExecutionState::Completed
        );

        fixture.commit(&fixture.client, b"local one\n", "local one");
        refresh_session_at_client_head(&session, &fixture.client);
        let push = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::Push,
                remote: Some("origin".into()),
                branch: Some("main".into()),
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            &push.arguments[4..],
            [
                "push",
                "--progress",
                "origin",
                "refs/heads/main:refs/heads/main"
            ]
        );
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                push.token,
            )
            .state,
            NativeTransferExecutionState::Completed
        );
        let remote_after_push = String::from_utf8(transfer_git(
            &fixture.remote,
            &["rev-parse", "refs/heads/main"],
        ))
        .unwrap();

        transfer_git(&fixture.client, &["tag", "v1.0.0"]);
        refresh_session_until(&session, |snapshot| {
            snapshot.refs.tags.iter().any(|tag| tag.name == b"v1.0.0")
        });
        let push_tag = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::PushTag,
                remote: Some("origin".into()),
                branch: Some("v1.0.0".into()),
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            &push_tag.arguments[4..],
            [
                "push",
                "--progress",
                "origin",
                "refs/tags/v1.0.0:refs/tags/v1.0.0"
            ]
        );
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                push_tag.token,
            )
            .state,
            NativeTransferExecutionState::Completed
        );
        assert_eq!(
            String::from_utf8(transfer_git(
                &fixture.remote,
                &["rev-parse", "refs/tags/v1.0.0"],
            ))
            .unwrap()
            .trim(),
            remote_after_push.trim()
        );
        let delete_tag = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::DeleteTag,
                remote: Some("origin".into()),
                branch: Some("v1.0.0".into()),
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            &delete_tag.arguments[4..],
            [
                "push",
                "--progress",
                &format!(
                    "--force-with-lease=refs/tags/v1.0.0:{}",
                    remote_after_push.trim()
                ),
                "origin",
                ":refs/tags/v1.0.0"
            ]
        );
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                delete_tag.token,
            )
            .state,
            NativeTransferExecutionState::Completed
        );
        transfer_git_expect_failure(&fixture.remote, &["rev-parse", "refs/tags/v1.0.0"]);
        assert!(!transfer_git(&fixture.client, &["tag", "--list", "v1.0.0"]).is_empty());
        transfer_git(
            &fixture.peer,
            &["tag", "-a", "-f", "v1.0.0", "-m", "changed"],
        );
        transfer_git(
            &fixture.peer,
            &["push", "-q", "-f", "origin", "refs/tags/v1.0.0"],
        );
        let changed_remote_tag = transfer_git(&fixture.remote, &["rev-parse", "refs/tags/v1.0.0"]);
        let stale_tag_delete = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::DeleteTag,
                remote: Some("origin".into()),
                branch: Some("v1.0.0".into()),
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                stale_tag_delete.token,
            )
            .failure
            .unwrap()
            .kind,
            NativeTransferFailureKind::Rejected
        );
        assert_eq!(
            transfer_git(&fixture.remote, &["rev-parse", "refs/tags/v1.0.0"]),
            changed_remote_tag
        );
        assert_eq!(
            repository_session_transfer_preview(
                session.session_id,
                session.generation,
                NativeTransferRequest {
                    kind: NativeTransferKind::PushTag,
                    remote: Some("origin".into()),
                    branch: Some("missing".into()),
                    pull_strategy: NativePullStrategy::FastForwardOnly,
                    allow_dirty: false,
                    stash_before_pull: false,
                    force_with_lease: false,
                    set_upstream: false,
                    refetch: false,
                    prune: true,
                },
            )
            .failure
            .unwrap()
            .kind,
            NativeTransferFailureKind::InvalidRequest
        );

        transfer_git(&fixture.peer, &["pull", "-q", "--ff-only"]);
        fixture.commit(&fixture.client, b"local rewrite\n", "local rewrite");
        refresh_session_at_client_head(&session, &fixture.client);
        let force = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::Push,
                remote: Some("origin".into()),
                branch: Some("main".into()),
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: true,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        let lease = force.expected_remote_object_id.clone().unwrap();
        assert_eq!(lease, remote_after_push.trim());
        assert!(force.arguments.iter().any(|argument| {
            argument == &format!("--force-with-lease=refs/heads/main:{lease}")
        }));

        fixture.commit(&fixture.peer, b"peer wins\n", "peer wins");
        transfer_git(&fixture.peer, &["push", "-q", "origin", "main"]);
        let peer_tip =
            String::from_utf8(transfer_git(&fixture.peer, &["rev-parse", "HEAD"])).unwrap();
        let rejected = repository_session_transfer_execute(
            session.session_id,
            session.generation,
            force.token,
        );
        assert_eq!(rejected.state, NativeTransferExecutionState::Failed);
        assert_eq!(
            rejected.failure.unwrap().kind,
            NativeTransferFailureKind::Rejected
        );
        assert_eq!(
            String::from_utf8(transfer_git(
                &fixture.remote,
                &["rev-parse", "refs/heads/main"],
            ))
            .unwrap()
            .trim(),
            peer_tip.trim()
        );

        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn delete_branch_transfer_is_leased_on_the_fetched_remote_branch() {
        let fixture = TransferFixture::new();
        transfer_git(
            &fixture.peer,
            &["push", "-q", "origin", "HEAD:refs/heads/topic"],
        );
        transfer_git(&fixture.client, &["fetch", "-q", "origin"]);
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_207,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        let request = |branch: &str| NativeTransferRequest {
            kind: NativeTransferKind::DeleteBranch,
            remote: Some("origin".into()),
            branch: Some(branch.into()),
            pull_strategy: NativePullStrategy::FastForwardOnly,
            allow_dirty: false,
            stash_before_pull: false,
            force_with_lease: false,
            set_upstream: false,
            refetch: false,
            prune: true,
        };
        assert_eq!(
            repository_session_transfer_preview(
                session.session_id,
                session.generation,
                request("never-fetched"),
            )
            .failure
            .unwrap()
            .kind,
            NativeTransferFailureKind::MissingUpstream
        );
        let fetched_topic = String::from_utf8(transfer_git(
            &fixture.client,
            &["rev-parse", "refs/remotes/origin/topic"],
        ))
        .unwrap();
        let delete = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            request("topic"),
        )
        .preview
        .unwrap();
        assert_eq!(
            &delete.arguments[4..],
            [
                "push",
                "--progress",
                &format!(
                    "--force-with-lease=refs/heads/topic:{}",
                    fetched_topic.trim()
                ),
                "origin",
                ":refs/heads/topic"
            ]
        );

        fixture.commit(&fixture.peer, b"moved topic\n", "moved topic");
        transfer_git(
            &fixture.peer,
            &["push", "-q", "origin", "HEAD:refs/heads/topic"],
        );
        let moved = transfer_git(&fixture.remote, &["rev-parse", "refs/heads/topic"]);
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                delete.token,
            )
            .failure
            .unwrap()
            .kind,
            NativeTransferFailureKind::Rejected
        );
        assert_eq!(
            transfer_git(&fixture.remote, &["rev-parse", "refs/heads/topic"]),
            moved
        );

        let fetch = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::Fetch,
                branch: None,
                ..request("topic")
            },
        )
        .preview
        .unwrap();
        let previous = repository_for_session(session.session_id, session.generation)
            .unwrap()
            .snapshot()
            .revision;
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                fetch.token,
            )
            .state,
            NativeTransferExecutionState::Completed
        );
        wait_for_new_revision(&session, previous);
        let delete = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            request("topic"),
        )
        .preview
        .unwrap();
        let deleted = repository_session_transfer_execute(
            session.session_id,
            session.generation,
            delete.token,
        );
        assert_eq!(
            deleted.state,
            NativeTransferExecutionState::Completed,
            "{:?}",
            deleted.failure
        );
        transfer_git_expect_failure(&fixture.remote, &["rev-parse", "refs/heads/topic"]);
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn delete_branch_already_gone_on_the_remote_prunes_its_tracking_ref() {
        let fixture = TransferFixture::new();
        for branch in ["merged", "moved"] {
            transfer_git(
                &fixture.peer,
                &["push", "-q", "origin", &format!("HEAD:refs/heads/{branch}")],
            );
        }
        transfer_git(&fixture.client, &["fetch", "-q", "origin"]);
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_250,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        let request = |branch: &str| NativeTransferRequest {
            kind: NativeTransferKind::DeleteBranch,
            remote: Some("origin".into()),
            branch: Some(branch.into()),
            pull_strategy: NativePullStrategy::FastForwardOnly,
            allow_dirty: false,
            stash_before_pull: false,
            force_with_lease: false,
            set_upstream: false,
            refetch: false,
            prune: true,
        };

        // The server deleted the branch, for example after merging its pull request.
        transfer_git(
            &fixture.peer,
            &["push", "-q", "origin", ":refs/heads/merged"],
        );
        let delete = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            request("merged"),
        )
        .preview
        .unwrap();
        let deleted = repository_session_transfer_execute(
            session.session_id,
            session.generation,
            delete.token,
        );
        assert_eq!(
            deleted.state,
            NativeTransferExecutionState::Completed,
            "{:?}",
            deleted.failure
        );
        transfer_git_expect_failure(
            &fixture.client,
            &["rev-parse", "--verify", "refs/remotes/origin/merged"],
        );

        // A branch that moved on the server stays refused and keeps its tracking ref.
        fixture.commit(&fixture.peer, b"moved branch\n", "moved branch");
        transfer_git(
            &fixture.peer,
            &["push", "-q", "origin", "HEAD:refs/heads/moved"],
        );
        let moved = transfer_git(&fixture.remote, &["rev-parse", "refs/heads/moved"]);
        let tracking = transfer_git(&fixture.client, &["rev-parse", "refs/remotes/origin/moved"]);
        let delete = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            request("moved"),
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                delete.token,
            )
            .failure
            .unwrap()
            .kind,
            NativeTransferFailureKind::Rejected
        );
        assert_eq!(
            transfer_git(&fixture.remote, &["rev-parse", "refs/heads/moved"]),
            moved
        );
        assert_eq!(
            transfer_git(&fixture.client, &["rev-parse", "refs/remotes/origin/moved"]),
            tracking
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn fetch_prunes_remote_branches_deleted_on_the_server() {
        let fixture = TransferFixture::new();
        transfer_git(
            &fixture.peer,
            &["push", "-q", "origin", "HEAD:refs/heads/merged"],
        );
        transfer_git(&fixture.client, &["fetch", "-q", "origin"]);
        transfer_git(
            &fixture.peer,
            &["push", "-q", "origin", ":refs/heads/merged"],
        );
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_251,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        let fetch = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::Fetch,
                remote: Some("origin".into()),
                branch: None,
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        assert!(fetch.arguments.ends_with(&[
            "fetch".to_owned(),
            "--progress".to_owned(),
            "--prune".to_owned(),
            "origin".to_owned(),
        ]));
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                fetch.token,
            )
            .state,
            NativeTransferExecutionState::Completed
        );
        transfer_git_expect_failure(
            &fixture.client,
            &["rev-parse", "--verify", "refs/remotes/origin/merged"],
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn a_prune_blocked_by_a_held_ref_lock_fails_as_locked_and_is_diagnosed() {
        for (generation, variant) in [(1_252, false), (1_253, true)] {
            let fixture = TransferFixture::new();
            transfer_git(
                &fixture.peer,
                &["push", "-q", "origin", "HEAD:refs/heads/topic/held"],
            );
            transfer_git(&fixture.client, &["fetch", "-q", "origin"]);
            transfer_git(
                &fixture.peer,
                &["push", "-q", "origin", ":refs/heads/topic/held"],
            );
            if variant {
                // A packed ref keeps its exact spelling on every file system, as
                // the loose refs of two spellings cannot on a case-insensitive one.
                let head = String::from_utf8(transfer_git(&fixture.client, &["rev-parse", "HEAD"]))
                    .unwrap();
                let packed = fixture.client.join(".git/packed-refs");
                let existing = std::fs::read_to_string(&packed).unwrap_or_default();
                std::fs::write(
                    &packed,
                    format!(
                        "{}{} refs/remotes/origin/TOPIC/held\n",
                        existing.replace(" sorted", ""),
                        head.trim()
                    ),
                )
                .unwrap();
            }
            let lock = fixture
                .client
                .join(".git/refs/remotes/origin/topic/held.lock");
            std::fs::write(&lock, b"").unwrap();
            let opened = repository_session_open_with_options(
                fixture.client.clone(),
                generation,
                RepositoryOptions {
                    watch: false,
                    ..RepositoryOptions::default()
                },
                ActivityStore::default(),
            );
            let session = opened.session.unwrap();
            wait_for_ready(&session);
            let fetch = repository_session_transfer_preview(
                session.session_id,
                session.generation,
                NativeTransferRequest {
                    kind: NativeTransferKind::Fetch,
                    remote: Some("origin".into()),
                    branch: None,
                    pull_strategy: NativePullStrategy::FastForwardOnly,
                    allow_dirty: false,
                    stash_before_pull: false,
                    force_with_lease: false,
                    set_upstream: false,
                    refetch: false,
                    prune: true,
                },
            )
            .preview
            .unwrap();
            let result = repository_session_transfer_execute(
                session.session_id,
                session.generation,
                fetch.token,
            );
            assert_eq!(result.state, NativeTransferExecutionState::Failed);
            assert_eq!(
                result.failure.map(|failure| failure.kind),
                Some(NativeTransferFailureKind::Locked)
            );
            let diagnosis = result.diagnosis.unwrap();
            if variant {
                assert_eq!(
                    diagnosis.kind,
                    NativeTransferDiagnosisKind::RefCaseCollision
                );
                // Git names whichever spelling it failed to lock first: the held
                // one, or on a case-insensitive file system possibly the other.
                let mut spellings = diagnosis.related.clone();
                spellings.extend(diagnosis.reference);
                spellings.sort();
                assert_eq!(
                    spellings,
                    [
                        "refs/remotes/origin/TOPIC/held",
                        "refs/remotes/origin/topic/held"
                    ]
                );
            } else {
                assert_eq!(
                    diagnosis.reference.as_deref(),
                    Some("refs/remotes/origin/topic/held")
                );
                assert_eq!(diagnosis.kind, NativeTransferDiagnosisKind::LockConflict);
                assert!(diagnosis.related.is_empty());
            }
            assert!(result.activity_id.is_some());
            assert!(lock.exists(), "a failed transfer never removes a lock");

            // Without pruning, the fetch does not touch the locked ref.
            let unpruned = repository_session_transfer_preview(
                session.session_id,
                session.generation,
                NativeTransferRequest {
                    kind: NativeTransferKind::Fetch,
                    remote: Some("origin".into()),
                    branch: None,
                    pull_strategy: NativePullStrategy::FastForwardOnly,
                    allow_dirty: false,
                    stash_before_pull: false,
                    force_with_lease: false,
                    set_upstream: false,
                    refetch: false,
                    prune: false,
                },
            )
            .preview
            .unwrap();
            assert!(!unpruned.arguments.contains(&"--prune".to_owned()));
            assert_eq!(
                repository_session_transfer_execute(
                    session.session_id,
                    session.generation,
                    unpruned.token,
                )
                .state,
                NativeTransferExecutionState::Completed
            );
            assert!(repository_session_close(session.session_id, session.generation).accepted);
        }
    }

    #[test]
    fn tracking_refs_are_deleted_only_while_unchanged_and_missing_ones_skipped() {
        let fixture = TransferFixture::new();
        transfer_git(
            &fixture.peer,
            &["push", "-q", "origin", "HEAD:refs/heads/topic/held"],
        );
        transfer_git(&fixture.client, &["fetch", "-q", "origin"]);
        transfer_git(
            &fixture.client,
            &["update-ref", "refs/remotes/origin/TOPIC/held", "HEAD"],
        );
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_254,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        let deleted = crate::application::transfer::repository_session_delete_tracking_refs(
            session.session_id,
            session.generation,
            vec![
                "refs/remotes/origin/topic/held".to_owned(),
                "refs/remotes/origin/TOPIC/held".to_owned(),
                "refs/remotes/origin/never".to_owned(),
            ],
        );
        assert_eq!(deleted.state, NativeTransferExecutionState::Completed);
        for name in [
            "refs/remotes/origin/topic/held",
            "refs/remotes/origin/TOPIC/held",
        ] {
            transfer_git_expect_failure(&fixture.client, &["rev-parse", "--verify", name]);
        }
        let refused = crate::application::transfer::repository_session_delete_tracking_refs(
            session.session_id,
            session.generation,
            vec!["refs/heads/main".to_owned()],
        );
        assert_eq!(
            refused.failure.map(|failure| failure.kind),
            Some(NativeTransferFailureKind::InvalidRequest),
            "only remote-tracking refs are repaired here"
        );
        transfer_git(
            &fixture.client,
            &["rev-parse", "--verify", "refs/heads/main"],
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn refetch_restores_missing_reachable_object_without_changing_worktree() {
        let fixture = TransferFixture::new();
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_211,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        let head = transfer_git(&fixture.client, &["rev-parse", "HEAD"]);
        let content = fs::read(fixture.client.join("tracked.txt")).unwrap();
        let object = String::from_utf8(transfer_git(
            &fixture.client,
            &["rev-parse", "HEAD:tracked.txt"],
        ))
        .unwrap();
        let object = object.trim();
        let loose = fixture
            .client
            .join(".git")
            .join("objects")
            .join(&object[..2])
            .join(&object[2..]);
        fs::remove_file(loose).unwrap();
        transfer_git_expect_failure(&fixture.client, &["cat-file", "-t", object]);

        let request = NativeTransferRequest {
            kind: NativeTransferKind::Fetch,
            remote: Some("origin".into()),
            branch: None,
            pull_strategy: NativePullStrategy::FastForwardOnly,
            allow_dirty: false,
            stash_before_pull: false,
            force_with_lease: false,
            set_upstream: false,
            refetch: true,
            prune: true,
        };
        let preview = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            request.clone(),
        )
        .preview
        .unwrap();
        assert_eq!(
            &preview.arguments[4..],
            ["fetch", "--progress", "--prune", "--refetch", "origin"]
        );
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                preview.token,
            )
            .state,
            NativeTransferExecutionState::Completed
        );
        assert_eq!(
            transfer_git(&fixture.client, &["cat-file", "-t", object]),
            b"blob\n"
        );
        assert_eq!(transfer_git(&fixture.client, &["rev-parse", "HEAD"]), head);
        assert_eq!(
            fs::read(fixture.client.join("tracked.txt")).unwrap(),
            content
        );
        assert!(transfer_git(&fixture.client, &["status", "--porcelain"]).is_empty());

        assert_eq!(
            repository_session_transfer_preview(
                session.session_id,
                session.generation,
                NativeTransferRequest {
                    kind: NativeTransferKind::Pull,
                    ..request
                },
            )
            .failure
            .unwrap()
            .kind,
            NativeTransferFailureKind::InvalidRequest
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn pull_strategies_enforce_dirty_policy_and_rebase() {
        let fixture = TransferFixture::new();
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_204,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);

        fs::write(fixture.client.join("dirty.txt"), b"uncommitted\n").unwrap();
        let previous = repository_for_session(session.session_id, session.generation)
            .unwrap()
            .snapshot()
            .revision;
        assert!(repository_session_refresh(session.session_id, session.generation).accepted);
        wait_for_new_revision(&session, previous);
        let dirty_request = NativeTransferRequest {
            kind: NativeTransferKind::Pull,
            remote: Some("origin".into()),
            branch: Some("main".into()),
            pull_strategy: NativePullStrategy::FastForwardIfPossible,
            allow_dirty: false,
            stash_before_pull: false,
            force_with_lease: false,
            set_upstream: false,
            refetch: false,
            prune: true,
        };
        assert_eq!(
            repository_session_transfer_preview(
                session.session_id,
                session.generation,
                dirty_request.clone(),
            )
            .failure
            .unwrap()
            .kind,
            NativeTransferFailureKind::DirtyWorktree
        );
        let acknowledged = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                allow_dirty: true,
                stash_before_pull: false,
                ..dirty_request
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            &acknowledged.arguments[4..],
            [
                "pull",
                "--progress",
                "--no-autostash",
                "--ff",
                "origin",
                "main"
            ]
        );
        fs::remove_file(fixture.client.join("dirty.txt")).unwrap();

        fixture.commit(&fixture.peer, b"peer fast forward\n", "peer ff");
        transfer_git(&fixture.peer, &["push", "-q", "origin", "main"]);
        let peer_tip =
            String::from_utf8(transfer_git(&fixture.peer, &["rev-parse", "HEAD"])).unwrap();
        let previous = repository_for_session(session.session_id, session.generation)
            .unwrap()
            .snapshot()
            .revision;
        assert!(repository_session_refresh(session.session_id, session.generation).accepted);
        wait_for_new_revision(&session, previous);
        let pull = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::Pull,
                remote: Some("origin".into()),
                branch: Some("main".into()),
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                pull.token,
            )
            .state,
            NativeTransferExecutionState::Completed
        );
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.client, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim(),
            peer_tip.trim()
        );

        fs::write(fixture.client.join("local.txt"), b"local rebase\n").unwrap();
        transfer_git(&fixture.client, &["add", "local.txt"]);
        transfer_git(&fixture.client, &["commit", "-qm", "local rebase"]);
        let before_rebase =
            String::from_utf8(transfer_git(&fixture.client, &["rev-parse", "HEAD"])).unwrap();
        fs::write(fixture.peer.join("peer.txt"), b"peer rebase base\n").unwrap();
        transfer_git(&fixture.peer, &["add", "peer.txt"]);
        transfer_git(&fixture.peer, &["commit", "-qm", "peer rebase base"]);
        transfer_git(&fixture.peer, &["push", "-q", "origin", "main"]);
        refresh_session_at_client_head(&session, &fixture.client);
        let rebase = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::Pull,
                remote: Some("origin".into()),
                branch: Some("main".into()),
                pull_strategy: NativePullStrategy::Rebase,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            &rebase.arguments[4..],
            [
                "pull",
                "--progress",
                "--no-autostash",
                "--rebase",
                "origin",
                "main"
            ]
        );
        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                rebase.token,
            )
            .state,
            NativeTransferExecutionState::Completed
        );
        assert_ne!(
            String::from_utf8(transfer_git(&fixture.client, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim(),
            before_rebase.trim()
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn transfer_authentication_retry_never_enters_activity_output() {
        use std::io::{Read, Write};
        use std::net::TcpListener;

        let fixture = TransferFixture::new();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        transfer_git(
            &fixture.client,
            &[
                "remote",
                "set-url",
                "origin",
                &format!("http://{address}/repository.git"),
            ],
        );
        // The denial must not depend on a helper of the machine running the test.
        transfer_git(&fixture.client, &["config", "credential.helper", ""]);
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_205,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        listener.set_nonblocking(true).unwrap();
        let stop = Arc::new(AtomicBool::new(false));
        let server_stop = Arc::clone(&stop);
        let server = std::thread::spawn(move || {
            // A Windows runner can spend several seconds starting Git's HTTP
            // credential helper between the initial denial and the retry.
            // Keep the loop bounded, but do not let the test server disappear
            // before the retry reaches it.
            let deadline = Instant::now() + Duration::from_secs(60);
            while Instant::now() < deadline && !server_stop.load(Ordering::Acquire) {
                match listener.accept() {
                    Ok((mut stream, _)) => {
                        // Windows hands out accepted sockets in the listener's
                        // non-blocking mode. Reading then returns at once, and
                        // closing before the request arrived resets the client.
                        let _ = stream.set_nonblocking(false);
                        let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
                        let mut request = [0_u8; 8192];
                        let _ = stream.read(&mut request);
                        let _ = stream.write_all(
                            b"HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=git\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                        );
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        std::thread::sleep(Duration::from_millis(10));
                    }
                    Err(_) => break,
                }
            }
        });
        let preview = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::Fetch,
                remote: Some("origin".into()),
                branch: None,
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        let denied = repository_session_transfer_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert_eq!(
            denied.failure.unwrap().kind,
            NativeTransferFailureKind::Authentication
        );
        let secret = "gitlama-private-token-sentinel";
        let retry = repository_session_transfer_execute_with_credentials(
            session.session_id,
            session.generation,
            preview.token,
            Some("private-user-sentinel".into()),
            None,
            Some(secret.into()),
        );
        assert_eq!(
            retry.failure.unwrap().kind,
            NativeTransferFailureKind::Authentication
        );
        let page = repository_session_activity(session.session_id, session.generation, 20);
        for record in page.page.unwrap().records {
            let mut published = record.arguments.join(" ").into_bytes();
            published.extend(record.stdout);
            published.extend(record.stderr);
            assert!(!published
                .windows(secret.len())
                .any(|value| value == secret.as_bytes()));
            assert!(!published
                .windows("private-user-sentinel".len())
                .any(|value| value == b"private-user-sentinel"));
        }
        assert!(repository_session_close(session.session_id, session.generation).accepted);
        stop.store(true, Ordering::Release);
        server.join().unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn transfer_sends_the_credential_of_a_configured_helper() {
        use std::io::{Read, Write};
        use std::net::TcpListener;

        let fixture = TransferFixture::new();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        transfer_git(
            &fixture.client,
            &[
                "remote",
                "set-url",
                "origin",
                &format!("http://{address}/repository.git"),
            ],
        );
        // Stands for a helper from the user's Git configuration.
        transfer_git(
            &fixture.client,
            &[
                "config",
                "credential.helper",
                "!f() { echo username=helper-user; echo password=helper-answer; }; f",
            ],
        );
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_291,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        listener.set_nonblocking(true).unwrap();
        let stop = Arc::new(AtomicBool::new(false));
        let server_stop = Arc::clone(&stop);
        let server = std::thread::spawn(move || {
            let mut authorized = false;
            let deadline = Instant::now() + Duration::from_secs(60);
            while Instant::now() < deadline && !server_stop.load(Ordering::Acquire) {
                match listener.accept() {
                    Ok((mut stream, _)) => {
                        // Windows hands out accepted sockets in the listener's
                        // non-blocking mode. Reading then returns at once, and
                        // closing before the request arrived resets the client.
                        let _ = stream.set_nonblocking(false);
                        let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
                        let mut request = [0_u8; 8192];
                        let length = stream.read(&mut request).unwrap_or(0);
                        // Basic credentials of helper-user:helper-answer.
                        authorized |= String::from_utf8_lossy(&request[..length])
                            .to_ascii_lowercase()
                            .contains("authorization: basic agvscgvylxvzzxi6agvscgvylwfuc3dlcg==");
                        let _ = stream.write_all(
                            b"HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=git\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                        );
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        std::thread::sleep(Duration::from_millis(10));
                    }
                    Err(_) => break,
                }
            }
            authorized
        });
        let preview = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::Fetch,
                remote: Some("origin".into()),
                branch: None,
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        assert!(!preview
            .arguments
            .iter()
            .any(|argument| argument.starts_with("credential.helper")));
        let denied = repository_session_transfer_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert_eq!(
            denied.failure.unwrap().kind,
            NativeTransferFailureKind::Authentication
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
        stop.store(true, Ordering::Release);
        assert!(server.join().unwrap());
    }

    #[cfg(unix)]
    #[test]
    fn transfer_cancellation_reaps_remote_hook_and_preserves_remote_ref() {
        use std::os::unix::fs::PermissionsExt;

        let fixture = TransferFixture::new();
        let hook = fixture.remote.join("hooks/pre-receive");
        fs::write(&hook, b"#!/bin/sh\nsleep 20\nexit 0\n").unwrap();
        fs::set_permissions(&hook, fs::Permissions::from_mode(0o700)).unwrap();
        fixture.commit(&fixture.client, b"cancel me\n", "cancel me");
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_206,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        let preview = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            NativeTransferRequest {
                kind: NativeTransferKind::Push,
                remote: Some("origin".into()),
                branch: Some("main".into()),
                pull_strategy: NativePullStrategy::FastForwardOnly,
                allow_dirty: false,
                stash_before_pull: false,
                force_with_lease: false,
                set_upstream: false,
                refetch: false,
                prune: true,
            },
        )
        .preview
        .unwrap();
        let session_id = session.session_id;
        let generation = session.generation;
        let token = preview.token;
        let started = Instant::now();
        let worker = std::thread::spawn(move || {
            repository_session_transfer_execute(session_id, generation, token)
        });
        let deadline = Instant::now() + Duration::from_secs(3);
        while Instant::now() < deadline
            && !repository_session_transfer_cancel(session_id, generation, token).accepted
        {
            std::thread::sleep(Duration::from_millis(20));
        }
        let result = worker.join().unwrap();
        assert_eq!(
            result.failure.unwrap().kind,
            NativeTransferFailureKind::Canceled
        );
        assert!(started.elapsed() < Duration::from_secs(8));
        assert_eq!(
            String::from_utf8(transfer_git(
                &fixture.remote,
                &["show", "refs/heads/main:tracked.txt"],
            ))
            .unwrap(),
            "base\n"
        );
        assert!(repository_session_close(session_id, generation).accepted);
    }
}
