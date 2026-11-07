//! Validated external-tool and custom-command previews.
pub use gitlama_contract::integrations::*;

use crate::activity::ActivityStore;
use crate::domain::path_identity::{native_path, native_path_identity, NativePathIdentity};
use crate::preview_store::PreviewStore;
use devmil_git::activity::ActivityStatus;
use devmil_git::diff::model::DiffPath;
use devmil_git::integrations::{
    ArgumentTemplate, IntegrationCommand, IntegrationDefinition, IntegrationExecution,
    IntegrationKind, IntegrationLaunchMode, IntegrationProcessOutcome, IntegrationRequest,
    IntegrationVariable, IntegrationVariables, SystemIntegrationPlatform,
};
use devmil_git::loading::working_diff::DiffEndpoint;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument, SemanticTimeout};
use devmil_git::types::{HeadState, ObjectId};
use devmil_git::{Repository, RepositoryErrorKind, RepositorySnapshot};
use std::collections::HashSet;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

pub(crate) const INTEGRATION_KINDS: [&str; 7] = [
    "editor",
    "terminal",
    "fileManager",
    "browser",
    "diffTool",
    "mergeTool",
    "custom",
];
/// Checks the stored integrations section.
pub(crate) fn validate_settings(
    integrations: &[NativeIntegrationSettings],
) -> Result<(), &'static str> {
    let integration_ids: HashSet<_> = integrations
        .iter()
        .map(|integration| integration.id.as_str())
        .collect();
    if integration_ids.len() != integrations.len()
        || integrations.iter().any(|integration| {
            integration.id.is_empty()
                || integration.id.len() > 128
                || !INTEGRATION_KINDS.contains(&integration.kind.as_str())
                || integration.arguments.len() > 128
                || integration.arguments.iter().map(String::len).sum::<usize>() > 16 * 1024
                || !(1..=300).contains(&integration.timeout_seconds)
        })
    {
        return Err("integrations");
    }
    Ok(())
}

const PREVIEW_CAPACITY_PER_SESSION: usize = 8;
const CUSTOM_OUTPUT_LIMIT: usize = 64 * 1024;
const EXTERNAL_DIFF_BYTES: usize = 64 * 1024 * 1024;

#[derive(Clone, Debug, Eq, PartialEq)]
struct RepositoryFacts {
    worktree: PathBuf,
    head: Option<String>,
    branch: Option<Vec<u8>>,
}

struct OwnedIntegration {
    command: IntegrationCommand,
    custom: bool,
    timeout: Duration,
    requires_confirmation: bool,
    facts: RepositoryFacts,
    completion: IntegrationCompletion,
}

enum IntegrationCompletion {
    None,
    ConflictMerge(crate::conflict::ExternalMergeFiles),
    TemporaryDirectory(PathBuf),
}

static INTEGRATIONS: OnceLock<Mutex<PreviewStore<OwnedIntegration>>> = OnceLock::new();

fn lock_registry() -> std::sync::MutexGuard<'static, PreviewStore<OwnedIntegration>> {
    crate::preview_store::lock(
        INTEGRATIONS.get_or_init(|| Mutex::new(PreviewStore::new(PREVIEW_CAPACITY_PER_SESSION))),
    )
}

#[must_use]
pub fn discover(kind: NativeIntegrationKind) -> NativeIntegrationDiscoveryResult {
    if kind == NativeIntegrationKind::Custom {
        return NativeIntegrationDiscoveryResult {
            candidates: Vec::new(),
        };
    }
    let candidates = SystemIntegrationPlatform::default()
        .discover(shared_kind(kind))
        .into_iter()
        .map(|definition| NativeIntegrationCandidate {
            id: definition.id,
            kind,
            executable: native_path_identity(&definition.executable),
            launch_mode: map_launch_mode(definition.launch_mode),
        })
        .collect();
    NativeIntegrationDiscoveryResult { candidates }
}

pub(crate) fn preview(
    session_id: u64,
    repository: &Repository,
    request: NativeIntegrationRequest,
) -> NativeIntegrationPreviewResult {
    match facts(&repository.snapshot()) {
        Some(facts) => preview_with_facts(session_id, facts, request),
        None => preview_failure(NativeIntegrationFailureKind::Read),
    }
}

/// The owner of integrations that run on this computer for a repository on another computer:
/// they belong to no local session and see only the files materialized for them.
pub(crate) const DETACHED_OWNER: u64 = u64::MAX;

pub(crate) fn detached_activity() -> ActivityStore {
    static ACTIVITY: std::sync::OnceLock<ActivityStore> = std::sync::OnceLock::new();
    ACTIVITY.get_or_init(ActivityStore::default).clone()
}

