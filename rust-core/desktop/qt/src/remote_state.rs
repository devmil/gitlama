//! Remote workspaces for QML: host profiles with their connection and reconnection states,
//! the record of remote writes, and the commands of the hosts dialog, the folder picker, the
//! status bar host menu and the tab banners.

use crate::plumbing::Commands;
use gitlama_workbench::app::Services;
use gitlama_workbench::remote::RemoteCapability;
use gitlama_workbench::remote::model::{DirectoryPage, EntryKind, Failure, display_path};
use gitlama_workbench::remote::reconnect::ReconnectPhase;
use gitlama_workbench::remote::service::ProfileError;
use gitlama_workbench::remote::workflows::failure_message;
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;
use std::time::Instant;

fn failure_value(code: Option<Failure>, alias: &str) -> Value {
    code.map_or(Value::Null, |code| {
        let (key, args) = failure_message(code, Some(alias));
        json!({ "code": code.name(), "key": key, "args": args })
    })
}

/// The hosts, the record of remote writes and the helper this build needs.
pub fn project(services: &Services) -> (Value, Value, Value) {
    let service = &services.remote;
    let workflows = &services.remote_workflows;
    let reconnector = service.reconnector();
    let hosts: Vec<Value> = service
        .profiles()
        .iter()
        .map(|profile| {
            let state = service.state(&profile.id);
            let reconnect = reconnector
                .as_ref()
                .and_then(|reconnector| reconnector.state_of(&profile.id));
            let capabilities: Vec<&str> = state
                .helper
                .as_ref()
                .map(|helper| {
                    RemoteCapability::ALL
                        .iter()
                        .filter(|capability| helper.capabilities.contains(capability))
                        .map(|capability| capability.name())
                        .collect()
                })
                .unwrap_or_default();
            json!({
                "id": profile.id,
                "label": profile.label,
                "alias": profile.alias,
                "color": profile.color,
                "icon": profile.icon,
                "verified": profile.verified.as_ref().map(|identity| json!({
                    "accountName": identity.account_name,
                    "accountUid": identity.account_uid,
                    "storeId": identity.store_id,
                })),
                "observed": service.observed_identity(&profile.id).map(|identity| json!({
                    "accountName": identity.account_name,
                    "accountUid": identity.account_uid,
                    "storeId": identity.store_id,
                })),
                "writesAllowed": profile.writes_allowed,
                "autoInstallHelper": profile.auto_install_helper,
                "phase": state.phase.name(),
                "ready": state.ready(),
                "failure": failure_value(state.failure, &profile.alias),
                "connecting": workflows.connecting(&profile.id),
                "needsHelper": workflows.needs_helper(&profile.id),
                "capabilities": capabilities,
                "writeBlock": service.write_block(&profile.id).map(|block| block.name()),
                "gitVersion": state.helper.as_ref().and_then(|helper| helper.git_version.clone()),
                "accountName": state.helper.as_ref().map(|helper| helper.account_name.clone()),
                "hostPlatform": service.host_target(&profile.id).map(|target| target.host()),
                "initializeBlock": workflows.initialize_block(&profile.id),
                "reconnect": reconnect.map(|reconnect| json!({
                    "phase": match reconnect.phase {
                        ReconnectPhase::Waiting => "waiting",
                        ReconnectPhase::Connecting => "connecting",
                        ReconnectPhase::Stopped => "stopped",
                    },
                    "attempt": reconnect.attempt,
                    // Whole seconds until the next attempt; QML counts down from `at`.
                    "seconds": reconnect.next_attempt_at.map(|at| {
                        at.saturating_duration_since(Instant::now()).as_millis().div_ceil(1000)
                    }),
                    "failure": failure_value(reconnect.failure, &profile.alias),
                    "gaveUp": reconnect.gave_up,
                })),
            })
        })
        .collect();
    let operations: Vec<Value> = service
        .operations()
        .iter()
        .rev()
        .map(|operation| {
            let host = service
                .profile(&operation.profile_id)
                .map(|profile| profile.label);
            json!({
                "id": operation.operation_id,
                "family": operation.family,
                "summary": operation.summary,
                "host": host,
                "profileId": operation.profile_id,
                "pending": operation.state == "pending",
                "outcome": operation.outcome,
                "created": operation.created_at_ms,
                "updated": operation.updated_at_ms,
            })
        })
        .collect();
    let helper = json!({
        "version": service.helper_version(),
        "buildId": service.helper_build_id(),
        "location": service.helper_build_id().map(|id| format!("~/.local/lib/gitlama/remote/{id}/gitlama-remote-helper")),
        "ledgerUsable": service.ledger_usable(),
    });
    (Value::Array(hosts), Value::Array(operations), helper)
}

