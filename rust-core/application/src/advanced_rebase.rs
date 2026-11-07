//! Fixup evidence, autosquash helpers and serial stacked-branch restacking.
pub use gitlama_contract::advanced_rebase::*;

use crate::activity::ActivityStore;
use crate::domain::outcome::MutationState;
use crate::preview_store::PreviewStore;
use devmil_git::activity::ActivityStatus;
use devmil_git::loading::autosquash::{EvidenceQuery, StackedBranch};
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::status::{BranchHead, WorkingTreeState};
use devmil_git::types::{ObjectId, RefId, RepositoryRelativePath};
use devmil_git::{Repository, RepositoryError, RepositoryErrorKind, RepositorySnapshot};
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

const MAX_FIXUP_PATHS: usize = 256;
const MAX_FIXUP_EVIDENCE: usize = 128;
const MAX_RESTACK_STEPS: usize = 128;
const PLAN_CAPACITY_PER_SESSION: usize = 4;

const fn native_restack_state(state: MutationState) -> NativeRestackExecutionState {
    match state {
        MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
            NativeRestackExecutionState::Completed
        }
        MutationState::ReconciledWithWarning => NativeRestackExecutionState::ReconciledWithWarning,
        MutationState::Conflict | MutationState::EditStop => NativeRestackExecutionState::Conflict,
        MutationState::Interrupted | MutationState::Partial => NativeRestackExecutionState::Partial,
        MutationState::Stale => NativeRestackExecutionState::Stale,
        MutationState::Canceled => NativeRestackExecutionState::Canceled,
        MutationState::Failed => NativeRestackExecutionState::Failed,
        MutationState::OutcomeUncertain => NativeRestackExecutionState::OutcomeUncertain,
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct RestackFacts {
    worktree: PathBuf,
    git_dir: PathBuf,
    common_git_dir: PathBuf,
    checkout_branch: Vec<u8>,
}

#[derive(Clone)]
struct RestackPlan {
    facts: RestackFacts,
    steps: Vec<NativeRestackStep>,
}

static REGISTRY: OnceLock<Mutex<PreviewStore<RestackPlan>>> = OnceLock::new();

fn lock_registry() -> std::sync::MutexGuard<'static, PreviewStore<RestackPlan>> {
    crate::preview_store::lock(
        REGISTRY.get_or_init(|| Mutex::new(PreviewStore::new(PLAN_CAPACITY_PER_SESSION))),
    )
}

pub(crate) fn suggest_fixup_base(
    repository: &Repository,
    selected_commit: Option<String>,
    paths: Vec<Vec<u8>>,
) -> NativeFixupSuggestionResult {
    if paths.len() > MAX_FIXUP_PATHS || (selected_commit.is_some() && !paths.is_empty()) {
        return suggestion_failure(NativeAdvancedRebaseFailureKind::InvalidRequest);
    }
    if selected_commit.is_none() && paths.is_empty() {
        return suggestion(NativeFixupSuggestionState::NoBase, Vec::new(), Vec::new());
    }
    let queries = if let Some(commit) = selected_commit {
        let Ok(commit) = ObjectId::parse(commit) else {
            return suggestion_failure(NativeAdvancedRebaseFailureKind::InvalidRequest);
        };
        vec![(
            None,
            EvidenceQuery {
                revision: Some(commit),
                path: None,
            },
        )]
    } else {
        let mut queries = Vec::with_capacity(paths.len());
        for path in paths {
            let Some(relative) = native_relative_path(path.clone()) else {
                return suggestion_failure(NativeAdvancedRebaseFailureKind::InvalidRequest);
            };
            queries.push((
                Some(path),
                EvidenceQuery {
                    revision: None,
                    path: Some(relative),
                },
            ));
        }
        queries
    };
    let requested = queries.len();
    let mut evidence = Vec::new();
    let mut activity_ids = Vec::new();
    for (path, query) in queries.into_iter().take(MAX_FIXUP_EVIDENCE) {
        let ticket = match repository.commit_evidence(query) {
            Ok(value) => value,
            Err(error) => {
                if matches!(error.kind, devmil_git::RepositoryErrorKind::Canceled) {
                    return suggestion_failure(NativeAdvancedRebaseFailureKind::Canceled);
                }
                continue;
            }
        };
        let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
            return suggestion_failure(NativeAdvancedRebaseFailureKind::Read);
        };
        let result = match result {
            Ok(result) => result,
            Err(error) => {
                if let Some(kind) = fixup_read_failure(&error) {
                    return suggestion_failure(kind);
                }
                continue;
            }
        };
        activity_ids.push(result.activity.id.get().to_string());
        evidence.push(NativeFixupEvidence {
            path,
            commit: result.commit.as_str().to_owned(),
            subject: result.subject.as_bytes().to_vec(),
        });
    }
    if evidence.is_empty() {
        return suggestion(NativeFixupSuggestionState::NoBase, evidence, activity_ids);
    }
    if evidence.len() < requested {
        return suggestion(
            NativeFixupSuggestionState::Incomplete,
            evidence,
            activity_ids,
        );
    }
    let mut counts = BTreeMap::<String, (usize, Vec<u8>)>::new();
    for item in &evidence {
        let entry = counts
            .entry(item.commit.clone())
            .or_insert_with(|| (0, item.subject.clone()));
        entry.0 += 1;
    }
    let maximum = counts.values().map(|value| value.0).max().unwrap_or(0);
    let winners = counts
        .iter()
        .filter(|(_, value)| value.0 == maximum)
        .collect::<Vec<_>>();
    if winners.len() != 1 {
        return suggestion(
            NativeFixupSuggestionState::Ambiguous,
            evidence,
            activity_ids,
        );
    }
    let candidate = winners[0].0.clone();
    let subject = winners[0].1 .1.clone();
    let mut result = suggestion(
        NativeFixupSuggestionState::Suggested,
        evidence,
        activity_ids,
    );
    result.candidate = Some(candidate);
    result.subject = Some(subject.clone());
    result.fixup_message = Some(prefixed(b"fixup! ", &subject));
    result.squash_message = Some(prefixed(b"squash! ", &subject));
    result
}

