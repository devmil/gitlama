//! Repository extensions (the Dart ExtensionCommands and
//! RepositoryExtensionsPanel): worktrees, submodules, Git LFS and the
//! `.gitignore` entry that hides a changed path.

use crate::backend::SessionCalls;
use crate::notices::Notices;
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::session::{SessionIdentity, display_path, local_path};
use crate::sidebar::{SidebarService, worktree_deletion_protected};
use crate::workspace::WorkspaceService;
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::extensions::{
    NativeExtensionFailureKind, NativeExtensionInventory, NativeExtensionMutationKind,
    NativeExtensionMutationRequest, NativeExtensionMutationResult, NativeExtensionMutationState,
    NativeLfsPathState, NativeSubmoduleState, NativeWorktreeEntry,
};
use serde_json::{Value, json};
use std::cell::RefCell;
use std::rc::Rc;

/// The extensions panel's state.
#[derive(Clone, Debug, Default)]
pub struct Panel {
    pub inventory: Option<NativeExtensionInventory>,
    pub busy: bool,
    pub failure: Option<&'static str>,
    /// The references a new worktree can check out.
    pub names: Vec<String>,
}

/// What a panel action names: a row of one of the inventory's lists.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PanelAction {
    OpenWorktree(usize),
    DeleteWorktree(usize),
    Submodule(usize),
    EnterSubmodule(usize),
    InspectPointer(usize),
}

/// The failure a mutation reports, unless its outcome is uncertain.
pub fn reported_failure(
    result: &NativeExtensionMutationResult,
) -> Option<NativeExtensionFailureKind> {
    if result.state == NativeExtensionMutationState::OutcomeUncertain {
        return None;
    }
    result
        .failure
        .as_ref()
        .map(|failure| failure.kind)
        .or(match result.state {
            NativeExtensionMutationState::Failed => Some(NativeExtensionFailureKind::Git),
            NativeExtensionMutationState::Canceled => Some(NativeExtensionFailureKind::Canceled),
            _ => None,
        })
}

/// What a failed extension change says (the Dart extensionFailureLabel).
pub fn failure_key(kind: NativeExtensionFailureKind) -> &'static str {
    match kind {
        NativeExtensionFailureKind::InvalidRequest => "extensionFailureInvalid",
        NativeExtensionFailureKind::Unavailable => "extensionFailureUnavailable",
        NativeExtensionFailureKind::Dirty => "extensionFailureDirty",
        NativeExtensionFailureKind::Locked => "extensionFailureLocked",
        NativeExtensionFailureKind::CurrentWorktree => "extensionFailureCurrent",
        NativeExtensionFailureKind::Stale => "extensionFailureStale",
        NativeExtensionFailureKind::Canceled => "extensionFailureCanceled",
        NativeExtensionFailureKind::TooLarge => "extensionFailureTooLarge",
        NativeExtensionFailureKind::Read | NativeExtensionFailureKind::Git => "extensionFailureGit",
    }
}

/// The field error of the ignore dialog for `kind`.
pub fn ignore_failure_key(kind: NativeExtensionFailureKind) -> &'static str {
    if kind == NativeExtensionFailureKind::InvalidRequest {
        "ignoreFailureInvalid"
    } else {
        "ignoreFailureWrite"
    }
}

pub struct Extensions {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    sidebar: Rc<SidebarService>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    notifier: Notifier,
    panel: RefCell<Panel>,
    /// The worktrees the tab row's open menu last listed.
    menu_worktrees: RefCell<Vec<gitlama_contract::extensions::NativeWorktreeEntry>>,
}

