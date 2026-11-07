//! The bridge types of `power_tools`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativePowerFailureKind {
    InvalidRequest,
    Busy,
    Canceled,
    TimedOut,
    Stale,
    Git,
    Read,
    TooLarge,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativePowerFailure {
    pub kind: NativePowerFailureKind,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativePowerJobState {
    Pending,
    Completed,
    Failed,
    Canceled,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativePowerJobStartResult {
    pub token: Option<u64>,
    pub failure: Option<NativePowerFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeSearchCompleteness {
    Complete,
    CommitLimitReached,
    ResultLimitReached,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffContentMatch {
    pub commit: String,
    pub summary: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffContentSearchResult {
    pub state: NativePowerJobState,
    pub matches: Vec<NativeDiffContentMatch>,
    pub examined_commits: u64,
    pub completeness: Option<NativeSearchCompleteness>,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativePowerFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeDiffSearchScope {
    AllRefs,
    CurrentBranch,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffSearchOptions {
    pub query: String,
    pub maximum_commits: u32,
    pub case_sensitive: bool,
    pub scope: NativeDiffSearchScope,
    /// With [`NativeDiffSearchScope::AllRefs`], whether commits only references outside
    /// branches, remote-tracking branches, tags and the stash reach are searched too.
    pub other_refs: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRepositoryStatisticsResult {
    pub state: NativePowerJobState,
    pub commit_count: u64,
    pub local_branch_count: u64,
    pub tag_count: u64,
    pub changed_path_count: u64,
    pub incomplete: bool,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativePowerFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeBisectMark {
    Good,
    Bad,
    Skip,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeBisectTimelineEntry {
    pub revision: String,
    pub mark: NativeBisectMark,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeBisectState {
    pub active: bool,
    pub current: Option<String>,
    pub original_head: Option<String>,
    pub timeline: Vec<NativeBisectTimelineEntry>,
    pub remaining_steps: Option<u64>,
    pub next_step_summary: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeBisectStateResult {
    pub state: Option<NativeBisectState>,
    pub failure: Option<NativePowerFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeBisectAction {
    Start,
    Good,
    Bad,
    Skip,
    Reset,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeBisectPreview {
    pub token: u64,
    pub action: NativeBisectAction,
    pub arguments: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeBisectPreviewResult {
    pub preview: Option<NativeBisectPreview>,
    pub failure: Option<NativePowerFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeBisectExecutionState {
    Completed,
    Stale,
    Failed,
    /// Git may have moved the bisect checkout; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeBisectExecutionResult {
    pub state: NativeBisectExecutionState,
    pub bisect: Option<NativeBisectState>,
    pub activity_id: Option<String>,
    pub failure: Option<NativePowerFailure>,
}