fn fixup_read_failure(error: &RepositoryError) -> Option<NativeAdvancedRebaseFailureKind> {
    matches!(error.kind, RepositoryErrorKind::Canceled)
        .then_some(NativeAdvancedRebaseFailureKind::Canceled)
}

pub(crate) fn plan_restack(
    session_id: u64,
    repository: &Repository,
    root_branch: Vec<u8>,
) -> NativeRestackPlanResult {
    let snapshot = repository.snapshot();
    let Some(facts) = restack_facts(snapshot.as_ref()) else {
        return restack_plan_failure(root_branch, preflight_kind(snapshot.as_ref()));
    };
    let mut root_ref = b"refs/heads/".to_vec();
    root_ref.extend_from_slice(&root_branch);
    let Ok(root_ref) = RefId::from_bytes(root_ref.clone()) else {
        return restack_plan_failure(root_branch, NativeAdvancedRebaseFailureKind::InvalidRequest);
    };
    let ticket = match repository.branch_stack() {
        Ok(value) => value,
        Err(_) => return restack_plan_failure(root_branch, NativeAdvancedRebaseFailureKind::Read),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return restack_plan_failure(root_branch, NativeAdvancedRebaseFailureKind::Read);
    };
    let Ok(discovery) = result else {
        return restack_plan_failure(root_branch, NativeAdvancedRebaseFailureKind::Read);
    };
    let by_name = discovery
        .branches
        .iter()
        .map(|branch| (branch.name.clone(), branch))
        .collect::<BTreeMap<_, _>>();
    if !by_name.contains_key(&root_ref) {
        return restack_plan_failure(root_branch, NativeAdvancedRebaseFailureKind::InvalidRequest);
    }
    let mut descendants = discovery
        .branches
        .iter()
        .filter(|branch| branch.name != root_ref && descends_from(branch, &root_ref, &by_name))
        .collect::<Vec<_>>();
    descendants.sort_by(|left, right| {
        left.depth
            .cmp(&right.depth)
            .then(left.name.cmp(&right.name))
    });
    let mut scheduled = BTreeSet::new();
    let mut selected = Vec::new();
    for branch in descendants {
        let Some(upstream) = branch.upstream.as_ref() else {
            continue;
        };
        let Some(parent) = by_name.get(upstream) else {
            continue;
        };
        let Some(fork) = branch.fork_point.as_ref() else {
            continue;
        };
        if fork != &parent.head || scheduled.contains(upstream) {
            if let Some(step) = restack_step(branch, &by_name) {
                scheduled.insert(branch.name.clone());
                selected.push(step);
            }
        }
    }
    if selected.is_empty() || selected.len() > MAX_RESTACK_STEPS {
        return restack_plan_failure(
            root_branch,
            if selected.is_empty() {
                NativeAdvancedRebaseFailureKind::InvalidRequest
            } else {
                NativeAdvancedRebaseFailureKind::TooLarge
            },
        );
    }
    for (index, step) in selected.iter_mut().enumerate() {
        step.id = index.try_into().unwrap_or(u32::MAX);
    }
    let published_count = selected.iter().filter(|step| step.published).count();
    let token = lock_registry().issue(
        session_id,
        RestackPlan {
            facts,
            steps: selected.clone(),
        },
    );
    NativeRestackPlanResult {
        token: Some(token),
        root_branch,
        steps: selected,
        published_count: published_count.try_into().unwrap_or(u32::MAX),
        incomplete: discovery.incomplete,
        activity_ids: discovery
            .activities
            .iter()
            .map(|activity| activity.id.get().to_string())
            .collect(),
        failure: None,
    }
}

