//! Exporting patches to files or pages and applying patch files.
#![allow(clippy::wildcard_imports)]
use crate::activity::allocate_activity_id;
use crate::activity::ActivityStore;
use crate::application::{diff::*, paths::*, session::*, staging::*};
use crate::diff::selection_for_rows;
use crate::domain::ids::SessionKey;
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::dto::*;
use crate::preview_store::SessionPreviews;
use devmil_git::activity::ActivityStatus;
use devmil_git::commands::patch::{export_arguments, PatchExportSource};
use devmil_git::diff::model::ContextLines;
use devmil_git::diff::model::FileChangeKind;
use devmil_git::diff::{BytePatchBuilder, PatchConstructionRequest};
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::types::{ObjectId, RepositoryRelativePath};
use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use devmil_git::diff::{parse_unified_patch, PatchLimits};

/// A session's patch exports, built patch contents and patch applications.
pub(crate) struct PatchState {
    pub(crate) exports: SessionPreviews<OwnedPatchExportPreview>,
    /// Built patches whose pages another computer reads.
    pub(crate) contents: SessionPreviews<Arc<Vec<u8>>>,
    pub(crate) applies: SessionPreviews<OwnedPatchApplyPreview>,
}

impl Default for PatchState {
    fn default() -> Self {
        Self {
            exports: SessionPreviews::new(PATCH_PREVIEW_CAPACITY),
            contents: SessionPreviews::new(PATCH_PREVIEW_CAPACITY),
            applies: SessionPreviews::new(PATCH_PREVIEW_CAPACITY),
        }
    }
}

struct PreparedPatchExport {
    selected: SelectedPatchExport,
    worktree: PathBuf,
    git_dir: PathBuf,
    index_bytes: Option<Vec<u8>>,
}

/// Builds the patch [request] names from the session's current state.
fn prepare_patch_export(
    session_id: u64,
    generation: u64,
    request: &NativePatchExportRequest,
) -> Result<PreparedPatchExport, NativeRepositoryFailureKind> {
    if request.row_ids.len() > crate::domain::limits::STAGE_ROWS
        || request.selected_paths.len() > crate::domain::limits::STAGE_PATHS
        || request.range_commits.len() > 10_000
    {
        return Err(NativeRepositoryFailureKind::InvalidOptions);
    }
    let (repository, activity, staging) = {
        let sessions = lock_sessions();
        let session = sessions.session(SessionKey::new(session_id, generation))?;
        (
            Arc::clone(&session.repository),
            session.activity.clone(),
            session
                .staging
                .projection
                .as_ref()
                .map(|value| OwnedStagingProjection {
                    request_id: value.request_id,
                    side: value.side,
                    document: Arc::clone(&value.document),
                    projection: value.projection.clone(),
                    worktree: value.worktree.clone(),
                    git_dir: value.git_dir.clone(),
                    unborn: value.unborn,
                    index_bytes: value.index_bytes.clone(),
                    worktree_states: value.worktree_states.clone(),
                    untracked_paths: value.untracked_paths.clone(),
                    force_text: value.force_text,
                }),
        )
    };
    let snapshot = repository.snapshot();
    let Some(discovered) = snapshot.repository.as_ref() else {
        return Err(NativeRepositoryFailureKind::Discovery);
    };
    let worktree = discovered.worktree.worktree_root().as_path().to_path_buf();
    let git_dir = discovered.worktree.git_dir().as_path().to_path_buf();
    let index_bytes = read_optional_bounded(&git_dir.join("index"), 128 * 1024 * 1024)?;
    let selected = select_patch_export(request, staging.as_ref(), &activity, &worktree)?;
    if selected.bytes.is_empty() {
        return Err(NativeRepositoryFailureKind::InvalidOptions);
    }
    Ok(PreparedPatchExport {
        selected,
        worktree,
        git_dir,
        index_bytes,
    })
}

/// Resolves patch scope in product precedence order and freezes one nonempty output.
pub fn repository_session_patch_export_preview(
    session_id: u64,
    generation: u64,
    request: NativePatchExportRequest,
) -> NativePatchExportPreviewResult {
    let PreparedPatchExport {
        selected,
        worktree,
        git_dir,
        index_bytes,
    } = match prepare_patch_export(session_id, generation, &request) {
        Ok(value) => value,
        Err(kind) => return patch_export_preview_failure(kind),
    };
    let directory = PathBuf::from(&request.destination_directory);
    if !directory.is_absolute()
        || fs::symlink_metadata(&directory).map_or(true, |metadata| {
            metadata.file_type().is_symlink() || !metadata.is_dir()
        })
    {
        return patch_export_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let destination = directory.join(&selected.filename);
    let destination_bytes = match read_optional_bounded(&destination, 128 * 1024 * 1024) {
        Ok(value) => value,
        Err(kind) => return patch_export_preview_failure(kind),
    };
    let requires_overwrite = destination_bytes.is_some() && !request.overwrite;
    let mut token = None;
    if !requires_overwrite {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return patch_export_preview_failure(kind),
        };
        token = Some(session.patch.exports.issue(OwnedPatchExportPreview {
            bytes: selected.bytes.clone(),
            destination: destination.clone(),
            destination_bytes,
            worktree: worktree.clone(),
            git_dir,
            index_bytes,
            worktree_states: selected.worktree_states,
        }));
    }
    NativePatchExportPreviewResult {
        preview: Some(NativePatchExportPreview {
            token,
            scope: selected.scope,
            format: selected.format,
            filename: selected.filename,
            destination: destination.to_string_lossy().into_owned(),
            byte_count: selected.bytes.len() as u64,
            requires_overwrite,
        }),
        failure: None,
    }
}

pub fn repository_session_patch_export_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativePatchExportExecutionResult {
    let preview = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return patch_export_execution_failure(kind),
        };
        let Some(value) = session.patch.exports.take(token) else {
            return patch_export_execution_failure(NativeRepositoryFailureKind::InvalidOptions);
        };
        value
    };
    if !patch_export_preconditions_match(&preview) {
        return NativePatchExportExecutionResult {
            state: NativePatchExportExecutionState::Stale,
            destination: None,
            failure: None,
        };
    }
    if atomic_patch_write(
        &preview.destination,
        &preview.bytes,
        preview.destination_bytes.as_deref(),
    )
    .is_err()
    {
        return patch_export_execution_failure(NativeRepositoryFailureKind::Read);
    }
    NativePatchExportExecutionResult {
        state: NativePatchExportExecutionState::Completed,
        destination: Some(preview.destination.to_string_lossy().into_owned()),
        failure: None,
    }
}

/// Bytes of a built patch one content page carries; a page stays within one wire frame.
const PATCH_CONTENT_PAGE_BYTES: usize = 1024 * 1024;