fn preview_with_facts(
    session_id: u64,
    facts: RepositoryFacts,
    request: NativeIntegrationRequest,
) -> NativeIntegrationPreviewResult {
    let definition = match resolve_definition(&request) {
        Ok(value) => value,
        Err(kind) => return preview_failure(kind),
    };
    let values = match variables(&facts, &request.variables) {
        Ok(value) => value,
        Err(kind) => return preview_failure(kind),
    };
    let expanded = match IntegrationCommand::expand(
        &definition,
        &IntegrationRequest {
            kind: definition.kind,
            working_directory: facts.worktree.clone(),
            variables: values,
            configured: Some(definition.clone()),
        },
    ) {
        Ok(value) => value,
        Err(_) => return preview_failure(NativeIntegrationFailureKind::MissingVariable),
    };
    if !executable_available(&expanded.executable) {
        return preview_failure(NativeIntegrationFailureKind::Unavailable);
    }
    let custom = request.kind == NativeIntegrationKind::Custom;
    if custom && expanded.launch_mode != IntegrationLaunchMode::Wait {
        return preview_failure(NativeIntegrationFailureKind::InvalidRequest);
    }
    let timeout = request
        .configured
        .as_ref()
        .map(|value| value.timeout_seconds)
        .unwrap_or(30);
    if custom && !(1..=300).contains(&timeout) {
        return preview_failure(NativeIntegrationFailureKind::InvalidRequest);
    }
    let requires_confirmation = request
        .configured
        .as_ref()
        .is_some_and(|value| value.requires_confirmation)
        || expanded.execution == IntegrationExecution::ExplicitShell
        || custom;
    let definition_id = definition.id.clone();
    let executable = expanded.executable.to_string_lossy().into_owned();
    let arguments = expanded
        .arguments
        .iter()
        .map(|value| value.to_string_lossy().into_owned())
        .collect();
    let explicit_shell = expanded.execution == IntegrationExecution::ExplicitShell;
    let waits_for_exit = expanded.launch_mode == IntegrationLaunchMode::Wait;
    let (token, evicted) = lock_registry().issue_evicting(
        session_id,
        OwnedIntegration {
            command: expanded,
            custom,
            timeout: Duration::from_secs(u64::from(timeout)),
            requires_confirmation,
            facts,
            completion: IntegrationCompletion::None,
        },
    );
    for owned in evicted {
        cleanup_completion(&owned.completion);
    }
    NativeIntegrationPreviewResult {
        preview: Some(NativeIntegrationPreview {
            token,
            kind: request.kind,
            definition_id,
            executable,
            arguments,
            explicit_shell,
            waits_for_exit,
            requires_confirmation,
        }),
        failure: None,
    }
}

pub(crate) fn preview_conflict_merge(
    session_id: u64,
    repository: &Repository,
    activity: &ActivityStore,
    path: Vec<u8>,
    expected_fingerprint: u64,
    configured: NativeIntegrationDefinition,
) -> NativeIntegrationPreviewResult {
    if configured.kind != NativeIntegrationKind::MergeTool
        || configured.launch_mode != NativeIntegrationLaunchMode::Wait
    {
        return preview_failure(NativeIntegrationFailureKind::InvalidRequest);
    }
    let prepared = match crate::conflict::prepare_external_merge(
        session_id,
        repository,
        activity,
        path,
        expected_fingerprint,
    ) {
        Ok(value) => value,
        Err(kind) => return preview_failure(map_conflict_failure(kind)),
    };
    let request = NativeIntegrationRequest {
        kind: NativeIntegrationKind::MergeTool,
        discovered_id: None,
        configured: Some(configured),
        variables: NativeIntegrationVariables {
            merge_base: Some(native_path_identity(&prepared.ancestor)),
            merge_current: Some(native_path_identity(&prepared.current)),
            merge_incoming: Some(native_path_identity(&prepared.incoming)),
            merge_result: Some(native_path_identity(&prepared.result)),
            ..NativeIntegrationVariables::default()
        },
    };
    let result = preview(session_id, repository, request);
    let Some(preview) = result.preview.as_ref() else {
        let _ = std::fs::remove_dir_all(&prepared.root);
        return result;
    };
    let mut entries = lock_registry();
    if let Some(owned) = entries.get_mut(session_id, preview.token) {
        owned.value.completion = IntegrationCompletion::ConflictMerge(prepared);
    }
    drop(entries);
    result
}

pub(crate) fn preview_commit_diff(
    session_id: u64,
    repository: &Repository,
    old_revision: Option<String>,
    new_revision: String,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    configured: NativeIntegrationDefinition,
) -> NativeIntegrationPreviewResult {
    if configured.kind != NativeIntegrationKind::DiffTool
        || configured.launch_mode != NativeIntegrationLaunchMode::Wait
    {
        return preview_failure(NativeIntegrationFailureKind::InvalidRequest);
    }
    let old_endpoint = match old_revision {
        Some(value) => match ObjectId::parse(value) {
            Ok(value) => DiffEndpoint::Commit(value),
            Err(_) => return preview_failure(NativeIntegrationFailureKind::InvalidRequest),
        },
        None => DiffEndpoint::EmptyTree,
    };
    let new_endpoint = match ObjectId::parse(new_revision) {
        Ok(value) => DiffEndpoint::Commit(value),
        Err(_) => return preview_failure(NativeIntegrationFailureKind::InvalidRequest),
    };
    let store = match create_private_directory("diff") {
        Ok(value) => value,
        Err(kind) => return preview_failure(kind),
    };
    let root = store.path().to_path_buf();
    let prepared = (|| {
        let old = read_content(repository, old_endpoint, old_path)?;
        let new = read_content(repository, new_endpoint, new_path)?;
        write_sides(&store, &old, &new)
    })();
    // Windows cannot delete a directory with an open handle.
    drop(store);
    if let Err(kind) = prepared {
        let _ = std::fs::remove_dir_all(&root);
        return preview_failure(kind);
    }
    match facts(&repository.snapshot()) {
        Some(facts) => diff_tool_preview(session_id, facts, root, configured),
        None => {
            let _ = std::fs::remove_dir_all(&root);
            preview_failure(NativeIntegrationFailureKind::Read)
        }
    }
}

