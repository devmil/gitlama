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
use crate::changes_state::ChangesState;
use crate::commit_state::CommitState;
use crate::settings_state::SettingsState;
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
    pub inspector_blame: Rc<RefCell<crate::blame_model::BlameModel>>,
    pub changes: Rc<RefCell<ChangesState>>,
    pub unstaged_rows: Rc<RefCell<RowModel>>,
    pub staged_rows: Rc<RefCell<RowModel>>,
    pub working_diff: Rc<RefCell<DiffModel>>,
    pub commit: Rc<RefCell<CommitState>>,
    pub settings: Rc<RefCell<SettingsState>>,
    pub workflows: Rc<RefCell<crate::workflows_state::WorkflowsState>>,
    pub conflicts: Rc<RefCell<crate::conflicts_state::ConflictsState>>,
    pub conflict_rows: Rc<RefCell<RowModel>>,
    pub operations: Rc<RefCell<crate::operations_state::OperationsState>>,
    pub patches: Rc<RefCell<crate::patch_state::PatchState>>,
    pub hosting: Rc<RefCell<crate::hosting_state::HostingState>>,
    pub line_selection: Rc<RefCell<crate::line_selection_state::LineSelectionState>>,
    pub line_rows: Rc<RefCell<RowModel>>,
    /// The history reference scope last seen in the settings; a change
    /// reloads the shown history.
    pub history_other_refs: std::cell::Cell<Option<bool>>,
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
            if let Some(services) = self.app.services() {
                let mut inspector = self.inspector.borrow_mut();
                if inspector.actions.is_none() {
                    inspector.actions = Some(Rc::clone(&services.inspector_actions));
                }
            }
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
            let activation = self.app.services().map_or(0, |services| services.cli.activations() as i64);
            if state.activation != activation {
                state.activation = activation;
                state.activation_changed();
            }
        }
        if changed.intersects(Topics::HOSTING | Topics::SETTINGS | Topics::WORKSPACE | Topics::SESSION | Topics::STARTUP) {
            self.project_hosting();
        }
        if changed.intersects(Topics::EVENTS) {
            self.emit_events();
        }
        if changed.intersects(Topics::WORKSPACE | Topics::SESSION | Topics::SETTINGS | Topics::OPERATIONS) {
            self.project_workspace(changed);
        }
        if changed.intersects(Topics::HISTORY | Topics::WORKSPACE | Topics::SESSION | Topics::HOSTING) {
            self.project_history();
        }
        if changed.intersects(Topics::INSPECTOR) {
            self.project_inspector();
        }
        if changed.intersects(Topics::CHANGES | Topics::SESSION | Topics::WORKSPACE | Topics::DIFF | Topics::OPERATIONS | Topics::SETTINGS) {
            self.project_changes();
        }
        if changed.intersects(Topics::OPERATIONS)
            && let Some(services) = self.app.services()
        {
            let progress = services.archives.progress();
            let value = serde_json::json!({
                "running": progress.running,
                "started": progress.started,
                "files": progress.files,
                "total": progress.total,
                "writing": progress.writing,
            });
            let snapshots = gitlama_workbench::snapshots::panel_value(&services.snapshots.panel());
            let mut workflows = self.workflows.borrow_mut();
            if workflows.archive != value {
                workflows.archive = value;
                workflows.archive_changed();
            }
            if workflows.snapshots != snapshots {
                workflows.snapshots = snapshots;
                workflows.snapshots_changed();
            }
            let extensions = gitlama_workbench::extensions::panel_value(&services.extensions.panel());
            if workflows.extensions != extensions {
                workflows.extensions = extensions;
                workflows.extensions_changed();
            }
            let power_tools = gitlama_workbench::power_tools::panel_value(&services.power_tools.panel());
            if workflows.power_tools != power_tools {
                workflows.power_tools = power_tools;
                workflows.power_tools_changed();
            }
        }
        if changed.intersects(Topics::OPERATIONS | Topics::WORKSPACE)
            && let Some(services) = self.app.services()
        {
            let snapshot = services.operations.current();
            let center = crate::operations_state::project(&snapshot, &services, |session, generation| {
                services.workspace.with_tabs(|tabs, _, _| {
                    tabs.iter()
                        .find(|tab| tab.session.as_ref().is_some_and(|open| open.identity.native_id == session && open.identity.generation == generation))
                        .map(|tab| tab.label.clone())
                })
            });
            let mut operations = self.operations.borrow_mut();
            if operations.center != center {
                operations.center = center;
                operations.center_changed();
            }
        }
        if changed.intersects(Topics::CONFLICTS | Topics::WORKSPACE | Topics::SESSION | Topics::SETTINGS)
            && let Some(services) = self.app.services()
            && let Some((mut state, text, revision, rows)) = services.conflicts.with_active(|session| crate::conflicts_state::project(session))
        {
            // The configured merge tools, for the external merge action.
            state["mergeTools"] = services.settings.with(|document| {
                serde_json::Value::Array(
                    document
                        .integrations
                        .iter()
                        .filter(|tool| tool.kind == "mergeTool")
                        .map(|tool| serde_json::Value::String(tool.id.clone()))
                        .collect(),
                )
            });
            self.conflict_rows.borrow_mut().publish(rows);
            let mut conflicts = self.conflicts.borrow_mut();
            if conflicts.result_text != text || conflicts.text_revision != revision as i64 {
                conflicts.result_text = text;
                conflicts.text_revision = revision as i64;
                conflicts.result_changed();
            }
            if conflicts.state != state {
                conflicts.state = state;
                conflicts.state_changed();
            }
        }
        if changed.intersects(Topics::OPERATIONS | Topics::WORKSPACE)
            && let Some(services) = self.app.services()
        {
            let busy = services
                .busy
                .blocking_of(services.workspace.active_tab_id())
                .map_or(Value::Null, |operation| {
                    let (key, args) = operation.activity.label();
                    serde_json::json!({
                        "key": key,
                        "args": args,
                        "cancellable": operation.cancel.is_some(),
                        "canceling": operation.canceling.get(),
                    })
                });
            let mut workflows = self.workflows.borrow_mut();
            if workflows.busy != busy {
                workflows.busy = busy;
                workflows.busy_changed();
            }
        }
        if changed.intersects(Topics::SETTINGS | Topics::UPDATES)
            && let Some(services) = self.app.services()
        {
            let updates = services.updates.value();
            let mut settings = self.settings.borrow_mut();
            if settings.updates != updates {
                settings.updates = updates;
                settings.updates_changed();
            }
        }
        if changed.intersects(Topics::SETTINGS | Topics::WORKSPACE | Topics::OPERATIONS | Topics::SESSION | Topics::INSPECTOR)
            && let Some(services) = self.app.services()
        {
            let renderer = services.diff_renderers.value();
            if self.settings.borrow().renderer != renderer {
                let mut settings = self.settings.borrow_mut();
                settings.renderer = renderer;
                settings.renderer_changed();
            }
            let tools = gitlama_workbench::tools::page_value(
                &services.tools.page(),
                &services.tools.configured(),
                services.workspace.current().is_some(),
            );
            if changed.intersects(Topics::SESSION | Topics::WORKSPACE) {
                services.acceleration.check_offer();
            }
            let acceleration = services.acceleration.value();
            let mut settings = self.settings.borrow_mut();
            if settings.tools != tools {
                settings.tools = tools;
                settings.tools_changed();
            }
            if settings.acceleration != acceleration {
                settings.acceleration = acceleration;
                settings.acceleration_changed();
            }
        }
        if changed.intersects(Topics::SETTINGS)
            && let Some(services) = self.app.services()
        {
            let other_refs = services.settings.with(|document| document.appearance.history_other_refs);
            if self.history_other_refs.replace(Some(other_refs)).is_some_and(|previous| previous != other_refs) {
                services.workspace.reload_shown_history();
            }
        }
        if changed.intersects(Topics::SETTINGS | Topics::WORKSPACE | Topics::SESSION)
            && let Some(services) = self.app.services()
        {
            services.auto_fetch.sync();
            let options = services
                .settings
                .with(|document| gitlama_workbench::inspector::DiffOptions::of(&document.appearance));
            // Context widened by Show more context lasts until the stored
            // preferences change.
            if changed.intersects(Topics::SETTINGS) && services.working_detail.options() != options {
                services.working_detail.set_options(options, services.working_detail.force_text());
            }
            if changed.intersects(Topics::SETTINGS) && services.inspector.diff_options() != options {
                let inspector = Rc::clone(&services.inspector);
                gitlama_workbench::rt::spawn_detached(async move { inspector.update_diff_options(options).await });
            }
            let page = crate::settings_state::project(&services);
            let mut settings = self.settings.borrow_mut();
            if settings.page != page {
                settings.page = page;
                settings.page_changed();
            }
        }
        if changed.intersects(Topics::SETTINGS) {
            if let Some(services) = self.app.services() {
                let name = services.integrations.file_browser();
                let mut workflows = self.workflows.borrow_mut();
                if workflows.file_browser != name {
                    workflows.file_browser = name;
                    workflows.file_browser_changed();
                }
            }
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

/// Shows the outcome of a settings write: `key` is why it was refused, ""
/// when it succeeded.
pub fn show_settings_result(state: &Rc<RefCell<SettingsState>>, key: &str) {
    let mut settings = state.borrow_mut();
    if settings.failure != key {
        settings.failure = key.to_owned();
        settings.failure_changed();
    }
}

impl Driver {
    /// Publishes "Select changed lines": its state and its rows.
    pub(crate) fn publish_line_selection(&self) {
        let (state, rows) = {
            let selection = self.line_selection.borrow();
            let rows: Vec<Value> =
                selection.rows.iter().map(|row| crate::line_selection_state::row_value(row, &selection.selection)).collect();
            (selection.project(), rows)
        };
        {
            let mut selection = self.line_selection.borrow_mut();
            if selection.state != state {
                selection.state = state;
                selection.state_changed();
            }
        }
        self.line_rows.borrow_mut().publish(rows);
    }

    pub(crate) fn settings_result(&self, key: &str) {
        show_settings_result(&self.settings, key);
    }

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

    /// The mark editor's image: its path and, once read, its preview.
    pub(crate) fn project_appearance_edit(&self) {
        let Some(services) = self.app.services() else { return };
        let mut state = self.workspace.borrow_mut();
        if state.appearance_edit.is_null() {
            return;
        }
        let image = state.appearance_image.clone();
        let url = image.as_ref().and_then(|path| services.appearances.image_at(path));
        let failed = image.as_ref().is_some_and(|path| services.appearances.image_failed(path));
        let mut next = state.appearance_edit.clone();
        next["image"] = image.as_ref().map_or(Value::Null, |path| Value::from(gitlama_workbench::session::display_path(path)));
        next["imageUrl"] = url.map_or(Value::Null, |url| Value::from(url.as_ref()));
        next["imageFailed"] = Value::from(failed);
        if next != state.appearance_edit {
            state.appearance_edit = next;
            state.appearance_edit_changed();
        }
    }

    fn project_workspace(&self, changed: Topics) {
        let Some(services) = self.app.services() else { return };
        if changed.intersects(Topics::WORKSPACE) {
            self.project_appearance_edit();
        }
        if changed.intersects(Topics::WORKSPACE | Topics::SESSION | Topics::OPERATIONS | Topics::SETTINGS) {
            let details = crate::workspace_state::details(&services);
            let mut workspace = self.workspace.borrow_mut();
            if workspace.details != details {
                workspace.details = details;
                workspace.details_changed();
            }
        }
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
            let mut entry = projection::entry(services.entry.current());
            entry["clone"] = services.entry.clones.current().map_or(Value::Null, |clone| {
                serde_json::json!({
                    "running": clone.state == gitlama_contract::clone::NativeCloneState::Running,
                    "progress": gitlama_workbench::clone::progress(&clone),
                })
            });
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
                    self.history.borrow_mut().snapshot = Some(Rc::clone(&session.snapshot));
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
            // Pull requests learned for the branch chips refresh the rows too.
            history.revision().wrapping_add(services.repository_hosting.revision() << 32),
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
            HistorySource { history: Some(Rc::clone(history)), context, head, hosting: Some(Rc::clone(&services.repository_hosting)) },
            total,
        );
    }

    /// The accounts page, the active repository's hosting and its linked
    /// pull requests; follows the active repository and its remotes.
    fn project_hosting(&self) {
        let Some(services) = self.app.services() else { return };
        {
            let mut state = self.hosting.borrow_mut();
            if state.hosting.is_none() {
                state.hosting = Some(Rc::clone(&services.hosting));
                state.repository_hosting = Some(Rc::clone(&services.repository_hosting));
            }
            let revision = services.hosting.revision();
            if state.credential_revision != Some(revision) {
                state.credential_revision = Some(revision);
                services.hosting.read_credentials();
            }
        }
        let remotes: Vec<gitlama_contract::hosting::NativeHostingRemote> = services
            .workspace
            .current()
            .map(|session| {
                session
                    .snapshot
                    .refs
                    .remotes
                    .iter()
                    .map(|remote| gitlama_contract::hosting::NativeHostingRemote {
                        name: remote.name.clone(),
                        url: String::from_utf8_lossy(&remote.display_url).into_owned(),
                    })
                    .collect()
            })
            .unwrap_or_default();
        services.repository_hosting.update(services.workspace.active_canonical(), remotes);
        self.publish_pull_request_rows(&services);
        let accounts = crate::hosting_state::accounts_value(&services.hosting, &services.hosting.credentials());
        let repository = services.repository_hosting.state_value();
        let linked = serde_json::Value::Array(
            services
                .repository_hosting
                .linked_pull_requests()
                .iter()
                .map(|linked| {
                    let mut value = gitlama_workbench::hosting::pull_value(&linked.pull);
                    value["authored"] = serde_json::Value::Bool(linked.authored);
                    value["viaBranch"] = serde_json::Value::Bool(linked.via_branch);
                    value
                })
                .collect(),
        );
        let mut state = self.hosting.borrow_mut();
        if state.accounts != accounts {
            state.accounts = accounts;
            state.accounts_changed();
        }
        if state.repository != repository || state.linked != linked {
            state.repository = repository;
            state.linked = linked;
            state.repository_changed();
        }
    }

    /// The sidebar's pull request rows (the Dart _pullRequestEntries): the
    /// account's own first, then the open and the merged ones of branches
    /// this repository still has.
    fn publish_pull_request_rows(&self, services: &gitlama_workbench::app::Services) {
        use gitlama_contract::hosting::NativeHostingChangeRequestState as State;
        use gitlama_workbench::sidebar::{Entry, PullRequestRow};
        let session = services.workspace.current();
        let binding = services.repository_hosting.binding();
        let remote = binding.as_ref().map(|binding| binding.remote.clone()).unwrap_or_default();
        let (branches, local_heads): (std::collections::HashSet<String>, std::collections::HashMap<String, String>) = session
            .as_ref()
            .map(|session| {
                let refs = &session.snapshot.refs;
                let mut names: std::collections::HashSet<String> =
                    refs.branches.iter().map(|branch| String::from_utf8_lossy(&branch.name).into_owned()).collect();
                for remote_refs in refs.remotes.iter().filter(|candidate| candidate.name == remote) {
                    names.extend(remote_refs.branches.iter().map(|branch| String::from_utf8_lossy(&branch.name).into_owned()));
                }
                let heads = refs.branches.iter().map(|branch| (String::from_utf8_lossy(&branch.name).into_owned(), branch.target.clone())).collect();
                (names, heads)
            })
            .unwrap_or_default();
        let entries: Vec<Entry> = services
            .repository_hosting
            .linked_pull_requests()
            .into_iter()
            .filter(|linked| !linked.via_branch || branches.contains(&linked.pull.source_branch))
            .map(|linked| {
                let pull = &linked.pull;
                let merged = pull.state == State::Merged;
                Entry {
                    name: format!("#{} {}", pull.number, pull.title),
                    tree_path: Some(format!("pull-request:{}", pull.number)),
                    command_name: Some(pull.web_url.clone()),
                    subtitle: if merged {
                        "@hostingPullRequestMerged".to_owned()
                    } else if linked.authored {
                        "@hostingPullRequestYours".to_owned()
                    } else {
                        pull.source_branch.clone()
                    },
                    icon: Some(if merged { "git-merge" } else if linked.authored { "user" } else { "git-pull-request" }),
                    target: local_heads.get(&pull.source_branch).cloned(),
                    pull_request: Some(PullRequestRow {
                        web_url: pull.web_url.clone(),
                        checks: (pull.checks.state != gitlama_contract::hosting::NativeHostingCheckState::Unknown)
                            .then(|| gitlama_workbench::hosting::check_state_name(pull.checks.state)),
                        conflicting: pull.mergeability == gitlama_contract::hosting::NativeHostingMergeability::Conflicting,
                        branches: (pull.source_branch.clone(), pull.target_branch.clone()),
                        checkout: (pull.state == State::Open && !pull.source_branch.is_empty() && !pull.head_sha.is_empty())
                            .then(|| (pull.source_branch.clone(), pull.head_sha.clone())),
                    }),
                    ..Entry::default()
                }
            })
            .collect();
        services.sidebar.set_pull_requests(entries);
    }

    /// Shows the outcome of a hosting accounts action ("" when it succeeded).
    pub(crate) fn hosting_result(&self, failure: String) {
        let mut state = self.hosting.borrow_mut();
        if state.failure != failure {
            state.failure = failure;
            state.failure_changed();
        }
    }

    pub(crate) fn project_inspector(&self) {
        let Some(services) = self.app.services() else { return };
        let tree = services.settings.with(|document| document.appearance.commit_files_mode == "tree");
        let collapsed = {
            let inspector = self.inspector.borrow();
            let mut folded = inspector.collapsed.borrow_mut();
            // Another commit starts with every folder open.
            let commit = services.inspector.current().location.map(|location| location.target.commit().to_owned()).unwrap_or_default();
            if folded.0 != commit {
                *folded = (commit, Default::default());
            }
            folded.1.clone()
        };
        let state = crate::inspector_state::project(&services.inspector, tree, &collapsed);
        {
            let mut inspector = self.inspector.borrow_mut();
            if inspector.state != state {
                inspector.state = state;
                inspector.state_changed();
            }
        }
        let diff = services.inspector.current().diff;
        self.inspector_diff.borrow_mut().publish(diff);
        self.inspector_blame.borrow_mut().publish(services.inspector.current().blame);
    }

    pub(crate) fn project_changes(&self) {
        let Some(services) = self.app.services() else { return };
        services.changes.sync();
        services.working_detail.follow();
        let filter = self.changes.borrow().filter.borrow().clone();
        let collapsed = self.changes.borrow().collapsed.borrow().clone();
        let projection = crate::changes_state::project(&services, &filter, &collapsed);
        self.unstaged_rows.borrow_mut().publish(projection.unstaged);
        self.staged_rows.borrow_mut().publish(projection.staged);
        self.working_diff.borrow_mut().publish(services.working_detail.document());
        // The editor shows the active worktree's draft when the tab changes.
        let tab = services.workspace.active_tab();
        let tab_id = tab.as_ref().map_or(-1, |tab| tab.id as i64);
        if self.commit.borrow().draft["tabId"].as_i64() != Some(tab_id) {
            let draft = services.commit.draft(tab.as_ref().and_then(|tab| tab.canonical_identity()));
            let mut commit = self.commit.borrow_mut();
            commit.draft = serde_json::json!({"tabId": tab_id, "subject": draft.subject, "description": draft.description});
            commit.draft_changed();
        }
        let effects = services.changes.take_effects();
        let mut changes = self.changes.borrow_mut();
        if changes.state != projection.state {
            changes.state = projection.state;
            changes.state_changed();
        }
        for effect in effects {
            use gitlama_workbench::changes::{ChangesEffect, side_name};
            let (kind, payload) = match effect {
                ChangesEffect::MoveStarted { tab, side, keys, single } => {
                    ("moveStarted", serde_json::json!({"tab": tab, "side": side_name(side), "keys": keys, "single": single}))
                }
                ChangesEffect::MoveEnded { tab, moved } => ("moveEnded", serde_json::json!({"tab": tab, "moved": moved})),
                ChangesEffect::ActionFailed { tab, side } => ("actionFailed", serde_json::json!({"tab": tab, "side": side_name(side)})),
                ChangesEffect::DiffSelectionRequested { tab, discard } => {
                    ("diffSelectionRequested", serde_json::json!({"tab": tab, "discard": discard}))
                }
            };
            changes.effect(kind.to_owned(), payload.to_string());
        }
    }
}
