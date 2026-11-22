//! The pump: runs QML's commands and the workbench's ready tasks on the GUI
//! thread, then projects what changed onto the QObjects, one borrow at a time.

use crate::app_state::AppState;
use crate::projection;
use crate::workspace_state::WorkspaceState;
use crate::row_model::RowModel;
use crate::sidebar_state::SidebarState;
use crate::history_model::{HistoryModel, HistorySource};
use crate::history_state::HistoryState;
use crate::diff_model::DiffModel;
use crate::inspector_state::InspectorState;
use gitlama_workbench::history_rows::ReferenceContext;
use crate::json::to_value;
use crate::plumbing::{Commands, PumpWaker};
use gitlama_workbench::app::{App, StartupPhase};
use gitlama_workbench::notify::Topics;
use gitlama_workbench::rt::Runtime;
use qtbridge::qobject;
use serde_json::Value;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

pub struct Driver {
    pub app: Rc<App>,
    pub runtime: Runtime,
    pub commands: Commands,
    pub waker: Arc<PumpWaker>,
    pub state: Rc<RefCell<AppState>>,
    pub workspace: Rc<RefCell<WorkspaceState>>,
    pub sidebar: Rc<RefCell<SidebarState>>,
    pub sidebar_rows: Rc<RefCell<RowModel>>,
    pub history: Rc<RefCell<HistoryState>>,
    pub history_rows: Rc<RefCell<HistoryModel>>,
    /// The reference context of the last snapshot History showed.
    pub history_context: RefCell<Option<(Rc<gitlama_contract::dto::NativeRepositorySnapshot>, Rc<ReferenceContext>)>>,
    /// What History last published: generation, total, head, context.
    pub history_published: RefCell<Option<(u64, u64, u64, Option<String>, usize)>>,
    pub inspector: Rc<RefCell<InspectorState>>,
    pub inspector_diff: Rc<RefCell<DiffModel>>,
}

#[qobject(ConvertToCamelCase)]
mod pump {
    use super::*;

    #[derive(Default)]
    pub struct Pump {
        pub driver: Option<Rc<Driver>>,
    }

    impl Pump {
        #[qslot]
        fn pump(&mut self) {
            if let Some(driver) = self.driver.clone() {
                driver.pump();
            }
        }
    }
}

pub use pump::Pump;

impl Driver {
    pub fn pump(&self) {
        self.waker.begin_pump();
        for command in self.commands.take() {
            command(self);
        }
        self.runtime.run_until_stalled();
        let changed = self.app.notifier().take();
        if !changed.is_empty() {
            self.project(changed);
        }
    }

    fn project(&self, changed: Topics) {
        if changed.intersects(Topics::STARTUP) {
            let phase = match self.app.phase() {
                StartupPhase::Loading => "loading",
                StartupPhase::Failed => "failed",
                StartupPhase::Ready => "ready",
            };
            let mut state = self.state.borrow_mut();
            if state.startup != phase {
                state.startup = phase.to_owned();
                state.startup_changed();
            }
        }
        if changed.intersects(Topics::EVENTS) {
            self.emit_events();
        }
        if changed.intersects(Topics::WORKSPACE | Topics::SESSION | Topics::SETTINGS) {
            self.project_workspace(changed);
        }
        if changed.intersects(Topics::HISTORY | Topics::WORKSPACE | Topics::SESSION) {
            self.project_history();
        }
        if changed.intersects(Topics::INSPECTOR) {
            self.project_inspector();
        }
        if changed.intersects(Topics::SETTINGS) {
            let appearance = self
                .app
                .services()
                .map(|services| services.settings.with(|document| to_value(&document.appearance)))
                .unwrap_or(Value::Null);
            let shortcuts = self
                .app
                .services()
                .map(|services| {
                    services
                        .settings
                        .with(|document| projection::shortcuts(&document.shortcut_overrides))
                })
                .unwrap_or_else(|| projection::shortcuts(&[]));
            let mut state = self.state.borrow_mut();
            if state.appearance != appearance || state.shortcuts != shortcuts {
                state.appearance = appearance;
                state.shortcuts = shortcuts;
                state.appearance_changed();
            }
        }
    }
}

impl Driver {
    fn emit_events(&self) {
        for prompt in self.app.prompts.take_fresh() {
            self.state.borrow_mut().prompt(
                prompt.id as i64,
                prompt.kind.to_owned(),
                prompt.payload.to_string(),
            );
        }
        for notice in self.app.notices.take() {
            match notice {
                gitlama_workbench::notices::Notice::Status { key, args, error } => {
                    self.state.borrow_mut().notice(key, args.to_string(), error);
                }
            }
        }
    }

