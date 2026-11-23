//! A diff's rows for QML: built on demand from a
//! `DiffDocument`, with each line's text, its syntax colours as runs
//! and its changed-word marks. Rows not loaded yet are placeholders that
//! ask the document for their page.

use gitlama_contract::diff::{
    NativeDiffFileKind, NativeDiffRow, NativeDiffRowKind, NativeSyntaxSideState, NativeSyntaxSpan,
};
use gitlama_workbench::diff_doc::DiffDocument;
use gitlama_workbench::text_syntax::token_name;
use qtbridge::qtbridge_type_lib::{QByteArray, QHash, QModelIndex, QVariant};
use qtbridge::{QAbstractItemModel, QAbstractItemModelBase};
use serde_json::{Value, json};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use crate::row_model::to_qvariant;

const ROLES: &[&str] = &[
    "stableId",
    "kind",
    "loading",
    "oldLine",
    "newLine",
    "text",
    "runsOld",
    "runsNew",
    "marks",
    "fileKind",
    "oldPath",
    "newPath",
    "selectable",
    "truncated",
    "invalid",
    "sectionEnd",
    "hunkRange",
    "hunkText",
];
const FIRST_ROLE: i32 = 0x100;
/// Spaces a tab shows as.
const TAB_WIDTH: usize = 4;
/// The most changed-word marks a line shows.
const MAX_MARKS: usize = 6;
/// WCAG contrast a syntax colour needs on its surfaces.
const MINIMUM_CONTRAST: f64 = 4.5;

pub fn kind_name(kind: NativeDiffRowKind) -> &'static str {
    match kind {
        NativeDiffRowKind::File => "file",
        NativeDiffRowKind::Hunk => "hunk",
        NativeDiffRowKind::Context => "context",
        NativeDiffRowKind::Addition => "addition",
        NativeDiffRowKind::Deletion => "deletion",
        NativeDiffRowKind::NoNewline => "noNewline",
        NativeDiffRowKind::Binary => "binary",
        NativeDiffRowKind::Image => "image",
        NativeDiffRowKind::Submodule => "submodule",
        NativeDiffRowKind::ModeOnly => "modeOnly",
        NativeDiffRowKind::TooLarge => "tooLarge",
    }
}