impl Extensions {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        sidebar: Rc<SidebarService>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            sidebar,
            prompts,
            notices,
            notifier,
            panel: RefCell::new(Panel::default()),
            menu_worktrees: RefCell::new(Vec::new()),
        })
    }

    pub fn panel(&self) -> Panel {
        self.panel.borrow().clone()
    }

    fn update(&self, change: impl FnOnce(&mut Panel)) {
        change(&mut self.panel.borrow_mut());
        self.notifier.notify(Topics::OPERATIONS);
    }

    /// Runs `request` for the active repository. Deleting a worktree first
    /// closes its other tabs and reopens them when the deletion does not
    /// happen (the Dart ExtensionCommands.execute).
    async fn execute(
        &self,
        identity: SessionIdentity,
        request: NativeExtensionMutationRequest,
    ) -> Result<NativeExtensionMutationResult, ()> {
        let mut closed = Vec::new();
        if request.kind == NativeExtensionMutationKind::WorktreeDelete
            && let Some(root) = &request.worktree_root
        {
            closed = self.workspace.close_worktree_tabs(root, identity).await;
        }
        let result = self
            .calls
            .repository_session_extension_execute(identity.native_id, identity.generation, request)
            .await;
        let restore = match &result {
            Ok(result) => matches!(
                result.state,
                NativeExtensionMutationState::Failed
                    | NativeExtensionMutationState::Canceled
                    | NativeExtensionMutationState::OutcomeUncertain
            ),
            Err(_) => true,
        };
        if restore && !closed.is_empty() {
            self.workspace.restore_worktree_tabs(closed, identity).await;
        }
        result.map_err(|_| ())
    }

    /// Reads the inventory again.
    pub async fn load(&self) {
        let Some(identity) = self.workspace.current().map(|session| session.identity) else {
            return;
        };
        self.update(|panel| {
            panel.busy = true;
            panel.failure = None;
        });
        let result = self
            .calls
            .repository_session_extensions(identity.native_id, identity.generation)
            .await;
        self.update(|panel| {
            panel.busy = false;
            match result {
                Ok(result) => match (result.inventory, result.failure) {
                    (Some(inventory), None) => panel.inventory = Some(inventory),
                    (_, failure) => {
                        panel.failure = Some(failure_key(
                            failure.map_or(NativeExtensionFailureKind::Git, |failure| failure.kind),
                        ))
                    }
                },
                Err(_) => panel.failure = Some(failure_key(NativeExtensionFailureKind::Stale)),
            }
        });
    }

    /// The worktree row's open menu (the Dart _showWorktreeMenu): the
    /// repository's worktrees that are neither open nor prunable, as
    /// [{label, icon}]; `None` when they could not be listed.
    pub async fn worktree_menu(&self) -> Option<Value> {
        let identity = self.workspace.current().map(|session| session.identity)?;
        let result = self
            .calls
            .repository_session_extensions(identity.native_id, identity.generation)
            .await
            .ok()?;
        let inventory = result.inventory.filter(|_| result.failure.is_none())?;
        let workspace = self.workspace.workspace();
        // Every worktree of the active repository that has a tab, even alone.
        let open: Vec<NativePathIdentity> = workspace
            .entry_of(workspace.active_tab_id)
            .into_iter()
            .filter_map(|tab| tab.canonical_identity().cloned())
            .collect();
        let closed: Vec<_> = inventory
            .worktrees
            .into_iter()
            .filter(|entry| !entry.prunable && !open.contains(&entry.worktree_root))
            .collect();
        let rows = closed
            .iter()
            .map(|entry| {
                json!({
                    "label": entry.branch.as_ref().map_or_else(
                        || crate::session::basename(&entry.worktree_root),
                        |branch| crate::sidebar::display_reference(&String::from_utf8_lossy(branch)).to_owned(),
                    ),
                    "icon": if entry.git_dir == entry.common_git_dir { "house" } else { "git-branch" },
                })
            })
            .collect();
        *self.menu_worktrees.borrow_mut() = closed;
        Some(Value::Array(rows))
    }

    /// Opens worktree `index` of the last open menu in a tab.
    pub async fn open_menu_worktree(&self, index: usize) {
        let Some(root) = self
            .menu_worktrees
            .borrow()
            .get(index)
            .map(|entry| entry.worktree_root.clone())
        else {
            return;
        };
        // A failed tab stays visible with its error.
        let _ = self.workspace.open_recent(root).await;
    }

    /// The panel opened: it starts from a fresh inventory.
    pub async fn open(&self) {
        let names = self
            .workspace
            .current()
            .map(|session| {
                crate::power_tools::reference_choices(&session.snapshot)
                    .into_iter()
                    .map(|(name, _)| name)
                    .collect()
            })
            .unwrap_or_default();
        self.update(|panel| {
            *panel = Panel {
                names,
                ..Panel::default()
            }
        });
        self.load().await;
    }

    /// Runs a change from the panel; a reported failure shows in its banner,
    /// anything else reloads the inventory.
    async fn run(&self, request: NativeExtensionMutationRequest) {
        if self.panel.borrow().busy {
            return;
        }
        let Some(identity) = self.workspace.current().map(|session| session.identity) else {
            return;
        };
        self.update(|panel| {
            panel.busy = true;
            panel.failure = None;
        });
        let result = self.execute(identity, request).await;
        let failure = match &result {
            Ok(result) => reported_failure(result),
            Err(()) => Some(NativeExtensionFailureKind::Git),
        };
        self.update(|panel| {
            panel.busy = false;
            panel.failure = failure.map(failure_key);
        });
        if failure.is_none() {
            if result
                .is_ok_and(|result| result.state == NativeExtensionMutationState::OutcomeUncertain)
            {
                self.notices.error("mutationOutcomeUncertain", Value::Null);
            }
            self.sidebar.reload_worktrees();
            self.load().await;
        }
    }

    fn request(kind: NativeExtensionMutationKind) -> NativeExtensionMutationRequest {
        NativeExtensionMutationRequest {
            kind,
            path: None,
            worktree_root: None,
            pattern: None,
            reference: None,
        }
    }

    /// Adds a worktree at `path` (a folder on this computer) checked out at
    /// `reference`.
    pub async fn create_worktree(&self, path: String, reference: String) {
        let (path, reference) = (path.trim().to_owned(), reference.trim().to_owned());
        if path.is_empty() || reference.is_empty() || self.panel.borrow().inventory.is_none() {
            return;
        }
        let mut request = Self::request(NativeExtensionMutationKind::WorktreeCreate);
        request.worktree_root = Some(local_path(&path));
        request.reference = Some(reference);
        self.run(request).await;
    }

    pub async fn lfs(&self, kind: NativeExtensionMutationKind, pattern: String) {
        let mut request = Self::request(kind);
        if kind != NativeExtensionMutationKind::LfsPull {
            request.pattern = Some(pattern.trim().to_owned());
        }
        self.run(request).await;
    }

    /// Runs `action` on its row of the inventory.
    pub async fn act(&self, action: PanelAction) {
        let Some(inventory) = self.panel.borrow().inventory.clone() else {
            return;
        };
        match action {
            PanelAction::OpenWorktree(index) => {
                if let Some(entry) = inventory
                    .worktrees
                    .get(index)
                    .filter(|entry| !entry.current)
                {
                    // A failed tab stays visible with its error.
                    let _ = self
                        .workspace
                        .open_recent(entry.worktree_root.clone())
                        .await;
                }
            }
            PanelAction::DeleteWorktree(index) => {
                let Some(entry) = inventory.worktrees.get(index).cloned() else {
                    return;
                };
                if worktree_deletion_protected(&inventory, &entry) {
                    return;
                }
                let payload = json!({"path": display_path(&entry.worktree_root)});
                if self.prompts.ask("confirmWorktreeDelete", payload).await
                    != Some(Value::Bool(true))
                {
                    return;
                }
                let mut request = Self::request(NativeExtensionMutationKind::WorktreeDelete);
                request.worktree_root = Some(entry.worktree_root);
                self.run(request).await;
            }
            PanelAction::Submodule(index) => {
                let Some(entry) = inventory.submodules.get(index) else {
                    return;
                };
                let kind = if entry.state == NativeSubmoduleState::Uninitialized {
                    NativeExtensionMutationKind::SubmoduleInit
                } else {
                    NativeExtensionMutationKind::SubmoduleUpdate
                };
                let mut request = Self::request(kind);
                request.path = Some(entry.path.clone());
                self.run(request).await;
            }
            PanelAction::EnterSubmodule(index) => {
                let Some(entry) = inventory
                    .submodules
                    .get(index)
                    .filter(|entry| entry.state != NativeSubmoduleState::Uninitialized)
                else {
                    return;
                };
                let Some(identity) = self.workspace.current().map(|session| session.identity)
                else {
                    return;
                };
                let failure = match self
                    .calls
                    .repository_session_submodule_enter(
                        identity.native_id,
                        identity.generation,
                        entry.path.clone(),
                    )
                    .await
                {
                    Ok(result) => match (result.worktree_root, result.failure) {
                        (Some(root), None) => {
                            let _ = self.workspace.open_recent(root).await;
                            None
                        }
                        (_, failure) => Some(
                            failure.map_or(NativeExtensionFailureKind::Git, |failure| failure.kind),
                        ),
                    },
                    Err(_) => Some(NativeExtensionFailureKind::Stale),
                };
                if let Some(kind) = failure {
                    self.update(|panel| panel.failure = Some(failure_key(kind)));
                }
            }
            PanelAction::InspectPointer(index) => {
                let Some(entry) = inventory.lfs_entries.get(index) else {
                    return;
                };
                let Some(identity) = self.workspace.current().map(|session| session.identity)
                else {
                    return;
                };
                match self
                    .calls
                    .repository_session_lfs_pointer(
                        identity.native_id,
                        identity.generation,
                        entry.path.clone(),
                    )
                    .await
                {
                    Ok(result) if result.failure.is_none() => {
                        let payload = json!({
                            "path": String::from_utf8_lossy(&entry.path),
                            "oid": result.pointer.as_ref().map(|pointer| pointer.oid_sha256.clone()),
                            "size": result.pointer.as_ref().map(|pointer| pointer.size),
                        });
                        self.prompts.ask("lfsPointer", payload).await;
                    }
                    Ok(result) => {
                        let key = failure_key(
                            result
                                .failure
                                .map_or(NativeExtensionFailureKind::Git, |failure| failure.kind),
                        );
                        self.update(|panel| panel.failure = Some(key));
                    }
                    Err(_) => self.update(|panel| {
                        panel.failure = Some(failure_key(NativeExtensionFailureKind::Stale))
                    }),
                }
            }
        }
    }

    /// Deletes linked worktree `index` of the sidebar's inventory after a
    /// confirmation (the Dart sidebar _delete).
    pub async fn delete_worktree(&self, index: usize) {
        let Some(inventory) = self.sidebar.worktrees() else {
            return;
        };
        let Some(entry) = inventory.worktrees.get(index).cloned() else {
            return;
        };
        if worktree_deletion_protected(&inventory, &entry) {
            return;
        }
        let Some(session) = self.workspace.current() else {
            return;
        };
        let identity = session.identity;
        let payload = json!({"path": display_path(&entry.worktree_root)});
        if self.prompts.ask("confirmWorktreeDelete", payload).await != Some(Value::Bool(true)) {
            return;
        }
        if self.workspace.current().map(|session| session.identity) != Some(identity) {
            return;
        }
        self.sidebar.set_worktree_failure(None);
        let request = NativeExtensionMutationRequest {
            kind: NativeExtensionMutationKind::WorktreeDelete,
            path: None,
            worktree_root: Some(entry.worktree_root),
            pattern: None,
            reference: None,
        };
        let failure = match self.execute(identity, request).await {
            Ok(result) if result.state == NativeExtensionMutationState::OutcomeUncertain => {
                self.notices.error("mutationOutcomeUncertain", Value::Null);
                self.sidebar.reload_worktrees();
                return;
            }
            Ok(result) => reported_failure(&result),
            Err(_) => Some(NativeExtensionFailureKind::Git),
        };
        if let Some(failure) = failure {
            self.notices.error(failure_key(failure), Value::Null);
        }
        self.sidebar.set_worktree_failure(failure.map(failure_key));
        self.sidebar.reload_worktrees();
    }

    /// Offers the `.gitignore` entry that matches exactly `path` and adds
    /// the entry the person confirms; a failed write asks again with the
    /// entry kept and the failure shown.
    pub async fn ignore(&self, path: String, directory: bool, tracked: bool) {
        let Some(session) = self.workspace.current() else {
            return;
        };
        let identity = session.identity;
        let mut entry = gitlama_core::api::ignore_exact_pattern(path.into_bytes(), directory)
            .unwrap_or_default();
        let mut failure: Option<&'static str> = None;
        loop {
            let payload = json!({"entry": entry, "directory": directory, "tracked": tracked, "failure": failure});
            let Some(answer) = self.prompts.ask("ignorePath", payload).await else {
                return;
            };
            let Some(pattern) = answer
                .as_str()
                .map(str::to_owned)
                .filter(|pattern| !pattern.trim().is_empty())
            else {
                return;
            };
            if self.workspace.current().map(|session| session.identity) != Some(identity) {
                return;
            }
            let request = NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::IgnoreAdd,
                path: None,
                worktree_root: None,
                pattern: Some(pattern.clone()),
                reference: None,
            };
            match self
                .calls
                .repository_session_extension_execute(
                    identity.native_id,
                    identity.generation,
                    request,
                )
                .await
            {
                Ok(result) => {
                    if let Some(kind) = reported_failure(&result) {
                        entry = pattern;
                        failure = Some(ignore_failure_key(kind));
                        continue;
                    }
                    if result.state == NativeExtensionMutationState::OutcomeUncertain {
                        self.notices.error("mutationOutcomeUncertain", Value::Null);
                    }
                    return;
                }
                Err(_) => {
                    entry = pattern;
                    failure = Some("ignoreFailureWrite");
                }
            }
        }
    }
}

