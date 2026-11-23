//! The patch dialog's state: Create writes a
//! patch to a chosen folder after a preview, Apply checks a patch file and
//! applies it; each finishes with a message and a way to start again.

use crate::plumbing::Commands;
use gitlama_contract::dto::NativeStagingSide;
use gitlama_workbench::patches::{
    PatchService, Source, apply_message, export_message, format_key, scope_key,
};
use gitlama_workbench::rt;
use gitlama_workbench::session::SessionIdentity;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;

/// Reads where a patch was asked for: {kind: history|diff|selection|lines|
/// files, commit, base, paths, side, requestId, rows}.
pub fn parse_source(value: &Value) -> Option<Source> {
    let paths = || -> Vec<Vec<u8>> {
        value["paths"]
            .as_array()
            .map(|paths| {
                paths
                    .iter()
                    .filter_map(Value::as_str)
                    .map(|path| path.as_bytes().to_vec())
                    .collect()
            })
            .unwrap_or_default()
    };
    let side = || {
        if value["side"] == "staged" {
            NativeStagingSide::Staged
        } else {
            NativeStagingSide::Unstaged
        }
    };
    Some(match value["kind"].as_str()? {
        "history" => Source::History {
            commit: value["commit"]
                .as_str()
                .filter(|commit| !commit.is_empty())
                .map(str::to_owned),
        },
        "diff" => Source::Diff {
            base: value["base"]
                .as_str()
                .filter(|base| !base.is_empty())
                .map(str::to_owned),
            commit: value["commit"].as_str()?.to_owned(),
            paths: paths(),
        },
        "selection" => Source::Selection,
        "lines" => Source::Lines {
            request_id: value["requestId"].as_str()?.parse().ok()?,
            rows: value["rows"]
                .as_array()
                .map(|rows| {
                    rows.iter()
                        .filter_map(Value::as_str)
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default(),
        },
        "files" => Source::Files {
            side: side(),
            paths: paths(),
        },
        "keys" => Source::Keys {
            side: side(),
            keys: value["keys"]
                .as_array()
                .map(|keys| {
                    keys.iter()
                        .filter_map(Value::as_str)
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default(),
        },
        _ => return None,
    })
}

#[qobject(ConvertToCamelCase)]
mod patch_state {
    use super::*;

    #[derive(Default)]
    pub struct PatchState {
        pub commands: Option<Commands>,
        /// {mode, busy, failed, destination, patchPath, export, apply,
        /// completion, repositoryLabel}.
        pub(crate) state: Value,
        source: Option<Source>,
        identity: Option<SessionIdentity>,
        export_token: Option<u64>,
        apply_token: Option<u64>,
        /// Answers of an earlier step or dialog are dropped.
        sequence: u64,
    }

    impl PatchState {
        qproperty!("state", Member = state, Notify = state_changed);

        #[qsignal]
        pub fn state_changed(&mut self);

        /// Starts a dialog for `source` in `mode` (create or apply).
        #[qslot]
        fn begin(&self, source: Value, mode: String) {
            let Some(source) = parse_source(&source) else {
                return;
            };
            self.with_state(move |state, services| {
                state.sequence += 1;
                state.source = Some(source);
                state.identity = services.patches.session();
                state.export_token = None;
                state.apply_token = None;
                let label = services
                    .workspace
                    .active_tab()
                    .map(|tab| tab.label)
                    .unwrap_or_default();
                state.state = json!({
                    "mode": if mode == "apply" { "apply" } else { "create" },
                    "busy": false,
                    "failed": false,
                    "destination": null,
                    "patchPath": null,
                    "export": null,
                    "apply": null,
                    "completion": null,
                    "repositoryLabel": label,
                });
                state.state_changed();
            });
        }

        /// Switches between Create and Apply.
        #[qslot]
        fn set_mode(&self, mode: String) {
            self.with_state(move |state, _| {
                if state.state["busy"] == true {
                    return;
                }
                state.state["mode"] = json!(if mode == "apply" { "apply" } else { "create" });
                state.state["failed"] = json!(false);
                state.state["completion"] = Value::Null;
                state.state_changed();
            });
        }

        /// Previews writing the patch into `directory`.
        #[qslot]
        fn choose_destination(&self, directory: String) {
            self.with_state(move |state, _| {
                state.state["destination"] = json!(directory);
                state.state_changed();
            });
            self.preview_export(false);
        }

        /// Previews writing over the existing file.
        #[qslot]
        fn overwrite(&self) {
            self.preview_export(true);
        }

        /// Writes the previewed patch.
        #[qslot]
        fn write(&self) {
            self.run(|state| state.export_token, |patches, identity, token, sequence, shared| async move {
                let result = patches.execute_export(identity, token).await;
                let mut state = shared.borrow_mut();
                if state.sequence != sequence {
                    return;
                }
                state.export_token = None;
                state.state["busy"] = json!(false);
                state.state["export"] = Value::Null;
                match result {
                    Ok(result) => {
                        let (key, failed) = export_message(result.state);
                        let path = (!failed).then(|| result.destination.clone()).flatten();
                        state.state["failed"] = json!(failed);
                        state.state["completion"] = json!({"key": key, "tone": if failed { "error" } else { "success" }, "path": path});
                    }
                    Err(_) => state.state["failed"] = json!(true),
                }
                state.state_changed();
            });
        }

        /// Checks the patch file `path`.
        #[qslot]
        fn choose_file(&self, path: String) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let shared = Rc::clone(&driver.patches);
                let (identity, sequence) = {
                    let mut state = shared.borrow_mut();
                    let Some(identity) = state.identity else { return };
                    state.sequence += 1;
                    state.apply_token = None;
                    state.state["patchPath"] = json!(path);
                    state.state["busy"] = json!(true);
                    state.state["failed"] = json!(false);
                    state.state["apply"] = Value::Null;
                    state.state["completion"] = Value::Null;
                    state.state_changed();
                    (identity, state.sequence)
                };
                let patches = Rc::clone(&services.patches);
                rt::spawn_detached(async move {
                    let result = if patches.active(identity) { patches.preview_apply(identity, path).await.ok() } else { None };
                    let mut state = shared.borrow_mut();
                    if state.sequence != sequence {
                        return;
                    }
                    state.state["busy"] = json!(false);
                    match result {
                        Some(preview) => {
                            state.apply_token = Some(preview.token);
                            state.state["apply"] = json!({
                                "paths": preview.paths.iter().map(|path| String::from_utf8_lossy(path).into_owned()).collect::<Vec<_>>(),
                                "binary": preview.binary,
                                "command": format!("git {}", preview.arguments.join(" ")),
                            });
                        }
                        None => state.state["failed"] = json!(true),
                    }
                    state.state_changed();
                });
            });
        }

        /// Applies the checked patch.
        #[qslot]
        fn apply(&self) {
            self.run(
                |state| state.apply_token,
                |patches, identity, token, sequence, shared| async move {
                    let result = patches.execute_apply(identity, token).await;
                    let mut state = shared.borrow_mut();
                    if state.sequence != sequence {
                        return;
                    }
                    state.apply_token = None;
                    state.state["busy"] = json!(false);
                    state.state["apply"] = Value::Null;
                    match result {
                        Ok(result) => {
                            let (key, tone) = apply_message(result.state);
                            state.state["failed"] = json!(tone == "error");
                            state.state["completion"] =
                                json!({"key": key, "tone": tone, "path": null});
                        }
                        Err(_) => state.state["failed"] = json!(true),
                    }
                    state.state_changed();
                },
            );
        }

        /// The dialog closed: later answers are dropped.
        #[qslot]
        fn end(&self) {
            self.with_state(|state, _| {
                state.sequence += 1;
                state.source = None;
                state.identity = None;
                state.export_token = None;
                state.apply_token = None;
            });
        }
    }

    impl PatchState {
        fn with_state(
            &self,
            action: impl FnOnce(&mut PatchState, &gitlama_workbench::app::Services) + 'static,
        ) {
            let Some(commands) = &self.commands else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                action(&mut driver.patches.borrow_mut(), &services);
            });
        }

        fn preview_export(&self, overwrite: bool) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let shared = Rc::clone(&driver.patches);
                let (identity, request, sequence) = {
                    let mut state = shared.borrow_mut();
                    let (Some(identity), Some(source), Some(destination)) = (
                        state.identity,
                        state.source.clone(),
                        state.state["destination"].as_str().map(str::to_owned),
                    ) else {
                        return;
                    };
                    if state.state["busy"] == true {
                        return;
                    }
                    state.sequence += 1;
                    state.export_token = None;
                    state.state["busy"] = json!(true);
                    state.state["failed"] = json!(false);
                    state.state["completion"] = Value::Null;
                    state.state_changed();
                    (
                        identity,
                        services.patches.request(&source, destination, overwrite),
                        state.sequence,
                    )
                };
                let patches = Rc::clone(&services.patches);
                rt::spawn_detached(async move {
                    let result = if patches.active(identity) {
                        patches.preview_export(identity, request).await.ok()
                    } else {
                        None
                    };
                    let mut state = shared.borrow_mut();
                    if state.sequence != sequence {
                        return;
                    }
                    state.state["busy"] = json!(false);
                    match result {
                        Some(preview) => {
                            state.export_token = preview.token;
                            state.state["export"] = json!({
                                "scope": scope_key(preview.scope),
                                "format": format_key(preview.format),
                                "filename": preview.filename,
                                "destination": preview.destination,
                                "bytes": preview.byte_count,
                                "requiresOverwrite": preview.requires_overwrite,
                                "writable": preview.token.is_some(),
                            });
                        }
                        None => state.state["failed"] = json!(true),
                    }
                    state.state_changed();
                });
            });
        }

        /// Starts the step that spends `token` (taken by `token_of`).
        fn run<T, F, Fut>(&self, token_of: T, step: F)
        where
            T: FnOnce(&PatchState) -> Option<u64> + 'static,
            F: FnOnce(
                    Rc<PatchService>,
                    SessionIdentity,
                    u64,
                    u64,
                    Rc<std::cell::RefCell<PatchState>>,
                ) -> Fut
                + 'static,
            Fut: std::future::Future<Output = ()> + 'static,
        {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let shared = Rc::clone(&driver.patches);
                let (identity, token, sequence) = {
                    let mut state = shared.borrow_mut();
                    let (Some(identity), Some(token)) = (state.identity, token_of(&state)) else {
                        return;
                    };
                    if state.state["busy"] == true || !services.patches.active(identity) {
                        return;
                    }
                    state.sequence += 1;
                    state.state["busy"] = json!(true);
                    state.state["failed"] = json!(false);
                    state.state_changed();
                    (identity, token, state.sequence)
                };
                rt::spawn_detached(step(
                    Rc::clone(&services.patches),
                    identity,
                    token,
                    sequence,
                    shared,
                ));
            });
        }
    }
}

pub use patch_state::PatchState;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sources_read_from_the_presentation() {
        assert_eq!(
            parse_source(&json!({"kind": "history"})),
            Some(Source::History { commit: None })
        );
        assert_eq!(
            parse_source(&json!({"kind": "history", "commit": "c"})),
            Some(Source::History {
                commit: Some("c".into())
            })
        );
        assert_eq!(
            parse_source(&json!({"kind": "diff", "base": "", "commit": "c", "paths": ["a"]})),
            Some(Source::Diff {
                base: None,
                commit: "c".into(),
                paths: vec![b"a".to_vec()]
            })
        );
        assert_eq!(
            parse_source(&json!({"kind": "files", "side": "staged", "paths": ["x"]})),
            Some(Source::Files {
                side: NativeStagingSide::Staged,
                paths: vec![b"x".to_vec()]
            })
        );
        assert_eq!(
            parse_source(&json!({"kind": "lines", "requestId": "7", "rows": ["r1"]})),
            Some(Source::Lines {
                request_id: 7,
                rows: vec!["r1".into()]
            })
        );
        assert_eq!(parse_source(&json!({"kind": "other"})), None);
    }
}
