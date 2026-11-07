//! Session-bound interactive rebase planning and execution.
pub use gitlama_contract::rebase_operation::*;

use crate::activity::{allocate_activity_id, ActivityStore};
use crate::conflict::{
    NativeConflictFailureKind, NativeConflictOperationKind, NativeConflictSequencerAction,
};
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::interrupted::{InterruptedOperation, Interruption, SequencerStep};
use crate::operations::{coordinate_mutation, ExecutionFailure};
use crate::preview_store::PreviewStore;
use devmil_git::activity::ActivityStatus;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::rebase::{
    interactive_rebase_environment, interactive_rebase_onto_argv, render_todo, validate_plan,
    CommitTarget, RebaseAction, RebaseCommand, RebaseEntryKind, RebasePlan, RebasePlanEntry,
    SequenceEditorProtocol, TodoOid,
};
use devmil_git::sequence_editor::apply_prepared_plan;
use devmil_git::status::{BranchHead, WorkingTreeState};
use devmil_git::types::{ObjectId, RepositoryRelativePath};
use devmil_git::{Repository, RepositorySnapshot};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

const MAX_REBASE_COMMITS: usize = 256;
const MAX_MESSAGE_BYTES: usize = 64 * 1024;
const PREVIEW_CAPACITY_PER_SESSION: usize = 8;

const fn native_state(state: MutationState) -> NativeRebaseExecutionState {
    match state {
        MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
            NativeRebaseExecutionState::Completed
        }
        MutationState::ReconciledWithWarning => NativeRebaseExecutionState::ReconciledWithWarning,
        MutationState::Conflict => NativeRebaseExecutionState::Conflict,
        MutationState::EditStop => NativeRebaseExecutionState::EditStop,
        MutationState::Interrupted | MutationState::Partial => {
            NativeRebaseExecutionState::Interrupted
        }
        MutationState::Stale => NativeRebaseExecutionState::Stale,
        MutationState::Canceled | MutationState::Failed => NativeRebaseExecutionState::Failed,
        MutationState::OutcomeUncertain => NativeRebaseExecutionState::OutcomeUncertain,
    }
}

type RebaseFacts = crate::domain::facts::BranchFacts;

#[derive(Clone)]
struct Draft {
    onto: ObjectId,
    facts: RebaseFacts,
    plan: RebasePlan,
    published: HashSet<String>,
    accepted: Option<AcceptedPlan>,
}

#[derive(Clone)]
struct AcceptedPlan {
    todo: Vec<u8>,
    instructions: Vec<NativeRebaseInstruction>,
}

static REGISTRY: OnceLock<Mutex<PreviewStore<Draft>>> = OnceLock::new();

fn lock_registry() -> std::sync::MutexGuard<'static, PreviewStore<Draft>> {
    crate::preview_store::lock(
        REGISTRY.get_or_init(|| Mutex::new(PreviewStore::new(PREVIEW_CAPACITY_PER_SESSION))),
    )
}

pub(crate) fn load_plan(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    onto: String,
    onto_name: Option<Vec<u8>>,
) -> NativeRebasePlanResult {
    let snapshot = repository.snapshot();
    if let Some(kind) = preflight_failure(snapshot.as_ref()) {
        return plan_failure(onto, onto_name, kind);
    }
    let Some(facts) = facts(snapshot.as_ref()) else {
        return plan_failure(onto, onto_name, NativeRebaseFailureKind::Read);
    };
    if facts.published
        && onto_name
            .as_ref()
            .is_some_and(|name| name == &facts.branch_name)
    {
        return plan_failure(onto, onto_name, NativeRebaseFailureKind::InvalidRequest);
    }
    let onto_id = match ObjectId::parse(onto.clone()) {
        Ok(value) => value,
        Err(_) => return plan_failure(onto, onto_name, NativeRebaseFailureKind::InvalidRequest),
    };
    if onto_name
        .as_ref()
        .is_some_and(|name| !snapshot_ref_matches(repository.snapshot().as_ref(), name, &onto_id))
    {
        return plan_failure(onto, onto_name, NativeRebaseFailureKind::Stale);
    }
    let mut activity_ids = Vec::new();
    let output = match run_read(
        &facts.worktree,
        [
            "log".to_owned(),
            "-z".to_owned(),
            "--reverse".to_owned(),
            "--no-merges".to_owned(),
            format!("--format={}", devmil_git::history::SUBJECT_LOG_FORMAT),
            format!("{}..{}", onto_id.as_str(), facts.head.as_str()),
            format!("--max-count={}", MAX_REBASE_COMMITS + 1),
        ],
        activity,
        &mut activity_ids,
    ) {
        Some(value) => value,
        None => return plan_failure(onto, onto_name, NativeRebaseFailureKind::Read),
    };
    let records = match devmil_git::history::parse_subject_log(&output) {
        Ok(value) if !value.is_empty() && value.len() <= MAX_REBASE_COMMITS => value,
        Ok(_) => return plan_failure(onto, onto_name, NativeRebaseFailureKind::EmptyPlan),
        Err(_) => return plan_failure(onto, onto_name, NativeRebaseFailureKind::Read),
    };
    let Some(published) = published_commits(&facts, &onto_id, activity, &mut activity_ids) else {
        return plan_failure(onto, onto_name, NativeRebaseFailureKind::Read);
    };
    let entries = records
        .iter()
        .map(|(oid, subject)| {
            let oid = TodoOid::new(oid.as_str()).expect("full Git object IDs are valid todo IDs");
            RebasePlanEntry::synthesized(RebaseEntryKind::Command(RebaseCommand::Pick(
                CommitTarget::new(oid, subject.clone()),
            )))
        })
        .collect();
    let plan = RebasePlan::new(entries);
    let instructions = instructions(&plan, &published);
    let published_count = instructions.iter().filter(|item| item.published).count();
    let token = lock_registry().issue(
        session_id,
        Draft {
            onto: onto_id,
            facts: facts.clone(),
            plan,
            published,
            accepted: None,
        },
    );
    NativeRebasePlanResult {
        token: Some(token),
        onto,
        onto_name,
        current_branch: facts.branch_name,
        current_head: facts.head.as_str().to_owned(),
        instructions,
        published_count: published_count.try_into().unwrap_or(u32::MAX),
        activity_ids: activity_ids.into_iter().map(|id| id.to_string()).collect(),
        failure: None,
    }
}

