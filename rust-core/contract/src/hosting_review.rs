//! The bridge types of `hosting_review`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the desktop library's (`gitlama_core`) module of the same name.
use crate::hosting::NativeHostingCheck;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum NativeHostingReviewAction {
    Comment,
    Approve,
    RequestChanges,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingReviewFailure {
    InvalidRequest,
    IntegrationDisabled,
    CredentialMissing,
    CredentialUnreadable,
    CredentialExpired,
    Unauthorized,
    PermissionDenied,
    RateLimited,
    MalformedResponse,
    Unavailable,
    Canceled,
    Unsupported,
    MovedBase,
    StaleAuthorization,
    Uncertain,
    DraftStorage,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct NativeHostingInlineDraft {
    pub stable_id: String,
    pub path: String,
    pub line: u64,
    pub body: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReviewAnchor {
    pub stable_id: String,
    pub path: String,
    pub line: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReviewDiff {
    pub stable_id: String,
    pub path: String,
    pub patch: String,
    pub anchors: Vec<NativeHostingReviewAnchor>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReviewThread {
    pub stable_id: String,
    pub path: Option<String>,
    pub line: Option<u64>,
    pub anchor_id: Option<String>,
    pub author: String,
    pub body: String,
    pub resolved: bool,
    pub outdated: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReviewPage {
    pub connection_id: String,
    pub repository: String,
    pub pull_request: u64,
    pub head_sha: String,
    pub diffs: Vec<NativeHostingReviewDiff>,
    pub threads: Vec<NativeHostingReviewThread>,
    pub checks: Vec<NativeHostingCheck>,
    pub next_page: Option<String>,
    pub incomplete: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReviewLoadResult {
    pub page: Option<NativeHostingReviewPage>,
    pub failure: Option<NativeHostingReviewFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReviewPreview {
    pub authorization_id: u64,
    pub target: String,
    pub payload: String,
    pub connection_id: String,
    pub repository: String,
    pub pull_request: u64,
    pub head_sha: String,
    pub action: NativeHostingReviewAction,
    pub body: String,
    pub inline_comments: Vec<NativeHostingInlineDraft>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReviewPreviewResult {
    pub preview: Option<NativeHostingReviewPreview>,
    pub failure: Option<NativeHostingReviewFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingCheckRetryPreview {
    pub authorization_id: u64,
    pub target: String,
    pub payload: String,
    pub connection_id: String,
    pub repository: String,
    pub head_sha: String,
    pub check_stable_id: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingCheckRetryPreviewResult {
    pub preview: Option<NativeHostingCheckRetryPreview>,
    pub failure: Option<NativeHostingReviewFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingReviewSubmitState {
    Submitted,
    Reconciled,
    Failed,
    Uncertain,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReviewSubmitResult {
    pub state: NativeHostingReviewSubmitState,
    pub failure: Option<NativeHostingReviewFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct NativeHostingReviewDraft {
    pub key: String,
    pub connection_id: String,
    pub repository: String,
    pub pull_request: u64,
    pub head_sha: String,
    pub action: NativeHostingReviewAction,
    pub body: String,
    pub inline_comments: Vec<NativeHostingInlineDraft>,
    pub updated_at: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReviewDraftResult {
    pub draft: Option<NativeHostingReviewDraft>,
    pub saved: bool,
    pub failure: Option<NativeHostingReviewFailure>,
}
