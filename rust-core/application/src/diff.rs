//! Bounded diff projection used by Flutter and byte-exact partial-patch proofs.
pub use gitlama_contract::diff::*;

use devmil_git::diff::model::{
    ByteSpan, ContextLines, DiffDocument, DiffFallback, DiffFile, DiffLayout, DiffLineId,
    DiffLineOrigin, FileChangeKind, LineEnding, LineSelection, SyntaxAvailability,
};
use devmil_git::diff::{BytePatchBuilder, DiffError, PatchConstructionRequest};
use std::collections::HashSet;

pub const DIFF_PAGE_CAPACITY: usize = 512;
pub const DIFF_TEXT_BYTES_PER_ROW: usize = 16 * 1024;

#[derive(Clone, Debug)]
pub struct DiffProjection {
    pub request_id: u64,
    pub layout: NativeDiffLayout,
    rows: Vec<NativeDiffRow>,
    /// The document file each row belongs to, by row.
    row_files: Vec<u32>,
}

impl DiffProjection {
    #[must_use]
    pub fn from_document(request_id: u64, document: &DiffDocument) -> Self {
        let layout = match document.layout {
            DiffLayout::SideBySide => NativeDiffLayout::SideBySide,
            DiffLayout::Unified | DiffLayout::ImageSideBySide => NativeDiffLayout::Unified,
        };
        let mut rows = Vec::new();
        let mut row_files = Vec::new();
        for (file_index, file) in document.files.iter().enumerate() {
            project_file(&mut rows, file_index, file);
            row_files.resize(rows.len(), u32::try_from(file_index).unwrap_or(u32::MAX));
        }
        let mut open_file: Option<usize> = None;
        for index in 0..rows.len() {
            if rows[index].kind == NativeDiffRowKind::File {
                if let Some(start) = open_file {
                    rows[start].section_end = u32::try_from(index).ok();
                }
                open_file = Some(index);
            }
        }
        if let Some(start) = open_file {
            rows[start].section_end = u32::try_from(rows.len()).ok();
        }
        Self {
            request_id,
            layout,
            rows,
            row_files,
        }
    }

    /// Rows `offset..offset + maximum_rows` with the index of the document file each belongs to.
    #[must_use]
    pub fn rows_with_files(
        &self,
        offset: usize,
        maximum_rows: usize,
    ) -> Vec<(usize, &NativeDiffRow)> {
        let end = offset.saturating_add(maximum_rows).min(self.rows.len());
        (offset.min(end)..end)
            .map(|index| (self.row_files[index] as usize, &self.rows[index]))
            .collect()
    }

    #[must_use]
    pub fn total_rows(&self) -> usize {
        self.rows.len()
    }

    #[must_use]
    pub fn page(&self, offset: usize, maximum_rows: usize) -> NativeDiffPage {
        let end = offset.saturating_add(maximum_rows).min(self.rows.len());
        let rows = if offset < end {
            self.rows[offset..end].to_vec()
        } else {
            Vec::new()
        };
        let payload_bytes = rows.iter().fold(0_u64, |total, row| {
            total
                .saturating_add(row.stable_id.len() as u64)
                .saturating_add(row.text.len() as u64)
                .saturating_add(32)
        });
        NativeDiffPage {
            request_id: self.request_id,
            layout: self.layout,
            total_rows: self.rows.len() as u64,
            offset: offset as u64,
            rows,
            payload_bytes,
        }
    }

    #[must_use]
    pub fn search(
        &self,
        query: &[u8],
        case_sensitive: bool,
        maximum_matches: usize,
    ) -> (Vec<u32>, u64, bool) {
        let query = if case_sensitive {
            query.to_vec()
        } else {
            query.iter().map(u8::to_ascii_lowercase).collect()
        };
        let mut matches = Vec::new();
        let mut total = 0_u64;
        for (index, row) in self.rows.iter().enumerate() {
            let found = if case_sensitive {
                contains_bytes(&row.text, &query)
            } else {
                contains_ascii_case_insensitive(&row.text, &query)
            };
            if found {
                total = total.saturating_add(1);
                if matches.len() < maximum_matches {
                    if let Ok(index) = u32::try_from(index) {
                        matches.push(index);
                    }
                }
            }
        }
        let truncated = total > matches.len() as u64;
        (matches, total, truncated)
    }