pub(crate) fn preview(
    session_id: u64,
    token: u64,
    edited: Vec<NativeRebaseInstruction>,
    acknowledge_published_history: bool,
    apply_autosquash: bool,
) -> NativeRebasePreviewResult {
    let mut registry = lock_registry();
    let Some(owned) = registry.get_mut(session_id, token) else {
        return preview_failure(NativeRebaseFailureKind::InvalidRequest);
    };
    if owned.running {
        return preview_failure(NativeRebaseFailureKind::InvalidRequest);
    }
    let draft = &mut owned.value;
    let mut plan = match apply_edits(&draft.plan, &edited) {
        Ok(value) => value,
        Err(kind) => return preview_failure(kind),
    };
    let autosquash_applied = if apply_autosquash {
        plan.apply_autosquash_preview()
    } else {
        0
    };
    if validate_plan(&plan).is_err() {
        return preview_failure(NativeRebaseFailureKind::InvalidPlan);
    }
    let instructions = instructions(&plan, &draft.published);
    let published_count = instructions.iter().filter(|item| item.published).count();
    if published_count > 0 && !acknowledge_published_history {
        return preview_failure(NativeRebaseFailureKind::PublicationConfirmationRequired);
    }
    let todo = render_todo(&plan);
    draft.accepted = Some(AcceptedPlan {
        todo: todo.clone(),
        instructions: instructions.clone(),
    });
    NativeRebasePreviewResult {
        token: Some(token),
        arguments: interactive_rebase_onto_argv(draft.onto.as_str()),
        todo,
        instruction_count: draft
            .accepted
            .as_ref()
            .map_or(0, |value| value.instructions.len())
            .try_into()
            .unwrap_or(u32::MAX),
        published_count: published_count.try_into().unwrap_or(u32::MAX),
        instructions,
        autosquash_applied: autosquash_applied.try_into().unwrap_or(u32::MAX),
        failure: None,
    }
}

