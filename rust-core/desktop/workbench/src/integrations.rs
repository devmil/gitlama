//! Opens the repository, a file or a folder in an editor, terminal or file
//! manager (the Dart IntegrationLauncher): the configured tool first,
//! otherwise the first one installed, with the arguments each platform's
//! tools need. A tool on this computer never receives a path on another
//! computer.

use crate::backend::SessionCalls;
use crate::history::HistoryService;
use crate::notices::Notices;
use crate::prompts::Prompts;
use crate::settings::SettingsService;
use crate::workspace::WorkspaceService;
use gitlama_contract::dto::{NativePathIdentity, NativePathPlatform};
use gitlama_contract::integrations::{
    NativeIntegrationDefinition, NativeIntegrationExecution, NativeIntegrationExecutionState, NativeIntegrationKind,
    NativeIntegrationLaunchMode, NativeIntegrationPreview, NativeIntegrationRequest, NativeIntegrationSettings,
    NativeIntegrationVariables,
};
use serde_json::{Value, json};
use std::rc::Rc;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Platform {
    MacOs,
    Windows,
    Linux,
}

impl Platform {
    pub fn host() -> Self {
        if cfg!(target_os = "macos") {
            Self::MacOs
        } else if cfg!(target_os = "windows") {
            Self::Windows
        } else {
            Self::Linux
        }
    }
}

pub fn kind_name(kind: NativeIntegrationKind) -> &'static str {
    match kind {
        NativeIntegrationKind::Editor => "editor",
        NativeIntegrationKind::Terminal => "terminal",
        NativeIntegrationKind::FileManager => "fileManager",
        NativeIntegrationKind::Browser => "browser",
        NativeIntegrationKind::DiffTool => "diffTool",
        NativeIntegrationKind::MergeTool => "mergeTool",
        NativeIntegrationKind::Custom => "custom",
    }
}

pub fn parse_kind(name: &str) -> Option<NativeIntegrationKind> {
    Some(match name {
        "editor" => NativeIntegrationKind::Editor,
        "terminal" => NativeIntegrationKind::Terminal,
        "fileManager" => NativeIntegrationKind::FileManager,
        "browser" => NativeIntegrationKind::Browser,
        "diffTool" => NativeIntegrationKind::DiffTool,
        "mergeTool" => NativeIntegrationKind::MergeTool,
        "custom" => NativeIntegrationKind::Custom,
        _ => return None,
    })
}

/// A stored tool as a definition the core runs.
pub fn definition(settings: &NativeIntegrationSettings) -> Option<NativeIntegrationDefinition> {
    Some(NativeIntegrationDefinition {
        id: settings.id.clone(),
        kind: parse_kind(&settings.kind)?,
        executable: settings.executable.clone(),
        arguments: settings.arguments.clone(),
        execution: if settings.explicit_shell { NativeIntegrationExecution::ExplicitShell } else { NativeIntegrationExecution::Direct },
        launch_mode: if settings.wait { NativeIntegrationLaunchMode::Wait } else { NativeIntegrationLaunchMode::Detached },
        requires_confirmation: settings.requires_confirmation,
        timeout_seconds: settings.timeout_seconds,
    })
}

/// The arguments that make a discovered tool of `kind` open (an editor) or
/// reveal (a file manager) `{file}` on `platform`.
pub fn file_arguments(kind: NativeIntegrationKind, candidate: &str, platform: Platform) -> Vec<String> {
    let arguments: &[&str] = match (kind, platform) {
        (NativeIntegrationKind::Editor, Platform::MacOs) => &["-t", "{file}"],
        (NativeIntegrationKind::FileManager, Platform::MacOs) => &["-R", "{file}"],
        (NativeIntegrationKind::FileManager, Platform::Windows) => &["/select,{file}"],
        (NativeIntegrationKind::FileManager, Platform::Linux) if selects_file(candidate, platform) => &["--select", "{file}"],
        _ => &["{file}"],
    };
    arguments.iter().map(|argument| (*argument).to_owned()).collect()
}

/// Whether a discovered file manager can select a file in its folder; the
/// others are given the folder instead.
pub fn selects_file(candidate: &str, platform: Platform) -> bool {
    platform != Platform::Linux || candidate.contains("dolphin") || candidate.contains("nautilus")
}

