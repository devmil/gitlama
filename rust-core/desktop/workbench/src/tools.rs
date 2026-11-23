//! The Custom commands settings page (the Dart IntegrationsPanel embedded
//! in Settings): the tools found on this computer and the configured ones,
//! each run after a preview of its command, and a form that validates a
//! new tool with the core before it is stored.

use crate::backend::SessionCalls;
use crate::integrations::{kind_name, parse_kind};
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::settings::SettingsService;
use crate::workspace::WorkspaceService;
use gitlama_contract::dto::{NativePathIdentity, NativePathPlatform};
use gitlama_contract::integrations::{
    NativeIntegrationCandidate, NativeIntegrationDefinition, NativeIntegrationExecution, NativeIntegrationExecutionState,
    NativeIntegrationFailureKind, NativeIntegrationKind, NativeIntegrationLaunchMode, NativeIntegrationRequest, NativeIntegrationSettings,
    NativeIntegrationVariables,
};
use serde_json::{Value, json};
use std::cell::RefCell;
use std::rc::Rc;

/// What a failed tool says (the Dart _integrationFailureLabel).
pub fn failure_key(kind: NativeIntegrationFailureKind) -> &'static str {
    use NativeIntegrationFailureKind::*;
    match kind {
        InvalidRequest => "integrationInvalid",
        Unavailable => "integrationUnavailable",
        MissingVariable => "integrationMissingVariable",
        Stale => "integrationStale",
        ConfirmationRequired => "integrationConfirmationRequired",
        Canceled => "operationStateCanceled",
        TimedOut => "integrationTimedOut",
        NonZeroExit => "integrationNonZero",
        Launch => "integrationLaunchFailed",
        Read => "integrationReadFailed",
    }
}

/// The kinds discovery looks for.
const DISCOVERED: [NativeIntegrationKind; 5] = [
    NativeIntegrationKind::Editor,
    NativeIntegrationKind::Terminal,
    NativeIntegrationKind::FileManager,
    NativeIntegrationKind::DiffTool,
    NativeIntegrationKind::MergeTool,
];

/// A new tool as the form describes it.
#[derive(Clone, Debug, Default)]
pub struct Form {
    pub id: String,
    pub kind: String,
    pub executable: String,
    /// One argument per line.
    pub arguments: String,
    pub explicit_shell: bool,
    pub wait: bool,
    pub confirmation: bool,
    pub timeout: String,
}

/// The page's state.
#[derive(Clone, Debug, Default)]
pub struct Page {
    pub discovered: Vec<NativeIntegrationCandidate>,
    pub busy: bool,
    pub failure: Option<&'static str>,
    /// Bumps when a tool was saved, so the form clears.
    pub saved: u64,
}

pub struct ToolsPage {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    settings: Rc<SettingsService>,
    prompts: Rc<Prompts>,
    notifier: Notifier,
    page: RefCell<Page>,
}

/// The tool `form` describes for a repository on `platform`, or None while
/// a field is missing or the timeout is not a number.
pub fn form_definition(form: &Form, platform: NativePathPlatform) -> Option<NativeIntegrationDefinition> {
    let id = form.id.trim();
    let executable = form.executable.trim();
    let timeout = form.timeout.trim().parse::<u32>().ok()?;
    if id.is_empty() || executable.is_empty() {
        return None;
    }
    let executable = match platform {
        NativePathPlatform::Windows => NativePathIdentity { platform, units: executable.encode_utf16().collect(), remote: None },
        NativePathPlatform::Unix => NativePathIdentity { platform, units: executable.bytes().map(u16::from).collect(), remote: None },
    };
    let kind = parse_kind(&form.kind).unwrap_or(NativeIntegrationKind::Custom);
    Some(NativeIntegrationDefinition {
        id: id.to_owned(),
        kind,
        executable,
        arguments: form.arguments.split('\n').filter(|line| !line.is_empty()).map(str::to_owned).collect(),
        execution: if form.explicit_shell { NativeIntegrationExecution::ExplicitShell } else { NativeIntegrationExecution::Direct },
        // A custom command always waits for its result.
        launch_mode: if form.wait || kind == NativeIntegrationKind::Custom {
            NativeIntegrationLaunchMode::Wait
        } else {
            NativeIntegrationLaunchMode::Detached
        },
        requires_confirmation: form.confirmation,
        timeout_seconds: timeout,
    })
}