pub(crate) fn execute_restack(
    session_id: u64,
    token: u64,
    repository: &Repository,
    activity: &ActivityStore,
    acknowledge_published_history: bool,
) -> NativeRestackExecutionResult {
    let (plan, cancellation) = {
        let mut registry = lock_registry();
        let Some(owned) = registry.get_mut(session_id, token) else {
            return restack_execution_failure(NativeAdvancedRebaseFailureKind::InvalidRequest);
        };
        if owned.running {
            return restack_execution_failure(NativeAdvancedRebaseFailureKind::InvalidRequest);
        }
        if owned.value.steps.iter().any(|step| step.published) && !acknowledge_published_history {
            return restack_execution_failure(
                NativeAdvancedRebaseFailureKind::PublicationConfirmationRequired,
            );
        }
        owned.running = true;
        owned.cancellation.store(false, Ordering::Release);
        (owned.value.clone(), Arc::clone(&owned.cancellation))
    };
    if restack_facts(repository.snapshot().as_ref()).as_ref() != Some(&plan.facts) {
        finish_plan(session_id, token);
        return restack_execution(
            MutationState::Stale,
            &plan,
            0,
            None,
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Some(NativeAdvancedRebaseFailureKind::Stale),
        );
    }
    let mut activities = Vec::new();
    if !validate_step_tips(&plan, activity, &mut activities) {
        finish_plan(session_id, token);
        return restack_execution(
            MutationState::Stale,
            &plan,
            0,
            None,
            Vec::new(),
            Vec::new(),
            activities,
            Some(NativeAdvancedRebaseFailureKind::Stale),
        );
    }
    let recovery_refs = match create_recovery_refs(token, &plan, activity, &mut activities) {
        Some(value) => value,
        None => {
            finish_plan(session_id, token);
            return restack_execution(
                MutationState::Failed,
                &plan,
                0,
                None,
                Vec::new(),
                Vec::new(),
                activities,
                Some(NativeAdvancedRebaseFailureKind::Git),
            );
        }
    };
    let mut completed = 0usize;
    let cancellation = cancellation.as_ref();
    for step in &plan.steps {
        if cancellation.load(Ordering::Acquire) {
            finish_plan(session_id, token);
            return restack_execution(
                if completed == 0 {
                    MutationState::Canceled
                } else {
                    MutationState::Partial
                },
                &plan,
                completed,
                None,
                recovery_refs,
                Vec::new(),
                activities,
                Some(NativeAdvancedRebaseFailureKind::Canceled),
            );
        }
        let branch_ref = full_ref(&step.branch);
        // Names Git cannot take as arguments stop the restack before anything runs.
        let Some(command) = restack_command(&plan.facts.worktree, step) else {
            finish_plan(session_id, token);
            return restack_execution_failure(NativeAdvancedRebaseFailureKind::Git);
        };
        if write_active_restack(&plan, token).is_err() {
            finish_plan(session_id, token);
            return restack_execution_failure(NativeAdvancedRebaseFailureKind::Git);
        }
        let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
        activities.push(id.get().to_string());
        let sink = activity.sink();
        let mut publish = |event| sink(event);
        let result = ActivityGitRunner::run_private(command, id, Some(cancellation), &mut publish);
        reload(repository);
        if !matches!(result.activity.status, ActivityStatus::Succeeded { .. }) {
            if crate::branch_facts::rebase_in_progress(&plan.facts.git_dir) {
                // The conflict continues through the conflict resolver, not this plan.
                finish_plan(session_id, token);
                let conflicts = conflict_paths(repository.snapshot().as_ref());
                return restack_execution(
                    MutationState::Conflict,
                    &plan,
                    completed,
                    Some(step.branch.clone()),
                    recovery_refs,
                    conflicts,
                    activities,
                    Some(NativeAdvancedRebaseFailureKind::Conflict),
                );
            }
            finish_plan(session_id, token);
            return restack_execution(
                if completed == 0 {
                    MutationState::Failed
                } else {
                    MutationState::Partial
                },
                &plan,
                completed,
                Some(step.branch.clone()),
                recovery_refs,
                Vec::new(),
                activities,
                Some(NativeAdvancedRebaseFailureKind::Git),
            );
        }
        if resolve_ref(&plan.facts.worktree, &branch_ref, activity, &mut activities).is_none() {
            // Git moved the branch but its new tip cannot be read: the user must inspect it.
            finish_plan(session_id, token);
            return restack_execution(
                MutationState::OutcomeUncertain,
                &plan,
                completed,
                Some(step.branch.clone()),
                recovery_refs,
                Vec::new(),
                activities,
                Some(NativeAdvancedRebaseFailureKind::Read),
            );
        }
        clear_active_restack(&plan.facts.common_git_dir);
        completed += 1;
    }
    let restored = checkout_branch(
        &plan.facts.worktree,
        &plan.facts.checkout_branch,
        activity,
        &mut activities,
    );
    clear_active_restack(&plan.facts.common_git_dir);
    finish_plan(session_id, token);
    restack_execution(
        if restored {
            MutationState::Completed
        } else {
            MutationState::ReconciledWithWarning
        },
        &plan,
        completed,
        None,
        recovery_refs,
        Vec::new(),
        activities,
        (!restored).then_some(NativeAdvancedRebaseFailureKind::Git),
    )
}

