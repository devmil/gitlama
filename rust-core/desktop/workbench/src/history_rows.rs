//! What one History graph row shows (the Dart history_pane `rowAt` and the
//! graph view's reference chips): the lanes through it, its node, its
//! references as chips and its commit metadata.

use crate::history::{HistoryService, WORKTREE_OBJECT_ID, is_worktree};
use crate::sidebar::{branch_reference, display_reference, remote_branch_reference};
use gitlama_contract::dto::{
    NativeHistoryMetadataFailure, NativeHistoryNodeShape, NativeHistorySegmentKind,
    NativeRepositoryRefs,
};
use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

/// The most reference chips a row shows before a `+n` count.
pub const MAX_REF_CHIPS: usize = 2;

/// Reference values derived from one reference snapshot (the Dart
/// ReferenceProjection).
#[derive(Default)]
pub struct ReferenceContext {
    /// Local branches whose remote upstream has the same target: full name
    /// to the upstream's full name.
    pub aligned_upstreams: HashMap<String, String>,
    /// The checked-out branch's full name.
    pub checked_out: Option<String>,
    /// Ahead and behind counts of each local branch, by full name.
    pub sync_counts: HashMap<String, (u64, u64)>,
}

impl ReferenceContext {
    pub fn new(refs: &NativeRepositoryRefs) -> Self {
        let mut remote_targets = HashMap::new();
        for remote in &refs.remotes {
            for branch in &remote.branches {
                remote_targets.insert(
                    remote_branch_reference(remote, branch),
                    branch.target.clone(),
                );
            }
        }
        let mut aligned_upstreams = HashMap::new();
        for branch in &refs.branches {
            let Some(upstream) = &branch.upstream else {
                continue;
            };
            let upstream = String::from_utf8_lossy(upstream).into_owned();
            if !upstream.starts_with("refs/remotes/") {
                continue;
            }
            if remote_targets.get(&upstream) != Some(&branch.target) {
                continue;
            }
            aligned_upstreams.insert(branch_reference(branch), upstream);
        }
        Self {
            aligned_upstreams,
            checked_out: refs
                .branches
                .iter()
                .find(|branch| branch.head)
                .map(branch_reference),
            sync_counts: refs
                .branches
                .iter()
                .map(|branch| (branch_reference(branch), (branch.ahead, branch.behind)))
                .collect(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Kind {
    Local,
    Remote,
    Tag,
    Stash,
    Other,
}

impl Kind {
    fn of(full: &str) -> Self {
        if full.starts_with("refs/heads/") {
            Kind::Local
        } else if full.starts_with("refs/remotes/") {
            Kind::Remote
        } else if full.starts_with("refs/tags/") {
            Kind::Tag
        } else if full == "refs/stash" {
            Kind::Stash
        } else {
            Kind::Other
        }
    }

    fn name(self) -> &'static str {
        match self {
            Kind::Local => "local",
            Kind::Remote => "remote",
            Kind::Tag => "tag",
            Kind::Stash => "stash",
            Kind::Other => "other",
        }
    }
}

struct DisplayReference {
    raw: String,
    kind: Kind,
    tracking: Option<String>,
}

/// The row's references as chips: a local branch and its aligned upstream
/// share one chip; the checked-out branch comes first, then local, remote,
/// tags, the stash and the rest.
fn display_references(
    refs: &[String],
    context: &ReferenceContext,
    current: bool,
) -> Vec<DisplayReference> {
    let present: HashSet<&str> = refs.iter().map(String::as_str).collect();
    let mut merged_remotes = HashSet::new();
    for reference in refs {
        if let Some(upstream) = context.aligned_upstreams.get(reference)
            && present.contains(upstream.as_str())
        {
            merged_remotes.insert(upstream.clone());
        }
    }
    let mut shown: Vec<DisplayReference> = refs
        .iter()
        .filter(|reference| !merged_remotes.contains(*reference))
        .map(|reference| {
            let kind = Kind::of(reference);
            let tracking = context
                .aligned_upstreams
                .get(reference)
                .filter(|upstream| present.contains(upstream.as_str()))
                .filter(|_| matches!(kind, Kind::Local | Kind::Remote | Kind::Tag))
                .cloned();
            DisplayReference {
                raw: reference.clone(),
                kind,
                tracking,
            }
        })
        .collect();
    let checked_out = context.checked_out.as_deref().filter(|_| current);
    if let Some(checked_out) = checked_out
        && !refs.iter().any(|reference| reference == checked_out)
    {
        shown.push(DisplayReference {
            raw: checked_out.to_owned(),
            kind: Kind::Local,
            tracking: None,
        });
    }
    let rank = |reference: &DisplayReference| {
        if Some(reference.raw.as_str()) == checked_out {
            0
        } else {
            1 + reference.kind as u8
        }
    };
    shown.sort_by_key(rank);
    shown
}

fn shape_index(shape: NativeHistoryNodeShape) -> u8 {
    match shape {
        NativeHistoryNodeShape::Commit => 0,
        NativeHistoryNodeShape::Merge => 1,
        NativeHistoryNodeShape::Boundary => 2,
        NativeHistoryNodeShape::Graft => 3,
        NativeHistoryNodeShape::Replace => 4,
        NativeHistoryNodeShape::Wip => 5,
        NativeHistoryNodeShape::WipConflict => 6,
        NativeHistoryNodeShape::Stash => 7,
    }
}

fn segment_kind_index(kind: NativeHistorySegmentKind) -> u8 {
    match kind {
        NativeHistorySegmentKind::Straight => 0,
        NativeHistorySegmentKind::Join => 1,
        NativeHistorySegmentKind::Merge => 2,
        NativeHistorySegmentKind::Octopus => 3,
        NativeHistorySegmentKind::Boundary => 4,
        NativeHistorySegmentKind::Missing => 5,
        NativeHistorySegmentKind::CollapsedMerge => 6,
    }
}

fn metadata_failure(failure: Option<NativeHistoryMetadataFailure>) -> Option<&'static str> {
    failure.map(|failure| match failure {
        NativeHistoryMetadataFailure::Missing => "missing",
        NativeHistoryMetadataFailure::ObjectTooLarge => "objectTooLarge",
        NativeHistoryMetadataFailure::AuthorTooLarge => "authorTooLarge",
        NativeHistoryMetadataFailure::SubjectTooLarge => "subjectTooLarge",
        NativeHistoryMetadataFailure::MalformedCommit => "malformedCommit",
    })
}

/// One History row as QML reads it.
pub struct RowView {
    pub object_id: String,
    pub loading: bool,
    pub lit: bool,
    /// {lane, shape, current, segments, wipStaged, wipChanged} for the
    /// native graph painter.
    pub graph: Value,
    /// The highest lane the row draws in: the text starts after it.
    pub occupied_lane: u32,
    pub subject: String,
    pub worktree: bool,
    pub author: String,
    pub avatar_hash: String,
    pub author_time: i64,
    pub metadata_failure: Option<&'static str>,
    pub chips: Value,
    pub overflow: Value,
    pub detached: bool,
    pub current: bool,
    pub selected: bool,
    pub compared: bool,
    pub search_match: bool,
    pub refs_text: String,
    pub hidden_refs: u32,
}

/// Builds row `index`, or a placeholder (asking History to load it).
pub fn row_view(
    history: &Rc<HistoryService>,
    index: u64,
    context: &ReferenceContext,
    head: Option<&str>,
) -> RowView {
    let Some(row) = history.row_at(index) else {
        history.ensure_index(index);
        return RowView {
            object_id: format!("loading-{index}"),
            loading: true,
            lit: false,
            graph: Value::Null,
            occupied_lane: 0,
            subject: String::new(),
            worktree: false,
            author: String::new(),
            avatar_hash: String::new(),
            author_time: 0,
            metadata_failure: None,
            chips: Value::Array(Vec::new()),
            overflow: Value::Null,
            detached: false,
            current: false,
            selected: false,
            compared: false,
            search_match: false,
            refs_text: String::new(),
            hidden_refs: 0,
        };
    };
    let segments = history.segments_for(&row.object_id);
    let occupied_lane = segments.iter().fold(row.lane, |lane, segment| {
        lane.max(segment.from_lane).max(segment.to_lane)
    });
    let current = head == Some(row.object_id.as_str());
    let refs: Vec<String> = row
        .refs
        .iter()
        .map(|bytes| String::from_utf8_lossy(bytes).into_owned())
        .collect();
    let display = display_references(&refs, context, current);
    let detached = current && context.checked_out.is_none();
    let visible = MAX_REF_CHIPS - usize::from(detached);
    let chips: Vec<Value> = display
        .iter()
        .take(visible)
        .map(|reference| {
            let head_chip = current && Some(&reference.raw) == context.checked_out.as_ref();
            let (ahead, behind) = if reference.tracking.is_none() {
                context
                    .sync_counts
                    .get(&reference.raw)
                    .copied()
                    .unwrap_or_default()
            } else {
                (0, 0)
            };
            json!({
                "raw": reference.raw,
                "label": display_reference(&reference.raw),
                "kind": if head_chip { "head" } else { reference.kind.name() },
                "upstream": reference.tracking.as_deref().map(display_reference),
                "tracking": reference.tracking,
                "ahead": ahead,
                "behind": behind,
            })
        })
        .collect();
    let overflow = if display.len() > visible {
        json!({
            "count": display.len() - visible,
            "names": display.iter().skip(visible).map(|reference| reference.raw.clone()).collect::<Vec<_>>().join("\n"),
        })
    } else {
        Value::Null
    };
    let worktree = is_worktree(&row);
    RowView {
        graph: json!({
            "lane": row.lane,
            "shape": shape_index(row.shape),
            "current": current,
            "wipStaged": row.wip_staged_files,
            "wipChanged": row.wip_changed_files,
            "segments": segments
                .iter()
                .map(|segment| json!([
                    segment.from_lane,
                    segment.to_lane,
                    segment_kind_index(segment.kind),
                    segment.starts_at_top,
                    segment.ends_at_center,
                    i32::from(segment.lit),
                ]))
                .collect::<Vec<_>>(),
        }),
        occupied_lane,
        subject: if worktree {
            String::new()
        } else {
            String::from_utf8_lossy(&row.subject).into_owned()
        },
        worktree,
        author: String::from_utf8_lossy(&row.author).into_owned(),
        avatar_hash: row.avatar_hash.clone(),
        author_time: row.author_time,
        metadata_failure: metadata_failure(row.metadata_failure),
        chips: Value::Array(chips),
        overflow,
        detached,
        current,
        selected: row.selected,
        compared: row.compared,
        search_match: history.is_search_match(&row.object_id),
        refs_text: refs.join(", "),
        hidden_refs: row.ref_count.saturating_sub(row.refs.len() as u32),
        lit: row.lit,
        loading: false,
        object_id: row.object_id,
    }
}

/// The object id the worktree row carries.
pub fn worktree_object_id() -> &'static str {
    WORKTREE_OBJECT_ID
}

#[cfg(test)]
mod tests {
    use super::*;

    fn context() -> ReferenceContext {
        ReferenceContext {
            aligned_upstreams: HashMap::from([(
                "refs/heads/main".to_owned(),
                "refs/remotes/origin/main".to_owned(),
            )]),
            checked_out: Some("refs/heads/main".to_owned()),
            sync_counts: HashMap::new(),
        }
    }

    #[test]
    fn an_aligned_upstream_shares_its_branch_chip() {
        let refs = vec![
            "refs/tags/v1".to_owned(),
            "refs/remotes/origin/main".to_owned(),
            "refs/heads/main".to_owned(),
        ];
        let shown = display_references(&refs, &context(), true);
        let raws: Vec<&str> = shown
            .iter()
            .map(|reference| reference.raw.as_str())
            .collect();
        assert_eq!(raws, ["refs/heads/main", "refs/tags/v1"]);
        assert_eq!(
            shown[0].tracking.as_deref(),
            Some("refs/remotes/origin/main")
        );
    }

    #[test]
    fn the_checked_out_branch_joins_the_current_row() {
        let shown = display_references(&[], &context(), true);
        assert_eq!(shown.len(), 1);
        assert!(display_references(&[], &context(), false).is_empty());
    }
}