    #[must_use]
    pub fn hunk_positions(&self, maximum_positions: usize) -> (Vec<u32>, u64, bool) {
        let mut positions = Vec::new();
        let mut total = 0_u64;
        for (index, row) in self.rows.iter().enumerate() {
            if row.kind == NativeDiffRowKind::Hunk {
                total = total.saturating_add(1);
                if positions.len() < maximum_positions {
                    if let Ok(index) = u32::try_from(index) {
                        positions.push(index);
                    }
                }
            }
        }
        let truncated = total > positions.len() as u64;
        (positions, total, truncated)
    }

    /// Builds a bounded inert textual view for optional presentation renderers.
    /// Stable staging identities remain in this projection and never cross the renderer boundary.
    #[must_use]
    pub fn renderer_input(&self, maximum_bytes: usize) -> Option<Vec<u8>> {
        let mut output = Vec::new();
        for row in &self.rows {
            let prefix = match row.kind {
                NativeDiffRowKind::Addition => b"+".as_slice(),
                NativeDiffRowKind::Deletion => b"-".as_slice(),
                NativeDiffRowKind::Hunk => b"@@ ".as_slice(),
                NativeDiffRowKind::File => b"file ".as_slice(),
                _ => b" ".as_slice(),
            };
            if output
                .len()
                .saturating_add(prefix.len())
                .saturating_add(row.text.len())
                .saturating_add(1)
                > maximum_bytes
            {
                return None;
            }
            output.extend_from_slice(prefix);
            output.extend_from_slice(&row.text);
            output.push(b'\n');
        }
        Some(output)
    }
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty() && haystack.windows(needle.len()).any(|value| value == needle)
}

fn contains_ascii_case_insensitive(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack.windows(needle.len()).any(|value| {
            value
                .iter()
                .map(u8::to_ascii_lowercase)
                .eq(needle.iter().copied())
        })
}

fn project_file(rows: &mut Vec<NativeDiffRow>, file_index: usize, file: &DiffFile) {
    let display_path = file
        .id
        .new_path
        .as_ref()
        .or(file.id.old_path.as_ref())
        .map_or_else(Vec::new, |path| path.as_bytes().to_vec());
    let file_identity = file_identity(file, file_index);
    rows.push(row(
        format!("f:{file_identity}"),
        NativeDiffRowKind::File,
        (None, None),
        display_path,
        false,
        file,
        &[],
    ));
    if let Some(fallback) = &file.fallback {
        let (kind, text) = match fallback {
            DiffFallback::Binary { byte_count } => (
                NativeDiffRowKind::Binary,
                byte_count.map_or_else(
                    || b"binary".to_vec(),
                    |value| value.to_string().into_bytes(),
                ),
            ),
            DiffFallback::TooLarge {
                byte_count,
                line_count,
                preview_line_limit,
            } => (
                NativeDiffRowKind::TooLarge,
                format!("{byte_count}:{line_count}:{preview_line_limit}").into_bytes(),
            ),
            DiffFallback::ImageDeferred => (NativeDiffRowKind::Image, b"image".to_vec()),
        };
        rows.push(row(
            format!("f:{file_identity}:fallback"),
            kind,
            (None, None),
            text,
            false,
            file,
            &[],
        ));
        return;
    }
    if file.hunks.is_empty()
        && matches!(
            file.kind,
            FileChangeKind::ModeChanged | FileChangeKind::Submodule
        )
    {
        let (kind, text) = match file.kind {
            FileChangeKind::ModeChanged => (
                NativeDiffRowKind::ModeOnly,
                format!(
                    "{:06o} → {:06o}",
                    file.old_mode.map_or(0, |value| value.value()),
                    file.new_mode.map_or(0, |value| value.value())
                )
                .into_bytes(),
            ),
            FileChangeKind::Submodule => (NativeDiffRowKind::Submodule, b"submodule".to_vec()),
            _ => unreachable!(),
        };
        rows.push(row(
            format!("f:{file_identity}:metadata"),
            kind,
            (None, None),
            text,
            false,
            file,
            &[],
        ));
        return;
    }
    for hunk in &file.hunks {
        let derived_intra_line = devmil_git::diff::intra_line::derive_intra_line_spans(&hunk.lines);
        rows.push(row(
            hunk_identity(
                &file_identity,
                hunk.id.old_start,
                hunk.id.new_start,
                hunk.id.ordinal,
            ),
            NativeDiffRowKind::Hunk,
            (Some(hunk.id.old_start), Some(hunk.id.new_start)),
            hunk.section.clone(),
            false,
            file,
            &[],
        ));
        for (line_index, line) in hunk.lines.iter().enumerate() {
            let kind = match line.origin {
                DiffLineOrigin::Context => NativeDiffRowKind::Context,
                DiffLineOrigin::Addition => NativeDiffRowKind::Addition,
                DiffLineOrigin::Deletion => NativeDiffRowKind::Deletion,
            };
            let intra_line = if line.intra_line.is_empty() {
                &derived_intra_line[line_index]
            } else {
                &line.intra_line
            };
            rows.push(row(
                line_identity(&line.id),
                kind,
                (line.id.old_line, line.id.new_line),
                line.source.clone(),
                line.is_change(),
                file,
                intra_line,
            ));
            if line.no_newline_marker || line.ending == LineEnding::None {
                rows.push(row(
                    format!("{}:nonewline", line_identity(&line.id)),
                    NativeDiffRowKind::NoNewline,
                    (None, None),
                    b"No newline at end of file".to_vec(),
                    false,
                    file,
                    &[],
                ));
            }
        }
    }
}

