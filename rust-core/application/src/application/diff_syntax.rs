//! Syntax categories for rows of a session's accepted committed or working diff projection.
//!
//! A request names rows of a projection the session already published; it never names paths,
//! endpoints or text. The session lock is held only to copy the projection's references and to
//! revalidate it afterwards; sources are read and parsed by the syntax worker in between.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::application::staging::StagingPathState;
use crate::diff::NativeDiffRowKind;
use crate::diff_syntax::{
    self, blob_sources, worktree_sources, Admission, FileSources, Job, NativeDiffSyntaxOrigin,
    NativeDiffSyntaxPage, NativeDiffSyntaxRequest, NativeDiffSyntaxResult, NativeDiffSyntaxRow,
    NativeSyntaxSideState, NativeTextSyntaxPage, NativeTextSyntaxRequest, NativeTextSyntaxResult,
    Owner, RowRef, TextAdmission, TextJob, ViewKey,
};
use crate::domain::ids::SessionKey;
use crate::domain::limits::{
    PATH_BYTES, SYNTAX_PAGE_ROWS, SYNTAX_REPLY_BYTES, SYNTAX_SOURCE_BYTES, TEXT_SYNTAX_PAGE_LINES,
};
use crate::dto::*;
use devmil_git::filesystem::fingerprint::PathFingerprint;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

/// How long a request waits for the worker before answering deferred; the work continues and
/// answers the next identical request.
const SYNTAX_WAIT: Duration = Duration::from_millis(1000);

/// Encoded bytes a reply's own fields and envelope may take beside its rows.
const PAGE_ENVELOPE_BYTES: usize = 1024;

