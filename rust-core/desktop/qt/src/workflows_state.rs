//! Slots that start the repository workflows the commands run (transfers,
//! references, stashes, ...). Each asks its own questions through prompts.

use crate::plumbing::Commands;
use gitlama_workbench::rt;
use gitlama_workbench::transfers::{Draft, parse_kind};
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;

#[qobject(ConvertToCamelCase)]
mod workflows_state {
    use super::*;

    #[derive(Default)]
    pub struct WorkflowsState {
        pub commands: Option<Commands>,
        /// The active tab's blocking operation for the busy overlay:
        /// {key, args, cancellable, canceling}, or null.
        pub(crate) busy: Value,
        /// The active tab's latest workflow, blocking or not, for the Compass:
        /// {key, args}, or null.
        pub(crate) work: Value,
        /// The person's fetch, pull or push running in the active tab:
        /// {action}, or null.
        pub(crate) running_transfer: Value,
        /// The file manager's name for "Open in …".
        pub(crate) file_browser: String,
        /// A snapshot being saved: {running, started, files, total, writing}.
        pub(crate) archive: Value,
        /// The named snapshots panel (snapshots.rs panel_value).
        pub(crate) snapshots: Value,
        /// The power tools panel (power_tools.rs panel_value).
        pub(crate) power_tools: Value,
        /// The extensions panel (extensions.rs panel_value).
        pub(crate) extensions: Value,
        /// Loaded author images: Gravatar hash to data URL.
        pub(crate) avatars: Value,
    }

    impl WorkflowsState {
        qproperty!("busy", Member = busy, Notify = busy_changed);
        qproperty!("work", Member = work, Notify = work_changed);
        qproperty!(
            "runningTransfer",
            Member = running_transfer,
            Notify = running_transfer_changed
        );
        qproperty!(
            "fileBrowser",
            Member = file_browser,
            Notify = file_browser_changed
        );
        qproperty!("archive", Member = archive, Notify = archive_changed);
        qproperty!("snapshots", Member = snapshots, Notify = snapshots_changed);

        qproperty!(
            "powerTools",
            Member = power_tools,
            Notify = power_tools_changed
        );

        #[qsignal]
        pub fn snapshots_changed(&mut self);

        #[qsignal]
        pub fn power_tools_changed(&mut self);

        qproperty!("avatars", Member = avatars, Notify = avatars_changed);
        #[qsignal]
        pub fn avatars_changed(&mut self);

        /// Loads the author image of Gravatar hash `hash` (while enabled).
        #[qslot]
        fn request_avatar(&self, hash: String) {
            self.with_services(move |services| services.avatars.request(hash));
        }

        /// Turns author images from Gravatar on or off.
        #[qslot]
        fn set_gravatar(&self, enabled: bool) {
            self.with_services(move |services| {
                services.avatars.set_enabled(enabled);
            });
        }

        qproperty!(
            "extensions",
            Member = extensions,
            Notify = extensions_changed
        );

        #[qsignal]
        pub fn extensions_changed(&mut self);

