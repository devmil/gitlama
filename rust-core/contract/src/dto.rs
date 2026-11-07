//! The repository session's bridge result and request types. The FRB facade (`api.rs`) and the
//! remote wire adapter both carry them; application use cases produce them. They hold no logic.
use crate::activity::{NativeActivityPage, NativeActivityProgress};

// The bridge types the family modules define, so both adapters name every type here.
pub use crate::advanced_rebase::{
    NativeAdvancedRebaseFailure, NativeAdvancedRebaseFailureKind, NativeFixupEvidence,
    NativeFixupSuggestionResult, NativeFixupSuggestionState, NativeRestackExecutionResult,
    NativeRestackExecutionState, NativeRestackPlanResult, NativeRestackStep,
};
pub use crate::archive::{
    NativeArchiveFailure, NativeArchiveFailureKind, NativeArchivePage, NativeArchiveStartResult,
    NativeArchiveState, NativeArchiveStatus,
};
pub use crate::clone::{
    NativeCloneCreateResult, NativeCloneRunResult, NativeCloneSnapshot, NativeCloneSnapshotResult,
    NativeCloneState,
};
pub use crate::conflict::{
    NativeConflictContinuationResult, NativeConflictContinuationState, NativeConflictFailure,
    NativeConflictFailureKind, NativeConflictFile, NativeConflictFileKind,
    NativeConflictOperationKind, NativeConflictRegion, NativeConflictRegionChoice,
    NativeConflictSequencerAction, NativeConflictSide, NativeConflictSideChoice,
    NativeConflictSnapshot, NativeConflictSnapshotResult,
};
pub use crate::diff::{
    NativeDiffLayout, NativeDiffPage, NativeDiffRow, NativeDiffRowKind, NativeDiffSyntaxOrigin,
    NativeDiffSyntaxPage, NativeDiffSyntaxRequest, NativeDiffSyntaxResult, NativeDiffSyntaxRow,
    NativeSyntaxSideState, NativeSyntaxSpan, NativeSyntaxTokenKind, NativeTextSyntaxLine,
    NativeTextSyntaxPage, NativeTextSyntaxRequest, NativeTextSyntaxResult,
};
pub use crate::diff_renderer::NativeDiffRendererSettings;
pub use crate::diff_renderer::{
    NativeDiffRendererDefinition, NativeDiffRendererFailure, NativeDiffRendererFailureKind,
    NativeDiffRendererPreview, NativeDiffRendererPreviewResult, NativeDiffRendererResult,
    NativeDiffRendererState,
};
pub use crate::domain::path_identity::{NativePathIdentity, NativePathPlatform};
pub use crate::extensions::{
    NativeExtensionFailure, NativeExtensionFailureKind, NativeExtensionInventory,
    NativeExtensionInventoryResult, NativeExtensionMutationKind, NativeExtensionMutationRequest,
    NativeExtensionMutationResult, NativeExtensionMutationState, NativeLfsEntry,
    NativeLfsPathState, NativeLfsPointer, NativeLfsPointerResult, NativeSubmoduleEnterResult,
    NativeSubmoduleEntry, NativeSubmoduleState, NativeWorktreeEntry,
};
pub use crate::history_operation::{
    NativeConflictPredictionKind, NativeConflictPredictionResult,
    NativeConflictPredictionStartResult, NativeHistoryMergeMode,
    NativeHistoryMutationExecutionResult, NativeHistoryMutationExecutionState,
    NativeHistoryMutationFailure, NativeHistoryMutationFailureKind, NativeHistoryMutationKind,
    NativeHistoryMutationPreview, NativeHistoryMutationPreviewResult, NativeHistoryMutationRequest,
};
pub use crate::hosting_settings::{NativeHostingBindingSettings, NativeHostingConnectionSettings};
pub use crate::integrations::NativeIntegrationSettings;
pub use crate::integrations::{
    NativeIntegrationCandidate, NativeIntegrationDefinition, NativeIntegrationDiscoveryResult,
    NativeIntegrationExecution, NativeIntegrationExecutionResult, NativeIntegrationExecutionState,
    NativeIntegrationFailure, NativeIntegrationFailureKind, NativeIntegrationKind,
    NativeIntegrationLaunchMode, NativeIntegrationPreview, NativeIntegrationPreviewResult,
    NativeIntegrationRequest, NativeIntegrationVariables,
};
pub use crate::named_snapshot::{
    NativeNamedSnapshot, NativeNamedSnapshotExecutionResult, NativeNamedSnapshotExecutionState,
    NativeNamedSnapshotFailure, NativeNamedSnapshotFailureKind, NativeNamedSnapshotListResult,
    NativeNamedSnapshotRestorePreview, NativeNamedSnapshotRestorePreviewResult,
    NativeNamedSnapshotState,
};
pub use crate::power_tools::{
    NativeBisectAction, NativeBisectExecutionResult, NativeBisectExecutionState, NativeBisectMark,
    NativeBisectPreview, NativeBisectPreviewResult, NativeBisectState, NativeBisectStateResult,
    NativeBisectTimelineEntry, NativeDiffContentMatch, NativeDiffContentSearchResult,
    NativeDiffSearchOptions, NativeDiffSearchScope, NativePowerFailure, NativePowerFailureKind,
    NativePowerJobStartResult, NativePowerJobState, NativeRepositoryStatisticsResult,
    NativeSearchCompleteness,
};
pub use crate::rebase_operation::{
    NativeRebaseAction, NativeRebaseExecutionResult, NativeRebaseExecutionState,
    NativeRebaseFailure, NativeRebaseFailureKind, NativeRebaseInstruction, NativeRebasePlanResult,
    NativeRebasePreviewResult,
};
pub use crate::recovery::{
    NativePreviousShutdown, NativeRecoveryCommandResult, NativeRecoveryFailure,
    NativeRecoveryFailureKind, NativeRecoveryPathResult, NativeRecoveryStartResult,
    NativeSequencerInspectionResult, NativeSequencerKind, NativeSequencerState,
};
pub use crate::stash::{
    NativeStashCommandPreview, NativeStashExecutionResult, NativeStashExecutionState,
    NativeStashFailure, NativeStashFailureKind, NativeStashKind, NativeStashPreview,
    NativeStashPreviewResult, NativeStashRequest,
};
pub use crate::storage::{
    NativeAppearanceSettings, NativeCommitDraft, NativeSettingsDocument, NativeSettingsFailure,
    NativeSettingsFailureKind, NativeSettingsLoadResult, NativeSettingsLoadState,
    NativeSettingsPathResult, NativeSettingsSaveResult, NativeWorktreeSettings,
};
pub use crate::transfer::{
    NativePullStrategy, NativeTransferDiagnosis, NativeTransferDiagnosisKind,
    NativeTransferExecutionResult, NativeTransferExecutionState, NativeTransferFailure,
    NativeTransferFailureKind, NativeTransferKind, NativeTransferPreview,
    NativeTransferPreviewResult, NativeTransferRequest,
};

