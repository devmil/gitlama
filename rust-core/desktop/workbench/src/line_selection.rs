//! The hunks and lines picked in a working diff, by stable row ID.
//!
//! A picked hunk is sent as its hunk ID, which takes every change line of
//! the hunk, also lines not loaded yet. Unpicking one line of a picked hunk
//! replaces the hunk ID with its other loaded change lines, so the picked
//! rows are always the ones shown as checked.

use gitlama_contract::diff::{NativeDiffRow, NativeDiffRowKind};
use std::collections::{HashMap, HashSet};

#[derive(Clone, Debug, Default)]
pub struct LineSelection {
    /// The picked hunk and line IDs, in the order they were picked.
    ids: Vec<String>,
    /// Row ID -> the hunk it belongs to.
    hunk_of: HashMap<String, String>,
    /// Hunk ID -> its loaded change lines, in order; hunks in row order.
    lines_of: Vec<(String, Vec<String>)>,
    /// Hunks whose rows are all loaded.
    complete: HashSet<String>,
}

impl LineSelection {
    pub fn row_ids(&self) -> Vec<String> {
        self.ids.clone()
    }

    pub fn is_empty(&self) -> bool {
        self.ids.is_empty()
    }

    fn picked(&self, id: &str) -> bool {
        self.ids.iter().any(|candidate| candidate == id)
    }

    fn add(&mut self, id: &str) {
        if !self.picked(id) {
            self.ids.push(id.to_owned());
        }
    }

    fn remove(&mut self, id: &str) -> bool {
        let before = self.ids.len();
        self.ids.retain(|candidate| candidate != id);
        self.ids.len() != before
    }

    fn lines(&self, hunk: &str) -> &[String] {
        self.lines_of
            .iter()
            .find(|(id, _)| id == hunk)
            .map_or(&[], |(_, lines)| lines.as_slice())
    }

    /// Indexes `rows`, the loaded rows of a diff of `total_rows` rows.
    pub fn update(&mut self, rows: &[NativeDiffRow], total_rows: u64) {
        self.hunk_of.clear();
        self.lines_of.clear();
        self.complete.clear();
        let mut hunk: Option<String> = None;
        for row in rows {
            match row.kind {
                NativeDiffRowKind::File => {
                    if let Some(done) = hunk.take() {
                        self.complete.insert(done);
                    }
                }
                NativeDiffRowKind::Hunk => {
                    if let Some(done) = hunk.take() {
                        self.complete.insert(done);
                    }
                    hunk = Some(row.stable_id.clone());
                    self.lines_of.push((row.stable_id.clone(), Vec::new()));
                }
                _ => {
                    let Some(current) = &hunk else { continue };
                    self.hunk_of.insert(row.stable_id.clone(), current.clone());
                    if row.selectable {
                        self.lines_of
                            .last_mut()
                            .expect("a hunk was opened")
                            .1
                            .push(row.stable_id.clone());
                    }
                }
            }
        }
        if let Some(last) = hunk
            && rows.len() as u64 >= total_rows
        {
            self.complete.insert(last);
        }
    }

    /// Whether the change line `id` is picked, alone or with its hunk.
    pub fn line_checked(&self, id: &str) -> bool {
        self.picked(id) || self.hunk_of.get(id).is_some_and(|hunk| self.picked(hunk))
    }

    /// Some(true) when all of `hunk` is picked, Some(false) when none of it,
    /// None for some of its lines.
    pub fn hunk_checked(&self, hunk: &str) -> Option<bool> {
        if self.picked(hunk) {
            return Some(true);
        }
        let lines = self.lines(hunk);
        let picked = lines.iter().filter(|id| self.picked(id)).count();
        if picked == 0 {
            Some(false)
        } else if picked == lines.len() && self.complete.contains(hunk) {
            Some(true)
        } else {
            None
        }
    }

    pub fn set_hunk(&mut self, hunk: &str, value: bool) {
        for line in self.lines(hunk).to_vec() {
            self.remove(&line);
        }
        if value {
            self.add(hunk);
        } else {
            self.remove(hunk);
        }
    }