pub fn file_kind_name(kind: NativeDiffFileKind) -> &'static str {
    match kind {
        NativeDiffFileKind::Modified => "modified",
        NativeDiffFileKind::Added => "added",
        NativeDiffFileKind::Deleted => "deleted",
        NativeDiffFileKind::Renamed => "renamed",
        NativeDiffFileKind::Copied => "copied",
        NativeDiffFileKind::ModeChanged => "modeChanged",
        NativeDiffFileKind::TypeChanged => "typeChanged",
        NativeDiffFileKind::Binary => "binary",
        NativeDiffFileKind::Image => "image",
        NativeDiffFileKind::Submodule => "submodule",
        NativeDiffFileKind::Conflict => "conflict",
        NativeDiffFileKind::Untracked => "untracked",
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct Rgb(f64, f64, f64);

fn parse_color(text: &str) -> Option<Rgb> {
    let hex = text.trim().trim_start_matches('#');
    // QML colours arrive as #rrggbb or #aarrggbb.
    let hex = if hex.len() == 8 { &hex[2..] } else { hex };
    if hex.len() != 6 {
        return None;
    }
    let channel = |at: usize| {
        u8::from_str_radix(&hex[at..at + 2], 16)
            .ok()
            .map(|value| f64::from(value) / 255.0)
    };
    Some(Rgb(channel(0)?, channel(2)?, channel(4)?))
}

fn luminance(Rgb(r, g, b): Rgb) -> f64 {
    let linear = |c: f64| {
        if c <= 0.03928 {
            c / 12.92
        } else {
            ((c + 0.055) / 1.055).powf(2.4)
        }
    };
    0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

fn contrast(a: Rgb, b: Rgb) -> f64 {
    let (la, lb) = (luminance(a), luminance(b));
    (la.max(lb) + 0.05) / (la.min(lb) + 0.05)
}

/// Syntax colours checked against the surfaces of each row kind: a colour that does not read on one keeps `ink`.
#[derive(Default, Clone, PartialEq)]
pub struct SyntaxPalette {
    ink: String,
    /// Row kind → token → colour.
    by_kind: HashMap<&'static str, HashMap<&'static str, String>>,
}

impl SyntaxPalette {
    /// `value`: {ink, syntax: {keyword: "#..", ...}, surfaces: {context:
    /// [..], addition: [..], deletion: [..]}}.
    pub fn from_value(value: &Value) -> Self {
        let ink = value["ink"].as_str().unwrap_or("#000000").to_owned();
        let mut by_kind = HashMap::new();
        for kind in ["context", "addition", "deletion"] {
            let surfaces: Vec<Rgb> = value["surfaces"][kind]
                .as_array()
                .map(|items| {
                    items
                        .iter()
                        .filter_map(|item| item.as_str().and_then(parse_color))
                        .collect()
                })
                .unwrap_or_default();
            let mut colours = HashMap::new();
            if let Some(syntax) = value["syntax"].as_object() {
                for token in [
                    "comment",
                    "keyword",
                    "string",
                    "number",
                    "type",
                    "function",
                    "variable",
                    "constant",
                    "operator",
                    "punctuation",
                    "attribute",
                    "tag",
                ] {
                    let Some(colour) = syntax.get(token).and_then(Value::as_str) else {
                        continue;
                    };
                    let readable = parse_color(colour).is_some_and(|rgb| {
                        surfaces
                            .iter()
                            .all(|surface| contrast(rgb, *surface) >= MINIMUM_CONTRAST)
                    });
                    colours.insert(
                        token,
                        if readable {
                            colour.to_owned()
                        } else {
                            ink.clone()
                        },
                    );
                }
            }
            by_kind.insert(kind, colours);
        }
        Self { ink, by_kind }
    }

    fn colour(&self, kind: &str, token: &str) -> Option<&str> {
        self.by_kind
            .get(kind)?
            .get(token)
            .map(String::as_str)
            .filter(|colour| *colour != self.ink)
    }
}

/// A line's displayed text: tabs expanded, with the UTF-16 offset of each
/// byte boundary of the source.
struct Display {
    text: String,
    /// Source byte offset → UTF-16 offset in `text`.
    utf16_at: Vec<usize>,
}

/// `bytes` decoded as Latin-1 (every byte is one character) for showing.
fn display_latin1(bytes: &[u8]) -> Display {
    let mut text = String::with_capacity(bytes.len());
    let mut utf16_at = vec![0; bytes.len() + 1];
    let mut units = 0;
    for (offset, byte) in bytes.iter().enumerate() {
        utf16_at[offset] = units;
        match *byte {
            b'\t' => {
                text.extend(std::iter::repeat_n(' ', TAB_WIDTH));
                units += TAB_WIDTH;
            }
            b'\r' | b'\n' => {}
            byte => {
                text.push(char::from(byte));
                units += 1;
            }
        }
    }
    utf16_at[bytes.len()] = units;
    Display { text, utf16_at }
}

fn display(bytes: &[u8]) -> Option<Display> {
    let source = std::str::from_utf8(bytes).ok()?;
    let mut text = String::with_capacity(source.len());
    let mut utf16_at = vec![0; bytes.len() + 1];
    let mut units = 0;
    for (offset, ch) in source.char_indices() {
        utf16_at[offset..offset + ch.len_utf8()].fill(units);
        if ch == '\t' {
            text.extend(std::iter::repeat_n(' ', TAB_WIDTH));
            units += TAB_WIDTH;
        } else if ch == '\r' || ch == '\n' {
            // Line terminators are not shown.
        } else {
            text.push(ch);
            units += ch.len_utf16();
        }
    }
    utf16_at[bytes.len()] = units;
    Some(Display { text, utf16_at })
}

/// `display`'s colour runs from `spans` (byte ranges of the source): `[start, end, colour]`
/// over UTF-16 offsets of the shown text, empty when nothing is coloured. A native
/// highlighter applies them to the line's plain text, which parses no markup.
fn runs(
    display: &Display,
    source: &[u8],
    spans: &[NativeSyntaxSpan],
    palette: &SyntaxPalette,
    kind: &str,
) -> Value {
    let mut out = Vec::new();
    let mut cursor = 0usize;
    for span in spans {
        let start = display.utf16_at[(span.start as usize).min(source.len())];
        let end = display.utf16_at[(span.end as usize).min(source.len())];
        if start < cursor || end <= start {
            continue;
        }
        if let Some(colour) = palette.colour(kind, token_name(span.kind)) {
            out.push(json!([start, end, colour]));
        }
        cursor = end;
    }
    Value::Array(out)
}

fn marks(row: &NativeDiffRow, display: &Display) -> Value {
    let mut result = Vec::new();
    let mut cursor = 0u32;
    let length = row.text.len() as u32;
    for span in row.intra_line.iter().take(MAX_MARKS) {
        let start = span.start.clamp(cursor, length);
        let end = span.end.clamp(start, length);
        let (from, to) = (
            display.utf16_at[start as usize],
            display.utf16_at[end as usize],
        );
        if to > from {
            result.push(json!([from, to]));
        }
        cursor = end;
    }
    Value::Array(result)
}

struct RowView {
    stable_id: String,
    kind: &'static str,
    loading: bool,
    old_line: i32,
    new_line: i32,
    text: String,
    runs_old: Value,
    runs_new: Value,
    marks: Value,
    file_kind: Option<&'static str>,
    old_path: String,
    new_path: String,
    selectable: bool,
    truncated: bool,
    invalid: bool,
    section_end: i32,
    hunk_range: String,
    hunk_text: String,
}

impl RowView {
    fn loading(index: u64) -> Self {
        Self {
            stable_id: format!("loading-{index}"),
            kind: "context",
            loading: true,
            old_line: -1,
            new_line: -1,
            text: String::new(),
            runs_old: Value::Array(Vec::new()),
            runs_new: Value::Array(Vec::new()),
            marks: Value::Array(Vec::new()),
            file_kind: None,
            old_path: String::new(),
            new_path: String::new(),
            selectable: false,
            truncated: false,
            invalid: false,
            section_end: -1,
            hunk_range: String::new(),
            hunk_text: String::new(),
        }
    }

    fn of(
        row: &NativeDiffRow,
        document: &DiffDocument,
        palette: &SyntaxPalette,
        latin1: bool,
    ) -> Self {
        let kind = kind_name(row.kind);
        let shown = if latin1 {
            Some(display_latin1(&row.text))
        } else {
            display(&row.text)
        };
        let text = shown
            .as_ref()
            .map(|display| display.text.clone())
            .unwrap_or_default();
        let line_row = matches!(
            row.kind,
            NativeDiffRowKind::Context | NativeDiffRowKind::Addition | NativeDiffRowKind::Deletion
        );
        let (mut runs_old, mut runs_new) = (Value::Array(Vec::new()), Value::Array(Vec::new()));
        if line_row
            && !row.text_truncated
            && let Some(display) = &shown
            && let Some(syntax) = document.syntax(&row.stable_id)
        {
            let surface = if row.kind == NativeDiffRowKind::Context {
                "context"
            } else {
                kind
            };

            if syntax.old_state == NativeSyntaxSideState::Ready && !syntax.old_spans.is_empty() {
                runs_old = runs(display, &row.text, &syntax.old_spans, palette, surface);
            }
            if syntax.new_state == NativeSyntaxSideState::Ready && !syntax.new_spans.is_empty() {
                runs_new = runs(display, &row.text, &syntax.new_spans, palette, surface);
            }
        }
        let (hunk_range, hunk_text) = if row.kind == NativeDiffRowKind::Hunk {
            split_hunk(&text)
        } else {
            (String::new(), String::new())
        };
        Self {
            stable_id: row.stable_id.clone(),
            kind,
            loading: false,
            old_line: row.old_line.map_or(-1, |line| line as i32),
            new_line: row.new_line.map_or(-1, |line| line as i32),
            marks: shown
                .as_ref()
                .map(|display| marks(row, display))
                .unwrap_or(Value::Array(Vec::new())),
            invalid: shown.is_none() && line_row,
            text,
            runs_old,
            runs_new,
            file_kind: row.file_kind.map(file_kind_name),
            old_path: row
                .old_path
                .as_deref()
                .map(|path| String::from_utf8_lossy(path).into_owned())
                .unwrap_or_default(),
            new_path: row
                .new_path
                .as_deref()
                .map(|path| String::from_utf8_lossy(path).into_owned())
                .unwrap_or_default(),
            selectable: row.selectable,
            truncated: row.text_truncated,
            section_end: row.section_end.map_or(-1, |end| end as i32),
            hunk_range,
            hunk_text,
        }
    }
}

/// `@@ -1,2 +1,3 @@ context` → ("@@ -1,2 +1,3 @@", "context").
fn split_hunk(text: &str) -> (String, String) {
    if let Some(rest) = text.strip_prefix("@@")
        && let Some(end) = rest.find("@@")
    {
        let range = format!("@@{}@@", &rest[..end]);
        return (range, rest[end + 2..].trim().to_owned());
    }
    (text.to_owned(), String::new())
}

#[qtbridge::qobject(Base = QAbstractItemModel, ConvertToCamelCase)]
mod diff_model {
    use super::*;

    #[derive(Default)]
    pub struct DiffModel {
        document: Option<Rc<DiffDocument>>,
        palette: SyntaxPalette,
        total: i32,
        rows: RefCell<HashMap<i32, Rc<RowView>>>,
        shown_revision: u64,
        /// Text is read as Latin-1 instead of UTF-8.
        latin1: bool,
        /// Counts publishes; a deferred clear applies only if none came after it.
        publications: u64,
        /// The publication a deferred clear waits on.
        clear_pending: Option<u64>,
    }

    impl DiffModel {
        #[qsignal]
        fn count_changed(&mut self);
        /// Another document replaced the shown one. Rows are rebound in place
        /// rather than reset, so the view keeps (and reuses) its row delegates.
        #[qsignal]
        fn replaced(&mut self);

        #[qslot]
        fn count(&self) -> i32 {
            self.total
        }

        /// Sets the syntax colours and the surfaces they are checked on.
        #[qslot]
        fn set_palette(&mut self, palette: Value) {
            let palette = crate::json::integral_numbers(palette);
            let palette = SyntaxPalette::from_value(&palette);
            // The same palette changes nothing: no refresh while the model publishes.
            if palette == self.palette {
                return;
            }
            self.palette = palette;
            self.refresh();
        }

        /// The image change among the loaded rows: {key, oldPath, newPath},
        /// or null.
        #[qslot]
        fn image_row(&self) -> Value {
            let Some(document) = &self.document else {
                return Value::Null;
            };
            let mut found = Value::Null;
            document.for_each_loaded(|_, row| {
                if found.is_null() && row.kind == NativeDiffRowKind::Image {
                    let text = |path: &Option<Vec<u8>>| {
                        path.as_deref()
                            .map(|path| String::from_utf8_lossy(path).into_owned())
                            .unwrap_or_default()
                    };
                    found = serde_json::json!({
                        "key": format!("{}:{}", document.request_id(), row.stable_id),
                        "oldPath": text(&row.old_path),
                        "newPath": text(&row.new_path),
                    });
                }
            });
            found
        }

        /// Reads text as Latin-1 (true) or UTF-8.
        #[qslot]
        fn set_latin1(&mut self, latin1: bool) {
            if self.latin1 != latin1 {
                self.latin1 = latin1;
                self.refresh();
            }
        }

        /// The minimap: for `buckets` slices of the rows, 0 when the loaded
        /// rows there change nothing, 1 for additions, 2 for deletions, 3
        /// for both.
        #[qslot]
        fn change_map(&self, buckets: i32) -> Vec<i32> {
            let buckets = buckets.max(1) as usize;
            let mut map = vec![0; buckets];
            let (Some(document), true) = (&self.document, self.total > 0) else {
                return map;
            };
            let total = self.total as usize;
            document.for_each_loaded(|at, row| {
                let mark = match row.kind {
                    NativeDiffRowKind::Addition => 1,
                    NativeDiffRowKind::Deletion => 2,
                    _ => return,
                };
                let bucket = (at as usize * buckets / total).min(buckets - 1);
                map[bucket] |= mark;
            });
            map
        }

        /// Reads the colours of rows `first..=last` (the rows on screen).
        #[qslot]
        fn demand_syntax(&self, first: i32, last: i32) {
            if let Some(document) = &self.document
                && first >= 0
                && last >= first
            {
                document.demand_syntax(first as u64, last as u64);
            }
        }

        /// The text of the selected rows in diff order (Copy lines).
        #[qslot]
        fn selection_text(&self, ids: Vec<String>) -> String {
            let Some(document) = &self.document else {
                return String::new();
            };
            let wanted: HashSet<String> = ids.into_iter().collect();
            let mut lines: Vec<(u64, String)> = Vec::new();
            document.for_each_loaded(|at, row| {
                if wanted.contains(&row.stable_id) {
                    let text = if self.latin1 {
                        row.text.iter().map(|byte| char::from(*byte)).collect()
                    } else {
                        String::from_utf8_lossy(&row.text).into_owned()
                    };
                    lines.push((at, text));
                }
            });
            lines.sort_by_key(|(at, _)| *at);
            lines
                .into_iter()
                .map(|(_, text)| text)
                .collect::<Vec<_>>()
                .join("\n")
        }

        /// The index of the first loaded row among `ids`, or -1: the row the
        /// selection's actions float over.
        #[qslot]
        fn first_index_of(&self, ids: Vec<String>) -> i32 {
            let Some(document) = &self.document else {
                return -1;
            };
            let wanted: HashSet<String> = ids.into_iter().collect();
            let mut first = -1;
            document.for_each_loaded(|at, row| {
                let at = at as i32;
                if wanted.contains(&row.stable_id) && (first < 0 || at < first) {
                    first = at;
                }
            });
            first
        }

        /// Whether the selected rows hold an added or removed line.
        #[qslot]
        fn selection_has_change(&self, ids: Vec<String>) -> bool {
            let Some(document) = &self.document else {
                return false;
            };
            let wanted: HashSet<String> = ids.into_iter().collect();
            let mut change = false;
            document.for_each_loaded(|_, row| {
                change |= wanted.contains(&row.stable_id)
                    && matches!(
                        row.kind,
                        NativeDiffRowKind::Addition | NativeDiffRowKind::Deletion
                    );
            });
            change
        }

        /// The text selected from row `first` at UTF-16 `first_offset` to row `last` at
        /// `last_offset`, over the line rows `side` shows ("old": context and deletions,
        /// "new": context and additions, "": every line row), joined by newlines (Copy).
        #[qslot]
        fn text_between(
            &self,
            first: i32,
            first_offset: i32,
            last: i32,
            last_offset: i32,
            side: String,
        ) -> String {
            let mut lines = Vec::new();
            for row in first.max(0)..=last.min(self.total - 1) {
                let view = self.view(row);
                let shown = match side.as_str() {
                    "old" => matches!(view.kind, "context" | "deletion"),
                    "new" => matches!(view.kind, "context" | "addition"),
                    _ => matches!(view.kind, "context" | "addition" | "deletion"),
                };
                if !shown || view.loading {
                    continue;
                }
                let units: Vec<u16> = view.text.encode_utf16().collect();
                let from = if row == first {
                    first_offset.max(0) as usize
                } else {
                    0
                };
                let to = if row == last {
                    last_offset.max(0) as usize
                } else {
                    units.len()
                };
                let to = to.min(units.len());
                lines.push(String::from_utf16_lossy(&units[from.min(to)..to]));
            }
            lines.join("\n")
        }

        /// The stable ids of the line rows from `first` to `last` (a Shift range).
        #[qslot]
        fn line_ids(&self, first: i32, last: i32) -> Vec<String> {
            let mut ids = Vec::new();
            for row in first.max(0)..=last.min(self.total - 1) {
                let view = self.view(row);
                if matches!(view.kind, "context" | "addition" | "deletion") && !view.loading {
                    ids.push(view.stable_id.clone());
                }
            }
            ids
        }

        /// The row of file section that contains row `index`.
        #[qslot]
        fn file_row_before(&self, index: i32) -> i32 {
            let mut at = index;
            while at >= 0 {
                if self.view(at).kind == "file" {
                    return at;
                }
                at -= 1;
            }
            -1
        }

        /// The hunk header the line at `index` belongs to, for the header
        /// pinned above a scrolled diff: {index, stableId, hunkRange,
        /// hunkText}, or null at a file header or before the first hunk.
        #[qslot]
        fn hunk_header_for(&self, index: i32) -> Value {
            let Some(document) = &self.document else {
                return Value::Null;
            };
            let (mut hunk, mut file) = (-1, -1);
            document.for_each_loaded(|at, row| {
                let at = at as i32;
                if at > index {
                    return;
                }
                match row.kind {
                    NativeDiffRowKind::Hunk => hunk = hunk.max(at),
                    NativeDiffRowKind::File => file = file.max(at),
                    _ => {}
                }
            });
            if hunk < 0 || hunk < file {
                return Value::Null;
            }
            let view = self.view(hunk);
            json!({
                "index": hunk,
                "stableId": view.stable_id,
                "hunkRange": view.hunk_range,
                "hunkText": view.hunk_text,
            })
        }

        /// The index of the next (or previous) hunk header from `index`, or -1.
        #[qslot]
        fn hunk_from(&self, index: i32, forward: bool) -> i32 {
            let Some(document) = &self.document else {
                return -1;
            };
            let mut found = -1;
            document.for_each_loaded(|at, row| {
                let at = at as i32;
                if row.kind != NativeDiffRowKind::Hunk {
                    return;
                }
                if forward && at > index && (found < 0 || at < found) {
                    found = at;
                }
                if !forward && at < index && at > found {
                    found = at;
                }
            });
            found
        }
    }

    impl QAbstractItemModel for DiffModel {
        fn index(&self, row: i32, column: i32, parent: &QModelIndex) -> QModelIndex {
            if parent.is_valid() || column != 0 || row < 0 || row >= self.total {
                return QModelIndex::default();
            }
            self.create_index(row, column, 0)
        }

        fn parent(&self, _child: &QModelIndex) -> QModelIndex {
            QModelIndex::default()
        }

        fn row_count(&self, parent: &QModelIndex) -> i32 {
            if parent.is_valid() { 0 } else { self.total }
        }

        fn column_count(&self, parent: &QModelIndex) -> i32 {
            i32::from(!parent.is_valid())
        }

        fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
            let row = index.row();
            if row < 0 || row >= self.total {
                return QVariant::default();
            }
            let view = self.view(row);
            match ROLES
                .get((role - FIRST_ROLE) as usize)
                .copied()
                .unwrap_or_default()
            {
                "stableId" => QVariant::from(&view.stable_id),
                "kind" => QVariant::from(view.kind),
                "loading" => QVariant::from(view.loading),
                "oldLine" => QVariant::from(view.old_line),
                "newLine" => QVariant::from(view.new_line),
                "text" => QVariant::from(&view.text),
                "runsOld" => to_qvariant(&view.runs_old),
                "runsNew" => to_qvariant(&view.runs_new),
                "marks" => to_qvariant(&view.marks),
                "fileKind" => QVariant::from(view.file_kind.unwrap_or_default()),
                "oldPath" => QVariant::from(&view.old_path),
                "newPath" => QVariant::from(&view.new_path),
                "selectable" => QVariant::from(view.selectable),
                "truncated" => QVariant::from(view.truncated),
                "invalid" => QVariant::from(view.invalid),
                "sectionEnd" => QVariant::from(view.section_end),
                "hunkRange" => QVariant::from(&view.hunk_range),
                "hunkText" => QVariant::from(&view.hunk_text),
                _ => QVariant::default(),
            }
        }

        fn role_names(&self) -> QHash<i32, QByteArray> {
            let mut names = QHash::<i32, QByteArray>::default();
            for (offset, name) in ROLES.iter().enumerate() {
                names.insert(&(FIRST_ROLE + offset as i32), &QByteArray::from(*name));
            }
            names
        }
    }

    impl DiffModel {
        fn view(&self, row: i32) -> Rc<RowView> {
            if let Some(view) = self.rows.borrow().get(&row) {
                return Rc::clone(view);
            }
            let Some(document) = &self.document else {
                return Rc::new(RowView::loading(row as u64));
            };
            let Some(view) = document.with_row(row as u64, |native| {
                RowView::of(native, document, &self.palette, self.latin1)
            }) else {
                document.ensure(row as u64);
                return Rc::new(RowView::loading(row as u64));
            };
            let view = Rc::new(view);
            self.rows.borrow_mut().insert(row, Rc::clone(&view));
            view
        }

        fn refresh(&mut self) {
            self.rows.borrow_mut().clear();
            if self.total > 0 {
                let top = self.create_index(0, 0, 0);
                let bottom = self.create_index(self.total - 1, 0, 0);
                self.data_changed(&top, &bottom);
            }
        }

        /// Shows `document` (None shows nothing). The same document only
        /// refreshes when rows or colours arrived.
        /// Starts waiting to clear the shown rows: the publication to clear after, or None when
        /// a clear already waits or there were no rows to keep (cleared at once).
        pub fn defer_clear(&mut self) -> Option<u64> {
            if self.clear_pending.is_some() {
                return None;
            }
            if self.total == 0 {
                self.publish(None);
                return None;
            }
            self.clear_pending = Some(self.publications);
            self.clear_pending
        }

        /// Clears the rows unless a document was published since `defer_clear` gave `waiting`.
        pub fn clear_after(&mut self, waiting: u64) {
            if self.clear_pending == Some(waiting) {
                self.publish(None);
            }
        }

        pub fn publish(&mut self, document: Option<Rc<DiffDocument>>) {
            self.publications += 1;
            self.clear_pending = None;
            let same = match (&self.document, &document) {
                (Some(shown), Some(next)) => Rc::ptr_eq(shown, next),
                (None, None) => true,
                _ => false,
            };
            if same {
                let revision = document.as_ref().map_or(0, |document| document.revision());
                if revision != self.shown_revision {
                    self.shown_revision = revision;
                    self.refresh();
                }
                return;
            }
            let total = document.as_ref().map_or(0, |document| {
                i32::try_from(document.total()).unwrap_or(i32::MAX)
            });
            // A reset would drop every row delegate and the view's reuse pool;
            // switching tabs or commits rebuilt the whole diff on each change.
            self.shown_revision = document.as_ref().map_or(0, |document| document.revision());
            self.document = document;
            self.rows.borrow_mut().clear();
            let previous = self.total;
            if total > previous {
                self.begin_insert_rows(&QModelIndex::default(), previous, total - 1);
                self.total = total;
                self.end_insert_rows();
            } else if total < previous {
                self.begin_remove_rows(&QModelIndex::default(), total, previous - 1);
                self.total = total;
                self.end_remove_rows();
            }
            let kept = previous.min(total);
            if kept > 0 {
                let top = self.create_index(0, 0, 0);
                let bottom = self.create_index(kept - 1, 0, 0);
                self.data_changed(&top, &bottom);
            }
            if total != previous {
                self.count_changed();
            }
            self.replaced();
        }
    }
}

pub use diff_model::DiffModel;

/// How long a shown diff waits for the next document before it clears. Switching tabs or
/// commits clears the document and then shows the next one: rebinding the shown rows to it
/// keeps their delegates, where clearing first would rebuild every row.
const CLEAR_GRACE: std::time::Duration = std::time::Duration::from_millis(400);

/// Shows `document` in `model`. Clearing a shown document waits `CLEAR_GRACE` for the next
/// one; views hide the diff while their state has none, so the waiting rows are not seen.
pub fn show(model: &Rc<RefCell<DiffModel>>, document: Option<Rc<DiffDocument>>) {
    if document.is_some() {
        model.borrow_mut().publish(document);
        return;
    }
    let Some(waiting) = model.borrow_mut().defer_clear() else {
        return;
    };
    let model = Rc::clone(model);
    gitlama_workbench::rt::spawn_detached(async move {
        gitlama_workbench::rt::sleep(CLEAR_GRACE).await;
        model.borrow_mut().clear_after(waiting);
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_contract::diff::NativeSyntaxTokenKind;

    #[test]
    fn tabs_expand_and_offsets_follow() {
        let shown = display("\tab".as_bytes()).unwrap();
        assert_eq!(shown.text, "    ab");
        assert_eq!(shown.utf16_at[1], 4);
        assert_eq!(shown.utf16_at[3], 6);
    }

    #[test]
    fn hunk_headers_split() {
        assert_eq!(
            split_hunk("@@ -1,2 +1,3 @@ fn main()"),
            ("@@ -1,2 +1,3 @@".to_owned(), "fn main()".to_owned())
        );
    }

    #[test]
    fn unreadable_colours_keep_ink() {
        let palette = SyntaxPalette::from_value(&json!({
            "ink": "#111111",
            "syntax": {"keyword": "#fefefe", "string": "#0a3d00"},
            "surfaces": {"context": ["#ffffff"], "addition": ["#ffffff"], "deletion": ["#ffffff"]},
        }));
        assert_eq!(palette.colour("context", "keyword"), None);
        assert_eq!(palette.colour("context", "string"), Some("#0a3d00"));
    }

    #[test]
    fn runs_colour_utf16_ranges() {
        let palette = SyntaxPalette::from_value(&json!({
            "ink": "#111111",
            "syntax": {"keyword": "#0000aa", "number": "#0a3d00"},
            "surfaces": {"context": ["#ffffff"]},
        }));
        let source = "é if 1".as_bytes();
        let shown = display(source).unwrap();
        let spans = [
            NativeSyntaxSpan {
                start: 3,
                end: 5,
                kind: NativeSyntaxTokenKind::Keyword,
            },
            NativeSyntaxSpan {
                start: 6,
                end: 7,
                kind: NativeSyntaxTokenKind::Number,
            },
        ];
        assert_eq!(
            runs(&shown, source, &spans, &palette, "context"),
            json!([[2, 4, "#0000aa"], [5, 6, "#0a3d00"]])
        );
        assert_eq!(runs(&shown, source, &[], &palette, "context"), json!([]));
    }
}
