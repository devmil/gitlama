//! The window's workspace: repository tabs and groups, the entry actions'
//! state and the recent repositories. Slots post commands.

use crate::plumbing::Commands;
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::Value;
use std::rc::Rc;

#[qobject(ConvertToCamelCase)]
mod workspace_state {
    use super::*;

    pub struct WorkspaceState {
        pub commands: Option<Commands>,
        /// A group a command created, reported once after the pump.
        pub(crate) created: std::rc::Rc<std::cell::Cell<Option<u64>>>,
        pub(crate) tabs: Value,
        pub(crate) active_tab_id: i64,
        pub(crate) groups: Value,
        pub(crate) entry: Value,
        pub(crate) recents: Value,
        pub(crate) active: Value,
        /// The repository mark being edited: {tabId, name, icon, color,
        /// image, imageUrl, imageFailed}, or null.
        pub(crate) appearance_edit: Value,
        pub(crate) appearance_image: Option<gitlama_contract::dto::NativePathIdentity>,
    }

    impl Default for WorkspaceState {
        fn default() -> Self {
            Self {
                commands: None,
                created: std::rc::Rc::new(std::cell::Cell::new(None)),
                tabs: Value::Array(Vec::new()),
                active_tab_id: -1,
                groups: Value::Array(Vec::new()),
                appearance_edit: Value::Null,
                appearance_image: None,
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
        qproperty!("appearanceEdit", Member = appearance_edit, Notify = appearance_edit_changed);

        #[qsignal]
        pub fn appearance_edit_changed(&mut self);
        /// The mark was saved (`ok`) or could not be.
        #[qsignal]
        pub fn appearance_saved(&mut self, ok: bool);

        /// Starts editing the mark of tab `tab_id`'s repository.
        #[qslot]
        fn edit_tab_appearance(&self, tab_id: i64) {
            let Some(commands) = &self.commands else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(tab) = services.workspace.tab(tab_id as u64) else { return };
                let identity = tab.canonical_identity().cloned();
                let appearance = services.appearances.appearance_for(identity.as_ref());
                let mut state = driver.workspace.borrow_mut();
                state.appearance_image = appearance.as_ref().and_then(|appearance| appearance.image.clone());
                state.appearance_edit = serde_json::json!({
                    "tabId": tab_id,
                    "name": tab.label,
                    "icon": appearance.as_ref().and_then(|appearance| appearance.icon.clone()),
                    "color": appearance.as_ref().and_then(|appearance| appearance.color.clone()),
                });
                drop(state);
                driver.project_appearance_edit();
            });
        }