fn stored(definition: &NativeIntegrationDefinition) -> NativeIntegrationSettings {
    NativeIntegrationSettings {
        id: definition.id.clone(),
        kind: kind_name(definition.kind).to_owned(),
        executable: definition.executable.clone(),
        arguments: definition.arguments.clone(),
        explicit_shell: definition.execution == NativeIntegrationExecution::ExplicitShell,
        wait: definition.launch_mode == NativeIntegrationLaunchMode::Wait,
        requires_confirmation: definition.requires_confirmation,
        timeout_seconds: definition.timeout_seconds,
    }
}

impl ToolsPage {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        settings: Rc<SettingsService>,
        prompts: Rc<Prompts>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self { calls, workspace, settings, prompts, notifier, page: RefCell::new(Page::default()) })
    }

    pub fn page(&self) -> Page {
        self.page.borrow().clone()
    }

    fn update(&self, change: impl FnOnce(&mut Page)) {
        change(&mut self.page.borrow_mut());
        self.notifier.notify(Topics::OPERATIONS);
    }

    /// The tools stored in the settings, as definitions.
    pub fn configured(&self) -> Vec<NativeIntegrationSettings> {
        self.settings.with(|document| document.integrations.clone())
    }

    /// The variables a tool sees from this page: the repository for every
    /// path (the Dart panel's _variables).
    fn variables(&self) -> NativeIntegrationVariables {
        let root = self.workspace.active_canonical();
        let status = self.workspace.current().and_then(|session| session.snapshot.status.clone());
        NativeIntegrationVariables {
            url: Some("https://example.invalid/".to_owned()),
            file: root.clone(),
            current_branch: status.as_ref().and_then(|status| status.branch_name.clone()),
            selected_commit: status.as_ref().and_then(|status| status.head_object_id.clone()),
            diff_left: root.clone(),
            diff_right: root.clone(),
            merge_base: root.clone(),
            merge_current: root.clone(),
            merge_incoming: root.clone(),
            merge_result: root,
        }
    }

    /// The page opened: it looks for installed tools.
    pub async fn open(&self) {
        self.update(|page| {
            page.busy = true;
            page.failure = None;
        });
        let mut found = Vec::new();
        for kind in DISCOVERED {
            if let Ok(result) = self.calls.integration_discover(kind).await {
                found.extend(result.candidates);
            }
        }
        self.update(|page| {
            page.discovered = found;
            page.busy = false;
        });
    }

    async fn run(&self, request: NativeIntegrationRequest) {
        if self.page.borrow().busy {
            return;
        }
        let Some(identity) = self.workspace.current().map(|session| session.identity) else { return };
        self.update(|page| {
            page.busy = true;
            page.failure = None;
        });
        let failure = self.preview_and_run(identity.native_id, identity.generation, request).await;
        self.update(|page| {
            page.busy = false;
            page.failure = failure;
        });
    }

    async fn preview_and_run(&self, session: u64, generation: u64, request: NativeIntegrationRequest) -> Option<&'static str> {
        let preview = match self.calls.repository_session_integration_preview(session, generation, request).await {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => preview,
                (_, failure) => return Some(failure_key(failure.map_or(NativeIntegrationFailureKind::Launch, |failure| failure.kind))),
            },
            Err(_) => return Some(failure_key(NativeIntegrationFailureKind::Stale)),
        };
        let commands: Vec<String> = std::iter::once(preview.executable.clone()).chain(preview.arguments.iter().cloned()).collect();
        let answer = self.prompts.ask("confirmIntegration", json!({"commands": commands, "summary": "integrationRunSummary"})).await;
        if answer != Some(Value::Bool(true)) {
            let _ = self.calls.repository_session_integration_cancel(session, generation, preview.token).await;
            return None;
        }
        match self.calls.repository_session_integration_execute(session, generation, preview.token, true).await {
            Ok(result) => match result.failure {
                Some(failure) => Some(failure_key(failure.kind)),
                None if matches!(result.state, NativeIntegrationExecutionState::Completed | NativeIntegrationExecutionState::Detached) => None,
                None => Some(failure_key(NativeIntegrationFailureKind::Launch)),
            },
            Err(_) => Some(failure_key(NativeIntegrationFailureKind::Stale)),
        }
    }

    /// Runs discovered tool `index`.
    pub async fn run_discovered(&self, index: usize) {
        let Some(candidate) = self.page.borrow().discovered.get(index).cloned() else { return };
        let request = NativeIntegrationRequest {
            kind: candidate.kind,
            discovered_id: Some(candidate.id),
            configured: None,
            variables: self.variables(),
        };
        self.run(request).await;
    }

    /// Runs the stored tool `id`.
    pub async fn run_configured(&self, id: &str) {
        let Some(definition) =
            self.settings.with(|document| document.integrations.iter().find(|tool| tool.id == id).and_then(crate::integrations::definition))
        else {
            return;
        };
        let request =
            NativeIntegrationRequest { kind: definition.kind, discovered_id: None, configured: Some(definition), variables: self.variables() };
        self.run(request).await;
    }

    /// Checks the tool `form` describes with the core, then stores it in
    /// place of any tool with its name.
    pub async fn save(&self, form: Form) {
        if self.page.borrow().busy {
            return;
        }
        let Some(root) = self.workspace.active_canonical() else { return };
        let Some(definition) = form_definition(&form, root.platform) else { return };
        let Some(identity) = self.workspace.current().map(|session| session.identity) else { return };
        self.update(|page| {
            page.busy = true;
            page.failure = None;
        });
        let request = NativeIntegrationRequest {
            kind: definition.kind,
            discovered_id: None,
            configured: Some(definition.clone()),
            variables: self.variables(),
        };
        let failure = match self.calls.repository_session_integration_preview(identity.native_id, identity.generation, request).await {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => {
                    let _ = self.calls.repository_session_integration_cancel(identity.native_id, identity.generation, preview.token).await;
                    let value = stored(&definition);
                    let saved = self
                        .settings
                        .update_durable(
                            |document| {
                                document.integrations.retain(|tool| tool.id != value.id);
                                document.integrations.push(value.clone());
                            },
                            |current, previous| current.integrations = previous.integrations.clone(),
                        )
                        .await;
                    saved.err().map(|_| "settingsSaveFailed")
                }
                (_, failure) => Some(failure_key(failure.map_or(NativeIntegrationFailureKind::InvalidRequest, |failure| failure.kind))),
            },
            Err(_) => Some(failure_key(NativeIntegrationFailureKind::Stale)),
        };
        self.update(|page| {
            page.busy = false;
            page.failure = failure;
            if failure.is_none() {
                page.saved += 1;
            }
        });
    }

    pub async fn remove(&self, id: String) {
        let _ = self
            .settings
            .update_durable(
                |document| document.integrations.retain(|tool| tool.id != id),
                |current, previous| current.integrations = previous.integrations.clone(),
            )
            .await;
        self.notifier.notify(Topics::OPERATIONS);
    }
}