pub(crate) fn execute(
    session_id: u64,
    token: u64,
    repository: &Repository,
    activity: &ActivityStore,
) -> NativeRebaseExecutionResult {
    let (draft, accepted, cancellation) = {
        let mut registry = lock_registry();
        let Some(owned) = registry.get_mut(session_id, token) else {
            return execution_failure(NativeRebaseFailureKind::InvalidRequest);
        };
        let Some(accepted) = owned.value.accepted.clone() else {
            return execution_failure(NativeRebaseFailureKind::InvalidPlan);
        };
        if owned.running {
            return execution_failure(NativeRebaseFailureKind::InvalidRequest);
        }
        owned.running = true;
        owned.cancellation.store(false, Ordering::Release);
        (
            owned.value.clone(),
            accepted,
            Arc::clone(&owned.cancellation),
        )
    };
    if facts(repository.snapshot().as_ref()).as_ref() != Some(&draft.facts) {
        finish(session_id, token);
        return NativeRebaseExecutionResult {
            state: NativeRebaseExecutionState::Stale,
            failure: Some(NativeRebaseFailure {
                kind: NativeRebaseFailureKind::Stale,
            }),
            activity_ids: Vec::new(),
            conflicting_paths: Vec::new(),
            running_instruction: None,
        };
    }
    let runtime = match prepare_runtime(token, &draft, &accepted) {
        Ok(value) => value,
        Err(kind) => {
            finish(session_id, token);
            return execution_failure(kind);
        }
    };
    let sink = activity.sink();
    let activity_ids = Mutex::new(Vec::new());
    let interrupted = AtomicBool::new(false);
    let after_head = Mutex::new(None);
    let operation_failure = Mutex::new(None);
    let outcome = coordinate_mutation(repository, cancellation.as_ref(), |cancellation| {
        let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
        activity_ids.lock().unwrap().push(id.get());
        let arguments = interactive_rebase_onto_argv(draft.onto.as_str());
        let mut environment = interactive_rebase_environment(
            &runtime.sequence_helper,
            &runtime.plan,
            SequenceEditorProtocol {
                mode_variable: "GITLAMA_SEQUENCE_EDITOR_MODE",
                mode_value: "prepared",
                plan_variable: "GITLAMA_REBASE_PLAN",
            },
        );
        if let Some((_, value)) = environment
            .iter_mut()
            .find(|(name, _)| name == "GIT_EDITOR")
        {
            *value = runtime.message_helper.to_string_lossy().into_owned();
        }
        let mut command = GitProcessCommand::git(repository.git_executable())
            .current_dir(&draft.facts.worktree)
            .args(arguments.into_iter().map(ProcessArgument::visible))
            .redact_output();
        for (name, value) in environment {
            command = if name == "LC_ALL" || name == "GITLAMA_SEQUENCE_EDITOR_MODE" {
                command.env(name, value)
            } else {
                command.env_redacted(name, value)
            }
            .map_err(|_| ExecutionFailure::Definite)?;
        }
        command = command
            .env_redacted("GITLAMA_REBASE_MESSAGES", &runtime.messages)
            .and_then(|value| {
                value.env_redacted("GITLAMA_REBASE_MESSAGE_COUNTER", &runtime.counter)
            })
            .map_err(|_| ExecutionFailure::Definite)?;
        let mut publish = |event| sink(event);
        let result = ActivityGitRunner::run_private(command, id, Some(cancellation), &mut publish);
        #[cfg(test)]
        if !matches!(result.activity.status, ActivityStatus::Succeeded { .. }) {
            let mut stderr = result.stderr;
            eprintln!(
                "rebase diagnostic: Git command failed ({:?}, {})",
                result.activity.status,
                classify_rebase_git_failure(&stderr.take_bytes())
            );
        }
        match result.activity.status {
            ActivityStatus::Succeeded { .. } => {
                if crate::branch_facts::rebase_in_progress(&draft.facts.git_dir) {
                    interrupted.store(true, Ordering::Release);
                    return Ok(());
                }
                *after_head.lock().unwrap() =
                    resolve_head(&draft.facts.worktree, cancellation, &sink, &activity_ids);
                if after_head.lock().unwrap().is_none() {
                    Err(ExecutionFailure::Uncertain)
                } else {
                    Ok(())
                }
            }
            ActivityStatus::Canceled { .. } => {
                if crate::branch_facts::rebase_in_progress(&draft.facts.git_dir) {
                    interrupted.store(true, Ordering::Release);
                    Ok(())
                } else {
                    *operation_failure.lock().unwrap() = Some(NativeRebaseFailureKind::Canceled);
                    Err(ExecutionFailure::Canceled)
                }
            }
            ActivityStatus::Running
            | ActivityStatus::Failed { .. }
            | ActivityStatus::TimedOut { .. }
            | ActivityStatus::LaunchError { .. } => {
                if crate::branch_facts::rebase_in_progress(&draft.facts.git_dir) {
                    interrupted.store(true, Ordering::Release);
                    Ok(())
                } else {
                    *operation_failure.lock().unwrap() = Some(NativeRebaseFailureKind::Failed);
                    Err(ExecutionFailure::Definite)
                }
            }
        }
    });
    finish(session_id, token);
    let is_interrupted = interrupted.load(Ordering::Acquire);
    if !is_interrupted {
        let _ = fs::remove_dir_all(&runtime.root);
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
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let running_instruction = if is_interrupted {
        read_running_instruction(&draft.facts.git_dir)
    } else {
        None
    };
    let mut result = MutationOutcome::from_terminal(outcome)
        .with_failure(operation_failure.into_inner().unwrap());
    if is_interrupted {
        // The repository's own state decides: the rebase ran and stopped.
        result.state = if !conflicting_paths.is_empty() {
            MutationState::Conflict
        } else if running_instruction
            .as_deref()
            .is_some_and(|line| line.starts_with(b"edit "))
        {
            MutationState::EditStop
        } else {
            MutationState::Interrupted
        };
    }
    NativeRebaseExecutionResult {
        state: native_state(result.state),
        failure: result.failure.map(|kind| NativeRebaseFailure { kind }),
        activity_ids: activity_ids
            .into_inner()
            .unwrap()
            .into_iter()
            .map(|id| id.to_string())
            .collect(),
        conflicting_paths,
        running_instruction,
    }
}

#[cfg(test)]
fn classify_rebase_git_failure(stderr: &[u8]) -> &'static str {
    let stderr = String::from_utf8_lossy(stderr).to_ascii_lowercase();
    if stderr.contains("problem with the editor") {
        "editor"
    } else if stderr.contains("could not apply") {
        "apply"
    } else if stderr.contains("invalid upstream") {
        "upstream"
    } else {
        "other"
    }
}

pub(crate) fn cancel(session_id: u64, token: u64) -> bool {
    lock_registry().cancel(session_id, token)
}

pub(crate) fn dismiss_session(session_id: u64) {
    lock_registry().dismiss_session(session_id);
}

fn apply_edits(
    original: &RebasePlan,
    edited: &[NativeRebaseInstruction],
) -> Result<RebasePlan, NativeRebaseFailureKind> {
    if edited.is_empty() || edited.len() != original.entries().len() {
        return Err(NativeRebaseFailureKind::InvalidPlan);
    }
    let expected = original
        .entries()
        .iter()
        .map(RebasePlanEntry::identity)
        .collect::<HashSet<_>>();
    let received = edited.iter().map(|item| item.id).collect::<HashSet<_>>();
    if expected != received || received.len() != edited.len() {
        return Err(NativeRebaseFailureKind::InvalidPlan);
    }
    let mut plan = original.clone();
    for (destination, instruction) in edited.iter().enumerate() {
        let source = plan
            .entries()
            .iter()
            .position(|entry| entry.identity() == instruction.id)
            .ok_or(NativeRebaseFailureKind::InvalidPlan)?;
        plan.move_entry(source, destination)
            .map_err(|_| NativeRebaseFailureKind::InvalidPlan)?;
        let action = match instruction.action {
            NativeRebaseAction::Pick => RebaseAction::Pick,
            NativeRebaseAction::Reword => RebaseAction::Reword,
            NativeRebaseAction::Edit => RebaseAction::Edit,
            NativeRebaseAction::Squash => RebaseAction::Squash,
            NativeRebaseAction::Fixup => RebaseAction::Fixup { amend: None },
            NativeRebaseAction::Drop => RebaseAction::Drop,
        };
        plan.set_action(destination, action)
            .map_err(|_| NativeRebaseFailureKind::InvalidPlan)?;
        if instruction.action == NativeRebaseAction::Reword {
            let message = instruction
                .replacement_message
                .as_ref()
                .filter(|value| !value.is_empty() && value.len() <= MAX_MESSAGE_BYTES)
                .ok_or(NativeRebaseFailureKind::InvalidPlan)?;
            plan.set_reword_message(destination, Some(message.clone()))
                .map_err(|_| NativeRebaseFailureKind::InvalidPlan)?;
        }
    }
    Ok(plan)
}