pub(crate) fn cancel_restack(session_id: u64, token: u64) -> bool {
    lock_registry().cancel(session_id, token)
}

/// Forgets the restack step a completed or abandoned rebase of `git_dir` was running.
pub(crate) fn finish_interrupted_restack(common_git_dir: &Path, git_dir: &Path) {
    if let Some(active) = active_restack(common_git_dir, git_dir) {
        let _ = fs::remove_dir_all(active);
    }
}

pub(crate) fn dismiss_session(session_id: u64) {
    lock_registry().dismiss_session(session_id);
}

fn suggestion(
    state: NativeFixupSuggestionState,
    evidence: Vec<NativeFixupEvidence>,
    activity_ids: Vec<String>,
) -> NativeFixupSuggestionResult {
    NativeFixupSuggestionResult {
        state,
        candidate: None,
        subject: None,
        fixup_message: None,
        squash_message: None,
        evidence,
        activity_ids,
        failure: None,
    }
}

fn suggestion_failure(kind: NativeAdvancedRebaseFailureKind) -> NativeFixupSuggestionResult {
    let mut result = suggestion(NativeFixupSuggestionState::NoBase, Vec::new(), Vec::new());
    result.failure = Some(NativeAdvancedRebaseFailure { kind });
    result
}

fn prefixed(prefix: &[u8], subject: &[u8]) -> Vec<u8> {
    let mut result = Vec::with_capacity(prefix.len() + subject.len());
    result.extend_from_slice(prefix);
    result.extend_from_slice(subject);
    result
}

fn descends_from(
    branch: &StackedBranch,
    root: &RefId,
    branches: &BTreeMap<RefId, &StackedBranch>,
) -> bool {
    let mut current = branch.upstream.as_ref();
    let mut visited = BTreeSet::new();
    while let Some(reference) = current {
        if reference == root {
            return true;
        }
        if !visited.insert(reference.clone()) {
            return false;
        }
        current = branches
            .get(reference)
            .and_then(|value| value.upstream.as_ref());
    }
    false
}

fn restack_step(
    branch: &StackedBranch,
    branches: &BTreeMap<RefId, &StackedBranch>,
) -> Option<NativeRestackStep> {
    let upstream = branch.upstream.as_ref()?;
    let parent = branches.get(upstream)?;
    let fork = branch.fork_point.as_ref()?;
    Some(NativeRestackStep {
        id: 0,
        branch: short_ref(&branch.name)?.to_vec(),
        expected_head: branch.head.as_str().to_owned(),
        old_parent: fork.as_str().to_owned(),
        new_parent: short_ref(upstream)?.to_vec(),
        expected_new_parent_head: parent.head.as_str().to_owned(),
        published: branch.published,
    })
}

