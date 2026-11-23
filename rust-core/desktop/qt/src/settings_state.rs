//! The settings dialog: what its Git page shows (automatic fetching, the
//! active repository), the last refused write and the licenses; slots for
//! the writes that are not appearance patches.

use crate::plumbing::Commands;
use gitlama_contract::storage::NativeAutoFetchSettings;
use gitlama_workbench::{auto_fetch, diagnostics, preferences, rt};
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;

const MAC: bool = cfg!(target_os = "macos");

/// The license documents GitLama ships, each under the package names the
/// license dialog lists.
const LICENSES: [(&[&str], &str); 6] = [
    (&["GitLama", "QSpline", "devmil-git"], include_str!("../../../../LICENSE")),
    (&["GitLama notices"], include_str!("../../../../THIRD_PARTY_NOTICES.md")),
    (&["JetBrains Mono"], include_str!("../../../../assets/fonts/OFL.txt")),
    (&["Qt"], include_str!("../../../../assets/licenses/QT-RUNTIME.md")),
    (&["Rust production dependencies"], include_str!("../../../../assets/licenses/RUST-DEPENDENCIES.md")),
    (&["Syntax grammars"], include_str!("../../../../assets/licenses/SYNTAX-GRAMMARS.md")),
];

/// The license dialog's packages: { name, licenses: [text, …] }, by name.
pub fn license_packages() -> Value {
    let mut packages: Vec<(String, Vec<&str>)> = Vec::new();
    for (names, text) in LICENSES {
        for name in names {
            match packages.iter_mut().find(|(existing, _)| existing == name) {
                Some((_, texts)) => texts.push(text),
                None => packages.push(((*name).to_owned(), vec![text])),
            }
        }
    }
    packages.sort_by_key(|(name, _)| name.to_lowercase());
    Value::Array(
        packages
            .into_iter()
            .map(|(name, licenses)| json!({"name": name, "licenses": licenses}))
            .collect(),
    )
}

/// Diagnostics schema 1 (devmil_logging's snapshot): app, version, platform,
/// the history's size, then its lines.
pub fn diagnostics_export(version: &str) -> String {
    let lines = diagnostics::snapshot();
    let bytes: usize = lines.iter().map(String::len).sum();
    format!(
        "Diagnostics schema 1\nApp: gitlama\nVersion: {}\nPlatform: {}\nMemory history: {} events, {} bytes\n\n{}",
        diagnostics::redact(version),
        std::env::consts::OS,
        lines.len(),
        bytes,
        lines.iter().map(|line| diagnostics::redact(line)).collect::<Vec<_>>().join("\n"),
    )
}

