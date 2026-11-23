//! Creating and applying patches: what a patch
//! contains is decided from where the user asked for it; the window only
//! chooses the destination. A repository on another computer builds the
//! patch there and it is saved on this one.

use crate::backend::SessionCalls;
use crate::changes::{ChangesService, other_side, unique_command_paths};
use crate::history::HistoryService;
use crate::session::{BackendKind, SessionIdentity};
use crate::workspace::WorkspaceService;
use gitlama_contract::dto::{
    NativeHistoryPage, NativePatchApplyExecutionResult, NativePatchApplyExecutionState,
    NativePatchApplyPreview, NativePatchExportExecutionResult, NativePatchExportExecutionState,
    NativePatchExportPreview, NativePatchExportRequest, NativePatchExportScope, NativePatchFormat,
    NativePatchSide, NativeStagingSide,
};
use std::rc::Rc;

/// Where a patch was asked for.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Source {
    /// What History shows: the compared commits, the selected commit(s) as
    /// one or a range, or the working tree; `commit` names one commit.
    History { commit: Option<String> },
    /// The commit or comparison whose diff is on screen, limited to `paths`.
    Diff {
        base: Option<String>,
        commit: String,
        paths: Vec<Vec<u8>>,
    },
    /// The Changes selection: the focused list's selected files, the other
    /// list's when the focused one has none, else everything focused.
    Selection,
    /// The chosen lines `rows` of the working diff `request_id`.
    Lines { request_id: u64, rows: Vec<String> },
    /// Exactly `paths` on `side`.
    Files {
        side: NativeStagingSide,
        paths: Vec<Vec<u8>>,
    },
    /// The Changes files `keys` on `side` (a folder's files).
    Keys {
        side: NativeStagingSide,
        keys: Vec<String>,
    },
}

fn patch_side(side: NativeStagingSide) -> NativePatchSide {
    match side {
        NativeStagingSide::Unstaged => NativePatchSide::Unstaged,
        NativeStagingSide::Staged => NativePatchSide::Staged,
    }
}

fn empty(destination: String, overwrite: bool) -> NativePatchExportRequest {
    NativePatchExportRequest {
        working_diff_request_id: None,
        row_ids: Vec::new(),
        selected_side: None,
        selected_paths: Vec::new(),
        focused_side: None,
        comparison_old: None,
        comparison_new: None,
        range_commits: Vec::new(),
        commit: None,
        history_paths: Vec::new(),
        workspace_default: false,
        destination_directory: destination,
        overwrite,
    }
}

/// The request of a History patch.
pub fn history_request(
    page: Option<&NativeHistoryPage>,
    commit: Option<String>,
    destination: String,
    overwrite: bool,
) -> NativePatchExportRequest {
    let (comparison_old, comparison_new) = match (commit.is_none(), page) {
        (true, Some(page)) => (
            page.comparison_old_object_id.clone(),
            page.comparison_new_object_id.clone(),
        ),
        _ => (None, None),
    };
    let mut single = commit;
    let mut range = Vec::new();
    if single.is_none() && (comparison_old.is_none() || comparison_new.is_none()) {
        let selected: Vec<String> = page
            .map(|page| {
                page.selected_object_ids
                    .iter()
                    .filter(|id| id.as_str() != "wip")
                    .cloned()
                    .collect()
            })
            .unwrap_or_default();
        if selected.len() == 1 {
            single = selected.into_iter().next();
        } else if selected.len() > 1 {
            // The selection in the order the graph shows it, oldest first.
            let mut visible: Vec<String> = page
                .map(|page| {
                    page.rows
                        .iter()
                        .filter(|row| selected.contains(&row.object_id))
                        .map(|row| row.object_id.clone())
                        .collect()
                })
                .filter(|rows: &Vec<String>| !rows.is_empty())
                .unwrap_or(selected);
            visible.reverse();
            range = visible;
        }
    }
    let workspace_default = comparison_old.is_none()
        && comparison_new.is_none()
        && range.is_empty()
        && single.is_none();
    NativePatchExportRequest {
        comparison_old,
        comparison_new,
        range_commits: range,
        commit: single,
        workspace_default,
        ..empty(destination, overwrite)
    }
}

/// The request of a patch of a shown diff (PatchRequestBuilder.diff).
pub fn diff_request(
    base: Option<String>,
    commit: String,
    paths: Vec<Vec<u8>>,
    destination: String,
    overwrite: bool,
) -> NativePatchExportRequest {
    let comparison = base.is_some();
    NativePatchExportRequest {
        comparison_new: comparison.then(|| commit.clone()),
        comparison_old: base,
        commit: (!comparison).then_some(commit),
        history_paths: paths,
        ..empty(destination, overwrite)
    }
}