/// Path bytes from QML: an array of numbers 0–255.
pub fn bytes_of(value: &Value) -> Option<Vec<u8>> {
    value
        .as_array()?
        .iter()
        .map(|byte| byte.as_u64().and_then(|byte| u8::try_from(byte).ok()))
        .collect()
}

fn page_value(page: &DirectoryPage) -> Value {
    json!({
        "directory": page.directory,
        "display": display_path(&page.directory),
        "parent": page.parent,
        "cursor": page.cursor,
        "truncated": page.truncated,
        "entries": page.entries.iter().map(|entry| json!({
            "name": entry.name,
            "display": display_path(&entry.name),
            "kind": match entry.kind {
                EntryKind::Directory => "directory",
                EntryKind::File => "file",
                EntryKind::Symlink => "symlink",
                EntryKind::Other => "other",
            },
            "repository": entry.repository,
        })).collect::<Vec<_>>(),
    })
}

fn profile_error_key(error: &ProfileError) -> &'static str {
    use gitlama_contract::storage::NativeSettingsFailureKind as Kind;
    match error {
        ProfileError::Invalid => "remoteProfileSaveStale",
        ProfileError::Capacity => "remoteFailureCapacity",
        // The settings service is gone (the window closes).
        ProfileError::Save(failure) if failure.rule.as_deref() == Some("service_unavailable") => {
            "remoteProfileSaveUnavailable"
        }
        ProfileError::Save(failure) => match failure.kind {
            Kind::Locked => "remoteProfileSaveLocked",
            Kind::Io => "remoteProfileSaveWriteFailed",
            _ => "remoteProfileSaveRejected",
        },
    }
}

/// A stable code the user can report.
fn profile_error_code(error: &ProfileError) -> String {
    use gitlama_contract::storage::NativeSettingsFailureKind as Kind;
    match error {
        ProfileError::Invalid => "remote_unsupported".to_owned(),
        ProfileError::Capacity => "remote_capacity".to_owned(),
        ProfileError::Save(failure) if failure.rule.as_deref() == Some("service_unavailable") => {
            "service_disposed".to_owned()
        }
        ProfileError::Save(failure) => {
            let kind = match failure.kind {
                Kind::Io => "io",
                Kind::Locked => "locked",
                Kind::Unreadable => "unreadable",
                Kind::InvalidDocument => "invalidDocument",
                Kind::UnsupportedSchema => "unsupportedSchema",
            };
            match &failure.rule {
                Some(rule) => format!("settings_{kind}_{rule}"),
                None => format!("settings_{kind}"),
            }
        }
    }
}

#[qobject(ConvertToCamelCase)]
mod remote_state {
    use super::*;

    #[derive(Default)]
    pub struct RemoteState {
        pub commands: Option<Commands>,
        /// Every host profile with its connection: see [`project`].
        pub(crate) hosts: Value,
        /// The record of remote writes, newest first.
        pub(crate) operations: Value,
        /// {version, buildId, location, ledgerUsable}.
        pub(crate) helper: Value,
    }

    impl RemoteState {
        qproperty!("hosts", Member = hosts, Notify = hosts_changed);
        qproperty!(
            "operations",
            Member = operations,
            Notify = operations_changed
        );
        qproperty!("helper", Member = helper, Notify = helper_changed);

        #[qsignal]
        pub fn hosts_changed(&mut self);
        #[qsignal]
        pub fn operations_changed(&mut self);
        #[qsignal]
        pub fn helper_changed(&mut self);
        /// A directory page arrived (`page` null with a failure {code, key, args}).
        #[qsignal]
        pub fn directory_listed(&mut self, request: i32, page: Value, failure: Value);
        /// A profile was saved (`profile` its ID) or not (`failure` {key, code}).
        #[qsignal]
        pub fn profile_saved(&mut self, request: i32, profile: String, failure: Value);
        /// A host change could not be saved: {key, code}.
        #[qsignal]
        pub fn save_failed(&mut self, failure: Value);
        /// Whether this build carries a helper for the host's platform.
        #[qsignal]
        pub fn installable_checked(&mut self, profile: String, installable: bool);

