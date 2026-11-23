//! The History pane: its page state and the slots that select, search and
//! filter. The rows are a `HistoryModel`.

use crate::plumbing::Commands;
use gitlama_workbench::history::{HistoryQuery, LoadPhase, SelectionOrigin, WORKTREE_OBJECT_ID};
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;

/// The pane's state as QML reads it.
pub fn project(history: &gitlama_workbench::history::HistoryService) -> Value {
    let state = history.current();
    let phase = match state.phase {
        LoadPhase::Loading => "loading",
        LoadPhase::Preview => "preview",
        LoadPhase::Complete => "complete",
        LoadPhase::Empty => "empty",
        LoadPhase::Failed => "failed",
    };
    let page = state.page.as_deref();
    json!({
        "phase": phase,
        "failure": state.failure_code,
        "queryFailure": state.query_failure_code,
        "targetNotShown": state.target_not_shown,
        "targetObjectId": state.target_object_id,
        "hasPage": page.is_some(),
        "empty": page.is_none_or(|page| page.rows.is_empty()),
        "total": page.map_or(0, |page| page.total_rows),
        "worktreeRows": page.map_or(0, |page| page.rows.iter().filter(|row| row.object_id == WORKTREE_OBJECT_ID).count()),
        "laneCount": page.map_or(0, |page| page.lane_count),
        "lightingActive": page.is_some_and(|page| page.lighting_active),
        "queryActive": page.is_some_and(|page| page.query_active),
        "acceptedQuery": page.map(|page| page.accepted_query.clone()),
        "collapsedCommits": page.map_or(0, |page| page.collapsed_commits),
        "selectedFilteredOut": page.is_some_and(|page| page.selected_filtered_out),
        "otherRefs": page.is_some_and(|page| page.other_refs),
        "branchFilterCount": page.map_or(0, |page| page.branch_filter.len()),
        "selectedIds": page.map_or(Vec::new(), |page| page.selected_object_ids.clone()),
        "focusedObjectId": page.and_then(|page| page.focused_object_id.clone()),
        "revealSequence": page.map_or(0, |page| page.reveal_sequence),
        "revealIndex": page.and_then(|page| page.reveal_index),
        "searchPending": history.search_pending(),
        "searchFailure": history.search_failure_code(),
        "searchMatches": history.search_matches().len(),
        "searchIndex": history.search_index(),
        "searchText": history.search_query().map(|query| query.text.clone()),
        "searchScopes": history.search_query().map(|query| json!({
            "hash": query.search_hash, "message": query.search_message,
            "author": query.search_author, "path": query.search_path,
        })),
        // The single selected commit is a merge whose side can collapse.
        "canCollapse": page.is_some_and(|page| page.selected_object_ids.len() == 1)
            && page
                .and_then(|page| page.selected_object_ids.first())
                .and_then(|id| history.row_by_id(id))
                .is_some_and(|row| row.parents.len() > 1),
        "generation": history.pages_generation(),
    })
}

/// The branches the graph can be filtered to: local branches (the main
/// branch first, the checked-out one next), then each remote's.
pub fn branch_filter_choices(snapshot: &gitlama_contract::dto::NativeRepositorySnapshot) -> Value {
    use gitlama_workbench::sidebar::{branch_reference, filter_upstream, main_branch_first, remote_branch_reference};
    let refs = &snapshot.refs;
    let ordered = main_branch_first(&refs.branches);
    let (main, others) = ordered.split_first().map_or((None, &[][..]), |(main, others)| (Some(*main), others));
    let mut choices = Vec::new();
    let locals = main
        .into_iter()
        .chain(others.iter().copied().filter(|branch| branch.head))
        .chain(others.iter().copied().filter(|branch| !branch.head));
    for branch in locals {
        let Ok(name) = std::str::from_utf8(&branch.name) else { continue };
        choices.push(json!({
            "reference": branch_reference(branch), "label": name, "name": name, "remote": null,
            "current": branch.head, "upstream": filter_upstream(branch),
        }));
    }
    for remote in &refs.remotes {
        let Ok(remote_name) = std::str::from_utf8(&remote.name) else { continue };
        for branch in main_branch_first(&remote.branches) {
            let Ok(name) = std::str::from_utf8(&branch.name) else { continue };
            if name == "HEAD" {
                continue;
            }
            choices.push(json!({
                "reference": remote_branch_reference(remote, branch), "label": format!("{remote_name}/{name}"), "name": name,
                "remote": remote_name, "current": false, "upstream": null,
            }));
        }
    }
    Value::Array(choices)
}

