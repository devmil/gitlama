//! The bridge types of `advanced_rebase`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeFixupSuggestionState {
    Suggested,
    Ambiguous,
    NoBase,
    Incomplete,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeFixupEvidence {
    pub path: Option<Vec<u8>>,
    pub commit: String,
    pub subject: Vec<u8>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeFixupSuggestionResult {
    pub state: NativeFixupSuggestionState,
    pub candidate: Option<String>,
    pub subject: Option<Vec<u8>>,
    pub fixup_message: Option<Vec<u8>>,
    pub squash_message: Option<Vec<u8>>,
    pub evidence: Vec<NativeFixupEvidence>,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativeAdvancedRebaseFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeAdvancedRebaseFailureKind {
    InvalidRequest,
    DirtyWorktree,
    DetachedHead,
    ActiveOperation,
    PublicationConfirmationRequired,
    Stale,
    Canceled,
    Conflict,
    TooLarge,
    Unsupported,
    Read,
    Git,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeAdvancedRebaseFailure {
    pub kind: NativeAdvancedRebaseFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRestackStep {
    pub id: u32,
    pub branch: Vec<u8>,
    pub expected_head: String,
    pub old_parent: String,
    pub new_parent: Vec<u8>,
    pub expected_new_parent_head: String,
    pub published: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRestackPlanResult {
    pub token: Option<u64>,
    pub root_branch: Vec<u8>,
    pub steps: Vec<NativeRestackStep>,
    pub published_count: u32,
    pub incomplete: bool,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativeAdvancedRebaseFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeRestackExecutionState {
    Completed,
    Conflict,
    Partial,
    Stale,
    Canceled,
    Failed,
    ReconciledWithWarning,
    /// Git may have moved a branch; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRestackExecutionResult {
    pub state: NativeRestackExecutionState,
    pub completed_steps: u32,
    pub total_steps: u32,
    pub current_branch: Option<Vec<u8>>,
    pub recovery_refs: Vec<Vec<u8>>,
    pub conflicting_paths: Vec<Vec<u8>>,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativeAdvancedRebaseFailure>,
}