const fn failure(kind: NativeRepositoryFailureKind) -> NativeDiffSyntaxResult {
    NativeDiffSyntaxResult {
        page: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

/// What the request copied from the session under its lock.
struct Accepted {
    rows: Vec<RowRef>,
    document: Arc<devmil_git::diff::model::DiffDocument>,
    repository: Arc<devmil_git::Repository>,
    /// For an unstaged projection: the exact worktree guards of the involved paths.
    worktree: Option<HashMap<Vec<u8>, PathFingerprint>>,
}

/// Categories for up to [`SYNTAX_PAGE_ROWS`] rows of the session's accepted `origin`
/// projection. Answers fewer rows with `next_offset` when the encoded reply would exceed
/// [`SYNTAX_REPLY_BYTES`]. Optional syntax failures are side states, never failures.
#[must_use]
pub fn repository_session_diff_syntax_page(
    session_id: u64,
    generation: u64,
    request: NativeDiffSyntaxRequest,
) -> NativeDiffSyntaxResult {
    let NativeDiffSyntaxRequest {
        origin,
        diff_request_id,
        syntax_request_id,
        offset,
        maximum_rows,
    } = request;
    if diff_request_id == 0
        || syntax_request_id == 0
        || maximum_rows == 0
        || maximum_rows as usize > SYNTAX_PAGE_ROWS
    {
        return failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let Ok(start) = usize::try_from(offset) else {
        return failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    let accepted = match accepted_rows(
        session_id,
        generation,
        origin,
        diff_request_id,
        start,
        maximum_rows as usize,
    ) {
        Ok(value) => value,
        Err(kind) => return failure(kind),
    };
    let view = ViewKey {
        session_id,
        generation,
        origin,
        diff_request_id,
    };
    let rows = if accepted.rows.is_empty() {
        Arc::new(Vec::new())
    } else {
        let files = file_sources(&accepted);
        let rows = accepted.rows.clone();
        match diff_syntax::submit(
            Job {
                view,
                syntax_request_id,
                offset,
                rows: accepted.rows,
                document: accepted.document,
                files,
                repository: accepted.repository,
            },
            SYNTAX_WAIT,
        ) {
            Admission::Ready(value) => value,
            Admission::Plain(state) => Arc::new(plain_rows(&rows, state)),
            Admission::Canceled => return failure(NativeRepositoryFailureKind::Canceled),
            Admission::Conflict => return failure(NativeRepositoryFailureKind::InvalidOptions),
        }
    };
    // The projection may have been replaced while the worker ran.
    if let Err(kind) = current_projection(session_id, generation, origin, diff_request_id) {
        return failure(kind);
    }
    NativeDiffSyntaxResult {
        page: Some(bounded_page(
            origin,
            diff_request_id,
            syntax_request_id,
            offset,
            &rows,
        )),
        failure: None,
    }
}

/// Cancels one syntax request of the session. Idempotent; a cancellation that arrives before
/// its request keeps that request from running.
#[must_use]
pub fn repository_session_diff_syntax_cancel(
    session_id: u64,
    generation: u64,
    origin: NativeDiffSyntaxOrigin,
    diff_request_id: u64,
    syntax_request_id: u64,
) -> NativeRepositoryCommandResult {
    if diff_request_id == 0 || syntax_request_id == 0 {
        return NativeRepositoryCommandResult {
            accepted: false,
            failure: Some(NativeRepositoryFailure {
                kind: NativeRepositoryFailureKind::InvalidOptions,
            }),
        };
    }
    if !session_is_current(session_id, generation) {
        return NativeRepositoryCommandResult {
            accepted: false,
            failure: Some(NativeRepositoryFailure {
                kind: NativeRepositoryFailureKind::StaleGeneration,
            }),
        };
    }
    NativeRepositoryCommandResult {
        accepted: diff_syntax::cancel(
            Owner::Diff(ViewKey {
                session_id,
                generation,
                origin,
                diff_request_id,
            }),
            syntax_request_id,
        ),
        failure: None,
    }
}

/// Categories for up to [`TEXT_SYNTAX_PAGE_LINES`] lines of text the caller holds, such as a
/// conflicted file's sides or its unsaved result. The desktop parses these itself: the text
/// already crossed from the repository, so no session or host is involved. Optional syntax
/// failures are states, never failures.
#[must_use]
pub fn text_syntax_page(request: NativeTextSyntaxRequest) -> NativeTextSyntaxResult {
    let NativeTextSyntaxRequest {
        view_id,
        syntax_request_id,
        path,
        source,
        first_line,
        maximum_lines,
    } = request;
    if view_id == 0
        || syntax_request_id == 0
        || first_line == 0
        || maximum_lines == 0
        || maximum_lines as usize > TEXT_SYNTAX_PAGE_LINES
        || path.len() > PATH_BYTES
    {
        return NativeTextSyntaxResult {
            page: None,
            failure: Some(NativeRepositoryFailure {
                kind: NativeRepositoryFailureKind::InvalidOptions,
            }),
        };
    }
    let job = TextJob {
        view_id,
        syntax_request_id,
        path,
        source,
        first_line,
        maximum_lines,
    };
    if job.source.len() > SYNTAX_SOURCE_BYTES {
        return NativeTextSyntaxResult {
            page: Some(job.plain(NativeSyntaxSideState::TooLarge)),
            failure: None,
        };
    }
    let plain = job.plain(NativeSyntaxSideState::Deferred);
    let page = match diff_syntax::submit_text(job, SYNTAX_WAIT) {
        TextAdmission::Ready(page) => (*page).clone(),
        TextAdmission::Plain(state) => NativeTextSyntaxPage { state, ..plain },
        TextAdmission::Canceled | TextAdmission::Conflict => {
            return NativeTextSyntaxResult {
                page: None,
                failure: Some(NativeRepositoryFailure {
                    kind: NativeRepositoryFailureKind::Canceled,
                }),
            }
        }
    };
    NativeTextSyntaxResult {
        page: Some(page),
        failure: None,
    }
}

/// Cancels one text syntax request. Idempotent; a cancellation that arrives before its request
/// keeps that request from running.
#[must_use]
pub fn text_syntax_cancel(view_id: u64, syntax_request_id: u64) -> bool {
    view_id != 0
        && syntax_request_id != 0
        && diff_syntax::cancel(Owner::Text(view_id), syntax_request_id)
}

fn accepted_rows(
    session_id: u64,
    generation: u64,
    origin: NativeDiffSyntaxOrigin,
    diff_request_id: u64,
    start: usize,
    maximum_rows: usize,
) -> Result<Accepted, NativeRepositoryFailureKind> {
    let sessions = lock_sessions();
    let session = sessions.session(SessionKey::new(session_id, generation))?;
    let (projection, document, guards) = match origin {
        NativeDiffSyntaxOrigin::Committed => {
            let (Some(projection), Some(document)) = (
                session.diff.projection.as_ref(),
                session.diff.document.as_ref(),
            ) else {
                return Err(NativeRepositoryFailureKind::InvalidOptions);
            };
            (projection, document, None)
        }
        NativeDiffSyntaxOrigin::Working => {
            let Some(staging) = session.staging.projection.as_ref() else {
                return Err(NativeRepositoryFailureKind::InvalidOptions);
            };
            let guards =
                (staging.side == NativeStagingSide::Unstaged).then_some(&staging.worktree_states);
            (&staging.projection, &staging.document, guards)
        }
    };
    if projection.request_id != diff_request_id {
        return Err(NativeRepositoryFailureKind::StaleGeneration);
    }
    if start > projection.total_rows() {
        return Err(NativeRepositoryFailureKind::InvalidOptions);
    }
    let rows = projection
        .rows_with_files(start, maximum_rows)
        .into_iter()
        .map(|(file, row)| RowRef {
            stable_id: row.stable_id.clone(),
            kind: row.kind,
            old_line: row.old_line,
            new_line: row.new_line,
            text: row.text.clone(),
            truncated: row.text_truncated,
            file,
        })
        .collect::<Vec<_>>();
    // Only the guards of files these rows show are copied.
    let worktree = guards.map(|guards| {
        let mut copied = HashMap::new();
        for row in &rows {
            if let Some(path) = document
                .files
                .get(row.file)
                .and_then(|file| file.id.new_path.as_ref())
            {
                if let Some(StagingPathState::Fingerprint(fingerprint)) =
                    guards.get(path.as_bytes())
                {
                    copied.insert(path.as_bytes().to_vec(), fingerprint.clone());
                }
            }
        }
        copied
    });
    Ok(Accepted {
        rows,
        document: Arc::clone(document),
        repository: Arc::clone(&session.repository),
        worktree,
    })
}

fn current_projection(
    session_id: u64,
    generation: u64,
    origin: NativeDiffSyntaxOrigin,
    diff_request_id: u64,
) -> Result<(), NativeRepositoryFailureKind> {
    let sessions = lock_sessions();
    let session = sessions.session(SessionKey::new(session_id, generation))?;
    let current = match origin {
        NativeDiffSyntaxOrigin::Committed => session
            .diff
            .projection
            .as_ref()
            .map(|projection| projection.request_id),
        NativeDiffSyntaxOrigin::Working => session
            .staging
            .projection
            .as_ref()
            .map(|staging| staging.request_id),
    };
    if current == Some(diff_request_id) {
        Ok(())
    } else {
        Err(NativeRepositoryFailureKind::StaleGeneration)
    }
}

fn file_sources(accepted: &Accepted) -> HashMap<usize, FileSources> {
    let mut files = HashMap::new();
    for row in &accepted.rows {
        if files.contains_key(&row.file) {
            continue;
        }
        let Some(file) = accepted.document.files.get(row.file) else {
            continue;
        };
        let sources = match &accepted.worktree {
            None => blob_sources(file),
            Some(guards) => worktree_sources(
                file,
                file.id
                    .new_path
                    .as_ref()
                    .and_then(|path| guards.get(path.as_bytes())),
            ),
        };
        files.insert(row.file, sources);
    }
    files
}

fn line_sides(kind: NativeDiffRowKind) -> (bool, bool) {
    match kind {
        NativeDiffRowKind::Context => (true, true),
        NativeDiffRowKind::Deletion => (true, false),
        NativeDiffRowKind::Addition => (false, true),
        _ => (false, false),
    }
}

/// Rows whose text sides all show plain text for `state`.
fn plain_rows(rows: &[RowRef], state: NativeSyntaxSideState) -> Vec<NativeDiffSyntaxRow> {
    rows.iter()
        .map(|row| {
            let (old, new) = line_sides(row.kind);
            let side = |shown: bool| {
                if shown {
                    state
                } else {
                    NativeSyntaxSideState::Unsupported
                }
            };
            NativeDiffSyntaxRow {
                stable_id: row.stable_id.clone(),
                old_state: side(old),
                new_state: side(new),
                old_spans: Vec::new(),
                new_spans: Vec::new(),
            }
        })
        .collect()
}

/// Encoded bytes of one row in the remote wire's JSON, the format with the larger encoding.
fn encoded_bytes(row: &NativeDiffSyntaxRow) -> usize {
    serde_json::to_vec(&diff_syntax::row_json(row)).map_or(usize::MAX, |bytes| bytes.len() + 1)
}

/// The contiguous prefix of `rows` whose encoding fits the reply bound. A row too large on its
/// own is answered plain, so a continuation always advances.
fn bounded_page(
    origin: NativeDiffSyntaxOrigin,
    diff_request_id: u64,
    syntax_request_id: u64,
    offset: u64,
    rows: &[NativeDiffSyntaxRow],
) -> NativeDiffSyntaxPage {
    let budget = SYNTAX_REPLY_BYTES - PAGE_ENVELOPE_BYTES;
    let mut used = 0;
    let mut out = Vec::new();
    for row in rows {
        let mut row = row.clone();
        let mut size = encoded_bytes(&row);
        if size > budget {
            for (state, spans) in [
                (&mut row.old_state, &mut row.old_spans),
                (&mut row.new_state, &mut row.new_spans),
            ] {
                if !spans.is_empty() {
                    spans.clear();
                    *state = NativeSyntaxSideState::LimitReached;
                }
            }
            size = encoded_bytes(&row);
        }
        if used + size > budget && !out.is_empty() {
            break;
        }
        used += size;
        out.push(row);
    }
    let count = out.len();
    NativeDiffSyntaxPage {
        origin,
        diff_request_id,
        syntax_request_id,
        offset,
        row_count: u32::try_from(count).unwrap_or(u32::MAX),
        next_offset: (count < rows.len()).then(|| offset + count as u64),
        rows: out,
        payload_bytes: (used + PAGE_ENVELOPE_BYTES) as u64,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::activity::ActivityStore;
    use crate::application::diff::{
        repository_session_commit_diff_load, repository_session_working_diff_load,
    };
    use crate::diff::{NativeDiffLayout, NativeSyntaxTokenKind, DIFF_PAGE_CAPACITY};
    use crate::test_support::*;
    use devmil_git::RepositoryOptions;
    use std::fs;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT: AtomicU64 = AtomicU64::new(1);

    fn next_id() -> u64 {
        NEXT.fetch_add(1, Ordering::Relaxed)
    }

    struct Session {
        fixture: GitFixture,
        id: u64,
        generation: u64,
    }

    fn open(fixture: GitFixture) -> Session {
        let generation = 4_000 + next_id();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            generation,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        Session {
            fixture,
            id: session.session_id,
            generation,
        }
    }

    fn git(session: &GitFixture, arguments: &[&str]) -> String {
        String::from_utf8(transfer_git(&session.0, arguments))
            .unwrap()
            .trim()
            .to_owned()
    }

    fn request(
        origin: NativeDiffSyntaxOrigin,
        diff_request_id: u64,
        offset: u64,
        maximum_rows: u32,
    ) -> NativeDiffSyntaxRequest {
        NativeDiffSyntaxRequest {
            origin,
            diff_request_id,
            syntax_request_id: next_id(),
            offset,
            maximum_rows,
        }
    }

    /// Requests every row of a projection, following continuations; retries deferred pages
    /// once the worker had time.
    fn all_rows(
        session: &Session,
        origin: NativeDiffSyntaxOrigin,
        diff_request_id: u64,
        total: u64,
    ) -> Vec<NativeDiffSyntaxRow> {
        let mut rows = Vec::new();
        let mut offset = 0;
        while offset < total {
            let maximum = (total - offset).min(SYNTAX_PAGE_ROWS as u64) as u32;
            let mut attempt = 0;
            let page = loop {
                let result = repository_session_diff_syntax_page(
                    session.id,
                    session.generation,
                    request(origin, diff_request_id, offset, maximum),
                );
                let page = result.page.expect("syntax page");
                let deferred = page.rows.iter().any(|row| {
                    row.old_state == NativeSyntaxSideState::Deferred
                        || row.new_state == NativeSyntaxSideState::Deferred
                });
                attempt += 1;
                if !deferred || attempt > 20 {
                    break page;
                }
                std::thread::sleep(Duration::from_millis(100));
            };
            assert_eq!(page.offset, offset);
            assert_eq!(page.row_count as usize, page.rows.len());
            assert!(page.payload_bytes as usize <= SYNTAX_REPLY_BYTES);
            offset += u64::from(page.row_count);
            if let Some(next) = page.next_offset {
                assert_eq!(next, offset);
            }
            rows.extend(page.rows);
        }
        rows
    }

    fn kind_at(
        spans: &[crate::diff_syntax::NativeSyntaxSpan],
        text: &[u8],
        needle: &str,
    ) -> NativeSyntaxTokenKind {
        let at = text
            .windows(needle.len())
            .position(|window| window == needle.as_bytes())
            .unwrap() as u32;
        spans
            .iter()
            .find(|span| span.start <= at && at < span.end)
            .map_or(NativeSyntaxTokenKind::Plain, |span| span.kind)
    }

    #[test]
    fn committed_rows_use_state_from_omitted_lines_on_both_sides() {
        let fixture = GitFixture::new();
        let mut old = String::from("/* a long comment\n");
        for index in 0..300 {
            old.push_str(&format!("   line {index}\n"));
        }
        old.push_str("*/\nfn kept() {}\nfn removed() {}\n");
        let new = old
            .replace("   line 299\n", "   changed line\n")
            .replace("fn removed() {}\n", "fn added() { let x = 1; }\n");
        fs::write(fixture.0.join("lib.rs"), &old).unwrap();
        git(&fixture, &["add", "lib.rs"]);
        git(&fixture, &["commit", "-qm", "old"]);
        let parent = git(&fixture, &["rev-parse", "HEAD"]);
        fs::write(fixture.0.join("lib.rs"), &new).unwrap();
        git(&fixture, &["commit", "-qam", "new"]);
        let commit = git(&fixture, &["rev-parse", "HEAD"]);
        let session = open(fixture);
        let loaded = repository_session_commit_diff_load(
            session.id,
            session.generation,
            NativeCommitDiffOptions {
                commit,
                first_parent: Some(parent),
                old_path: None,
                new_path: None,
                context_lines: 3,
                whitespace: NativeDiffWhitespace::Preserve,
                layout: NativeDiffLayout::Unified,
                maximum_rows: DIFF_PAGE_CAPACITY as u32,
                force_text: false,
            },
        )
        .page
        .unwrap();
        let rows = all_rows(
            &session,
            NativeDiffSyntaxOrigin::Committed,
            loaded.request_id,
            loaded.total_rows,
        );
        assert_eq!(rows.len(), loaded.rows.len());
        for (row, syntax) in loaded.rows.iter().zip(&rows) {
            assert_eq!(row.stable_id, syntax.stable_id);
            let text = String::from_utf8_lossy(&row.text);
            match row.kind {
                NativeDiffRowKind::File | NativeDiffRowKind::Hunk => {
                    assert_eq!(syntax.old_state, NativeSyntaxSideState::Unsupported);
                    assert_eq!(syntax.new_state, NativeSyntaxSideState::Unsupported);
                }
                NativeDiffRowKind::Deletion if text.contains("line 299") => {
                    // The comment opened 300 lines before the hunk.
                    assert_eq!(syntax.old_state, NativeSyntaxSideState::Ready);
                    assert_eq!(
                        kind_at(&syntax.old_spans, &row.text, "line"),
                        NativeSyntaxTokenKind::Comment
                    );
                    assert!(syntax.new_spans.is_empty());
                }
                NativeDiffRowKind::Addition if text.contains("added") => {
                    assert_eq!(syntax.new_state, NativeSyntaxSideState::Ready);
                    assert_eq!(
                        kind_at(&syntax.new_spans, &row.text, "fn"),
                        NativeSyntaxTokenKind::Keyword
                    );
                    assert_eq!(
                        kind_at(&syntax.new_spans, &row.text, "1"),
                        NativeSyntaxTokenKind::Number
                    );
                    assert_eq!(syntax.old_state, NativeSyntaxSideState::Unsupported);
                }
                NativeDiffRowKind::Context if text.contains("kept") => {
                    assert_eq!(syntax.old_state, NativeSyntaxSideState::Ready);
                    assert_eq!(syntax.new_state, NativeSyntaxSideState::Ready);
                    assert_eq!(syntax.old_spans, syntax.new_spans);
                }
                _ => {}
            }
        }
        // A replaced projection retires the old identity.
        let stale = repository_session_diff_syntax_page(
            session.id,
            session.generation,
            request(
                NativeDiffSyntaxOrigin::Committed,
                loaded.request_id + 1,
                0,
                4,
            ),
        );
        assert_eq!(
            stale.failure.unwrap().kind,
            NativeRepositoryFailureKind::StaleGeneration
        );
        drop(session.fixture);
    }

    #[test]
    fn working_rows_are_proven_against_the_accepted_worktree_guard() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("app.py"), "def a():\n    return 1\n").unwrap();
        git(&fixture, &["add", "app.py"]);
        git(&fixture, &["commit", "-qm", "base"]);
        fs::write(fixture.0.join("app.py"), "def a():\n    return 2\n").unwrap();
        fs::write(fixture.0.join("new.py"), "import os\n").unwrap();
        let session = open(fixture);
        let load = || {
            repository_session_working_diff_load(
                session.id,
                session.generation,
                NativeWorkingDiffOptions {
                    side: NativeStagingSide::Unstaged,
                    old_path: None,
                    new_path: None,
                    context_lines: 3,
                    whitespace: NativeDiffWhitespace::Preserve,
                    layout: NativeDiffLayout::Unified,
                    maximum_rows: DIFF_PAGE_CAPACITY as u32,
                    force_text: false,
                },
            )
            .page
            .unwrap()
        };
        let loaded = load();
        let rows = all_rows(
            &session,
            NativeDiffSyntaxOrigin::Working,
            loaded.request_id,
            loaded.total_rows,
        );
        let find = |needle: &str| {
            let index = loaded
                .rows
                .iter()
                .position(|row| row.text == needle.as_bytes())
                .unwrap();
            (&loaded.rows[index], &rows[index])
        };
        let (row, syntax) = find("    return 2");
        assert_eq!(syntax.new_state, NativeSyntaxSideState::Ready);
        assert_eq!(
            kind_at(&syntax.new_spans, &row.text, "return"),
            NativeSyntaxTokenKind::Keyword
        );
        let (row, syntax) = find("    return 1");
        assert_eq!(syntax.old_state, NativeSyntaxSideState::Ready);
        assert_eq!(
            kind_at(&syntax.old_spans, &row.text, "1"),
            NativeSyntaxTokenKind::Number
        );
        // An untracked file opens on its own; its only side is the worktree file.
        let untracked = repository_session_working_diff_load(
            session.id,
            session.generation,
            NativeWorkingDiffOptions {
                side: NativeStagingSide::Unstaged,
                old_path: None,
                new_path: Some(b"new.py".to_vec()),
                context_lines: 3,
                whitespace: NativeDiffWhitespace::Preserve,
                layout: NativeDiffLayout::Unified,
                maximum_rows: DIFF_PAGE_CAPACITY as u32,
                force_text: false,
            },
        )
        .page
        .unwrap();
        let syntax = all_rows(
            &session,
            NativeDiffSyntaxOrigin::Working,
            untracked.request_id,
            untracked.total_rows,
        );
        let index = untracked
            .rows
            .iter()
            .position(|row| row.text == b"import os")
            .unwrap();
        assert_eq!(syntax[index].new_state, NativeSyntaxSideState::Ready);
        assert_eq!(
            kind_at(
                &syntax[index].new_spans,
                &untracked.rows[index].text,
                "import"
            ),
            NativeSyntaxTokenKind::Keyword
        );

        // An equal-size edit after the diff was accepted is drift, not colours. (A source
        // already proven by the accepted digest may still answer from the cache: its bytes
        // are exactly the accepted ones.)
        fs::write(
            session.fixture.0.join("app.py"),
            "def a():\n    return 2\n# x\n",
        )
        .unwrap();
        let loaded = load();
        fs::write(
            session.fixture.0.join("app.py"),
            "def a():\n    return 2\n# y\n",
        )
        .unwrap();
        let rows = all_rows(
            &session,
            NativeDiffSyntaxOrigin::Working,
            loaded.request_id,
            loaded.total_rows,
        );
        let index = loaded
            .rows
            .iter()
            .position(|row| row.text == b"    return 2")
            .unwrap();
        assert_eq!(rows[index].new_state, NativeSyntaxSideState::SourceChanged);
        assert!(rows[index].new_spans.is_empty());
    }

    #[test]
    fn requests_are_validated_cancelled_and_never_conflated() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("a.rs"), "fn a() {}\n").unwrap();
        git(&fixture, &["add", "a.rs"]);
        git(&fixture, &["commit", "-qm", "base"]);
        fs::write(fixture.0.join("a.rs"), "fn b() {}\n").unwrap();
        let session = open(fixture);
        let loaded = repository_session_working_diff_load(
            session.id,
            session.generation,
            NativeWorkingDiffOptions {
                side: NativeStagingSide::Unstaged,
                old_path: None,
                new_path: None,
                context_lines: 3,
                whitespace: NativeDiffWhitespace::Preserve,
                layout: NativeDiffLayout::Unified,
                maximum_rows: DIFF_PAGE_CAPACITY as u32,
                force_text: false,
            },
        )
        .page
        .unwrap();
        let working = NativeDiffSyntaxOrigin::Working;
        let invalid = |request: NativeDiffSyntaxRequest| {
            repository_session_diff_syntax_page(session.id, session.generation, request)
                .failure
                .unwrap()
                .kind
        };
        let valid = request(working, loaded.request_id, 0, 4);
        for broken in [
            NativeDiffSyntaxRequest {
                syntax_request_id: 0,
                ..valid
            },
            NativeDiffSyntaxRequest {
                diff_request_id: 0,
                ..valid
            },
            NativeDiffSyntaxRequest {
                maximum_rows: 0,
                ..valid
            },
            NativeDiffSyntaxRequest {
                maximum_rows: SYNTAX_PAGE_ROWS as u32 + 1,
                ..valid
            },
            NativeDiffSyntaxRequest {
                offset: loaded.total_rows + 1,
                ..valid
            },
        ] {
            assert_eq!(invalid(broken), NativeRepositoryFailureKind::InvalidOptions);
        }
        // The committed projection was never loaded in this session.
        assert_eq!(
            invalid(request(
                NativeDiffSyntaxOrigin::Committed,
                loaded.request_id,
                0,
                4
            )),
            NativeRepositoryFailureKind::InvalidOptions
        );
        assert_eq!(
            invalid(NativeDiffSyntaxRequest {
                diff_request_id: loaded.request_id + 7,
                ..valid
            }),
            NativeRepositoryFailureKind::StaleGeneration
        );
        // Cancelling first keeps the request from ever running; cancel is idempotent.
        let early = request(working, loaded.request_id, 0, 3);
        for _ in 0..2 {
            let cancelled = repository_session_diff_syntax_cancel(
                session.id,
                session.generation,
                working,
                loaded.request_id,
                early.syntax_request_id,
            );
            assert!(cancelled.accepted && cancelled.failure.is_none());
        }
        assert_eq!(invalid(early), NativeRepositoryFailureKind::Canceled);
        assert_eq!(
            repository_session_diff_syntax_cancel(
                session.id,
                session.generation + 1,
                working,
                loaded.request_id,
                9,
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::StaleGeneration
        );
        // An empty range past the last row answers no rows.
        let end = repository_session_diff_syntax_page(
            session.id,
            session.generation,
            request(working, loaded.request_id, loaded.total_rows, 4),
        )
        .page
        .unwrap();
        assert!(end.rows.is_empty() && end.next_offset.is_none());
    }

    #[test]
    fn replies_stop_at_the_encoded_bound_and_always_advance() {
        let span = |index: u32| crate::diff_syntax::NativeSyntaxSpan {
            start: index * 2,
            end: index * 2 + 1,
            kind: NativeSyntaxTokenKind::Keyword,
        };
        let row = |id: usize, spans: u32| NativeDiffSyntaxRow {
            stable_id: format!("l:{id:0>40}"),
            old_state: NativeSyntaxSideState::Ready,
            new_state: NativeSyntaxSideState::Ready,
            old_spans: (0..spans).map(span).collect(),
            new_spans: (0..spans).map(span).collect(),
        };
        let rows = (0..32).map(|id| row(id, 64)).collect::<Vec<_>>();
        let page = bounded_page(NativeDiffSyntaxOrigin::Committed, 1, 2, 64, &rows);
        assert!(page.rows.len() < rows.len());
        assert_eq!(page.next_offset, Some(64 + page.rows.len() as u64));
        let encoded = page.rows.iter().map(encoded_bytes).sum::<usize>();
        assert!(encoded + PAGE_ENVELOPE_BYTES <= SYNTAX_REPLY_BYTES);

        // A row that cannot fit alone is answered plain, so a continuation advances.
        let huge = vec![row(0, 2_000)];
        let page = bounded_page(NativeDiffSyntaxOrigin::Working, 1, 2, 0, &huge);
        assert_eq!(page.rows.len(), 1);
        assert_eq!(page.rows[0].old_state, NativeSyntaxSideState::LimitReached);
        assert!(page.rows[0].new_spans.is_empty());
        assert_eq!(page.next_offset, None);
    }

    fn text_request(
        view_id: u64,
        path: &str,
        source: &str,
        first_line: u32,
        maximum_lines: u32,
    ) -> NativeTextSyntaxRequest {
        NativeTextSyntaxRequest {
            view_id,
            syntax_request_id: next_id(),
            path: path.as_bytes().to_vec(),
            source: source.as_bytes().to_vec(),
            first_line,
            maximum_lines,
        }
    }

    /// The page for `request`, asked again while the worker answers deferred.
    fn text_page(request: &NativeTextSyntaxRequest) -> NativeTextSyntaxPage {
        for _ in 0..20 {
            let page = text_syntax_page(NativeTextSyntaxRequest {
                syntax_request_id: next_id(),
                ..request.clone()
            })
            .page
            .expect("text syntax page");
            let deferred = page.state == NativeSyntaxSideState::Deferred
                || page
                    .lines
                    .iter()
                    .any(|line| line.state == NativeSyntaxSideState::Deferred);
            if !deferred {
                return page;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        panic!("text syntax stayed deferred");
    }

    fn text_kind_at(
        page: &NativeTextSyntaxPage,
        source: &str,
        line: u32,
        needle: &str,
    ) -> Option<NativeSyntaxTokenKind> {
        let text = source.lines().nth(line as usize - 1).unwrap();
        let start = u32::try_from(text.find(needle).unwrap()).unwrap();
        let entry = &page.lines[(line - page.first_line) as usize];
        assert_eq!(entry.state, NativeSyntaxSideState::Ready);
        entry
            .spans
            .iter()
            .find(|span| span.start <= start && start < span.end)
            .map(|span| span.kind)
    }

    #[test]
    fn caller_text_lines_keep_state_from_lines_before_the_request() {
        let mut source = String::from("/* opened far above\n");
        for index in 0..300 {
            source.push_str(&format!("still comment {index}\n"));
        }
        source.push_str("*/\nfn kept() { let x = \"s\"; }\r\nlast_line_without_end");
        let view = next_id();
        let page = text_page(&text_request(view, "src/conflicted.rs", &source, 290, 16));
        assert_eq!(page.view_id, view);
        assert_eq!(page.state, NativeSyntaxSideState::Ready);
        assert_eq!(page.first_line, 290);
        // Lines 290..=305 exist: 301 comment lines, the closer, the function and the last line.
        assert_eq!(page.lines.len(), 15);
        assert_eq!(
            text_kind_at(&page, &source, 300, "still"),
            Some(NativeSyntaxTokenKind::Comment)
        );
        assert_eq!(
            text_kind_at(&page, &source, 303, "fn"),
            Some(NativeSyntaxTokenKind::Keyword)
        );
        assert_eq!(
            text_kind_at(&page, &source, 303, "\"s\""),
            Some(NativeSyntaxTokenKind::String)
        );
        // A CRLF line's spans stay inside its content.
        let crlf = &page.lines[(303 - 290) as usize];
        let content = "fn kept() { let x = \"s\"; }".len() as u32;
        assert!(crlf.spans.iter().all(|span| span.end <= content));

        // Past the end of the text: no lines, nothing to colour.
        let beyond = text_page(&text_request(view, "src/conflicted.rs", &source, 400, 8));
        assert_eq!(beyond.state, NativeSyntaxSideState::Ready);
        assert!(beyond.lines.is_empty());
    }

    #[test]
    fn caller_text_spans_are_utf16_offsets_of_each_line() {
        // "é" is two UTF-8 bytes but one UTF-16 unit; "😀" is four bytes and two units.
        let source = "let s = \"é😀\"; let n = 1;\n";
        let page = text_page(&text_request(next_id(), "a.js", source, 1, 1));
        let line = &page.lines[0];
        let text = source.trim_end_matches('\n');
        let utf16 = text.encode_utf16().collect::<Vec<_>>();
        let number = text.find('1').unwrap();
        let number_unit = text[..number].encode_utf16().count() as u32;
        let span = line
            .spans
            .iter()
            .find(|span| span.start <= number_unit && number_unit < span.end)
            .expect("number span");
        assert_eq!(span.kind, NativeSyntaxTokenKind::Number);
        assert!(line
            .spans
            .iter()
            .all(|span| span.end as usize <= utf16.len()));
        let string = line
            .spans
            .iter()
            .find(|span| span.kind == NativeSyntaxTokenKind::String)
            .expect("string span");
        assert_eq!(
            String::from_utf16(&utf16[string.start as usize..string.end as usize]).unwrap(),
            "\"é😀\""
        );
    }

    #[test]
    fn caller_text_without_grammar_or_valid_text_stays_plain() {
        let view = next_id();
        let unknown = text_page(&text_request(
            view,
            "notes.unknown-kind",
            "just words\n",
            1,
            4,
        ));
        assert_eq!(unknown.state, NativeSyntaxSideState::Unsupported);
        assert!(unknown.lines.is_empty());

        let mut invalid = text_request(view, "src/a.rs", "", 1, 4);
        invalid.source = b"fn a() {}\n\xff\xfe\n".to_vec();
        assert_eq!(
            text_page(&invalid).state,
            NativeSyntaxSideState::InvalidEncoding
        );

        let mut huge = text_request(view, "src/a.rs", "", 1, 4);
        huge.source = vec![b'a'; SYNTAX_SOURCE_BYTES + 1];
        let page = text_syntax_page(huge).page.unwrap();
        assert_eq!(page.state, NativeSyntaxSideState::TooLarge);
    }

    #[test]
    fn caller_text_requests_are_validated_and_cancellable() {
        let invalid = |request: NativeTextSyntaxRequest| {
            let result = text_syntax_page(request);
            assert!(result.page.is_none());
            assert_eq!(
                result.failure.map(|failure| failure.kind),
                Some(NativeRepositoryFailureKind::InvalidOptions)
            );
        };
        let valid = text_request(next_id(), "a.rs", "fn a() {}\n", 1, 1);
        invalid(NativeTextSyntaxRequest {
            view_id: 0,
            ..valid.clone()
        });
        invalid(NativeTextSyntaxRequest {
            syntax_request_id: 0,
            ..valid.clone()
        });
        invalid(NativeTextSyntaxRequest {
            first_line: 0,
            ..valid.clone()
        });
        invalid(NativeTextSyntaxRequest {
            maximum_lines: 0,
            ..valid.clone()
        });
        invalid(NativeTextSyntaxRequest {
            maximum_lines: TEXT_SYNTAX_PAGE_LINES as u32 + 1,
            ..valid.clone()
        });
        invalid(NativeTextSyntaxRequest {
            path: vec![b'a'; PATH_BYTES + 1],
            ..valid.clone()
        });
        assert!(!text_syntax_cancel(0, 1));
        assert!(!text_syntax_cancel(1, 0));

        // A cancellation that arrives first keeps its request from running.
        assert!(text_syntax_cancel(valid.view_id, valid.syntax_request_id));
        let result = text_syntax_page(valid.clone());
        assert!(result.page.is_none());
        assert_eq!(
            result.failure.map(|failure| failure.kind),
            Some(NativeRepositoryFailureKind::Canceled)
        );
        // Another request of the same view still runs.
        let page = text_page(&valid);
        assert_eq!(page.state, NativeSyntaxSideState::Ready);
        assert_eq!(page.lines.len(), 1);
    }
}