fn short_ref(reference: &RefId) -> Option<&[u8]> {
    reference.as_bytes().strip_prefix(b"refs/heads/")
}

fn full_ref(short: &[u8]) -> RefId {
    let mut value = b"refs/heads/".to_vec();
    value.extend_from_slice(short);
    RefId::from_bytes(value).expect("validated local branch suffix remains a valid ref")
}

fn restack_facts(snapshot: &RepositorySnapshot) -> Option<RestackFacts> {
    if preflight_kind(snapshot) != NativeAdvancedRebaseFailureKind::Read {
        return None;
    }
    let repository = snapshot.repository.as_ref()?;
    let status = snapshot.status.as_ref()?;
    let BranchHead::Attached(branch) = &status.branch.head else {
        return None;
    };
    Some(RestackFacts {
        worktree: repository.worktree.worktree_root().as_path().to_path_buf(),
        git_dir: repository.worktree.git_dir().as_path().to_path_buf(),
        common_git_dir: repository
            .worktree
            .repository()
            .common_git_dir()
            .as_path()
            .to_path_buf(),
        checkout_branch: branch.as_bytes().to_vec(),
    })
}

fn preflight_kind(snapshot: &RepositorySnapshot) -> NativeAdvancedRebaseFailureKind {
    let Some(status) = snapshot.status.as_ref() else {
        return NativeAdvancedRebaseFailureKind::Read;
    };
    if matches!(status.branch.head, BranchHead::Detached) {
        return NativeAdvancedRebaseFailureKind::DetachedHead;
    }
    if status.working_tree != WorkingTreeState::Clean {
        return NativeAdvancedRebaseFailureKind::DirtyWorktree;
    }
    if !status.operations.is_empty() {
        return NativeAdvancedRebaseFailureKind::ActiveOperation;
    }
    NativeAdvancedRebaseFailureKind::Read
}

fn validate_step_tips(
    plan: &RestackPlan,
    activity: &ActivityStore,
    activity_ids: &mut Vec<String>,
) -> bool {
    let mut expected = BTreeMap::new();
    for step in &plan.steps {
        expected.insert(full_ref(&step.branch), step.expected_head.as_str());
        expected
            .entry(full_ref(&step.new_parent))
            .or_insert(step.expected_new_parent_head.as_str());
    }
    expected.into_iter().all(|(reference, oid)| {
        resolve_ref(&plan.facts.worktree, &reference, activity, activity_ids)
            .is_some_and(|actual| actual == oid)
    })
}

fn create_recovery_refs(
    token: u64,
    plan: &RestackPlan,
    activity: &ActivityStore,
    activity_ids: &mut Vec<String>,
) -> Option<Vec<Vec<u8>>> {
    let mut refs = Vec::new();
    for (index, step) in plan.steps.iter().enumerate() {
        let name = format!(
            "refs/gitlama/recovery/restack-{token}/{index}/{}",
            native_text(&step.branch)?
        );
        let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
        activity_ids.push(id.get().to_string());
        let command = GitProcessCommand::git("git")
            .current_dir(&plan.facts.worktree)
            .args([
                ProcessArgument::visible("update-ref"),
                ProcessArgument::visible(name.clone()),
                ProcessArgument::visible(step.expected_head.clone()),
            ])
            .redact_output();
        let sink = activity.sink();
        let mut publish = |event| sink(event);
        if !matches!(
            ActivityGitRunner::run_private(command, id, None, &mut publish)
                .activity
                .status,
            ActivityStatus::Succeeded { .. }
        ) {
            return None;
        }
        refs.push(name.into_bytes());
    }
    Some(refs)
}

fn resolve_ref(
    worktree: &Path,
    reference: &RefId,
    activity: &ActivityStore,
    activity_ids: &mut Vec<String>,
) -> Option<String> {
    let sink = activity.sink();
    let publish = |event| sink(event);
    let mut record = |id: devmil_git::activity::ActivityId| activity_ids.push(id.get().to_string());
    devmil_git::probes::resolve(
        std::ffi::OsStr::new("git"),
        worktree,
        &native_text(reference.as_bytes())?,
        &mut crate::git_probe::ProbeExecutor::publishing(None, &publish, &mut record),
    )
    .ok()
    .flatten()
    .map(|oid| oid.as_str().to_owned())
}