/// The page as the presentation shows it.
pub fn page_value(page: &Page, configured: &[NativeIntegrationSettings], repository: bool) -> Value {
    json!({
        "repository": repository,
        "busy": page.busy,
        "failure": page.failure,
        "saved": page.saved,
        "discovered": page.discovered.iter().map(|candidate| json!({
            "id": candidate.id,
            "kind": kind_name(candidate.kind),
        })).collect::<Vec<_>>(),
        "configured": configured.iter().map(|tool| json!({"id": tool.id, "kind": tool.kind})).collect::<Vec<_>>(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn form() -> Form {
        Form {
            id: " lint ".into(),
            kind: "custom".into(),
            executable: "/usr/bin/make".into(),
            arguments: "lint\n\n{file}".into(),
            explicit_shell: false,
            wait: false,
            confirmation: true,
            timeout: "30".into(),
        }
    }

    #[test]
    fn a_complete_form_describes_a_tool() {
        let definition = form_definition(&form(), NativePathPlatform::Unix).unwrap();
        assert_eq!(definition.id, "lint");
        assert_eq!(definition.arguments, ["lint", "{file}"]);
        // Custom commands wait for their result.
        assert_eq!(definition.launch_mode, NativeIntegrationLaunchMode::Wait);
        let stored = stored(&definition);
        assert_eq!(stored.kind, "custom");
        assert!(stored.wait);
    }

    #[test]
    fn an_incomplete_form_describes_nothing() {
        assert!(form_definition(&Form { timeout: "soon".into(), ..form() }, NativePathPlatform::Unix).is_none());
        assert!(form_definition(&Form { id: " ".into(), ..form() }, NativePathPlatform::Unix).is_none());
        assert!(form_definition(&Form { executable: String::new(), ..form() }, NativePathPlatform::Unix).is_none());
    }

    #[test]
    fn failures_name_their_messages() {
        assert_eq!(failure_key(NativeIntegrationFailureKind::Canceled), "operationStateCanceled");
        assert_eq!(failure_key(NativeIntegrationFailureKind::NonZeroExit), "integrationNonZero");
    }
}
