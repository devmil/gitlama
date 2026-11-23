//! GitLama's commands (the Dart `AppCommandRegistry`) and keyboard shortcuts
//! (`AppShortcutCatalog`). The registry in `data/commands.json` is the one
//! source the toolbar, menus, palette, shortcuts and settings read.

use gitlama_contract::storage::NativeShortcutOverride;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;

pub const SCOPES: [&str; 7] = [
    "global", "changes", "history", "diff", "conflict", "rebase", "sidebar",
];

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandDefinition {
    pub id: String,
    /// The localization key of the command's name.
    pub label: String,
    pub group: String,
    pub icon: String,
    /// The default binding on Windows and Linux.
    pub shortcut: Option<String>,
    /// The default binding on macOS; `shortcut` when absent.
    pub mac_shortcut: Option<String>,
    /// A key a focused list handles for this command itself; never bound
    /// globally.
    pub key_hint: Option<String>,
    pub scopes: Vec<String>,
    pub requires_repository: bool,
    pub available: bool,
    pub destructive: bool,
    /// How the command relates to a repository on another computer (view,
    /// read, stage, commit, refs, stash, transfer, discard, history,
    /// recovery, extensions, unsupported).
    pub remote: String,
}

impl CommandDefinition {
    pub fn default_shortcut(&self, mac: bool) -> Option<&str> {
        if mac {
            self.mac_shortcut.as_deref().or(self.shortcut.as_deref())
        } else {
            self.shortcut.as_deref()
        }
    }

    pub fn is_global(&self) -> bool {
        self.scopes.iter().any(|scope| scope == "global")
    }
}

#[derive(Deserialize)]
struct Registry {
    commands: Vec<CommandDefinition>,
}

/// Every command, in the palette's order.
pub fn registry() -> &'static [CommandDefinition] {
    static REGISTRY: OnceLock<Vec<CommandDefinition>> = OnceLock::new();
    REGISTRY.get_or_init(|| {
        serde_json::from_str::<Registry>(include_str!("../data/commands.json"))
            .expect("the command registry is valid")
            .commands
    })
}

pub fn by_id(id: &str) -> Option<&'static CommandDefinition> {
    registry().iter().find(|command| command.id == id)
}

/// Commands that were removed; loading drops their overrides (ADR 0005).
pub const RETIRED_COMMAND_IDS: [&str; 3] = ["undo", "redo", "showRecovery"];
pub const MAXIMUM_OVERRIDES: usize = 512;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShortcutFailure {
    Invalid,
    Reserved,
    UnknownCommand,
    DuplicateOverride,
    Conflict,
    TooManyOverrides,
}

impl ShortcutFailure {
    pub fn name(self) -> &'static str {
        match self {
            Self::Invalid => "invalid",
            Self::Reserved => "reserved",
            Self::UnknownCommand => "unknownCommand",
            Self::DuplicateOverride => "duplicateOverride",
            Self::Conflict => "conflict",
            Self::TooManyOverrides => "tooManyOverrides",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShortcutError {
    pub code: ShortcutFailure,
    pub command: Option<String>,
    pub conflicting_command: Option<String>,
}

impl ShortcutError {
    fn new(code: ShortcutFailure) -> Self {
        Self {
            code,
            command: None,
            conflicting_command: None,
        }
    }
}

/// A parsed key combination.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Shortcut {
    /// `Ctrl+Shift+P`: modifiers in Ctrl, Cmd, Alt, Shift order, then the key.
    pub canonical: String,
    pub key: String,
    pub control: bool,
    pub meta: bool,
    pub alt: bool,
    pub shift: bool,
}

impl Shortcut {
    pub fn parse(input: &str) -> Result<Self, ShortcutError> {
        let invalid = || ShortcutError::new(ShortcutFailure::Invalid);
        if input.is_empty() || input.chars().count() > 64 || input.trim() != input {
            return Err(invalid());
        }
        let parts: Vec<&str> = input.split('+').collect();
        if parts.iter().any(|part| part.is_empty()) {
            return Err(invalid());
        }
        let key_token = parts[parts.len() - 1];
        let mut modifiers: HashSet<&'static str> = HashSet::new();
        for raw in &parts[..parts.len() - 1] {
            let modifier = match raw.to_lowercase().as_str() {
                "ctrl" | "control" => "Ctrl",
                "cmd" | "command" | "meta" => "Cmd",
                "alt" | "option" => "Alt",
                "shift" => "Shift",
                _ => return Err(invalid()),
            };
            if !modifiers.insert(modifier) {
                return Err(invalid());
            }
        }
        if modifiers.contains("Ctrl") && modifiers.contains("Cmd") {
            return Err(invalid());
        }
        let key = parse_key(key_token).ok_or_else(invalid)?;
        let question = key == "?";
        if question {
            modifiers.insert("Shift");
        }
        if (modifiers.contains("Alt") && key == "F4")
            || (modifiers.contains("Ctrl") && key == "Q")
            || (modifiers.contains("Cmd") && key == "Q")
        {
            return Err(ShortcutError::new(ShortcutFailure::Reserved));
        }
        let mut canonical: Vec<&str> = ["Ctrl", "Cmd", "Alt", "Shift"]
            .into_iter()
            .filter(|modifier| modifiers.contains(modifier))
            .collect();
        if question {
            canonical.retain(|modifier| *modifier != "Shift");
        }
        canonical.push(&key);
        Ok(Self {
            canonical: canonical.join("+"),
            control: modifiers.contains("Ctrl"),
            meta: modifiers.contains("Cmd"),
            alt: modifiers.contains("Alt"),
            shift: modifiers.contains("Shift"),
            key,
        })
    }