        /// The extensions panel: `action` is open, load, createWorktree
        /// (path, reference), lfsTrack, lfsUntrack (pattern), lfsPull, or a
        /// row action (openWorktree, deleteWorktree, submodule,
        /// enterSubmodule, inspectPointer) with its `index`.
        #[qslot]
        fn extension(&self, action: String, options: Value) {
            let options = crate::json::integral_numbers(options);
            use gitlama_contract::extensions::NativeExtensionMutationKind as Kind;
            use gitlama_workbench::extensions::PanelAction;
            self.with_services(move |services| {
                let extensions = Rc::clone(&services.extensions);
                let text = |key: &str| options[key].as_str().unwrap_or_default().to_owned();
                let index = crate::json::whole(&options["index"]).unwrap_or(u64::MAX) as usize;
                let row = match action.as_str() {
                    "openWorktree" => Some(PanelAction::OpenWorktree(index)),
                    "deleteWorktree" => Some(PanelAction::DeleteWorktree(index)),
                    "submodule" => Some(PanelAction::Submodule(index)),
                    "enterSubmodule" => Some(PanelAction::EnterSubmodule(index)),
                    "inspectPointer" => Some(PanelAction::InspectPointer(index)),
                    _ => None,
                };
                if let Some(row) = row {
                    return rt::spawn_detached(async move { extensions.act(row).await });
                }
                match action.as_str() {
                    "open" => rt::spawn_detached(async move { extensions.open().await }),
                    "load" => rt::spawn_detached(async move { extensions.load().await }),
                    "createWorktree" => {
                        let (path, reference) = (text("path"), text("reference"));
                        rt::spawn_detached(async move {
                            extensions.create_worktree(path, reference).await
                        })
                    }
                    "lfsTrack" | "lfsUntrack" | "lfsPull" => {
                        let kind = match action.as_str() {
                            "lfsTrack" => Kind::LfsTrack,
                            "lfsUntrack" => Kind::LfsUntrack,
                            _ => Kind::LfsPull,
                        };
                        let pattern = text("pattern");
                        rt::spawn_detached(async move { extensions.lfs(kind, pattern).await })
                    }
                    _ => {}
                }
            });
        }

        /// Power tools: `action` is open or close (options.owner), search
        /// (query, caseSensitive, currentBranch), cancelSearch, statistics,
        /// bisect (step: start, good, bad, skip, reset; good, bad) or reveal
        /// (commit).
        #[qslot]
        fn power_tool(&self, action: String, options: Value) {
            let options = crate::json::integral_numbers(options);
            self.with_services(move |services| {
                let tools = Rc::clone(&services.power_tools);
                let text = |key: &str| options[key].as_str().unwrap_or_default().to_owned();
                let owner = crate::json::whole(&options["owner"]).unwrap_or(0);
                match action.as_str() {
                    "open" => rt::spawn_detached(async move { tools.open(owner).await }),
                    "close" => tools.close(owner),
                    "search" => {
                        let (query, case, current) = (
                            text("query"),
                            options["caseSensitive"].as_bool() == Some(true),
                            options["currentBranch"].as_bool() == Some(true),
                        );
                        rt::spawn_detached(async move { tools.search(query, case, current).await })
                    }
                    "cancelSearch" => tools.cancel_search(),
                    "statistics" => rt::spawn_detached(async move { tools.statistics().await }),
                    "bisect" => {
                        let Some(step) =
                            gitlama_workbench::power_tools::bisect_action(&text("step"))
                        else {
                            return;
                        };
                        let (good, bad) = (text("good"), text("bad"));
                        rt::spawn_detached(async move { tools.bisect(step, good, bad).await })
                    }
                    "reveal" => {
                        let commit = text("commit");
                        rt::spawn_detached(async move { tools.reveal(commit).await })
                    }
                    _ => {}
                }
            });
        }

        /// Named snapshots: `action` is load, more, create, restore, branch,
        /// delete or select; `options` carries id, name, includeUntracked,
        /// keepIndex.
        #[qslot]
        fn snapshot(&self, action: String, options: Value) {
            let options = crate::json::integral_numbers(options);
            self.with_services(move |services| {
                let snapshots = Rc::clone(&services.snapshots);
                let id = options["id"].as_str().and_then(|id| id.parse::<u64>().ok());
                match (action.as_str(), id) {
                    ("select", Some(id)) => snapshots.select(id),
                    ("load", _) => rt::spawn_detached(async move { snapshots.load(true).await }),
                    ("more", _) => rt::spawn_detached(async move { snapshots.load(false).await }),
                    ("create", _) => {
                        let name = options["name"].as_str().unwrap_or_default().to_owned();
                        let untracked = options["includeUntracked"].as_bool().unwrap_or(true);
                        let keep = options["keepIndex"].as_bool().unwrap_or(false);
                        rt::spawn_detached(
                            async move { snapshots.create(name, untracked, keep).await },
                        )
                    }
                    ("restore", Some(id)) => {
                        rt::spawn_detached(async move { snapshots.restore(id).await })
                    }
                    ("branch", Some(id)) => {
                        rt::spawn_detached(async move { snapshots.branch(id).await })
                    }
                    ("delete", Some(id)) => {
                        rt::spawn_detached(async move { snapshots.delete(id).await })
                    }
                    _ => {}
                }
            });
        }

