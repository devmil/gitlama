//! The bridge types of `diff`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeDiffLayout {
    Unified,
    SideBySide,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeDiffRowKind {
    File,
    Hunk,
    Context,
    Addition,
    Deletion,
    NoNewline,
    Binary,
    Image,
    Submodule,
    ModeOnly,
    TooLarge,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeDiffFileKind {
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct NativeDiffSpan {
    pub start: u32,
    pub end: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffRow {
    pub stable_id: String,
    pub kind: NativeDiffRowKind,
    pub old_line: Option<u32>,
    pub new_line: Option<u32>,
    pub text: Vec<u8>,
    pub text_truncated: bool,
    pub selectable: bool,
    pub intra_line: Vec<NativeDiffSpan>,
    pub syntax: Option<Vec<u8>>,
    pub file_kind: Option<NativeDiffFileKind>,
    pub old_path: Option<Vec<u8>>,
    pub new_path: Option<Vec<u8>>,
    /// Exclusive row offset of this file section. Present only on file rows.
    pub section_end: Option<u32>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffPage {
    pub request_id: u64,
    pub layout: NativeDiffLayout,
    pub total_rows: u64,
    pub offset: u64,
    pub rows: Vec<NativeDiffRow>,
    pub payload_bytes: u64,
}

/// Which accepted projection of a session a syntax request reads: the committed (history or
/// comparison) diff or the staged/unstaged working diff.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum NativeDiffSyntaxOrigin {
    Committed,
    Working,
}

/// The closed, theme-independent category of a run of diff text.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeSyntaxTokenKind {
    Plain,
    Comment,
    Keyword,
    String,
    Number,
    Type,
    Function,
    Variable,
    Constant,
    Operator,
    Punctuation,
    Attribute,
    Tag,
}

/// A half-open UTF-8 byte range of a row's displayed text, without its sign or terminator.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct NativeSyntaxSpan {
    pub start: u32,
    pub end: u32,
    pub kind: NativeSyntaxTokenKind,
}

/// Why one side of a row has, or lacks, categories. Every state but `Ready` shows plain text.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeSyntaxSideState {
    /// Categories are known; no spans means the line is plain.
    Ready,
    /// The row has no text on this side, or no grammar matches the file.
    Unsupported,
    InvalidEncoding,
    TooLarge,
    /// The source no longer matches the accepted diff.
    SourceChanged,
    /// A line, span or reply bound was reached.
    LimitReached,
    /// Transient pressure; a later demand may succeed.
    Deferred,
    /// The source cannot be identified or read exactly.
    Unavailable,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffSyntaxRow {
    pub stable_id: String,
    pub old_state: NativeSyntaxSideState,
    pub new_state: NativeSyntaxSideState,
    pub old_spans: Vec<NativeSyntaxSpan>,
    pub new_spans: Vec<NativeSyntaxSpan>,
}

/// One syntax read of an accepted diff projection's rows.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct NativeDiffSyntaxRequest {
    pub origin: NativeDiffSyntaxOrigin,
    /// The accepted diff projection the rows belong to.
    pub diff_request_id: u64,
    /// The caller's nonzero identity of this request, for cancellation.
    pub syntax_request_id: u64,
    pub offset: u64,
    pub maximum_rows: u32,
}

/// The categories of contiguous rows of one accepted projection. The session is the one the
/// request named; a remote helper's own session identity never reaches the client.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffSyntaxPage {
    pub origin: NativeDiffSyntaxOrigin,
    pub diff_request_id: u64,
    pub syntax_request_id: u64,
    pub offset: u64,
    /// Contiguous rows returned from `offset`; `rows` holds exactly this many.
    pub row_count: u32,
    /// Where to continue when the reply bound ended the page early.
    pub next_offset: Option<u64>,
    pub rows: Vec<NativeDiffSyntaxRow>,
    pub payload_bytes: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDiffSyntaxResult {
    pub page: Option<NativeDiffSyntaxPage>,
    pub failure: Option<crate::dto::NativeRepositoryFailure>,
}

/// One syntax read of text the caller already holds, such as a conflicted file's side or an
/// unsaved merge result. The path only selects the grammar; nothing is read from it.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeTextSyntaxRequest {
    /// The caller's nonzero identity of the text's view; its requests queue and cancel together.
    pub view_id: u64,
    /// The caller's nonzero identity of this request, for cancellation.
    pub syntax_request_id: u64,
    pub path: Vec<u8>,
    pub source: Vec<u8>,
    /// The one-based first line wanted.
    pub first_line: u32,
    pub maximum_lines: u32,
}

/// The categories of one line of a text, over UTF-16 code-unit offsets of the line without its
/// terminator: the offsets a Dart string of the line indexes.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeTextSyntaxLine {
    pub state: NativeSyntaxSideState,
    pub spans: Vec<NativeSyntaxSpan>,
}

/// The categories of contiguous lines from `first_line`: fewer than requested where the text
/// ends. When `state` is not `Ready` the whole text stays plain and `lines` is empty.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeTextSyntaxPage {
    pub view_id: u64,
    pub syntax_request_id: u64,
    pub first_line: u32,
    pub state: NativeSyntaxSideState,
    pub lines: Vec<NativeTextSyntaxLine>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeTextSyntaxResult {
    pub page: Option<NativeTextSyntaxPage>,
    pub failure: Option<crate::dto::NativeRepositoryFailure>,
}
