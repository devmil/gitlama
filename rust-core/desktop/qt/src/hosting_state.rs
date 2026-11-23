//! Hosting for the window: the accounts page, the active repository's
//! binding and resources, and the pull requests linked to its branches.

use crate::plumbing::Commands;
use gitlama_contract::hosting::{NativeHostingConnection, NativeHostingCredentialState, NativeHostingResourceKind};
use gitlama_contract::hosting_runtime::NativeHostingOAuthState;
use gitlama_contract::hosting_settings::NativeHostingBindingSettings;
use gitlama_workbench::hosting::{
    Hosting, authentication_name, oauth_failure_name, parse_authentication, parse_preset, preset_name, pull_value,
};
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;

/// The accounts page's projection.
pub fn accounts_value(hosting: &Hosting, credentials: &[(String, NativeHostingCredentialState)]) -> Value {
    let (github, gitlab) = hosting.cli_available();
    let authorization = hosting.authorization().map(|authorization| {
        let snapshot = authorization.snapshot.as_ref();
        json!({
            "connectionId": authorization.connection_id,
            "newConnection": authorization.new_connection,
            "state": snapshot.map(|snapshot| match snapshot.state {
                NativeHostingOAuthState::Queued => "queued",
                NativeHostingOAuthState::WaitingForBrowser => "waitingForBrowser",
                NativeHostingOAuthState::WaitingForDevice => "waitingForDevice",
                NativeHostingOAuthState::Exchanging => "exchanging",
                NativeHostingOAuthState::Succeeded => "succeeded",
                NativeHostingOAuthState::Failed => "failed",
                NativeHostingOAuthState::Canceled => "canceled",
            }),
            "requestId": snapshot.map(|snapshot| snapshot.request_id.to_string()),
            "browserUrl": snapshot.and_then(|snapshot| snapshot.browser_url.clone()),
            "userCode": snapshot.and_then(|snapshot| snapshot.user_code.clone()),
            "failure": snapshot.and_then(|snapshot| snapshot.failure).map(oauth_failure_name),
        })
    });
    json!({
        "expandedNodes": hosting.expanded_nodes(),
        "githubCli": github,
        "gitlabCli": gitlab,
        "authorization": authorization,
        "connections": hosting.connections().iter().map(|connection| json!({
            "id": connection.id,
            "preset": preset_name(connection.preset),
            "login": connection.login,
            "webBaseUrl": connection.web_base_url,
            "authentication": authentication_name(connection.authentication),
            "enabled": connection.enabled,
            "refreshEnabled": connection.refresh_enabled,
            "credential": credentials.iter().find(|(id, _)| id == &connection.id).map(|(_, state)| match state {
                NativeHostingCredentialState::Missing => "missing",
                NativeHostingCredentialState::Available => "available",
                NativeHostingCredentialState::Expired => "expired",
                NativeHostingCredentialState::Unreadable => "unreadable",
            }),
        })).collect::<Vec<_>>(),
    })
}

#[qobject(ConvertToCamelCase)]
mod hosting_state {
    use super::*;

    #[derive(Default)]
    pub struct HostingState {
        pub commands: Option<Commands>,
        /// The accounts page: {connections, authorization, githubCli, gitlabCli}.
        pub(crate) accounts: Value,
        /// The active repository: {binding, changeRequests, issues, busy, …}.
        pub(crate) repository: Value,
        /// Pull requests linked to the repository's branches, authored first.
        pub(crate) linked: Value,
        /// The last failure of an accounts action: an l10n key, a failure
        /// name, or "".
        pub(crate) failure: String,
        pub(crate) hosting: Option<Rc<Hosting>>,
        pub(crate) repository_hosting: Option<Rc<gitlama_workbench::hosting::RepositoryHosting>>,
        /// The accounts revision whose credentials were last read.
        pub(crate) credential_revision: Option<u64>,
    }

    impl HostingState {
        qproperty!("accounts", Member = accounts, Notify = accounts_changed);
        qproperty!("repository", Member = repository, Notify = repository_changed);
        qproperty!("linked", Member = linked, Notify = repository_changed);
        qproperty!("failure", Member = failure, Notify = failure_changed);

        #[qsignal]
        pub fn accounts_changed(&mut self);
        #[qsignal]
        pub fn repository_changed(&mut self);
        #[qsignal]
        pub fn failure_changed(&mut self);

