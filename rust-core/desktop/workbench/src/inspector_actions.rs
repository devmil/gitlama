//! What the inspector's file menus do beyond navigation (the Dart
//! InspectorFileActions and PaneInspectorHost): whether a file of a commit
//! exists in the working tree, restoring a file to a commit's version and
//! opening a change in the configured diff tool.

use crate::backend::SessionCalls;
use crate::integrations::{Integrations, definition};
use crate::notices::Notices;
use crate::prompts::Prompts;
use crate::settings::SettingsService;
use crate::workspace::WorkspaceService;
use gitlama_contract::dto::{NativePathPlatform, NativeRestoreState};
use gitlama_contract::integrations::{NativeIntegrationDefinition, NativeIntegrationKind};
use serde_json::{Value, json};
use std::rc::Rc;

/// The largest file a restore previews (as in Flutter).
const RESTORE_BYTE_LIMIT: u32 = 8 * 1024 * 1024;

/// The status line of a finished restore: (key, error).
pub fn restore_message(state: NativeRestoreState) -> (&'static str, bool) {
    match state {
        NativeRestoreState::Restored => ("historyRestoreSucceeded", false),
        NativeRestoreState::Stale => ("historyRestoreStale", false),
        NativeRestoreState::ReconciledWithWarning => ("historyRestoreReconciled", false),
        NativeRestoreState::OutcomeUncertain => ("historyRestoreOutcomeUncertain", false),
        NativeRestoreState::Failed => ("historyRestoreFailed", false),
    }
}

pub struct InspectorActions {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    settings: Rc<SettingsService>,
    integrations: Rc<Integrations>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
}

impl InspectorActions {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        settings: Rc<SettingsService>,
        integrations: Rc<Integrations>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            settings,
            integrations,
            prompts,
            notices,
        })
    }

    /// Whether the active repository lives on another computer.
    pub fn remote(&self) -> bool {
        self.workspace
            .active_canonical()
            .is_some_and(|root| root.remote.is_some())
    }

    /// Whether working-tree files can be opened (a local repository).
    pub fn can_open_working_copy(&self) -> bool {
        self.workspace
            .active_canonical()
            .is_some_and(|root| root.remote.is_none())
    }

    /// Whether `path` (repository-relative) exists in the local working tree.
    pub fn exists_in_working_tree(&self, path: &str) -> bool {
        let Some(root) = self
            .workspace
            .active_canonical()
            .filter(|root| root.remote.is_none())
        else {
            return false;
        };
        let root = match root.platform {
            NativePathPlatform::Windows => String::from_utf16_lossy(&root.units),
            NativePathPlatform::Unix => {
                #[cfg(unix)]
                {
                    use std::os::unix::ffi::OsStringExt;
                    let bytes: Vec<u8> = root.units.iter().map(|unit| *unit as u8).collect();
                    return std::path::PathBuf::from(std::ffi::OsString::from_vec(bytes))
                        .join(path)
                        .symlink_metadata()
                        .is_ok();
                }
                #[cfg(not(unix))]
                String::from_utf16_lossy(&root.units)
            }
        };
        std::path::Path::new(&root)
            .join(path)
            .symlink_metadata()
            .is_ok()
    }

    /// The configured diff tool, if any.
    pub fn diff_tool(&self) -> Option<NativeIntegrationDefinition> {
        self.settings.with(|document| {
            document
                .integrations
                .iter()
                .filter_map(definition)
                .find(|tool| tool.kind == NativeIntegrationKind::DiffTool)
        })
    }

    /// Previews restoring `path` to its content in `commit`, asks for
    /// confirmation and reports the outcome.
    pub async fn restore(&self, path: String, commit: String) {
        let Some(session) = self.workspace.current() else {
            return;
        };
        if self.remote() {
            return self.notices.status("remoteCommandUnsupported", Value::Null);
        }
        let identity = session.identity;
        let preview = self
            .calls
            .repository_session_restore_preview(
                identity.native_id,
                identity.generation,
                commit,
                path.clone().into_bytes(),
                RESTORE_BYTE_LIMIT,
            )
            .await
            .ok()
            .and_then(|result| result.preview.filter(|_| result.failure.is_none()));
        let Some(preview) = preview else {
            return self.notices.error("historyRestoreFailed", Value::Null);
        };
        let payload = json!({
            "path": path,
            "source": preview.source_bytes.len(),
            "current": preview.current_bytes.as_ref().map(Vec::len),
        });
        if self.prompts.ask("confirmRestore", payload).await != Some(Value::Bool(true)) {
            return;
        }
        match self
            .calls
            .repository_session_restore_file(identity.native_id, identity.generation, preview.token)
            .await
        {
            Ok(result) => {
                let (key, error) = restore_message(result.state);
                if error {
                    self.notices.error(key, Value::Null)
                } else {
                    self.notices.status(key, Value::Null)
                }
            }
            Err(_) => self.notices.error("historyRestoreFailed", Value::Null),
        }
    }

    /// Opens a change of the shown target in the configured diff tool.
    pub async fn external_diff(
        &self,
        old_revision: Option<String>,
        new_revision: String,
        old_path: String,
        new_path: String,
    ) {
        let Some(tool) = self.diff_tool() else { return };
        let Some(session) = self.workspace.current() else {
            return;
        };
        let identity = session.identity;
        let preview = self
            .calls
            .repository_session_commit_external_diff_preview(
                identity.native_id,
                identity.generation,
                old_revision,
                new_revision,
                Some(old_path.into_bytes()),
                Some(new_path.into_bytes()),
                tool,
            )
            .await
            .ok()
            .and_then(|result| result.preview.filter(|_| result.failure.is_none()));
        let Some(preview) = preview else {
            return self.notices.error("integrationLaunchFailed", Value::Null);
        };
        self.integrations
            .confirm_and_run(
                identity.native_id,
                identity.generation,
                preview,
                "integrationDiffSummary",
                true,
            )
            .await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn restores_report_each_outcome() {
        assert_eq!(
            restore_message(NativeRestoreState::Restored),
            ("historyRestoreSucceeded", false)
        );
        assert_eq!(
            restore_message(NativeRestoreState::Stale).0,
            "historyRestoreStale"
        );
        assert_eq!(
            restore_message(NativeRestoreState::Failed).0,
            "historyRestoreFailed"
        );
    }
}