/// The request of a working-tree patch (PatchRequestBuilder.workingTree).
pub fn working_tree_request(
    side: NativeStagingSide,
    paths: Vec<Vec<u8>>,
    destination: String,
    overwrite: bool,
) -> NativePatchExportRequest {
    let any = !paths.is_empty();
    NativePatchExportRequest {
        selected_side: any.then(|| patch_side(side)),
        focused_side: (!any).then(|| patch_side(side)),
        selected_paths: paths,
        ..empty(destination, overwrite)
    }
}

pub fn scope_key(scope: NativePatchExportScope) -> &'static str {
    match scope {
        NativePatchExportScope::Lines => "patchScopeLines",
        NativePatchExportScope::SelectedFilesUnstaged => "patchScopeSelectedUnstaged",
        NativePatchExportScope::SelectedFilesStaged => "patchScopeSelectedStaged",
        NativePatchExportScope::Unstaged => "patchScopeUnstaged",
        NativePatchExportScope::Staged => "patchScopeStaged",
        NativePatchExportScope::Head => "patchScopeHead",
        NativePatchExportScope::Commit => "patchScopeCommit",
        NativePatchExportScope::Range => "patchScopeRange",
        NativePatchExportScope::Compare => "patchScopeCompare",
    }
}

pub fn format_key(format: NativePatchFormat) -> &'static str {
    match format {
        NativePatchFormat::UnifiedDiff => "patchFormatUnified",
        NativePatchFormat::FormatPatch => "patchFormatEmail",
    }
}

/// A finished export: (message key, failed).
pub fn export_message(state: NativePatchExportExecutionState) -> (&'static str, bool) {
    match state {
        NativePatchExportExecutionState::Completed => ("patchExportDone", false),
        NativePatchExportExecutionState::Stale => ("patchExportStale", true),
        NativePatchExportExecutionState::Failed => ("patchExportFailed", true),
    }
}

/// A finished apply: (message key, tone: success, warning or error).
pub fn apply_message(state: NativePatchApplyExecutionState) -> (&'static str, &'static str) {
    match state {
        NativePatchApplyExecutionState::Completed => ("patchApplyDone", "success"),
        NativePatchApplyExecutionState::Stale => ("patchApplyStale", "error"),
        NativePatchApplyExecutionState::Failed => ("patchApplyFailed", "error"),
        NativePatchApplyExecutionState::ReconciledWithWarning => ("patchApplyWarning", "warning"),
        NativePatchApplyExecutionState::OutcomeUncertain => ("patchApplyOutcomeUncertain", "error"),
    }
}

pub struct PatchService {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    history: Rc<HistoryService>,
    changes: Rc<ChangesService>,
}

/// Why a step failed: the dialog shows its generic failure.
#[derive(Debug, PartialEq, Eq)]
pub struct PatchFailure;

