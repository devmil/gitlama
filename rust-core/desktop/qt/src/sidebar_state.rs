//! The workspace sidebar: its header state, and slots for selecting,
//! expanding and filtering. Its rows are a `RowModel`.

use crate::plumbing::Commands;
use gitlama_workbench::history::BranchFilter;
use gitlama_workbench::rt;
use gitlama_workbench::workspace::Pane;
use qtbridge::qobject;
use serde_json::Value;
use std::rc::Rc;

/// The roles of the sidebar's rows.
pub const SIDEBAR_ROLES: &[&str] = &[
    "key",
    "kind",
    "section",
    "name",
    "reference",
    "selected",
    "icon",
    "count",
    "depth",
    "hasChildren",
    "expanded",
    "current",
    "currentDescription",
    "subtitle",
    "ahead",
    "behind",
    "filtered",
    "holdsFiltered",
    "commands",
    "primaryCommand",
    "target",
    "commandName",
    "filterReference",
    "filterUpstream",
    "revealReference",
    "draggable",
    "dropTarget",
    "activate",
    "worktree",
    "worktreePath",
    "worktreeProtected",
    "pullRequest",
    "hasMenu",
];

#[qobject(ConvertToCamelCase)]
mod sidebar_state {
    use super::*;

    #[derive(Default)]
    pub struct SidebarState {
        pub commands: Option<Commands>,
        pub(crate) header: Value,
    }

    impl SidebarState {
        qproperty!("header", Member = header, Notify = header_changed);

        #[qsignal]
        pub fn header_changed(&mut self);

        /// Selects reference row `reference`; History reveals `reveal`.
        #[qslot]
        fn select_reference(&self, reference: String, reveal: String) {
            self.with_services(move |services| {
                let reveal = (!reveal.is_empty()).then_some(reveal);
                services.navigator.select_reference(reference, reveal);
            });
        }

        /// Shows `commit` in History without reloading it.
        #[qslot]
        fn reveal_target(&self, commit: String) {
            self.with_services(move |services| {
                let navigator = Rc::clone(&services.navigator);
                rt::spawn_detached(async move {
                    navigator.show_commit(commit, None, false, false).await
                });
            });
        }

        /// Shows the pane named `pane` (`changes` or `history`).
        #[qslot]
        fn select_pane(&self, pane: String) {
            self.with_services(move |services| {
                let pane = if pane == "history" {
                    Pane::History
                } else {
                    Pane::Changes
                };
                services.navigator.select_pane(pane, None);
            });
        }

        #[qslot]
        fn next_pane(&self) {
            self.with_services(|services| services.navigator.next_pane());
        }

        /// Opens or closes the row or section at `path`.
        #[qslot]
        fn set_expanded(&self, path: String, expanded: bool) {
            self.with_services(move |services| services.sidebar.set_expanded(path, expanded));
        }

        /// Shows or edits the reference filter; closed, it clears.
        #[qslot]
        fn set_filter(&self, open: bool, text: String) {
            self.with_services(move |services| services.sidebar.set_filter(open, text));
        }

        /// Loads the worktree list again (when its section opens).
        #[qslot]
        fn reload_worktrees(&self) {
            self.with_services(|services| services.sidebar.reload_worktrees());
        }

        /// Opens worktree `index` of the sidebar's inventory in a tab.
        #[qslot]
        fn open_worktree(&self, index: i32) {
            self.with_services(move |services| {
                let Some(inventory) = services.sidebar.worktrees() else {
                    return;
                };
                let Some(worktree) = usize::try_from(index)
                    .ok()
                    .and_then(|index| inventory.worktrees.get(index))
                else {
                    return;
                };
                let root = worktree.worktree_root.clone();
                let workspace = Rc::clone(&services.workspace);
                rt::spawn_detached(async move {
                    // A failed tab stays visible with its error.
                    let _ = workspace.open_recent(root).await;
                });
            });
        }

        /// Sets the active tab's history branch filter to `references`.
        #[qslot]
        fn set_branch_filter(&self, references: Vec<String>) {
            self.with_services(move |services| {
                let Some(tab) = services.workspace.active_tab_id() else {
                    return;
                };
                let workspace = Rc::clone(&services.workspace);
                rt::spawn_detached(async move {
                    workspace
                        .set_branch_filter(tab, BranchFilter::new(references))
                        .await
                });
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

pub use sidebar_state::SidebarState;