fn instructions(plan: &RebasePlan, published: &HashSet<String>) -> Vec<NativeRebaseInstruction> {
    let mut last_base_id = None;
    plan.entries()
        .iter()
        .filter_map(|entry| {
            let command = entry.command()?;
            let (action, oid, subject, replacement_message) = match command {
                RebaseCommand::Pick(value) => {
                    (NativeRebaseAction::Pick, value.oid(), value.subject(), None)
                }
                RebaseCommand::Reword(value) => (
                    NativeRebaseAction::Reword,
                    value.oid(),
                    value.subject(),
                    value.message_override().map(<[u8]>::to_vec),
                ),
                RebaseCommand::Edit(value) => {
                    (NativeRebaseAction::Edit, value.oid(), value.subject(), None)
                }
                RebaseCommand::Squash(value) => (
                    NativeRebaseAction::Squash,
                    value.oid(),
                    value.subject(),
                    None,
                ),
                RebaseCommand::Fixup(value) => (
                    NativeRebaseAction::Fixup,
                    value.oid(),
                    value.subject(),
                    None,
                ),
                RebaseCommand::Drop(value) => {
                    (NativeRebaseAction::Drop, value.oid(), value.subject(), None)
                }
                _ => return None,
            };
            let autosquash_base_id = matches!(
                action,
                NativeRebaseAction::Squash | NativeRebaseAction::Fixup
            )
            .then_some(last_base_id)
            .flatten();
            if !matches!(
                action,
                NativeRebaseAction::Squash | NativeRebaseAction::Fixup | NativeRebaseAction::Drop
            ) {
                last_base_id = Some(entry.identity());
            }
            Some(NativeRebaseInstruction {
                id: entry.identity(),
                action,
                oid: oid.as_written().to_owned(),
                subject: subject.to_vec(),
                published: published.contains(oid.as_written()),
                replacement_message,
                autosquash_base_id,
            })
        })
        .collect()
}

struct Runtime {
    root: PathBuf,
    sequence_helper: PathBuf,
    message_helper: PathBuf,
    plan: PathBuf,
    messages: PathBuf,
    counter: PathBuf,
}

fn prepare_runtime(
    token: u64,
    draft: &Draft,
    accepted: &AcceptedPlan,
) -> Result<Runtime, NativeRebaseFailureKind> {
    #[cfg(not(any(unix, windows)))]
    {
        let _ = (token, draft, accepted);
        return Err(NativeRebaseFailureKind::Unsupported);
    }
    #[cfg(any(unix, windows))]
    {
        let failed = |_| NativeRebaseFailureKind::Failed;
        let rebase_root =
            crate::private_store::PrivateDir::repository(&draft.facts.common_git_dir, &["rebase"])
                .map_err(failed)?;
        let mut entropy = [0_u8; 8];
        getrandom::fill(&mut entropy).map_err(|_| NativeRebaseFailureKind::Failed)?;
        let suffix = entropy
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let runtime = rebase_root
            .child(&format!("{}-{token}-{suffix}", std::process::id()))
            .map_err(failed)?;
        let messages = runtime.child("messages").map_err(failed)?;
        runtime
            .write_new("prepared-todo", &accepted.todo)
            .map_err(failed)?;
        runtime.write_new("validation-todo", &[]).map_err(failed)?;
        for (name, bytes) in [
            ("before-head", draft.facts.head.as_str().as_bytes()),
            ("branch-ref", draft.facts.branch_ref.as_slice()),
            (
                "git-dir",
                &devmil_git::native_bytes::path_to_bytes(&draft.facts.git_dir),
            ),
        ] {
            runtime.write_new(name, bytes).map_err(failed)?;
        }
        let plan = runtime.entry_path("prepared-todo");
        apply_prepared_plan(&plan, &runtime.entry_path("validation-todo"))
            .map_err(|_| NativeRebaseFailureKind::InvalidPlan)?;
        let mut message_index = 0usize;
        for instruction in &accepted.instructions {
            if instruction.action == NativeRebaseAction::Reword {
                let message = instruction
                    .replacement_message
                    .as_ref()
                    .ok_or(NativeRebaseFailureKind::InvalidPlan)?;
                messages
                    .write_new(&message_index.to_string(), message)
                    .map_err(failed)?;
                message_index += 1;
            }
        }
        runtime
            .write_new("message-counter", b"0\n")
            .map_err(failed)?;
        #[cfg(unix)]
        let (sequence_helper, message_helper) = {
            runtime
                .write_new_executable(
                    "sequence-editor",
                    b"#!/bin/sh\nset -eu\nexec /bin/cp \"$GITLAMA_REBASE_PLAN\" \"$1\"\n",
                )
                .map_err(failed)?;
            runtime
                .write_new_executable(
                    "message-editor",
                    b"#!/bin/sh\nset -eu\nread -r n < \"$GITLAMA_REBASE_MESSAGE_COUNTER\"\n/bin/cp \"$GITLAMA_REBASE_MESSAGES/$n\" \"$1\"\nprintf '%s\\n' \"$((n + 1))\" > \"$GITLAMA_REBASE_MESSAGE_COUNTER\"\n",
                )
                .map_err(failed)?;
            (
                runtime.entry_path("sequence-editor"),
                runtime.entry_path("message-editor"),
            )
        };
        #[cfg(windows)]
        let (sequence_helper, message_helper) = {
            runtime
                .write_new(
                    "sequence-editor.ps1",
                    b"param([Parameter(Mandatory=$true)][string]$Target)\r\n$ErrorActionPreference = 'Stop'\r\nCopy-Item -LiteralPath $env:GITLAMA_REBASE_PLAN -Destination $Target -Force\r\nexit 0\r\n",
                )
                .map_err(failed)?;
            runtime
                .write_new(
                    "message-editor.ps1",
                    b"param([Parameter(Mandatory=$true)][string]$Target)\r\n$ErrorActionPreference = 'Stop'\r\n$message = Get-ChildItem -LiteralPath $env:GITLAMA_REBASE_MESSAGES -File | Sort-Object { [int]$_.Name } | Select-Object -First 1\r\nif ($null -eq $message) { exit 1 }\r\nCopy-Item -LiteralPath $message.FullName -Destination $Target -Force\r\nRemove-Item -LiteralPath $message.FullName -Force\r\nexit 0\r\n",
                )
                .map_err(failed)?;
            // Git treats editor values as shell command strings. PowerShell's
            // `-File` contract preserves the appended todo/message path as one
            // native argument and avoids cmd.exe's nested quoting rules.
            let command = |script: &str| {
                PathBuf::from(format!(
                    "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{}\"",
                    runtime.entry_path(script).to_string_lossy().replace('\\', "/")
                ))
            };
            (
                command("sequence-editor.ps1"),
                command("message-editor.ps1"),
            )
        };
        Ok(Runtime {
            root: runtime.path().to_path_buf(),
            sequence_helper,
            message_helper,
            plan,
            messages: messages.path().to_path_buf(),
            counter: runtime.entry_path("message-counter"),
        })
    }
}

