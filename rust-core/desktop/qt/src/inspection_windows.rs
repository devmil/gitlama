//! Inspection windows: a location of the active repository opens in a
//! window of its own, with its own inspector, diff and blame, beside the
//! main window. A window stays on its repository while the main window
//! switches tabs; Show in main window brings that repository's tab forward
//! and reveals the commit in History.

use crate::blame_model::BlameModel;
use crate::diff_model::DiffModel;
use crate::inspector_state::InspectorState;
use crate::plumbing::Commands;
use gitlama_contract::dto::NativePathIdentity;
use gitlama_workbench::inspector::{InspectorService, Lens, Location, Scope, Target};
use gitlama_workbench::rt;
use qtbridge::{QObjectHolder, qobject};
use serde_json::Value;
use std::cell::{Cell, RefCell};
use std::rc::Rc;

/// One open window: its bridge objects and the repository it inspects.
pub struct Window {
    pub id: u64,
    pub state: Rc<RefCell<InspectorState>>,
    pub diff: Rc<RefCell<DiffModel>>,
    pub blame: Rc<RefCell<BlameModel>>,
    pub repository: RefCell<Option<NativePathIdentity>>,
}

pub type Registry = Rc<RefCell<Vec<Rc<Window>>>>;

/// The location `value` names: {commit, base?, path?, directory?, lens?, scope?}.
pub fn location_of(value: &Value) -> Option<Location> {
    let commit = value["commit"].as_str()?.to_owned();
    let target = match value["base"].as_str().filter(|base| !base.is_empty()) {
        Some(base) => Target::Comparison {
            base: base.to_owned(),
            commit,
        },
        None => Target::Commit(commit),
    };
    let path = value["path"]
        .as_str()
        .filter(|path| !path.is_empty())
        .map(|path| path.as_bytes().to_vec());
    Some(Location {
        target,
        scope: if value["scope"].as_str() == Some("all") {
            Scope::All
        } else {
            Scope::Changed
        },
        directory: value["directory"].as_bool().unwrap_or(false) && path.is_some(),
        lens: match value["lens"].as_str() {
            Some("contents") => Lens::Contents,
            Some("blame") => Lens::Blame,
            Some("history") => Lens::History,
            _ => Lens::Diff,
        },
        path,
        lines: None,
        history_commit: None,
        anchor: 0,
    })
}

#[qobject(ConvertToCamelCase)]
mod inspection_windows {
    use super::*;

    #[derive(Default)]
    pub struct InspectionWindows {
        pub commands: Option<Commands>,
        pub registry: Registry,
        next: Cell<u64>,
    }