/// `%20` and friends of a file URL's path.
fn percent_decode(path: &str) -> String {
    let bytes = path.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%'
            && index + 2 < bytes.len()
            && let Ok(value) = u8::from_str_radix(&path[index + 1..index + 3], 16)
        {
            out.push(value);
            index += 3;
        } else {
            out.push(bytes[index]);
            index += 1;
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[qobject(ConvertToCamelCase)]
mod settings_state {
    use super::*;

    #[derive(Default)]
    pub struct SettingsState {
        pub commands: Option<Commands>,
        /// {autoFetch: {enabled, intervalMinutes}, intervals, contextChoices,
        /// repository: {label, autoFetch: "default"|"on"|"off", resettable}|null}.
        pub(crate) page: Value,
        /// The l10n key of the last refused write; "" when the last write
        /// succeeded.
        pub(crate) failure: String,
        /// The Custom commands page (tools.rs page_value).
        pub(crate) tools: Value,
        /// Git's status accelerators of the active session: {offer, settings}
        /// (acceleration.rs value).
        pub(crate) acceleration: Value,
        /// The diff renderer: {configured, result, card} (diff_renderer.rs value).
        pub(crate) renderer: Value,
    }

    impl SettingsState {
        qproperty!("page", Member = page, Notify = page_changed);
        qproperty!("failure", Member = failure, Notify = failure_changed);

        #[qsignal]
        pub fn page_changed(&mut self);
        #[qsignal]
        pub fn failure_changed(&mut self);

        qproperty!("acceleration", Member = acceleration, Notify = acceleration_changed);
        #[qsignal]
        pub fn acceleration_changed(&mut self);

        /// Status accelerators: `action` is read (for the settings), enable
        /// (from the offer), enableFromSettings or dismiss (the offer).
        #[qslot]
        fn status_acceleration(&self, action: String) {
            self.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let acceleration = Rc::clone(&services.acceleration);
                match action.as_str() {
                    "read" => rt::spawn_detached(async move { acceleration.read().await }),
                    "enable" => rt::spawn_detached(async move { acceleration.enable(false).await }),
                    "enableFromSettings" => rt::spawn_detached(async move { acceleration.enable(true).await }),
                    "dismiss" => acceleration.dismiss(),
                    _ => {}
                }
            });
        }

        qproperty!("renderer", Member = renderer, Notify = renderer_changed);
        #[qsignal]
        pub fn renderer_changed(&mut self);

        /// The diff renderer: `action` is render, useBuiltIn, save (id,
        /// title, executable, arguments) or remove.
        #[qslot]
        fn diff_renderer(&self, action: String, options: Value) {
            self.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let renderers = Rc::clone(&services.diff_renderers);
                let text = |key: &str| options[key].as_str().unwrap_or_default().to_owned();
                match action.as_str() {
                    "render" => rt::spawn_detached(async move { renderers.render().await }),
                    "useBuiltIn" => renderers.use_built_in(),
                    "remove" => rt::spawn_detached(async move { renderers.remove().await }),
                    "save" => {
                        let form = gitlama_workbench::diff_renderer::Form {
                            id: text("id"),
                            title: text("title"),
                            executable: text("executable"),
                            arguments: text("arguments"),
                        };
                        rt::spawn_detached(async move { renderers.save(form).await })
                    }
                    _ => {}
                }
            });
        }

        qproperty!("tools", Member = tools, Notify = tools_changed);
        #[qsignal]
        pub fn tools_changed(&mut self);

        /// The Custom commands page: `action` is open, runDiscovered
        /// (index), run or remove (id), or save (the form: id, kind,
        /// executable, arguments, explicitShell, wait, confirmation, timeout).
        #[qslot]
        fn tool(&self, action: String, options: Value) {
            self.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let tools = Rc::clone(&services.tools);
                let text = |key: &str| options[key].as_str().unwrap_or_default().to_owned();
                match action.as_str() {
                    "open" => rt::spawn_detached(async move { tools.open().await }),
                    "runDiscovered" => {
                        let index = options["index"].as_u64().unwrap_or(u64::MAX) as usize;
                        rt::spawn_detached(async move { tools.run_discovered(index).await })
                    }
                    "run" => {
                        let id = text("id");
                        rt::spawn_detached(async move { tools.run_configured(&id).await })
                    }
                    "remove" => {
                        let id = text("id");
                        rt::spawn_detached(async move { tools.remove(id).await })
                    }
                    "save" => {
                        let form = gitlama_workbench::tools::Form {
                            id: text("id"),
                            kind: text("kind"),
                            executable: text("executable"),
                            arguments: text("arguments"),
                            explicit_shell: options["explicitShell"].as_bool() == Some(true),
                            wait: options["wait"].as_bool() != Some(false),
                            confirmation: options["confirmation"].as_bool() != Some(false),
                            timeout: text("timeout"),
                        };
                        rt::spawn_detached(async move { tools.save(form).await })
                    }
                    _ => {}
                }
            });
        }

        /// `value` is {enabled?, intervalMinutes?}.
        #[qslot]
        fn update_auto_fetch(&self, value: Value) {
            self.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let current = services.settings.with(|document| document.auto_fetch.clone());
                let next = NativeAutoFetchSettings {
                    enabled: value["enabled"].as_bool().unwrap_or(current.enabled),
                    interval_minutes: value["intervalMinutes"]
                        .as_u64()
                        .and_then(|minutes| u32::try_from(minutes).ok())
                        .filter(|minutes| *minutes > 0)
                        .unwrap_or(current.interval_minutes),
                };
                let saved = preferences::update_auto_fetch(&services.settings, next);
                driver.settings_result(if saved { "" } else { "settingsSaveFailed" });
            });
        }

        /// `value` is "default", "on" or "off" for the active repository.
        #[qslot]
        fn set_repository_auto_fetch(&self, value: String) {
            self.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(repository) = services.workspace.active_canonical() else { return };
                let choice = match value.as_str() {
                    "on" => Some(true),
                    "off" => Some(false),
                    _ => None,
                };
                let saved = preferences::set_repository_auto_fetch(&services.settings, &repository, choice);
                driver.settings_result(if saved { "" } else { "settingsSaveFailed" });
            });
        }

        /// Binds `command` to `binding` (`Ctrl+Shift+P`); blank unbinds.
        #[qslot]
        fn set_shortcut(&self, command: String, binding: String) {
            self.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let settings = Rc::clone(&services.settings);
                let state = Rc::clone(&driver.settings);
                rt::spawn_detached(async move {
                    let result = preferences::set_shortcut(&settings, &command, &binding, MAC).await;
                    crate::driver::show_settings_result(&state, result.err().unwrap_or(""));
                });
            });
        }

        #[qslot]
        fn reset_shortcuts(&self) {
            self.post(|driver| {
                let Some(services) = driver.app.services() else { return };
                let settings = Rc::clone(&services.settings);
                let state = Rc::clone(&driver.settings);
                rt::spawn_detached(async move {
                    let result = preferences::reset_shortcuts(&settings).await;
                    crate::driver::show_settings_result(&state, result.err().unwrap_or(""));
                });
            });
        }

        /// Forgets the active repository's stored settings (asked first by
        /// the dialog).
        #[qslot]
        fn reset_repository(&self) {
            self.post(|driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(repository) = services.workspace.active_canonical() else { return };
                let settings = Rc::clone(&services.settings);
                let state = Rc::clone(&driver.settings);
                rt::spawn_detached(async move {
                    let result = preferences::reset_repository(&settings, &repository).await;
                    crate::driver::show_settings_result(&state, result.err().unwrap_or(""));
                });
            });
        }

        /// Shows `key` (an l10n key) as the refused write; "" clears it.
        #[qslot]
        fn show_failure(&mut self, key: String) {
            if self.failure != key {
                self.failure = key;
                self.failure_changed();
            }
        }

        #[qslot]
        fn licenses(&self) -> Value {
            license_packages()
        }

        /// Whether detailed diagnostic capture is on now.
        #[qslot]
        fn diagnostics_detailed(&self) -> bool {
            diagnostics::detailed_remaining().is_some()
        }

        #[qslot]
        fn set_diagnostics_detailed(&self, enabled: bool) {
            diagnostics::set_detailed(enabled);
        }

        #[qslot]
        fn clear_diagnostics(&self) {
            diagnostics::clear();
        }

        /// The export as it would be saved: a header, then the safe history.
        #[qslot]
        fn diagnostics_preview(&self, version: String) -> String {
            diagnostics_export(&version)
        }

        /// Writes `text` to the file `url` names; false when it could not.
        #[qslot]
        fn save_diagnostics(&self, url: String, text: String) -> bool {
            let mut path = url.strip_prefix("file://").map(percent_decode).unwrap_or(url);
            // file:///C:/… on Windows.
            if cfg!(windows) && path.as_bytes().get(2) == Some(&b':') && path.starts_with('/') {
                path.remove(0);
            }
            let saved = std::fs::write(&path, text).is_ok();
            diagnostics::info("Diagnostics", if saved { "diagnostics_saved" } else { "diagnostics_save_failed" }, &[]);
            saved
        }
    }

    impl SettingsState {
        pub(crate) fn post(&self, command: impl FnOnce(&crate::driver::Driver) + 'static) {
            if let Some(commands) = &self.commands {
                commands.post(command);
            }
        }
    }
}