/// Compares two versions of a file read from a repository on another computer with a diff tool
/// on this computer.
pub(crate) fn preview_diff_bytes(
    old: &[u8],
    new: &[u8],
    configured: NativeIntegrationDefinition,
) -> NativeIntegrationPreviewResult {
    if configured.kind != NativeIntegrationKind::DiffTool
        || configured.launch_mode != NativeIntegrationLaunchMode::Wait
        || old.len() > EXTERNAL_DIFF_BYTES
        || new.len() > EXTERNAL_DIFF_BYTES
    {
        return preview_failure(NativeIntegrationFailureKind::InvalidRequest);
    }
    let store = match create_private_directory("diff") {
        Ok(value) => value,
        Err(kind) => return preview_failure(kind),
    };
    let root = store.path().to_path_buf();
    let written = write_sides(&store, old, new);
    // Windows cannot delete a directory with an open handle.
    drop(store);
    if let Err(kind) = written {
        let _ = std::fs::remove_dir_all(&root);
        return preview_failure(kind);
    }
    // The tool runs in the directory of its two files; there is no local worktree.
    let facts = RepositoryFacts {
        worktree: root.clone(),
        head: None,
        branch: None,
    };
    diff_tool_preview(DETACHED_OWNER, facts, root, configured)
}

/// Previews a diff tool on `root/left` and `root/right`; the directory goes with the integration.
fn diff_tool_preview(
    session_id: u64,
    facts: RepositoryFacts,
    root: PathBuf,
    configured: NativeIntegrationDefinition,
) -> NativeIntegrationPreviewResult {
    let left = root.join("left");
    let right = root.join("right");
    let request = NativeIntegrationRequest {
        kind: NativeIntegrationKind::DiffTool,
        discovered_id: None,
        configured: Some(configured),
        variables: NativeIntegrationVariables {
            diff_left: Some(native_path_identity(&left)),
            diff_right: Some(native_path_identity(&right)),
            ..NativeIntegrationVariables::default()
        },
    };
    let result = preview_with_facts(session_id, facts, request);
    let Some(preview) = result.preview.as_ref() else {
        let _ = std::fs::remove_dir_all(&root);
        return result;
    };
    let mut entries = lock_registry();
    if let Some(owned) = entries.get_mut(session_id, preview.token) {
        owned.value.completion = IntegrationCompletion::TemporaryDirectory(root);
    }
    drop(entries);
    result
}

pub(crate) fn execute(
    session_id: u64,
    token: u64,
    confirmed: bool,
    repository: &Repository,
    activity: &ActivityStore,
) -> NativeIntegrationExecutionResult {
    let Some(current_facts) = facts(&repository.snapshot()) else {
        return execution_failure(NativeIntegrationFailureKind::Read);
    };
    execute_with(
        session_id,
        token,
        confirmed,
        Some(&current_facts),
        Some(repository),
        activity,
    )
}

/// Runs an integration previewed for a repository on another computer.
pub(crate) fn execute_detached(token: u64, confirmed: bool) -> NativeIntegrationExecutionResult {
    execute_with(
        DETACHED_OWNER,
        token,
        confirmed,
        None,
        None,
        &detached_activity(),
    )
}

/// Runs a previewed integration. Without `current_facts` there is no repository whose state
/// could have moved since the preview.
fn execute_with(
    session_id: u64,
    token: u64,
    confirmed: bool,
    current_facts: Option<&RepositoryFacts>,
    repository: Option<&Repository>,
    activity: &ActivityStore,
) -> NativeIntegrationExecutionResult {
    let (command, custom, timeout, cancellation) = {
        let mut entries = lock_registry();
        let Some(owned) = entries.get_mut(session_id, token) else {
            return execution_failure(NativeIntegrationFailureKind::InvalidRequest);
        };
        if owned.running {
            return execution_failure(NativeIntegrationFailureKind::InvalidRequest);
        }
        if current_facts.is_some_and(|current| owned.value.facts != *current) {
            let removed = entries.finish(session_id, token);
            drop(entries);
            if let Some(removed) = removed {
                cleanup_completion(&removed.completion);
            }
            return stale_result();
        }
        if owned.value.requires_confirmation && !confirmed {
            return execution_failure(NativeIntegrationFailureKind::ConfirmationRequired);
        }
        owned.running = true;
        (
            owned.value.command.clone(),
            owned.value.custom,
            owned.value.timeout,
            Arc::clone(&owned.cancellation),
        )
    };
    let result = if custom {
        execute_custom(command, timeout, cancellation.as_ref(), activity)
    } else {
        execute_platform(command)
    };
    let owned = lock_registry().finish(session_id, token);
    let Some(owned) = owned else {
        return result;
    };
    complete_integration(session_id, repository, activity, owned.completion, result)
}

pub(crate) fn cancel(session_id: u64, token: u64) -> bool {
    let mut entries = lock_registry();
    let Some(owned) = entries.get(session_id, token) else {
        return false;
    };
    if owned.running {
        if !owned.value.custom {
            return false;
        }
        owned.cancellation.store(true, Ordering::Release);
    } else {
        let removed = entries.finish(session_id, token);
        drop(entries);
        if let Some(removed) = removed {
            cleanup_completion(&removed.completion);
        }
    }
    true
}

pub(crate) fn dismiss_session(session_id: u64) {
    let removed = lock_registry().dismiss_session(session_id);
    for entry in removed {
        cleanup_completion(&entry.completion);
    }
}