        #[qsignal]
        pub fn archive_changed(&mut self);

        /// The snapshot's file and folder name for `commit` of the repository
        /// `label`.
        #[qslot]
        fn archive_name(&self, label: String, commit: String) -> String {
            gitlama_workbench::archive::archive_name(&label, &commit)
        }

        /// Saves the zip snapshot of `commit` to `destination`.
        #[qslot]
        fn save_commit_archive(&self, commit: String, prefix: String, destination: String) {
            self.with_services(move |services| {
                let archives = Rc::clone(&services.archives);
                rt::spawn_detached(async move { archives.save(commit, prefix, destination).await });
            });
        }

        /// Stops the snapshot being saved.
        #[qslot]
        fn cancel_commit_archive(&self) {
            self.with_services(|services| services.archives.cancel());
        }

        #[qsignal]
        pub fn busy_changed(&mut self);
        #[qsignal]
        pub fn work_changed(&mut self);
        #[qsignal]
        pub fn running_transfer_changed(&mut self);
        /// A fetch, pull or push the person started in the active tab ended,
        /// even one that ended before any refresh showed it running.
        #[qsignal]
        pub fn work_finished(&mut self, succeeded: bool);
        /// The answer of `worktree_menu`.
        #[qsignal]
        pub fn worktree_menu_ready(&mut self, rows: Value);
        /// The answer of `inspect_locks`: see `RepositoryLocks::inspect`.
        #[qsignal]
        pub fn locks_inspected(&mut self, inspection: Value);
        /// The answer of `remove_locks`: {removed} or {failure: l10n key}.
        #[qsignal]
        pub fn locks_removed(&mut self, outcome: Value);
        #[qsignal]
        pub fn file_browser_changed(&mut self);

        /// The menu of a file or folder (file_actions.rs): `subject` names
        /// it, `selection` is {count, staged, clean} or null, `host` is
        /// {capabilities, reasons: {action: key}, inspectionReason, busy,
        /// allowStagingWhileBusy}.
        #[qslot]
        fn file_menu(&self, subject: Value, selection: Value, host: Value) -> Value {
            let subject = crate::json::integral_numbers(subject);
            let selection = crate::json::integral_numbers(selection);
            let host = crate::json::integral_numbers(host);
            use gitlama_workbench::file_actions::{FileAction, Host, Selection, Subject, menu};
            let Some(subject) = Subject::from_value(&subject) else {
                return Value::Array(Vec::new());
            };
            let selection = selection
                .get("count")
                .and_then(Value::as_u64)
                .map(|count| Selection {
                    count: count as usize,
                    staged: selection["staged"].as_bool().unwrap_or(false),
                    clean: selection["clean"].as_bool(),
                });
            let host = Host {
                capabilities: host["capabilities"]
                    .as_array()
                    .map(|names| {
                        names
                            .iter()
                            .filter_map(Value::as_str)
                            .filter_map(FileAction::parse)
                            .collect()
                    })
                    .unwrap_or_default(),
                file_browser: self.file_browser.clone(),
                inspection_reason: host["inspectionReason"].as_str().map(str::to_owned),
                reasons: host["reasons"]
                    .as_object()
                    .map(|reasons| {
                        reasons
                            .iter()
                            .filter_map(|(name, reason)| {
                                Some((FileAction::parse(name)?, reason.as_str()?.to_owned()))
                            })
                            .collect()
                    })
                    .unwrap_or_default(),
                busy: host["busy"].as_bool().unwrap_or(false),
                allow_staging_while_busy: host["allowStagingWhileBusy"].as_bool().unwrap_or(false),
            };
            Value::Array(menu(&subject, &host, selection))
        }

