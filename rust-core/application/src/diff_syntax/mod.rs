//! Syntax categories for the rows of an accepted diff projection.
//!
//! Colours are optional enrichment of text that is already on screen. Nothing here is awaited
//! by a diff read: a syntax request names rows of a projection the session already accepted,
//! the worker reads each side's exact source on the repository's background lane, proves it
//! against every line the diff displays, and parses whole sources with the shared engine on
//! one low-priority thread. Any doubt about a source leaves that side plain.
pub use gitlama_contract::diff::{
    NativeDiffSyntaxOrigin, NativeDiffSyntaxPage, NativeDiffSyntaxRequest, NativeDiffSyntaxResult,
    NativeDiffSyntaxRow, NativeSyntaxSideState, NativeSyntaxSpan, NativeSyntaxTokenKind,
    NativeTextSyntaxLine, NativeTextSyntaxPage, NativeTextSyntaxRequest, NativeTextSyntaxResult,
};

mod priority;
mod worker;

pub(crate) use worker::{
    cancel, cancel_session, retire_view, submit, submit_text, Admission, Owner, TextAdmission,
};

use crate::diff::NativeDiffRowKind;
use crate::domain::limits::{SYNTAX_LINE_BYTES, SYNTAX_SOURCE_BYTES, SYNTAX_SPANS_PER_SIDE};
use devmil_git::diff::model::{DiffDocument, DiffFile, DiffPath, GitFileMode};
use devmil_git::diff::source::{patch_object_ids, verify_displayed_lines, DiffSide, SourceLines};
use devmil_git::diff::syntax::{
    Annotation, AnnotationRequest, LineSyntax, SyntaxAnnotator, SyntaxCatalog, SyntaxLimits,
    SyntaxTokenKind,
};
use devmil_git::types::ObjectId;
use devmil_git::Repository;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// How long one source read may wait on the repository's background lane.
const SOURCE_READ_WAIT: Duration = Duration::from_secs(2);

/// The accepted projection a request's rows belong to.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) struct ViewKey {
    pub session_id: u64,
    pub generation: u64,
    pub origin: NativeDiffSyntaxOrigin,
    pub diff_request_id: u64,
}

/// Where one side of one file's source is read from.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum SideSource {
    /// The side does not exist (an addition's old side); its rows show nothing.
    Absent,
    /// An immutable blob the accepted diff named.
    Blob { object: ObjectId, path: DiffPath },
    /// The worktree file the accepted diff showed, proven by the exact digest captured with it.
    Worktree {
        path: DiffPath,
        bytes: u64,
        digest: [u8; 32],
    },
    /// No exact source: the side stays plain for this reason.
    Plain(NativeSyntaxSideState),
}

#[derive(Clone, Debug)]
pub(crate) struct FileSources {
    pub old: SideSource,
    pub new: SideSource,
}

/// One requested row: the identity and text the reply must match.
#[derive(Clone, Debug)]
pub(crate) struct RowRef {
    pub stable_id: String,
    pub kind: NativeDiffRowKind,
    pub old_line: Option<u32>,
    pub new_line: Option<u32>,
    pub text: Vec<u8>,
    pub truncated: bool,
    pub file: usize,
}

/// One admitted unit of work.
pub(crate) struct Job {
    pub view: ViewKey,
    pub syntax_request_id: u64,
    pub offset: u64,
    pub rows: Vec<RowRef>,
    pub document: Arc<DiffDocument>,
    pub files: HashMap<usize, FileSources>,
    pub repository: Arc<Repository>,
}

/// One admitted read of text the caller holds.
pub(crate) struct TextJob {
    pub view_id: u64,
    pub syntax_request_id: u64,
    pub path: Vec<u8>,
    pub source: Vec<u8>,
    pub first_line: u32,
    pub maximum_lines: u32,
}