    pub fn set_line(&mut self, id: &str, value: bool) {
        let hunk = self.hunk_of.get(id).cloned();
        if value {
            if hunk.as_ref().is_none_or(|hunk| !self.picked(hunk)) {
                self.add(id);
            }
            return;
        }
        match hunk {
            Some(hunk) if self.remove(&hunk) => {
                for line in self.lines(&hunk).to_vec() {
                    if line != id {
                        self.add(&line);
                    }
                }
            }
            _ => {
                self.remove(id);
            }
        }
    }

    /// Whether every loaded hunk is picked.
    pub fn all_checked(&self) -> bool {
        !self.lines_of.is_empty()
            && self
                .lines_of
                .iter()
                .all(|(hunk, _)| self.hunk_checked(hunk) == Some(true))
    }

    pub fn select_all(&mut self) {
        let hunks: Vec<String> = self.lines_of.iter().map(|(hunk, _)| hunk.clone()).collect();
        for hunk in hunks {
            self.set_hunk(&hunk, true);
        }
    }

    pub fn clear(&mut self) {
        self.ids.clear();
    }

    /// The picked change lines among the loaded rows, and whether a picked
    /// hunk still has rows to load, which makes the count a lower bound.
    pub fn picked_lines(&self) -> (usize, bool) {
        let mut count = 0;
        let mut more = false;
        for (hunk, lines) in &self.lines_of {
            if self.picked(hunk) {
                count += lines.len();
                more |= !self.complete.contains(hunk);
            } else {
                count += lines.iter().filter(|id| self.picked(id)).count();
            }
        }
        (count, more)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(id: &str, kind: NativeDiffRowKind) -> NativeDiffRow {
        NativeDiffRow {
            stable_id: id.to_owned(),
            kind,
            old_line: None,
            new_line: None,
            text: Vec::new(),
            text_truncated: false,
            selectable: matches!(
                kind,
                NativeDiffRowKind::Addition | NativeDiffRowKind::Deletion
            ),
            intra_line: Vec::new(),
            syntax: None,
            file_kind: None,
            old_path: None,
            new_path: None,
            section_end: None,
        }
    }

    fn rows() -> Vec<NativeDiffRow> {
        use NativeDiffRowKind::*;
        vec![
            row("f", File),
            row("h1", Hunk),
            row("c1", Context),
            row("a1", Addition),
            row("d1", Deletion),
            row("h2", Hunk),
            row("a2", Addition),
        ]
    }

    #[test]
    fn a_picked_hunk_takes_its_lines_and_unpicking_one_keeps_the_others() {
        let mut selection = LineSelection::default();
        selection.update(&rows(), 7);
        selection.set_hunk("h1", true);
        assert!(selection.line_checked("a1") && selection.line_checked("d1"));
        assert_eq!(selection.hunk_checked("h1"), Some(true));
        assert_eq!(selection.row_ids(), ["h1"]);
        selection.set_line("a1", false);
        assert_eq!(selection.row_ids(), ["d1"]);
        assert_eq!(selection.hunk_checked("h1"), None);
        selection.set_line("a1", true);
        assert_eq!(selection.hunk_checked("h1"), Some(true));
        assert_eq!(selection.picked_lines(), (2, false));
    }

    #[test]
    fn select_all_and_counts_with_rows_still_to_load() {
        let mut selection = LineSelection::default();
        // The last hunk may continue past the loaded rows.
        selection.update(&rows(), 20);
        assert!(!selection.all_checked());
        selection.select_all();
        assert!(selection.all_checked());
        assert_eq!(selection.row_ids(), ["h1", "h2"]);
        assert_eq!(selection.picked_lines(), (3, true));
        selection.clear();
        assert!(selection.is_empty());
        assert_eq!(selection.hunk_checked("h2"), Some(false));
        // An incomplete hunk with all its loaded lines picked is partial.
        selection.set_line("a2", true);
        assert_eq!(selection.hunk_checked("h2"), None);
    }
}