        /// Opens the repository (`path` empty) or its file `path` with a tool
        /// of `kind` (editor, terminal, fileManager).
        #[qslot]
        fn open_tool(&self, kind: String, path: String) {
            use gitlama_workbench::integrations::{Target, parse_kind};
            let Some(kind) = parse_kind(&kind) else {
                return;
            };
            self.with_services(move |services| {
                let integrations = Rc::clone(&services.integrations);
                let target = (!path.is_empty()).then_some(Target::Relative(path));
                rt::spawn_detached(async move { integrations.open(kind, target).await });
            });
        }

        /// Opens the local folder `path` itself in the file manager.
        #[qslot]
        fn open_folder(&self, path: String) {
            use gitlama_contract::dto::{NativePathIdentity, NativePathPlatform};
            self.with_services(move |services| {
                let integrations = Rc::clone(&services.integrations);
                let folder = if cfg!(windows) {
                    NativePathIdentity {
                        platform: NativePathPlatform::Windows,
                        units: path.encode_utf16().collect(),
                        remote: None,
                    }
                } else {
                    NativePathIdentity {
                        platform: NativePathPlatform::Unix,
                        units: path.bytes().map(u16::from).collect(),
                        remote: None,
                    }
                };
                rt::spawn_detached(async move { integrations.open_folder(folder).await });
            });
        }

        /// Offers and adds the `.gitignore` entry that hides `path`.
        #[qslot]
        fn ignore_path(&self, path: String, directory: bool, tracked: bool) {
            self.with_services(move |services| {
                let extensions = Rc::clone(&services.extensions);
                rt::spawn_detached(
                    async move { extensions.ignore(path, directory, tracked).await },
                );
            });
        }

        /// Shows the local file `path` in the file manager.
        #[qslot]
        fn reveal_path(&self, path: String) {
            use gitlama_contract::dto::{NativePathIdentity, NativePathPlatform};
            use gitlama_workbench::integrations::Target;
            self.with_services(move |services| {
                let integrations = Rc::clone(&services.integrations);
                let file = if cfg!(windows) {
                    NativePathIdentity {
                        platform: NativePathPlatform::Windows,
                        units: path.encode_utf16().collect(),
                        remote: None,
                    }
                } else {
                    NativePathIdentity {
                        platform: NativePathPlatform::Unix,
                        units: path.bytes().map(u16::from).collect(),
                        remote: None,
                    }
                };
                rt::spawn_detached(async move {
                    integrations
                        .open(
                            gitlama_contract::integrations::NativeIntegrationKind::FileManager,
                            Some(Target::Absolute(file)),
                        )
                        .await
                });
            });
        }

        /// Deletes linked worktree `index` of the sidebar after a confirmation.
        #[qslot]
        fn delete_worktree(&self, index: i32) {
            let Ok(index) = usize::try_from(index) else {
                return;
            };
            self.with_services(move |services| {
                let extensions = Rc::clone(&services.extensions);
                rt::spawn_detached(async move { extensions.delete_worktree(index).await });
            });
        }

        /// Runs the configured tool `id` on the repository.
        #[qslot]
        fn run_integration(&self, id: String) {
            self.with_services(move |services| {
                let integrations = Rc::clone(&services.integrations);
                rt::spawn_detached(async move { integrations.run_stored(&id).await });
            });
        }

        /// Asks the active tab's blocking operation to stop.
        #[qslot]
        fn cancel_busy(&self) {
            self.with_services(|services| {
                if let Some(tab) = services.workspace.active_tab_id() {
                    services.busy.cancel(tab);
                }
            });
        }