        /// The defaults of preset `preset`, with `web_base` for a
        /// self-hosted one: {webBaseUrl, apiBaseUrl, capabilities,
        /// authentications} or null.
        #[qslot]
        fn preset_defaults(&self, preset: String, web_base: String) -> Value {
            let Some(preset) = parse_preset(&preset) else { return Value::Null };
            let web_base = (!web_base.trim().is_empty()).then(|| web_base.trim().to_owned());
            gitlama_workbench::hosting::preset_defaults_value(preset, web_base)
        }

        /// Adds an account from the form ({id, preset, webBaseUrl,
        /// apiBaseUrl, oauthClientId, authentication, capabilities}) by
        /// signing it in.
        #[qslot]
        fn add_connection(&self, form: Value) {
            let text = |key: &str| form[key].as_str().unwrap_or_default().trim().to_owned();
            let Some(preset) = parse_preset(&text("preset")) else { return };
            let Some(authentication) = parse_authentication(&text("authentication")) else { return };
            let id = text("id");
            let connection = NativeHostingConnection {
                id: id.clone(),
                preset,
                login: String::new(),
                web_base_url: text("webBaseUrl"),
                api_base_url: text("apiBaseUrl"),
                oauth_client_id: text("oauthClientId"),
                authentication,
                enabled: true,
                refresh_enabled: true,
                capabilities: form["capabilities"]
                    .as_array()
                    .map(|names| names.iter().filter_map(Value::as_str).filter_map(gitlama_workbench::hosting::parse_capability).collect())
                    .unwrap_or_default(),
                credential_identity: format!("credential:{id}"),
                allow_split_origin: false,
            };
            self.authorize_connection(connection, true);
        }

        /// Signs account `id` in again.
        #[qslot]
        fn reauthorize(&self, id: String) {
            self.with(move |hosting, state| {
                let Some(connection) = hosting.connection(&id) else { return };
                state.authorize_connection(connection, false);
            });
        }

        /// Stops following a sign-in (a running one is canceled).
        #[qslot]
        fn end_authorization(&self) {
            self.spawn(|hosting, _| async move { hosting.end_authorization().await });
        }

        #[qslot]
        fn remove_connection(&self, id: String) {
            self.spawn_reporting(move |hosting| async move { hosting.remove_connection(&id).await.map_err(str::to_owned) });
        }

        /// Turns account `id` on or off, or its background refresh.
        #[qslot]
        fn toggle_connection(&self, id: String, enabled: bool, refresh_enabled: bool) {
            self.spawn_reporting(move |hosting| async move {
                let Some(mut connection) = hosting.connection(&id) else { return Ok(()) };
                connection.enabled = enabled;
                connection.refresh_enabled = refresh_enabled;
                hosting.save_connection(connection).await.map(|_| ()).map_err(str::to_owned)
            });
        }