    fn project_workspace(&self, changed: Topics) {
        let Some(services) = self.app.services() else { return };
        if changed.intersects(Topics::SETTINGS) {
            let recents = services
                .settings
                .with(|document| projection::recents(&document.recent_repositories));
            let mut workspace = self.workspace.borrow_mut();
            if workspace.recents != recents {
                workspace.recents = recents;
                workspace.recents_changed();
            }
        }
        if changed.intersects(Topics::WORKSPACE | Topics::SESSION) {
            services.entry.follow_session(services.workspace.current().as_ref());
            let (tabs, active, groups) = services.workspace.with_tabs(|tabs, active, groups| {
                (
                    Value::Array(tabs.iter().map(|tab| projection::tab(tab, &services.appearances)).collect()),
                    active.map_or(-1, |id| id as i64),
                    Value::Array(groups.iter().map(projection::group).collect()),
                )
            });
            let entry = projection::entry(services.entry.current());
            let active_projection = services.workspace.with_tabs(|tabs, active, groups| {
                let tab = active.and_then(|id| tabs.iter().find(|tab| tab.id == id));
                let group = tab
                    .and_then(|tab| tab.group_id)
                    .and_then(|id| groups.iter().find(|group| group.id == id))
                    .map(|group| group.name.as_str());
                projection::active(tab, group)
            });
            let mut workspace = self.workspace.borrow_mut();
            if workspace.active != active_projection {
                workspace.active = active_projection;
                workspace.active_changed();
            }
            if workspace.tabs != tabs || workspace.active_tab_id != active || workspace.groups != groups {
                workspace.tabs = tabs;
                workspace.active_tab_id = active;
                workspace.groups = groups;
                workspace.tabs_changed();
            }
            if workspace.entry != entry {
                workspace.entry = entry;
                workspace.entry_changed();
            }
            drop(workspace);
            self.project_sidebar(&services);
            let mut workspace = self.workspace.borrow_mut();
            let created = workspace.created.take();
            if let Some(group) = created {
                workspace.group_created(group as i64);
            }
        }
    }

    fn project_sidebar(&self, services: &gitlama_workbench::app::Services) {
        services.navigator.follow_workspace();
        let selected = services.navigator.selected_reference(services.workspace.active_tab_id());
        let projection = services.sidebar.project(selected.as_deref());
        self.sidebar_rows.borrow_mut().publish(projection.rows);
        let mut sidebar = self.sidebar.borrow_mut();
        if sidebar.header != projection.header {
            sidebar.header = projection.header;
            sidebar.header_changed();
        }
    }

    fn project_history(&self) {
        let Some(services) = self.app.services() else { return };
        let history = &services.workspace.history;
        let state = crate::history_state::project(history);
        {
            let mut pane = self.history.borrow_mut();
            if pane.state != state {
                pane.state = state;
                pane.state_changed();
            }
        }
        let session = services.workspace.current();
        let context = match &session {
            Some(session) => {
                let cached = self
                    .history_context
                    .borrow()
                    .as_ref()
                    .filter(|(snapshot, _)| Rc::ptr_eq(snapshot, &session.snapshot))
                    .map(|(_, context)| Rc::clone(context));
                cached.unwrap_or_else(|| {
                    let context = Rc::new(ReferenceContext::new(&session.snapshot.refs));
                    *self.history_context.borrow_mut() = Some((Rc::clone(&session.snapshot), Rc::clone(&context)));
                    context
                })
            }
            None => Rc::new(ReferenceContext::default()),
        };
        let head = session.as_ref().and_then(|session| {
            match session.snapshot.status.as_ref() {
                Some(status) => status.head_object_id.clone(),
                None => session.snapshot.identity.as_ref().and_then(|identity| identity.head_object_id.clone()),
            }
        });
        let current = history.current();
        let total = current.page.as_ref().map_or(0, |page| page.total_rows);
        let key = (
            history.pages_generation(),
            history.revision(),
            total,
            head.clone(),
            Rc::as_ptr(&context) as usize,
        );
        if self.history_published.borrow().as_ref() == Some(&key) {
            return;
        }
        *self.history_published.borrow_mut() = Some(key);
        let total = i32::try_from(total).unwrap_or(i32::MAX);
        self.history_rows.borrow_mut().publish(
            HistorySource { history: Some(Rc::clone(history)), context, head },
            total,
        );
    }

    fn project_inspector(&self) {
        let Some(services) = self.app.services() else { return };
        let state = crate::inspector_state::project(&services.inspector);
        {
            let mut inspector = self.inspector.borrow_mut();
            if inspector.state != state {
                inspector.state = state;
                inspector.state_changed();
            }
        }
        let diff = services.inspector.current().diff;
        self.inspector_diff.borrow_mut().publish(diff);
    }
}
