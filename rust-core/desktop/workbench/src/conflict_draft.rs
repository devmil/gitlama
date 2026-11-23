//! A reviewable merge result (the Dart ConflictMergeDraft): the conflict
//! regions of a file's result, the choice made in each, and the comparison
//! rows that show both sides next to each other. Text is UTF-16, as Dart and
//! QML count it, so region offsets are the offsets the result editor uses.

use gitlama_contract::conflict::{NativeConflictFile, NativeConflictRegionChoice};

type Text = Vec<u16>;

const NEWLINE: u16 = b'\n' as u16;

fn utf16(text: &str) -> Text {
    text.encode_utf16().collect()
}

pub fn string(text: &[u16]) -> String {
    String::from_utf16_lossy(text)
}

fn starts_with(line: &[u16], prefix: &str) -> bool {
    let prefix = utf16(prefix);
    line.len() >= prefix.len() && line[..prefix.len()] == prefix[..]
}

/// Whether `text` still holds a conflict marker as Git writes one: seven
/// `<`, `|` or `>` followed by a space or the line end, or exactly seven `=`.
/// Longer runs, such as a Markdown heading underline, are content.
pub fn has_conflict_markers(text: &str) -> bool {
    text.split('\n').any(|line| {
        let line = line.strip_suffix('\r').unwrap_or(line);
        if line == "=======" {
            return true;
        }
        ["<<<<<<<", "|||||||", ">>>>>>>"].iter().any(|marker| {
            line.strip_prefix(marker)
                .is_some_and(|rest| rest.is_empty() || rest.starts_with(' '))
        })
    })
}

/// How many conflicts `text` still opens (`<<<<<<<` at a line start).
pub fn marker_count(text: &str) -> usize {
    text.split('\n')
        .filter(|line| line.starts_with("<<<<<<<"))
        .count()
}

