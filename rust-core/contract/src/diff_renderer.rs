//! The bridge types of `diff_renderer`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.
use crate::domain::path_identity::NativePathIdentity;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeDiffRendererSettings {
    pub id: String,
    pub title: String,
    pub executable: NativePathIdentity,
    pub arguments: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffRendererDefinition {
    pub id: String,
    pub title: String,
    pub executable: NativePathIdentity,
    pub arguments: Vec<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeDiffRendererFailureKind {
    InvalidDefinition,
    Unavailable,
    InvalidCapability,
    InputTooLarge,
    OutputTooLarge,
    LaunchFailed,
    ProcessFailed,
    TimedOut,
    Canceled,
    Stale,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffRendererFailure {
    pub kind: NativeDiffRendererFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffRendererPreview {
    pub token: u64,
    pub title: String,
    pub executable: String,
    pub capability_arguments: Vec<String>,
    pub arguments: Vec<String>,
    pub protocol: String,
    pub media_type: String,
    pub input_bytes: u64,
    pub output_limit_bytes: u64,
    pub timeout_seconds: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffRendererPreviewResult {
    pub preview: Option<NativeDiffRendererPreview>,
    pub failure: Option<NativeDiffRendererFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeDiffRendererState {
    Pending,
    Ready,
    Fallback,
    Canceled,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffRendererResult {
    pub state: NativeDiffRendererState,
    pub title: Option<String>,
    pub text: Option<String>,
    pub accessibility_text: Option<String>,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativeDiffRendererFailure>,
}