/// The checked-out branch's upstream when it has commits the branch lacks.
pub fn stale_upstream(snapshot: &gitlama_contract::dto::NativeRepositorySnapshot) -> Value {
    let Some(branch) = snapshot.refs.branches.iter().find(|branch| branch.head) else { return Value::Null };
    let Some(upstream) = branch.upstream.as_ref().filter(|_| branch.behind > 0 && !branch.upstream_gone) else { return Value::Null };
    let upstream = String::from_utf8_lossy(upstream).into_owned();
    let shown = upstream.strip_prefix("refs/remotes/").map(str::to_owned).unwrap_or(upstream);
    json!({"reference": shown, "behind": branch.behind})
}

#[qobject(ConvertToCamelCase)]
mod history_state {
    use super::*;

    #[derive(Default)]
    pub struct HistoryState {
        pub commands: Option<Commands>,
        pub(crate) state: Value,
        /// The snapshot History shows, for the commit menu's references.
        pub(crate) snapshot: Option<std::rc::Rc<gitlama_contract::dto::NativeRepositorySnapshot>>,
    }

    impl HistoryState {
        qproperty!("state", Member = state, Notify = state_changed);

        #[qsignal]
        pub fn state_changed(&mut self);

        /// Selects commit `object_id` (the working tree row shows Changes).
        #[qslot]
        fn select(&self, object_id: String) {
            self.with_services(move |services| {
                if object_id == WORKTREE_OBJECT_ID {
                    services.navigator.select_pane(gitlama_workbench::workspace::Pane::Changes, None);
                } else {
                    services.navigator.select_identity(object_id);
                }
            });
        }

        /// Adds commit `object_id` to the selection or removes it.
        #[qslot]
        fn toggle(&self, object_id: String) {
            self.with_services(move |services| {
                if object_id == WORKTREE_OBJECT_ID {
                    services.navigator.select_pane(gitlama_workbench::workspace::Pane::Changes, None);
                } else {
                    services.navigator.toggle_identity(object_id);
                }
            });
        }

        /// Selects `object_id` and scrolls it into view without focus.
        #[qslot]
        fn reveal(&self, object_id: String) {
            self.with_services(move |services| services.navigator.reveal_identity(object_id));
        }

        /// The references at commit `object_id` for its context menu:
        /// [{name, entry: {name, commandName, target, filterReference,
        /// filterUpstream, commands, current}}].
        #[qslot]
        fn references_at(&self, object_id: String) -> Value {
            let Some(snapshot) = self.snapshot.as_ref() else { return Value::Array(Vec::new()) };
            Value::Array(
                gitlama_workbench::sidebar::entries_at(&snapshot.refs, &object_id)
                    .into_iter()
                    .map(|(name, entry)| {
                        serde_json::json!({
                            "name": name,
                            "entry": {
                                "name": entry.name,
                                "commandName": entry.command_name,
                                "target": entry.target,
                                "filterReference": entry.filter_reference,
                                "filterUpstream": entry.filter_upstream,
                                "commands": entry.commands,
                                "current": entry.current,
                            }
                        })
                    })
                    .collect(),
            )
        }