pub use crate::remote_pending::{
    NativeRemotePendingLoadResult, NativeRemotePendingLoadState, NativeRemotePendingOperation,
    NativeRemotePendingSaveResult,
};

pub use crate::view_cache::{
    NativeViewCacheCommandResult, NativeViewCacheFailure, NativeViewCacheFailureKind,
    NativeViewCacheReadResult,
};

/// Compatibility handshake, independent of the installed Git executable.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CoreInfo {
    pub protocol_version: u32,
    pub minimum_git_major: u32,
    pub minimum_git_minor: u32,
    pub minimum_git_patch: u32,
}

/// The release this library was built as, from the canonical `VERSION` file.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeApplicationRelease {
    pub version: String,
    pub build: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeRepositoryPhase {
    Unloaded,
    Loading,
    Ready,
    Failed,
    Closed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeRepositoryFailureKind {
    Canceled,
    MissingObject,
    TooLarge,
    InvalidOutput,
    MissingGit,
    Unsupported,
    InvalidOptions,
    Discovery,
    Read,
    Watch,
    Closed,
    Capacity,
    InvalidGeneration,
    UnknownSession,
    StaleGeneration,
    RetiredSession,
    ExistingRepository,
    DestinationNotEmpty,
    DestinationNotDirectory,
    InitializationFailed,
    TimedOut,
    PathNotFound,
    PermissionDenied,
    NotRepository,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryFailure {
    pub kind: NativeRepositoryFailureKind,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositorySnapshot {
    pub revision: u64,
    pub phase: NativeRepositoryPhase,
    pub failure: Option<NativeRepositoryFailure>,
    pub watch_failure: Option<NativeRepositoryFailure>,
    pub identity: Option<NativeRepositoryIdentity>,
    pub status: Option<NativeRepositoryStatus>,
    pub status_failure: Option<NativeRepositoryFailure>,
    pub refs_failure: Option<NativeRepositoryFailure>,
    pub ref_counts: NativeRepositoryRefCounts,
    pub refs: NativeRepositoryRefs,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryRefs {
    pub branches: Vec<NativeRepositoryReference>,
    pub remotes: Vec<NativeRepositoryRemote>,
    pub tags: Vec<NativeRepositoryReference>,
    pub stashes: Vec<NativeRepositoryStash>,
    pub truncated: bool,
}

// A derived impl would carry no `flutter_rust_bridge:ignore` marker.
#[allow(clippy::derivable_impls)]
impl Default for NativeRepositoryRefs {
    // flutter_rust_bridge reads this crate as a third-party input and would expose a Dart
    // `default_()` for every `Default` impl; the bridge types carry no functions.
    /// flutter_rust_bridge:ignore
    fn default() -> Self {
        Self {
            branches: Default::default(),
            remotes: Default::default(),
            tags: Default::default(),
            stashes: Default::default(),
            truncated: Default::default(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryReference {
    /// The name within its section: `main`, `v1.0`, or `main` of a remote.
    pub name: Vec<u8>,
    /// The full reference name, such as `refs/remotes/origin/main`, so the
    /// client never rebuilds it from the short name.
    pub full_name: Vec<u8>,
    pub target: String,
    pub head: bool,
    pub published: bool,
    pub upstream: Option<Vec<u8>>,
    pub ahead: u64,
    pub behind: u64,
    pub upstream_gone: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryRemote {
    pub name: Vec<u8>,
    pub display_url: Vec<u8>,
    pub branches: Vec<NativeRepositoryReference>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryStash {
    pub selector: Vec<u8>,
    pub object_id: String,
    pub subject: Vec<u8>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeWorkingTreeState {
    Clean,
    Dirty,
    Conflicted,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeChangeKind {
    Unmodified,
    Modified,
    TypeChanged,
    Added,
    Deleted,
    Renamed,
    Copied,
    UpdatedButUnmerged,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeStatusEntryKind {
    Ordinary,
    Rename,
    Unmerged,
    Untracked,
    Ignored,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeOperationKind {
    Merge,
    Rebase,
    CherryPick,
    Revert,
    Bisect,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeOperationState {
    pub kind: NativeOperationKind,
    pub current: Option<u32>,
    pub total: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeStatusEntry {
    pub kind: NativeStatusEntryKind,
    pub path: NativePathIdentity,
    pub source: Option<NativePathIdentity>,
    pub index: NativeChangeKind,
    pub worktree: NativeChangeKind,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryStatus {
    pub working_tree: NativeWorkingTreeState,
    pub branch_name: Option<Vec<u8>>,
    pub head_object_id: Option<String>,
    pub upstream: Option<Vec<u8>>,
    pub ahead: u64,
    pub behind: u64,
    pub entries: Vec<NativeStatusEntry>,
    pub total_entries: u64,
    pub entries_truncated: bool,
    pub operations: Vec<NativeOperationState>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryRefCounts {
    pub branches: u64,
    pub remotes: u64,
    pub tags: u64,
    pub stashes: u64,
    pub worktrees: u64,
}

// A derived impl would carry no `flutter_rust_bridge:ignore` marker.
#[allow(clippy::derivable_impls)]
impl Default for NativeRepositoryRefCounts {
    // flutter_rust_bridge reads this crate as a third-party input and would expose a Dart
    // `default_()` for every `Default` impl; the bridge types carry no functions.
    /// flutter_rust_bridge:ignore
    fn default() -> Self {
        Self {
            branches: Default::default(),
            remotes: Default::default(),
            tags: Default::default(),
            stashes: Default::default(),
            worktrees: Default::default(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeRepositoryKind {
    Worktree,
    Bare,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeHeadKind {
    Attached,
    Detached,
    Unborn,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryIdentity {
    pub common_git_dir: NativePathIdentity,
    pub worktree_root: NativePathIdentity,
    pub git_dir: NativePathIdentity,
    pub kind: NativeRepositoryKind,
    pub head_kind: NativeHeadKind,
    pub head_reference: Option<Vec<u8>>,
    pub head_object_id: Option<String>,
    pub git_major: u32,
    pub git_minor: u32,
    pub git_patch: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeRepositoryEventKind {
    Snapshot,
    Resynchronize,
    ReadCompleted,
    WatchOverflow,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryEvent {
    pub kind: NativeRepositoryEventKind,
    pub snapshot: Option<NativeRepositorySnapshot>,
    pub read_id: Option<u64>,
    pub cache_hit: bool,
    pub watch_overflow_revision: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositorySession {
    pub session_id: u64,
    pub generation: u64,
    pub snapshot: NativeRepositorySnapshot,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryOpenResult {
    pub session: Option<NativeRepositorySession>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryEventsResult {
    pub events: Vec<NativeRepositoryEvent>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryCommandResult {
    pub accepted: bool,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryActivityResult {
    pub page: Option<NativeActivityPage>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeIndexLockFailureKind {
    Missing,
    Changed,
    UnsafeFile,
    Io,
    ActiveOperation,
    RepositoryNotReady,
    InvalidToken,
    StaleGeneration,
    UnknownSession,
    RetiredSession,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeIndexLockInspectionResult {
    pub present: bool,
    pub token: Option<u64>,
    pub size_bytes: Option<u64>,
    pub failure: Option<NativeIndexLockFailureKind>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeIndexLockRemovalResult {
    pub removed: bool,
    pub failure: Option<NativeIndexLockFailureKind>,
}

/// One Git lock file (`*.lock`) found in the repository's Git directories.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryLock {
    /// Removes this lock while it is the inspected file.
    pub token: u64,
    /// The path relative to its Git directory, such as `refs/heads/main.lock`.
    pub path: String,
    /// Whether it lives in the worktree's own Git directory rather than the shared one.
    pub worktree_scoped: bool,
    pub size_bytes: u64,
    /// Seconds since Git wrote the lock, when the filesystem reports it.
    pub age_seconds: Option<u64>,
}

/// Git's optional status accelerators for one repository and how long its last status scan took.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeStatusAcceleration {
    /// `core.untrackedCache` is enabled.
    pub untracked_cache: bool,
    /// `core.fsmonitor` names the built-in monitor or a hook.
    pub fsmonitor: bool,
    /// This platform and Git version provide the built-in monitor.
    pub fsmonitor_available: bool,
    /// The duration of the last completed status scan, when one was recorded.
    pub last_scan_millis: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeStatusAccelerationResult {
    pub acceleration: Option<NativeStatusAcceleration>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRepositoryLockInspectionResult {
    pub locks: Vec<NativeRepositoryLock>,
    /// The inspection stopped at its bound; more locks may exist.
    pub truncated: bool,
    pub failure: Option<NativeIndexLockFailureKind>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeOperationCenterState {
    Running,
    Attention,
    Warning,
    Succeeded,
    Failed,
    Canceled,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeOperationCenterOrigin {
    User,
    Background,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeOperationCenterAction {
    Refresh,
    Initialize,
    Clone,
    Fetch,
    Pull,
    Push,
    Other,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeOperationCenterEntry {
    pub activity_id: Option<u64>,
    pub session_id: Option<u64>,
    pub clone_attempt_id: Option<u64>,
    pub generation: u64,
    pub state: NativeOperationCenterState,
    pub origin: NativeOperationCenterOrigin,
    pub action: NativeOperationCenterAction,
    pub started_at_unix_ms: u64,
    pub finished_at_unix_ms: Option<u64>,
    pub progress: Option<NativeActivityProgress>,
    pub can_cancel: bool,
    pub can_retry: bool,
    pub has_details: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeOperationCenterSnapshot {
    pub entries: Vec<NativeOperationCenterEntry>,
    pub running_count: u32,
    pub failed_count: u32,
    pub warning_count: u32,
    pub attention_count: u32,
    pub truncated: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeOperationCenterResult {
    pub snapshot: Option<NativeOperationCenterSnapshot>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeHistoryNodeShape {
    Commit,
    Merge,
    Boundary,
    Graft,
    Replace,
    Wip,
    WipConflict,
    /// A stash commit: its index and untracked parents are storage, not history.
    Stash,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeHistorySegmentKind {
    Straight,
    Join,
    Merge,
    Octopus,
    Boundary,
    Missing,
    CollapsedMerge,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeHistoryRow {
    pub object_id: String,
    pub parents: Vec<String>,
    pub parent_count: u32,
    pub parents_truncated: bool,
    pub refs: Vec<Vec<u8>>,
    pub ref_count: u32,
    pub refs_truncated: bool,
    pub lane: u32,
    pub shape: NativeHistoryNodeShape,
    pub metadata_available: bool,
    pub subject: Vec<u8>,
    pub author: Vec<u8>,
    pub avatar_hash: String,
    pub author_time: i64,
    pub metadata_failure: Option<NativeHistoryMetadataFailure>,
    pub selected: bool,
    pub current: bool,
    pub lit: bool,
    /// The commit belongs to one side of a two-commit comparison only.
    pub compared: bool,
    pub wip_changed_files: u32,
    pub wip_staged_files: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeHistoryMetadataFailure {
    Missing,
    ObjectTooLarge,
    AuthorTooLarge,
    SubjectTooLarge,
    MalformedCommit,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeHistoryMetadataRow {
    pub object_id: String,
    pub subject: Vec<u8>,
    pub author: Vec<u8>,
    pub avatar_hash: String,
    pub author_time: i64,
    pub failure: Option<NativeHistoryMetadataFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeHistoryMetadataResult {
    pub request_id: u64,
    pub rows: Vec<NativeHistoryMetadataRow>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeHistorySegment {
    pub from_object_id: String,
    pub to_object_id: String,
    pub parent_ordinal: u32,
    /// Absolute endpoints in the current visible topology, independent of loaded pages.
    pub from_row: u64,
    pub to_row: Option<u64>,
    pub lit: bool,
    pub from_lane: u32,
    pub to_lane: u32,
    pub kind: NativeHistorySegmentKind,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeHistoryPage {
    pub request_id: u64,
    pub topology_complete: bool,
    pub total_rows: u64,
    pub offset: u64,
    pub rows: Vec<NativeHistoryRow>,
    pub segments: Vec<NativeHistorySegment>,
    pub lane_count: u32,
    pub payload_bytes: u64,
    pub lighting_active: bool,
    pub current_object_id: Option<String>,
    pub selected_object_ids: Vec<String>,
    pub focused_object_id: Option<String>,
    pub comparison_old_object_id: Option<String>,
    pub comparison_new_object_id: Option<String>,
    pub reveal_sequence: u64,
    pub reveal_object_id: Option<String>,
    pub reveal_index: Option<u64>,
    pub query_sequence: u64,
    pub query_active: bool,
    pub accepted_query: String,
    /// The branch filter this view shows, sorted; empty shows every reference.
    pub branch_filter: Vec<Vec<u8>>,
    pub selected_filtered_out: bool,
    pub collapsed_commits: u64,
    /// Whether commits only references outside branches, remote-tracking branches, tags
    /// and the stash reach are part of this history.
    pub other_refs: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeHistoryResult {
    pub page: Option<NativeHistoryPage>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeHistorySelectionOptions {
    pub object_id: Option<String>,
    pub toggle: bool,
    pub reveal: bool,
    pub focus: bool,
    pub offset: u64,
    pub maximum_rows: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeHistoryQueryOptions {
    pub text: String,
    pub search_hash: bool,
    pub search_message: bool,
    pub search_author: bool,
    pub search_path: bool,
    pub offset: u64,
    pub maximum_rows: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeDiffResult {
    pub page: Option<NativeDiffPage>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeStagingSide {
    Unstaged,
    Staged,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeStagingScope {
    All,
    Files,
    Rows,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeWorkingDiffOptions {
    pub side: NativeStagingSide,
    pub old_path: Option<Vec<u8>>,
    pub new_path: Option<Vec<u8>>,
    pub context_lines: u32,
    pub whitespace: NativeDiffWhitespace,
    pub layout: NativeDiffLayout,
    pub maximum_rows: u32,
    /// Diffs files Git considers binary as text. Row staging is unavailable for such a diff.
    pub force_text: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeStagingRequest {
    /// Zero prepares whole-file intent from fresh status under the mutation lease.
    /// Row actions always require an accepted diff request.
    pub request_id: u64,
    pub side: NativeStagingSide,
    pub scope: NativeStagingScope,
    pub paths: Vec<Vec<u8>>,
    pub row_ids: Vec<String>,
}

/// Progress of a session's current staging transaction. Idle also means no active write.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeStagingPhase {
    Idle,
    Waiting,
    Preparing,
    Updating,
    Refreshing,
}

// Keep the bridge contract free of generated Default methods.
#[allow(clippy::derivable_impls)]
impl Default for NativeStagingPhase {
    /// flutter_rust_bridge:ignore
    fn default() -> Self {
        Self::Idle
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeStagingExecutionState {
    Completed,
    Stale,
    Failed,
    ReconciledWithWarning,
    /// Git may have changed the index; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeStagingExecutionResult {
    pub state: NativeStagingExecutionState,
    pub failure: Option<NativeRepositoryFailure>,
    pub diagnostic: Option<NativeStagingDiagnostic>,
}

/// Safe support information. Never contains command output, paths or repository content.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeStagingFailureCode {
    InvalidRequest,
    RepositoryUnavailable,
    StatusRead,
    IndexRead,
    ContentRead,
    ContentChanged,
    IndexPrepare,
    IndexLocked,
    IndexChanged,
    IndexUnsafe,
    IndexInstall,
    GitLaunch,
    GitTimeout,
    GitFailed,
    PatchUnavailable,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeStagingDiagnostic {
    pub code: NativeStagingFailureCode,
    pub activity_id: Option<u64>,
    pub exit_code: Option<i32>,
    pub git_version: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeDiscardKind {
    Discard,
    Clean,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeDiscardScope {
    Files,
    Rows,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeDiscardRequest {
    pub kind: NativeDiscardKind,
    pub scope: NativeDiscardScope,
    pub working_diff_request_id: Option<u64>,
    pub paths: Vec<Vec<u8>>,
    pub row_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeDiscardPreview {
    pub token: u64,
    pub kind: NativeDiscardKind,
    pub file_count: u64,
    pub arguments: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeDiscardPreviewResult {
    pub preview: Option<NativeDiscardPreview>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeDiscardExecutionState {
    Completed,
    Stale,
    Failed,
    ReconciledWithWarning,
    /// Git may have changed the worktree; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeDiscardExecutionResult {
    pub state: NativeDiscardExecutionState,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativePatchSide {
    Unstaged,
    Staged,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativePatchExportScope {
    Lines,
    SelectedFilesUnstaged,
    SelectedFilesStaged,
    Unstaged,
    Staged,
    Head,
    Commit,
    Range,
    Compare,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativePatchFormat {
    UnifiedDiff,
    FormatPatch,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchExportRequest {
    pub working_diff_request_id: Option<u64>,
    pub row_ids: Vec<String>,
    pub selected_side: Option<NativePatchSide>,
    pub selected_paths: Vec<Vec<u8>>,
    pub focused_side: Option<NativePatchSide>,
    pub comparison_old: Option<String>,
    pub comparison_new: Option<String>,
    pub range_commits: Vec<String>,
    pub commit: Option<String>,
    /// Limits a comparison or commit patch to these paths.
    pub history_paths: Vec<Vec<u8>>,
    pub workspace_default: bool,
    pub destination_directory: String,
    pub overwrite: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchExportPreview {
    pub token: Option<u64>,
    pub scope: NativePatchExportScope,
    pub format: NativePatchFormat,
    pub filename: String,
    pub destination: String,
    pub byte_count: u64,
    pub requires_overwrite: bool,
}

/// A built patch kept for paging: its name and its first page.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchExportContent {
    pub token: u64,
    pub scope: NativePatchExportScope,
    pub format: NativePatchFormat,
    pub filename: String,
    pub total_bytes: u64,
    pub first: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchExportContentResult {
    pub content: Option<NativePatchExportContent>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchExportContentPage {
    pub bytes: Vec<u8>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchSavePreviewResult {
    pub token: Option<u64>,
    pub destination: Option<String>,
    pub requires_overwrite: bool,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchExportPreviewResult {
    pub preview: Option<NativePatchExportPreview>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativePatchExportExecutionState {
    Completed,
    Stale,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchExportExecutionResult {
    pub state: NativePatchExportExecutionState,
    pub destination: Option<String>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchApplyPreview {
    pub token: u64,
    pub paths: Vec<Vec<u8>>,
    pub binary: bool,
    pub arguments: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchApplyPreviewResult {
    pub preview: Option<NativePatchApplyPreview>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativePatchApplyExecutionState {
    Completed,
    Stale,
    Failed,
    ReconciledWithWarning,
    /// Git may have changed the worktree; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePatchApplyExecutionResult {
    pub state: NativePatchApplyExecutionState,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRecentCommitMessage {
    pub object_id: String,
    pub subject: String,
    pub description: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitTools {
    pub recent: Vec<NativeRecentCommitMessage>,
    pub template: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitToolsResult {
    pub tools: Option<NativeCommitTools>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitRequest {
    pub subject: String,
    pub description: String,
    pub coauthors: Vec<String>,
    pub author: Option<String>,
    pub amend: bool,
    pub skip_hooks: bool,
    pub signing: NativeCommitSigning,
    pub sign_off: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeCommitSigning {
    UseGitConfiguration,
    Require,
    Disable,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeCommitWarning {
    PublishedAmend,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitPreview {
    pub token: u64,
    pub warnings: Vec<NativeCommitWarning>,
    pub arguments: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitPreviewResult {
    pub preview: Option<NativeCommitPreview>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeCommitExecutionState {
    Completed,
    Stale,
    Failed,
    ReconciledWithWarning,
    /// Git may have changed the branch; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeCommitFailureKind {
    Hook,
    Signing,
    Other,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitExecutionResult {
    pub state: NativeCommitExecutionState,
    pub commit: Option<String>,
    pub failure_kind: Option<NativeCommitFailureKind>,
    pub exit_code: Option<i32>,
    pub output: Vec<String>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeDiffWhitespace {
    Preserve,
    IgnoreAll,
    IgnoreAmount,
    IgnoreEndOfLine,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitDiffOptions {
    pub commit: String,
    pub first_parent: Option<String>,
    pub old_path: Option<Vec<u8>>,
    pub new_path: Option<Vec<u8>>,
    pub context_lines: u32,
    pub whitespace: NativeDiffWhitespace,
    pub layout: NativeDiffLayout,
    pub maximum_rows: u32,
    /// Diffs files Git considers binary as text.
    pub force_text: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeDiffSearchResult {
    pub request_id: u64,
    pub matches: Vec<u32>,
    pub total_matches: u64,
    pub truncated: bool,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeDiffPositionsResult {
    pub request_id: u64,
    pub positions: Vec<u32>,
    pub total_positions: u64,
    pub truncated: bool,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeImageDiffResult {
    pub old: Option<crate::image_decoder::NativeDecodedImage>,
    pub new: Option<crate::image_decoder::NativeDecodedImage>,
    pub decode_failure: Option<crate::image_decoder::NativeImageDecodeFailureKind>,
    pub failure: Option<NativeRepositoryFailure>,
}

/// Change sides kept for reading: their sizes, or none for a side without content.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeChangeSourceResult {
    pub token: u64,
    pub old_bytes: Option<u64>,
    pub new_bytes: Option<u64>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeChangeSourcePage {
    pub bytes: Vec<u8>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeReflogAction {
    InspectCommit,
    CreateBranch,
    CreateTag,
    ResetCurrentBranch,
    CherryPick,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeReflogEntry {
    pub id: String,
    pub reference: Vec<u8>,
    pub commit: String,
    pub recorded_at_unix_seconds: i64,
    pub timezone: Vec<u8>,
    pub summary: Vec<u8>,
    pub actor_name: Vec<u8>,
    pub actor_email: Vec<u8>,
    pub actions: Vec<NativeReflogAction>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeReflogPage {
    pub entries: Vec<NativeReflogEntry>,
    pub next_offset: Option<u64>,
    pub activity_id: Option<u64>,
    pub retained_after_failure: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeReflogResult {
    pub page: NativeReflogPage,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeTreeEntryKind {
    Directory,
    File,
    Symlink,
    Submodule,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeTreeEntry {
    pub stable_id: String,
    pub path: Vec<u8>,
    pub object_id: String,
    pub kind: NativeTreeEntryKind,
    pub mode: u32,
    pub size: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeTreePage {
    pub commit: String,
    pub directory: Option<Vec<u8>>,
    pub entries: Vec<NativeTreeEntry>,
    pub next_offset: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitDetail {
    pub commit: String,
    pub tree: String,
    pub parents: Vec<String>,
    pub author: Vec<u8>,
    pub avatar_hash: String,
    pub author_time: i64,
    pub author_timezone: Vec<u8>,
    pub committer: Vec<u8>,
    pub committer_time: i64,
    pub committer_timezone: Vec<u8>,
    pub message: Vec<u8>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeFileChangeKind {
    Modified,
    Added,
    Deleted,
    Renamed,
    Copied,
    ModeChanged,
    TypeChanged,
    Binary,
    Image,
    Submodule,
    Conflict,
    Untracked,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitFile {
    pub old_mode: u32,
    pub new_mode: u32,
    pub old_object_id: Option<String>,
    pub new_object_id: Option<String>,
    pub kind: NativeFileChangeKind,
    pub similarity: Option<u32>,
    pub old_path: Vec<u8>,
    pub new_path: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitInspection {
    pub detail: NativeCommitDetail,
    pub files: Vec<NativeCommitFile>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitInspectionResult {
    pub inspection: Option<NativeCommitInspection>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitDetailsResult {
    pub details: Vec<NativeCommitDetail>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeTreeResult {
    pub page: Option<NativeTreePage>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCommitFileContentResult {
    pub bytes: Option<Vec<u8>>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePathHistoryEntry {
    pub stable_id: String,
    pub commit: String,
    pub author: Vec<u8>,
    pub author_time: i64,
    pub summary: Vec<u8>,
    pub path: Vec<u8>,
    pub old_path: Option<Vec<u8>>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePathHistoryPage {
    pub entries: Vec<NativePathHistoryEntry>,
    pub next_offset: Option<u64>,
    pub rename_hops: u64,
    pub incomplete: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePathHistoryResult {
    pub page: Option<NativePathHistoryPage>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativePathHistoryOptions {
    pub revision: Option<String>,
    pub path: Vec<u8>,
    pub directory: bool,
    pub offset: u64,
    pub maximum_rows: u32,
    pub rename_hops_before: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRangeHistoryEntry {
    pub stable_id: String,
    pub commit: String,
    pub author: Vec<u8>,
    pub author_time: i64,
    pub summary: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRangeHistoryResult {
    pub entries: Vec<NativeRangeHistoryEntry>,
    pub incomplete: bool,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeBlameRow {
    pub stable_id: String,
    pub final_line: u64,
    pub original_line: u64,
    pub content: Vec<u8>,
    pub commit: Option<String>,
    pub author: Vec<u8>,
    pub author_time: i64,
    pub summary: Vec<u8>,
    pub original_path: Vec<u8>,
    pub boundary: bool,
    pub span_first_line: u64,
    pub span_last_line: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeBlamePage {
    pub request_id: u64,
    pub revision: String,
    pub path: Vec<u8>,
    pub total_rows: u64,
    pub offset: u64,
    pub rows: Vec<NativeBlameRow>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeBlameResult {
    pub page: Option<NativeBlamePage>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeBlameOptions {
    pub revision: String,
    pub path: Vec<u8>,
    pub first_line: Option<u64>,
    pub last_line: Option<u64>,
    pub detect_moves: bool,
    pub detect_copies: bool,
    pub maximum_rows: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRestorePreview {
    pub token: u64,
    pub commit: String,
    pub path: Vec<u8>,
    pub source_bytes: Vec<u8>,
    pub current_bytes: Option<Vec<u8>>,
    pub expected_head: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRestorePreviewResult {
    pub preview: Option<NativeRestorePreview>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeRestoreState {
    Restored,
    Stale,
    Failed,
    OutcomeUncertain,
    ReconciledWithWarning,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRestoreResult {
    pub state: NativeRestoreState,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeRefMutationKind {
    CreateBranch,
    RenameBranch,
    DeleteBranch,
    CheckoutBranch,
    SetUpstream,
    UnsetUpstream,
    CreateTag,
    DeleteTag,
    AddRemote,
    EditRemote,
    RenameRemote,
    RemoveRemote,
    Reset,
    CheckoutCommit,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeRefResetMode {
    Soft,
    Mixed,
    Hard,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRefMutationRequest {
    pub kind: NativeRefMutationKind,
    pub name: Option<String>,
    pub second_name: Option<String>,
    pub target: Option<String>,
    pub message: Option<String>,
    pub url: Option<String>,
    pub force: bool,
    pub reset_mode: Option<NativeRefResetMode>,
    /// Switch to a newly created branch.
    pub checkout: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeRefMutationWarning {
    DirtyCheckout,
    DetachedHead,
    PublishedBranch,
    CheckedOutElsewhere,
    DestructiveReset,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRefMutationPreview {
    pub token: u64,
    pub kind: NativeRefMutationKind,
    pub arguments: Vec<String>,
    pub warnings: Vec<NativeRefMutationWarning>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRefMutationPreviewResult {
    pub preview: Option<NativeRefMutationPreview>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeRefMutationExecutionState {
    Completed,
    Stale,
    Failed,
    ReconciledWithWarning,
    /// Git may have changed the refs; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRefMutationExecutionResult {
    pub state: NativeRefMutationExecutionState,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeDiffSelectionPatchResult {
    pub patch: Option<Vec<u8>>,
    pub failure: Option<NativeRepositoryFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeDiffRendererInputResult {
    pub input: Option<Vec<u8>>,
    pub failure: Option<NativeDiffRendererFailure>,
}

// Transfer authentication results that clones and transfers share.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeCloneFailureKind {
    InvalidSource,
    EmbeddedCredential,
    InvalidDestination,
    DestinationOccupied,
    AttemptCapacity,
    UnknownAttempt,
    InvalidAttemptState,
    MissingGit,
    Authentication,
    CredentialBrokerUnavailable,
    HostKey,
    Git,
    TimedOut,
    Canceled,
    Discovery,
    HostKeyProbeFailed,
    HostKeyChallengeExpired,
    HostKeyWriteFailed,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeCloneFailure {
    pub kind: NativeCloneFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostKeyChallenge {
    pub challenge_id: u64,
    pub host: String,
    pub port: u16,
    pub algorithm: String,
    pub fingerprint: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostKeyResult {
    pub challenge: Option<NativeHostKeyChallenge>,
    pub failure: Option<NativeCloneFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeCloneCommandResult {
    pub accepted: bool,
    pub failure: Option<NativeCloneFailure>,
}
