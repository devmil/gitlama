//! The bridge types of `hosting`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the desktop library's (`gitlama_core`) module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingPreset {
    GitHub,
    GitLab,
    GitLabSelfManaged,
    Forgejo,
    Codeberg,
    GitHubEnterprise,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingAuthentication {
    OAuth,
    GitHubCli,
    GitLabCli,
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum NativeHostingCapability {
    ChangeRequests,
    ChangeRequestCheckout,
    ChangeRequestReview,
    CommitStatuses,
    CheckRuns,
    Issues,
    RemoteReferences,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingConnection {
    pub id: String,
    pub preset: NativeHostingPreset,
    pub login: String,
    pub web_base_url: String,
    pub api_base_url: String,
    pub oauth_client_id: String,
    pub authentication: NativeHostingAuthentication,
    pub enabled: bool,
    pub refresh_enabled: bool,
    pub capabilities: Vec<NativeHostingCapability>,
    pub credential_identity: String,
    pub allow_split_origin: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingRemote {
    pub name: Vec<u8>,
    pub url: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingBindingState {
    Unmatched,
    Ambiguous,
    Bound,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingBindingResult {
    pub state: NativeHostingBindingState,
    pub remote: Vec<u8>,
    pub server: String,
    pub connection_id: Option<String>,
    pub provider_repository: Option<String>,
    pub web_url: Option<String>,
    pub failure: Option<NativeHostingFailureKind>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingCredentialState {
    Missing,
    Available,
    Expired,
    Unreadable,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingFailureKind {
    InvalidConnection,
    InvalidRemote,
    InvalidLink,
    Ambiguous,
    CredentialMissing,
    CredentialUnreadable,
    CredentialExpired,
    CredentialStore,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingConnectionResult {
    pub connection: Option<NativeHostingConnection>,
    pub failure: Option<NativeHostingFailureKind>,
}

/// The defaults a new connection of one preset starts with (devmil-git's preset rules).
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingPresetDefaults {
    pub preset: NativeHostingPreset,
    /// The normalized `https` web origin.
    pub web_base_url: String,
    pub api_base_url: String,
    /// A GitHub Enterprise Cloud tenant (`<tenant>.ghe.com`) with its API on `api.<tenant>`.
    pub github_tenant: bool,
    pub capabilities: Vec<NativeHostingCapability>,
    /// Allowed authentication methods; the first is the default.
    pub authentications: Vec<NativeHostingAuthentication>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingPresetDefaultsResult {
    pub defaults: Option<NativeHostingPresetDefaults>,
    pub failure: Option<NativeHostingFailureKind>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingLinkResult {
    pub url: Option<String>,
    pub failure: Option<NativeHostingFailureKind>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingResourceKind {
    Repository,
    ChangeRequest,
    CreateChangeRequest,
    Issue,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingChangeRequestState {
    Open,
    Closed,
    Merged,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingReviewSummary {
    None,
    Pending,
    Approved,
    ChangesRequested,
    Unknown,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingMergeability {
    Mergeable,
    Conflicting,
    Checking,
    Unknown,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingCheckState {
    Pending,
    Passing,
    Failing,
    Canceled,
    Skipped,
    Unknown,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingCheck {
    pub stable_id: String,
    pub name: String,
    pub state: NativeHostingCheckState,
    pub conclusion: String,
    pub details_url: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingCheckSummary {
    pub state: NativeHostingCheckState,
    pub checks: Vec<NativeHostingCheck>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingChangeRequest {
    pub stable_id: String,
    pub number: u64,
    pub title: String,
    pub author: String,
    pub state: NativeHostingChangeRequestState,
    pub draft: bool,
    pub source_repository: String,
    pub source_branch: String,
    pub target_repository: String,
    pub target_branch: String,
    pub head_sha: String,
    pub web_url: String,
    pub review_summary: NativeHostingReviewSummary,
    pub mergeability: NativeHostingMergeability,
    pub checks: NativeHostingCheckSummary,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingIssueState {
    Open,
    Closed,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingIssue {
    pub stable_id: String,
    pub number: u64,
    pub title: String,
    pub state: NativeHostingIssueState,
    pub author: String,
    pub assignees: Vec<String>,
    pub labels: Vec<String>,
    pub private: bool,
    pub updated_at: String,
    pub web_url: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingRemoteReferenceKind {
    Issue,
    ChangeRequest,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingRemoteReference {
    pub stable_id: String,
    pub kind: NativeHostingRemoteReferenceKind,
    pub number: u64,
    pub title: String,
    pub insertion: String,
    pub web_url: String,
}

/// The provider-neutral resource envelope used by later scheduler and adapter packages.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingResources {
    pub change_requests: Vec<NativeHostingChangeRequest>,
    pub issues: Vec<NativeHostingIssue>,
    pub remote_references: Vec<NativeHostingRemoteReference>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingCredentialResult {
    pub state: NativeHostingCredentialState,
    pub failure: Option<NativeHostingFailureKind>,
}