impl TextJob {
    /// A reply that leaves the whole text plain for `state`.
    pub(crate) const fn plain(&self, state: NativeSyntaxSideState) -> NativeTextSyntaxPage {
        NativeTextSyntaxPage {
            view_id: self.view_id,
            syntax_request_id: self.syntax_request_id,
            first_line: self.first_line,
            state,
            lines: Vec::new(),
        }
    }
}

/// The sources of one committed or staged file: blobs the accepted read named.
pub(crate) fn blob_sources(file: &DiffFile) -> FileSources {
    let ids = patch_object_ids(file);
    let side =
        |path: Option<&DiffPath>, mode: Option<GitFileMode>, object: Option<&ObjectId>| match (
            path,
            ids.as_ref(),
        ) {
            (None, _) => SideSource::Absent,
            (Some(_), _) if unsupported_mode(mode) => {
                SideSource::Plain(NativeSyntaxSideState::Unsupported)
            }
            (Some(path), Some(_)) => object.map_or(
                SideSource::Plain(NativeSyntaxSideState::Unavailable),
                |object| SideSource::Blob {
                    object: object.clone(),
                    path: path.clone(),
                },
            ),
            (Some(_), None) => SideSource::Plain(NativeSyntaxSideState::Unavailable),
        };
    FileSources {
        old: side(
            file.id.old_path.as_ref(),
            file.old_mode,
            ids.as_ref().and_then(|ids| ids.old.as_ref()),
        ),
        new: side(
            file.id.new_path.as_ref(),
            file.new_mode,
            ids.as_ref().and_then(|ids| ids.new.as_ref()),
        ),
    }
}

/// Symlinks and submodules show link targets and commit IDs, not source.
fn unsupported_mode(mode: Option<GitFileMode>) -> bool {
    matches!(mode, Some(GitFileMode::SYMLINK | GitFileMode::GITLINK))
}

/// The sources of one unstaged file: the index blob and the worktree file proven by `guard`.
pub(crate) fn worktree_sources(
    file: &DiffFile,
    guard: Option<&devmil_git::filesystem::fingerprint::PathFingerprint>,
) -> FileSources {
    use devmil_git::filesystem::fingerprint::PathFingerprint;
    let blobs = blob_sources(file);
    let new = match (file.id.new_path.as_ref(), guard) {
        (None, _) => SideSource::Absent,
        (Some(_), _) if unsupported_mode(file.new_mode) => {
            SideSource::Plain(NativeSyntaxSideState::Unsupported)
        }
        (Some(path), Some(PathFingerprint::File { bytes, digest, .. })) => SideSource::Worktree {
            path: path.clone(),
            bytes: *bytes,
            digest: *digest,
        },
        (Some(_), Some(PathFingerprint::DeferredFile(_))) => {
            SideSource::Plain(NativeSyntaxSideState::TooLarge)
        }
        (Some(_), _) => SideSource::Plain(NativeSyntaxSideState::Unavailable),
    };
    FileSources {
        old: if file.id.old_path.is_none() {
            SideSource::Absent
        } else {
            blobs.old
        },
        new,
    }
}

/// The worker's parser and its source cache. Lives on the worker thread only.
pub(crate) struct Engine {
    annotator: Option<SyntaxAnnotator>,
    sources: SourceCache,
}

impl Engine {
    pub(crate) fn new() -> Self {
        Self {
            annotator: None,
            sources: SourceCache::default(),
        }
    }

    fn annotator(&mut self) -> &mut SyntaxAnnotator {
        self.annotator.get_or_insert_with(|| {
            SyntaxAnnotator::new(
                Arc::new(SyntaxCatalog::bundled()),
                SyntaxLimits {
                    source_bytes: SYNTAX_SOURCE_BYTES,
                    line_bytes: SYNTAX_LINE_BYTES,
                    spans_per_line: SYNTAX_SPANS_PER_SIDE,
                    ..SyntaxLimits::default()
                },
            )
        })
    }

