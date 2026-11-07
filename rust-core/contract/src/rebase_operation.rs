//! The bridge types of `rebase_operation`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeRebaseAction {
    Pick,
    Reword,
    Edit,
    Squash,
    Fixup,
    Drop,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRebaseInstruction {
    pub id: u64,
    pub action: NativeRebaseAction,
    pub oid: String,
    pub subject: Vec<u8>,
    pub published: bool,
    pub replacement_message: Option<Vec<u8>>,
    pub autosquash_base_id: Option<u64>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeRebaseFailureKind {
    InvalidRequest,
    EmptyPlan,
    InvalidPlan,
    DirtyWorktree,
    DetachedHead,
    ActiveOperation,
    PublicationConfirmationRequired,
    Stale,
    Canceled,
    Failed,
    Read,
    Unsupported,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRebaseFailure {
    pub kind: NativeRebaseFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRebasePlanResult {
    pub token: Option<u64>,
    pub onto: String,
    pub onto_name: Option<Vec<u8>>,
    pub current_branch: Vec<u8>,
    pub current_head: String,
    pub instructions: Vec<NativeRebaseInstruction>,
    pub published_count: u32,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativeRebaseFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRebasePreviewResult {
    pub token: Option<u64>,
    pub arguments: Vec<String>,
    pub todo: Vec<u8>,
    pub instruction_count: u32,
    pub published_count: u32,
    pub instructions: Vec<NativeRebaseInstruction>,
    pub autosquash_applied: u32,
    pub failure: Option<NativeRebaseFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeRebaseExecutionState {
    Completed,
    Conflict,
    EditStop,
    Interrupted,
    Stale,
    Failed,
    ReconciledWithWarning,
    /// Git may have rewritten the branch; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRebaseExecutionResult {
    pub state: NativeRebaseExecutionState,
    pub failure: Option<NativeRebaseFailure>,
    pub activity_ids: Vec<String>,
    pub conflicting_paths: Vec<Vec<u8>>,
    pub running_instruction: Option<Vec<u8>>,
}