fn complete_integration(
    session_id: u64,
    repository: Option<&Repository>,
    activity: &ActivityStore,
    completion: IntegrationCompletion,
    mut result: NativeIntegrationExecutionResult,
) -> NativeIntegrationExecutionResult {
    if let IntegrationCompletion::ConflictMerge(prepared) = &completion {
        if result.state == NativeIntegrationExecutionState::Completed {
            let finished = repository.map_or(
                Err(crate::conflict::NativeConflictFailureKind::Stale),
                |repository| {
                    crate::conflict::finish_external_merge(
                        session_id, repository, activity, prepared,
                    )
                },
            );
            if let Err(kind) = finished {
                result = execution_failure(map_conflict_failure(kind));
            }
        }
    }
    cleanup_completion(&completion);
    result
}

fn cleanup_completion(completion: &IntegrationCompletion) {
    match completion {
        IntegrationCompletion::None => {}
        IntegrationCompletion::ConflictMerge(prepared) => {
            let _ = std::fs::remove_dir_all(&prepared.root);
        }
        IntegrationCompletion::TemporaryDirectory(root) => {
            let _ = std::fs::remove_dir_all(root);
        }
    }
}

fn create_private_directory(
    label: &str,
) -> Result<crate::private_store::PrivateDir, NativeIntegrationFailureKind> {
    crate::private_store::PrivateDir::temporary(&format!("gitlama-{label}"))
        .map_err(|_| NativeIntegrationFailureKind::Launch)
}

/// Writes the two compared versions owner-only as `left` and `right`.
fn write_sides(
    store: &crate::private_store::PrivateDir,
    old: &[u8],
    new: &[u8],
) -> Result<(), NativeIntegrationFailureKind> {
    store
        .write_new("left", old)
        .and_then(|()| store.write_new("right", new))
        .map_err(|_| NativeIntegrationFailureKind::Launch)
}

fn read_content(
    repository: &Repository,
    endpoint: DiffEndpoint,
    path: Option<Vec<u8>>,
) -> Result<Vec<u8>, NativeIntegrationFailureKind> {
    let Some(path) = path else {
        return Ok(Vec::new());
    };
    let path =
        DiffPath::from_bytes(path).map_err(|_| NativeIntegrationFailureKind::InvalidRequest)?;
    let ticket = repository
        .content(endpoint, path, EXTERNAL_DIFF_BYTES)
        .map_err(|_| NativeIntegrationFailureKind::Read)?;
    let value = ticket
        .recv_timeout(Duration::from_secs(30))
        .ok_or(NativeIntegrationFailureKind::TimedOut)?;
    match value {
        Ok(value) => Ok(value
            .as_ref()
            .as_ref()
            .map_or_else(Vec::new, |content| content.bytes.clone())),
        Err(error) if error.kind == RepositoryErrorKind::MissingObject => Ok(Vec::new()),
        Err(_) => Err(NativeIntegrationFailureKind::Read),
    }
}

fn map_conflict_failure(
    kind: crate::conflict::NativeConflictFailureKind,
) -> NativeIntegrationFailureKind {
    use crate::conflict::NativeConflictFailureKind as Conflict;
    match kind {
        Conflict::Stale | Conflict::MissingPath | Conflict::NoActiveOperation => {
            NativeIntegrationFailureKind::Stale
        }
        Conflict::TooLarge => NativeIntegrationFailureKind::InvalidRequest,
        Conflict::InvalidRequest | Conflict::Binary | Conflict::Unsupported => {
            NativeIntegrationFailureKind::InvalidRequest
        }
        Conflict::Read => NativeIntegrationFailureKind::Read,
        Conflict::Write | Conflict::Git | Conflict::Unresolved => {
            NativeIntegrationFailureKind::Launch
        }
    }
}

fn execute_custom(
    command: IntegrationCommand,
    timeout: Duration,
    cancellation: &AtomicBool,
    activity: &ActivityStore,
) -> NativeIntegrationExecutionResult {
    let activity_id =
        crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
    let specification = GitProcessCommand::new(command.executable)
        .args(command.arguments.into_iter().map(ProcessArgument::visible))
        .current_dir(command.working_directory)
        .semantic_timeout(
            SemanticTimeout::new(timeout, "custom command reached its configured time limit")
                .expect("constant timeout is valid"),
        )
        .output_limit(CUSTOM_OUTPUT_LIMIT);
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let result = ActivityGitRunner::run_private(
        specification,
        activity_id,
        Some(cancellation),
        &mut publish,
    );
    let (state, failure) = match result.activity.status {
        ActivityStatus::Succeeded { .. } => (NativeIntegrationExecutionState::Completed, None),
        ActivityStatus::Canceled { .. } => (
            NativeIntegrationExecutionState::Canceled,
            Some(NativeIntegrationFailureKind::Canceled),
        ),
        ActivityStatus::TimedOut { .. } => (
            NativeIntegrationExecutionState::TimedOut,
            Some(NativeIntegrationFailureKind::TimedOut),
        ),
        ActivityStatus::Failed { .. } => (
            NativeIntegrationExecutionState::Failed,
            Some(NativeIntegrationFailureKind::NonZeroExit),
        ),
        ActivityStatus::LaunchError { .. } | ActivityStatus::Running => (
            NativeIntegrationExecutionState::Failed,
            Some(NativeIntegrationFailureKind::Launch),
        ),
    };
    NativeIntegrationExecutionResult {
        state,
        activity_id: Some(activity_id.get().to_string()),
        process_id: None,
        failure: failure.map(|kind| NativeIntegrationFailure { kind }),
    }
}