    /// Categories for every row of `job`, in order.
    pub(crate) fn run(&mut self, job: &Job, cancellation: &AtomicBool) -> Vec<NativeDiffSyntaxRow> {
        let mut sides: HashMap<(usize, DiffSide), SideResult> = HashMap::new();
        let mut wanted: BTreeMap<(usize, DiffSide), BTreeSet<u32>> = BTreeMap::new();
        for row in &job.rows {
            if let Some(line) = side_line(row, DiffSide::Old) {
                wanted
                    .entry((row.file, DiffSide::Old))
                    .or_default()
                    .insert(line);
            }
            if let Some(line) = side_line(row, DiffSide::New) {
                wanted
                    .entry((row.file, DiffSide::New))
                    .or_default()
                    .insert(line);
            }
        }
        for ((file, side), lines) in wanted {
            let result = if cancellation.load(Ordering::Acquire) {
                SideResult::Plain(NativeSyntaxSideState::Deferred)
            } else {
                self.annotate_side(job, file, side, &lines, cancellation)
            };
            sides.insert((file, side), result);
        }
        job.rows
            .iter()
            .map(|row| {
                let (old_state, old_spans) = row_side(row, DiffSide::Old, &sides);
                let (new_state, new_spans) = row_side(row, DiffSide::New, &sides);
                NativeDiffSyntaxRow {
                    stable_id: row.stable_id.clone(),
                    old_state,
                    new_state,
                    old_spans,
                    new_spans,
                }
            })
            .collect()
    }

    fn annotate_side(
        &mut self,
        job: &Job,
        file_index: usize,
        side: DiffSide,
        lines: &BTreeSet<u32>,
        cancellation: &AtomicBool,
    ) -> SideResult {
        let Some(file) = job.document.files.get(file_index) else {
            return SideResult::Plain(NativeSyntaxSideState::Unavailable);
        };
        let Some(sources) = job.files.get(&file_index) else {
            return SideResult::Plain(NativeSyntaxSideState::Unavailable);
        };
        let source = match side {
            DiffSide::Old => &sources.old,
            DiffSide::New => &sources.new,
        };
        let (key, path, bytes) = match self.sources.read(&job.repository, source, cancellation) {
            Ok(value) => value,
            Err(state) => return SideResult::Plain(state),
        };
        let verified = match verify_displayed_lines(file, side, &bytes) {
            Ok(verified) => verified,
            Err(_) => return SideResult::Plain(NativeSyntaxSideState::SourceChanged),
        };
        let annotator = self.annotator();
        let Some(language) = annotator.catalog().resolve(path.as_bytes(), &bytes) else {
            return SideResult::Plain(NativeSyntaxSideState::Unsupported);
        };
        let requested = lines
            .iter()
            .copied()
            .filter(|line| verified.contains(line))
            .collect::<Vec<_>>();
        let cancel = CancelFlag(cancellation);
        match annotator.annotate(
            AnnotationRequest {
                source_key: &key,
                source: &bytes,
                language,
                lines: &requested,
            },
            &cancel,
        ) {
            Annotation::Lines { lines, complete } => SideResult::Lines {
                lines,
                verified,
                complete,
            },
            Annotation::InvalidEncoding => {
                SideResult::Plain(NativeSyntaxSideState::InvalidEncoding)
            }
            Annotation::TooLarge => SideResult::Plain(NativeSyntaxSideState::TooLarge),
            Annotation::Canceled => SideResult::Plain(NativeSyntaxSideState::Deferred),
        }
    }
}

