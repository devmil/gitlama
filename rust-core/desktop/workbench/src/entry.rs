//! Opening, cloning and creating repositories (the Dart
//! `EntryWorkflowService`), and the one owner of what the window says failed.

use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::session::{FailureCode, SessionResult, SessionState};
use crate::workspace::WorkspaceService;
use gitlama_contract::domain::path_identity::NativePathIdentity;
use serde_json::json;
use std::cell::Cell;
use std::future::Future;
use std::rc::Rc;

/// What the welcome screen and the workspace notice show while opening.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct EntryState {
    /// An open, clone or creation runs; the entry actions wait.
    pub busy: bool,
    /// Why the last open or creation failed.
    pub failure: Option<FailureCode>,
    /// Why the last clone failed (a clone failure code name).
    pub clone_failure: Option<&'static str>,
}

pub struct EntryWorkflows {
    workspace: Rc<WorkspaceService>,
    prompts: Rc<Prompts>,
    notifier: Notifier,
    state: Cell<EntryState>,
}

impl EntryWorkflows {
    pub fn new(workspace: Rc<WorkspaceService>, prompts: Rc<Prompts>, notifier: Notifier) -> Rc<Self> {
        Rc::new(Self {
            workspace,
            prompts,
            notifier,
            state: Cell::new(EntryState::default()),
        })
    }

    pub fn current(&self) -> EntryState {
        self.state.get()
    }

    fn set(&self, update: impl FnOnce(&mut EntryState)) {
        let mut state = self.state.get();
        update(&mut state);
        self.state.set(state);
        self.notifier.notify(Topics::WORKSPACE);
    }

    /// Follows the active session: its failure is what the window shows.
    pub fn follow_session(&self, state: Option<&SessionState>) {
        let failure = state.and_then(|state| {
            state
                .snapshot
                .failure
                .as_ref()
                .map(FailureCode::from)
                .or(state.transport_failure)
        });
        if self.state.get().failure != failure {
            self.set(|state| state.failure = failure);
        }
    }

    /// Runs `operation` unless another entry action runs, keeping its
    /// repository failure.
    pub async fn run<F>(&self, operation: F)
    where
        F: Future<Output = SessionResult<Option<SessionState>>>,
    {
        if self.state.get().busy {
            return;
        }
        self.set(|state| {
            state.busy = true;
            state.failure = None;
        });
        if let Err(error) = operation.await {
            self.set(|state| state.failure = Some(error.code()));
        }
        self.set(|state| state.busy = false);
    }

    /// Asks the window for a folder.
    pub async fn choose_directory(&self, can_create: bool) -> Option<String> {
        self.prompts
            .ask("chooseDirectory", json!({ "canCreateDirectories": can_create }))
            .await
            .and_then(|value| value.as_str().map(str::to_owned))
            .filter(|path| !path.is_empty())
    }

    /// Lets the user choose a repository folder and opens it.
    pub async fn open(self: &Rc<Self>) {
        let this = Rc::clone(self);
        self.run(async move {
            let Some(path) = this.choose_directory(false).await else {
                return Ok(None);
            };
            this.workspace.open(path).await.map(Some)
        })
        .await;
    }

    /// Opens `path` (a dropped folder or a command-line argument).
    pub async fn open_path(self: &Rc<Self>, path: String) {
        let workspace = Rc::clone(&self.workspace);
        self.run(async move { workspace.open(path).await.map(Some) }).await;
    }

    /// Opens the recent repository `identity` on this computer.
    pub async fn open_recent(self: &Rc<Self>, identity: NativePathIdentity) {
        let workspace = Rc::clone(&self.workspace);
        self.run(async move { workspace.open_recent(identity).await.map(Some) })
            .await;
    }

    /// Creates a repository on this computer: asks Bare or not, then a folder.
    pub async fn initialize(self: &Rc<Self>, initially_bare: bool) {
        let choice = self
            .prompts
            .ask("initializeRepository", json!({ "initiallyBare": initially_bare }))
            .await;
        let Some(choice) = choice else { return };
        let bare = choice.get("bare").and_then(|value| value.as_bool()).unwrap_or(false);
        let profile = choice
            .get("profileId")
            .and_then(|value| value.as_str())
            .map(str::to_owned);
        if profile.is_some() {
            // Remote creation runs through the remote workspace workflows.
            return;
        }
        let this = Rc::clone(self);
        self.run(async move {
            let Some(path) = this.choose_directory(true).await else {
                return Ok(None);
            };
            this.workspace
                .initialize(path, "main".into(), bare)
                .await
                .map(Some)
        })
        .await;
    }
}