    /// The Qt key sequence of this shortcut (`Ctrl+Shift+P`; Cmd is `Meta`
    /// in Qt terms only on macOS where Qt maps Ctrl to Command).
    pub fn qt_sequence(&self, mac: bool) -> String {
        let mut parts: Vec<String> = Vec::new();
        // On macOS Qt's "Ctrl" is the Command key and "Meta" is Control.
        if self.control {
            parts.push(if mac { "Meta".into() } else { "Ctrl".into() });
        }
        if self.meta {
            parts.push(if mac { "Ctrl".into() } else { "Meta".into() });
        }
        if self.alt {
            parts.push("Alt".into());
        }
        if self.shift && self.key != "?" {
            parts.push("Shift".into());
        }
        parts.push(match self.key.as_str() {
            "Enter" => "Return".into(),
            other => other.into(),
        });
        parts.join("+")
    }
}

fn parse_key(value: &str) -> Option<String> {
    let normalized = if value.chars().count() == 1 {
        value.to_uppercase()
    } else {
        value.to_owned()
    };
    let named = match normalized.to_lowercase().as_str() {
        "enter" => Some("Enter"),
        "space" => Some("Space"),
        "tab" => Some("Tab"),
        "up" => Some("Up"),
        "down" => Some("Down"),
        "left" => Some("Left"),
        "right" => Some("Right"),
        "insert" => Some("Insert"),
        "?" => Some("?"),
        "," => Some(","),
        "/" => Some("/"),
        "[" => Some("["),
        "]" => Some("]"),
        _ => None,
    };
    if let Some(named) = named {
        return Some(named.to_owned());
    }
    if normalized.len() == 1 {
        let byte = normalized.as_bytes()[0];
        if byte.is_ascii_uppercase() || byte.is_ascii_digit() {
            return Some(normalized);
        }
    }
    let lower = normalized.to_lowercase();
    if let Some(number) = lower.strip_prefix('f')
        && let Ok(number) = number.parse::<u32>()
        && (1..=24).contains(&number)
        && !number.to_string().starts_with('0')
        && number.to_string() == lower[1..]
    {
        return Some(format!("F{number}"));
    }
    None
}

/// The shortcut each command has: its default unless overridden, validated
/// for conflicts within every scope.
pub fn resolve(
    overrides: &[NativeShortcutOverride],
    mac: bool,
) -> Result<HashMap<String, Option<Shortcut>>, ShortcutError> {
    if overrides.len() > MAXIMUM_OVERRIDES {
        return Err(ShortcutError::new(ShortcutFailure::TooManyOverrides));
    }
    let mut bindings: HashMap<String, Option<Shortcut>> = HashMap::new();
    for command in registry() {
        let parsed = command
            .default_shortcut(mac)
            .map(Shortcut::parse)
            .transpose()?;
        bindings.insert(command.id.clone(), parsed);
    }
    let mut seen = HashSet::new();
    for entry in overrides {
        if by_id(&entry.command_id).is_none() {
            return Err(ShortcutError::new(ShortcutFailure::UnknownCommand));
        }
        if !seen.insert(entry.command_id.clone()) {
            return Err(ShortcutError {
                code: ShortcutFailure::DuplicateOverride,
                command: Some(entry.command_id.clone()),
                conflicting_command: None,
            });
        }
        let parsed = match &entry.binding {
            None => None,
            Some(binding) => Some(Shortcut::parse(binding).map_err(|error| ShortcutError {
                code: error.code,
                command: Some(entry.command_id.clone()),
                conflicting_command: None,
            })?),
        };
        bindings.insert(entry.command_id.clone(), parsed);
    }
    for scope in SCOPES {
        let mut claimed: HashMap<&str, &str> = HashMap::new();
        for command in registry() {
            if !command.is_global() && !command.scopes.iter().any(|value| value == scope) {
                continue;
            }
            let Some(Some(shortcut)) = bindings.get(&command.id) else {
                continue;
            };
            if let Some(previous) = claimed.get(shortcut.canonical.as_str()) {
                return Err(ShortcutError {
                    code: ShortcutFailure::Conflict,
                    command: Some(command.id.clone()),
                    conflicting_command: Some((*previous).to_owned()),
                });
            }
            claimed.insert(&shortcut.canonical, &command.id);
        }
    }
    Ok(bindings)
}

/// The shortcut each command shows: its binding, or its list key hint unless
/// the user overrode the command.
pub fn shown(
    overrides: &[NativeShortcutOverride],
    mac: bool,
) -> Result<HashMap<String, Option<Shortcut>>, ShortcutError> {
    let overridden: HashSet<&str> = overrides
        .iter()
        .map(|entry| entry.command_id.as_str())
        .collect();
    let mut resolved = resolve(overrides, mac)?;
    for command in registry() {
        let entry = resolved.entry(command.id.clone()).or_insert(None);
        if entry.is_none()
            && !overridden.contains(command.id.as_str())
            && let Some(hint) = &command.key_hint
        {
            *entry = Shortcut::parse(hint).ok();
        }
    }
    Ok(resolved)
}

/// `overrides` with `command` bound to `input` (None or blank removes the
/// binding), validated.
pub fn replace(
    overrides: &[NativeShortcutOverride],
    command: &str,
    input: Option<&str>,
    mac: bool,
) -> Result<Vec<NativeShortcutOverride>, ShortcutError> {
    let normalized = match input.map(str::trim).filter(|value| !value.is_empty()) {
        None => None,
        Some(value) => Some(Shortcut::parse(value)?.canonical),
    };
    let mut next: Vec<NativeShortcutOverride> = overrides
        .iter()
        .filter(|entry| entry.command_id != command)
        .cloned()
        .collect();
    next.push(NativeShortcutOverride {
        command_id: command.to_owned(),
        binding: normalized,
    });
    resolve(&next, mac)?;
    Ok(next)
}

/// Drops overrides of retired commands (as loading did in the Flutter
/// application).
pub fn without_retired(overrides: &[NativeShortcutOverride]) -> Vec<NativeShortcutOverride> {
    overrides
        .iter()
        .filter(|entry| !RETIRED_COMMAND_IDS.contains(&entry.command_id.as_str()))
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_registry_has_every_command_once() {
        let ids: HashSet<&str> = registry()
            .iter()
            .map(|command| command.id.as_str())
            .collect();
        assert_eq!(ids.len(), registry().len());
        assert_eq!(registry().len(), 104);
    }

    #[test]
    fn defaults_resolve_without_conflicts_on_both_platforms() {
        resolve(&[], true).unwrap();
        let bindings = resolve(&[], false).unwrap();
        assert_eq!(
            bindings["fetch"].as_ref().unwrap().canonical,
            "Ctrl+Shift+K"
        );
    }

    #[test]
    fn parsing_canonicalizes_and_rejects_reserved_keys() {
        assert_eq!(
            Shortcut::parse("shift+ctrl+p").unwrap().canonical,
            "Ctrl+Shift+P"
        );
        assert_eq!(Shortcut::parse("?").unwrap().canonical, "?");
        assert_eq!(Shortcut::parse("f12").unwrap().canonical, "F12");
        assert_eq!(
            Shortcut::parse("Ctrl+Q").unwrap_err().code,
            ShortcutFailure::Reserved
        );
        assert_eq!(
            Shortcut::parse("Ctrl+Cmd+A").unwrap_err().code,
            ShortcutFailure::Invalid
        );
        assert_eq!(
            Shortcut::parse("F25").unwrap_err().code,
            ShortcutFailure::Invalid
        );
    }

    #[test]
    fn an_override_that_conflicts_is_refused() {
        let error = replace(&[], "push", Some("Ctrl+Shift+K"), false).unwrap_err();
        assert_eq!(error.code, ShortcutFailure::Conflict);
        let ok = replace(&[], "push", Some("Ctrl+Shift+U"), false).unwrap();
        assert_eq!(ok[0].binding.as_deref(), Some("Ctrl+Shift+U"));
    }

    #[test]
    fn qt_sequences_swap_control_and_command_on_macos() {
        let shortcut = Shortcut::parse("Cmd+Shift+P").unwrap();
        assert_eq!(shortcut.qt_sequence(true), "Ctrl+Shift+P");
        let shortcut = Shortcut::parse("Ctrl+Enter").unwrap();
        assert_eq!(shortcut.qt_sequence(false), "Ctrl+Return");
    }
}