impl Engine {
    /// Categories for the requested lines of a caller-held text: `Ready` lines up to the end
    /// of the text, or no lines and the reason the whole text stays plain.
    pub(crate) fn run_text(
        &mut self,
        job: &TextJob,
        cancellation: &AtomicBool,
    ) -> NativeTextSyntaxPage {
        use sha2::{Digest, Sha256};
        if job.source.len() > SYNTAX_SOURCE_BYTES {
            return job.plain(NativeSyntaxSideState::TooLarge);
        }
        let annotator = self.annotator();
        let Some(language) = annotator.catalog().resolve(&job.path, &job.source) else {
            return job.plain(NativeSyntaxSideState::Unsupported);
        };
        let mut key = b"text:".to_vec();
        key.extend_from_slice(&Sha256::digest(&job.source));
        let text_lines = SourceLines::new(&job.source);
        let available = u32::try_from(text_lines.len()).unwrap_or(u32::MAX);
        let last = job
            .first_line
            .saturating_add(job.maximum_lines.saturating_sub(1))
            .min(available);
        let lines = (job.first_line..=last).collect::<Vec<_>>();
        if lines.is_empty() {
            return job.plain(NativeSyntaxSideState::Ready);
        }
        let cancel = CancelFlag(cancellation);
        let (annotated, complete) = match annotator.annotate(
            AnnotationRequest {
                source_key: &key,
                source: &job.source,
                language,
                lines: &lines,
            },
            &cancel,
        ) {
            Annotation::Lines { lines, complete } => (lines, complete),
            Annotation::InvalidEncoding => {
                return job.plain(NativeSyntaxSideState::InvalidEncoding)
            }
            Annotation::TooLarge => return job.plain(NativeSyntaxSideState::TooLarge),
            Annotation::Canceled => return job.plain(NativeSyntaxSideState::Deferred),
        };
        let lines = lines
            .iter()
            .map(|line| {
                let plain = |state| NativeTextSyntaxLine {
                    state,
                    spans: Vec::new(),
                };
                match annotated.get(line) {
                    None if complete => plain(NativeSyntaxSideState::Unavailable),
                    None => plain(NativeSyntaxSideState::Deferred),
                    Some(LineSyntax::LimitReached) => plain(NativeSyntaxSideState::LimitReached),
                    Some(LineSyntax::Spans(spans)) => {
                        let content = text_lines.line(*line).map_or(&[][..], |(text, _)| text);
                        match native_spans(content, spans)
                            .and_then(|spans| utf16_spans(content, spans))
                        {
                            Some(spans) => NativeTextSyntaxLine {
                                state: NativeSyntaxSideState::Ready,
                                spans,
                            },
                            None => plain(NativeSyntaxSideState::LimitReached),
                        }
                    }
                }
            })
            .collect();
        NativeTextSyntaxPage {
            lines,
            ..job.plain(NativeSyntaxSideState::Ready)
        }
    }
}

/// `spans`, validated over the UTF-8 bytes of `content`, as UTF-16 code-unit offsets: one
/// forward scan of the line.
fn utf16_spans(content: &[u8], spans: Vec<NativeSyntaxSpan>) -> Option<Vec<NativeSyntaxSpan>> {
    let text = std::str::from_utf8(content).ok()?;
    let mut chars = text.char_indices().peekable();
    let mut units = 0u32;
    let mut at = |byte: u32| {
        while let Some(&(index, character)) = chars.peek() {
            if index >= byte as usize {
                break;
            }
            units += u32::try_from(character.len_utf16()).unwrap_or(2);
            chars.next();
        }
        units
    };
    Some(
        spans
            .into_iter()
            .map(|span| NativeSyntaxSpan {
                start: at(span.start),
                end: at(span.end),
                kind: span.kind,
            })
            .collect(),
    )
}

struct CancelFlag<'a>(&'a AtomicBool);

impl devmil_git::cancellation::Cancellation for CancelFlag<'_> {
    fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::Acquire)
    }
}

enum SideResult {
    Plain(NativeSyntaxSideState),
    Lines {
        lines: BTreeMap<u32, LineSyntax>,
        verified: BTreeSet<u32>,
        complete: bool,
    },
}