/// `value` split after each newline, keeping the newlines.
fn lines(value: &[u16]) -> Vec<Text> {
    let mut result = Vec::new();
    let mut start = 0;
    for (index, unit) in value.iter().enumerate() {
        if *unit == NEWLINE {
            result.push(value[start..=index].to_vec());
            start = index + 1;
        }
    }
    if start < value.len() {
        result.push(value[start..].to_vec());
    }
    result
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Block {
    pub index: usize,
    pub start: usize,
    pub end: usize,
    pub current: Text,
    pub incoming: Text,
    pub original: Text,
    pub choice: Option<NativeConflictRegionChoice>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Row {
    pub current: Text,
    pub incoming: Text,
    pub current_line: Option<usize>,
    pub incoming_line: Option<usize>,
    pub block: Option<usize>,
    pub different: bool,
}

impl Row {
    fn new(
        current: Text,
        incoming: Text,
        current_line: Option<usize>,
        incoming_line: Option<usize>,
        block: Option<usize>,
        different: bool,
    ) -> Self {
        Self {
            current,
            incoming,
            current_line,
            incoming_line,
            block,
            different,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MergeDraft {
    pub text: Text,
    pub blocks: Vec<Block>,
    pub rows: Vec<Row>,
}

impl MergeDraft {
    pub fn from_file(file: &NativeConflictFile) -> Self {
        let text = utf16(&String::from_utf8_lossy(
            file.result.as_deref().unwrap_or_default(),
        ));
        let mut blocks: Vec<Block> = Vec::new();
        let mut rows = Vec::new();
        let all = lines(&text);
        let (mut cursor, mut offset, mut current_line, mut incoming_line) =
            (0usize, 0usize, 1usize, 1usize);
        while cursor < all.len() {
            let line = &all[cursor];
            if !starts_with(line, "<<<<<<<") {
                rows.push(Row::new(
                    line.clone(),
                    line.clone(),
                    Some(current_line),
                    Some(incoming_line),
                    None,
                    false,
                ));
                current_line += 1;
                incoming_line += 1;
                offset += line.len();
                cursor += 1;
                continue;
            }
            let start = offset;
            let first = cursor + 1;
            let mut separator = first;
            while separator < all.len() && !starts_with(&all[separator], "=======") {
                separator += 1;
            }
            let mut end = separator + 1;
            while end < all.len() && !starts_with(&all[end], ">>>>>>>") {
                end += 1;
            }
            if separator >= all.len() || end >= all.len() {
                rows.push(Row::new(
                    line.clone(),
                    line.clone(),
                    Some(current_line),
                    Some(incoming_line),
                    None,
                    false,
                ));
                current_line += 1;
                incoming_line += 1;
                offset += line.len();
                cursor += 1;
                continue;
            }
            // Diff3 adds ancestor lines between ||||||| and =======.
            let current_end = (first..separator)
                .find(|index| starts_with(&all[*index], "|||||||"))
                .unwrap_or(separator);
            let current: Text = all[first..current_end].concat();
            let incoming: Text = all[separator + 1..end].concat();
            let original: Text = all[cursor..=end].concat();
            let index = blocks.len();
            let left = lines(&current);
            let right = lines(&incoming);
            let count = left.len().max(right.len()).max(1);
            for row in 0..count {
                let current_number = (row < left.len()).then(|| {
                    current_line += 1;
                    current_line - 1
                });
                let incoming_number = (row < right.len()).then(|| {
                    incoming_line += 1;
                    incoming_line - 1
                });
                rows.push(Row::new(
                    left.get(row).cloned().unwrap_or_default(),
                    right.get(row).cloned().unwrap_or_default(),
                    current_number,
                    incoming_number,
                    Some(index),
                    false,
                ));
            }
            blocks.push(Block {
                index,
                start,
                end: start + original.len(),
                current,
                incoming,
                original,
                choice: None,
            });
            offset += all[cursor..=end].iter().map(Vec::len).sum::<usize>();
            cursor = end + 1;
        }
        let rows = stage_rows(file, &blocks).unwrap_or(rows);
        Self { text, blocks, rows }
    }

    /// Where each block sits in `rows`: (first row, row count).
    pub fn block_rows(&self) -> Vec<(usize, usize)> {
        let mut first = vec![0; self.blocks.len()];
        let mut count = vec![0; self.blocks.len()];
        for (index, row) in self.rows.iter().enumerate() {
            let Some(block) = row.block.filter(|block| *block < self.blocks.len()) else {
                continue;
            };
            if count[block] == 0 {
                first[block] = index;
            }
            count[block] += 1;
        }
        first.into_iter().zip(count).collect()
    }

    pub fn resolved_count(&self) -> usize {
        self.blocks
            .iter()
            .filter(|block| block.choice.is_some())
            .count()
    }

    pub fn unresolved_count(&self) -> usize {
        self.blocks.len() - self.resolved_count()
    }

    /// Takes `choice` in block `index`; taking the other side as well takes
    /// both. Returns the new text.
    pub fn take(&mut self, index: usize, choice: NativeConflictRegionChoice) -> &[u16] {
        use NativeConflictRegionChoice::{Both, Current, Incoming};
        let Some(block) = self.blocks.get(index) else {
            return &self.text;
        };
        let next = match (block.choice, choice) {
            (Some(Current), Current) | (Some(Incoming), Incoming) | (Some(Both), Both) => {
                block.choice
            }
            (Some(Current), Incoming) | (Some(Incoming), Current) => Some(Both),
            (Some(Both), Current) | (Some(Both), Incoming) => Some(Both),
            _ => Some(choice),
        };
        self.set(index, next)
    }

    /// Takes `choice` back out of block `index`.
    pub fn remove(&mut self, index: usize, choice: NativeConflictRegionChoice) -> &[u16] {
        use NativeConflictRegionChoice::{Both, Current, Incoming};
        let Some(block) = self.blocks.get(index) else {
            return &self.text;
        };
        let current = block.choice;
        let next = match (current, choice) {
            (Some(Both), Current) => Some(Incoming),
            (Some(Both), Incoming) => Some(Current),
            (Some(Current), Current) | (Some(Incoming), Incoming) | (Some(Both), Both) => None,
            _ => current,
        };
        self.set(index, next)
    }

    fn set(&mut self, index: usize, next: Option<NativeConflictRegionChoice>) -> &[u16] {
        let block = &self.blocks[index];
        let replacement = match next {
            Some(NativeConflictRegionChoice::Current) => block.current.clone(),
            Some(NativeConflictRegionChoice::Incoming) => block.incoming.clone(),
            Some(NativeConflictRegionChoice::Both) => {
                [block.current.clone(), block.incoming.clone()].concat()
            }
            None => block.original.clone(),
        };
        let (start, end) = (block.start, block.end);
        self.replace(start, end, &replacement, index);
        self.blocks[index].choice = next;
        &self.text
    }

    /// Follows a hand edit of the result to `updated`.
    pub fn edit(&mut self, updated: &[u16]) {
        if updated == self.text.as_slice() {
            return;
        }
        let text = &self.text;
        let mut prefix = 0;
        while prefix < text.len() && prefix < updated.len() && text[prefix] == updated[prefix] {
            prefix += 1;
        }
        let mut suffix = 0;
        while suffix < text.len() - prefix
            && suffix < updated.len() - prefix
            && text[text.len() - suffix - 1] == updated[updated.len() - suffix - 1]
        {
            suffix += 1;
        }
        let old_end = text.len() - suffix;
        let new_end = updated.len() - suffix;
        let new_length = updated.len();
        self.shift_ranges(prefix, old_end, new_end - prefix, None, new_length);
        self.text = updated.to_vec();
    }

    fn replace(&mut self, start: usize, end: usize, replacement: &[u16], selected: usize) {
        let mut text = self.text[..start].to_vec();
        text.extend_from_slice(replacement);
        text.extend_from_slice(&self.text[end..]);
        let new_length = text.len();
        self.text = text;
        self.shift_ranges(start, end, replacement.len(), Some(selected), new_length);
    }

    fn shift_ranges(
        &mut self,
        start: usize,
        end: usize,
        replacement_length: usize,
        selected: Option<usize>,
        new_length: usize,
    ) {
        let delta = replacement_length as isize - (end - start) as isize;
        let shift = |value: usize| (value as isize + delta).max(0) as usize;
        for block in &mut self.blocks {
            if Some(block.index) == selected {
                block.start = start;
                block.end = start + replacement_length;
            } else if block.start >= end {
                block.start = shift(block.start);
                block.end = shift(block.end);
            } else if block.end > start {
                // Keep a hand-edited block attached to its updated span.
                block.start = block.start.min(start);
                block.end = shift(block.end).clamp(block.start, new_length);
            }
        }
    }
}

/// Rows aligned to the files' own lines, when every region can be found in
/// both sides; None keeps the merge-result projection.
fn stage_rows(file: &NativeConflictFile, blocks: &[Block]) -> Option<Vec<Row>> {
    if (file.current.present && file.current.content.is_none())
        || (file.incoming.present && file.incoming.content.is_none())
        || file.regions.len() != blocks.len()
    {
        return None;
    }
    let decode = |bytes: &[u8]| std::str::from_utf8(bytes).ok().map(utf16);
    let current = lines(&decode(
        file.current.content.as_deref().unwrap_or_default(),
    )?);
    let incoming = lines(&decode(
        file.incoming.content.as_deref().unwrap_or_default(),
    )?);
    let mut rows = Vec::new();
    let (mut left, mut right) = (0, 0);
    for (region, conflict) in file.regions.iter().enumerate() {
        let left_conflict = lines(&decode(&conflict.current)?);
        let right_conflict = lines(&decode(&conflict.incoming)?);
        // An empty side has no unique anchor.
        if left_conflict.is_empty() || right_conflict.is_empty() {
            return None;
        }
        let left_start = find_lines(&current, &left_conflict, left)?;
        let right_start = find_lines(&incoming, &right_conflict, right)?;
        align_lines(
            &mut rows,
            &current,
            &incoming,
            left,
            left_start,
            right,
            right_start,
        );
        for row in 0..left_conflict.len().max(right_conflict.len()) {
            rows.push(Row::new(
                left_conflict.get(row).cloned().unwrap_or_default(),
                right_conflict.get(row).cloned().unwrap_or_default(),
                (row < left_conflict.len()).then_some(left_start + row + 1),
                (row < right_conflict.len()).then_some(right_start + row + 1),
                Some(region),
                false,
            ));
        }
        left = left_start + left_conflict.len();
        right = right_start + right_conflict.len();
    }
    align_lines(
        &mut rows,
        &current,
        &incoming,
        left,
        current.len(),
        right,
        incoming.len(),
    );
    Some(rows)
}

fn find_lines(haystack: &[Text], needle: &[Text], start: usize) -> Option<usize> {
    (start..=haystack.len().saturating_sub(needle.len())).find(|index| {
        index + needle.len() <= haystack.len() && haystack[*index..*index + needle.len()] == *needle
    })
}

fn align_lines(
    rows: &mut Vec<Row>,
    current: &[Text],
    incoming: &[Text],
    mut left: usize,
    left_end: usize,
    mut right: usize,
    right_end: usize,
) {
    while left < left_end || right < right_end {
        if left >= left_end {
            rows.push(Row::new(
                Vec::new(),
                incoming[right].clone(),
                None,
                Some(right + 1),
                None,
                true,
            ));
            right += 1;
            continue;
        }
        if right >= right_end {
            rows.push(Row::new(
                current[left].clone(),
                Vec::new(),
                Some(left + 1),
                None,
                None,
                true,
            ));
            left += 1;
            continue;
        }
        if current[left] == incoming[right] {
            rows.push(Row::new(
                current[left].clone(),
                incoming[right].clone(),
                Some(left + 1),
                Some(right + 1),
                None,
                false,
            ));
            left += 1;
            right += 1;
            continue;
        }
        let left_match = look_ahead(current, left + 1, left_end, &incoming[right]);
        let right_match = look_ahead(incoming, right + 1, right_end, &current[left]);
        if let Some(found) = left_match
            && right_match.is_none_or(|other| found - left <= other - right)
        {
            rows.push(Row::new(
                current[left].clone(),
                Vec::new(),
                Some(left + 1),
                None,
                None,
                true,
            ));
            left += 1;
        } else if right_match.is_some() {
            rows.push(Row::new(
                Vec::new(),
                incoming[right].clone(),
                None,
                Some(right + 1),
                None,
                true,
            ));
            right += 1;
        } else {
            rows.push(Row::new(
                current[left].clone(),
                incoming[right].clone(),
                Some(left + 1),
                Some(right + 1),
                None,
                true,
            ));
            left += 1;
            right += 1;
        }
    }
}

fn look_ahead(lines: &[Text], start: usize, end: usize, value: &[u16]) -> Option<usize> {
    (start..(start + 24).min(end)).find(|index| lines[*index] == value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use NativeConflictRegionChoice::{Both, Current, Incoming};
    use gitlama_contract::conflict::{
        NativeConflictFileKind, NativeConflictRegion, NativeConflictSide,
    };

    fn side(content: Option<&str>) -> NativeConflictSide {
        NativeConflictSide {
            present: content.is_some(),
            mode: None,
            content: content.map(|text| text.as_bytes().to_vec()),
            byte_count: content.map_or(0, str::len) as u64,
        }
    }

    fn file(
        result: &str,
        current: Option<&str>,
        incoming: Option<&str>,
        regions: Vec<(&str, &str)>,
    ) -> NativeConflictFile {
        NativeConflictFile {
            path: b"f.txt".to_vec(),
            kind: NativeConflictFileKind::Text,
            ancestor: side(None),
            current: side(current),
            incoming: side(incoming),
            result: Some(result.as_bytes().to_vec()),
            result_present: true,
            result_mode: None,
            marker_free: false,
            regions: regions
                .into_iter()
                .enumerate()
                .map(|(index, (current, incoming))| NativeConflictRegion {
                    index: index as u32,
                    current: current.as_bytes().to_vec(),
                    incoming: incoming.as_bytes().to_vec(),
                    ancestor: None,
                })
                .collect(),
            fingerprint: 1,
            can_undo_resolution: false,
        }
    }

    const RESULT: &str = "a\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> topic\nz\n";

    #[test]
    fn markers_follow_gits_rule() {
        assert!(has_conflict_markers(RESULT));
        assert!(has_conflict_markers("x\n=======\r\ny"));
        assert!(!has_conflict_markers("Title\n========\n"));
        assert!(!has_conflict_markers("<<<<<<<<< no"));
        assert_eq!(marker_count(RESULT), 1);
    }

    #[test]
    fn a_result_parses_into_its_regions_and_rows() {
        let draft = MergeDraft::from_file(&file(RESULT, None, None, vec![]));
        assert_eq!(draft.blocks.len(), 1);
        let block = &draft.blocks[0];
        assert_eq!(string(&block.current), "ours\n");
        assert_eq!(string(&block.incoming), "theirs\n");
        assert_eq!(
            (block.start, block.end),
            (
                2,
                2 + "<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> topic\n".len()
            )
        );
        assert_eq!(draft.rows.len(), 3);
        assert_eq!(draft.rows[1].block, Some(0));
        assert_eq!(
            (draft.rows[2].current_line, draft.rows[2].incoming_line),
            (Some(3), Some(3))
        );
        assert_eq!(draft.block_rows(), vec![(1, 1)]);
    }

    #[test]
    fn choices_combine_and_come_back_out() {
        let mut draft = MergeDraft::from_file(&file(RESULT, None, None, vec![]));
        assert_eq!(string(draft.take(0, Current)), "a\nours\nz\n");
        assert_eq!(string(draft.take(0, Incoming)), "a\nours\ntheirs\nz\n");
        assert_eq!(draft.blocks[0].choice, Some(Both));
        assert_eq!(string(draft.remove(0, Current)), "a\ntheirs\nz\n");
        assert_eq!(string(draft.remove(0, Incoming)), RESULT);
        assert_eq!(draft.unresolved_count(), 1);
    }

    #[test]
    fn a_hand_edit_moves_the_regions_after_it() {
        let text =
            "<<<<<<< a\n1\n=======\n2\n>>>>>>> b\nmid\n<<<<<<< a\n3\n=======\n4\n>>>>>>> b\n";
        let mut draft = MergeDraft::from_file(&file(text, None, None, vec![]));
        let second = draft.blocks[1].start;
        let mut edited = utf16("XX");
        edited.extend_from_slice(&draft.text);
        draft.edit(&edited);
        assert_eq!(draft.blocks[1].start, second + 2);
        let result = string(draft.take(1, Incoming)).to_owned();
        assert!(result.ends_with("mid\n4\n"));
    }

    #[test]
    fn rows_align_to_the_files_own_lines() {
        let current = "a\nkeep\nours\nz\n";
        let incoming = "a\ntheirs\nz\nextra\n";
        let draft = MergeDraft::from_file(&file(
            RESULT,
            Some(current),
            Some(incoming),
            vec![("ours\n", "theirs\n")],
        ));
        let shown: Vec<(String, String, Option<usize>)> = draft
            .rows
            .iter()
            .map(|row| (string(&row.current), string(&row.incoming), row.block))
            .collect();
        assert_eq!(shown[0], ("a\n".into(), "a\n".into(), None));
        assert_eq!(shown[1], ("keep\n".into(), String::new(), None));
        assert_eq!(shown[2], ("ours\n".into(), "theirs\n".into(), Some(0)));
        assert_eq!(
            shown.last().unwrap(),
            &(String::new(), "extra\n".into(), None)
        );
        assert!(draft.rows[1].different);
    }
}