        /// Uses the image file at `path` (empty removes the image).
        #[qslot]
        fn set_appearance_image(&self, path: String) {
            let Some(commands) = &self.commands else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let image = (!path.is_empty()).then(|| gitlama_workbench::session::local_path(&path));
                if let Some(image) = &image {
                    // A file chosen again is read again.
                    services.appearances.forget_image(image);
                }
                driver.workspace.borrow_mut().appearance_image = image;
                driver.project_appearance_edit();
            });
        }

        /// Saves the edited mark: `icon` and `color` keys (empty for none).
        #[qslot]
        fn save_tab_appearance(&self, icon: String, color: String) {
            let Some(commands) = &self.commands else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let (tab_id, image) = {
                    let state = driver.workspace.borrow();
                    (state.appearance_edit["tabId"].as_i64(), state.appearance_image.clone())
                };
                let Some(identity) = tab_id
                    .and_then(|tab| services.workspace.tab(tab as u64))
                    .and_then(|tab| tab.canonical_identity().cloned())
                else {
                    return;
                };
                let mut appearance = services.appearances.appearance_for(Some(&identity)).unwrap_or(
                    gitlama_contract::storage::NativeRepositoryAppearance {
                        identity: identity.clone(),
                        icon: None,
                        color: None,
                        image: None,
                        name: None,
                    },
                );
                appearance.icon = (!icon.is_empty()).then_some(icon);
                appearance.color = (!color.is_empty()).then_some(color);
                appearance.image = image;
                let appearances = Rc::clone(&services.appearances);
                let shared = Rc::clone(&driver.workspace);
                rt::spawn_detached(async move {
                    let ok = appearances.save(appearance).await.is_ok();
                    shared.borrow_mut().appearance_saved(ok);
                });
            });
        }

        /// Ends the mark editor.
        #[qslot]
        fn end_tab_appearance(&self) {
            let Some(commands) = &self.commands else { return };
            commands.post(|driver| {
                let mut state = driver.workspace.borrow_mut();
                state.appearance_edit = Value::Null;
                state.appearance_image = None;
                state.appearance_edit_changed();
            });
        }

        #[qsignal]
        pub fn tabs_changed(&mut self);
        #[qsignal]
        pub fn entry_changed(&mut self);
        #[qsignal]
        pub fn recents_changed(&mut self);
        #[qsignal]
        pub fn active_changed(&mut self);
        /// A group was created for a tab; the strip asks for its name.
        #[qsignal]
        pub fn group_created(&mut self, group: i64);

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
        fn clone_repository(&self) {
            self.with_services(|services| {
                let entry = std::rc::Rc::clone(&services.entry);
                rt::spawn_detached(async move { entry.clone_repository().await });
            });
        }

        #[qslot]
        fn retry_clone_with_credentials(&self) {
            self.with_services(|services| {
                let entry = std::rc::Rc::clone(&services.entry);
                rt::spawn_detached(async move { entry.retry_clone_with_credentials().await });
            });
        }

        #[qslot]
        fn inspect_clone_host_key(&self) {
            self.with_services(|services| {
                let entry = std::rc::Rc::clone(&services.entry);
                rt::spawn_detached(async move { entry.inspect_clone_host_key().await });
            });
        }

        #[qslot]
        fn cancel_clone(&self) {
            self.with_services(|services| {
                let entry = std::rc::Rc::clone(&services.entry);
                rt::spawn_detached(async move { entry.cancel_clone().await });
            });
        }

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

        /// Puts `tabId` at `index` among the other tabs, in group `group`
        /// (-1 for none).
        #[qslot]
        fn move_tab(&self, tab_id: i64, index: i32, group: i64) {
            self.with_services(move |services| {
                services.workspace.move_tab(
                    tab_id as u64,
                    index.max(0) as usize,
                    (group >= 0).then_some(group as u64),
                )
            });
        }

        #[qslot]
        fn move_tab_group(&self, group: i64, index: i32) {
            self.with_services(move |services| {
                services.workspace.move_tab_group(group as u64, index.max(0) as usize)
            });
        }

        #[qslot]
        fn move_worktree_tab(&self, tab_id: i64, index: i32) {
            self.with_services(move |services| {
                services.workspace.move_worktree_tab(tab_id as u64, i64::from(index))
            });
        }

        #[qslot]
        fn close_tabs(&self, tab_ids: Vec<i64>) {
            self.with_services(move |services| {
                let workspace = std::rc::Rc::clone(&services.workspace);
                let ids = tab_ids.into_iter().map(|id| id as u64).collect();
                rt::spawn_detached(async move { workspace.close_tabs(ids).await });
            });
        }

        /// Names the tab's repository; an empty name restores the folder's.
        #[qslot]
        fn rename_tab(&self, tab_id: i64, name: String) {
            self.with_services(move |services| {
                let Some(identity) = services
                    .workspace
                    .tab(tab_id as u64)
                    .and_then(|tab| tab.canonical_identity().cloned())
                else {
                    return;
                };
                let appearances = std::rc::Rc::clone(&services.appearances);
                let notices = std::rc::Rc::clone(&services.notices);
                rt::spawn_detached(async move {
                    let name = (!name.trim().is_empty()).then_some(name);
                    if appearances.rename(identity, name).await.is_err() {
                        notices.error("repositoryIconSaveFailed", serde_json::json!([]));
                    }
                });
            });
        }

        /// Removes the icon, colour and image of the tab's repository.
        #[qslot]
        fn remove_tab_icon(&self, tab_id: i64) {
            self.with_services(move |services| {
                let Some(identity) = services
                    .workspace
                    .tab(tab_id as u64)
                    .and_then(|tab| tab.canonical_identity().cloned())
                else {
                    return;
                };
                let appearances = std::rc::Rc::clone(&services.appearances);
                let notices = std::rc::Rc::clone(&services.notices);
                rt::spawn_detached(async move {
                    if appearances.remove_mark(identity).await.is_err() {
                        notices.error("repositoryIconSaveFailed", serde_json::json!([]));
                    }
                });
            });
        }

        /// Puts the tab in a new group; `groupCreated` names it for renaming.
        #[qslot]
        fn create_tab_group(&self, tab_id: i64) {
            let state = self.created.clone();
            self.with_services(move |services| {
                if let Some(group) = services.workspace.create_tab_group(tab_id as u64) {
                    state.set(Some(group));
                }
            });
        }

        #[qslot]
        fn add_tab_to_group(&self, tab_id: i64, group: i64) {
            self.with_services(move |services| services.workspace.add_tab_to_group(tab_id as u64, group as u64));
        }

        #[qslot]
        fn remove_tab_from_group(&self, tab_id: i64) {
            self.with_services(move |services| services.workspace.remove_tab_from_group(tab_id as u64));
        }

        #[qslot]
        fn rename_tab_group(&self, group: i64, name: String) {
            self.with_services(move |services| services.workspace.rename_tab_group(group as u64, &name));
        }

        #[qslot]
        fn edit_tab_group(&self, group: i64, name: String, color: String, icon: String) {
            self.with_services(move |services| {
                services.workspace.edit_tab_group(
                    group as u64,
                    &name,
                    &color,
                    (!icon.is_empty()).then_some(icon.as_str()),
                )
            });
        }

        #[qslot]
        fn set_tab_group_collapsed(&self, group: i64, collapsed: bool) {
            self.with_services(move |services| services.workspace.set_tab_group_collapsed(group as u64, collapsed));
        }

        #[qslot]
        fn ungroup_tabs(&self, group: i64) {
            self.with_services(move |services| services.workspace.ungroup_tabs(group as u64));
        }

        #[qslot]
        fn close_tab_group(&self, group: i64) {
            self.with_services(move |services| {
                let workspace = std::rc::Rc::clone(&services.workspace);
                rt::spawn_detached(async move { workspace.close_tab_group(group as u64).await });
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