/// The source line of `row` on `side`, when the row shows text from that side.
fn side_line(row: &RowRef, side: DiffSide) -> Option<u32> {
    match (side, row.kind) {
        (DiffSide::Old, NativeDiffRowKind::Context | NativeDiffRowKind::Deletion) => row.old_line,
        (DiffSide::New, NativeDiffRowKind::Context | NativeDiffRowKind::Addition) => row.new_line,
        _ => None,
    }
}

fn row_side(
    row: &RowRef,
    side: DiffSide,
    sides: &HashMap<(usize, DiffSide), SideResult>,
) -> (NativeSyntaxSideState, Vec<NativeSyntaxSpan>) {
    let Some(line) = side_line(row, side) else {
        return (NativeSyntaxSideState::Unsupported, Vec::new());
    };
    match sides.get(&(row.file, side)) {
        None => (NativeSyntaxSideState::Unavailable, Vec::new()),
        Some(SideResult::Plain(state)) => (*state, Vec::new()),
        Some(SideResult::Lines {
            lines,
            verified,
            complete,
        }) => {
            if !verified.contains(&line) {
                // A context line that differs on this side (whitespace ignored).
                return (NativeSyntaxSideState::Unavailable, Vec::new());
            }
            if row.truncated {
                return (NativeSyntaxSideState::LimitReached, Vec::new());
            }
            match lines.get(&line) {
                None if *complete => (NativeSyntaxSideState::Unavailable, Vec::new()),
                None => (NativeSyntaxSideState::Deferred, Vec::new()),
                Some(LineSyntax::LimitReached) => (NativeSyntaxSideState::LimitReached, Vec::new()),
                Some(LineSyntax::Spans(spans)) => match native_spans(&row.text, spans) {
                    Some(spans) => (NativeSyntaxSideState::Ready, spans),
                    None => (NativeSyntaxSideState::Unavailable, Vec::new()),
                },
            }
        }
    }
}

/// Validated spans of the row's exact text: ordered, nonempty, on character boundaries.
fn native_spans(
    text: &[u8],
    spans: &[devmil_git::diff::syntax::SyntaxSpan],
) -> Option<Vec<NativeSyntaxSpan>> {
    let text = std::str::from_utf8(text).ok()?;
    let mut cursor = 0;
    let mut out = Vec::with_capacity(spans.len());
    for span in spans {
        let (start, end) = (span.start as usize, span.end as usize);
        if start < cursor
            || end <= start
            || end > text.len()
            || !text.is_char_boundary(start)
            || !text.is_char_boundary(end)
        {
            return None;
        }
        cursor = end;
        out.push(NativeSyntaxSpan {
            start: span.start,
            end: span.end,
            kind: native_kind(span.kind),
        });
    }
    (out.len() <= SYNTAX_SPANS_PER_SIDE).then_some(out)
}

const fn native_kind(kind: SyntaxTokenKind) -> NativeSyntaxTokenKind {
    match kind {
        SyntaxTokenKind::Plain => NativeSyntaxTokenKind::Plain,
        SyntaxTokenKind::Comment => NativeSyntaxTokenKind::Comment,
        SyntaxTokenKind::Keyword => NativeSyntaxTokenKind::Keyword,
        SyntaxTokenKind::String => NativeSyntaxTokenKind::String,
        SyntaxTokenKind::Number => NativeSyntaxTokenKind::Number,
        SyntaxTokenKind::Type => NativeSyntaxTokenKind::Type,
        SyntaxTokenKind::Function => NativeSyntaxTokenKind::Function,
        SyntaxTokenKind::Variable => NativeSyntaxTokenKind::Variable,
        SyntaxTokenKind::Constant => NativeSyntaxTokenKind::Constant,
        SyntaxTokenKind::Operator => NativeSyntaxTokenKind::Operator,
        SyntaxTokenKind::Punctuation => NativeSyntaxTokenKind::Punctuation,
        SyntaxTokenKind::Attribute => NativeSyntaxTokenKind::Attribute,
        SyntaxTokenKind::Tag => NativeSyntaxTokenKind::Tag,
    }
}