/// Resolves projected hunk and line identities back to the shared byte-preserving selection.
/// Unknown or cross-file identities are rejected instead of being silently ignored.
pub fn selection_for_rows(
    file: &DiffFile,
    file_index: usize,
    row_ids: &[String],
) -> Option<LineSelection> {
    if row_ids.is_empty() {
        return None;
    }
    let requested = row_ids.iter().map(String::as_str).collect::<HashSet<_>>();
    if requested.len() != row_ids.len() {
        return None;
    }
    let file_identity = file_identity(file, file_index);
    let mut matched = HashSet::new();
    let mut selected = Vec::new();
    for hunk in &file.hunks {
        let hunk_id = hunk_identity(
            &file_identity,
            hunk.id.old_start,
            hunk.id.new_start,
            hunk.id.ordinal,
        );
        if requested.contains(hunk_id.as_str()) {
            matched.insert(hunk_id);
            selected.extend(
                hunk.lines
                    .iter()
                    .filter(|line| line.is_change())
                    .map(|line| line.id.clone()),
            );
        }
        for line in &hunk.lines {
            let line_id = line_identity(&line.id);
            if requested.contains(line_id.as_str()) {
                matched.insert(line_id);
                if line.is_change() {
                    selected.push(line.id.clone());
                }
            }
        }
    }
    (matched.len() == requested.len() && !selected.is_empty()).then(|| LineSelection::new(selected))
}

/// A forward unified patch of the change lines among [row_ids], across every
/// file of [document]. Context rows are accepted and stay context; a file
/// whose selected rows hold no change line is left out. Empty when nothing
/// is selected.
pub fn selection_patch(document: &DiffDocument, row_ids: &[String]) -> Result<Vec<u8>, DiffError> {
    let mut patch = Vec::new();
    for (index, file) in document.files.iter().enumerate() {
        let known = file_row_ids(file, index);
        let selected = row_ids
            .iter()
            .filter(|id| known.contains(id.as_str()))
            .cloned()
            .collect::<Vec<_>>();
        if selected.is_empty() {
            continue;
        }
        let Some(selection) = selection_for_rows(file, index, &selected) else {
            continue;
        };
        patch.extend_from_slice(
            &BytePatchBuilder
                .construct_patch(&PatchConstructionRequest {
                    file: file.clone(),
                    selection,
                    context: ContextLines::new(3).expect("constant context is valid"),
                    reverse: false,
                })?
                .bytes,
        );
    }
    Ok(patch)
}

/// The stable row identities that address one file's hunks and lines.
fn file_row_ids(file: &DiffFile, file_index: usize) -> HashSet<String> {
    let file_identity = file_identity(file, file_index);
    let mut ids = HashSet::new();
    for hunk in &file.hunks {
        ids.insert(hunk_identity(
            &file_identity,
            hunk.id.old_start,
            hunk.id.new_start,
            hunk.id.ordinal,
        ));
        ids.extend(hunk.lines.iter().map(|line| line_identity(&line.id)));
    }
    ids
}

fn hunk_identity(file: &str, old_start: u32, new_start: u32, ordinal: u32) -> String {
    format!("f:{file}:h:{old_start}:{new_start}:{ordinal}")
}