/// The arguments that open a folder itself.
pub fn folder_arguments(candidate: &str) -> Vec<String> {
    if candidate.ends_with("-gio") { vec!["open".into(), "{file}".into()] } else { vec!["{file}".into()] }
}

/// The file manager's name for "Open in …" (the Dart
/// configuredFileBrowserName / platformFileBrowserName).
pub fn file_browser_name(configured: Option<&NativeIntegrationSettings>, platform: Platform) -> String {
    let known = |id: &str| -> Option<&'static str> {
        [("dolphin", "Dolphin"), ("nautilus", "Files"), ("nemo", "Nemo"), ("thunar", "Thunar"), ("pcmanfm", "PCManFM")]
            .into_iter()
            .find(|(needle, _)| id.contains(needle))
            .map(|(_, name)| name)
    };
    if let Some(configured) = configured {
        let executable = String::from_utf16_lossy(&configured.executable.units).to_lowercase();
        return known(&executable).map_or_else(|| configured.id.clone(), str::to_owned);
    }
    match platform {
        Platform::MacOs => "Finder",
        Platform::Windows => "Explorer",
        Platform::Linux => "Files",
    }
    .to_owned()
}

fn separator(unit: u16) -> bool {
    unit == u16::from(b'/') || unit == u16::from(b'\\')
}

/// The folder that contains `path`; `path` itself at the top.
pub fn parent(path: &NativePathIdentity) -> NativePathIdentity {
    match path.units.iter().rposition(|unit| separator(*unit)) {
        Some(index) => NativePathIdentity { units: path.units[..index].to_vec(), ..path.clone() },
        None => path.clone(),
    }
}

fn absolute(path: &NativePathIdentity) -> bool {
    path.units.first() == Some(&u16::from(b'/'))
}

/// The repository-relative `relative` (UTF-8 with `/`) inside `root`.
pub fn repository_file(root: &NativePathIdentity, relative: &str) -> NativePathIdentity {
    let windows = root.platform == NativePathPlatform::Windows;
    let units: Vec<u16> = if windows {
        relative.replace('/', "\\").encode_utf16().collect()
    } else {
        relative.bytes().map(u16::from).collect()
    };
    let separator = if windows { u16::from(b'\\') } else { u16::from(b'/') };
    let mut joined = root.units.clone();
    if !units.is_empty() {
        if joined.last().is_some_and(|last| *last != separator) {
            joined.push(separator);
        }
        joined.extend(units);
    }
    NativePathIdentity { platform: root.platform, units: joined, remote: root.remote.clone() }
}

/// A file or folder a tool opens: repository-relative, or absolute (a file
/// this computer wrote, another tab's folder).
#[derive(Clone, Debug)]
pub enum Target {
    Relative(String),
    Absolute(NativePathIdentity),
}

pub struct Integrations {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    history: Rc<HistoryService>,
    settings: Rc<SettingsService>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    platform: Platform,
}