fn facts(snapshot: &RepositorySnapshot) -> Option<RebaseFacts> {
    crate::domain::facts::BranchFacts::capture(snapshot)
}

fn preflight_failure(snapshot: &RepositorySnapshot) -> Option<NativeRebaseFailureKind> {
    let status = snapshot.status.as_ref()?;
    if matches!(status.branch.head, BranchHead::Detached) {
        return Some(NativeRebaseFailureKind::DetachedHead);
    }
    if status.working_tree != WorkingTreeState::Clean {
        return Some(NativeRebaseFailureKind::DirtyWorktree);
    }
    if !status.operations.is_empty() {
        return Some(NativeRebaseFailureKind::ActiveOperation);
    }
    None
}

fn snapshot_ref_matches(snapshot: &RepositorySnapshot, name: &[u8], target: &ObjectId) -> bool {
    snapshot.refs.iter().any(|section| match section {
        devmil_git::loading::refs::RefsSectionData::Branches { rows, .. } => {
            rows.iter().any(|row| {
                row.target == *target
                    && row
                        .id
                        .as_bytes()
                        .strip_prefix(b"refs/heads/")
                        .is_some_and(|short| short == name)
            })
        }
        devmil_git::loading::refs::RefsSectionData::Remotes { references, .. } => {
            references.iter().any(|row| {
                row.target == *target
                    && row
                        .id
                        .as_bytes()
                        .strip_prefix(b"refs/remotes/")
                        .is_some_and(|short| short == name)
            })
        }
        _ => false,
    })
}

/// The plan's commits that any remote-tracking ref already contains. Whether rewriting them
/// needs confirmation is GitLama's policy.
fn published_commits(
    facts: &RebaseFacts,
    onto: &ObjectId,
    activity: &ActivityStore,
    activity_ids: &mut Vec<u64>,
) -> Option<HashSet<String>> {
    let sink = activity.sink();
    let publish = |event| sink(event);
    let mut record = |id: devmil_git::activity::ActivityId| activity_ids.push(id.get());
    devmil_git::probes::published_commits(
        std::ffi::OsStr::new("git"),
        &facts.worktree,
        &devmil_git::probes::CommitRange {
            base: Some(onto.clone()),
            tip: facts.head.clone(),
        },
        MAX_REBASE_COMMITS,
        &mut crate::git_probe::ProbeExecutor::publishing(None, &publish, &mut record),
    )
    .ok()
    .map(|commits| {
        commits
            .into_iter()
            .map(|commit| commit.as_str().to_owned())
            .collect()
    })
}

fn run_read(
    worktree: &Path,
    arguments: impl IntoIterator<Item = String>,
    activity: &ActivityStore,
    activity_ids: &mut Vec<u64>,
) -> Option<Vec<u8>> {
    let id = allocate_activity_id();
    activity_ids.push(id.get());
    let command = GitProcessCommand::git("git")
        .current_dir(worktree)
        .args(arguments.into_iter().map(ProcessArgument::visible))
        .redact_output();
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let mut result = ActivityGitRunner::run_private(command, id, None, &mut publish);
    matches!(result.activity.status, ActivityStatus::Succeeded { .. })
        .then(|| result.stdout.take_bytes())
}

use crate::branch_facts::resolve_head;

