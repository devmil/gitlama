//! The window's workspace: repository tabs and groups, the entry actions'
//! state and the recent repositories. Slots post commands.

use crate::plumbing::Commands;
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::Value;

#[qobject(ConvertToCamelCase)]
mod workspace_state {
    use super::*;

    pub struct WorkspaceState {
        pub commands: Option<Commands>,
        pub(crate) tabs: Value,
        pub(crate) active_tab_id: i64,
        pub(crate) groups: Value,
        pub(crate) entry: Value,
        pub(crate) recents: Value,
        pub(crate) active: Value,
    }

    impl Default for WorkspaceState {
        fn default() -> Self {
            Self {
                commands: None,
                tabs: Value::Array(Vec::new()),
                active_tab_id: -1,
                groups: Value::Array(Vec::new()),
                entry: Value::Null,
                recents: Value::Array(Vec::new()),
                active: Value::Null,
            }
        }
    }

    impl WorkspaceState {
        qproperty!("tabs", Member = tabs, Notify = tabs_changed);
        qproperty!("activeTabId", Member = active_tab_id, Notify = tabs_changed);
        qproperty!("groups", Member = groups, Notify = tabs_changed);
        qproperty!("entry", Member = entry, Notify = entry_changed);
        qproperty!("recents", Member = recents, Notify = recents_changed);
        qproperty!("active", Member = active, Notify = active_changed);

        #[qsignal]
        pub fn tabs_changed(&mut self);
        #[qsignal]
        pub fn entry_changed(&mut self);
        #[qsignal]
        pub fn recents_changed(&mut self);
        #[qsignal]
        pub fn active_changed(&mut self);

        /// Lets the user choose a repository folder and opens it.
        #[qslot]
        fn open_repository(&self) {
            self.with_services(|services| {
                let entry = std::rc::Rc::clone(&services.entry);
                rt::spawn_detached(async move { entry.open().await });
            });
        }

        /// Opens a folder dropped on the window or given on the command line.
        #[qslot]
        fn open_path(&self, path: String) {
            self.with_services(move |services| {
                let entry = std::rc::Rc::clone(&services.entry);
                rt::spawn_detached(async move { entry.open_path(path).await });
            });
        }

        /// Opens recent repository number `index` of the settings' list.
        #[qslot]
        fn open_recent(&self, index: i32) {
            self.with_services(move |services| {
                let Some(identity) = services
                    .settings
                    .with(|document| document.recent_repositories.get(index as usize).cloned())
                else {
                    return;
                };
                let entry = std::rc::Rc::clone(&services.entry);
                rt::spawn_detached(async move { entry.open_recent(identity).await });
            });
        }

        /// Creates a repository; `bare` starts the dialog with Bare chosen.
        #[qslot]
        fn initialize_repository(&self, bare: bool) {
            self.with_services(move |services| {
                let entry = std::rc::Rc::clone(&services.entry);
                rt::spawn_detached(async move { entry.initialize(bare).await });
            });
        }

        #[qslot]
        fn activate_tab(&self, tab_id: i64) {
            self.with_services(move |services| services.workspace.activate_tab(tab_id as u64));
        }

        #[qslot]
        fn close_tab(&self, tab_id: i64) {
            self.with_services(move |services| {
                let workspace = std::rc::Rc::clone(&services.workspace);
                rt::spawn_detached(async move { workspace.close_tab(tab_id as u64).await });
            });
        }

        #[qslot]
        fn reorder_tab(&self, tab_id: i64, target_index: i32) {
            self.with_services(move |services| {
                services
                    .workspace
                    .reorder_tab(tab_id as u64, target_index.max(0) as usize)
            });
        }

        /// Adds a tab that asks which repository to open.
        #[qslot]
        fn add_repository_chooser(&self) {
            self.with_services(|services| {
                services.workspace.add_repository_chooser();
            });
        }

        /// Opens a repository from a chooser tab: `recentIndex` < 0 asks for a
        /// folder.
        #[qslot]
        fn open_from_chooser(&self, tab_id: i64, recent_index: i32) {
            self.with_services(move |services| {
                let recent = (recent_index >= 0)
                    .then(|| {
                        services.settings.with(|document| {
                            document.recent_repositories.get(recent_index as usize).cloned()
                        })
                    })
                    .flatten();
                let workspace = std::rc::Rc::clone(&services.workspace);
                rt::spawn_detached(async move {
                    let _ = workspace.open_from_chooser(tab_id as u64, recent).await;
                });
            });
        }
    }

    impl WorkspaceState {
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

pub use workspace_state::WorkspaceState;
