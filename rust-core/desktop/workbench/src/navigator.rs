//! The workspace's navigation sequences (the Dart `WorkspaceNavigator`):
//! which pane a tab shows, which commit History selects and how a commit is
//! brought on screen. Every surface that navigates goes through these.

use crate::history::SelectionOrigin;
use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::workspace::{Pane, Route, WorkspaceService};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;

pub struct Navigator {
    workspace: Rc<WorkspaceService>,
    notifier: Notifier,
    selected_references: RefCell<HashMap<u64, String>>,
    active_tab: Cell<Option<u64>>,
}

impl Navigator {
    pub fn new(workspace: Rc<WorkspaceService>, notifier: Notifier) -> Rc<Self> {
        let active = workspace.active_tab_id();
        Rc::new(Self {
            workspace,
            notifier,
            selected_references: RefCell::new(HashMap::new()),
            active_tab: Cell::new(active),
        })
    }

    /// Follows the active tab: a tab's sidebar selection ends when it is left.
    pub fn follow_workspace(&self) {
        let active = self.workspace.active_tab_id();
        if active == self.active_tab.get() {
            return;
        }
        if let Some(previous) = self.active_tab.get()
            && self
                .selected_references
                .borrow_mut()
                .remove(&previous)
                .is_some()
        {
            self.notifier.notify(Topics::WORKSPACE);
        }
        self.active_tab.set(active);
    }

    /// The sidebar row selected in tab `tab_id`.
    pub fn selected_reference(&self, tab_id: Option<u64>) -> Option<String> {
        self.selected_references.borrow().get(&tab_id?).cloned()
    }

    /// Selects the sidebar row `reference` in the active tab; `reveal` is the
    /// reference History shows while it is selected.
    pub fn select_reference(&self, reference: String, reveal: Option<String>) {
        let Some(tab_id) = self.workspace.active_tab_id() else {
            return;
        };
        self.selected_references
            .borrow_mut()
            .insert(tab_id, reference);
        self.notifier.notify(Topics::WORKSPACE);
        let workspace = Rc::clone(&self.workspace);
        rt::spawn_detached(async move { workspace.reveal_reference(tab_id, reveal).await });
    }

    /// Shows `pane` in tab `tab_id` (the active tab when None).
    pub fn select_pane(&self, pane: Pane, tab_id: Option<u64>) {
        let active = self.workspace.active_tab();
        let tab = match tab_id {
            None => active.clone(),
            Some(id) if Some(id) == active.as_ref().map(|tab| tab.id) => active.clone(),
            Some(id) => self.workspace.tab(id),
        };
        let Some(tab) = tab else { return };
        let mut navigation = tab.navigation.clone();
        navigation.pane = pane;
        navigation.route = Route::Repository;
        navigation.selected_identity = None;
        self.workspace.update_navigation(tab.id, navigation);
        if Some(tab.id) != active.map(|tab| tab.id) {
            return;
        }
        let workspace = Rc::clone(&self.workspace);
        match pane {
            Pane::History => {
                rt::spawn_detached(async move { workspace.show_history(tab.id).await })
            }
            Pane::Changes => {
                let history = Rc::clone(&workspace.history);
                rt::spawn_detached(history.select(
                    None,
                    false,
                    false,
                    false,
                    0,
                    SelectionOrigin::Graph,
                ));
            }
        }
    }

    /// Switches the active tab between Changes and History.
    pub fn next_pane(&self) {
        let pane = match self.workspace.active_tab().map(|tab| tab.navigation.pane) {
            Some(Pane::Changes) => Pane::History,
            _ => Pane::Changes,
        };
        self.select_pane(pane, None);
    }

    /// Selects `identity` (a commit or a path) in the active tab.
    pub fn select_identity(&self, identity: String) {
        let Some(active) = self.remember(&identity) else {
            return;
        };
        if active == Pane::History {
            rt::spawn_detached(self.workspace.history.select(
                Some(identity),
                false,
                false,
                true,
                0,
                SelectionOrigin::Graph,
            ));
        }
    }

    /// Adds `identity` to History's selection or removes it.
    pub fn toggle_identity(&self, identity: String) {
        if self.remember(&identity).is_none() {
            return;
        }
        rt::spawn_detached(self.workspace.history.select(
            Some(identity),
            true,
            false,
            true,
            0,
            SelectionOrigin::Graph,
        ));
    }

    /// Selects `identity` in History and scrolls it into view without
    /// moving focus.
    pub fn reveal_identity(&self, identity: String) {
        if self.remember(&identity).is_none() {
            return;
        }
        rt::spawn_detached(self.workspace.history.select(
            Some(identity),
            false,
            true,
            false,
            0,
            SelectionOrigin::Graph,
        ));
    }

    fn remember(&self, identity: &str) -> Option<Pane> {
        let active = self.workspace.active_tab()?;
        let mut navigation = active.navigation.clone();
        navigation.selected_identity = Some(identity.to_owned());
        let pane = navigation.pane;
        self.workspace.update_navigation(active.id, navigation);
        Some(pane)
    }

    /// Shows History in the active tab with `commit` selected and revealed;
    /// with `base` it compares them. Without `reload` a shown History keeps
    /// its rows.
    pub async fn show_commit(
        &self,
        commit: String,
        base: Option<String>,
        focus: bool,
        reload: bool,
    ) {
        let Some(active) = self.workspace.active_tab() else {
            return;
        };
        let Some(session) = active.session.clone() else {
            return;
        };
        let needs_history = reload || active.navigation.pane != Pane::History;
        let mut navigation = active.navigation.clone();
        navigation.pane = Pane::History;
        navigation.route = Route::Repository;
        navigation.selected_identity = Some(commit.clone());
        self.workspace.update_navigation(active.id, navigation);
        let history = Rc::clone(&self.workspace.history);
        if needs_history {
            history.load(session.identity, Vec::new()).await;
        }
        match base {
            None => {
                history
                    .select(Some(commit), false, true, focus, 0, SelectionOrigin::Graph)
                    .await
            }
            Some(base) => {
                history
                    .select(Some(base), false, true, true, 0, SelectionOrigin::Graph)
                    .await;
                history
                    .select(Some(commit), true, false, true, 0, SelectionOrigin::Graph)
                    .await;
            }
        }
    }

    /// Selects exactly the two commits History has selected again, which
    /// compares them.
    pub async fn compare_selected(&self) -> bool {
        let selected = self
            .workspace
            .history
            .current()
            .page
            .map(|page| page.selected_object_ids.clone())
            .unwrap_or_default();
        if selected.len() != 2 {
            return false;
        }
        let history = Rc::clone(&self.workspace.history);
        history
            .select(None, false, false, true, 0, SelectionOrigin::Graph)
            .await;
        history
            .select(
                Some(selected[0].clone()),
                true,
                false,
                true,
                0,
                SelectionOrigin::Graph,
            )
            .await;
        history
            .select(
                Some(selected[1].clone()),
                true,
                false,
                true,
                0,
                SelectionOrigin::Graph,
            )
            .await;
        true
    }
}
