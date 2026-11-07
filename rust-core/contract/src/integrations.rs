//! The bridge types of `integrations`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.
use crate::domain::path_identity::NativePathIdentity;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeIntegrationSettings {
    pub id: String,
    pub kind: String,
    pub executable: NativePathIdentity,
    pub arguments: Vec<String>,
    pub explicit_shell: bool,
    pub wait: bool,
    pub requires_confirmation: bool,
    pub timeout_seconds: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeIntegrationKind {
    Editor,
    Terminal,
    FileManager,
    Browser,
    DiffTool,
    MergeTool,
    Custom,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeIntegrationExecution {
    Direct,
    ExplicitShell,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeIntegrationLaunchMode {
    Detached,
    Wait,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeIntegrationDefinition {
    pub id: String,
    pub kind: NativeIntegrationKind,
    pub executable: NativePathIdentity,
    pub arguments: Vec<String>,
    pub execution: NativeIntegrationExecution,
    pub launch_mode: NativeIntegrationLaunchMode,
    pub requires_confirmation: bool,
    pub timeout_seconds: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeIntegrationVariables {
    pub url: Option<String>,
    pub file: Option<NativePathIdentity>,
    pub current_branch: Option<Vec<u8>>,
    pub selected_commit: Option<String>,
    pub diff_left: Option<NativePathIdentity>,
    pub diff_right: Option<NativePathIdentity>,
    pub merge_base: Option<NativePathIdentity>,
    pub merge_current: Option<NativePathIdentity>,
    pub merge_incoming: Option<NativePathIdentity>,
    pub merge_result: Option<NativePathIdentity>,
}

// A derived impl would carry no `flutter_rust_bridge:ignore` marker.
#[allow(clippy::derivable_impls)]
impl Default for NativeIntegrationVariables {
    // flutter_rust_bridge reads this crate as a third-party input and would expose a Dart
    // `default_()` for every `Default` impl; the bridge types carry no functions.
    /// flutter_rust_bridge:ignore
    fn default() -> Self {
        Self {
            url: Default::default(),
            file: Default::default(),
            current_branch: Default::default(),
            selected_commit: Default::default(),
            diff_left: Default::default(),
            diff_right: Default::default(),
            merge_base: Default::default(),
            merge_current: Default::default(),
            merge_incoming: Default::default(),
            merge_result: Default::default(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeIntegrationRequest {
    pub kind: NativeIntegrationKind,
    pub discovered_id: Option<String>,
    pub configured: Option<NativeIntegrationDefinition>,
    pub variables: NativeIntegrationVariables,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeIntegrationCandidate {
    pub id: String,
    pub kind: NativeIntegrationKind,
    pub executable: NativePathIdentity,
    pub launch_mode: NativeIntegrationLaunchMode,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeIntegrationDiscoveryResult {
    pub candidates: Vec<NativeIntegrationCandidate>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeIntegrationFailureKind {
    InvalidRequest,
    Unavailable,
    MissingVariable,
    Stale,
    ConfirmationRequired,
    Canceled,
    TimedOut,
    NonZeroExit,
    Launch,
    Read,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeIntegrationFailure {
    pub kind: NativeIntegrationFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeIntegrationPreview {
    pub token: u64,
    pub kind: NativeIntegrationKind,
    pub definition_id: String,
    pub executable: String,
    pub arguments: Vec<String>,
    pub explicit_shell: bool,
    pub waits_for_exit: bool,
    pub requires_confirmation: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeIntegrationPreviewResult {
    pub preview: Option<NativeIntegrationPreview>,
    pub failure: Option<NativeIntegrationFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeIntegrationExecutionState {
    Completed,
    Detached,
    Failed,
    Canceled,
    TimedOut,
    Stale,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeIntegrationExecutionResult {
    pub state: NativeIntegrationExecutionState,
    pub activity_id: Option<String>,
    pub process_id: Option<u32>,
    pub failure: Option<NativeIntegrationFailure>,
}