/// One row exactly as the remote wire encodes it, for measuring replies without the wire
/// adapter; `wire` tests pin it to the generated codec.
pub(crate) fn row_json(row: &NativeDiffSyntaxRow) -> serde_json::Value {
    let spans = |spans: &[NativeSyntaxSpan]| {
        serde_json::Value::Array(
            spans
                .iter()
                .map(|span| {
                    serde_json::json!({
                        "start": span.start,
                        "end": span.end,
                        "kind": kind_name(span.kind),
                    })
                })
                .collect(),
        )
    };
    serde_json::json!({
        "stableId": row.stable_id,
        "oldState": state_name(row.old_state),
        "newState": state_name(row.new_state),
        "oldSpans": spans(&row.old_spans),
        "newSpans": spans(&row.new_spans),
    })
}

pub(crate) const fn state_name(state: NativeSyntaxSideState) -> &'static str {
    match state {
        NativeSyntaxSideState::Ready => "ready",
        NativeSyntaxSideState::Unsupported => "unsupported",
        NativeSyntaxSideState::InvalidEncoding => "invalidEncoding",
        NativeSyntaxSideState::TooLarge => "tooLarge",
        NativeSyntaxSideState::SourceChanged => "sourceChanged",
        NativeSyntaxSideState::LimitReached => "limitReached",
        NativeSyntaxSideState::Deferred => "deferred_",
        NativeSyntaxSideState::Unavailable => "unavailable",
    }
}

pub(crate) const fn kind_name(kind: NativeSyntaxTokenKind) -> &'static str {
    match kind {
        NativeSyntaxTokenKind::Plain => "plain",
        NativeSyntaxTokenKind::Comment => "comment",
        NativeSyntaxTokenKind::Keyword => "keyword",
        NativeSyntaxTokenKind::String => "string",
        NativeSyntaxTokenKind::Number => "number",
        NativeSyntaxTokenKind::Type => "type",
        NativeSyntaxTokenKind::Function => "function",
        NativeSyntaxTokenKind::Variable => "variable",
        NativeSyntaxTokenKind::Constant => "constant",
        NativeSyntaxTokenKind::Operator => "operator_",
        NativeSyntaxTokenKind::Punctuation => "punctuation",
        NativeSyntaxTokenKind::Attribute => "attribute",
        NativeSyntaxTokenKind::Tag => "tag",
    }
}

/// Exact sources by identity, bounded by retained bytes. Immutable blobs and digest-proven
/// worktree captures are both keyed by content identity, so a hit is always exact.
#[derive(Default)]
struct SourceCache {
    entries: HashMap<Vec<u8>, (Arc<Vec<u8>>, u64)>,
    bytes: usize,
    clock: u64,
}

type SourceRead = (Vec<u8>, DiffPath, Arc<Vec<u8>>);

impl SourceCache {
    fn read(
        &mut self,
        repository: &Repository,
        source: &SideSource,
        cancellation: &AtomicBool,
    ) -> Result<SourceRead, NativeSyntaxSideState> {
        let (key, path) = match source {
            SideSource::Absent => return Err(NativeSyntaxSideState::Unsupported),
            SideSource::Plain(state) => return Err(*state),
            SideSource::Blob { object, path } => {
                (format!("blob:{}", object.as_str()).into_bytes(), path)
            }
            SideSource::Worktree {
                path,
                bytes,
                digest,
            } => {
                if *bytes > SYNTAX_SOURCE_BYTES as u64 {
                    return Err(NativeSyntaxSideState::TooLarge);
                }
                let mut key = b"worktree:".to_vec();
                key.extend_from_slice(digest);
                (key, path)
            }
        };
        self.clock += 1;
        if let Some((bytes, used)) = self.entries.get_mut(&key) {
            *used = self.clock;
            return Ok((key, path.clone(), Arc::clone(bytes)));
        }
        let bytes = match source {
            SideSource::Blob { object, .. } => wait(
                repository.raw_blob(object.clone(), SYNTAX_SOURCE_BYTES),
                cancellation,
            )?,
            SideSource::Worktree {
                path,
                bytes,
                digest,
            } => {
                let captured = wait(
                    repository.worktree_source(path.clone(), SYNTAX_SOURCE_BYTES),
                    cancellation,
                )?;
                use sha2::{Digest, Sha256};
                if captured.len() as u64 != *bytes
                    || <[u8; 32]>::from(Sha256::digest(captured.as_slice())) != *digest
                {
                    return Err(NativeSyntaxSideState::SourceChanged);
                }
                captured
            }
            SideSource::Absent | SideSource::Plain(_) => unreachable!(),
        };
        self.insert(key.clone(), Arc::clone(&bytes));
        Ok((key, path.clone(), bytes))
    }