fn execute_platform(command: IntegrationCommand) -> NativeIntegrationExecutionResult {
    match SystemIntegrationPlatform::default().launch(&command) {
        Ok(IntegrationProcessOutcome::Detached { process_id }) => {
            NativeIntegrationExecutionResult {
                state: NativeIntegrationExecutionState::Detached,
                activity_id: None,
                process_id: Some(process_id),
                failure: None,
            }
        }
        Ok(IntegrationProcessOutcome::Exited { .. }) => NativeIntegrationExecutionResult {
            state: NativeIntegrationExecutionState::Completed,
            activity_id: None,
            process_id: None,
            failure: None,
        },
        Err(error) => {
            use devmil_git::integrations::IntegrationLaunchErrorKind as Kind;
            let kind = match error.kind {
                Kind::ExecutableUnavailable => NativeIntegrationFailureKind::Unavailable,
                Kind::NonZeroExit => NativeIntegrationFailureKind::NonZeroExit,
                Kind::WorkingDirectoryUnavailable => NativeIntegrationFailureKind::Stale,
                Kind::PermissionDenied | Kind::LaunchFailed | Kind::WaitFailed => {
                    NativeIntegrationFailureKind::Launch
                }
            };
            execution_failure(kind)
        }
    }
}

fn resolve_definition(
    request: &NativeIntegrationRequest,
) -> Result<IntegrationDefinition, NativeIntegrationFailureKind> {
    if let Some(configured) = &request.configured {
        if request.discovered_id.is_some() || configured.kind != request.kind {
            return Err(NativeIntegrationFailureKind::InvalidRequest);
        }
        return configured_definition(configured);
    }
    let id = request
        .discovered_id
        .as_ref()
        .ok_or(NativeIntegrationFailureKind::InvalidRequest)?;
    if request.kind == NativeIntegrationKind::Custom {
        return Err(NativeIntegrationFailureKind::InvalidRequest);
    }
    SystemIntegrationPlatform::default()
        .discover(shared_kind(request.kind))
        .into_iter()
        .find(|definition| definition.id == *id)
        .ok_or(NativeIntegrationFailureKind::Unavailable)
}

fn configured_definition(
    definition: &NativeIntegrationDefinition,
) -> Result<IntegrationDefinition, NativeIntegrationFailureKind> {
    if definition.id.is_empty() || definition.id.len() > 128 {
        return Err(NativeIntegrationFailureKind::InvalidRequest);
    }
    let executable = native_path(&definition.executable)
        .filter(|path| path.is_absolute())
        .ok_or(NativeIntegrationFailureKind::InvalidRequest)?;
    let arguments = definition
        .arguments
        .iter()
        .map(|argument| ArgumentTemplate::parse(argument))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| NativeIntegrationFailureKind::InvalidRequest)?;
    let value = IntegrationDefinition {
        id: definition.id.clone(),
        kind: shared_kind(definition.kind),
        executable,
        arguments,
        execution: match definition.execution {
            NativeIntegrationExecution::Direct => IntegrationExecution::Direct,
            NativeIntegrationExecution::ExplicitShell => IntegrationExecution::ExplicitShell,
        },
        launch_mode: match definition.launch_mode {
            NativeIntegrationLaunchMode::Detached => IntegrationLaunchMode::Detached,
            NativeIntegrationLaunchMode::Wait => IntegrationLaunchMode::Wait,
        },
    };
    value
        .validate()
        .map_err(|_| NativeIntegrationFailureKind::InvalidRequest)?;
    Ok(value)
}

fn variables(
    facts: &RepositoryFacts,
    input: &NativeIntegrationVariables,
) -> Result<IntegrationVariables, NativeIntegrationFailureKind> {
    let mut values = IntegrationVariables::default()
        .with(IntegrationVariable::Repository, facts.worktree.as_os_str())
        .with(
            IntegrationVariable::WorkingDirectory,
            facts.worktree.as_os_str(),
        );
    if let Some(value) = &input.url {
        values = values.with(IntegrationVariable::Url, value);
    }
    values = with_path(values, IntegrationVariable::File, input.file.as_ref())?;
    if let Some(value) = &input.current_branch {
        values = values.with(
            IntegrationVariable::CurrentBranch,
            bytes_to_os(value.clone())?,
        );
    }
    if let Some(value) = &input.selected_commit {
        values = values.with(IntegrationVariable::SelectedCommit, value);
    }
    values = with_path(
        values,
        IntegrationVariable::DiffLeft,
        input.diff_left.as_ref(),
    )?;
    values = with_path(
        values,
        IntegrationVariable::DiffRight,
        input.diff_right.as_ref(),
    )?;
    values = with_path(
        values,
        IntegrationVariable::MergeBase,
        input.merge_base.as_ref(),
    )?;
    values = with_path(
        values,
        IntegrationVariable::MergeCurrent,
        input.merge_current.as_ref(),
    )?;
    values = with_path(
        values,
        IntegrationVariable::MergeIncoming,
        input.merge_incoming.as_ref(),
    )?;
    with_path(
        values,
        IntegrationVariable::MergeResult,
        input.merge_result.as_ref(),
    )
}

fn with_path(
    values: IntegrationVariables,
    variable: IntegrationVariable,
    identity: Option<&NativePathIdentity>,
) -> Result<IntegrationVariables, NativeIntegrationFailureKind> {
    match identity {
        Some(identity) => native_path(identity)
            .map(|value| values.with(variable, value.into_os_string()))
            .ok_or(NativeIntegrationFailureKind::InvalidRequest),
        None => Ok(values),
    }
}