fn row(
    stable_id: String,
    kind: NativeDiffRowKind,
    line_numbers: (Option<u32>, Option<u32>),
    mut text: Vec<u8>,
    selectable: bool,
    file: &DiffFile,
    intra_line: &[ByteSpan],
) -> NativeDiffRow {
    let text_truncated = text.len() > DIFF_TEXT_BYTES_PER_ROW;
    text.truncate(DIFF_TEXT_BYTES_PER_ROW);
    NativeDiffRow {
        stable_id,
        kind,
        old_line: line_numbers.0,
        new_line: line_numbers.1,
        text,
        text_truncated,
        selectable,
        intra_line: intra_line
            .iter()
            .take(6)
            .filter_map(|span| {
                Some(NativeDiffSpan {
                    start: u32::try_from(span.start).ok()?,
                    end: u32::try_from(span.end).ok()?,
                })
            })
            .collect(),
        syntax: match &file.syntax {
            SyntaxAvailability::Available(value) => Some(value.clone()),
            SyntaxAvailability::Unavailable => None,
        },
        file_kind: Some(native_file_kind(&file.kind)),
        old_path: file
            .id
            .old_path
            .as_ref()
            .map(|path| path.as_bytes().to_vec()),
        new_path: file
            .id
            .new_path
            .as_ref()
            .map(|path| path.as_bytes().to_vec()),
        section_end: None,
    }
}

fn file_identity(file: &DiffFile, occurrence: usize) -> String {
    format!(
        "{}:{}:{occurrence}",
        file.id
            .old_path
            .as_ref()
            .map_or_else(|| "-".into(), |path| hex(path.as_bytes())),
        file.id
            .new_path
            .as_ref()
            .map_or_else(|| "-".into(), |path| hex(path.as_bytes()))
    )
}

fn line_identity(id: &DiffLineId) -> String {
    let new_line = id
        .new_line
        .map_or_else(|| "-".into(), |value| value.to_string());
    format!(
        "l:{}:{}:{}:{}:{}:{}:{new_line}:{}",
        id.hunk
            .file
            .old_path
            .as_ref()
            .map_or_else(|| "-".into(), |path| hex(path.as_bytes())),
        id.hunk
            .file
            .new_path
            .as_ref()
            .map_or_else(|| "-".into(), |path| hex(path.as_bytes())),
        id.hunk.old_start,
        id.hunk.new_start,
        id.hunk.ordinal,
        id.old_line
            .map_or_else(|| "-".into(), |value| value.to_string()),
        id.occurrence
    )
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write as _;

    let mut value = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        let _ = write!(value, "{byte:02x}");
    }
    value
}

const fn native_file_kind(kind: &FileChangeKind) -> NativeDiffFileKind {
    match kind {
        FileChangeKind::Modified => NativeDiffFileKind::Modified,
        FileChangeKind::Added => NativeDiffFileKind::Added,
        FileChangeKind::Deleted => NativeDiffFileKind::Deleted,
        FileChangeKind::Renamed { .. } => NativeDiffFileKind::Renamed,
        FileChangeKind::Copied { .. } => NativeDiffFileKind::Copied,
        FileChangeKind::ModeChanged => NativeDiffFileKind::ModeChanged,
        FileChangeKind::TypeChanged => NativeDiffFileKind::TypeChanged,
        FileChangeKind::Binary => NativeDiffFileKind::Binary,
        FileChangeKind::Image => NativeDiffFileKind::Image,
        FileChangeKind::Submodule => NativeDiffFileKind::Submodule,
        FileChangeKind::Conflict => NativeDiffFileKind::Conflict,
        FileChangeKind::Untracked => NativeDiffFileKind::Untracked,
    }
}