        /// Fetch, pull, push, push or delete a tag, delete a remote branch:
        /// `options` may carry initialRemote, initialBranch, initialForce.
        #[qslot]
        fn transfer(&self, kind: String, options: Value) {
            let options = crate::json::integral_numbers(options);
            let Some(kind) = parse_kind(&kind) else {
                return;
            };
            self.with_services(move |services| {
                let mut draft = Draft::new(kind);
                draft.initial_remote = options["initialRemote"].as_str().map(str::to_owned);
                draft.initial_branch = options["initialBranch"].as_str().map(str::to_owned);
                draft.initial_force = options["initialForce"].as_bool().unwrap_or(false);
                let transfers = Rc::clone(&services.transfers);
                rt::spawn_detached(async move { transfers.start(draft).await });
            });
        }

        /// A branch, tag or remote change of `kind` (refs.rs kind names);
        /// `options` may carry initialName and initialTarget.
        #[qslot]
        fn reference(&self, kind: String, options: Value) {
            let options = crate::json::integral_numbers(options);
            let Some(kind) = gitlama_workbench::refs::parse_kind(&kind) else {
                return;
            };
            self.with_services(move |services| {
                let refs = Rc::clone(&services.refs);
                let name = options["initialName"].as_str().map(str::to_owned);
                let target = options["initialTarget"].as_str().map(str::to_owned);
                rt::spawn_detached(async move { refs.mutate(kind, name, target).await });
            });
        }

        /// Renames a branch and changes its upstream.
        #[qslot]
        fn edit_branch(&self, name: String) {
            self.with_services(move |services| {
                let refs = Rc::clone(&services.refs);
                let name = (!name.is_empty()).then_some(name);
                rt::spawn_detached(async move { refs.edit_branch(name).await });
            });
        }

        /// Checks out branch `name` (`reference` is its full name when known).
        #[qslot]
        fn checkout(&self, name: String, reference: String) {
            self.with_services(move |services| {
                let refs = Rc::clone(&services.refs);
                let name = (!name.is_empty()).then_some(name);
                let reference = (!reference.is_empty()).then_some(reference);
                rt::spawn_detached(async move { refs.checkout(name, reference).await });
            });
        }

        /// Deletes a branch on its remote.
        #[qslot]
        fn delete_remote_branch(&self, reference: String) {
            self.with_services(move |services| {
                let refs = Rc::clone(&services.refs);
                let reference = (!reference.is_empty()).then_some(reference);
                rt::spawn_detached(async move { refs.delete_remote_branch(reference).await });
            });
        }

        /// A stash change of `kind` (push, apply, pop, drop, rename,
        /// autoStashCheckout); `options` may carry selector, objectId and
        /// targetBranch.
        #[qslot]
        fn stash(&self, kind: String, options: Value) {
            let options = crate::json::integral_numbers(options);
            let Some(kind) = gitlama_workbench::rewrite::parse_stash_kind(&kind) else {
                return;
            };
            self.with_services(move |services| {
                let rewrite = Rc::clone(&services.rewrite);
                let text = |key: &str| {
                    options[key]
                        .as_str()
                        .filter(|text| !text.is_empty())
                        .map(str::to_owned)
                };
                let (selector, object_id, target) =
                    (text("selector"), text("objectId"), text("targetBranch"));
                rt::spawn_detached(async move {
                    rewrite.stash(kind, selector, object_id, target).await
                });
            });
        }

        /// Checks out commit `target` (detached).
        #[qslot]
        fn checkout_commit(&self, target: String) {
            self.with_services(move |services| {
                let rewrite = Rc::clone(&services.rewrite);
                let target = (!target.is_empty()).then_some(target);
                rt::spawn_detached(async move { rewrite.checkout_commit(target).await });
            });
        }

        /// Merges a branch, or cherry-picks or reverts commits: `kind` is
        /// merge, cherryPick or revert; empty strings leave a value unset.
        #[qslot]
        fn mutate_history(&self, kind: String, source_name: String, target: String) {
            self.with_services(move |services| {
                let Some(kind) = gitlama_workbench::history_mutations::parse_kind(&kind) else {
                    return;
                };
                let mutations = Rc::clone(&services.history_mutations);
                let source = (!source_name.is_empty()).then_some(source_name);
                let target = (!target.is_empty()).then_some(target);
                rt::spawn_detached(async move { mutations.mutate(kind, source, target).await });
            });
        }