fn facts(snapshot: &RepositorySnapshot) -> Option<RepositoryFacts> {
    let repository = snapshot.repository.as_ref()?;
    let (head, branch) = match &repository.head {
        HeadState::Attached { branch, target } => (
            Some(target.as_str().to_owned()),
            Some(branch.as_bytes().to_vec()),
        ),
        HeadState::Detached { target } => (Some(target.as_str().to_owned()), None),
        HeadState::Unborn { branch } => (None, Some(branch.as_bytes().to_vec())),
    };
    Some(RepositoryFacts {
        worktree: repository.worktree.worktree_root().as_path().to_path_buf(),
        head,
        branch,
    })
}

fn shared_kind(kind: NativeIntegrationKind) -> IntegrationKind {
    match kind {
        NativeIntegrationKind::Editor | NativeIntegrationKind::Custom => IntegrationKind::Editor,
        NativeIntegrationKind::Terminal => IntegrationKind::Terminal,
        NativeIntegrationKind::FileManager => IntegrationKind::FileManager,
        NativeIntegrationKind::Browser => IntegrationKind::Browser,
        NativeIntegrationKind::DiffTool => IntegrationKind::DiffTool,
        NativeIntegrationKind::MergeTool => IntegrationKind::MergeTool,
    }
}

fn map_launch_mode(mode: IntegrationLaunchMode) -> NativeIntegrationLaunchMode {
    match mode {
        IntegrationLaunchMode::Detached => NativeIntegrationLaunchMode::Detached,
        IntegrationLaunchMode::Wait => NativeIntegrationLaunchMode::Wait,
    }
}

fn executable_available(path: &Path) -> bool {
    let Ok(metadata) = path.metadata() else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    {
        true
    }
}

fn bytes_to_os(value: Vec<u8>) -> Result<OsString, NativeIntegrationFailureKind> {
    if value.contains(&0) {
        return Err(NativeIntegrationFailureKind::InvalidRequest);
    }
    devmil_git::native_bytes::bytes_to_os_string(&value)
        .map_err(|_| NativeIntegrationFailureKind::InvalidRequest)
}

fn preview_failure(kind: NativeIntegrationFailureKind) -> NativeIntegrationPreviewResult {
    NativeIntegrationPreviewResult {
        preview: None,
        failure: Some(NativeIntegrationFailure { kind }),
    }
}

fn stale_result() -> NativeIntegrationExecutionResult {
    NativeIntegrationExecutionResult {
        state: NativeIntegrationExecutionState::Stale,
        activity_id: None,
        process_id: None,
        failure: Some(NativeIntegrationFailure {
            kind: NativeIntegrationFailureKind::Stale,
        }),
    }
}

fn execution_failure(kind: NativeIntegrationFailureKind) -> NativeIntegrationExecutionResult {
    NativeIntegrationExecutionResult {
        state: match kind {
            NativeIntegrationFailureKind::Canceled => NativeIntegrationExecutionState::Canceled,
            NativeIntegrationFailureKind::TimedOut => NativeIntegrationExecutionState::TimedOut,
            NativeIntegrationFailureKind::Stale => NativeIntegrationExecutionState::Stale,
            _ => NativeIntegrationExecutionState::Failed,
        },
        activity_id: None,
        process_id: None,
        failure: Some(NativeIntegrationFailure { kind }),
    }
}