#[must_use]
pub const fn change_kind_name(kind: &FileChangeKind) -> &'static str {
    match kind {
        FileChangeKind::Modified => "modified",
        FileChangeKind::Added => "added",
        FileChangeKind::Deleted => "deleted",
        FileChangeKind::Renamed { .. } => "renamed",
        FileChangeKind::Copied { .. } => "copied",
        FileChangeKind::ModeChanged => "mode-changed",
        FileChangeKind::TypeChanged => "type-changed",
        FileChangeKind::Binary => "binary",
        FileChangeKind::Image => "image",
        FileChangeKind::Submodule => "submodule",
        FileChangeKind::Conflict => "conflict",
        FileChangeKind::Untracked => "untracked",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use devmil_git::diff::intra_line::replacement_spans;
    use devmil_git::diff::model::{ContextLines, DiffWhitespacePolicy, LineSelection};
    use devmil_git::diff::{BytePatchBuilder, PatchConstructionRequest};
    use devmil_git::loading::commit::{CommitDiffBase, CommitDiffOptions, CommitDiffScope};
    use devmil_git::types::ObjectId;
    use devmil_git::{Repository, RepositoryOptions};
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::process::{Command, Stdio};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::time::Duration;

    static NEXT: AtomicUsize = AtomicUsize::new(1);

    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            let root = std::env::temp_dir().join(format!(
                "gitlama-diff-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&root).unwrap();
            let fixture = Self(root);
            fixture.git(&["init", "-b", "main"]);
            fixture.git(&["config", "user.name", "Test"]);
            fixture.git(&["config", "user.email", "test@example.invalid"]);
            fixture
        }
        fn git(&self, arguments: &[&str]) -> Vec<u8> {
            let output = Command::new("git")
                .current_dir(&self.0)
                .args(arguments)
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "{}",
                String::from_utf8_lossy(&output.stderr)
            );
            output.stdout
        }
        fn head(&self) -> ObjectId {
            ObjectId::parse(
                String::from_utf8(self.git(&["rev-parse", "HEAD"]))
                    .unwrap()
                    .trim(),
            )
            .unwrap()
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn write(root: &Path, name: &str, bytes: &[u8]) {
        fs::write(root.join(name), bytes).unwrap();
    }

    fn committed_diff(fixture: &Fixture, layout: DiffLayout) -> DiffDocument {
        let repository = Repository::new(
            &fixture.0,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
        )
        .unwrap();
        repository.load().unwrap();
        let ticket = repository
            .commit_diff(
                fixture.head(),
                CommitDiffBase::EmptyTree,
                CommitDiffOptions {
                    scope: CommitDiffScope::All,
                    context: ContextLines::DEFAULT,
                    whitespace: DiffWhitespacePolicy::Preserve,
                    layout,
                    force_text: false,
                },
            )
            .unwrap();
        ticket
            .recv_timeout(Duration::from_secs(10))
            .unwrap()
            .unwrap()
            .as_ref()
            .clone()
    }

    #[test]
    fn selection_patch_spans_files_and_keeps_selected_context_as_context() {
        let fixture = Fixture::new();
        write(&fixture.0, "a.txt", b"one\r\ntwo\r\n");
        write(&fixture.0, "b.txt", b"alpha\nbeta");
        fixture.git(&["add", "."]);
        fixture.git(&["commit", "-m", "files"]);
        let document = committed_diff(&fixture, DiffLayout::Unified);
        let rows = DiffProjection::from_document(1, &document)
            .page(0, DIFF_PAGE_CAPACITY)
            .rows;
        let id = |text: &[u8]| {
            rows.iter()
                .find(|row| row.text == text && row.kind == NativeDiffRowKind::Addition)
                .unwrap()
                .stable_id
                .clone()
        };
        let patch = selection_patch(&document, &[id(b"two"), id(b"beta")]).unwrap();
        let text = String::from_utf8(patch).unwrap();
        assert!(text.contains("+two\r\n"), "{text}");
        assert!(!text.contains("+one"), "{text}");
        assert!(
            text.contains("+beta\n\\ No newline at end of file"),
            "{text}"
        );
        assert!(!text.contains("+alpha"), "{text}");
        let file_row = rows
            .iter()
            .find(|row| row.kind == NativeDiffRowKind::File)
            .unwrap()
            .stable_id
            .clone();
        assert!(selection_patch(&document, &[file_row]).unwrap().is_empty());
    }

    #[test]
    fn file_headers_publish_exclusive_section_ends_across_pages() {
        let fixture = Fixture::new();
        write(&fixture.0, "a.txt", b"one\n");
        write(&fixture.0, "b.txt", b"two\n");
        fixture.git(&["add", "."]);
        fixture.git(&["commit", "-m", "files"]);
        let document = committed_diff(&fixture, DiffLayout::Unified);
        let projection = DiffProjection::from_document(1, &document);
        let rows = projection.page(0, DIFF_PAGE_CAPACITY).rows;
        let starts: Vec<_> = rows
            .iter()
            .enumerate()
            .filter_map(|(index, row)| (row.kind == NativeDiffRowKind::File).then_some(index))
            .collect();
        assert_eq!(starts.len(), 2);
        assert_eq!(rows[starts[0]].section_end, Some(starts[1] as u32));
        assert_eq!(rows[starts[1]].section_end, Some(rows.len() as u32));
        assert!(rows
            .iter()
            .filter(|row| row.kind != NativeDiffRowKind::File)
            .all(|row| row.section_end.is_none()));
        assert_eq!(
            projection.page(0, 1).rows[0].section_end,
            Some(starts[1] as u32)
        );
    }

    #[test]
    fn committed_projection_is_paged_and_bounds_long_lines() {
        let fixture = Fixture::new();
        let long = vec![b'x'; DIFF_TEXT_BYTES_PER_ROW * 2];
        write(&fixture.0, "long.txt", &long);
        fixture.git(&["add", "."]);
        fixture.git(&["commit", "-m", "long"]);
        let document = committed_diff(&fixture, DiffLayout::SideBySide);
        let projection = DiffProjection::from_document(7, &document);
        let page = projection.page(0, DIFF_PAGE_CAPACITY);
        assert_eq!(page.request_id, 7);
        assert_eq!(page.layout, NativeDiffLayout::SideBySide);
        assert!(page.rows.iter().any(|row| row.text_truncated));
        assert!(page.rows.len() <= DIFF_PAGE_CAPACITY);
        assert!(page.payload_bytes < 64 * 1024);
    }

    #[test]
    fn derives_intra_line_spans_for_plain_git_replacements() {
        let (deleted, added) = replacement_spans(
            br#"version = "0.1.0-beta.7""#,
            br#"version = "0.1.0-beta.8""#,
        )
        .unwrap();
        let deleted = deleted.unwrap();
        let added = added.unwrap();
        assert_eq!(
            &br#"version = "0.1.0-beta.7""#[deleted.start..deleted.end],
            b"7"
        );
        assert_eq!(
            &br#"version = "0.1.0-beta.8""#[added.start..added.end],
            b"8"
        );

        let (deleted, added) =
            replacement_spans("name = café".as_bytes(), "name = café".as_bytes()).unwrap();
        let deleted = deleted.unwrap();
        let added = added.unwrap();
        assert!("name = café".get(deleted.start..deleted.end).is_some());
        assert!("name = café".get(added.start..added.end).is_some());

        let (deleted, added) = replacement_spans(b"name", b"name = value").unwrap();
        assert!(deleted.is_none());
        assert_eq!(&b"name = value"[added.unwrap().start..], b" = value");
    }

    #[test]
    fn committed_diff_cache_identity_includes_byte_path_and_display_options() {
        let fixture = Fixture::new();
        write(&fixture.0, "a.txt", b"a\n");
        write(&fixture.0, "b.txt", b"b\n");
        fixture.git(&["add", "."]);
        fixture.git(&["commit", "-m", "files"]);
        let repository = Repository::new(
            &fixture.0,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
        )
        .unwrap();
        repository.load().unwrap();
        let receive = |options: CommitDiffOptions| {
            repository
                .commit_diff(fixture.head(), CommitDiffBase::EmptyTree, options)
                .unwrap()
                .recv_timeout(Duration::from_secs(10))
                .unwrap()
                .unwrap()
        };
        let unified = receive(CommitDiffOptions::default());
        let cached = receive(CommitDiffOptions::default());
        assert!(Arc::ptr_eq(&unified, &cached));
        let split = receive(CommitDiffOptions {
            layout: DiffLayout::SideBySide,
            ..CommitDiffOptions::default()
        });
        assert!(!Arc::ptr_eq(&unified, &split));
        let wider_context = receive(CommitDiffOptions {
            context: ContextLines::new(6).unwrap(),
            ..CommitDiffOptions::default()
        });
        let ignored_whitespace = receive(CommitDiffOptions {
            whitespace: DiffWhitespacePolicy::IgnoreAmount,
            ..CommitDiffOptions::default()
        });
        assert!(!Arc::ptr_eq(&unified, &wider_context));
        assert!(!Arc::ptr_eq(&unified, &ignored_whitespace));
        let unified_projection = DiffProjection::from_document(1, &unified);
        let split_projection = DiffProjection::from_document(2, &split);
        let selectable = |projection: &DiffProjection| {
            projection
                .page(0, DIFF_PAGE_CAPACITY)
                .rows
                .into_iter()
                .filter(|row| row.selectable)
                .map(|row| row.stable_id)
                .collect::<Vec<_>>()
        };
        assert_eq!(
            selectable(&unified_projection),
            selectable(&split_projection)
        );
        let (matches, total, truncated) = unified_projection.search(b"a", false, 1);
        assert!(!matches.is_empty());
        assert!(total >= matches.len() as u64);
        assert_eq!(truncated, total > 1);
        let (hunks, total_hunks, _) = unified_projection.hunk_positions(32);
        assert_eq!(hunks.len() as u64, total_hunks);
        let path_a = devmil_git::diff::model::DiffPath::from_bytes(b"a.txt".to_vec()).unwrap();
        let path_b = devmil_git::diff::model::DiffPath::from_bytes(b"b.txt".to_vec()).unwrap();
        let only_a = receive(CommitDiffOptions {
            scope: CommitDiffScope::File {
                old_path: path_a.clone(),
                new_path: path_a.clone(),
            },
            ..CommitDiffOptions::default()
        });
        let only_a_cached = receive(CommitDiffOptions {
            scope: CommitDiffScope::File {
                old_path: path_a.clone(),
                new_path: path_a,
            },
            ..CommitDiffOptions::default()
        });
        let only_b = receive(CommitDiffOptions {
            scope: CommitDiffScope::File {
                old_path: path_b.clone(),
                new_path: path_b,
            },
            ..CommitDiffOptions::default()
        });
        assert!(Arc::ptr_eq(&only_a, &only_a_cached));
        assert!(!Arc::ptr_eq(&only_a, &only_b));
    }

    #[test]
    fn selected_line_patch_preserves_exact_index_bytes_and_rejects_stale_snapshot() {
        let fixture = Fixture::new();
        write(&fixture.0, "fixture.txt", b"one\r\ntwo\r\nthree");
        fixture.git(&["add", "."]);
        fixture.git(&["commit", "-m", "base"]);
        write(&fixture.0, "fixture.txt", b"ONE\r\ntwo\r\nTHREE");

        let raw = fixture.git(&["diff", "--raw", "-z", "--no-abbrev", "--", "fixture.txt"]);
        let patch = fixture.git(&[
            "diff",
            "--patch",
            "--unified=0",
            "--binary",
            "--full-index",
            "--no-color",
            "--",
            "fixture.txt",
        ]);
        let document = devmil_git::diff::parse_unified_patch_with_raw_metadata(
            &raw,
            &patch,
            devmil_git::diff::PatchLimits::default(),
        )
        .unwrap();
        let accepted = document.files[0].clone();
        let selected = accepted
            .hunks
            .iter()
            .flat_map(|hunk| &hunk.lines)
            .filter(|line| line.source == b"one" || line.source == b"ONE")
            .map(|line| line.id.clone())
            .collect::<Vec<_>>();
        assert_eq!(
            selected.len(),
            2,
            "a replacement selects its old and new side"
        );
        let constructed = BytePatchBuilder
            .construct_patch(&PatchConstructionRequest {
                file: accepted.clone(),
                selection: LineSelection::new(selected),
                context: ContextLines::new(0).unwrap(),
                reverse: false,
            })
            .unwrap();
        let temporary_index = fixture.0.join(".git/gitlama-proof-index");
        fs::copy(fixture.0.join(".git/index"), &temporary_index).unwrap();
        let mut child = Command::new("git")
            .current_dir(&fixture.0)
            .env("GIT_INDEX_FILE", &temporary_index)
            .args(["apply", "--cached", "--recount", "--unidiff-zero", "-"])
            .stdin(Stdio::piped())
            .spawn()
            .unwrap();
        use std::io::Write;
        child
            .stdin
            .as_mut()
            .unwrap()
            .write_all(&constructed.bytes)
            .unwrap();
        assert!(child.wait().unwrap().success());
        let staged = Command::new("git")
            .current_dir(&fixture.0)
            .env("GIT_INDEX_FILE", &temporary_index)
            .args(["show", ":fixture.txt"])
            .output()
            .unwrap();
        assert!(staged.status.success());
        assert_eq!(staged.stdout, b"ONE\r\ntwo\r\nthree");
        assert_eq!(
            fixture.git(&["show", ":fixture.txt"]),
            b"one\r\ntwo\r\nthree"
        );
        assert_eq!(
            fs::read(fixture.0.join("fixture.txt")).unwrap(),
            b"ONE\r\ntwo\r\nTHREE"
        );

        fixture.git(&["reset", "--hard", "HEAD"]);
        write(&fixture.0, "fixture.txt", b"external\r\ntwo\r\nthree");
        let current_patch = fixture.git(&[
            "diff",
            "--patch",
            "--unified=0",
            "--binary",
            "--full-index",
            "--no-color",
            "--",
            "fixture.txt",
        ]);
        let current_raw = fixture.git(&["diff", "--raw", "-z", "--no-abbrev", "--", "fixture.txt"]);
        let current = devmil_git::diff::parse_unified_patch_with_raw_metadata(
            &current_raw,
            &current_patch,
            devmil_git::diff::PatchLimits::default(),
        )
        .unwrap();
        assert_ne!(
            current.files[0], accepted,
            "preflight must reject a changed accepted snapshot"
        );
    }

    #[test]
    fn adversarial_kinds_remain_typed_and_no_newline_is_explicit() {
        let fixture = Fixture::new();
        write(&fixture.0, "delete.txt", b"delete\n");
        write(&fixture.0, "rename.txt", b"rename one\nrename two\n");
        write(&fixture.0, "binary.bin", &[0, 1, 2, 0, 3]);
        write(&fixture.0, "image.png", &[0x89, b'P', b'N', b'G', 1]);
        fixture.git(&["add", "."]);
        fixture.git(&["commit", "-m", "base"]);
        fixture.git(&["mv", "rename.txt", "renamed.txt"]);
        write(
            &fixture.0,
            "renamed.txt",
            b"rename one\nrename two\nrenamed content\n",
        );
        fs::remove_file(fixture.0.join("delete.txt")).unwrap();
        write(&fixture.0, "added.txt", b"no-final-newline");
        write(&fixture.0, "binary.bin", &[0, 9, 2, 0, 3]);
        write(&fixture.0, "image.png", &[0x89, b'P', b'N', b'G', 2]);
        fixture.git(&["add", "-A"]);
        fixture.git(&["commit", "-m", "adversarial"]);
        let document = committed_diff(&fixture, DiffLayout::Unified);
        let kinds = document
            .files
            .iter()
            .map(|file| change_kind_name(&file.kind))
            .collect::<Vec<_>>();
        assert!(kinds.contains(&"added"));
        assert!(kinds.contains(&"deleted"));
        assert!(kinds.contains(&"renamed"));
        assert!(document.files.iter().any(|file| file.fallback.is_some()));
        assert!(document.files.iter().any(|file| {
            file.kind == FileChangeKind::Image && file.fallback == Some(DiffFallback::ImageDeferred)
        }));
        let temporary_index = fixture.0.join(".git/adversarial-proof-index");
        let read_tree = Command::new("git")
            .current_dir(&fixture.0)
            .env("GIT_INDEX_FILE", &temporary_index)
            .args(["read-tree", "HEAD^"])
            .output()
            .unwrap();
        assert!(read_tree.status.success());
        for file in &document.files {
            let selection = file
                .hunks
                .iter()
                .flat_map(|hunk| &hunk.lines)
                .filter(|line| line.is_change())
                .map(|line| line.id.clone())
                .collect::<Vec<_>>();
            if file.fallback.is_some() {
                assert!(
                    selection.is_empty(),
                    "binary fallbacks expose no selectable text lines"
                );
                continue;
            }
            if selection.is_empty() {
                continue;
            }
            let patch = BytePatchBuilder
                .construct_patch(&PatchConstructionRequest {
                    file: file.clone(),
                    selection: LineSelection::new(selection),
                    context: ContextLines::new(0).unwrap(),
                    reverse: false,
                })
                .unwrap();
            let mut child = Command::new("git")
                .current_dir(&fixture.0)
                .env("GIT_INDEX_FILE", &temporary_index)
                .args(["apply", "--cached", "--recount", "--unidiff-zero", "-"])
                .stdin(Stdio::piped())
                .spawn()
                .unwrap();
            use std::io::Write;
            child
                .stdin
                .as_mut()
                .unwrap()
                .write_all(&patch.bytes)
                .unwrap();
            assert!(
                child.wait().unwrap().success(),
                "{} patch failed",
                change_kind_name(&file.kind)
            );
        }
        let added = Command::new("git")
            .current_dir(&fixture.0)
            .env("GIT_INDEX_FILE", &temporary_index)
            .args(["show", ":added.txt"])
            .output()
            .unwrap();
        assert_eq!(added.stdout, b"no-final-newline");
        let renamed = Command::new("git")
            .current_dir(&fixture.0)
            .env("GIT_INDEX_FILE", &temporary_index)
            .args(["show", ":renamed.txt"])
            .output()
            .unwrap();
        assert_eq!(renamed.stdout, b"rename one\nrename two\nrenamed content\n");
        let deleted = Command::new("git")
            .current_dir(&fixture.0)
            .env("GIT_INDEX_FILE", &temporary_index)
            .args(["show", ":delete.txt"])
            .output()
            .unwrap();
        assert!(!deleted.status.success());
        let projection = DiffProjection::from_document(1, &document);
        let page = projection.page(0, DIFF_PAGE_CAPACITY);
        assert!(page
            .rows
            .iter()
            .any(|row| row.kind == NativeDiffRowKind::NoNewline));
        assert!(page
            .rows
            .iter()
            .any(|row| row.kind == NativeDiffRowKind::Image));
    }
}
