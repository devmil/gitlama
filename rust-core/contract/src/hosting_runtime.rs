//! The bridge types of `hosting_runtime`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the desktop library's (`gitlama_core`) module of the same name.
use crate::hosting::{NativeHostingChangeRequest, NativeHostingCheckState, NativeHostingResources};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingOAuthState {
    Queued,
    WaitingForBrowser,
    WaitingForDevice,
    Exchanging,
    Succeeded,
    Failed,
    Canceled,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingOAuthFailure {
    InvalidConnection,
    Busy,
    Unavailable,
    Unauthorized,
    RateLimited,
    MalformedResponse,
    Expired,
    Denied,
    SecureStore,
    NotFound,
    Redirected,
    ServerError,
    Network,
    Certificate,
    TimedOut,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingOAuthSnapshot {
    pub request_id: u64,
    pub state: NativeHostingOAuthState,
    pub browser_url: Option<String>,
    pub user_code: Option<String>,
    pub authenticated_login: Option<String>,
    pub failure: Option<NativeHostingOAuthFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingOAuthStartResult {
    pub snapshot: Option<NativeHostingOAuthSnapshot>,
    pub failure: Option<NativeHostingOAuthFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingOAuthPollResult {
    pub snapshot: Option<NativeHostingOAuthSnapshot>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingResourceLoadState {
    Inactive,
    Loading,
    Ready,
    Failed,
    Canceled,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingResourceFailure {
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
    NotFound,
    Redirected,
    ServerError,
    Network,
    Certificate,
    TimedOut,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingResourceSnapshot {
    pub request_id: u64,
    pub state: NativeHostingResourceLoadState,
    pub page: u32,
    pub resources: NativeHostingResources,
    pub stale: bool,
    pub has_more: bool,
    pub failure: Option<NativeHostingResourceFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingResourceStartResult {
    pub snapshot: Option<NativeHostingResourceSnapshot>,
    pub failure: Option<NativeHostingResourceFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingResourcePollResult {
    pub snapshot: Option<NativeHostingResourceSnapshot>,
}

/// Open pull requests found for one branch of the bound repository.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingBranchPullRequests {
    pub branch: String,
    pub change_requests: Vec<NativeHostingChangeRequest>,
}

/// The CI result of one commit of the bound repository, such as its default branch's head.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingHeadChecks {
    pub head: String,
    pub checks: NativeHostingCheckState,
}

/// Progress of one on-demand pull-request lookup. Heads and branches appear in `heads` and
/// `branches` as they resolve; `authored` stays `None` until the authored query (if
/// requested) resolves.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingPullRequestLookupSnapshot {
    pub request_id: u64,
    pub state: NativeHostingResourceLoadState,
    pub heads: Vec<NativeHostingHeadChecks>,
    pub branches: Vec<NativeHostingBranchPullRequests>,
    pub authored: Option<Vec<NativeHostingChangeRequest>>,
    pub failure: Option<NativeHostingResourceFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingPullRequestLookupStartResult {
    pub snapshot: Option<NativeHostingPullRequestLookupSnapshot>,
    pub failure: Option<NativeHostingResourceFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingPullRequestLookupPollResult {
    pub snapshot: Option<NativeHostingPullRequestLookupSnapshot>,
}