    fn insert(&mut self, key: Vec<u8>, bytes: Arc<Vec<u8>>) {
        let limit = crate::domain::limits::SYNTAX_RETAINED_SOURCE_BYTES;
        if bytes.len() > limit {
            return;
        }
        while self.bytes + bytes.len() > limit {
            let Some(oldest) = self
                .entries
                .iter()
                .min_by_key(|(_, (_, used))| *used)
                .map(|(key, _)| key.clone())
            else {
                break;
            };
            if let Some((removed, _)) = self.entries.remove(&oldest) {
                self.bytes -= removed.len();
            }
        }
        self.bytes += bytes.len();
        self.entries.insert(key, (bytes, self.clock));
    }
}

/// Waits for a background read, giving up on cancellation or after [`SOURCE_READ_WAIT`].
/// Dropping the ticket cancels a read that has not started.
fn wait(
    ticket: Result<devmil_git::ReadTicket<Vec<u8>>, devmil_git::RepositoryError>,
    cancellation: &AtomicBool,
) -> Result<Arc<Vec<u8>>, NativeSyntaxSideState> {
    use devmil_git::RepositoryErrorKind;
    let ticket = ticket.map_err(|error| match error.kind {
        RepositoryErrorKind::Capacity => NativeSyntaxSideState::Deferred,
        _ => NativeSyntaxSideState::Unavailable,
    })?;
    let deadline = Instant::now() + SOURCE_READ_WAIT;
    loop {
        if cancellation.load(Ordering::Acquire) {
            return Err(NativeSyntaxSideState::Deferred);
        }
        let now = Instant::now();
        if now >= deadline {
            return Err(NativeSyntaxSideState::Deferred);
        }
        if let Some(result) = ticket.recv_timeout((deadline - now).min(Duration::from_millis(25))) {
            return result.map_err(|error| match error.kind {
                RepositoryErrorKind::TooLarge => NativeSyntaxSideState::TooLarge,
                RepositoryErrorKind::Canceled | RepositoryErrorKind::Capacity => {
                    NativeSyntaxSideState::Deferred
                }
                _ => NativeSyntaxSideState::Unavailable,
            });
        }
    }
}

#[cfg(test)]
mod tests {
    /// The shipped grammar notices equal the bundled grammars' licences. Regenerate with
    /// `GITLAMA_WRITE_GRAMMAR_NOTICES=1 cargo test -p gitlama_application grammar_notices`.
    #[test]
    fn grammar_notices_are_current() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../assets/licenses/SYNTAX-GRAMMARS.md");
        let expected = devmil_git::diff::syntax::grammar_notices_markdown();
        if std::env::var_os("GITLAMA_WRITE_GRAMMAR_NOTICES").is_some() {
            std::fs::write(&path, &expected).unwrap();
        }
        let actual = std::fs::read_to_string(&path).unwrap_or_default();
        assert!(
            actual == expected,
            "assets/licenses/SYNTAX-GRAMMARS.md is stale; regenerate it"
        );
    }
}