fn read_running_instruction(git_dir: &Path) -> Option<Vec<u8>> {
    for directory in [git_dir.join("rebase-merge"), git_dir.join("rebase-apply")] {
        for name in ["done", "git-rebase-todo"] {
            let Ok(bytes) = fs::read(directory.join(name)) else {
                continue;
            };
            let line = if name == "done" {
                bytes
                    .rsplit(|byte| *byte == b'\n')
                    .find(|line| !line.is_empty())
            } else {
                bytes
                    .split(|byte| *byte == b'\n')
                    .find(|line| !line.is_empty())
            };
            if let Some(line) = line {
                return Some(line.to_vec());
            }
        }
    }
    None
}

fn native_path(path: &RepositoryRelativePath) -> Vec<u8> {
    devmil_git::native_bytes::path_to_bytes(path.as_path())
}

fn finish(session_id: u64, token: u64) {
    lock_registry().finish(session_id, token);
}

fn plan_failure(
    onto: String,
    onto_name: Option<Vec<u8>>,
    kind: NativeRebaseFailureKind,
) -> NativeRebasePlanResult {
    NativeRebasePlanResult {
        token: None,
        onto,
        onto_name,
        current_branch: Vec::new(),
        current_head: String::new(),
        instructions: Vec::new(),
        published_count: 0,
        activity_ids: Vec::new(),
        failure: Some(NativeRebaseFailure { kind }),
    }
}

fn preview_failure(kind: NativeRebaseFailureKind) -> NativeRebasePreviewResult {
    NativeRebasePreviewResult {
        token: None,
        arguments: Vec::new(),
        todo: Vec::new(),
        instruction_count: 0,
        published_count: 0,
        instructions: Vec::new(),
        autosquash_applied: 0,
        failure: Some(NativeRebaseFailure { kind }),
    }
}

fn execution_failure(kind: NativeRebaseFailureKind) -> NativeRebaseExecutionResult {
    NativeRebaseExecutionResult {
        state: NativeRebaseExecutionState::Failed,
        failure: Some(NativeRebaseFailure { kind }),
        activity_ids: Vec::new(),
        conflicting_paths: Vec::new(),
        running_instruction: None,
    }
}

/// An interactive rebase stops at conflicts and edit stops and resumes through Git's
/// sequencer with the editors and plan GitLama prepared when it started; a restack's step
/// resumes the same way.
pub(crate) struct RebaseSequencer;

pub(crate) static REBASE: RebaseSequencer = RebaseSequencer;

impl InterruptedOperation for RebaseSequencer {
    fn kind(&self) -> NativeConflictOperationKind {
        NativeConflictOperationKind::Rebase
    }

    fn sequencer(
        &self,
        interruption: &Interruption<'_>,
        action: NativeConflictSequencerAction,
    ) -> Result<SequencerStep, NativeConflictFailureKind> {
        let mut step =
            SequencerStep::new(devmil_git::rebase::rebase_sequencer_argv(match action {
                NativeConflictSequencerAction::Continue => {
                    devmil_git::rebase::SequencerAction::Continue
                }
                NativeConflictSequencerAction::Skip => devmil_git::rebase::SequencerAction::Skip,
                NativeConflictSequencerAction::Abort => devmil_git::rebase::SequencerAction::Abort,
            }));
        if let Some(runtime) =
            find_rebase_runtime(interruption.common_git_dir, interruption.git_dir)
        {
            step.environment = vec![
                ("GIT_EDITOR", runtime.join("sequence-editor")),
                ("GITLAMA_REBASE_PLAN", runtime.join("prepared-todo")),
                ("GITLAMA_REBASE_MESSAGES", runtime.join("messages")),
                (
                    "GITLAMA_REBASE_MESSAGE_COUNTER",
                    runtime.join("message-counter"),
                ),
            ];
            step.runtime = Some(runtime);
        }
        Ok(step)
    }

    fn completed(
        &self,
        interruption: &Interruption<'_>,
        _step: &SequencerStep,
        _current: &RepositorySnapshot,
    ) {
        crate::advanced_rebase::finish_interrupted_restack(
            interruption.common_git_dir,
            interruption.git_dir,
        );
    }

    fn aborted(&self, interruption: &Interruption<'_>, _step: &SequencerStep) {
        crate::advanced_rebase::finish_interrupted_restack(
            interruption.common_git_dir,
            interruption.git_dir,
        );
    }
}

/// The runtime an interactive rebase of `git_dir` prepared, with its editors and plan.
fn find_rebase_runtime(common_git_dir: &Path, git_dir: &Path) -> Option<PathBuf> {
    let root = common_git_dir.join("gitlama/rebase");
    let expected = devmil_git::native_bytes::path_to_bytes(git_dir);
    let expected = expected.as_slice();
    fs::read_dir(root)
        .ok()?
        .filter_map(Result::ok)
        .take(64)
        .filter_map(|entry| {
            let metadata = entry.metadata().ok()?;
            (metadata.is_dir()
                && fs::read(entry.path().join("git-dir")).ok()?.as_slice() == expected)
                .then_some(entry.path())
        })
        .max_by_key(|path| fs::metadata(path).and_then(|value| value.modified()).ok())
}

crate::family_failures!(NativeRebaseFailureKind, "rebase", {
    InvalidRequest => InvalidRequest,
    EmptyPlan => InvalidRequest,
    InvalidPlan => InvalidRequest,
    DirtyWorktree => Precondition,
    DetachedHead => Precondition,
    ActiveOperation => Precondition,
    PublicationConfirmationRequired => Precondition,
    Stale => Stale,
    Canceled => Canceled,
    Failed => Git,
    Read => Read,
    Unsupported => Unsupported,
});

#[cfg(test)]
mod outcome_tests {
    use super::*;