        #[qslot]
        fn connect(&self, profile: String) {
            self.spawn(move |services| {
                let workflows = Rc::clone(&services.remote_workflows);
                async move {
                    if let Some(selected) = workflows.service.profile(&profile) {
                        workflows.connect_for_use(&selected).await;
                    }
                }
            });
        }

        /// Connects a host from the hosts dialog: no installation offer, no message; the
        /// dialog shows the host's state.
        #[qslot]
        fn connect_host(&self, profile: String) {
            self.spawn(move |services| {
                let service = Rc::clone(&services.remote);
                async move {
                    let _ = service.connect(&profile).await;
                }
            });
        }

        /// Answers `installableChecked` for a host whose helper is missing.
        #[qslot]
        fn check_installable(&self, profile: String) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let service = Rc::clone(&services.remote);
                let state = Rc::clone(&driver.remote);
                rt::spawn_detached(async move {
                    let installable = service.installable_helper(&profile).await.is_some();
                    state.borrow_mut().installable_checked(profile, installable);
                });
            });
        }

        #[qslot]
        fn cancel(&self, profile: String) {
            self.with_services(move |services| services.remote.cancel(&profile));
        }

        #[qslot]
        fn disconnect(&self, profile: String) {
            self.spawn(move |services| {
                let service = Rc::clone(&services.remote);
                async move { service.disconnect(&profile).await }
            });
        }

        #[qslot]
        fn reconnect(&self, profile: String) {
            self.spawn(move |services| {
                let workflows = Rc::clone(&services.remote_workflows);
                async move { workflows.reconnect(&profile).await }
            });
        }

        #[qslot]
        fn stop_reconnecting(&self, profile: String) {
            self.with_services(move |services| {
                if let Some(reconnector) = services.remote.reconnector() {
                    reconnector.stop(&profile);
                }
            });
        }

        #[qslot]
        fn install_helper(&self, profile: String) {
            self.spawn(move |services| {
                let workflows = Rc::clone(&services.remote_workflows);
                async move {
                    workflows.install_helper(&profile).await;
                }
            });
        }

        #[qslot]
        fn set_access(&self, profile: String, allow_changes: bool) {
            self.spawn(move |services| {
                let workflows = Rc::clone(&services.remote_workflows);
                async move { workflows.set_access(&profile, allow_changes).await }
            });
        }

        /// Reconnects a host whose access changed, with its tabs.
        #[qslot]
        fn apply_access(&self, profile: String) {
            self.spawn(move |services| {
                let workflows = Rc::clone(&services.remote_workflows);
                async move { workflows.apply_access(&profile).await }
            });
        }

        #[qslot]
        fn set_auto_install(&self, profile: String, enabled: bool) {
            let state = self.commands.clone();
            self.spawn(move |services| {
                let service = Rc::clone(&services.remote);
                async move {
                    if let Err(error) = service.set_auto_install_helper(&profile, enabled).await
                        && let Some(commands) = state
                    {
                        commands.post(move |driver| {
                            driver.remote.borrow_mut().save_failed(json!({
                                "key": profile_error_key(&error), "code": profile_error_code(&error),
                            }));
                        });
                    }
                }
            });
        }

        /// Saves a profile (`id` empty for a new one); answers with `profileSaved`.
        #[qslot]
        fn save_profile(
            &self,
            request: i32,
            id: String,
            label: String,
            alias: String,
            color: String,
            icon: String,
        ) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let service = Rc::clone(&services.remote);
                let state = Rc::clone(&driver.remote);
                rt::spawn_detached(async move {
                    let result = service
                        .save_profile(
                            Some(id.as_str()).filter(|id| !id.is_empty()),
                            &label,
                            &alias,
                            Some(color).filter(|color| !color.is_empty()),
                            Some(icon).filter(|icon| !icon.is_empty()),
                        )
                        .await;
                    let mut shown = state.borrow_mut();
                    match result {
                        Ok(profile) => shown.profile_saved(request, profile.id, Value::Null),
                        Err(error) => shown.profile_saved(
                            request,
                            String::new(),
                            json!({ "key": profile_error_key(&error), "code": profile_error_code(&error) }),
                        ),
                    }
                });
            });
        }

        #[qslot]
        fn delete_profile(&self, profile: String) {
            let state = self.commands.clone();
            self.spawn(move |services| {
                let service = Rc::clone(&services.remote);
                async move {
                    if let Err(error) = service.delete_profile(&profile).await
                        && let Some(commands) = state
                    {
                        commands.post(move |driver| {
                            driver.remote.borrow_mut().save_failed(json!({
                                "key": profile_error_key(&error), "code": profile_error_code(&error),
                            }));
                        });
                    }
                }
            });
        }

        /// Accepts the identity a host reported after it changed, and connects again.
        #[qslot]
        fn rebind(&self, profile: String) {
            self.spawn(move |services| {
                let service = Rc::clone(&services.remote);
                async move {
                    let _ = service.rebind(&profile).await;
                }
            });
        }

        /// Lists `directory` (path bytes; null for the home) on a connected host.
        #[qslot]
        fn list_directory(&self, request: i32, profile: String, directory: Value, cursor: String) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let service = Rc::clone(&services.remote);
                let alias = service
                    .profile(&profile)
                    .map(|profile| profile.alias)
                    .unwrap_or_default();
                let state = Rc::clone(&driver.remote);
                let directory = bytes_of(&directory);
                let cursor = Some(cursor).filter(|cursor| !cursor.is_empty());
                rt::spawn_detached(async move {
                    let result = service.list_directory(&profile, directory, cursor).await;
                    let mut shown = state.borrow_mut();
                    match result {
                        Ok(page) => shown.directory_listed(request, page_value(&page), Value::Null),
                        Err(code) => shown.directory_listed(
                            request,
                            Value::Null,
                            failure_value(Some(code), &alias),
                        ),
                    }
                });
            });
        }

        /// Chooses a host and a folder and opens the repository there; `tab` (≥ 0) replaces
        /// a chooser tab.
        #[qslot]
        fn open_remote_repository(&self, tab: i32) {
            self.spawn(move |services| {
                let workflows = Rc::clone(&services.remote_workflows);
                async move {
                    workflows
                        .open_remote_repository(u64::try_from(tab).ok())
                        .await;
                }
            });
        }

        /// Opens the remote recent at `index` (connecting its host); `tab` (≥ 0) replaces a
        /// chooser tab.
        #[qslot]
        fn open_recent(&self, index: i32, tab: i32) {
            self.spawn(move |services| {
                let workflows = Rc::clone(&services.remote_workflows);
                let identity = services
                    .settings
                    .with(|document| document.recent_repositories.get(index as usize).cloned());
                async move {
                    if let Some(identity) = identity {
                        workflows
                            .open_recent(identity, u64::try_from(tab).ok())
                            .await;
                    }
                }
            });
        }

        /// Opens `path` on the saved host with SSH alias `alias` (offering to save an unknown
        /// alias first), connecting it: the command line's remote open.
        #[qslot]
        fn open_on_host(&self, alias: String, path: String) {
            self.spawn(move |services| {
                let workflows = Rc::clone(&services.remote_workflows);
                async move { workflows.open_on_host(&alias, path.into_bytes()).await }
            });
        }

        /// Reopens a remote tab after the user trusted the repository now at its path.
        #[qslot]
        fn trust_repository(&self, tab: i32) {
            self.spawn(move |services| {
                let workspace = Rc::clone(&services.workspace);
                async move {
                    let _ = workspace.reopen_changed_remote_tab(tab as u64).await;
                }
            });
        }

        /// Removes a resolved remote write the user acknowledged.
        #[qslot]
        fn dismiss_operation(&self, operation: String) {
            self.spawn(move |services| {
                let service = Rc::clone(&services.remote);
                async move { service.dismiss_operation(&operation).await }
            });
        }

        /// Looks up a host's unresolved writes again.
        #[qslot]
        fn reconcile(&self, profile: String) {
            self.spawn(move |services| {
                let service = Rc::clone(&services.remote);
                async move { service.reconcile(&profile).await }
            });
        }
    }

    impl RemoteState {
        fn with_services(&self, action: impl FnOnce(&Services) + 'static) {
            if let Some(commands) = &self.commands {
                commands.post(move |driver| {
                    if let Some(services) = driver.app.services() {
                        action(&services);
                    }
                });
            }
        }

        fn spawn<F, Fut>(&self, start: F)
        where
            F: FnOnce(&Services) -> Fut + 'static,
            Fut: std::future::Future<Output = ()> + 'static,
        {
            self.with_services(move |services| rt::spawn_detached(start(services)));
        }
    }
}

pub use remote_state::RemoteState;