        /// Binds the active repository: its remote `remote`, account
        /// `connection_id` and provider repository `provider_repository`.
        #[qslot]
        fn save_binding(&self, remote: String, connection_id: String, provider_repository: String) {
            let Some(commands) = &self.commands else { return };
            let reply = commands.clone();
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(repository) = services.workspace.active_canonical() else { return };
                let hosting = Rc::clone(&services.hosting);
                let binding = NativeHostingBindingSettings {
                    repository,
                    remote: remote.into_bytes(),
                    connection_id,
                    provider_repository: provider_repository.trim().to_owned(),
                };
                rt::spawn_detached(async move {
                    let result = hosting.save_binding(binding).await;
                    reply.post(move |driver| driver.hosting_result(result.err().unwrap_or_default().to_owned()));
                });
            });
        }

        /// Binds the active repository automatically again.
        #[qslot]
        fn clear_binding(&self) {
            let Some(commands) = &self.commands else { return };
            let reply = commands.clone();
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(repository) = services.workspace.active_canonical() else { return };
                let hosting = Rc::clone(&services.hosting);
                rt::spawn_detached(async move {
                    let result = hosting.clear_binding(repository).await;
                    reply.post(move |driver| driver.hosting_result(result.err().unwrap_or_default().to_owned()));
                });
            });
        }

        /// Loads the bound repository's resources again (`page` > 1 adds a page).
        #[qslot]
        fn refresh(&self, manual: bool, page: i32) {
            self.with_repository(move |repository| {
                rt::spawn_detached(async move { repository.refresh(manual, page.max(1) as u32).await });
            });
        }

        /// The web page of the bound repository's `kind` (repository,
        /// changeRequest, createChangeRequest, issue) with `number`, or "".
        #[qslot]
        fn resource_link(&self, kind: String, number: i64) -> String {
            let (Some(hosting), Some(repository)) = (&self.hosting, &self.repository_hosting) else { return String::new() };
            let Some(binding) = repository.binding() else { return String::new() };
            let (Some(connection_id), Some(provider_repository)) = (binding.connection_id, binding.provider_repository) else {
                return String::new();
            };
            let kind = match kind.as_str() {
                "repository" => NativeHostingResourceKind::Repository,
                "changeRequest" => NativeHostingResourceKind::ChangeRequest,
                "createChangeRequest" => NativeHostingResourceKind::CreateChangeRequest,
                "issue" => NativeHostingResourceKind::Issue,
                _ => return String::new(),
            };
            hosting.resource_link(&connection_id, &provider_repository, kind, (number > 0).then_some(number as u64)).unwrap_or_default()
        }

        /// Whether `url` may open in a browser.
        #[qslot]
        fn openable(&self, url: String) -> bool {
            gitlama_workbench::hosting::openable_url(&url)
        }

        /// The pull requests of provider branch `branch` (looked up on
        /// demand): [pull] or null while unknown.
        #[qslot]
        fn pull_requests_for_branch(&self, branch: String) -> Value {
            let Some(repository) = &self.repository_hosting else { return Value::Null };
            repository.request_branches([branch.clone()]);
            repository.pull_requests_for_branch(&branch).map_or(Value::Null, |pulls| Value::Array(pulls.iter().map(pull_value).collect()))
        }

        /// The CI result of commit `head` (looked up on demand), or "".
        #[qslot]
        fn head_checks(&self, head: String) -> String {
            let Some(repository) = &self.repository_hosting else { return String::new() };
            repository.request_head_checks(&head).map(gitlama_workbench::hosting::check_state_name).unwrap_or_default().to_owned()
        }

        /// Looks `branch` up again: its pull request's head is at none of
        /// its refs, whose targets `refs` names.
        #[qslot]
        fn recheck_branch(&self, branch: String, refs: String) {
            if let Some(repository) = &self.repository_hosting {
                repository.recheck_branch(&branch, &refs);
            }
        }

        #[qslot]
        fn set_expanded_nodes(&self, nodes: Value) {
            let nodes: Vec<String> = nodes.as_array().map(|nodes| nodes.iter().filter_map(Value::as_str).map(str::to_owned).collect()).unwrap_or_default();
            if let Some(hosting) = &self.hosting {
                hosting.set_expanded_nodes(nodes);
            }
        }

        #[qslot]
        fn clear_failure(&self) {
            if let Some(commands) = &self.commands {
                commands.post(|driver| driver.hosting_result(String::new()));
            }
        }

        fn authorize_connection(&self, connection: NativeHostingConnection, new_connection: bool) {
            self.spawn_reporting(move |hosting| async move { hosting.authorize(connection, new_connection).await });
        }

        fn with(&self, action: impl FnOnce(Rc<Hosting>, &Self) + 'static) {
            if let Some(hosting) = &self.hosting {
                action(Rc::clone(hosting), self);
            }
        }

        fn with_repository(&self, action: impl FnOnce(Rc<gitlama_workbench::hosting::RepositoryHosting>) + 'static) {
            if let Some(repository) = &self.repository_hosting {
                action(Rc::clone(repository));
            }
        }

        fn spawn<F: std::future::Future<Output = ()> + 'static>(&self, work: impl FnOnce(Rc<Hosting>, ()) -> F + 'static) {
            if let Some(hosting) = &self.hosting {
                rt::spawn_detached(work(Rc::clone(hosting), ()));
            }
        }

        /// Runs `work`; its failure shows on the accounts page.
        fn spawn_reporting<F>(&self, work: impl FnOnce(Rc<Hosting>) -> F + 'static)
        where
            F: std::future::Future<Output = Result<(), String>> + 'static,
        {
            let (Some(hosting), Some(commands)) = (&self.hosting, &self.commands) else { return };
            let hosting = Rc::clone(hosting);
            let reply = commands.clone();
            reply.post(|driver| driver.hosting_result(String::new()));
            rt::spawn_detached(async move {
                let result = work(hosting).await;
                reply.post(move |driver| driver.hosting_result(result.err().unwrap_or_default()));
            });
        }
    }
}

pub use hosting_state::HostingState;