    impl InspectionWindows {
        /// Opens `location` of the active repository in a new window's
        /// inspector: the window's id (its objects come from `inspector`,
        /// `diff` and `blame`), or 0 when the location is invalid.
        #[qslot]
        fn open(&self, location: Value) -> i32 {
            let location = crate::json::integral_numbers(location);
            let Some(location) = location_of(&location) else {
                return 0;
            };
            let Some(commands) = self.commands.clone() else {
                return 0;
            };
            let id = self.next.get() + 1;
            self.next.set(id);
            let state = Rc::new(RefCell::new(InspectorState::default()));
            InspectorState::attach_qobject(&state);
            {
                let mut shown = state.borrow_mut();
                shown.commands = Some(commands.clone());
                shown.this = Some(Rc::downgrade(&state));
            }
            let diff = Rc::new(RefCell::new(DiffModel::default()));
            DiffModel::attach_qobject(&diff);
            let blame = Rc::new(RefCell::new(BlameModel::default()));
            BlameModel::attach_qobject(&blame);
            let window = Rc::new(Window {
                id,
                state: Rc::clone(&state),
                diff: Rc::clone(&diff),
                blame: Rc::clone(&blame),
                repository: RefCell::new(None),
            });
            self.registry.borrow_mut().push(Rc::clone(&window));
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let Some(session) = services.workspace.current() else {
                    return;
                };
                *window.repository.borrow_mut() = services.workspace.active_canonical();
                let service = InspectorService::new(
                    Rc::clone(&services.calls),
                    driver.app.notifier().clone(),
                );
                service.attach(session.identity);
                window.state.borrow_mut().service = Some(Rc::clone(&service));
                rt::spawn_detached(
                    async move { service.navigate(location, false, false, None).await },
                );
            });
            id as i32
        }

        /// Window `id`'s inspector.
        #[qslot]
        fn inspector(&self, id: i32) -> Rc<RefCell<InspectorState>> {
            self.window(id)
                .map(|window| Rc::clone(&window.state))
                .unwrap_or_default()
        }

        /// Window `id`'s diff.
        #[qslot]
        fn diff(&self, id: i32) -> Rc<RefCell<DiffModel>> {
            self.window(id)
                .map(|window| Rc::clone(&window.diff))
                .unwrap_or_default()
        }

        /// Window `id`'s blame.
        #[qslot]
        fn blame(&self, id: i32) -> Rc<RefCell<BlameModel>> {
            self.window(id)
                .map(|window| Rc::clone(&window.blame))
                .unwrap_or_default()
        }

        fn window(&self, id: i32) -> Option<Rc<Window>> {
            self.registry
                .borrow()
                .iter()
                .find(|window| window.id == id as u64)
                .cloned()
        }

        /// The host profile window `id`'s repository is on; "" on this computer.
        #[qslot]
        fn host_of(&self, id: i32) -> String {
            self.window(id)
                .and_then(|window| {
                    window
                        .repository
                        .borrow()
                        .as_ref()
                        .and_then(|identity| identity.remote.clone())
                })
                .map(|remote| remote.profile_id)
                .unwrap_or_default()
        }

        /// Shows window `id`'s location again on the session its repository's tab has now
        /// (after a host reconnected).
        #[qslot]
        fn retry(&self, id: i32) {
            let Some(window) = self.window(id) else {
                return;
            };
            let Some(commands) = &self.commands else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let Some(repository) = window.repository.borrow().clone() else {
                    return;
                };
                let session = services.workspace.with_tabs(|tabs, _, _| {
                    tabs.iter()
                        .find(|tab| tab.canonical_identity() == Some(&repository))
                        .and_then(|tab| tab.session.as_ref().map(|session| session.identity))
                });
                let Some(session) = session else { return };
                let Some(service) = window.state.borrow().service.clone() else {
                    return;
                };
                let location = service.current().location.clone();
                service.attach(session);
                if let Some(location) = location {
                    rt::spawn_detached(async move {
                        service.navigate(location, false, false, None).await
                    });
                }
            });
        }

        /// The window `id` closed; its objects go with the next turn.
        #[qslot]
        fn close(&self, id: i32) {
            let registry = Rc::clone(&self.registry);
            if let Some(commands) = &self.commands {
                commands.post(move |_| {
                    registry
                        .borrow_mut()
                        .retain(|window| window.id != id as u64)
                });
            }
        }

        /// Shows the window's commit in the main window: its repository's tab
        /// comes forward and History reveals the commit.
        #[qslot]
        fn show_in_main_window(&self, id: i32, commit: String) {
            let Some(window) = self
                .registry
                .borrow()
                .iter()
                .find(|window| window.id == id as u64)
                .cloned()
            else {
                return;
            };
            let Some(commands) = &self.commands else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let Some(repository) = window.repository.borrow().clone() else {
                    return;
                };
                let tab = services
                    .workspace
                    .workspace()
                    .tabs
                    .iter()
                    .find(|tab| tab.canonical_identity() == Some(&repository))
                    .map(|tab| tab.id);
                let Some(tab) = tab else { return };
                services.workspace.activate_tab(tab);
                let navigator = Rc::clone(&services.navigator);
                rt::spawn_detached(async move {
                    navigator.show_commit(commit, None, false, true).await
                });
            });
        }
    }
}

pub use inspection_windows::InspectionWindows;