impl PatchService {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        history: Rc<HistoryService>,
        changes: Rc<ChangesService>,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            history,
            changes,
        })
    }

    /// The active repository's session, which a dialog keeps.
    pub fn session(&self) -> Option<SessionIdentity> {
        self.workspace.current().map(|session| session.identity)
    }

    /// Whether `identity` is still the active session.
    pub fn active(&self, identity: SessionIdentity) -> bool {
        self.session() == Some(identity)
    }

    /// The export request of `source` written to `destination`.
    pub fn request(
        &self,
        source: &Source,
        destination: String,
        overwrite: bool,
    ) -> NativePatchExportRequest {
        match source {
            Source::History { commit } => history_request(
                self.history.current().page.as_deref(),
                commit.clone(),
                destination,
                overwrite,
            ),
            Source::Diff {
                base,
                commit,
                paths,
            } => diff_request(
                base.clone(),
                commit.clone(),
                paths.clone(),
                destination,
                overwrite,
            ),
            Source::Files { side, paths } => {
                working_tree_request(*side, paths.clone(), destination, overwrite)
            }
            Source::Keys { side, keys } => {
                let entries: Vec<_> = self
                    .workspace
                    .current()
                    .and_then(|session| session.snapshot.status.clone())
                    .map(|status| {
                        crate::changes::entries_on(&status, *side)
                            .into_iter()
                            .filter(|entry| keys.contains(&crate::changes::change_key(entry)))
                            .collect()
                    })
                    .unwrap_or_default();
                working_tree_request(
                    *side,
                    unique_command_paths(&entries),
                    destination,
                    overwrite,
                )
            }
            Source::Lines { request_id, rows } => NativePatchExportRequest {
                working_diff_request_id: Some(*request_id),
                row_ids: rows.clone(),
                ..empty(destination, overwrite)
            },
            Source::Selection => {
                let Some(tab) = self.workspace.active_tab_id() else {
                    return working_tree_request(
                        NativeStagingSide::Unstaged,
                        Vec::new(),
                        destination,
                        overwrite,
                    );
                };
                let mut side = self.changes.selection_of(tab).focused;
                let mut entries = self.changes.selected_entries(tab, side);
                if entries.is_empty() {
                    let other = self.changes.selected_entries(tab, other_side(side));
                    if !other.is_empty() {
                        side = other_side(side);
                        entries = other;
                    }
                }
                working_tree_request(side, unique_command_paths(&entries), destination, overwrite)
            }
        }
    }

    /// Previews writing the patch `request` describes.
    pub async fn preview_export(
        &self,
        identity: SessionIdentity,
        request: NativePatchExportRequest,
    ) -> Result<NativePatchExportPreview, PatchFailure> {
        if identity.backend == BackendKind::Local {
            let result = self
                .calls
                .repository_session_patch_export_preview(
                    identity.native_id,
                    identity.generation,
                    request,
                )
                .await
                .map_err(|_| PatchFailure)?;
            return result
                .preview
                .filter(|_| result.failure.is_none())
                .ok_or(PatchFailure);
        }
        // The host builds the patch; it is saved on this computer.
        let destination = request.destination_directory.clone();
        let overwrite = request.overwrite;
        let result = self
            .calls
            .repository_session_patch_export_content(
                identity.native_id,
                identity.generation,
                request,
            )
            .await
            .map_err(|_| PatchFailure)?;
        let content = result
            .content
            .filter(|_| result.failure.is_none())
            .ok_or(PatchFailure)?;
        let total = content.total_bytes as usize;
        let mut bytes = content.first;
        while bytes.len() < total {
            let page = self
                .calls
                .repository_session_patch_export_content_page(
                    identity.native_id,
                    identity.generation,
                    content.token,
                    bytes.len() as u64,
                )
                .await
                .map_err(|_| PatchFailure)?;
            // A page that adds nothing would never finish.
            if page.failure.is_some() || page.bytes.is_empty() {
                return Err(PatchFailure);
            }
            bytes.extend(page.bytes);
        }
        if bytes.len() != total {
            return Err(PatchFailure);
        }
        let byte_count = bytes.len() as u64;
        let saved = self
            .calls
            .patch_export_save_preview(destination, content.filename.clone(), bytes, overwrite)
            .await
            .map_err(|_| PatchFailure)?;
        if saved.failure.is_some() {
            return Err(PatchFailure);
        }
        Ok(NativePatchExportPreview {
            token: saved.token,
            scope: content.scope,
            format: content.format,
            filename: content.filename,
            destination: saved.destination.ok_or(PatchFailure)?,
            byte_count,
            requires_overwrite: saved.requires_overwrite,
        })
    }

    /// Writes a previewed patch.
    pub async fn execute_export(
        &self,
        identity: SessionIdentity,
        token: u64,
    ) -> Result<NativePatchExportExecutionResult, PatchFailure> {
        let result = if identity.backend == BackendKind::Local {
            self.calls
                .repository_session_patch_export_execute(
                    identity.native_id,
                    identity.generation,
                    token,
                )
                .await
        } else {
            self.calls.patch_export_save_execute(token).await
        };
        result.map_err(|_| PatchFailure)
    }

    /// Checks that the patch file `path` applies.
    pub async fn preview_apply(
        &self,
        identity: SessionIdentity,
        path: String,
    ) -> Result<NativePatchApplyPreview, PatchFailure> {
        let result = self
            .calls
            .repository_session_patch_apply_preview(identity.native_id, identity.generation, path)
            .await
            .map_err(|_| PatchFailure)?;
        result
            .preview
            .filter(|_| result.failure.is_none())
            .ok_or(PatchFailure)
    }

    /// Applies a checked patch.
    pub async fn execute_apply(
        &self,
        identity: SessionIdentity,
        token: u64,
    ) -> Result<NativePatchApplyExecutionResult, PatchFailure> {
        self.calls
            .repository_session_patch_apply_execute(identity.native_id, identity.generation, token)
            .await
            .map_err(|_| PatchFailure)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn page(
        selected: &[&str],
        rows: &[&str],
        comparison: Option<(&str, &str)>,
    ) -> NativeHistoryPage {
        NativeHistoryPage {
            request_id: 1,
            topology_complete: true,
            total_rows: rows.len() as u64,
            offset: 0,
            rows: rows
                .iter()
                .map(|id| gitlama_contract::dto::NativeHistoryRow {
                    object_id: (*id).to_owned(),
                    parents: vec![],
                    parent_count: 0,
                    parents_truncated: false,
                    refs: vec![],
                    ref_count: 0,
                    refs_truncated: false,
                    lane: 0,
                    shape: gitlama_contract::dto::NativeHistoryNodeShape::Commit,
                    metadata_available: false,
                    subject: vec![],
                    author: vec![],
                    avatar_hash: String::new(),
                    author_time: 0,
                    metadata_failure: None,
                    selected: false,
                    current: false,
                    lit: false,
                    compared: false,
                    wip_changed_files: 0,
                    wip_staged_files: 0,
                })
                .collect(),
            segments: vec![],
            lane_count: 1,
            payload_bytes: 0,
            lighting_active: false,
            current_object_id: None,
            selected_object_ids: selected.iter().map(|id| (*id).to_owned()).collect(),
            focused_object_id: None,
            comparison_old_object_id: comparison.map(|(old, _)| old.to_owned()),
            comparison_new_object_id: comparison.map(|(_, new)| new.to_owned()),
            reveal_sequence: 0,
            reveal_object_id: None,
            reveal_index: None,
            query_sequence: 0,
            query_active: false,
            accepted_query: String::new(),
            branch_filter: vec![],
            selected_filtered_out: false,
            collapsed_commits: 0,
            other_refs: false,
        }
    }

    #[test]
    fn history_patches_follow_the_selection() {
        let none = history_request(
            Some(&page(&[], &["c", "b", "a"], None)),
            None,
            "/out".into(),
            false,
        );
        assert!(none.workspace_default && none.commit.is_none());
        let one = history_request(
            Some(&page(&["b"], &["c", "b", "a"], None)),
            None,
            "/out".into(),
            false,
        );
        assert_eq!(one.commit.as_deref(), Some("b"));
        assert!(!one.workspace_default);
        // A range lists the selection oldest first, in graph order.
        let range = history_request(
            Some(&page(&["a", "c"], &["c", "b", "a"], None)),
            None,
            "/out".into(),
            true,
        );
        assert_eq!(range.range_commits, ["a", "c"]);
        assert!(range.overwrite);
        let compared = history_request(
            Some(&page(&["a", "c"], &["c", "b", "a"], Some(("a", "c")))),
            None,
            "/out".into(),
            false,
        );
        assert_eq!(
            (
                compared.comparison_old.as_deref(),
                compared.comparison_new.as_deref()
            ),
            (Some("a"), Some("c"))
        );
        assert!(compared.range_commits.is_empty() && compared.commit.is_none());
        let named = history_request(
            Some(&page(&["a", "c"], &["c", "b", "a"], Some(("a", "c")))),
            Some("b".into()),
            "/out".into(),
            false,
        );
        assert_eq!(named.commit.as_deref(), Some("b"));
        assert!(named.comparison_old.is_none() && named.range_commits.is_empty());
    }

    #[test]
    fn diff_and_working_tree_patches() {
        let commit = diff_request(
            None,
            "c".into(),
            vec![b"a.rs".to_vec()],
            "/out".into(),
            false,
        );
        assert_eq!(commit.commit.as_deref(), Some("c"));
        assert_eq!(commit.history_paths, [b"a.rs".to_vec()]);
        let compare = diff_request(Some("a".into()), "c".into(), vec![], "/out".into(), false);
        assert_eq!(
            (
                compare.comparison_old.as_deref(),
                compare.comparison_new.as_deref(),
                compare.commit
            ),
            (Some("a"), Some("c"), None)
        );
        let files = working_tree_request(
            NativeStagingSide::Staged,
            vec![b"x".to_vec()],
            "/out".into(),
            false,
        );
        assert_eq!(
            (files.selected_side, files.focused_side),
            (Some(NativePatchSide::Staged), None)
        );
        let all = working_tree_request(NativeStagingSide::Unstaged, vec![], "/out".into(), false);
        assert_eq!(
            (all.selected_side, all.focused_side),
            (None, Some(NativePatchSide::Unstaged))
        );
    }

    #[test]
    fn outcomes_name_their_messages() {
        assert_eq!(
            export_message(NativePatchExportExecutionState::Completed),
            ("patchExportDone", false)
        );
        assert_eq!(
            export_message(NativePatchExportExecutionState::Stale),
            ("patchExportStale", true)
        );
        assert_eq!(
            apply_message(NativePatchApplyExecutionState::ReconciledWithWarning),
            ("patchApplyWarning", "warning")
        );
        assert_eq!(
            apply_message(NativePatchApplyExecutionState::OutcomeUncertain).1,
            "error"
        );
        assert_eq!(scope_key(NativePatchExportScope::Range), "patchScopeRange");
        assert_eq!(
            format_key(NativePatchFormat::FormatPatch),
            "patchFormatEmail"
        );
    }
}