fn checkout_branch(
    worktree: &Path,
    branch: &[u8],
    activity: &ActivityStore,
    activity_ids: &mut Vec<String>,
) -> bool {
    let Some(branch) = native_os_string(branch.to_vec()) else {
        return false;
    };
    let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
    activity_ids.push(id.get().to_string());
    let command = GitProcessCommand::git("git")
        .current_dir(worktree)
        .args([
            ProcessArgument::visible("switch"),
            ProcessArgument::visible("--quiet"),
            ProcessArgument::redacted(branch, "<branch>"),
        ])
        .redact_output();
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    matches!(
        ActivityGitRunner::run_private(command, id, None, &mut publish)
            .activity
            .status,
        ActivityStatus::Succeeded { .. }
    )
}

fn write_active_restack(plan: &RestackPlan, token: u64) -> std::io::Result<()> {
    let store = crate::private_store::PrivateDir::repository(&plan.facts.common_git_dir, &[])?;
    store.remove("restack-active")?;
    let root = store.child("restack-active")?;
    root.write_new(
        "git-dir",
        &devmil_git::native_bytes::path_to_bytes(&plan.facts.git_dir),
    )?;
    root.write_new("token", token.to_string().as_bytes())?;
    Ok(())
}

fn active_restack(common_git_dir: &Path, git_dir: &Path) -> Option<PathBuf> {
    let root = common_git_dir.join("gitlama/restack-active");
    (fs::read(root.join("git-dir")).ok()?.as_slice()
        == devmil_git::native_bytes::path_to_bytes(git_dir).as_slice())
    .then_some(root)
}

fn clear_active_restack(common_git_dir: &Path) {
    let _ = fs::remove_dir_all(common_git_dir.join("gitlama/restack-active"));
}

fn conflict_paths(snapshot: &RepositorySnapshot) -> Vec<Vec<u8>> {
    snapshot
        .status
        .as_ref()
        .map(|status| {
            status
                .entries
                .iter()
                .filter(|entry| entry.is_conflicted())
                .map(|entry| devmil_git::native_bytes::path_to_bytes(entry.path().as_path()))
                .collect()
        })
        .unwrap_or_default()
}

