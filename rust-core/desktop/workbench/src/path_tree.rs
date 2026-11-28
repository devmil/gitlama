//! Flattens items with '/'-separated paths into the visible rows of a file
//! list or tree (Meridian's MeridianPathTree). Pure logic: the presentation
//! builds the rows' items. Every file list arranges a tree the same way.

use std::cmp::Ordering;
use std::collections::{BTreeMap, HashSet};

/// One visible row: a folder or a file.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Row<T> {
    pub directory: bool,
    /// `a/b` for the folder `b` inside `a`; the item's full path for a
    /// file. Folder identities are what the collapsed set holds.
    pub identity: String,
    /// The segment name in a tree, the full path in a list.
    pub label: String,
    /// Nesting level; 0 at the root and for every row of a list.
    pub depth: usize,
    /// The file's item; None for a folder.
    pub item: Option<T>,
    /// Every file item below a folder, at any depth: what a folder's
    /// actions apply to. Empty for a file.
    pub descendants: Vec<T>,
}

struct Node<T> {
    identity: String,
    directories: BTreeMap<String, Node<T>>,
    files: Vec<(T, String)>,
}

impl<T: Clone> Node<T> {
    fn new(identity: String) -> Self {
        Self {
            identity,
            directories: BTreeMap::new(),
            files: Vec::new(),
        }
    }

    fn descendants(&self, into: &mut Vec<T>) {
        into.extend(self.files.iter().map(|(item, _)| item.clone()));
        for directory in self.directories.values() {
            directory.descendants(into);
        }
    }
}

/// The visible rows for `items`.
///
/// As a tree each path is split at `/` (backslashes count as `/`; empty
/// segments are dropped). At every level the folders come first, sorted by
/// name, then the files, sorted by `compare`. A folder whose identity is in
/// `collapsed` keeps its row but hides everything below it. As a list the
/// result is the files alone, sorted the same way, at depth 0 and labelled
/// with their full path.
pub fn flatten<T: Clone>(
    items: impl IntoIterator<Item = T>,
    path_of: impl Fn(&T) -> String,
    collapsed: &HashSet<String>,
    tree: bool,
    compare: Option<&dyn Fn(&T, &T) -> Ordering>,
) -> Vec<Row<T>> {
    let by_path = |a: &T, b: &T| path_of(a).cmp(&path_of(b));
    let order = |a: &T, b: &T| compare.map_or_else(|| by_path(a, b), |compare| compare(a, b));
    if !tree {
        let mut files: Vec<T> = items.into_iter().collect();
        files.sort_by(order);
        return files
            .into_iter()
            .map(|item| {
                let path = path_of(&item);
                Row {
                    directory: false,
                    identity: path.clone(),
                    label: path,
                    depth: 0,
                    item: Some(item),
                    descendants: Vec::new(),
                }
            })
            .collect();
    }
    let mut root = Node::new(String::new());
    for item in items {
        let path = path_of(&item).replace('\\', "/");
        let parts: Vec<&str> = path.split('/').filter(|part| !part.is_empty()).collect();
        let mut node = &mut root;
        let mut identity = String::new();
        for part in parts.iter().take(parts.len().saturating_sub(1)) {
            identity = if identity.is_empty() {
                (*part).to_owned()
            } else {
                format!("{identity}/{part}")
            };
            let next = identity.clone();
            node = node
                .directories
                .entry((*part).to_owned())
                .or_insert_with(|| Node::new(next));
        }
        let name = parts.last().copied().unwrap_or_default().to_owned();
        node.files.push((item, name));
    }
    let mut rows = Vec::new();
    fn visit<T: Clone>(
        node: &Node<T>,
        depth: usize,
        rows: &mut Vec<Row<T>>,
        collapsed: &HashSet<String>,
        path_of: &dyn Fn(&T) -> String,
        order: &dyn Fn(&T, &T) -> Ordering,
    ) {
        for (name, directory) in &node.directories {
            let mut descendants = Vec::new();
            directory.descendants(&mut descendants);
            rows.push(Row {
                directory: true,
                identity: directory.identity.clone(),
                label: name.clone(),
                depth,
                item: None,
                descendants,
            });
            if !collapsed.contains(&directory.identity) {
                visit(directory, depth + 1, rows, collapsed, path_of, order);
            }
        }
        let mut files: Vec<&(T, String)> = node.files.iter().collect();
        files.sort_by(|a, b| order(&a.0, &b.0));
        for (item, name) in files {
            rows.push(Row {
                directory: false,
                identity: path_of(item),
                label: name.clone(),
                depth,
                item: Some(item.clone()),
                descendants: Vec::new(),
            });
        }
    }
    visit(&root, 0, &mut rows, collapsed, &path_of, &order);
    rows
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shown(rows: &[Row<&str>]) -> Vec<String> {
        rows.iter()
            .map(|row| {
                format!(
                    "{}{}{}",
                    "  ".repeat(row.depth),
                    row.label,
                    if row.directory { "/" } else { "" }
                )
            })
            .collect()
    }

    #[test]
    fn folders_come_first_then_files_at_every_level() {
        let items = [
            "b.txt",
            "src/main.rs",
            "src/lib/a.rs",
            "a.txt",
            "docs\\guide.md",
        ];
        let rows = flatten(
            items,
            |item| (*item).to_owned(),
            &HashSet::new(),
            true,
            None,
        );
        assert_eq!(
            shown(&rows),
            [
                "docs/",
                "  guide.md",
                "src/",
                "  lib/",
                "    a.rs",
                "  main.rs",
                "a.txt",
                "b.txt"
            ]
        );
        let src = rows.iter().find(|row| row.identity == "src").unwrap();
        assert_eq!(src.descendants, ["src/main.rs", "src/lib/a.rs"]);
        assert_eq!(
            rows.iter()
                .find(|row| row.label == "a.rs")
                .unwrap()
                .identity,
            "src/lib/a.rs"
        );
    }

    #[test]
    fn collapsed_folders_keep_their_row_and_hide_their_contents() {
        let items = ["src/main.rs", "src/lib/a.rs", "a.txt"];
        let collapsed: HashSet<String> = ["src/lib".to_owned()].into();
        let rows = flatten(items, |item| (*item).to_owned(), &collapsed, true, None);
        assert_eq!(shown(&rows), ["src/", "  lib/", "  main.rs", "a.txt"]);
        let all: HashSet<String> = ["src".to_owned()].into();
        assert_eq!(
            shown(&flatten(items, |item| (*item).to_owned(), &all, true, None)),
            ["src/", "a.txt"]
        );
    }

    #[test]
    fn a_list_is_the_sorted_files_with_full_paths() {
        let rows = flatten(
            ["b/x", "a"],
            |item| (*item).to_owned(),
            &HashSet::new(),
            false,
            None,
        );
        assert_eq!(shown(&rows), ["a", "b/x"]);
    }
}