/// The last part of `path`, or all of it.
fn folder_name(path: &str) -> String {
    path.split(['/', '\\'])
        .rfind(|part| !part.is_empty())
        .unwrap_or(path)
        .to_owned()
}

fn worktree_value(inventory: &NativeExtensionInventory, entry: &NativeWorktreeEntry) -> Value {
    let path = display_path(&entry.worktree_root);
    let branch = entry.branch.as_deref().map(|branch| {
        let name = String::from_utf8_lossy(branch).into_owned();
        name.strip_prefix("refs/heads/")
            .map(str::to_owned)
            .unwrap_or(name)
    });
    json!({
        "title": branch.clone().unwrap_or_else(|| folder_name(&path)),
        "path": path,
        "locked": entry.locked,
        "current": entry.current,
        "head": entry.head.as_deref().map(|head| head.chars().take(8).collect::<String>()),
        "deletable": !worktree_deletion_protected(inventory, entry),
    })
}

/// The panel as the presentation shows it.
pub fn panel_value(panel: &Panel) -> Value {
    let inventory = panel.inventory.as_ref().map(|inventory| {
        json!({
            "worktrees": inventory.worktrees.iter().map(|entry| worktree_value(inventory, entry)).collect::<Vec<_>>(),
            "submodules": inventory.submodules.iter().map(|entry| json!({
                "path": String::from_utf8_lossy(&entry.path),
                "state": match entry.state {
                    NativeSubmoduleState::AtRecordedCommit => "extensionSubmoduleRecorded",
                    NativeSubmoduleState::DifferentCommit => "extensionSubmoduleDifferent",
                    NativeSubmoduleState::Uninitialized => "extensionSubmoduleUninitialized",
                    NativeSubmoduleState::Conflicted => "extensionSubmoduleConflicted",
                },
                "initialized": entry.state != NativeSubmoduleState::Uninitialized,
            })).collect::<Vec<_>>(),
            "lfsAvailable": inventory.lfs_available,
            "lfs": inventory.lfs_entries.iter().map(|entry| json!({
                "path": String::from_utf8_lossy(&entry.path),
                "state": match entry.state {
                    NativeLfsPathState::Pointer => "extensionLfsStatePointer",
                    NativeLfsPathState::Materialized => "extensionLfsStateMaterialized",
                    NativeLfsPathState::Missing => "extensionLfsStateMissing",
                },
            })).collect::<Vec<_>>(),
        })
    });
    json!({"busy": panel.busy, "failure": panel.failure, "inventory": inventory, "names": panel.names})
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_contract::extensions::NativeExtensionFailure;

    fn result(
        state: NativeExtensionMutationState,
        failure: Option<NativeExtensionFailureKind>,
    ) -> NativeExtensionMutationResult {
        NativeExtensionMutationResult {
            state,
            activity_ids: vec![],
            failure: failure.map(|kind| NativeExtensionFailure { kind }),
        }
    }

    #[test]
    fn failures_are_reported_unless_the_outcome_is_uncertain() {
        use NativeExtensionMutationState::*;
        assert_eq!(reported_failure(&result(Completed, None)), None);
        assert_eq!(
            reported_failure(&result(Failed, None)),
            Some(NativeExtensionFailureKind::Git)
        );
        assert_eq!(
            reported_failure(&result(Canceled, None)),
            Some(NativeExtensionFailureKind::Canceled)
        );
        assert_eq!(
            reported_failure(&result(
                Failed,
                Some(NativeExtensionFailureKind::InvalidRequest)
            )),
            Some(NativeExtensionFailureKind::InvalidRequest)
        );
        assert_eq!(
            reported_failure(&result(
                OutcomeUncertain,
                Some(NativeExtensionFailureKind::Git)
            )),
            None
        );
        assert_eq!(
            ignore_failure_key(NativeExtensionFailureKind::InvalidRequest),
            "ignoreFailureInvalid"
        );
        assert_eq!(
            ignore_failure_key(NativeExtensionFailureKind::Locked),
            "ignoreFailureWrite"
        );
    }
}