fn reload(repository: &Repository) {
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

fn native_os_string(bytes: Vec<u8>) -> Option<OsString> {
    devmil_git::native_bytes::bytes_to_os_string(&bytes).ok()
}

fn native_text(bytes: &[u8]) -> Option<String> {
    String::from_utf8(bytes.to_vec()).ok()
}

fn finish_plan(session_id: u64, token: u64) {
    lock_registry().finish(session_id, token);
}

fn restack_plan_failure(
    root_branch: Vec<u8>,
    kind: NativeAdvancedRebaseFailureKind,
) -> NativeRestackPlanResult {
    NativeRestackPlanResult {
        token: None,
        root_branch,
        steps: Vec::new(),
        published_count: 0,
        incomplete: false,
        activity_ids: Vec::new(),
        failure: Some(NativeAdvancedRebaseFailure { kind }),
    }
}

#[allow(clippy::too_many_arguments)]
fn restack_execution(
    state: MutationState,
    plan: &RestackPlan,
    completed: usize,
    current_branch: Option<Vec<u8>>,
    recovery_refs: Vec<Vec<u8>>,
    conflicting_paths: Vec<Vec<u8>>,
    activity_ids: Vec<String>,
    failure: Option<NativeAdvancedRebaseFailureKind>,
) -> NativeRestackExecutionResult {
    NativeRestackExecutionResult {
        state: native_restack_state(state),
        completed_steps: completed.try_into().unwrap_or(u32::MAX),
        total_steps: plan.steps.len().try_into().unwrap_or(u32::MAX),
        current_branch,
        recovery_refs,
        conflicting_paths,
        activity_ids,
        failure: failure.map(|kind| NativeAdvancedRebaseFailure { kind }),
    }
}

fn restack_execution_failure(
    kind: NativeAdvancedRebaseFailureKind,
) -> NativeRestackExecutionResult {
    NativeRestackExecutionResult {
        state: NativeRestackExecutionState::Failed,
        completed_steps: 0,
        total_steps: 0,
        current_branch: None,
        recovery_refs: Vec::new(),
        conflicting_paths: Vec::new(),
        activity_ids: Vec::new(),
        failure: Some(NativeAdvancedRebaseFailure { kind }),
    }
}

/// The `git rebase --onto` for one restack step. The shared rebase settings
/// apply here too: auto-stash stays off whatever the user configured, and the
/// editors and locale are pinned.
fn restack_command(worktree: &Path, step: &NativeRestackStep) -> Option<GitProcessCommand> {
    let argv = devmil_git::rebase::rebase_onto_upstream_argv(
        &native_text(&step.new_parent)?,
        &step.old_parent,
        &native_text(&step.branch)?,
    )
    .ok()?;
    let mut command = GitProcessCommand::git("git")
        .current_dir(worktree)
        .args(argv.into_iter().map(ProcessArgument::visible));
    for (name, value) in devmil_git::rebase::rebase_environment() {
        command = command
            .env(name, value)
            .expect("constant environment is valid");
    }
    Some(command.redact_output())
}

crate::family_failures!(NativeAdvancedRebaseFailureKind, "restack", {
    InvalidRequest => InvalidRequest,
    DirtyWorktree => Precondition,
    DetachedHead => Precondition,
    ActiveOperation => Precondition,
    PublicationConfirmationRequired => Precondition,
    Stale => Stale,
    Canceled => Canceled,
    Conflict => Conflict,
    TooLarge => TooLarge,
    Unsupported => Unsupported,
    Read => Read,
    Git => Git,
});

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_uncertain_restack_stays_uncertain() {
        assert_eq!(
            native_restack_state(MutationState::OutcomeUncertain),
            NativeRestackExecutionState::OutcomeUncertain
        );
        assert_eq!(
            native_restack_state(MutationState::Canceled),
            NativeRestackExecutionState::Canceled
        );
    }

    #[test]
    fn canceled_fixup_read_remains_canceled_instead_of_becoming_no_base() {
        let canceled = RepositoryError {
            kind: RepositoryErrorKind::Canceled,
            message: "canceled".to_owned(),
            activity: None,
        };
        let ordinary = RepositoryError {
            kind: RepositoryErrorKind::Read,
            message: "read failed".to_owned(),
            activity: None,
        };

        assert_eq!(
            fixup_read_failure(&canceled),
            Some(NativeAdvancedRebaseFailureKind::Canceled)
        );
        assert_eq!(fixup_read_failure(&ordinary), None);
    }

    #[test]
    fn restack_pins_the_shared_rebase_configuration() {
        let step = NativeRestackStep {
            id: 1,
            branch: b"refs/heads/topic".to_vec(),
            expected_head: "a".repeat(40),
            old_parent: "b".repeat(40),
            new_parent: b"refs/heads/main".to_vec(),
            expected_new_parent_head: "c".repeat(40),
            published: false,
        };
        let command = super::restack_command(Path::new("/tmp"), &step)
            .unwrap()
            .activity_command();
        let arguments: Vec<_> = command
            .arguments
            .iter()
            .map(|argument| argument.display.as_str())
            .collect();
        assert_eq!(
            &arguments[..4],
            ["-c", "rebase.autoStash=false", "rebase", "--onto"]
        );
        let environment: Vec<_> = command
            .environment
            .iter()
            .map(|item| (item.name.as_str(), item.display.as_str()))
            .collect();
        assert!(environment.contains(&("LC_ALL", "C")));
        assert!(environment.contains(&("GIT_EDITOR", "true")));
        assert!(environment.contains(&("GIT_SEQUENCE_EDITOR", "true")));
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::advanced_rebase::{NativeFixupSuggestionState, NativeRestackExecutionState};
    use crate::application::{conflicts::*, rebase::*, session::*};
    use crate::test_support::*;

    use crate::conflict::{
        NativeConflictContinuationState, NativeConflictSequencerAction, NativeConflictSideChoice,
    };

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[test]
    fn fixup_evidence_and_restack_use_exact_shared_topology_and_recovery() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("a.txt"), b"a0\n").unwrap();
        fs::write(fixture.0.join("b.txt"), b"b0\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "initial"]);
        fs::write(fixture.0.join("a.txt"), b"a1\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "touch a"]);
        let touch_a = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(fixture.0.join("b.txt"), b"b1\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "touch b"]);
        transfer_git(&fixture.0, &["switch", "-c", "base"]);
        fs::write(fixture.0.join("base.txt"), b"base one\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base one"]);
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        transfer_git(&fixture.0, &["branch", "--set-upstream-to=base", "topic"]);
        fs::write(fixture.0.join("topic.txt"), b"topic\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "topic"]);
        transfer_git(&fixture.0, &["switch", "-c", "leaf"]);
        transfer_git(&fixture.0, &["branch", "--set-upstream-to=topic", "leaf"]);
        fs::write(fixture.0.join("leaf.txt"), b"leaf\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "leaf"]);
        let original_leaf = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&fixture.0, &["switch", "base"]);
        fs::write(fixture.0.join("base.txt"), b"base two\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "base two"]);

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            12_172,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let exact = repository_session_fixup_suggestion(
            session.session_id,
            session.generation,
            Some(touch_a.clone()),
            Vec::new(),
        );
        assert_eq!(exact.state, NativeFixupSuggestionState::Suggested);
        assert_eq!(exact.candidate.as_deref(), Some(touch_a.as_str()));
        assert_eq!(
            exact.fixup_message.as_deref(),
            Some(b"fixup! touch a".as_slice())
        );
        let ambiguous = repository_session_fixup_suggestion(
            session.session_id,
            session.generation,
            None,
            vec![b"a.txt".to_vec(), b"b.txt".to_vec()],
        );
        assert_eq!(ambiguous.state, NativeFixupSuggestionState::Ambiguous);
        assert_eq!(ambiguous.evidence.len(), 2);

        let stale = repository_session_restack_plan(
            session.session_id,
            session.generation,
            b"base".to_vec(),
        );
        assert_eq!(stale.steps.len(), 2);
        transfer_git(&fixture.0, &["branch", "-f", "leaf", "main"]);
        let stale_result = repository_session_restack_execute(
            session.session_id,
            session.generation,
            stale.token.unwrap(),
            true,
        );
        assert_eq!(stale_result.state, NativeRestackExecutionState::Stale);
        transfer_git(&fixture.0, &["branch", "-f", "leaf", &original_leaf]);
        refresh_session(&session);

        let plan = repository_session_restack_plan(
            session.session_id,
            session.generation,
            b"base".to_vec(),
        );
        assert_eq!(plan.steps.len(), 2);
        assert_eq!(plan.steps[0].branch, b"topic");
        assert_eq!(plan.steps[1].branch, b"leaf");
        let result = repository_session_restack_execute(
            session.session_id,
            session.generation,
            plan.token.unwrap(),
            true,
        );
        assert_eq!(result.state, NativeRestackExecutionState::Completed);
        assert_eq!(result.completed_steps, 2);
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["branch", "--show-current"]))
                .unwrap()
                .trim(),
            "base"
        );
        let base_head = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "base"]))
            .unwrap()
            .trim()
            .to_owned();
        let topic_head = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "topic"]))
            .unwrap()
            .trim()
            .to_owned();
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["merge-base", "base", "topic"]))
                .unwrap()
                .trim(),
            base_head
        );
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["merge-base", "topic", "leaf"]))
                .unwrap()
                .trim(),
            topic_head
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn restack_conflict_survives_restart_and_records_completed_step_recovery() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("conflict.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "initial"]);
        transfer_git(&fixture.0, &["switch", "-c", "base"]);
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        transfer_git(&fixture.0, &["branch", "--set-upstream-to=base", "topic"]);
        fs::write(fixture.0.join("conflict.txt"), b"topic\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "topic"]);
        transfer_git(&fixture.0, &["switch", "base"]);
        fs::write(fixture.0.join("conflict.txt"), b"new base\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "new base"]);

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            12_173,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let plan = repository_session_restack_plan(
            session.session_id,
            session.generation,
            b"base".to_vec(),
        );
        assert_eq!(plan.steps.len(), 1);
        let result = repository_session_restack_execute(
            session.session_id,
            session.generation,
            plan.token.unwrap(),
            true,
        );
        assert_eq!(result.state, NativeRestackExecutionState::Conflict);
        assert_eq!(result.completed_steps, 0);
        assert_eq!(result.current_branch.as_deref(), Some(b"topic".as_slice()));
        assert_eq!(result.conflicting_paths, [b"conflict.txt".to_vec()]);
        assert!(repository_session_close(session.session_id, session.generation).accepted);

        let reopened = repository_session_open_with_options(
            fixture.0.clone(),
            12_174,
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
        let file = &conflicts.files[0];
        assert!(repository_session_conflict_choose_side(
            reopened.session_id,
            reopened.generation,
            file.path.clone(),
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
            fs::read(fixture.0.join("conflict.txt")).unwrap(),
            b"topic\n"
        );
        assert!(repository_session_close(reopened.session_id, reopened.generation).accepted);
    }
}
