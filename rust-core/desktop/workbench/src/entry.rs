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
    pub clones: Rc<crate::clone::CloneService>,
    prompts: Rc<Prompts>,
    notifier: Notifier,
    state: Cell<EntryState>,
}

impl EntryWorkflows {
    pub fn new(workspace: Rc<WorkspaceService>, prompts: Rc<Prompts>, notifier: Notifier) -> Rc<Self> {
        Rc::new(Self {
            clones: crate::clone::CloneService::new(notifier.clone()),
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

    /// Opens the folders dropped on the window (the Dart
    /// RepositoryDropService): each folder in turn; anything else is
    /// rejected. Says how many opened, were rejected and failed.
    pub async fn open_dropped(self: &Rc<Self>, paths: Vec<String>, notices: &crate::notices::Notices) {
        let (mut opened, mut rejected, mut failed) = (0u64, 0u64, 0u64);
        for path in paths {
            if !std::path::Path::new(&path).is_dir() {
                rejected += 1;
                continue;
            }
            match self.workspace.open(path).await {
                Ok(_) => opened += 1,
                Err(_) => failed += 1,
            }
        }
        notices.status("repositoryDropSummary", serde_json::json!({"opened": opened, "rejected": rejected, "failed": failed}));
    }

    /// Opens the recent repository `identity` on this computer.
    pub async fn open_recent(self: &Rc<Self>, identity: NativePathIdentity) {
        let workspace = Rc::clone(&self.workspace);
        self.run(async move { workspace.open_recent(identity).await.map(Some) })
            .await;
    }

    /// Runs a clone step, keeping its failure for the welcome screen, and
    /// opens the tab of a finished clone.
    async fn cloning<F>(&self, operation: F)
    where
        F: Future<Output = crate::clone::CloneResult<Option<(Option<crate::session::OpenedSession>, bool)>>>,
    {
        if self.state.get().busy {
            return;
        }
        self.set(|state| {
            state.busy = true;
            state.clone_failure = None;
        });
        match operation.await {
            Ok(Some((Some(opened), current))) => {
                if let Err(error) = self.workspace.adopt_opened(opened, current).await
                    && current
                {
                    self.set(|state| state.failure = Some(error.code()));
                }
            }
            Ok(_) => {}
            Err(failure) => self.set(|state| state.clone_failure = Some(failure)),
        }
        self.set(|state| state.busy = false);
    }

    /// Asks for a source and a destination and clones it.
    pub async fn clone_repository(self: &Rc<Self>) {
        let Some(source) = self.prompts.ask("chooseCloneSource", json!({})).await else { return };
        let Some(source) = source.as_str().map(str::trim).filter(|source| !source.is_empty()).map(str::to_owned) else { return };
        let this = Rc::clone(self);
        self.cloning(async move {
            let Some(destination) = this.choose_directory(true).await else { return Ok(None) };
            let generation = this.workspace.next_generation();
            this.clones.start(source, destination, generation).await.map(Some)
        })
        .await;
    }

    /// A new destination when the failed attempt left a partial one.
    async fn retry_destination(&self) -> Result<Option<String>, ()> {
        match self.clones.current() {
            Some(current) if current.partial_destination => self.choose_directory(true).await.map(Some).ok_or(()),
            _ => Ok(None),
        }
    }

    /// Retries the failed clone with credentials the user enters.
    pub async fn retry_clone_with_credentials(self: &Rc<Self>) {
        let Some(answer) = self.prompts.ask("gitCredentials", json!({"target": "", "allowToken": false})).await else { return };
        let username = answer["username"].as_str().filter(|name| !name.is_empty()).map(str::to_owned);
        let secret = answer["secret"].as_str().map(str::to_owned);
        let this = Rc::clone(self);
        self.cloning(async move {
            let Ok(destination) = this.retry_destination().await else { return Ok(None) };
            this.clones.retry_with_credentials(username, secret, None, destination).await.map(Some)
        })
        .await;
    }

    /// Shows the clone's host key and records the user's decision.
    pub async fn inspect_clone_host_key(self: &Rc<Self>) {
        let this = Rc::clone(self);
        self.cloning(async move {
            let challenge = this.clones.probe_host_key().await?;
            let accept = this
                .prompts
                .ask(
                    "trustHostKey",
                    json!({
                        "host": challenge.host,
                        "port": challenge.port,
                        "algorithm": challenge.algorithm,
                        "fingerprint": challenge.fingerprint,
                    }),
                )
                .await
                == Some(serde_json::Value::Bool(true));
            let destination = if accept {
                match this.retry_destination().await {
                    Ok(destination) => destination,
                    Err(()) => return Ok(None),
                }
            } else {
                None
            };
            this.clones.resolve_host_key(&challenge, accept, destination).await
        })
        .await;
    }

    pub async fn cancel_clone(&self) {
        let _ = self.clones.cancel().await;
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
