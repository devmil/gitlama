//! The bridge types of `hosting_reference`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the desktop library's (`gitlama_core`) module of the same name.
use crate::hosting::NativeHostingRemoteReferenceKind;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHostingReferenceFailure {
    InvalidRequest,
    StaleRevision,
    ChangedText,
    StaleRange,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReferenceCandidate {
    pub stable_id: String,
    pub kind: NativeHostingRemoteReferenceKind,
    pub number: u64,
    pub title: String,
    pub insertion: String,
    pub web_url: String,
    pub stale: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReferenceProjection {
    pub revision: u64,
    pub text_hash: u64,
    pub replace_start: u32,
    pub replace_end: u32,
    pub query: String,
    pub candidates: Vec<NativeHostingReferenceCandidate>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReferenceProjectionResult {
    pub projection: Option<NativeHostingReferenceProjection>,
    pub failure: Option<NativeHostingReferenceFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHostingReferenceApplyResult {
    pub text: Vec<u16>,
    pub caret: u32,
    pub failure: Option<NativeHostingReferenceFailure>,
}