impl Integrations {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        history: Rc<HistoryService>,
        settings: Rc<SettingsService>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
    ) -> Rc<Self> {
        Rc::new(Self { calls, workspace, history, settings, prompts, notices, platform: Platform::host() })
    }

    fn configured(&self, kind: NativeIntegrationKind) -> Option<NativeIntegrationDefinition> {
        self.settings.with(|document| {
            document.integrations.iter().filter_map(definition).find(|definition| definition.kind == kind)
        })
    }

    /// The name of the file manager "Open in …" opens.
    pub fn file_browser(&self) -> String {
        self.settings.with(|document| {
            file_browser_name(document.integrations.iter().find(|tool| tool.kind == "fileManager"), self.platform)
        })
    }

    fn remote(&self) -> bool {
        self.workspace.active_canonical().is_some_and(|root| root.remote.is_some())
    }

    fn resolve(&self, target: Option<&Target>) -> Option<NativePathIdentity> {
        let root = self.workspace.active_canonical()?;
        Some(match target {
            None => root,
            Some(Target::Absolute(path)) => path.clone(),
            Some(Target::Relative(path)) => repository_file(&root, path),
        })
    }

    fn variables(&self, file: Option<NativePathIdentity>) -> NativeIntegrationVariables {
        let status = self.workspace.current().and_then(|session| session.snapshot.status.clone());
        NativeIntegrationVariables {
            file,
            current_branch: status.as_ref().and_then(|status| status.branch_name.clone()),
            selected_commit: self
                .history
                .current()
                .target_object_id
                .or_else(|| status.as_ref().and_then(|status| status.head_object_id.clone())),
            ..NativeIntegrationVariables::default()
        }
    }

    /// Runs a configured tool on the repository or `target`.
    pub async fn run_configured(&self, definition: NativeIntegrationDefinition, target: Option<Target>) {
        let file = self.resolve(target.as_ref());
        self.launch(NativeIntegrationRequest {
            kind: definition.kind,
            discovered_id: None,
            configured: Some(definition),
            variables: self.variables(file),
        })
        .await;
    }

    /// Runs the stored tool `id` on the repository.
    pub async fn run_stored(&self, id: &str) {
        let Some(definition) = self.settings.with(|document| {
            document.integrations.iter().find(|tool| tool.id == id).and_then(definition)
        }) else {
            return self.notices.status("integrationUnavailable", Value::Null);
        };
        self.run_configured(definition, None).await;
    }

    /// Opens the repository, or `target` in it, with a tool of `kind`.
    pub async fn open(&self, kind: NativeIntegrationKind, target: Option<Target>) {
        // A file this computer wrote opens locally even while the active
        // repository lives on another computer.
        let local_file = matches!(&target, Some(Target::Absolute(path)) if path.remote.is_none() && absolute(path));
        if !local_file && self.remote() {
            return self.notices.status("remoteCommandUnsupported", Value::Null);
        }
        if let Some(configured) = self.configured(kind) {
            return self.run_configured(configured, target).await;
        }
        let candidate = match self.calls.integration_discover(kind).await {
            Ok(result) => result.candidates.into_iter().next(),
            Err(_) => return self.notices.error("integrationLaunchFailed", Value::Null),
        };
        let Some(candidate) = candidate else { return self.notices.status("integrationUnavailable", Value::Null) };
        let file = self.resolve(target.as_ref());
        let opens_file = matches!(kind, NativeIntegrationKind::Editor | NativeIntegrationKind::FileManager) && target.is_some();
        let file = match file {
            Some(file) if target.is_some() && kind == NativeIntegrationKind::FileManager && !selects_file(&candidate.id, self.platform) => {
                Some(parent(&file))
            }
            other => other,
        };
        self.launch(NativeIntegrationRequest {
            kind,
            discovered_id: (!opens_file).then(|| candidate.id.clone()),
            configured: opens_file.then(|| NativeIntegrationDefinition {
                id: candidate.id.clone(),
                kind,
                executable: candidate.executable.clone(),
                arguments: file_arguments(kind, &candidate.id, self.platform),
                execution: NativeIntegrationExecution::Direct,
                launch_mode: candidate.launch_mode,
                requires_confirmation: false,
                timeout_seconds: 0,
            }),
            variables: self.variables(file),
        })
        .await;
    }

    /// Opens `folder` itself (a repository or worktree root) in the file
    /// manager.
    pub async fn open_folder(&self, folder: NativePathIdentity) {
        if folder.remote.is_some() {
            return self.notices.status("remoteCommandUnsupported", Value::Null);
        }
        if let Some(configured) = self.configured(NativeIntegrationKind::FileManager) {
            return self.run_configured(configured, Some(Target::Absolute(folder))).await;
        }
        let candidate = match self.calls.integration_discover(NativeIntegrationKind::FileManager).await {
            Ok(result) => result.candidates.into_iter().next(),
            Err(_) => return self.notices.error("integrationLaunchFailed", Value::Null),
        };
        let Some(candidate) = candidate else { return self.notices.status("integrationUnavailable", Value::Null) };
        self.launch(NativeIntegrationRequest {
            kind: NativeIntegrationKind::FileManager,
            discovered_id: None,
            configured: Some(NativeIntegrationDefinition {
                id: candidate.id.clone(),
                kind: NativeIntegrationKind::FileManager,
                executable: candidate.executable,
                arguments: folder_arguments(&candidate.id),
                execution: NativeIntegrationExecution::Direct,
                launch_mode: candidate.launch_mode,
                requires_confirmation: false,
                timeout_seconds: 0,
            }),
            variables: self.variables(Some(folder)),
        })
        .await;
    }

    async fn launch(&self, request: NativeIntegrationRequest) {
        let Some(session) = self.workspace.current() else { return };
        if request.variables.file.is_none() {
            return;
        }
        let variables = &request.variables;
        if [
            &variables.file,
            &variables.diff_left,
            &variables.diff_right,
            &variables.merge_base,
            &variables.merge_current,
            &variables.merge_incoming,
            &variables.merge_result,
        ]
        .into_iter()
        .any(|path| path.as_ref().is_some_and(|path| path.remote.is_some()))
        {
            return self.notices.status("remoteCommandUnsupported", Value::Null);
        }
        let identity = session.identity;
        let preview = match self.calls.repository_session_integration_preview(identity.native_id, identity.generation, request).await {
            Ok(result) => result.preview,
            Err(_) => None,
        };
        let Some(preview) = preview else { return self.notices.error("integrationLaunchFailed", Value::Null) };
        self.confirm_and_run(identity.native_id, identity.generation, preview, "integrationRunSummary", false).await;
    }

    /// Asks to run `preview` when it needs confirmation (described by
    /// `summary`, an l10n key), then runs it; `completed_only` reports a
    /// tool that detached as a failure too.
    pub async fn confirm_and_run(
        &self,
        session: u64,
        generation: u64,
        preview: NativeIntegrationPreview,
        summary: &str,
        completed_only: bool,
    ) {
        if preview.requires_confirmation {
            let commands: Vec<String> = std::iter::once(preview.executable.clone()).chain(preview.arguments.iter().cloned()).collect();
            let answer = self.prompts.ask("confirmIntegration", json!({"commands": commands, "summary": summary})).await;
            if answer != Some(Value::Bool(true)) {
                let _ = self.calls.repository_session_integration_cancel(session, generation, preview.token).await;
                return;
            }
        }
        match self.calls.repository_session_integration_execute(session, generation, preview.token, true).await {
            Ok(result)
                if result.state == NativeIntegrationExecutionState::Completed
                    || (!completed_only && result.state == NativeIntegrationExecutionState::Detached) => {}
            _ => self.notices.error("integrationLaunchFailed", Value::Null),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unix(path: &str) -> NativePathIdentity {
        NativePathIdentity { platform: NativePathPlatform::Unix, units: path.bytes().map(u16::from).collect(), remote: None }
    }

    #[test]
    fn discovered_tools_get_each_platforms_arguments() {
        use NativeIntegrationKind::{Editor, FileManager};
        assert_eq!(file_arguments(Editor, "code", Platform::MacOs), ["-t", "{file}"]);
        assert_eq!(file_arguments(Editor, "code", Platform::Linux), ["{file}"]);
        assert_eq!(file_arguments(FileManager, "finder", Platform::MacOs), ["-R", "{file}"]);
        assert_eq!(file_arguments(FileManager, "explorer", Platform::Windows), ["/select,{file}"]);
        assert_eq!(file_arguments(FileManager, "linux-nautilus", Platform::Linux), ["--select", "{file}"]);
        assert_eq!(file_arguments(FileManager, "linux-thunar", Platform::Linux), ["{file}"]);
        assert!(!selects_file("linux-xdg-open", Platform::Linux));
        assert_eq!(folder_arguments("linux-gio"), ["open", "{file}"]);
        assert_eq!(folder_arguments("linux-xdg-open"), ["{file}"]);
    }

    #[test]
    fn paths_join_the_repository_root_and_find_their_folder() {
        assert_eq!(repository_file(&unix("/repo"), "lib/a.rs"), unix("/repo/lib/a.rs"));
        assert_eq!(repository_file(&unix("/repo/"), "a"), unix("/repo/a"));
        assert_eq!(parent(&unix("/repo/lib/a.rs")), unix("/repo/lib"));
        assert_eq!(parent(&unix("a")), unix("a"));
    }

    #[test]
    fn the_file_browser_is_named_after_the_configured_tool() {
        let tool = NativeIntegrationSettings {
            id: "mine".into(),
            kind: "fileManager".into(),
            executable: unix("/usr/bin/dolphin"),
            arguments: vec![],
            explicit_shell: false,
            wait: false,
            requires_confirmation: false,
            timeout_seconds: 0,
        };
        assert_eq!(file_browser_name(Some(&tool), Platform::Linux), "Dolphin");
        let other = NativeIntegrationSettings { executable: unix("/opt/fm"), ..tool };
        assert_eq!(file_browser_name(Some(&other), Platform::Linux), "mine");
        assert_eq!(file_browser_name(None, Platform::MacOs), "Finder");
        assert_eq!(file_browser_name(None, Platform::Linux), "Files");
    }
}