    #[test]
    fn an_uncertain_rebase_stays_uncertain() {
        assert_eq!(
            native_state(MutationState::OutcomeUncertain),
            NativeRebaseExecutionState::OutcomeUncertain
        );
        assert_eq!(
            native_state(MutationState::Canceled),
            NativeRebaseExecutionState::Failed
        );
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{conflicts::*, rebase::*, session::*};
    use crate::dto::*;

    use crate::conflict::{
        NativeConflictContinuationState, NativeConflictOperationKind, NativeConflictSequencerAction,
    };

    use crate::rebase_operation::{
        NativeRebaseAction, NativeRebaseExecutionState, NativeRebaseFailureKind,
    };

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[test]
    fn rebase_plan_keeps_empty_subjects_and_marks_commits_any_remote_contains() {
        // Regressions: an empty subject shifted the positional log pairing, and only the newest
        // commits of the configured upstream counted as published.
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
        transfer_git(
            &fixture.0,
            &["commit", "-q", "--allow-empty-message", "-m", ""],
        );
        transfer_git(&fixture.0, &["init", "-q", "--bare", ".git/elsewhere.git"]);
        transfer_git(
            &fixture.0,
            &["remote", "add", "elsewhere", ".git/elsewhere.git"],
        );
        // Pushed under another name and without setting an upstream.
        transfer_git(&fixture.0, &["push", "-q", "elsewhere", "topic:shared"]);
        fs::write(fixture.0.join("two.txt"), b"two\n").unwrap();
        transfer_git(&fixture.0, &["add", "two.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "two"]);

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
        let loaded = repository_session_rebase_plan(
            session.session_id,
            session.generation,
            base,
            Some(b"main".to_vec()),
        );
        assert!(loaded.failure.is_none(), "{:?}", loaded.failure);
        assert_eq!(loaded.instructions.len(), 2);
        assert!(loaded.instructions[0].subject.is_empty());
        assert!(loaded.instructions[0].published);
        assert_eq!(loaded.instructions[1].subject, b"two");
        assert!(!loaded.instructions[1].published);
        assert_eq!(loaded.published_count, 1);
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn interactive_rebase_reorders_rewords_validates_and_refuses_stale_start() {
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
        fs::write(fixture.0.join("two.txt"), b"two\n").unwrap();
        transfer_git(&fixture.0, &["add", "two.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "two"]);

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_217,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let loaded = repository_session_rebase_plan(
            session.session_id,
            session.generation,
            base.clone(),
            Some(b"main".to_vec()),
        );
        assert!(loaded.failure.is_none());
        assert_eq!(loaded.instructions.len(), 2);

        let mut illegal = loaded.instructions.clone();
        illegal[0].action = NativeRebaseAction::Squash;
        assert_eq!(
            repository_session_rebase_preview(
                session.session_id,
                session.generation,
                loaded.token.unwrap(),
                illegal,
                false,
                false,
            )
            .failure
            .unwrap()
            .kind,
            NativeRebaseFailureKind::InvalidPlan
        );

        let mut edited = loaded.instructions.clone();
        edited.swap(0, 1);
        edited[1].action = NativeRebaseAction::Reword;
        edited[1].replacement_message = Some(b"one rewritten\n\nbody\n".to_vec());
        let preview = repository_session_rebase_preview(
            session.session_id,
            session.generation,
            loaded.token.unwrap(),
            edited,
            false,
            false,
        );
        assert!(preview.failure.is_none());
        assert_eq!(preview.instruction_count, 2);
        assert_eq!(preview.arguments[3], "--interactive");
        let result = repository_session_rebase_execute(
            session.session_id,
            session.generation,
            loaded.token.unwrap(),
        );
        assert_eq!(result.state, NativeRebaseExecutionState::Completed);
        let subjects =
            String::from_utf8(transfer_git(&fixture.0, &["log", "-2", "--format=%s"])).unwrap();
        assert_eq!(
            subjects.lines().collect::<Vec<_>>(),
            ["one rewritten", "two"]
        );

        refresh_session(&session);
        let stale = repository_session_rebase_plan(
            session.session_id,
            session.generation,
            base,
            Some(b"main".to_vec()),
        );
        fs::write(fixture.0.join("external.txt"), b"external\n").unwrap();
        transfer_git(&fixture.0, &["add", "external.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "external"]);
        refresh_session(&session);
        assert_eq!(
            repository_session_rebase_preview(
                session.session_id,
                session.generation,
                stale.token.unwrap(),
                stale.instructions,
                false,
                false,
            )
            .failure,
            None
        );
        assert_eq!(
            repository_session_rebase_execute(
                session.session_id,
                session.generation,
                stale.token.unwrap(),
            )
            .state,
            NativeRebaseExecutionState::Stale
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn interactive_rebase_autosquash_preview_resolves_fixup_base() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("base.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        let base = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("feature.txt"), b"feature\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "feature"]);
        fs::write(fixture.0.join("fix.txt"), b"fix\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "fixup! feature"]);

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            12_171,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let loaded = repository_session_rebase_plan(
            session.session_id,
            session.generation,
            base,
            Some(b"main".to_vec()),
        );
        let base_id = loaded.instructions[0].id;
        let preview = repository_session_rebase_preview(
            session.session_id,
            session.generation,
            loaded.token.unwrap(),
            loaded.instructions,
            false,
            true,
        );
        assert!(preview.failure.is_none());
        assert_eq!(preview.autosquash_applied, 1);
        assert_eq!(preview.instructions[1].action, NativeRebaseAction::Fixup);
        assert_eq!(preview.instructions[1].autosquash_base_id, Some(base_id));
        assert!(preview.todo.windows(6).any(|window| window == b"fixup "));
        let result = repository_session_rebase_execute(
            session.session_id,
            session.generation,
            preview.token.unwrap(),
        );
        assert_eq!(result.state, NativeRebaseExecutionState::Completed);
        assert_eq!(
            String::from_utf8(transfer_git(
                &fixture.0,
                &["log", "--format=%s", "main..HEAD"]
            ))
            .unwrap()
            .lines()
            .collect::<Vec<_>>(),
            ["feature"]
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn interactive_rebase_edit_stop_survives_session_restart() {
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
        fs::write(fixture.0.join("edit.txt"), b"edit\n").unwrap();
        transfer_git(&fixture.0, &["add", "edit.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "edit stop"]);

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
        let loaded = repository_session_rebase_plan(
            session.session_id,
            session.generation,
            base,
            Some(b"main".to_vec()),
        );
        let mut edited = loaded.instructions;
        edited[0].action = NativeRebaseAction::Edit;
        let preview = repository_session_rebase_preview(
            session.session_id,
            session.generation,
            loaded.token.unwrap(),
            edited,
            false,
            false,
        );
        assert!(preview.failure.is_none());
        assert!(preview.todo.starts_with(b"edit "));
        let result = repository_session_rebase_execute(
            session.session_id,
            session.generation,
            loaded.token.unwrap(),
        );
        assert_eq!(result.state, NativeRebaseExecutionState::EditStop);
        assert!(result.running_instruction.unwrap().starts_with(b"edit "));
        assert!(fixture.0.join(".git/rebase-merge").is_dir());
        assert!(repository_session_close(session.session_id, session.generation).accepted);

        let reopened = repository_session_open_with_options(
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
        let snapshot = wait_for_ready(&reopened);
        assert!(snapshot
            .status
            .unwrap()
            .operations
            .iter()
            .any(|operation| operation.kind == NativeOperationKind::Rebase));
        let conflicts = repository_session_conflicts(reopened.session_id, reopened.generation)
            .snapshot
            .unwrap();
        assert_eq!(conflicts.operation, NativeConflictOperationKind::Rebase);
        let aborted = repository_session_conflict_continue(
            reopened.session_id,
            reopened.generation,
            NativeConflictSequencerAction::Abort,
        );
        assert_eq!(aborted.state, NativeConflictContinuationState::Aborted);
        assert!(repository_session_close(reopened.session_id, reopened.generation).accepted);
    }

    #[test]
    fn interactive_rebase_exposes_real_conflict_and_abort_restores_topic() {
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
        transfer_git(&fixture.0, &["commit", "-qm", "first"]);
        fs::write(fixture.0.join("conflict.txt"), b"topic\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "topic conflict"]);
        let topic_head = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&fixture.0, &["switch", "main"]);
        fs::write(fixture.0.join("conflict.txt"), b"main\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "main conflict"]);
        let main = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(&fixture.0, &["switch", "topic"]);

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
        let loaded = repository_session_rebase_plan(
            session.session_id,
            session.generation,
            main,
            Some(b"main".to_vec()),
        );
        assert_eq!(loaded.instructions.len(), 2);
        assert!(repository_session_rebase_preview(
            session.session_id,
            session.generation,
            loaded.token.unwrap(),
            loaded.instructions,
            false,
            false,
        )
        .failure
        .is_none());
        let result = repository_session_rebase_execute(
            session.session_id,
            session.generation,
            loaded.token.unwrap(),
        );
        assert_eq!(result.state, NativeRebaseExecutionState::Conflict);
        assert_eq!(result.conflicting_paths, [b"conflict.txt".to_vec()]);
        assert!(result.running_instruction.is_some());
        assert!(fixture.0.join(".git/rebase-merge").is_dir());
        assert!(fixture.0.join("first.txt").is_file());
        let conflicts = repository_session_conflicts(session.session_id, session.generation)
            .snapshot
            .unwrap();
        assert_eq!(conflicts.operation, NativeConflictOperationKind::Rebase);
        assert_eq!(conflicts.files.len(), 1);
        let aborted = repository_session_conflict_continue(
            session.session_id,
            session.generation,
            NativeConflictSequencerAction::Abort,
        );
        assert_eq!(aborted.state, NativeConflictContinuationState::Aborted);
        assert_eq!(
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim(),
            topic_head
        );
        assert_eq!(
            fs::read(fixture.0.join("conflict.txt")).unwrap(),
            b"topic\n"
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[test]
    fn apply_backend_rebase_conflict_names_both_sides() {
        // Regression: rebase labels were read from the merge backend's files only.
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("conflict.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "."]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        transfer_git(&fixture.0, &["switch", "-c", "topic"]);
        fs::write(fixture.0.join("conflict.txt"), b"topic\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "topic"]);
        transfer_git(&fixture.0, &["switch", "main"]);
        fs::write(fixture.0.join("conflict.txt"), b"main\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "main"]);
        transfer_git(&fixture.0, &["switch", "topic"]);
        transfer_git_expect_failure(&fixture.0, &["rebase", "--apply", "main"]);
        assert!(fixture.0.join(".git/rebase-apply").is_dir());

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
        let snapshot = repository_session_conflicts(session.session_id, session.generation)
            .snapshot
            .unwrap();
        assert_eq!(snapshot.operation, NativeConflictOperationKind::Rebase);
        assert_eq!(snapshot.current_label, b"main");
        assert_eq!(snapshot.incoming_label, b"topic");
        transfer_git(&fixture.0, &["rebase", "--abort"]);
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }
}