        /// Asks whether to merge `source_name` or rebase onto it.
        #[qslot]
        fn integrate_branch(&self, source_name: String, target: String) {
            self.with_services(move |services| {
                let rebases = Rc::clone(&services.rebases);
                let source = (!source_name.is_empty()).then_some(source_name);
                let target = (!target.is_empty()).then_some(target);
                rt::spawn_detached(async move { rebases.integrate(source, target).await });
            });
        }

        /// Rebases the current branch interactively onto `target` (an
        /// object ID), or a branch the user chooses.
        #[qslot]
        fn rebase(&self, target: String) {
            self.with_services(move |services| {
                let rebases = Rc::clone(&services.rebases);
                let target = (!target.is_empty()).then_some(target);
                rt::spawn_detached(async move { rebases.rebase(target).await });
            });
        }

        /// Restacks the branches on `root`, or a root the user chooses.
        #[qslot]
        fn restack(&self, root: String) {
            self.with_services(move |services| {
                let rebases = Rc::clone(&services.rebases);
                let root = (!root.is_empty()).then_some(root);
                rt::spawn_detached(async move { rebases.restack(root).await });
            });
        }

        /// Lists the worktrees the tab row's open menu offers
        /// (`worktree_menu_ready`: [{label, icon}], or null when they could
        /// not be listed).
        #[qslot]
        fn worktree_menu(&self) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(|driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let extensions = Rc::clone(&services.extensions);
                let shared = Rc::clone(&driver.workflows);
                rt::spawn_detached(async move {
                    let rows = extensions.worktree_menu().await.unwrap_or(Value::Null);
                    shared.borrow_mut().worktree_menu_ready(rows);
                });
            });
        }

        /// Opens worktree `index` of the last listed menu.
        #[qslot]
        fn open_menu_worktree(&self, index: i32) {
            self.with_services(move |services| {
                let extensions = Rc::clone(&services.extensions);
                rt::spawn_detached(async move {
                    extensions.open_menu_worktree(index.max(0) as usize).await
                });
            });
        }

        /// Inspect index lock: removes a left behind index lock after a confirmation.
        #[qslot]
        fn inspect_index_lock(&self) {
            self.with_services(|services| {
                let locks = Rc::clone(&services.locks);
                rt::spawn_detached(async move { locks.inspect_index_lock().await });
            });
        }

        /// Lists the active repository's lock files (`locks_inspected`).
        #[qslot]
        fn inspect_locks(&self) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(|driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let locks = Rc::clone(&services.locks);
                let shared = Rc::clone(&driver.workflows);
                rt::spawn_detached(async move {
                    let inspection = locks.inspect().await;
                    shared.borrow_mut().locks_inspected(inspection);
                });
            });
        }

        /// Removes the listed locks (`locks_removed`).
        #[qslot]
        fn remove_locks(&self, tokens: Vec<String>) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let locks = Rc::clone(&services.locks);
                let shared = Rc::clone(&driver.workflows);
                let tokens: Vec<u64> = tokens
                    .iter()
                    .filter_map(|token| token.parse().ok())
                    .collect();
                rt::spawn_detached(async move {
                    let outcome = match locks.remove(tokens).await {
                        Ok(removed) => json!({"removed": removed}),
                        Err(key) => json!({"failure": key}),
                    };
                    shared.borrow_mut().locks_removed(outcome);
                });
            });
        }

        fn with_services(&self, action: impl FnOnce(&gitlama_workbench::app::Services) + 'static) {
            if let Some(commands) = &self.commands {
                commands.post(move |driver| {
                    if let Some(services) = driver.app.services() {
                        action(&services);
                    }
                });
            }
        }
    }
}

pub use workflows_state::WorkflowsState;