pub use settings_state::SettingsState;

/// The Git page's projection.
pub fn project(services: &gitlama_workbench::app::Services) -> Value {
    let repository = services.workspace.active_tab().and_then(|tab| {
        let canonical = tab.canonical_identity()?.clone();
        Some((tab.label.clone(), canonical))
    });
    services.settings.with(|document| {
        let interval = document.auto_fetch.interval_minutes;
        let mut intervals: Vec<u32> = preferences::AUTO_FETCH_INTERVALS.to_vec();
        if !intervals.contains(&interval) {
            intervals.push(interval);
            intervals.sort_unstable();
        }
        json!({
            "autoFetch": {"enabled": document.auto_fetch.enabled, "intervalMinutes": interval},
            "intervals": intervals,
            "contextChoices": preferences::CONTEXT_CHOICES,
            "repository": repository.map(|(label, canonical)| json!({
                "label": label,
                "autoFetch": match auto_fetch::auto_fetch_override(document, &canonical) {
                    Some(true) => "on",
                    Some(false) => "off",
                    None => "default",
                },
                "remote": canonical.remote.is_some(),
            })),
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_license_document_is_listed_once_per_package() {
        let packages = license_packages();
        let names: Vec<&str> = packages.as_array().unwrap().iter().map(|package| package["name"].as_str().unwrap()).collect();
        assert_eq!(names.len(), 8);
        assert!(names.contains(&"Qt"));
        assert!(packages.as_array().unwrap().iter().all(|package| !package["licenses"][0].as_str().unwrap().is_empty()));
    }

    #[test]
    fn a_file_url_decodes_to_its_path() {
        assert_eq!(percent_decode("/tmp/a%20b.txt"), "/tmp/a b.txt");
        assert_eq!(percent_decode("/tmp/%zz"), "/tmp/%zz");
    }

    #[test]
    fn the_export_starts_with_its_schema_header() {
        let text = diagnostics_export("1.0");
        assert!(text.starts_with("Diagnostics schema 1\nApp: gitlama\nVersion: 1.0\n"));
    }
}