        /// Moves the keyboard selection by `delta` rows (from the focused one).
        #[qslot]
        fn select_relative(&self, object_id: String, extend: bool) {
            self.with_services(move |services| {
                rt::spawn_detached(services.workspace.history.select(
                    Some(object_id),
                    extend,
                    true,
                    true,
                    0,
                    SelectionOrigin::Keyboard,
                ));
            });
        }

        /// Searches for `text` in the given scopes (an empty text clears).
        #[qslot]
        fn apply_query(&self, text: String, hash: bool, message: bool, author: bool, path: bool) {
            self.with_services(move |services| {
                let query = HistoryQuery {
                    text: text.trim().to_owned(),
                    search_hash: hash,
                    search_message: message,
                    search_author: author,
                    search_path: path,
                };
                rt::spawn_detached(services.workspace.history.apply_query(query));
            });
        }

        /// Goes to the next (or previous) search match.
        #[qslot]
        fn navigate_search(&self, backwards: bool) {
            self.with_services(move |services| services.workspace.history.navigate_search(backwards));
        }

        /// Collapses or expands the merge `object_id`'s side branch.
        #[qslot]
        fn toggle_collapse(&self, object_id: String) {
            self.with_services(move |services| services.workspace.history.toggle_collapse(object_id, 0));
        }

        /// The branches the graph can be filtered to (the Dart
        /// buildBranchFilterChoices): {reference, label, name, remote,
        /// current, upstream}, the main branch first.
        #[qslot]
        fn branch_filter_choices(&self) -> Value {
            self.snapshot.as_deref().map_or(Value::Array(Vec::new()), branch_filter_choices)
        }

        /// The new commits of the checked-out branch's upstream:
        /// {reference, behind}, or null.
        #[qslot]
        fn stale_upstream(&self) -> Value {
            self.snapshot.as_deref().map_or(Value::Null, stale_upstream)
        }

        /// Reads the reflog; `reflog_loaded` carries {entries: [{summary,
        /// commit, short}], retainedAfterFailure} or {failed: true}.
        #[qslot]
        fn load_reflog(&self) {
            let Some(commands) = self.commands.clone() else { return };
            let reply = commands.clone();
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(identity) = services.workspace.current().map(|session| session.identity) else { return };
                let request = services.calls.repository_session_reflog(identity.native_id, identity.generation, 0, 256);
                rt::spawn_detached(async move {
                    let value = match request.await {
                        Ok(result) if result.failure.is_none() => json!({
                            "entries": result.page.entries.iter().map(|entry| json!({
                                "summary": String::from_utf8_lossy(&entry.summary),
                                "commit": entry.commit,
                                "short": entry.commit.chars().take(10).collect::<String>(),
                            })).collect::<Vec<_>>(),
                            "retainedAfterFailure": result.page.retained_after_failure,
                        }),
                        _ => json!({"failed": true, "entries": []}),
                    };
                    reply.post(move |driver| driver.history.borrow_mut().reflog_loaded(value));
                });
            });
        }

        #[qsignal]
        pub fn reflog_loaded(&mut self, reflog: Value);

        /// Loads History of the active tab again.
        #[qslot]
        fn reload(&self) {
            self.with_services(|services| {
                let Some(identity) = services.workspace.current().map(|session| session.identity) else { return };
                let history = Rc::clone(&services.workspace.history);
                rt::spawn_detached(async move { history.load(identity, Vec::new()).await });
            });
        }

        /// Shows commit `object_id` in History (reloading only when needed).
        #[qslot]
        fn show_commit(&self, object_id: String) {
            self.with_services(move |services| {
                let navigator = Rc::clone(&services.navigator);
                rt::spawn_detached(async move { navigator.show_commit(object_id, None, true, false).await });
            });
        }

        fn with_services(&self, action: impl FnOnce(&gitlama_workbench::app::Services) + 'static) {
            if let Some(commands) = &self.commands {
                commands.post(move |driver| {
                    if let Some(services) = driver.app.services() {
                        action(&services);
                    }
                });
            }
        }
    }
}

pub use history_state::HistoryState;