/// Builds the patch `request` names without writing it, for a repository whose patch is saved
/// on another computer: the first page comes with it and
/// [`repository_session_patch_export_content_page`] returns the rest of the same bytes. The
/// destination fields of `request` are ignored.
pub fn repository_session_patch_export_content(
    session_id: u64,
    generation: u64,
    request: NativePatchExportRequest,
) -> NativePatchExportContentResult {
    let content_failure = |kind| NativePatchExportContentResult {
        content: None,
        failure: Some(NativeRepositoryFailure { kind }),
    };
    let selected = match prepare_patch_export(session_id, generation, &request) {
        Ok(value) => value.selected,
        Err(kind) => return content_failure(kind),
    };
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return content_failure(kind),
    };
    let first = selected.bytes[..selected.bytes.len().min(PATCH_CONTENT_PAGE_BYTES)].to_vec();
    let total_bytes = selected.bytes.len() as u64;
    let token = session.patch.contents.issue(Arc::new(selected.bytes));
    NativePatchExportContentResult {
        content: Some(NativePatchExportContent {
            token,
            scope: selected.scope,
            format: selected.format,
            filename: selected.filename,
            total_bytes,
            first,
        }),
        failure: None,
    }
}

/// The bytes of a built patch from `offset`, at most one page.
pub fn repository_session_patch_export_content_page(
    session_id: u64,
    generation: u64,
    token: u64,
    offset: u64,
) -> NativePatchExportContentPage {
    let page_failure = |kind| NativePatchExportContentPage {
        bytes: Vec::new(),
        failure: Some(NativeRepositoryFailure { kind }),
    };
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return page_failure(kind),
    };
    let Some(bytes) = session.patch.contents.get(token) else {
        return page_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    let Some(start) = usize::try_from(offset)
        .ok()
        .filter(|start| *start <= bytes.len())
    else {
        return page_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    let end = bytes.len().min(start + PATCH_CONTENT_PAGE_BYTES);
    NativePatchExportContentPage {
        bytes: bytes[start..end].to_vec(),
        failure: None,
    }
}

struct OwnedPatchSave {
    bytes: Vec<u8>,
    destination: PathBuf,
    destination_bytes: Option<Vec<u8>>,
}

/// Saves of patches built on another computer: no session owns them.
fn patch_saves() -> std::sync::MutexGuard<'static, SessionPreviews<OwnedPatchSave>> {
    static SAVES: OnceLock<Mutex<SessionPreviews<OwnedPatchSave>>> = OnceLock::new();
    SAVES
        .get_or_init(|| Mutex::new(SessionPreviews::new(PATCH_PREVIEW_CAPACITY)))
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Prepares saving patch `bytes` built on another computer as `filename` in the local
/// `destination_directory`, with the destination checks of a local export.
pub fn patch_export_save_preview(
    destination_directory: String,
    filename: String,
    bytes: Vec<u8>,
    overwrite: bool,
) -> NativePatchSavePreviewResult {
    let save_failure = |kind| NativePatchSavePreviewResult {
        token: None,
        destination: None,
        requires_overwrite: false,
        failure: Some(NativeRepositoryFailure { kind }),
    };
    // The name comes from the other computer: one plain file name and nothing else.
    if bytes.is_empty()
        || bytes.len() > 128 * 1024 * 1024
        || filename.is_empty()
        || filename == "."
        || filename == ".."
        || filename.contains(['/', '\\', '\0'])
        || filename.len() > 255
    {
        return save_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let directory = PathBuf::from(&destination_directory);
    if !directory.is_absolute()
        || fs::symlink_metadata(&directory).map_or(true, |metadata| {
            metadata.file_type().is_symlink() || !metadata.is_dir()
        })
    {
        return save_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let destination = directory.join(&filename);
    let destination_bytes = match read_optional_bounded(&destination, 128 * 1024 * 1024) {
        Ok(value) => value,
        Err(kind) => return save_failure(kind),
    };
    let requires_overwrite = destination_bytes.is_some() && !overwrite;
    let token = if requires_overwrite {
        None
    } else {
        Some(patch_saves().issue(OwnedPatchSave {
            bytes,
            destination: destination.clone(),
            destination_bytes,
        }))
    };
    NativePatchSavePreviewResult {
        token,
        destination: Some(destination.to_string_lossy().into_owned()),
        requires_overwrite,
        failure: None,
    }
}

/// Writes a prepared patch save once; a destination that changed since is stale.
pub fn patch_export_save_execute(token: u64) -> NativePatchExportExecutionResult {
    let Some(save) = patch_saves().take(token) else {
        return patch_export_execution_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    match read_optional_bounded(&save.destination, 128 * 1024 * 1024) {
        Ok(current) if current == save.destination_bytes => {}
        Ok(_) => {
            return NativePatchExportExecutionResult {
                state: NativePatchExportExecutionState::Stale,
                destination: None,
                failure: None,
            };
        }
        Err(kind) => return patch_export_execution_failure(kind),
    }
    if atomic_patch_write(
        &save.destination,
        &save.bytes,
        save.destination_bytes.as_deref(),
    )
    .is_err()
    {
        return patch_export_execution_failure(NativeRepositoryFailureKind::Read);
    }
    NativePatchExportExecutionResult {
        state: NativePatchExportExecutionState::Completed,
        destination: Some(save.destination.to_string_lossy().into_owned()),
        failure: None,
    }
}

/// Parses and checks a patch and freezes the affected paths.
pub fn repository_session_patch_apply_preview(
    session_id: u64,
    generation: u64,
    patch_path: String,
) -> NativePatchApplyPreviewResult {
    let (repository, activity) = match session_repository_and_activity(session_id, generation) {
        Ok(value) => value,
        Err(kind) => return patch_apply_preview_failure(kind),
    };
    let snapshot = repository.snapshot();
    let Some(discovered) = snapshot.repository.as_ref() else {
        return patch_apply_preview_failure(NativeRepositoryFailureKind::Discovery);
    };
    let patch_path = PathBuf::from(patch_path);
    if !patch_path.is_absolute() {
        return patch_apply_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let patch_bytes = match read_optional_bounded(&patch_path, 64 * 1024 * 1024) {
        Ok(Some(value)) if !value.is_empty() => value,
        Ok(_) => return patch_apply_preview_failure(NativeRepositoryFailureKind::InvalidOptions),
        Err(kind) => return patch_apply_preview_failure(kind),
    };
    let document = match parse_unified_patch(
        &patch_bytes,
        PatchLimits {
            max_bytes: 64 * 1024 * 1024,
            max_lines: 1_000_000,
            preview_line_limit: 400,
        },
    ) {
        Ok(value) if !value.files.is_empty() => value,
        Ok(_) => return patch_apply_preview_failure(NativeRepositoryFailureKind::InvalidOutput),
        Err(error) => return patch_apply_preview_failure(map_diff_error_kind(error.kind)),
    };
    let mut paths = BTreeSet::new();
    let mut binary = false;
    for file in &document.files {
        binary |= file.fallback.is_some() || matches!(file.kind, FileChangeKind::Binary);
        for path in [&file.id.old_path, &file.id.new_path].into_iter().flatten() {
            if !valid_patch_path(path.as_bytes()) {
                return patch_apply_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            }
            paths.insert(path.as_bytes().to_vec());
        }
    }
    let paths = paths.into_iter().collect::<Vec<_>>();
    if paths.is_empty() || paths.len() > crate::domain::limits::STAGE_PATHS {
        return patch_apply_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let worktree = discovered.worktree.worktree_root().as_path().to_path_buf();
    let git_dir = discovered.worktree.git_dir().as_path().to_path_buf();
    if patch_apply_check(
        &activity,
        repository.git_executable(),
        &worktree,
        &patch_bytes,
    )
    .is_err()
    {
        return patch_apply_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let index_bytes = match read_optional_bounded(&git_dir.join("index"), 128 * 1024 * 1024) {
        Ok(value) => value,
        Err(kind) => return patch_apply_preview_failure(kind),
    };
    let worktree_states = match capture_staging_paths(&worktree, paths.iter().cloned().collect()) {
        Ok(value) => value,
        Err(kind) => return patch_apply_preview_failure(kind),
    };
    if patch_apply_check(
        &activity,
        repository.git_executable(),
        &worktree,
        &patch_bytes,
    )
    .is_err()
        || read_optional_bounded(&git_dir.join("index"), 128 * 1024 * 1024)
            .map_or(true, |current| current != index_bytes)
        || capture_staging_paths(&worktree, paths.iter().cloned().collect())
            .map_or(true, |current| current != worktree_states)
    {
        return patch_apply_preview_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return patch_apply_preview_failure(kind),
    };
    let token = session.patch.applies.issue(OwnedPatchApplyPreview {
        patch_file_bytes: patch_bytes.clone(),
        patch_bytes,
        patch_path: patch_path.clone(),
        worktree,
        git_dir,
        index_bytes,
        worktree_states,
    });
    NativePatchApplyPreviewResult {
        preview: Some(NativePatchApplyPreview {
            token,
            paths,
            binary,
            arguments: vec!["apply".into(), "--recount".into(), "<patch>".into()],
        }),
        failure: None,
    }
}

pub fn repository_session_patch_apply_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativePatchApplyExecutionResult {
    let (repository, activity, preview) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return patch_apply_execution_failure(kind),
        };
        let Some(preview) = session.patch.applies.take(token) else {
            return patch_apply_execution_failure(NativeRepositoryFailureKind::InvalidOptions);
        };
        (
            Arc::clone(&session.repository),
            session.activity.clone(),
            preview,
        )
    };
    if !patch_apply_preconditions_match(&preview) {
        return NativePatchApplyExecutionResult {
            state: NativePatchApplyExecutionState::Stale,
            failure: None,
        };
    }
    let command = devmil_git::commands::restore::apply_patch(
        preview.patch_bytes.clone(),
        devmil_git::commands::restore::ApplyOptions::default(),
    )
    .process_command(repository.git_executable(), &preview.worktree)
    .redact_output();
    let cancellation = AtomicBool::new(false);
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let outcome = crate::operations::coordinate_process_mutation(
        &repository,
        &cancellation,
        command,
        crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change),
        &mut publish,
    );
    let outcome = MutationOutcome::from_terminal(outcome);
    patch_apply_result(
        if matches!(
            outcome.state,
            MutationState::Canceled | MutationState::Failed
        ) {
            outcome.with_failure(Some(NativeRepositoryFailureKind::Read))
        } else {
            outcome
        },
    )
}

/// The bridge result of a patch application: the one place its outcome becomes a state.
pub(crate) fn patch_apply_result(
    outcome: MutationOutcome<NativeRepositoryFailureKind>,
) -> NativePatchApplyExecutionResult {
    let state = match outcome.state {
        MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
            NativePatchApplyExecutionState::Completed
        }
        MutationState::ReconciledWithWarning => {
            NativePatchApplyExecutionState::ReconciledWithWarning
        }
        MutationState::Stale => NativePatchApplyExecutionState::Stale,
        MutationState::Conflict
        | MutationState::Interrupted
        | MutationState::EditStop
        | MutationState::Partial
        | MutationState::Canceled
        | MutationState::Failed => NativePatchApplyExecutionState::Failed,
        MutationState::OutcomeUncertain => NativePatchApplyExecutionState::OutcomeUncertain,
    };
    NativePatchApplyExecutionResult {
        state,
        failure: outcome.failure.map(|kind| NativeRepositoryFailure { kind }),
    }
}

pub(crate) struct OwnedPatchExportPreview {
    pub(crate) bytes: Vec<u8>,
    pub(crate) destination: PathBuf,
    pub(crate) destination_bytes: Option<Vec<u8>>,
    pub(crate) worktree: PathBuf,
    pub(crate) git_dir: PathBuf,
    pub(crate) index_bytes: Option<Vec<u8>>,
    pub(crate) worktree_states: HashMap<Vec<u8>, StagingPathState>,
}

pub(crate) struct OwnedPatchApplyPreview {
    pub(crate) patch_bytes: Vec<u8>,
    pub(crate) patch_path: PathBuf,
    pub(crate) patch_file_bytes: Vec<u8>,
    pub(crate) worktree: PathBuf,
    pub(crate) git_dir: PathBuf,
    pub(crate) index_bytes: Option<Vec<u8>>,
    pub(crate) worktree_states: HashMap<Vec<u8>, StagingPathState>,
}
pub(crate) static NEXT_PATCH_TEMPORARY: std::sync::atomic::AtomicU64 =
    std::sync::atomic::AtomicU64::new(1);
pub(crate) const PATCH_PREVIEW_CAPACITY: usize = 4;

pub(crate) const fn patch_export_preview_failure(
    kind: NativeRepositoryFailureKind,
) -> NativePatchExportPreviewResult {
    NativePatchExportPreviewResult {
        preview: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn patch_export_execution_failure(
    kind: NativeRepositoryFailureKind,
) -> NativePatchExportExecutionResult {
    NativePatchExportExecutionResult {
        state: NativePatchExportExecutionState::Failed,
        destination: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn patch_apply_preview_failure(
    kind: NativeRepositoryFailureKind,
) -> NativePatchApplyPreviewResult {
    NativePatchApplyPreviewResult {
        preview: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn patch_apply_execution_failure(
    kind: NativeRepositoryFailureKind,
) -> NativePatchApplyExecutionResult {
    NativePatchApplyExecutionResult {
        state: NativePatchApplyExecutionState::Failed,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) struct SelectedPatchExport {
    pub(crate) scope: NativePatchExportScope,
    pub(crate) format: NativePatchFormat,
    pub(crate) filename: String,
    pub(crate) bytes: Vec<u8>,
    pub(crate) worktree_states: HashMap<Vec<u8>, StagingPathState>,
}

pub(crate) fn select_patch_export(
    request: &NativePatchExportRequest,
    staging: Option<&OwnedStagingProjection>,
    activity: &ActivityStore,
    worktree: &Path,
) -> Result<SelectedPatchExport, NativeRepositoryFailureKind> {
    let repository_name = worktree
        .file_name()
        .and_then(|value| value.to_str())
        .map(safe_patch_slug)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "repository".into());
    if !request.row_ids.is_empty() {
        let projection = staging.ok_or(NativeRepositoryFailureKind::InvalidOptions)?;
        if request.working_diff_request_id != Some(projection.request_id)
            || projection.document.files.len() != 1
        {
            return Err(NativeRepositoryFailureKind::StaleGeneration);
        }
        let file = projection.document.files.first().unwrap();
        let selection = selection_for_rows(file, 0, &request.row_ids)
            .ok_or(NativeRepositoryFailureKind::InvalidOptions)?;
        let bytes = BytePatchBuilder
            .construct_patch(&PatchConstructionRequest {
                file: file.clone(),
                selection,
                context: ContextLines::new(3).expect("constant context is valid"),
                reverse: false,
            })
            .map_err(|error| map_diff_error_kind(error.kind))?
            .bytes;
        let basename = file
            .id
            .new_path
            .as_ref()
            .or(file.id.old_path.as_ref())
            .and_then(|path| {
                native_path_argument(path.as_bytes().to_vec()).and_then(|value| {
                    PathBuf::from(value)
                        .file_name()?
                        .to_str()
                        .map(str::to_owned)
                })
            })
            .map(|value| safe_patch_slug(&value))
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "selection".into());
        return Ok(SelectedPatchExport {
            scope: NativePatchExportScope::Lines,
            format: NativePatchFormat::UnifiedDiff,
            filename: format!("{basename}.partial.patch"),
            bytes,
            worktree_states: projection.worktree_states.clone(),
        });
    }
    let history_paths = patch_paths(&request.history_paths)?;
    let (source, paths, scope, format, filename) = if !request.selected_paths.is_empty() {
        let side = request
            .selected_side
            .ok_or(NativeRepositoryFailureKind::InvalidOptions)?;
        let staged = side == NativePatchSide::Staged;
        (
            PatchExportSource::Worktree { staged },
            patch_paths(&request.selected_paths)?,
            if staged {
                NativePatchExportScope::SelectedFilesStaged
            } else {
                NativePatchExportScope::SelectedFilesUnstaged
            },
            NativePatchFormat::UnifiedDiff,
            if staged {
                format!("{repository_name}-selected-staged.patch")
            } else {
                format!("{repository_name}-selected.patch")
            },
        )
    } else if let Some(side) = request.focused_side {
        let staged = side == NativePatchSide::Staged;
        (
            PatchExportSource::Worktree { staged },
            Vec::new(),
            if staged {
                NativePatchExportScope::Staged
            } else {
                NativePatchExportScope::Unstaged
            },
            NativePatchFormat::UnifiedDiff,
            format!(
                "{repository_name}-{}.patch",
                if staged { "staged" } else { "unstaged" }
            ),
        )
    } else if let (Some(old), Some(new)) = (&request.comparison_old, &request.comparison_new) {
        let old = ObjectId::parse(old.clone())
            .map_err(|_| NativeRepositoryFailureKind::InvalidOptions)?;
        let new = ObjectId::parse(new.clone())
            .map_err(|_| NativeRepositoryFailureKind::InvalidOptions)?;
        let filename = format!(
            "{}-{}{}.patch",
            &old.as_str()[..8],
            &new.as_str()[..8],
            patch_path_suffix(&history_paths)
        );
        (
            PatchExportSource::Comparison { old, new },
            history_paths,
            NativePatchExportScope::Compare,
            NativePatchFormat::UnifiedDiff,
            filename,
        )
    } else if request.range_commits.len() >= 2 {
        let commits = request
            .range_commits
            .iter()
            .cloned()
            .map(ObjectId::parse)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| NativeRepositoryFailureKind::InvalidOptions)?;
        let from_root = validate_first_parent_range(activity, worktree, &commits)?;
        let oldest = commits.first().unwrap().clone();
        let newest = commits.last().unwrap().clone();
        let filename = format!("{}-{}.patch", &oldest.as_str()[..8], &newest.as_str()[..8]);
        (
            PatchExportSource::FirstParentRange {
                oldest,
                newest,
                from_root,
            },
            Vec::new(),
            NativePatchExportScope::Range,
            NativePatchFormat::FormatPatch,
            filename,
        )
    } else if let Some(commit) = &request.commit {
        let commit = ObjectId::parse(commit.clone())
            .map_err(|_| NativeRepositoryFailureKind::InvalidOptions)?;
        let filename = format!(
            "0001-{}{}.patch",
            &commit.as_str()[..8],
            patch_path_suffix(&history_paths)
        );
        (
            PatchExportSource::Commit(commit),
            history_paths,
            NativePatchExportScope::Commit,
            NativePatchFormat::FormatPatch,
            filename,
        )
    } else if request.workspace_default {
        (
            PatchExportSource::Head,
            Vec::new(),
            NativePatchExportScope::Head,
            NativePatchFormat::UnifiedDiff,
            format!("{repository_name}.patch"),
        )
    } else {
        return Err(NativeRepositoryFailureKind::InvalidOptions);
    };
    // Paths follow the option separator and stay out of the activity record.
    let mut scoped = false;
    let arguments = export_arguments(&source, &paths)
        .into_iter()
        .map(|argument| {
            if scoped {
                ProcessArgument::redacted(argument, "<path>")
            } else {
                scoped = argument == "--";
                ProcessArgument::visible(argument)
            }
        })
        .collect::<Vec<_>>();
    let command = GitProcessCommand::git("git")
        .current_dir(worktree)
        .args(arguments)
        .output_limit(64 * 1024 * 1024)
        .redact_output();
    let bytes = run_patch_capture(activity, command)?;
    Ok(SelectedPatchExport {
        scope,
        format,
        filename,
        bytes,
        worktree_states: HashMap::new(),
    })
}

pub(crate) fn patch_paths(
    paths: &[Vec<u8>],
) -> Result<Vec<RepositoryRelativePath>, NativeRepositoryFailureKind> {
    paths
        .iter()
        .map(|path| {
            valid_patch_path(path)
                .then(|| native_path_argument(path.clone()))
                .flatten()
                .and_then(|value| RepositoryRelativePath::new(PathBuf::from(value)).ok())
                .ok_or(NativeRepositoryFailureKind::InvalidOptions)
        })
        .collect()
}

/// Names the file a single-path patch is limited to, so it does not replace
/// the patch of the whole commit or comparison in the same directory.
pub(crate) fn patch_path_suffix(paths: &[RepositoryRelativePath]) -> String {
    let [path] = paths else {
        return if paths.is_empty() {
            String::new()
        } else {
            "-selected".into()
        };
    };
    path.as_path()
        .file_name()
        .and_then(|name| name.to_str())
        .map(safe_patch_slug)
        .filter(|name| !name.is_empty())
        .map_or_else(|| "-selected".into(), |name| format!("-{name}"))
}

pub(crate) fn validate_first_parent_range(
    activity: &ActivityStore,
    worktree: &Path,
    requested: &[ObjectId],
) -> Result<bool, NativeRepositoryFailureKind> {
    let newest = requested
        .last()
        .ok_or(NativeRepositoryFailureKind::InvalidOptions)?;
    let command = GitProcessCommand::git("git")
        .current_dir(worktree)
        .args([
            ProcessArgument::visible("rev-list"),
            ProcessArgument::visible("--first-parent"),
            ProcessArgument::visible("--reverse"),
            ProcessArgument::visible(newest.as_str()),
        ])
        .output_limit(4 * 1024 * 1024)
        .redact_output();
    let output = run_patch_capture(activity, command)?;
    let actual = output
        .split(|byte| *byte == b'\n')
        .filter(|line| !line.is_empty())
        .map(|line| std::str::from_utf8(line).ok())
        .collect::<Option<Vec<_>>>()
        .ok_or(NativeRepositoryFailureKind::InvalidOutput)?;
    let Some(start) = actual
        .iter()
        .position(|candidate| *candidate == requested[0].as_str())
    else {
        return Err(NativeRepositoryFailureKind::InvalidOptions);
    };
    if actual[start..].len() != requested.len()
        || actual[start..]
            .iter()
            .zip(requested)
            .any(|(actual, requested)| *actual != requested.as_str())
    {
        return Err(NativeRepositoryFailureKind::InvalidOptions);
    }
    Ok(start == 0)
}

pub(crate) fn safe_patch_slug(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.') {
                character
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches(['-', '.'])
        .chars()
        .take(80)
        .collect()
}

pub(crate) fn run_patch_capture(
    activity: &ActivityStore,
    command: GitProcessCommand,
) -> Result<Vec<u8>, NativeRepositoryFailureKind> {
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let mut result =
        ActivityGitRunner::run_private(command, allocate_activity_id(), None, &mut publish);
    if matches!(result.activity.status, ActivityStatus::Succeeded { .. }) {
        Ok(result.stdout.take_bytes())
    } else {
        Err(NativeRepositoryFailureKind::Read)
    }
}

pub(crate) fn run_patch_command(
    activity: &ActivityStore,
    command: GitProcessCommand,
) -> Result<(), NativeRepositoryFailureKind> {
    run_patch_capture(activity, command).map(|_| ())
}

pub(crate) fn patch_apply_check(
    activity: &ActivityStore,
    executable: &std::ffi::OsStr,
    worktree: &Path,
    patch_bytes: &[u8],
) -> Result<(), NativeRepositoryFailureKind> {
    let command = devmil_git::commands::restore::apply_patch(
        patch_bytes.to_vec(),
        devmil_git::commands::restore::ApplyOptions {
            check: true,
            unidiff_zero: false,
        },
    )
    .process_command(executable, worktree)
    .redact_output();
    run_patch_command(activity, command)
}

pub(crate) fn patch_export_preconditions_match(preview: &OwnedPatchExportPreview) -> bool {
    read_optional_bounded(&preview.destination, 128 * 1024 * 1024)
        .is_ok_and(|current| current == preview.destination_bytes)
        && read_optional_bounded(&preview.git_dir.join("index"), 128 * 1024 * 1024)
            .is_ok_and(|current| current == preview.index_bytes)
        && staging_states_match(&preview.worktree, &preview.worktree_states)
}

pub(crate) fn atomic_patch_write(
    destination: &Path,
    bytes: &[u8],
    expected: Option<&[u8]>,
) -> Result<(), ()> {
    if bytes.is_empty() {
        return Err(());
    }
    if read_optional_bounded(destination, 128 * 1024 * 1024)
        .map_err(|_| ())?
        .as_deref()
        != expected
    {
        return Err(());
    }
    let parent = destination.parent().ok_or(())?;
    let temporary_id = NEXT_PATCH_TEMPORARY.fetch_add(1, Ordering::Relaxed);
    let temporary = parent.join(format!(
        ".gitlama-patch-{}-{temporary_id}",
        std::process::id()
    ));
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)
        .map_err(|_| ())?;
    let result = (|| {
        file.write_all(bytes).map_err(|_| ())?;
        file.sync_all().map_err(|_| ())?;
        if read_optional_bounded(destination, 128 * 1024 * 1024)
            .map_err(|_| ())?
            .as_deref()
            != expected
        {
            return Err(());
        }
        fs::rename(&temporary, destination).map_err(|_| ())?;
        Ok(())
    })();
    let _ = fs::remove_file(&temporary);
    result
}

pub(crate) fn valid_patch_path(bytes: &[u8]) -> bool {
    if bytes.is_empty() || bytes.contains(&0) {
        return false;
    }
    let Some(native) = native_path_argument(bytes.to_vec()) else {
        return false;
    };
    let path = PathBuf::from(native);
    !path.is_absolute()
        && path
            .components()
            .all(|component| matches!(component, std::path::Component::Normal(_)))
}

pub(crate) fn patch_apply_preconditions_match(preview: &OwnedPatchApplyPreview) -> bool {
    read_optional_bounded(&preview.patch_path, 64 * 1024 * 1024)
        .is_ok_and(|bytes| bytes.as_deref() == Some(preview.patch_file_bytes.as_slice()))
        && read_optional_bounded(&preview.git_dir.join("index"), 128 * 1024 * 1024)
            .is_ok_and(|current| current == preview.index_bytes)
        && capture_staging_paths(
            &preview.worktree,
            preview.worktree_states.keys().cloned().collect(),
        )
        .is_ok_and(|current| current == preview.worktree_states)
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::outcome::MutationTerminalState;

    #[test]
    fn an_uncertain_patch_application_stays_uncertain() {
        let result = patch_apply_result(MutationOutcome::from_terminal(
            MutationTerminalState::OutcomeUncertain,
        ));
        assert_eq!(
            result.state,
            NativePatchApplyExecutionState::OutcomeUncertain
        );
        assert_eq!(result.failure, None);
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{diff::*, patch::*};

    use crate::diff::NativeDiffLayout;
    use crate::diff::DIFF_PAGE_CAPACITY;

    use devmil_git::RepositoryOptions;

    use std::fs;

    use std::path::PathBuf;
    use std::process::Command;

    #[test]
    fn patch_export_obeys_scope_precedence_and_atomic_destination_contract() {
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
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        fs::write(fixture.0.join("staged.txt"), b"base staged\n").unwrap();
        git(&["add", "."]);
        git(&["commit", "-qm", "root"]);
        let root = String::from_utf8(git(&["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(fixture.0.join("history.txt"), b"middle\n").unwrap();
        fs::write(fixture.0.join("other.txt"), b"other\n").unwrap();
        git(&["add", "history.txt", "other.txt"]);
        git(&["commit", "-qm", "middle"]);
        let middle = String::from_utf8(git(&["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(fixture.0.join("history.txt"), b"newest\n").unwrap();
        git(&["commit", "-qam", "newest"]);
        let newest = String::from_utf8(git(&["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(fixture.0.join("staged.txt"), b"staged change\n").unwrap();
        git(&["add", "staged.txt"]);
        fs::write(fixture.0.join("tracked.txt"), b"working change\n").unwrap();
        let output = fixture.0.join("patch-output");
        fs::create_dir(&output).unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            950,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);

        let working = repository_session_working_diff_load(
            session.session_id,
            950,
            NativeWorkingDiffOptions {
                side: NativeStagingSide::Unstaged,
                old_path: Some(b"tracked.txt".to_vec()),
                new_path: Some(b"tracked.txt".to_vec()),
                context_lines: 3,
                whitespace: NativeDiffWhitespace::Preserve,
                layout: NativeDiffLayout::Unified,
                maximum_rows: DIFF_PAGE_CAPACITY as u32,
                force_text: false,
            },
        )
        .page
        .unwrap();
        let mut request = patch_request(&output);
        request.working_diff_request_id = Some(working.request_id);
        request.row_ids = working
            .rows
            .iter()
            .filter(|row| row.text == b"base" || row.text == b"working change")
            .map(|row| row.stable_id.clone())
            .collect();
        request.selected_paths = vec![b"staged.txt".to_vec()];
        request.selected_side = Some(NativePatchSide::Staged);
        request.comparison_old = Some(root.clone());
        request.comparison_new = Some(newest.clone());
        let lines = repository_session_patch_export_preview(session.session_id, 950, request)
            .preview
            .unwrap();
        assert_eq!(lines.scope, NativePatchExportScope::Lines);
        assert_eq!(lines.format, NativePatchFormat::UnifiedDiff);
        assert!(lines.byte_count > 0);

        let mut scopes = Vec::new();
        for (side, path) in [
            (NativePatchSide::Unstaged, b"tracked.txt".to_vec()),
            (NativePatchSide::Staged, b"staged.txt".to_vec()),
        ] {
            let mut request = patch_request(&output);
            request.selected_side = Some(side);
            request.selected_paths = vec![path];
            scopes.push(
                repository_session_patch_export_preview(session.session_id, 950, request)
                    .preview
                    .unwrap()
                    .scope,
            );
        }
        for side in [NativePatchSide::Unstaged, NativePatchSide::Staged] {
            let mut request = patch_request(&output);
            request.focused_side = Some(side);
            scopes.push(
                repository_session_patch_export_preview(session.session_id, 950, request)
                    .preview
                    .unwrap()
                    .scope,
            );
        }
        let mut compare = patch_request(&output);
        compare.comparison_old = Some(root.clone());
        compare.comparison_new = Some(newest.clone());
        scopes.push(
            repository_session_patch_export_preview(session.session_id, 950, compare)
                .preview
                .unwrap()
                .scope,
        );
        let mut commit = patch_request(&output);
        commit.commit = Some(middle.clone());
        let commit_preview =
            repository_session_patch_export_preview(session.session_id, 950, commit)
                .preview
                .unwrap();
        assert_eq!(commit_preview.format, NativePatchFormat::FormatPatch);
        scopes.push(commit_preview.scope);
        let mut range = patch_request(&output);
        range.range_commits = vec![root.clone(), middle.clone(), newest.clone()];
        let range_preview = repository_session_patch_export_preview(session.session_id, 950, range)
            .preview
            .unwrap();
        assert_eq!(range_preview.format, NativePatchFormat::FormatPatch);
        scopes.push(range_preview.scope);
        let mut discontiguous = patch_request(&output);
        discontiguous.range_commits = vec![root.clone(), newest.clone()];
        assert_eq!(
            repository_session_patch_export_preview(session.session_id, 950, discontiguous)
                .failure
                .unwrap()
                .kind,
            NativeRepositoryFailureKind::InvalidOptions
        );
        let mut head = patch_request(&output);
        head.workspace_default = true;
        let head_preview =
            repository_session_patch_export_preview(session.session_id, 950, head.clone())
                .preview
                .unwrap();
        scopes.push(head_preview.scope);
        assert_eq!(
            scopes,
            [
                NativePatchExportScope::SelectedFilesUnstaged,
                NativePatchExportScope::SelectedFilesStaged,
                NativePatchExportScope::Unstaged,
                NativePatchExportScope::Staged,
                NativePatchExportScope::Compare,
                NativePatchExportScope::Commit,
                NativePatchExportScope::Range,
                NativePatchExportScope::Head,
            ]
        );

        let line_ids = working
            .rows
            .iter()
            .filter(|row| row.text == b"base" || row.text == b"working change")
            .map(|row| row.stable_id.clone())
            .collect::<Vec<_>>();
        let mut exact_cases = Vec::new();
        let mut request = patch_request(&output);
        request.working_diff_request_id = Some(working.request_id);
        request.row_ids = line_ids;
        let old_blob = String::from_utf8(git(&["rev-parse", "HEAD:tracked.txt"]))
            .unwrap()
            .trim()
            .to_owned();
        let new_blob = String::from_utf8(git(&["hash-object", "tracked.txt"]))
            .unwrap()
            .trim()
            .to_owned();
        exact_cases.push((
            request,
            NativePatchExportScope::Lines,
            format!(
                "diff --git a/tracked.txt b/tracked.txt\nindex {old_blob}..{new_blob} 100644\n--- a/tracked.txt\n+++ b/tracked.txt\n@@ -1,1 +1,1 @@\n-base\n+working change\n"
            )
            .into_bytes(),
        ));
        for (side, path, scope, expected) in [
            (
                NativePatchSide::Unstaged,
                b"tracked.txt".to_vec(),
                NativePatchExportScope::SelectedFilesUnstaged,
                git(&["diff", "--", "tracked.txt"]),
            ),
            (
                NativePatchSide::Staged,
                b"staged.txt".to_vec(),
                NativePatchExportScope::SelectedFilesStaged,
                git(&["diff", "--cached", "--", "staged.txt"]),
            ),
        ] {
            let mut request = patch_request(&output);
            request.selected_side = Some(side);
            request.selected_paths = vec![path];
            exact_cases.push((request, scope, expected));
        }
        for (side, scope, expected) in [
            (
                NativePatchSide::Unstaged,
                NativePatchExportScope::Unstaged,
                git(&["diff"]),
            ),
            (
                NativePatchSide::Staged,
                NativePatchExportScope::Staged,
                git(&["diff", "--cached"]),
            ),
        ] {
            let mut request = patch_request(&output);
            request.focused_side = Some(side);
            exact_cases.push((request, scope, expected));
        }
        let mut request = patch_request(&output);
        request.comparison_old = Some(root.clone());
        request.comparison_new = Some(newest.clone());
        exact_cases.push((
            request,
            NativePatchExportScope::Compare,
            git(&["diff", &root, &newest]),
        ));
        let mut request = patch_request(&output);
        request.commit = Some(middle.clone());
        exact_cases.push((
            request,
            NativePatchExportScope::Commit,
            git(&["format-patch", "-1", "--stdout", &middle]),
        ));
        // A diff limited to one file exports that file only.
        let mut request = patch_request(&output);
        request.comparison_old = Some(root.clone());
        request.comparison_new = Some(newest.clone());
        request.history_paths = vec![b"other.txt".to_vec()];
        let limited = git(&["diff", &root, &newest, "--", "other.txt"]);
        assert_ne!(limited, git(&["diff", &root, &newest]));
        exact_cases.push((request, NativePatchExportScope::Compare, limited));
        let mut request = patch_request(&output);
        request.commit = Some(middle.clone());
        request.history_paths = vec![b"other.txt".to_vec()];
        let preview =
            repository_session_patch_export_preview(session.session_id, 950, request.clone())
                .preview
                .unwrap();
        assert_eq!(
            preview.filename,
            format!("0001-{}-other.txt.patch", &middle[..8])
        );
        exact_cases.push((
            request,
            NativePatchExportScope::Commit,
            git(&["format-patch", "-1", "--stdout", &middle, "--", "other.txt"]),
        ));
        let mut request = patch_request(&output);
        request.commit = Some(middle.clone());
        request.history_paths = vec![b"../outside".to_vec()];
        assert_eq!(
            repository_session_patch_export_preview(session.session_id, 950, request)
                .failure
                .unwrap()
                .kind,
            NativeRepositoryFailureKind::InvalidOptions
        );
        let mut request = patch_request(&output);
        request.range_commits = vec![root.clone(), middle.clone(), newest.clone()];
        exact_cases.push((
            request,
            NativePatchExportScope::Range,
            git(&[
                "format-patch",
                "--stdout",
                "--first-parent",
                "--root",
                &newest,
            ]),
        ));
        let mut request = patch_request(&output);
        request.workspace_default = true;
        exact_cases.push((
            request,
            NativePatchExportScope::Head,
            git(&["diff", "HEAD"]),
        ));
        for (index, (mut request, expected_scope, expected_bytes)) in
            exact_cases.into_iter().enumerate()
        {
            let directory = output.join(format!("exact-{index}"));
            fs::create_dir(&directory).unwrap();
            request.destination_directory = directory.to_string_lossy().into_owned();
            let preview = repository_session_patch_export_preview(session.session_id, 950, request)
                .preview
                .unwrap();
            assert_eq!(preview.scope, expected_scope);
            let written = repository_session_patch_export_execute(
                session.session_id,
                950,
                preview.token.unwrap(),
            );
            assert_eq!(written.state, NativePatchExportExecutionState::Completed);
            assert_eq!(
                fs::read(written.destination.unwrap()).unwrap(),
                expected_bytes
            );
        }

        let head_preview =
            repository_session_patch_export_preview(session.session_id, 950, head.clone())
                .preview
                .unwrap();
        let execution = repository_session_patch_export_execute(
            session.session_id,
            950,
            head_preview.token.unwrap(),
        );
        assert_eq!(execution.state, NativePatchExportExecutionState::Completed);
        let destination = PathBuf::from(execution.destination.unwrap());
        assert!(!fs::read(&destination).unwrap().is_empty());
        let existing = fs::read(&destination).unwrap();
        let blocked =
            repository_session_patch_export_preview(session.session_id, 950, head.clone())
                .preview
                .unwrap();
        assert!(blocked.requires_overwrite);
        assert!(blocked.token.is_none());
        assert_eq!(fs::read(&destination).unwrap(), existing);
        head.overwrite = true;
        let overwrite = repository_session_patch_export_preview(session.session_id, 950, head)
            .preview
            .unwrap();
        fs::write(&destination, b"raced destination\n").unwrap();
        assert_eq!(
            repository_session_patch_export_execute(
                session.session_id,
                950,
                overwrite.token.unwrap(),
            )
            .state,
            NativePatchExportExecutionState::Stale
        );
        assert_eq!(fs::read(&destination).unwrap(), b"raced destination\n");
        assert!(fs::read_dir(&output).unwrap().all(|entry| !entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".gitlama-patch-")));

        // A patch built for another computer: the same bytes, read in pages and saved there.
        let mut built = patch_request(&output);
        built.commit = Some(middle.clone());
        let content = repository_session_patch_export_content(session.session_id, 950, built)
            .content
            .unwrap();
        assert_eq!(content.format, NativePatchFormat::FormatPatch);
        assert_eq!(content.first.len() as u64, content.total_bytes);
        let past_end = repository_session_patch_export_content_page(
            session.session_id,
            950,
            content.token,
            content.total_bytes,
        );
        assert!(past_end.bytes.is_empty() && past_end.failure.is_none());
        assert!(repository_session_patch_export_content_page(
            session.session_id,
            950,
            content.token,
            content.total_bytes + 1,
        )
        .failure
        .is_some());
        let saved_directory = fixture.0.join("saved-elsewhere");
        fs::create_dir(&saved_directory).unwrap();
        let directory = saved_directory.to_string_lossy().into_owned();
        for unsafe_name in ["", "..", "a/b.patch", "a\\b.patch"] {
            assert!(patch_export_save_preview(
                directory.clone(),
                unsafe_name.into(),
                content.first.clone(),
                false,
            )
            .failure
            .is_some());
        }
        let save = patch_export_save_preview(
            directory.clone(),
            content.filename.clone(),
            content.first.clone(),
            false,
        );
        assert!(!save.requires_overwrite);
        let written = patch_export_save_execute(save.token.unwrap());
        assert_eq!(written.state, NativePatchExportExecutionState::Completed);
        let saved = saved_directory.join(&content.filename);
        assert_eq!(fs::read(&saved).unwrap(), content.first);
        // An existing file needs overwrite, and one that changes after the preview is kept.
        let again = patch_export_save_preview(
            directory.clone(),
            content.filename.clone(),
            content.first.clone(),
            false,
        );
        assert!(again.requires_overwrite && again.token.is_none());
        let overwrite = patch_export_save_preview(
            directory,
            content.filename.clone(),
            content.first.clone(),
            true,
        );
        fs::write(&saved, b"changed meanwhile\n").unwrap();
        assert_eq!(
            patch_export_save_execute(overwrite.token.unwrap()).state,
            NativePatchExportExecutionState::Stale
        );
        assert_eq!(fs::read(&saved).unwrap(), b"changed meanwhile\n");
        assert!(repository_session_close(session.session_id, 950).accepted);
    }

    #[test]
    fn patch_apply_checks_drift_before_applying() {
        let source = GitFixture::new();
        fs::write(source.0.join("tracked.txt"), b"base\n").unwrap();
        fs::write(source.0.join("binary.dat"), [0, 1, 2, 3, 0, 4]).unwrap();
        for index in 0..5 {
            fs::write(source.0.join(format!("multi-{index}.txt")), b"base\n").unwrap();
        }
        let source_git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&source.0)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", source.0.join("empty-config"))
                .env("GIT_AUTHOR_NAME", "GitLama Test")
                .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
                .env("GIT_COMMITTER_NAME", "GitLama Test")
                .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
                .output()
                .unwrap();
            assert!(output.status.success());
            output.stdout
        };
        source_git(&["add", "."]);
        source_git(&["commit", "-qm", "base"]);
        fs::write(source.0.join("tracked.txt"), b"patched\n").unwrap();
        let patch = source.0.join("change.patch");
        fs::write(&patch, source_git(&["diff", "--binary"])).unwrap();

        let target = GitFixture::new();
        fs::write(target.0.join("tracked.txt"), b"base\n").unwrap();
        fs::write(target.0.join("binary.dat"), [0, 1, 2, 3, 0, 4]).unwrap();
        for index in 0..5 {
            fs::write(target.0.join(format!("multi-{index}.txt")), b"base\n").unwrap();
        }
        let target_git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&target.0)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", target.0.join("empty-config"))
                .env("GIT_AUTHOR_NAME", "GitLama Test")
                .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
                .env("GIT_COMMITTER_NAME", "GitLama Test")
                .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
                .output()
                .unwrap();
            assert!(output.status.success());
            output.stdout
        };
        target_git(&["add", "."]);
        target_git(&["commit", "-qm", "base"]);
        let session = repository_session_open_with_options(
            target.0.clone(),
            951,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let preview = repository_session_patch_apply_preview(
            session.session_id,
            951,
            patch.to_string_lossy().into_owned(),
        )
        .preview
        .unwrap();
        assert_eq!(preview.paths, [b"tracked.txt".to_vec()]);
        assert!(!preview.binary);
        fs::write(target.0.join("tracked.txt"), b"external\n").unwrap();
        assert_eq!(
            repository_session_patch_apply_execute(session.session_id, 951, preview.token).state,
            NativePatchApplyExecutionState::Stale
        );
        assert_eq!(
            fs::read(target.0.join("tracked.txt")).unwrap(),
            b"external\n"
        );

        fs::write(target.0.join("tracked.txt"), b"base\n").unwrap();
        let preview = repository_session_patch_apply_preview(
            session.session_id,
            951,
            patch.to_string_lossy().into_owned(),
        )
        .preview
        .unwrap();
        let applied =
            repository_session_patch_apply_execute(session.session_id, 951, preview.token);
        assert_eq!(applied.state, NativePatchApplyExecutionState::Completed);
        assert_eq!(
            fs::read(target.0.join("tracked.txt")).unwrap(),
            b"patched\n"
        );
        restore_tracked_files(&target.0);
        assert_eq!(fs::read(target.0.join("tracked.txt")).unwrap(), b"base\n");

        let original_patch = fs::read(&patch).unwrap();
        let raced = repository_session_patch_apply_preview(
            session.session_id,
            951,
            patch.to_string_lossy().into_owned(),
        )
        .preview
        .unwrap();
        fs::write(&patch, b"changed after preview\n").unwrap();
        assert_eq!(
            repository_session_patch_apply_execute(session.session_id, 951, raced.token).state,
            NativePatchApplyExecutionState::Stale
        );
        assert_eq!(fs::read(target.0.join("tracked.txt")).unwrap(), b"base\n");
        fs::write(&patch, &original_patch).unwrap();

        fs::write(source.0.join("binary.dat"), [0, 9, 8, 7, 0, 6, 5]).unwrap();
        let binary_patch = source.0.join("binary.patch");
        fs::write(
            &binary_patch,
            source_git(&["diff", "--binary", "--", "binary.dat"]),
        )
        .unwrap();
        let binary = repository_session_patch_apply_preview(
            session.session_id,
            951,
            binary_patch.to_string_lossy().into_owned(),
        )
        .preview
        .unwrap();
        assert_eq!(binary.paths, [b"binary.dat".to_vec()]);
        assert!(binary.binary);
        assert_eq!(
            repository_session_patch_apply_execute(session.session_id, 951, binary.token).state,
            NativePatchApplyExecutionState::Completed
        );
        assert_eq!(
            fs::read(target.0.join("binary.dat")).unwrap(),
            [0, 9, 8, 7, 0, 6, 5]
        );
        restore_tracked_files(&target.0);
        assert_eq!(
            fs::read(target.0.join("binary.dat")).unwrap(),
            [0, 1, 2, 3, 0, 4]
        );

        for index in 0..5 {
            fs::write(
                source.0.join(format!("multi-{index}.txt")),
                format!("changed {index}\n"),
            )
            .unwrap();
        }
        let multi_patch = source.0.join("multi.patch");
        fs::write(
            &multi_patch,
            source_git(&[
                "diff",
                "--",
                "multi-0.txt",
                "multi-1.txt",
                "multi-2.txt",
                "multi-3.txt",
                "multi-4.txt",
            ]),
        )
        .unwrap();
        let multi = repository_session_patch_apply_preview(
            session.session_id,
            951,
            multi_patch.to_string_lossy().into_owned(),
        )
        .preview
        .unwrap();
        assert_eq!(multi.paths.len(), 5);
        assert_eq!(
            repository_session_patch_apply_execute(session.session_id, 951, multi.token).state,
            NativePatchApplyExecutionState::Completed
        );
        restore_tracked_files(&target.0);
        for index in 0..5 {
            assert_eq!(
                fs::read(target.0.join(format!("multi-{index}.txt"))).unwrap(),
                b"base\n"
            );
        }

        fs::write(&patch, b"diff --git a/../escape b/../escape\n--- a/../escape\n+++ b/../escape\n@@ -0,0 +1 @@\n+bad\n").unwrap();
        assert!(matches!(
            repository_session_patch_apply_preview(
                session.session_id,
                951,
                patch.to_string_lossy().into_owned(),
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::InvalidOptions
                | NativeRepositoryFailureKind::InvalidOutput
        ));
        assert!(!target.0.parent().unwrap().join("escape").exists());
        assert!(repository_session_close(session.session_id, 951).accepted);
    }
}