crate::family_failures!(NativeIntegrationFailureKind, "integration", {
    InvalidRequest => InvalidRequest,
    Unavailable => Unavailable,
    MissingVariable => InvalidRequest,
    Stale => Stale,
    ConfirmationRequired => InvalidRequest,
    Canceled => Canceled,
    TimedOut => TimedOut,
    NonZeroExit => Rejected,
    Launch => Unavailable,
    Read => Read,
});

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use crate::activity::ActivityStore;
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use crate::test_support::*;

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use crate::application::{diff::*, diff_renderers::*, integrations::*, session::*};

    #[allow(unused_imports)] // Only some platforms' tests use all of them.
    use crate::integrations::{
        NativeIntegrationDefinition, NativeIntegrationExecution, NativeIntegrationExecutionState,
        NativeIntegrationFailureKind, NativeIntegrationKind, NativeIntegrationLaunchMode,
        NativeIntegrationRequest, NativeIntegrationVariables,
    };

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use devmil_git::RepositoryOptions;

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::fs;

    #[cfg(unix)]
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::os::unix::fs::PermissionsExt;
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::path::Path;

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::time::Duration;
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::time::Instant;

    #[cfg(unix)]
    #[test]
    fn integrations_preserve_exact_argv_require_shell_confirmation_and_reject_stale_head() {
        use std::os::unix::ffi::OsStrExt;
        use std::os::unix::fs::PermissionsExt;

        let fixture = GitFixture::new();
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        let capture = fixture.0.join("captured arguments.bin");
        let runner = fixture.0.join("capture tool");
        let quoted_capture = capture.to_string_lossy().replace('\'', "'\"'\"'");
        fs::write(
            &runner,
            format!(
                "#!/bin/sh\n: > '{quoted_capture}'\nfor value in \"$@\"; do printf '%s\\0' \"$value\" >> '{quoted_capture}'; done\n"
            ),
        )
        .unwrap();
        fs::set_permissions(&runner, fs::Permissions::from_mode(0o700)).unwrap();
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
        let odd_file = fixture.0.join("quote ' space -- $(touch nope).txt");
        let preview = repository_session_integration_preview(
            session.session_id,
            session.generation,
            NativeIntegrationRequest {
                kind: NativeIntegrationKind::Custom,
                discovered_id: None,
                configured: Some(NativeIntegrationDefinition {
                    id: "adversarial-argv".to_owned(),
                    kind: NativeIntegrationKind::Custom,
                    executable: crate::domain::path_identity::native_path_identity(&runner),
                    arguments: vec![
                        "{repository}".to_owned(),
                        "{file}".to_owned(),
                        "{current_branch}".to_owned(),
                        "{selected_commit}".to_owned(),
                        "literal;$(touch injected)".to_owned(),
                        "--leading".to_owned(),
                    ],
                    execution: NativeIntegrationExecution::Direct,
                    launch_mode: NativeIntegrationLaunchMode::Wait,
                    requires_confirmation: true,
                    timeout_seconds: 5,
                }),
                variables: NativeIntegrationVariables {
                    file: Some(crate::domain::path_identity::native_path_identity(
                        &odd_file,
                    )),
                    current_branch: Some(b"branch ' -- ;$()".to_vec()),
                    selected_commit: Some("deadbeef;$(false)".to_owned()),
                    ..NativeIntegrationVariables::default()
                },
            },
        )
        .preview
        .unwrap();
        assert!(preview.requires_confirmation);
        let result = repository_session_integration_execute(
            session.session_id,
            session.generation,
            preview.token,
            true,
        );
        assert_eq!(result.state, NativeIntegrationExecutionState::Completed);
        let captured = fs::read(&capture).unwrap();
        let canonical_repository = fs::canonicalize(&fixture.0).unwrap();
        let expected = [
            canonical_repository.as_os_str().as_bytes(),
            odd_file.as_os_str().as_bytes(),
            b"branch ' -- ;$()",
            b"deadbeef;$(false)",
            b"literal;$(touch injected)",
            b"--leading",
        ]
        .join(&0);
        let mut expected_with_terminator = expected;
        expected_with_terminator.push(0);
        assert_eq!(captured, expected_with_terminator);
        assert!(!fixture.0.join("injected").exists());

        let shell_output = fixture.0.join("explicit-shell.txt");
        let quoted_output = shell_output.to_string_lossy().replace('\'', "'\"'\"'");
        let shell_preview = repository_session_integration_preview(
            session.session_id,
            session.generation,
            NativeIntegrationRequest {
                kind: NativeIntegrationKind::Custom,
                discovered_id: None,
                configured: Some(NativeIntegrationDefinition {
                    id: "explicit-shell".to_owned(),
                    kind: NativeIntegrationKind::Custom,
                    executable: crate::domain::path_identity::native_path_identity(Path::new(
                        "/bin/sh",
                    )),
                    arguments: vec![
                        "-c".to_owned(),
                        format!("printf shell-ok > '{quoted_output}'"),
                    ],
                    execution: NativeIntegrationExecution::ExplicitShell,
                    launch_mode: NativeIntegrationLaunchMode::Wait,
                    requires_confirmation: false,
                    timeout_seconds: 5,
                }),
                variables: NativeIntegrationVariables::default(),
            },
        )
        .preview
        .unwrap();
        assert!(shell_preview.explicit_shell);
        assert_eq!(
            repository_session_integration_execute(
                session.session_id,
                session.generation,
                shell_preview.token,
                false,
            )
            .failure
            .unwrap()
            .kind,
            NativeIntegrationFailureKind::ConfirmationRequired
        );
        assert_eq!(
            repository_session_integration_execute(
                session.session_id,
                session.generation,
                shell_preview.token,
                true,
            )
            .state,
            NativeIntegrationExecutionState::Completed
        );
        assert_eq!(fs::read(shell_output).unwrap(), b"shell-ok");

        let stale = repository_session_integration_preview(
            session.session_id,
            session.generation,
            NativeIntegrationRequest {
                kind: NativeIntegrationKind::Custom,
                discovered_id: None,
                configured: Some(NativeIntegrationDefinition {
                    id: "stale".to_owned(),
                    kind: NativeIntegrationKind::Custom,
                    executable: crate::domain::path_identity::native_path_identity(&runner),
                    arguments: vec![],
                    execution: NativeIntegrationExecution::Direct,
                    launch_mode: NativeIntegrationLaunchMode::Wait,
                    requires_confirmation: true,
                    timeout_seconds: 5,
                }),
                variables: NativeIntegrationVariables::default(),
            },
        )
        .preview
        .unwrap();
        fs::write(fixture.0.join("tracked.txt"), b"moved\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "move head"]);
        refresh_session(&session);
        assert_eq!(
            repository_session_integration_execute(
                session.session_id,
                session.generation,
                stale.token,
                true,
            )
            .state,
            NativeIntegrationExecutionState::Stale
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn external_diff_materializes_exact_commit_sides_and_cleans_temporary_files() {
        use std::os::unix::fs::PermissionsExt;

        let fixture = GitFixture::new();
        let path = "binary space.bin";
        fs::write(fixture.0.join(path), b"\0old").unwrap();
        transfer_git(&fixture.0, &["add", path]);
        transfer_git(&fixture.0, &["commit", "-qm", "old"]);
        let old = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"])).unwrap();
        fs::write(fixture.0.join(path), b"\0new").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "new"]);
        let new = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"])).unwrap();
        let runner = fixture.0.join("diff tool");
        fs::write(&runner, "#!/bin/sh\ntest -f \"$1\" && test -f \"$2\"\n").unwrap();
        fs::set_permissions(&runner, fs::Permissions::from_mode(0o700)).unwrap();
        let session = repository_session_open_with_options(
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
        wait_for_ready(&session);
        let preview = repository_session_commit_external_diff_preview(
            session.session_id,
            session.generation,
            Some(old.trim().to_owned()),
            new.trim().to_owned(),
            Some(path.as_bytes().to_vec()),
            Some(path.as_bytes().to_vec()),
            NativeIntegrationDefinition {
                id: "fixture diff".to_owned(),
                kind: NativeIntegrationKind::DiffTool,
                executable: crate::domain::path_identity::native_path_identity(&runner),
                arguments: vec!["{diff_left}".to_owned(), "{diff_right}".to_owned()],
                execution: NativeIntegrationExecution::Direct,
                launch_mode: NativeIntegrationLaunchMode::Wait,
                requires_confirmation: true,
                timeout_seconds: 30,
            },
        )
        .preview
        .unwrap();
        assert_eq!(fs::read(&preview.arguments[0]).unwrap(), b"\0old");
        assert_eq!(fs::read(&preview.arguments[1]).unwrap(), b"\0new");
        assert_eq!(
            repository_session_integration_execute(
                session.session_id,
                session.generation,
                preview.token,
                true,
            )
            .state,
            NativeIntegrationExecutionState::Completed
        );
        assert!(!Path::new(&preview.arguments[0]).exists());
        assert!(!Path::new(&preview.arguments[1]).exists());

        // A repository on another computer: its host keeps both sides, and the same tool compares
        // copies here without a local repository.
        let source = repository_session_change_source(
            session.session_id,
            session.generation,
            Some(old.trim().to_owned()),
            new.trim().to_owned(),
            Some(path.as_bytes().to_vec()),
            Some(path.as_bytes().to_vec()),
            64 * 1024 * 1024,
        );
        assert!(source.failure.is_none());
        let side = |new_side| {
            repository_session_change_source_page(
                session.session_id,
                session.generation,
                source.token,
                new_side,
                0,
            )
            .bytes
        };
        let detached = external_diff_detached_preview(
            side(false),
            side(true),
            NativeIntegrationDefinition {
                id: "fixture diff".to_owned(),
                kind: NativeIntegrationKind::DiffTool,
                executable: crate::domain::path_identity::native_path_identity(&runner),
                arguments: vec!["{diff_left}".to_owned(), "{diff_right}".to_owned()],
                execution: NativeIntegrationExecution::Direct,
                launch_mode: NativeIntegrationLaunchMode::Wait,
                requires_confirmation: true,
                timeout_seconds: 30,
            },
        )
        .preview
        .unwrap();
        assert_eq!(fs::read(&detached.arguments[0]).unwrap(), b"\0old");
        assert_eq!(fs::read(&detached.arguments[1]).unwrap(), b"\0new");
        assert_eq!(
            external_diff_detached_execute(detached.token, true).state,
            NativeIntegrationExecutionState::Completed
        );
        assert!(!Path::new(&detached.arguments[0]).exists());
        assert!(!Path::new(&detached.arguments[1]).exists());
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn custom_command_timeout_and_cancel_reap_the_process() {
        use std::os::unix::fs::PermissionsExt;

        let fixture = GitFixture::new();
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        let marker = fixture.0.join("started");
        let runner = fixture.0.join("stall-command");
        let quoted_marker = marker.to_string_lossy().replace('\'', "'\"'\"'");
        fs::write(
            &runner,
            format!("#!/bin/sh\ntouch '{quoted_marker}'\nsleep 20\n"),
        )
        .unwrap();
        fs::set_permissions(&runner, fs::Permissions::from_mode(0o700)).unwrap();
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
        let request = |id: &str, timeout_seconds| NativeIntegrationRequest {
            kind: NativeIntegrationKind::Custom,
            discovered_id: None,
            configured: Some(NativeIntegrationDefinition {
                id: id.to_owned(),
                kind: NativeIntegrationKind::Custom,
                executable: crate::domain::path_identity::native_path_identity(&runner),
                arguments: vec![],
                execution: NativeIntegrationExecution::Direct,
                launch_mode: NativeIntegrationLaunchMode::Wait,
                requires_confirmation: true,
                timeout_seconds,
            }),
            variables: NativeIntegrationVariables::default(),
        };
        let timed = repository_session_integration_preview(
            session.session_id,
            session.generation,
            request("timeout", 1),
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_integration_execute(
                session.session_id,
                session.generation,
                timed.token,
                true,
            )
            .state,
            NativeIntegrationExecutionState::TimedOut
        );
        let _ = fs::remove_file(&marker);

        let canceled = repository_session_integration_preview(
            session.session_id,
            session.generation,
            request("cancel", 30),
        )
        .preview
        .unwrap();
        let session_id = session.session_id;
        let generation = session.generation;
        let token = canceled.token;
        let execution = std::thread::spawn(move || {
            repository_session_integration_execute(session_id, generation, token, true)
        });
        let deadline = Instant::now() + Duration::from_secs(30);
        while !marker.exists() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(marker.exists());
        assert!(
            repository_session_integration_cancel(
                session.session_id,
                session.generation,
                canceled.token
            )
            .accepted
        );
        assert_eq!(
            execution.join().unwrap().state,
            NativeIntegrationExecutionState::Canceled
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }
}
