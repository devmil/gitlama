//! The settings dialog's writes (the Dart SettingsService's setters):
//! automatic fetching, shortcuts and the per-repository reset. Appearance
//! writes go through the generic appearance patch.

use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::storage::NativeAutoFetchSettings;

use crate::auto_fetch::set_auto_fetch_override;
use crate::commands;
use crate::settings::SettingsService;

/// The intervals the settings offer, in minutes.
pub const AUTO_FETCH_INTERVALS: [u32; 5] = [5, 10, 15, 30, 60];
/// The diff context choices, in lines.
pub const CONTEXT_CHOICES: [u32; 4] = [0, 3, 6, 10];

/// Why a settings write was refused: an l10n key for the dialog's footer.
pub fn failure_key(code: commands::ShortcutFailure) -> &'static str {
    match code {
        commands::ShortcutFailure::Reserved => "settingsShortcutReserved",
        commands::ShortcutFailure::Conflict => "settingsShortcutConflict",
        _ => "settingsShortcutInvalid",
    }
}

pub fn update_auto_fetch(settings: &SettingsService, auto_fetch: NativeAutoFetchSettings) -> bool {
    settings.update(|document| document.auto_fetch = auto_fetch).is_ok()
}

/// Overrides automatic fetching for `repository`; None follows the
/// application.
pub fn set_repository_auto_fetch(settings: &SettingsService, repository: &NativePathIdentity, value: Option<bool>) -> bool {
    settings
        .update(|document| set_auto_fetch_override(document, repository, value))
        .is_ok()
}

/// Binds `command` to `input` (blank removes the binding) and saves at once;
/// Err is the l10n key of why not.
pub async fn set_shortcut(settings: &SettingsService, command: &str, input: &str, mac: bool) -> Result<(), &'static str> {
    let current = settings.with(|document| commands::without_retired(&document.shortcut_overrides));
    let overrides = commands::replace(&current, command, Some(input), mac).map_err(|error| failure_key(error.code))?;
    settings
        .update_durable(
            move |document| document.shortcut_overrides = overrides,
            |current, previous| current.shortcut_overrides = previous.shortcut_overrides.clone(),
        )
        .await
        .map_err(|_| "settingsSaveFailed")
}

pub async fn reset_shortcuts(settings: &SettingsService) -> Result<(), &'static str> {
    settings
        .update_durable(
            |document| document.shortcut_overrides.clear(),
            |current, previous| current.shortcut_overrides = previous.shortcut_overrides.clone(),
        )
        .await
        .map_err(|_| "settingsSaveFailed")
}

/// Forgets what is stored for `repository`: its automatic-fetch override
/// and its workspace state.
pub async fn reset_repository(settings: &SettingsService, repository: &NativePathIdentity) -> Result<(), &'static str> {
    let target = repository.clone();
    settings
        .update_durable(
            move |document| {
                set_auto_fetch_override(document, &target, None);
                document.worktrees.retain(|worktree| worktree.identity != target);
            },
            |current, previous| {
                current.repository_options = previous.repository_options.clone();
                current.worktrees = previous.worktrees.clone();
            },
        )
        .await
        .map_err(|_| "settingsSaveFailed")
}
