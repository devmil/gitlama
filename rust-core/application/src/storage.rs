//! Versioned, atomic application settings and workspace persistence.
pub use gitlama_contract::storage::*;

use crate::diff_renderer::NativeDiffRendererSettings;
use crate::domain::path_identity::valid_account_uid;
use crate::domain::path_identity::valid_profile_id;
use crate::domain::path_identity::valid_remote_authority;
use crate::domain::path_identity::valid_store_id;
use crate::domain::path_identity::PathIdentityLocation;
use crate::dto::NativePathIdentity;
use crate::dto::NativePathPlatform;
use crate::hosting_settings::NativeHostingBindingSettings;
use crate::hosting_settings::NativeHostingConnectionSettings;
use crate::integrations::NativeIntegrationSettings;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions, TryLockError};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

const CURRENT_SCHEMA: u32 = 13;
/// The first schema that can hold remote workspace identities and profiles.
const REMOTE_SCHEMA: u64 = 13;
const MAX_DOCUMENT_BYTES: u64 = 16 * 1024 * 1024;
const MAX_WORKTREES: usize = 1000;
const MAX_OPEN_WORKTREES: usize = 100;
const MAX_DRAFT_BYTES: usize = 1024 * 1024;
const MAX_INTEGRATIONS: usize = 64;
const MAX_HOSTING_CONNECTIONS: usize = 32;
const MAX_HOSTING_BINDINGS: usize = 1000;
const MAX_SHORTCUT_OVERRIDES: usize = 512;
const MAX_REPOSITORY_APPEARANCES: usize = 1000;
const MAX_REPOSITORY_OPTIONS: usize = 1000;
const MAX_TAB_GROUPS: usize = 64;
const MAX_TAB_NAME_BYTES: usize = 256;
const MAX_AUTO_FETCH_MINUTES: u32 = 24 * 60;
const MAX_REMOTE_PROFILES: usize = 64;
const MAX_REMOTE_PROFILE_TEXT: usize = 128;
const MAX_REMOTE_ACCOUNT_NAME_BYTES: usize = 128;
/// Decoded native bytes of a remote path, matching the wire contract.
const MAX_REMOTE_PATH_BYTES: usize = crate::domain::limits::PATH_BYTES;
static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(1);

// Stored appearance and workspace names. Dart writes the same lists, and
// `test/fixtures/settings_storage_names.json` holds both sides to them.
const THEMES: [&str; 3] = ["system", "light", "dark"];
const DENSITIES: [&str; 3] = ["compact", "regular", "comfortable"];
const REDUCE_MOTION: [&str; 3] = ["followSystem", "reduce", "full"];
const FILE_LAYOUTS: [&str; 2] = ["list", "tree"];
const INSPECTION_OPEN_IN: [&str; 2] = ["pane", "window"];
const DIFF_LAYOUTS: [&str; 2] = ["unified", "sideBySide"];
const DIFF_WHITESPACE: [&str; 4] = ["preserve", "ignoreAll", "ignoreAmount", "ignoreEndOfLine"];
const MAX_DIFF_CONTEXT_LINES: u32 = 100;
const RELEASE_CHANNELS: [&str; 2] = ["stable", "beta"];
const WORKTREE_PANES: [&str; 2] = ["changes", "history"];
const WORKTREE_ROUTES: [&str; 5] = ["repository", "commit", "file", "blame", "operation"];

/// Maps the reduce-motion names an earlier core accepted, but that the
/// application never wrote, to the names it does write.
fn migrate_reduce_motion(value: String) -> String {
    match value.as_str() {
        "enabled" => "reduce".into(),
        "disabled" => "full".into(),
        _ => value,
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SettingsDto {
    schema_version: u32,
    #[serde(default)]
    appearance: AppearanceDto,
    #[serde(default)]
    recent_repositories: Vec<NativePathIdentity>,
    #[serde(default)]
    worktrees: Vec<WorktreeDto>,
    #[serde(default)]
    open_worktrees: Vec<NativePathIdentity>,
    #[serde(default)]
    active_worktree: Option<NativePathIdentity>,
    #[serde(default)]
    integrations: Vec<NativeIntegrationSettings>,
    #[serde(default)]
    diff_renderer: Option<NativeDiffRendererSettings>,
    #[serde(default)]
    hosting_connections: Vec<NativeHostingConnectionSettings>,
    #[serde(default)]
    hosting_bindings: Vec<NativeHostingBindingSettings>,
    #[serde(default)]
    hosting_expanded_nodes: Vec<String>,
    #[serde(default)]
    shortcut_overrides: Vec<NativeShortcutOverride>,
    #[serde(default)]
    repository_appearances: Vec<NativeRepositoryAppearance>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    release_channel: Option<String>,
    #[serde(default)]
    auto_fetch: NativeAutoFetchSettings,
    #[serde(default)]
    repository_options: Vec<NativeRepositoryOptions>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    tab_groups: Vec<NativeTabGroup>,
    #[serde(default)]
    remote_profiles: Vec<NativeRemoteHostProfile>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    remote_workspaces_enabled: bool,
}

#[derive(Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct AppearanceDto {
    theme: String,
    density: String,
    reduce_motion: String,
    date_format: String,
    gravatar_enabled: bool,
    sidebar_width: u32,
    diff_width: u32,
    changes_unstaged_mode: String,
    changes_staged_mode: String,
    changes_split_ratio: u32,
    commit_files_mode: String,
    inspection_open_in: String,
    diff_wrap: bool,
    diff_layout: String,
    diff_whitespace: String,
    diff_context_lines: u32,
    diff_indicators: bool,
    diff_minimap: bool,
    history_other_refs: bool,
    window_x: Option<i32>,
    window_y: Option<i32>,
    window_width: Option<u32>,
    window_height: Option<u32>,
    window_maximized: bool,
}

impl Default for AppearanceDto {
    fn default() -> Self {
        NativeAppearanceSettings::default().into()
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorktreeDto {
    identity: NativePathIdentity,
    #[serde(default)]
    filter: String,
    #[serde(default)]
    anchor: Option<String>,
    #[serde(default = "default_workspace_pane")]
    pane: String,
    #[serde(default = "default_workspace_route")]
    route: String,
    #[serde(default)]
    changes_scroll_offset: u64,
    #[serde(default)]
    history_scroll_offset: u64,
    #[serde(default)]
    draft: DraftDto,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    branch_filter: Vec<String>,
}

fn default_workspace_pane() -> String {
    "changes".into()
}

fn default_workspace_route() -> String {
    "repository".into()
}

#[derive(Default, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct DraftDto {
    subject: String,
    description: String,
}

pub fn settings_load(path: String) -> NativeSettingsLoadResult {
    match load_from(Path::new(&path)) {
        Ok((state, document)) => NativeSettingsLoadResult {
            state,
            document: Some(document),
            failure: None,
        },
        Err(kind) => load_failure(kind),
    }
}

pub fn settings_default_path() -> NativeSettingsPathResult {
    let profile_root = std::env::var_os("GITLAMA_PROFILE_ROOT")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from);
    let platform_base = if cfg!(target_os = "windows") {
        std::env::var_os("APPDATA").map(PathBuf::from)
    } else if cfg!(target_os = "macos") {
        std::env::var_os("HOME")
            .map(PathBuf::from)
            .map(|home| home.join("Library/Application Support"))
    } else {
        std::env::var_os("XDG_CONFIG_HOME")
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .or_else(|| {
                std::env::var_os("HOME")
                    .filter(|value| !value.is_empty())
                    .map(PathBuf::from)
                    .map(|home| home.join(".config"))
            })
    };
    let application = if cfg!(target_os = "linux") {
        "gitlama"
    } else {
        "GitLama"
    };
    let Some(path) = default_settings_path(profile_root, platform_base, application) else {
        return NativeSettingsPathResult {
            path: None,
            failure: Some(NativeSettingsFailure {
                kind: NativeSettingsFailureKind::Io,
                rule: None,
            }),
        };
    };
    match path.into_os_string().into_string() {
        Ok(path) => NativeSettingsPathResult {
            path: Some(path),
            failure: None,
        },
        Err(_) => NativeSettingsPathResult {
            path: None,
            failure: Some(NativeSettingsFailure {
                kind: NativeSettingsFailureKind::Io,
                rule: None,
            }),
        },
    }
}

fn default_settings_path(
    profile_root: Option<PathBuf>,
    platform_base: Option<PathBuf>,
    application: &str,
) -> Option<PathBuf> {
    match profile_root {
        Some(root) if root.is_absolute() => Some(root.join("settings.json")),
        Some(_) => None,
        None => platform_base.map(|base| base.join(application).join("settings.json")),
    }
}

pub fn settings_save(path: String, document: NativeSettingsDocument) -> NativeSettingsSaveResult {
    match save_to(Path::new(&path), &document) {
        Ok(()) => NativeSettingsSaveResult {
            saved: true,
            failure: None,
        },
        Err(kind) => NativeSettingsSaveResult {
            saved: false,
            failure: Some(NativeSettingsFailure {
                kind,
                rule: (kind == NativeSettingsFailureKind::InvalidDocument)
                    .then(|| validation_failure(&document))
                    .flatten()
                    .map(str::to_owned),
            }),
        },
    }
}

fn load_from(
    path: &Path,
) -> Result<(NativeSettingsLoadState, NativeSettingsDocument), NativeSettingsFailureKind> {
    let backup = sibling(path, ".backup");
    let mut state = NativeSettingsLoadState::Loaded;
    if !path.exists() && backup.exists() {
        fs::rename(&backup, path).map_err(map_io)?;
        sync_parent(path)?;
        state = NativeSettingsLoadState::RestoredBackup;
    }
    if !path.exists() {
        return Ok((
            NativeSettingsLoadState::Absent,
            NativeSettingsDocument::default(),
        ));
    }
    let metadata = fs::metadata(path).map_err(map_read)?;
    if metadata.len() > MAX_DOCUMENT_BYTES {
        preserve_corrupt(path)?;
        return Ok((
            NativeSettingsLoadState::RecoveredCorrupt,
            NativeSettingsDocument::default(),
        ));
    }
    let mut bytes = Vec::with_capacity(usize::try_from(metadata.len()).unwrap_or(0));
    File::open(path)
        .and_then(|mut file| file.read_to_end(&mut bytes))
        .map_err(map_read)?;
    let value: serde_json::Value = match serde_json::from_slice(&bytes) {
        Ok(value) => value,
        Err(_) => {
            preserve_corrupt(path)?;
            return Ok((
                NativeSettingsLoadState::RecoveredCorrupt,
                NativeSettingsDocument::default(),
            ));
        }
    };
    let version = value
        .get("schemaVersion")
        .and_then(serde_json::Value::as_u64)
        .ok_or(NativeSettingsFailureKind::InvalidDocument)?;
    if version > u64::from(CURRENT_SCHEMA) {
        return Err(NativeSettingsFailureKind::UnsupportedSchema);
    }
    if version == 0 {
        return Err(NativeSettingsFailureKind::UnsupportedSchema);
    }
    let dto: SettingsDto = match serde_json::from_value(value) {
        Ok(dto) => dto,
        Err(_) => {
            preserve_corrupt(path)?;
            return Ok((
                NativeSettingsLoadState::RecoveredCorrupt,
                NativeSettingsDocument::default(),
            ));
        }
    };
    let document = NativeSettingsDocument::try_from(dto)
        .map_err(|()| NativeSettingsFailureKind::InvalidDocument)?;
    // Older schemas only ever held local paths. Remote data there is not a
    // migration input, and must not be accepted as if it had been written.
    if version < REMOTE_SCHEMA && holds_remote_data(&document) {
        return Err(NativeSettingsFailureKind::InvalidDocument);
    }
    if state == NativeSettingsLoadState::Loaded && version < u64::from(CURRENT_SCHEMA) {
        state = NativeSettingsLoadState::Migrated;
    }
    Ok((state, document))
}

fn save_to(
    path: &Path,
    document: &NativeSettingsDocument,
) -> Result<(), NativeSettingsFailureKind> {
    save_to_with_writer(path, document, |file, bytes| file.write_all(bytes))
}

fn save_to_with_writer(
    path: &Path,
    document: &NativeSettingsDocument,
    write: impl FnOnce(&mut File, &[u8]) -> std::io::Result<()>,
) -> Result<(), NativeSettingsFailureKind> {
    validate(document).map_err(|()| NativeSettingsFailureKind::InvalidDocument)?;
    let parent = path.parent().ok_or(NativeSettingsFailureKind::Io)?;
    fs::create_dir_all(parent).map_err(map_io)?;
    let lock_path = sibling(path, ".lock");
    let _lock = SettingsLock::acquire(&lock_path)?;
    let dto = SettingsDto::from(document);
    let mut bytes =
        serde_json::to_vec_pretty(&dto).map_err(|_| NativeSettingsFailureKind::InvalidDocument)?;
    bytes.push(b'\n');
    if bytes.len() as u64 > MAX_DOCUMENT_BYTES {
        return Err(NativeSettingsFailureKind::InvalidDocument);
    }
    let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    let temporary = sibling(path, &format!(".tmp.{}.{sequence}", std::process::id()));
    let backup = sibling(path, ".backup");
    let result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)
            .map_err(map_io)?;
        write(&mut file, &bytes).map_err(map_io)?;
        file.flush().map_err(map_io)?;
        file.sync_all().map_err(map_io)?;
        drop(file);
        if path.exists() {
            if backup.exists() {
                fs::remove_file(&backup).map_err(map_io)?;
            }
            fs::rename(path, &backup).map_err(map_io)?;
        }
        if let Err(error) = fs::rename(&temporary, path) {
            if backup.exists() && !path.exists() {
                let _ = fs::rename(&backup, path);
            }
            return Err(map_io(error));
        }
        sync_parent(path)?;
        if backup.exists() {
            fs::remove_file(&backup).map_err(map_io)?;
            sync_parent(path)?;
        }
        Ok(())
    })();
    if temporary.exists() {
        let _ = fs::remove_file(temporary);
    }
    result
}

pub(crate) fn validate(document: &NativeSettingsDocument) -> Result<(), ()> {
    validation_failure(document).map_or(Ok(()), |_| Err(()))
}

/// The stable name of the first rule [document] breaks, if any. Names carry
/// no user content, so they may be shown and logged.
pub(crate) fn validation_failure(document: &NativeSettingsDocument) -> Option<&'static str> {
    check(document).err()
}

fn check(document: &NativeSettingsDocument) -> Result<(), &'static str> {
    validate_remote(document)?;
    if document.worktrees.len() > MAX_WORKTREES
        || document.open_worktrees.len() > MAX_OPEN_WORKTREES
        || document.recent_repositories.len() > 100
        || document.integrations.len() > MAX_INTEGRATIONS
        || document.hosting_connections.len() > MAX_HOSTING_CONNECTIONS
        || document.hosting_bindings.len() > MAX_HOSTING_BINDINGS
        || document.hosting_expanded_nodes.len() > 256
        || document.shortcut_overrides.len() > MAX_SHORTCUT_OVERRIDES
        || document.repository_appearances.len() > MAX_REPOSITORY_APPEARANCES
    {
        return Err("limits");
    }
    if !valid_window_geometry(&document.appearance) {
        return Err("window_geometry");
    }
    if document.appearance.sidebar_width > 4096
        || document.appearance.diff_width > 8192
        || !(100..=900).contains(&document.appearance.changes_split_ratio)
        || !FILE_LAYOUTS.contains(&document.appearance.changes_unstaged_mode.as_str())
        || !FILE_LAYOUTS.contains(&document.appearance.changes_staged_mode.as_str())
        || !FILE_LAYOUTS.contains(&document.appearance.commit_files_mode.as_str())
        || !INSPECTION_OPEN_IN.contains(&document.appearance.inspection_open_in.as_str())
        || !DIFF_LAYOUTS.contains(&document.appearance.diff_layout.as_str())
        || !DIFF_WHITESPACE.contains(&document.appearance.diff_whitespace.as_str())
        || document.appearance.diff_context_lines > MAX_DIFF_CONTEXT_LINES
        || !THEMES.contains(&document.appearance.theme.as_str())
        || !DENSITIES.contains(&document.appearance.density.as_str())
        || !REDUCE_MOTION.contains(&document.appearance.reduce_motion.as_str())
    {
        return Err("appearance");
    }
    if document
        .release_channel
        .as_deref()
        .is_some_and(|channel| !RELEASE_CHANNELS.contains(&channel))
    {
        return Err("release_channel");
    }
    // Integrations, the diff renderer and hosting validate their own sections.
    crate::diff_renderer::validate_settings(document.diff_renderer.as_ref())?;
    crate::integrations::validate_settings(&document.integrations)?;
    crate::hosting_settings::validate_settings(
        &document.hosting_connections,
        &document.hosting_bindings,
        &document.hosting_expanded_nodes,
    )?;
    let shortcut_ids: HashSet<_> = document
        .shortcut_overrides
        .iter()
        .map(|entry| entry.command_id.as_str())
        .collect();
    if shortcut_ids.len() != document.shortcut_overrides.len()
        || document.shortcut_overrides.iter().any(|entry| {
            entry.command_id.is_empty()
                || entry.command_id.len() > 96
                || !entry
                    .command_id
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
                || entry.binding.as_ref().is_some_and(|binding| {
                    binding.is_empty()
                        || binding.len() > 64
                        || binding.trim() != binding
                        || binding.chars().any(char::is_control)
                })
        })
    {
        return Err("shortcut_overrides");
    }
    let option_identities: HashSet<_> = document
        .repository_options
        .iter()
        .map(|options| &options.identity)
        .collect();
    if !(1..=MAX_AUTO_FETCH_MINUTES).contains(&document.auto_fetch.interval_minutes)
        || document.repository_options.len() > MAX_REPOSITORY_OPTIONS
        || option_identities.len() != document.repository_options.len()
        || document.repository_options.iter().any(|options| {
            options.identity.units.is_empty()
                || options.identity.units.len() > 32 * 1024
                || options.auto_fetch.is_none()
        })
    {
        return Err("repository_options");
    }
    let appearance_identities: HashSet<_> = document
        .repository_appearances
        .iter()
        .map(|appearance| &appearance.identity)
        .collect();
    let catalogue_key = invalid_catalogue_key;
    if appearance_identities.len() != document.repository_appearances.len()
        || document.repository_appearances.iter().any(|appearance| {
            catalogue_key(&appearance.icon)
                || catalogue_key(&appearance.color)
                || appearance
                    .image
                    .as_ref()
                    .is_some_and(|image| image.units.is_empty() || image.units.len() > 32 * 1024)
                || appearance.name.as_deref().is_some_and(invalid_tab_name)
                || (appearance.icon.is_none()
                    && appearance.color.is_none()
                    && appearance.image.is_none()
                    && appearance.name.is_none())
        })
    {
        return Err("repository_appearances");
    }
    let mut grouped = HashSet::new();
    if document.tab_groups.len() > MAX_TAB_GROUPS
        || document.tab_groups.iter().any(|group| {
            (!group.name.is_empty() && invalid_tab_name(&group.name))
                || group.color.is_empty()
                || catalogue_key(&Some(group.color.clone()))
                || catalogue_key(&group.icon)
                || group.members.is_empty()
                || group.members.len() > MAX_OPEN_WORKTREES
                || group.members.iter().any(|member| {
                    member.units.is_empty()
                        || member.units.len() > 32 * 1024
                        || !grouped.insert(member)
                })
        })
    {
        return Err("tab_groups");
    }
    let identities: HashSet<_> = document
        .worktrees
        .iter()
        .map(|worktree| &worktree.identity)
        .collect();
    if identities.len() != document.worktrees.len()
        || document.worktrees.iter().any(|worktree| {
            worktree.draft.subject.len() + worktree.draft.description.len() > MAX_DRAFT_BYTES
                || !WORKTREE_PANES.contains(&worktree.pane.as_str())
                || !WORKTREE_ROUTES.contains(&worktree.route.as_str())
                || worktree.changes_scroll_offset > 10_000_000
                || worktree.history_scroll_offset > 10_000_000
                || !valid_branch_filter(&worktree.branch_filter)
        })
    {
        return Err("worktrees");
    }
    let recents: HashSet<_> = document.recent_repositories.iter().collect();
    if recents.len() != document.recent_repositories.len() {
        return Err("recent_repositories");
    }
    let open: HashSet<_> = document.open_worktrees.iter().collect();
    if open.len() != document.open_worktrees.len()
        || !open.iter().all(|identity| identities.contains(identity))
    {
        return Err("open_worktrees");
    }
    // A new tab without a repository may be active while repository tabs
    // stay open; an active worktree must be one of them.
    match &document.active_worktree {
        Some(active) if !open.contains(active) => Err("active_worktree"),
        _ => Ok(()),
    }
}

/// Checks remote profiles and every identity's location. Workspace keys may
/// be remote; a path the application hands to a local program or reads as a
/// local file must be local.
fn validate_remote(document: &NativeSettingsDocument) -> Result<(), &'static str> {
    let mut local_files = document
        .integrations
        .iter()
        .map(|integration| &integration.executable)
        .chain(
            document
                .diff_renderer
                .iter()
                .map(|renderer| &renderer.executable),
        )
        .chain(
            document
                .repository_appearances
                .iter()
                .filter_map(|appearance| appearance.image.as_ref()),
        );
    if !workspace_keys(document).all(valid_location)
        || local_files.any(PathIdentityLocation::is_remote)
    {
        return Err("remote_locations");
    }
    let profile_ids: HashSet<_> = document
        .remote_profiles
        .iter()
        .map(|profile| profile.id.as_str())
        .collect();
    if document.remote_profiles.len() > MAX_REMOTE_PROFILES
        || profile_ids.len() != document.remote_profiles.len()
        || !document.remote_profiles.iter().all(valid_remote_profile)
    {
        return Err("remote_profiles");
    }
    Ok(())
}

/// A local identity keeps its previous rules; a remote one must be a valid
/// authority and an absolute Unix path of bytes within the wire bound.
fn valid_location(identity: &NativePathIdentity) -> bool {
    let Some(authority) = &identity.remote else {
        return true;
    };
    valid_remote_authority(authority)
        && identity.platform == NativePathPlatform::Unix
        && identity.units.len() <= MAX_REMOTE_PATH_BYTES
        && identity.units.first() == Some(&u16::from(b'/'))
        && identity
            .units
            .iter()
            .all(|unit| *unit != 0 && *unit <= 0xff)
}

/// Whether a stored catalogue key (an appearance colour or icon) is malformed.
fn invalid_catalogue_key(value: &Option<String>) -> bool {
    value.as_ref().is_some_and(|value| {
        value.is_empty()
            || value.len() > 64
            || !value
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
    })
}

fn valid_remote_profile(profile: &NativeRemoteHostProfile) -> bool {
    !invalid_catalogue_key(&profile.color)
        && !invalid_catalogue_key(&profile.icon)
        && valid_profile_id(&profile.id)
        && valid_remote_label(&profile.label)
        && valid_remote_alias(&profile.alias)
        && profile.verified.as_ref().is_none_or(|verified| {
            valid_store_id(&verified.store_id)
                && valid_account_uid(&verified.account_uid)
                && verified.account_name.len() <= MAX_REMOTE_ACCOUNT_NAME_BYTES
                && !verified.account_name.chars().any(char::is_control)
        })
}

/// A host or user@host destination, at most 128 ASCII characters total.
fn valid_remote_alias(value: &str) -> bool {
    let mut parts = value.split('@');
    let valid_part = |part: &str| {
        part.as_bytes()
            .first()
            .is_some_and(u8::is_ascii_alphanumeric)
            && part
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
    };
    value.len() <= MAX_REMOTE_PROFILE_TEXT
        && valid_part(parts.next().unwrap_or_default())
        && parts.next().is_none_or(valid_part)
        && parts.next().is_none()
}

/// 1–128 Unicode scalar values without control characters, not only blanks.
fn valid_remote_label(value: &str) -> bool {
    !value.trim().is_empty()
        && value.chars().count() <= MAX_REMOTE_PROFILE_TEXT
        && !value.chars().any(char::is_control)
}

fn holds_remote_data(document: &NativeSettingsDocument) -> bool {
    !document.remote_profiles.is_empty()
        || workspace_keys(document).any(PathIdentityLocation::is_remote)
}

/// Every identity that keys workspace state rather than naming a local file.
fn workspace_keys(document: &NativeSettingsDocument) -> impl Iterator<Item = &NativePathIdentity> {
    document
        .recent_repositories
        .iter()
        .chain(document.worktrees.iter().map(|worktree| &worktree.identity))
        .chain(&document.open_worktrees)
        .chain(&document.active_worktree)
        .chain(document.tab_groups.iter().flat_map(|group| &group.members))
        .chain(
            document
                .repository_appearances
                .iter()
                .map(|appearance| &appearance.identity),
        )
        .chain(
            document
                .repository_options
                .iter()
                .map(|options| &options.identity),
        )
        .chain(
            document
                .hosting_bindings
                .iter()
                .map(|binding| &binding.repository),
        )
}

/// Mirrors the native history bound; references are distinct full names.
fn valid_branch_filter(references: &[String]) -> bool {
    references.len() <= crate::domain::limits::BRANCH_FILTER_REFERENCES
        && references.iter().collect::<HashSet<_>>().len() == references.len()
        && references.iter().all(|reference| {
            reference.starts_with("refs/") && reference.len() <= MAX_BRANCH_FILTER_REFERENCE_BYTES
        })
}

const MAX_BRANCH_FILTER_REFERENCE_BYTES: usize = 1024;

/// A tab or group name: trimmed, bounded and free of control characters.
fn invalid_tab_name(name: &str) -> bool {
    name.is_empty()
        || name.len() > MAX_TAB_NAME_BYTES
        || name.trim() != name
        || name.chars().any(char::is_control)
}

fn valid_window_geometry(appearance: &NativeAppearanceSettings) -> bool {
    match (
        appearance.window_x,
        appearance.window_y,
        appearance.window_width,
        appearance.window_height,
    ) {
        (None, None, None, None) => true,
        (Some(_), Some(_), Some(width), Some(height)) => {
            (900..=16_384).contains(&width) && (600..=16_384).contains(&height)
        }
        _ => false,
    }
}

fn preserve_corrupt(path: &Path) -> Result<(), NativeSettingsFailureKind> {
    for index in 0..=u16::MAX {
        let suffix = if index == 0 {
            ".corrupt".into()
        } else {
            format!(".corrupt.{index}")
        };
        let destination = sibling(path, &suffix);
        if !destination.exists() {
            fs::rename(path, destination).map_err(map_io)?;
            sync_parent(path)?;
            return Ok(());
        }
    }
    Err(NativeSettingsFailureKind::Io)
}

fn sibling(path: &Path, suffix: &str) -> PathBuf {
    let name = path
        .file_name()
        .unwrap_or_else(|| OsStr::new("settings.json"));
    let mut sibling = name.to_os_string();
    sibling.push(suffix);
    path.with_file_name(sibling)
}

#[cfg(unix)]
fn sync_parent(path: &Path) -> Result<(), NativeSettingsFailureKind> {
    let parent = path.parent().ok_or(NativeSettingsFailureKind::Io)?;
    File::open(parent)
        .and_then(|directory| directory.sync_all())
        .map_err(map_io)
}

// Windows does not support opening a directory with `File::open`, so the Unix
// directory-fsync durability step is unavailable there. The replacement file
// itself is still synced before it is renamed into place.
#[cfg(windows)]
fn sync_parent(path: &Path) -> Result<(), NativeSettingsFailureKind> {
    path.parent()
        .is_some()
        .then_some(())
        .ok_or(NativeSettingsFailureKind::Io)
}

fn map_io(_: std::io::Error) -> NativeSettingsFailureKind {
    NativeSettingsFailureKind::Io
}

fn map_read(error: std::io::Error) -> NativeSettingsFailureKind {
    if error.kind() == std::io::ErrorKind::PermissionDenied {
        NativeSettingsFailureKind::Unreadable
    } else {
        NativeSettingsFailureKind::Io
    }
}

fn load_failure(kind: NativeSettingsFailureKind) -> NativeSettingsLoadResult {
    NativeSettingsLoadResult {
        state: NativeSettingsLoadState::Absent,
        document: None,
        failure: Some(NativeSettingsFailure { kind, rule: None }),
    }
}

struct SettingsLock(File);

impl SettingsLock {
    fn acquire(path: &Path) -> Result<Self, NativeSettingsFailureKind> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(path)
            .map_err(map_io)?;
        match file.try_lock() {
            Ok(()) => Ok(Self(file)),
            Err(TryLockError::WouldBlock) => Err(NativeSettingsFailureKind::Locked),
            Err(TryLockError::Error(_)) => Err(NativeSettingsFailureKind::Io),
        }
    }
}

impl Drop for SettingsLock {
    fn drop(&mut self) {
        let _ = self.0.unlock();
    }
}

impl From<NativeAppearanceSettings> for AppearanceDto {
    fn from(value: NativeAppearanceSettings) -> Self {
        Self {
            theme: value.theme,
            density: value.density,
            reduce_motion: value.reduce_motion,
            date_format: value.date_format,
            gravatar_enabled: value.gravatar_enabled,
            sidebar_width: value.sidebar_width,
            diff_width: value.diff_width,
            changes_unstaged_mode: value.changes_unstaged_mode,
            changes_staged_mode: value.changes_staged_mode,
            changes_split_ratio: value.changes_split_ratio,
            commit_files_mode: value.commit_files_mode,
            inspection_open_in: value.inspection_open_in,
            diff_wrap: value.diff_wrap,
            diff_layout: value.diff_layout,
            diff_whitespace: value.diff_whitespace,
            diff_context_lines: value.diff_context_lines,
            diff_indicators: value.diff_indicators,
            diff_minimap: value.diff_minimap,
            history_other_refs: value.history_other_refs,
            window_x: value.window_x,
            window_y: value.window_y,
            window_width: value.window_width,
            window_height: value.window_height,
            window_maximized: value.window_maximized,
        }
    }
}

impl From<AppearanceDto> for NativeAppearanceSettings {
    fn from(value: AppearanceDto) -> Self {
        Self {
            theme: value.theme,
            density: value.density,
            reduce_motion: migrate_reduce_motion(value.reduce_motion),
            date_format: value.date_format,
            gravatar_enabled: value.gravatar_enabled,
            sidebar_width: value.sidebar_width,
            diff_width: value.diff_width,
            changes_unstaged_mode: value.changes_unstaged_mode,
            changes_staged_mode: value.changes_staged_mode,
            changes_split_ratio: value.changes_split_ratio,
            commit_files_mode: value.commit_files_mode,
            inspection_open_in: value.inspection_open_in,
            diff_wrap: value.diff_wrap,
            diff_layout: value.diff_layout,
            diff_whitespace: value.diff_whitespace,
            diff_context_lines: value.diff_context_lines,
            diff_indicators: value.diff_indicators,
            diff_minimap: value.diff_minimap,
            history_other_refs: value.history_other_refs,
            window_x: value.window_x,
            window_y: value.window_y,
            window_width: value.window_width,
            window_height: value.window_height,
            window_maximized: value.window_maximized,
        }
    }
}

impl From<&NativeSettingsDocument> for SettingsDto {
    fn from(value: &NativeSettingsDocument) -> Self {
        Self {
            schema_version: CURRENT_SCHEMA,
            appearance: value.appearance.clone().into(),
            recent_repositories: value.recent_repositories.clone(),
            worktrees: value
                .worktrees
                .iter()
                .map(|worktree| WorktreeDto {
                    identity: worktree.identity.clone(),
                    filter: worktree.filter.clone(),
                    anchor: worktree.anchor.clone(),
                    pane: worktree.pane.clone(),
                    route: worktree.route.clone(),
                    changes_scroll_offset: worktree.changes_scroll_offset,
                    history_scroll_offset: worktree.history_scroll_offset,
                    draft: DraftDto {
                        subject: worktree.draft.subject.clone(),
                        description: worktree.draft.description.clone(),
                    },
                    branch_filter: worktree.branch_filter.clone(),
                })
                .collect(),
            open_worktrees: value.open_worktrees.clone(),
            active_worktree: value.active_worktree.clone(),
            integrations: value.integrations.clone(),
            diff_renderer: value.diff_renderer.clone(),
            hosting_connections: value.hosting_connections.clone(),
            hosting_bindings: value.hosting_bindings.clone(),
            hosting_expanded_nodes: value.hosting_expanded_nodes.clone(),
            shortcut_overrides: value.shortcut_overrides.clone(),
            repository_appearances: value.repository_appearances.clone(),
            release_channel: value.release_channel.clone(),
            auto_fetch: value.auto_fetch.clone(),
            repository_options: value.repository_options.clone(),
            tab_groups: value.tab_groups.clone(),
            remote_profiles: value.remote_profiles.clone(),
            remote_workspaces_enabled: value.remote_workspaces_enabled,
        }
    }
}

impl TryFrom<SettingsDto> for NativeSettingsDocument {
    type Error = ();

    fn try_from(value: SettingsDto) -> Result<Self, Self::Error> {
        let document = Self {
            appearance: value.appearance.into(),
            recent_repositories: value.recent_repositories,
            worktrees: value
                .worktrees
                .into_iter()
                .map(|worktree| NativeWorktreeSettings {
                    identity: worktree.identity,
                    filter: worktree.filter,
                    anchor: worktree.anchor,
                    pane: worktree.pane,
                    route: worktree.route,
                    changes_scroll_offset: worktree.changes_scroll_offset,
                    history_scroll_offset: worktree.history_scroll_offset,
                    draft: NativeCommitDraft {
                        subject: worktree.draft.subject,
                        description: worktree.draft.description,
                    },
                    branch_filter: worktree.branch_filter,
                })
                .collect(),
            open_worktrees: value.open_worktrees,
            active_worktree: value.active_worktree,
            integrations: value.integrations,
            diff_renderer: value.diff_renderer,
            hosting_connections: value.hosting_connections,
            hosting_bindings: value.hosting_bindings,
            hosting_expanded_nodes: value.hosting_expanded_nodes,
            shortcut_overrides: value.shortcut_overrides,
            repository_appearances: value.repository_appearances,
            release_channel: value.release_channel,
            auto_fetch: value.auto_fetch,
            repository_options: value.repository_options,
            tab_groups: value.tab_groups,
            remote_profiles: value.remote_profiles,
            remote_workspaces_enabled: value.remote_workspaces_enabled,
        };
        validate(&document)?;
        Ok(document)
    }
}

crate::family_failures!(NativeSettingsFailureKind, "settings", {
    Io => Read,
    Locked => Busy,
    Unreadable => Read,
    InvalidDocument => Read,
    UnsupportedSchema => Unsupported,
});

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::path_identity::{native_path, native_path_identity, NativeRemoteAuthority};
    use crate::hosting_settings::{HOSTING_AUTHENTICATIONS, HOSTING_PRESETS};
    use crate::integrations::INTEGRATION_KINDS;

    #[test]
    fn hosting_connection_names_allow_internal_spaces_only() {
        assert!(crate::domain::hosting::valid_connection_identity(
            "Work Forgejo"
        ));
        assert!(crate::domain::hosting::valid_connection_identity(
            "credential:Work Forgejo"
        ));
        assert!(!crate::domain::hosting::valid_connection_identity(
            " Work Forgejo"
        ));
        assert!(!crate::domain::hosting::valid_connection_identity(
            "Work Forgejo "
        ));
        assert!(!crate::domain::hosting::valid_connection_identity(
            "Work\nForgejo"
        ));
    }
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_FIXTURE: AtomicU64 = AtomicU64::new(1);

    struct Fixture(PathBuf);

    impl Fixture {
        fn new() -> Self {
            let sequence = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "gitlama-settings-{}-{sequence}",
                std::process::id()
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }

        fn settings(&self) -> PathBuf {
            self.0.join("settings.json")
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            fs::remove_dir_all(&self.0).unwrap();
        }
    }

    fn identity(name: &str) -> NativePathIdentity {
        native_path_identity(Path::new(name))
    }

    fn document() -> NativeSettingsDocument {
        let first = identity("first");
        let second = identity("second");
        NativeSettingsDocument {
            appearance: NativeAppearanceSettings {
                density: "comfortable".into(),
                date_format: "iso".into(),
                gravatar_enabled: true,
                changes_unstaged_mode: "tree".into(),
                changes_staged_mode: "list".into(),
                changes_split_ratio: 620,
                commit_files_mode: "list".into(),
                inspection_open_in: "window".into(),
                diff_wrap: true,
                diff_layout: "sideBySide".into(),
                diff_whitespace: "ignoreAll".into(),
                diff_context_lines: 6,
                diff_indicators: false,
                diff_minimap: false,
                history_other_refs: true,
                ..NativeAppearanceSettings::default()
            },
            recent_repositories: vec![first.clone()],
            worktrees: vec![
                NativeWorktreeSettings {
                    identity: first.clone(),
                    filter: "author:Example".into(),
                    anchor: Some("abc123".into()),
                    pane: "history".into(),
                    route: "commit".into(),
                    changes_scroll_offset: 12,
                    history_scroll_offset: 34,
                    draft: NativeCommitDraft {
                        subject: "subject".into(),
                        description: "description".into(),
                    },
                    branch_filter: vec![
                        "refs/heads/main".into(),
                        "refs/remotes/origin/topic".into(),
                    ],
                },
                NativeWorktreeSettings {
                    identity: second,
                    filter: String::new(),
                    anchor: None,
                    pane: "changes".into(),
                    route: "repository".into(),
                    changes_scroll_offset: 0,
                    history_scroll_offset: 0,
                    draft: NativeCommitDraft {
                        subject: String::new(),
                        description: String::new(),
                    },
                    branch_filter: Vec::new(),
                },
            ],
            open_worktrees: vec![first.clone()],
            active_worktree: Some(first),
            integrations: vec![NativeIntegrationSettings {
                id: "custom-status".into(),
                kind: "custom".into(),
                executable: identity("/usr/bin/git"),
                arguments: vec!["status".into(), "--short".into()],
                explicit_shell: false,
                wait: true,
                requires_confirmation: true,
                timeout_seconds: 30,
            }],
            diff_renderer: Some(NativeDiffRendererSettings {
                id: "plain".into(),
                title: "Plain renderer".into(),
                executable: identity("/usr/bin/renderer"),
                arguments: vec!["--theme=dark".into()],
            }),
            hosting_connections: vec![NativeHostingConnectionSettings {
                id: "github:fixture".into(),
                preset: "github".into(),
                login: "fixture".into(),
                web_base_url: "https://github.com".into(),
                api_base_url: "https://api.github.com".into(),
                oauth_client_id: "public-client".into(),
                authentication: "oauth".into(),
                enabled: true,
                refresh_enabled: true,
                capabilities: vec!["issues".into(), "changeRequests".into()],
                credential_identity: "credential:github:fixture".into(),
                allow_split_origin: true,
            }],
            hosting_bindings: vec![NativeHostingBindingSettings {
                repository: identity("first"),
                remote: b"origin".to_vec(),
                connection_id: "github:fixture".into(),
                provider_repository: "team/project".into(),
            }],
            hosting_expanded_nodes: vec!["changeRequests".into()],
            shortcut_overrides: vec![NativeShortcutOverride {
                command_id: "showHistory".into(),
                binding: Some("Ctrl+Alt+H".into()),
            }],
            repository_appearances: vec![NativeRepositoryAppearance {
                identity: identity("first"),
                icon: Some("rocket".into()),
                color: Some("teal".into()),
                image: Some(identity("/icons/first.png")),
                name: Some("Website".into()),
            }],
            release_channel: Some("beta".into()),
            auto_fetch: NativeAutoFetchSettings {
                enabled: false,
                interval_minutes: 30,
            },
            repository_options: vec![NativeRepositoryOptions {
                identity: identity("first"),
                auto_fetch: Some(true),
            }],
            tab_groups: vec![NativeTabGroup {
                name: "Client work".into(),
                color: "violet".into(),
                icon: Some("server".into()),
                collapsed: true,
                members: vec![identity("first")],
            }],
            remote_profiles: Vec::new(),
            remote_workspaces_enabled: false,
        }
    }

    #[test]
    fn round_trip_preserves_draft_order_and_closed_worktree_state() {
        let fixture = Fixture::new();
        save_to(&fixture.settings(), &document()).unwrap();
        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::Loaded);
        assert_eq!(loaded, document());
        assert_eq!(loaded.open_worktrees.len(), 1);
        assert_eq!(loaded.worktrees.len(), 2);
    }

    #[test]
    fn malformed_input_is_preserved_and_defaults_are_explicit() {
        let fixture = Fixture::new();
        fs::write(fixture.settings(), b"{unfinished").unwrap();
        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::RecoveredCorrupt);
        assert_eq!(loaded, NativeSettingsDocument::default());
        assert!(sibling(&fixture.settings(), ".corrupt").exists());
    }

    #[test]
    fn backup_left_by_interrupted_replacement_is_restored() {
        let fixture = Fixture::new();
        let backup = sibling(&fixture.settings(), ".backup");
        let dto = SettingsDto::from(&document());
        fs::write(&backup, serde_json::to_vec(&dto).unwrap()).unwrap();
        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::RestoredBackup);
        assert_eq!(loaded, document());
    }

    #[test]
    fn migration_ignores_legacy_graph_columns_but_keeps_date_format() {
        let fixture = Fixture::new();
        fs::write(
            fixture.settings(),
            br#"{"schemaVersion":1,"appearance":{"dateFormat":"local","graphColumns":["author"]}}"#,
        )
        .unwrap();
        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::Migrated);
        assert_eq!(loaded.appearance.date_format, "local");
        assert!(!loaded.appearance.gravatar_enabled);
        assert_eq!(loaded.appearance.changes_unstaged_mode, "list");
        assert_eq!(loaded.appearance.changes_staged_mode, "list");
        assert_eq!(loaded.appearance.changes_split_ratio, 500);
        assert_eq!(loaded.appearance.commit_files_mode, "tree");
        assert_eq!(loaded.appearance.inspection_open_in, "pane");
        save_to(&fixture.settings(), &loaded).unwrap();
        let saved = fs::read_to_string(fixture.settings()).unwrap();
        assert!(!saved.contains("graphColumns"));
        assert!(saved.contains("\"schemaVersion\": 13"));
    }

    #[test]
    fn schema_eleven_adds_empty_repository_appearances() {
        let fixture = Fixture::new();
        fs::write(
            fixture.settings(),
            br#"{"schemaVersion":11,"shortcutOverrides":[]}"#,
        )
        .unwrap();
        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::Migrated);
        assert!(loaded.repository_appearances.is_empty());
    }

    #[test]
    fn release_channel_is_optional_and_closed() {
        let fixture = Fixture::new();
        fs::write(fixture.settings(), br#"{"schemaVersion":12}"#).unwrap();
        let (_, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(loaded.release_channel, None);

        let mut chosen = document();
        for channel in ["stable", "beta"] {
            chosen.release_channel = Some(channel.into());
            save_to(&fixture.settings(), &chosen).unwrap();
            let (_, loaded) = load_from(&fixture.settings()).unwrap();
            assert_eq!(loaded.release_channel.as_deref(), Some(channel));
        }
        chosen.release_channel = None;
        save_to(&fixture.settings(), &chosen).unwrap();
        let saved = fs::read_to_string(fixture.settings()).unwrap();
        assert!(!saved.contains("releaseChannel"));

        for invalid in ["", "nightly", "Beta"] {
            chosen.release_channel = Some(invalid.into());
            assert!(validate(&chosen).is_err());
        }
    }

    #[test]
    fn branch_filters_accept_distinct_full_references_within_the_bound() {
        assert!(validate(&document()).is_ok());
        let with_filter = |filter: Vec<String>| {
            let mut value = document();
            value.worktrees[0].branch_filter = filter;
            value
        };
        for invalid in [
            vec!["main".to_owned()],
            vec!["refs/heads/main".to_owned(), "refs/heads/main".to_owned()],
            vec![format!("refs/heads/{}", "x".repeat(1024))],
            (0..=crate::domain::limits::BRANCH_FILTER_REFERENCES)
                .map(|index| format!("refs/heads/b{index}"))
                .collect(),
        ] {
            assert!(validate(&with_filter(invalid)).is_err());
        }
        // Documents written before the field existed keep loading unfiltered.
        let legacy = serde_json::json!({
            "identity": identity("first"),
            "pane": "history",
        });
        let worktree = serde_json::from_value::<WorktreeDto>(legacy).unwrap();
        assert!(worktree.branch_filter.is_empty());
    }

    #[test]
    fn repository_appearances_reject_invalid_keys_and_duplicates() {
        let valid = document();
        assert!(validate(&valid).is_ok());
        let mut uppercase = valid.clone();
        uppercase.repository_appearances[0].icon = Some("Rocket".into());
        assert!(validate(&uppercase).is_err());
        let mut empty = valid.clone();
        empty.repository_appearances[0] = NativeRepositoryAppearance {
            identity: identity("first"),
            icon: None,
            color: None,
            image: None,
            name: None,
        };
        assert!(validate(&empty).is_err());
        let mut named = valid.clone();
        named.repository_appearances[0] = NativeRepositoryAppearance {
            identity: identity("first"),
            icon: None,
            color: None,
            image: None,
            name: Some("Website".into()),
        };
        assert!(validate(&named).is_ok());
        for name in ["", " padded", "line\nbreak", &"x".repeat(257)] {
            let mut invalid = named.clone();
            invalid.repository_appearances[0].name = Some(name.into());
            assert!(validate(&invalid).is_err(), "{name:?}");
        }
        let mut duplicate = valid;
        duplicate
            .repository_appearances
            .push(duplicate.repository_appearances[0].clone());
        assert!(validate(&duplicate).is_err());
    }

    #[test]
    fn tab_groups_are_bounded_named_and_disjoint() {
        let valid = document();
        assert!(validate(&valid).is_ok());
        let mut unnamed = valid.clone();
        unnamed.tab_groups[0].name = String::new();
        assert!(validate(&unnamed).is_ok());
        let mut padded = valid.clone();
        padded.tab_groups[0].name = "Client ".into();
        assert!(validate(&padded).is_err());
        let mut colour = valid.clone();
        colour.tab_groups[0].color = "Violet".into();
        assert!(validate(&colour).is_err());
        // A custom colour is stored as its lowercase rgb value.
        let mut custom = valid.clone();
        custom.tab_groups[0].color = "rgb-c2410c".into();
        assert!(validate(&custom).is_ok());
        custom.repository_appearances[0].color = Some("rgb-1a5f3c".into());
        assert!(validate(&custom).is_ok());
        let mut plain = valid.clone();
        plain.tab_groups[0].icon = None;
        assert!(validate(&plain).is_ok());
        let mut icon = valid.clone();
        icon.tab_groups[0].icon = Some("Server".into());
        assert!(validate(&icon).is_err());
        let mut empty = valid.clone();
        empty.tab_groups[0].members.clear();
        assert!(validate(&empty).is_err());
        let mut shared = valid.clone();
        shared.tab_groups.push(shared.tab_groups[0].clone());
        assert!(validate(&shared).is_err());
        let mut many = valid;
        many.tab_groups = (0..=MAX_TAB_GROUPS)
            .map(|index| NativeTabGroup {
                name: String::new(),
                color: "blue".into(),
                icon: None,
                collapsed: false,
                members: vec![identity(&format!("repository-{index}"))],
            })
            .collect();
        assert!(validate(&many).is_err());
    }

    #[test]
    fn documents_without_tab_names_or_groups_keep_loading() {
        let appearance = serde_json::from_value::<NativeRepositoryAppearance>(
            serde_json::json!({"identity": identity("first"), "icon": "box"}),
        )
        .unwrap();
        assert_eq!(appearance.name, None);
        let serialized = serde_json::to_value(&appearance).unwrap();
        assert!(serialized.get("name").is_none());
        let group = serde_json::from_value::<NativeTabGroup>(serde_json::json!({
            "color": "blue",
            "members": [identity("first")],
        }))
        .unwrap();
        assert_eq!(group.icon, None);
        let serialized = serde_json::to_value(&group).unwrap();
        assert!(serialized.get("icon").is_none());
    }

    #[test]
    fn changes_layout_preferences_are_bounded_and_typed() {
        let mut candidate = document();
        assert!(validate(&candidate).is_ok());
        candidate.appearance.changes_unstaged_mode = "grid".into();
        assert!(validate(&candidate).is_err());
        candidate.appearance.changes_unstaged_mode = "tree".into();
        candidate.appearance.changes_split_ratio = 99;
        assert!(validate(&candidate).is_err());
        candidate.appearance.changes_split_ratio = 901;
        assert!(validate(&candidate).is_err());
    }

    #[test]
    fn inspector_preferences_default_and_are_typed() {
        let fixture = Fixture::new();
        fs::write(
            fixture.settings(),
            br#"{"schemaVersion":13,"appearance":{"changesStagedMode":"tree"}}"#,
        )
        .unwrap();
        let (_, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(loaded.appearance.commit_files_mode, "tree");
        assert_eq!(loaded.appearance.inspection_open_in, "pane");
        let mut candidate = document();
        candidate.appearance.commit_files_mode = "grid".into();
        assert!(validate(&candidate).is_err());
        candidate.appearance.commit_files_mode = "list".into();
        candidate.appearance.inspection_open_in = "tab".into();
        assert!(validate(&candidate).is_err());
        candidate.appearance.inspection_open_in = "window".into();
        assert!(validate(&candidate).is_ok());
    }

    #[test]
    fn diff_view_preferences_default_and_are_typed() {
        let fixture = Fixture::new();
        fs::write(
            fixture.settings(),
            br#"{"schemaVersion":13,"appearance":{"commitFilesMode":"list"}}"#,
        )
        .unwrap();
        let (_, loaded) = load_from(&fixture.settings()).unwrap();
        assert!(!loaded.appearance.diff_wrap);
        assert_eq!(loaded.appearance.diff_layout, "unified");
        assert_eq!(loaded.appearance.diff_whitespace, "preserve");
        assert_eq!(loaded.appearance.diff_context_lines, 3);
        assert!(loaded.appearance.diff_indicators);
        assert!(loaded.appearance.diff_minimap);
        assert!(!loaded.appearance.history_other_refs);
        let mut candidate = document();
        candidate.appearance.diff_layout = "split".into();
        assert!(validate(&candidate).is_err());
        candidate.appearance.diff_layout = "unified".into();
        candidate.appearance.diff_whitespace = "ignoreSome".into();
        assert!(validate(&candidate).is_err());
        candidate.appearance.diff_whitespace = "ignoreAmount".into();
        candidate.appearance.diff_context_lines = MAX_DIFF_CONTEXT_LINES + 1;
        assert!(validate(&candidate).is_err());
        candidate.appearance.diff_context_lines = 0;
        assert!(validate(&candidate).is_ok());
    }

    #[test]
    fn schema_eight_adds_empty_hosting_state_without_inventing_credentials() {
        let fixture = Fixture::new();
        fs::write(
            fixture.settings(),
            br#"{"schemaVersion":8,"integrations":[],"diffRenderer":null}"#,
        )
        .unwrap();
        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::Migrated);
        assert!(loaded.hosting_connections.is_empty());
        assert!(loaded.hosting_bindings.is_empty());
        save_to(&fixture.settings(), &loaded).unwrap();
        let saved = fs::read_to_string(fixture.settings()).unwrap();
        assert!(saved.contains("\"schemaVersion\": 13"));
        assert!(!saved.contains("accessToken"));
        assert!(!saved.contains("refreshToken"));
    }

    #[test]
    fn auto_fetch_defaults_to_enabled_and_rejects_invalid_options() {
        let fixture = Fixture::new();
        fs::write(fixture.settings(), br#"{"schemaVersion":12}"#).unwrap();
        let (_, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(loaded.auto_fetch, NativeAutoFetchSettings::default());
        assert!(loaded.auto_fetch.enabled);
        assert!(loaded.repository_options.is_empty());

        save_to(&fixture.settings(), &document()).unwrap();
        let (_, saved) = load_from(&fixture.settings()).unwrap();
        assert!(!saved.auto_fetch.enabled);
        assert_eq!(saved.auto_fetch.interval_minutes, 30);
        assert_eq!(saved.repository_options[0].auto_fetch, Some(true));

        for minutes in [0, MAX_AUTO_FETCH_MINUTES + 1] {
            let mut interval = document();
            interval.auto_fetch.interval_minutes = minutes;
            assert!(validate(&interval).is_err());
        }
        let mut duplicate = document();
        duplicate
            .repository_options
            .push(duplicate.repository_options[0].clone());
        assert!(validate(&duplicate).is_err());
        // An entry without an override is removed instead of stored.
        let mut empty = document();
        empty.repository_options[0].auto_fetch = None;
        assert!(validate(&empty).is_err());
    }

    #[test]
    fn every_hosting_name_the_application_writes_is_saved_and_reloaded() {
        #[derive(Deserialize)]
        struct Names {
            presets: Vec<String>,
            authentications: Vec<String>,
        }
        let names: Names = serde_json::from_str(include_str!(
            "../../../test/fixtures/settings_storage_names.json"
        ))
        .unwrap();
        assert_eq!(names.presets, HOSTING_PRESETS);
        assert_eq!(names.authentications, HOSTING_AUTHENTICATIONS);
        for preset in &names.presets {
            for authentication in &names.authentications {
                let fixture = Fixture::new();
                let mut candidate = document();
                candidate.hosting_connections[0].preset = preset.clone();
                candidate.hosting_connections[0].authentication = authentication.clone();
                save_to(&fixture.settings(), &candidate).unwrap();
                let (_, loaded) = load_from(&fixture.settings()).unwrap();
                assert_eq!(loaded.hosting_connections, candidate.hosting_connections);
            }
        }
        let mut unknown = document();
        unknown.hosting_connections[0].authentication = "githubCli".into();
        assert!(validate(&unknown).is_err());
    }

    #[test]
    fn every_stored_name_the_application_writes_is_saved_and_reloaded() {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct Names {
            themes: Vec<String>,
            densities: Vec<String>,
            reduce_motion: Vec<String>,
            file_layouts: Vec<String>,
            inspection_open_in: Vec<String>,
            diff_layouts: Vec<String>,
            diff_whitespace: Vec<String>,
            release_channels: Vec<String>,
            integration_kinds: Vec<String>,
            worktree_panes: Vec<String>,
            worktree_routes: Vec<String>,
        }
        let names: Names = serde_json::from_str(include_str!(
            "../../../test/fixtures/settings_storage_names.json"
        ))
        .unwrap();
        assert_eq!(names.themes, THEMES);
        assert_eq!(names.densities, DENSITIES);
        assert_eq!(names.reduce_motion, REDUCE_MOTION);
        assert_eq!(names.file_layouts, FILE_LAYOUTS);
        assert_eq!(names.inspection_open_in, INSPECTION_OPEN_IN);
        assert_eq!(names.diff_layouts, DIFF_LAYOUTS);
        assert_eq!(names.diff_whitespace, DIFF_WHITESPACE);
        assert_eq!(names.release_channels, RELEASE_CHANNELS);
        assert_eq!(names.integration_kinds, INTEGRATION_KINDS);
        assert_eq!(names.worktree_panes, WORKTREE_PANES);
        assert_eq!(names.worktree_routes, WORKTREE_ROUTES);
        let round_trip = |change: &dyn Fn(&mut NativeSettingsDocument)| {
            let fixture = Fixture::new();
            let mut candidate = document();
            change(&mut candidate);
            save_to(&fixture.settings(), &candidate).unwrap();
            let (_, loaded) = load_from(&fixture.settings()).unwrap();
            assert_eq!(loaded, candidate);
        };
        for value in &names.themes {
            round_trip(&|doc| doc.appearance.theme = value.clone());
        }
        for value in &names.densities {
            round_trip(&|doc| doc.appearance.density = value.clone());
        }
        for value in &names.reduce_motion {
            round_trip(&|doc| doc.appearance.reduce_motion = value.clone());
        }
        for value in &names.file_layouts {
            round_trip(&|doc| {
                doc.appearance.changes_unstaged_mode = value.clone();
                doc.appearance.changes_staged_mode = value.clone();
                doc.appearance.commit_files_mode = value.clone();
            });
        }
        for value in &names.inspection_open_in {
            round_trip(&|doc| doc.appearance.inspection_open_in = value.clone());
        }
        for value in &names.diff_layouts {
            round_trip(&|doc| doc.appearance.diff_layout = value.clone());
        }
        for value in &names.diff_whitespace {
            round_trip(&|doc| doc.appearance.diff_whitespace = value.clone());
        }
        for value in &names.release_channels {
            round_trip(&|doc| doc.release_channel = Some(value.clone()));
        }
        for value in &names.integration_kinds {
            round_trip(&|doc| doc.integrations[0].kind = value.clone());
        }
        for value in &names.worktree_panes {
            round_trip(&|doc| doc.worktrees[0].pane = value.clone());
        }
        for value in &names.worktree_routes {
            round_trip(&|doc| doc.worktrees[0].route = value.clone());
        }
    }

    #[test]
    fn earlier_reduce_motion_names_load_as_the_names_the_application_writes() {
        for (stored, expected) in [("enabled", "reduce"), ("disabled", "full")] {
            let fixture = Fixture::new();
            let mut candidate = document();
            candidate.appearance.reduce_motion = "followSystem".into();
            save_to(&fixture.settings(), &candidate).unwrap();
            let text = fs::read_to_string(fixture.settings()).unwrap();
            let replaced = text.replace(
                r#""reduceMotion": "followSystem""#,
                &format!(r#""reduceMotion": "{stored}""#),
            );
            assert!(text != replaced, "fixture must contain the stored name");
            fs::write(fixture.settings(), replaced).unwrap();
            let (_, loaded) = load_from(&fixture.settings()).unwrap();
            assert_eq!(loaded.appearance.reduce_motion, expected);
        }
        let mut unknown = document();
        unknown.appearance.reduce_motion = "enabled".into();
        assert_eq!(validation_failure(&unknown), Some("appearance"));
    }

    #[test]
    fn schema_nine_adds_empty_hosting_expansion_state() {
        let fixture = Fixture::new();
        fs::write(
            fixture.settings(),
            br#"{"schemaVersion":9,"hostingConnections":[],"hostingBindings":[]}"#,
        )
        .unwrap();
        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::Migrated);
        assert!(loaded.hosting_expanded_nodes.is_empty());
        assert!(loaded.shortcut_overrides.is_empty());
    }

    #[test]
    fn schema_ten_adds_empty_shortcut_overrides() {
        let fixture = Fixture::new();
        fs::write(
            fixture.settings(),
            br#"{"schemaVersion":10,"hostingExpandedNodes":[]}"#,
        )
        .unwrap();
        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::Migrated);
        assert!(loaded.shortcut_overrides.is_empty());
        save_to(&fixture.settings(), &loaded).unwrap();
        let saved = fs::read_to_string(fixture.settings()).unwrap();
        assert!(saved.contains("\"schemaVersion\": 13"));
    }

    const PROFILE_ID: &str = "123e4567-e89b-42d3-a456-426614174000";
    const OTHER_PROFILE_ID: &str = "00000000-0000-4000-8000-00000000000a";
    const STORE_ID: &str = "0123456789abcdef0123456789abcdef";

    fn authority(profile_id: &str) -> NativeRemoteAuthority {
        NativeRemoteAuthority {
            profile_id: profile_id.into(),
            store_id: STORE_ID.into(),
            account_uid: "1000".into(),
        }
    }

    fn remote_identity(path: &str, profile_id: &str) -> NativePathIdentity {
        NativePathIdentity {
            platform: NativePathPlatform::Unix,
            units: path.bytes().map(u16::from).collect(),
            remote: Some(authority(profile_id)),
        }
    }

    fn profile(id: &str) -> NativeRemoteHostProfile {
        NativeRemoteHostProfile {
            id: id.into(),
            label: "Build server".into(),
            alias: "build-01.example".into(),
            verified: Some(NativeRemoteVerifiedIdentity {
                store_id: STORE_ID.into(),
                account_uid: "1000".into(),
                account_name: "builder".into(),
            }),
            writes_allowed: false,
            auto_install_helper: false,
            color: None,
            icon: None,
        }
    }

    fn worktree(identity: NativePathIdentity, subject: &str) -> NativeWorktreeSettings {
        NativeWorktreeSettings {
            identity,
            filter: String::new(),
            anchor: None,
            pane: "changes".into(),
            route: "repository".into(),
            changes_scroll_offset: 0,
            history_scroll_offset: 0,
            draft: NativeCommitDraft {
                subject: subject.into(),
                description: String::new(),
            },
            branch_filter: Vec::new(),
        }
    }

    /// The local document with remote workspaces open beside it.
    fn remote_document() -> NativeSettingsDocument {
        let remote = remote_identity("/srv/project", PROFILE_ID);
        let mut value = document();
        value.remote_profiles = vec![profile(PROFILE_ID)];
        value
            .worktrees
            .push(worktree(remote.clone(), "remote draft"));
        value.open_worktrees.push(remote.clone());
        value.active_worktree = Some(remote.clone());
        value.recent_repositories.push(remote.clone());
        value.tab_groups[0].members.push(remote.clone());
        value
            .repository_appearances
            .push(NativeRepositoryAppearance {
                identity: remote.clone(),
                icon: Some("server".into()),
                color: None,
                image: None,
                name: Some("Server checkout".into()),
            });
        value.repository_options.push(NativeRepositoryOptions {
            identity: remote,
            auto_fetch: Some(false),
        });
        value
    }

    #[test]
    fn schema12_local_round_trip_unchanged() {
        let fixture = Fixture::new();
        let mut original = serde_json::to_value(SettingsDto::from(&document())).unwrap();
        original["schemaVersion"] = serde_json::json!(12);
        original.as_object_mut().unwrap().remove("remoteProfiles");
        let bytes = serde_json::to_vec_pretty(&original).unwrap();
        fs::write(fixture.settings(), &bytes).unwrap();

        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::Migrated);
        assert_eq!(loaded, document());
        assert!(loaded.remote_profiles.is_empty());
        assert!(workspace_keys(&loaded).all(|identity| !identity.is_remote()));
        save_to(&fixture.settings(), &loaded).unwrap();

        let saved: serde_json::Value =
            serde_json::from_slice(&fs::read(fixture.settings()).unwrap()).unwrap();
        let mut expected = original;
        expected["schemaVersion"] = serde_json::json!(13);
        expected["remoteProfiles"] = serde_json::json!([]);
        assert_eq!(saved, expected);
        // Local identities keep exactly their schema 12 shape.
        let platform = if cfg!(windows) { "windows" } else { "unix" };
        assert_eq!(
            serde_json::to_value(identity("first")).unwrap(),
            serde_json::json!({"platform": platform, "units": [102, 105, 114, 115, 116]}),
        );
    }

    #[test]
    fn remote_identities_round_trip_in_every_workspace_list() {
        let fixture = Fixture::new();
        let value = remote_document();
        save_to(&fixture.settings(), &value).unwrap();
        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::Loaded);
        assert_eq!(loaded, value);
        let remote = remote_identity("/srv/project", PROFILE_ID);
        assert_eq!(loaded.active_worktree, Some(remote.clone()));
        assert!(loaded.open_worktrees.contains(&remote));
        assert!(loaded.recent_repositories.contains(&remote));
        assert!(loaded.tab_groups[0].members.contains(&remote));
        assert_eq!(
            loaded
                .worktrees
                .iter()
                .find(|worktree| worktree.identity == remote)
                .map(|worktree| worktree.draft.subject.as_str()),
            Some("remote draft")
        );

        let saved: serde_json::Value =
            serde_json::from_slice(&fs::read(fixture.settings()).unwrap()).unwrap();
        assert_eq!(saved["schemaVersion"], 13);
        assert_eq!(
            saved["activeWorktree"]["remote"],
            serde_json::json!({
                "profileId": PROFILE_ID,
                "storeId": STORE_ID,
                "accountUid": "1000",
            })
        );
        assert!(saved["openWorktrees"][0].get("remote").is_none());
        assert_eq!(saved["remoteProfiles"][0]["alias"], "build-01.example");
        // The local path boundary refuses the remote identity.
        assert_eq!(native_path(&remote), None);
    }

    #[test]
    fn identical_paths_different_hosts() {
        let fixture = Fixture::new();
        let path = "/home/dev/project";
        let first = remote_identity(path, PROFILE_ID);
        let second = remote_identity(path, OTHER_PROFILE_ID);
        let local = native_path_identity(Path::new(path));
        assert_eq!(first.units, local.units);
        assert_ne!(first, second);
        assert_ne!(first, local);

        let mut value = NativeSettingsDocument {
            remote_profiles: vec![profile(PROFILE_ID), profile(OTHER_PROFILE_ID)],
            ..NativeSettingsDocument::default()
        };
        value.worktrees = vec![
            worktree(first.clone(), "first host"),
            worktree(second.clone(), "second host"),
        ];
        value.open_worktrees = vec![first.clone(), second.clone()];
        value.active_worktree = Some(second.clone());
        #[cfg(unix)]
        {
            value
                .worktrees
                .push(worktree(local.clone(), "this computer"));
            value.open_worktrees.push(local.clone());
        }
        save_to(&fixture.settings(), &value).unwrap();
        let (_, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(loaded, value);
        let draft = |identity: &NativePathIdentity| {
            loaded
                .worktrees
                .iter()
                .find(|worktree| &worktree.identity == identity)
                .map(|worktree| worktree.draft.subject.clone())
        };
        assert_eq!(draft(&first).as_deref(), Some("first host"));
        assert_eq!(draft(&second).as_deref(), Some("second host"));
        #[cfg(unix)]
        assert_eq!(draft(&local).as_deref(), Some("this computer"));
    }

    #[test]
    fn orphaned_remote_entries_are_preserved() {
        let fixture = Fixture::new();
        let mut value = remote_document();
        // The profile was deleted; its workspaces stay recoverable.
        value.remote_profiles.clear();
        save_to(&fixture.settings(), &value).unwrap();
        let (_, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(loaded, value);
    }

    #[test]
    fn invalid_remote_identities_are_rejected() {
        let valid = remote_document();
        assert!(validate(&valid).is_ok());
        let with_active = |identity: NativePathIdentity| {
            let mut value = valid.clone();
            let remote = remote_identity("/srv/project", PROFILE_ID);
            let replace = |entry: &mut NativePathIdentity| {
                if *entry == remote {
                    *entry = identity.clone();
                }
            };
            value
                .worktrees
                .iter_mut()
                .for_each(|w| replace(&mut w.identity));
            value.open_worktrees.iter_mut().for_each(replace);
            value.active_worktree.iter_mut().for_each(replace);
            value
        };
        let base = || remote_identity("/srv/project", PROFILE_ID);
        let mut invalid = Vec::new();
        for (profile_id, store_id, account_uid) in [
            ("123E4567-E89B-42D3-A456-426614174000", STORE_ID, "1000"),
            ("123e4567e89b42d3a456426614174000", STORE_ID, "1000"),
            ("", STORE_ID, "1000"),
            (PROFILE_ID, "0123456789ABCDEF0123456789ABCDEF", "1000"),
            (PROFILE_ID, "0123456789abcdef", "1000"),
            (PROFILE_ID, STORE_ID, "01000"),
            (PROFILE_ID, STORE_ID, "-1"),
            (PROFILE_ID, STORE_ID, "+1"),
            (PROFILE_ID, STORE_ID, ""),
            (PROFILE_ID, STORE_ID, "4294967296"),
        ] {
            let mut identity = base();
            identity.remote = Some(NativeRemoteAuthority {
                profile_id: profile_id.into(),
                store_id: store_id.into(),
                account_uid: account_uid.into(),
            });
            invalid.push(identity);
        }
        let mut relative = base();
        relative.units = b"srv/project".iter().map(|b| u16::from(*b)).collect();
        let mut empty = base();
        empty.units.clear();
        let mut nul = base();
        nul.units.push(0);
        let mut wide = base();
        wide.units.push(0x100);
        let mut long = base();
        long.units
            .resize(MAX_REMOTE_PATH_BYTES + 1, u16::from(b'a'));
        let mut windows = base();
        windows.platform = NativePathPlatform::Windows;
        invalid.extend([relative, empty, nul, wide, long, windows]);
        for identity in invalid {
            assert!(
                validate(&with_active(identity.clone())).is_err(),
                "{identity:?}"
            );
        }
        let mut longest = base();
        longest.units.resize(MAX_REMOTE_PATH_BYTES, u16::from(b'a'));
        assert!(validate(&with_active(longest)).is_ok());
        let mut root_uid = base();
        root_uid.remote.as_mut().unwrap().account_uid = "0".into();
        assert!(validate(&with_active(root_uid)).is_ok());
        let mut maximum_uid = base();
        maximum_uid.remote.as_mut().unwrap().account_uid = "4294967295".into();
        assert!(validate(&with_active(maximum_uid)).is_ok());

        // Files the application opens or runs locally are never remote.
        let mut executable = valid.clone();
        executable.integrations[0].executable = base();
        assert!(validate(&executable).is_err());
        let mut renderer = valid.clone();
        renderer.diff_renderer.as_mut().unwrap().executable = base();
        assert!(validate(&renderer).is_err());
        let mut image = valid;
        image.repository_appearances[0].image = Some(base());
        assert!(validate(&image).is_err());
    }

    #[test]
    fn open_worktrees_may_have_no_active_one() {
        let fixture = Fixture::new();
        let mut value = document();
        assert!(!value.open_worktrees.is_empty());
        value.active_worktree = None;
        save_to(&fixture.settings(), &value).unwrap();
        let (_, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(loaded.active_worktree, None);
        assert_eq!(loaded.open_worktrees, value.open_worktrees);

        value.active_worktree = Some(value.worktrees[0].identity.clone());
        value.open_worktrees.clear();
        assert_eq!(validation_failure(&value), Some("active_worktree"));
    }

    #[test]
    fn a_rejected_save_names_the_broken_rule() {
        let fixture = Fixture::new();
        let mut value = document();
        value.appearance.window_width = Some(10);
        let result = settings_save(fixture.settings().to_string_lossy().into_owned(), value);
        let failure = result.failure.unwrap();
        assert_eq!(failure.kind, NativeSettingsFailureKind::InvalidDocument);
        assert_eq!(failure.rule.as_deref(), Some("window_geometry"));
    }

    #[test]
    fn automatic_helper_installation_is_off_unless_recorded() {
        let mut profile = profile("123e4567-e89b-42d3-a456-426614174000");
        let written = serde_json::to_value(&profile).unwrap();
        // Off is not written, so documents stay as older versions wrote them.
        assert!(written.get("autoInstallHelper").is_none());
        let loaded: NativeRemoteHostProfile = serde_json::from_value(written).unwrap();
        assert!(!loaded.auto_install_helper);
        profile.auto_install_helper = true;
        let written = serde_json::to_value(&profile).unwrap();
        assert_eq!(written["autoInstallHelper"], true);
        let loaded: NativeRemoteHostProfile = serde_json::from_value(written).unwrap();
        assert!(loaded.auto_install_helper);
    }

    #[test]
    fn remote_profiles_are_bounded_and_validated() {
        let valid = remote_document();
        let with_profile = |change: &dyn Fn(&mut NativeRemoteHostProfile)| {
            let mut value = valid.clone();
            change(&mut value.remote_profiles[0]);
            value
        };
        for alias in [
            "a",
            "A.b_c-9",
            "user@host",
            "me@192.0.2.1",
            &"x".repeat(128),
        ] {
            assert!(validate(&with_profile(&|p| p.alias = alias.into())).is_ok());
        }
        for alias in [
            "",
            "-ssh",
            ".hidden",
            "user@@host",
            "user@-host",
            "@host",
            "user@",
            "host name",
            "host:22",
            "*",
            "hôst",
            &"x".repeat(129),
        ] {
            assert!(
                validate(&with_profile(&|p| p.alias = alias.into())).is_err(),
                "{alias:?}"
            );
        }
        for label in ["Ä", " padded label ", &"é".repeat(128)] {
            assert!(validate(&with_profile(&|p| p.label = label.into())).is_ok());
        }
        for label in [
            "",
            "   ",
            "line\nbreak",
            "bell\u{7}",
            "\u{85}",
            &"é".repeat(129),
        ] {
            assert!(
                validate(&with_profile(&|p| p.label = label.into())).is_err(),
                "{label:?}"
            );
        }
        assert!(validate(&with_profile(&|p| p.id = "not-a-uuid".into())).is_err());
        assert!(validate(&with_profile(&|p| p.verified = None)).is_ok());
        // A host's tabs may show a catalogue colour and icon.
        assert!(validate(&with_profile(&|p| {
            p.color = Some("teal".into());
            p.icon = Some("server".into());
        }))
        .is_ok());
        for key in ["", "Teal", "with space", &"x".repeat(65)] {
            assert!(validate(&with_profile(&|p| p.color = Some(key.into()))).is_err());
            assert!(validate(&with_profile(&|p| p.icon = Some(key.into()))).is_err());
        }
        let verified = |change: &dyn Fn(&mut NativeRemoteVerifiedIdentity)| {
            with_profile(&|p| change(p.verified.as_mut().unwrap()))
        };
        assert!(validate(&verified(&|v| v.account_name = String::new())).is_ok());
        assert!(validate(&verified(&|v| v.account_name = "x".repeat(128))).is_ok());
        assert!(validate(&verified(&|v| v.account_name = "x".repeat(129))).is_err());
        assert!(validate(&verified(&|v| v.account_name = "tab\there".into())).is_err());
        assert!(validate(&verified(&|v| v.store_id = "short".into())).is_err());
        assert!(validate(&verified(&|v| v.account_uid = "007".into())).is_err());

        let mut duplicate = valid.clone();
        duplicate.remote_profiles.push(profile(PROFILE_ID));
        assert!(validate(&duplicate).is_err());
        let identifier = |index: usize| format!("00000000-0000-4000-8000-{index:012x}");
        let mut full = valid.clone();
        full.remote_profiles = (0..MAX_REMOTE_PROFILES)
            .map(|index| profile(&identifier(index)))
            .collect();
        assert!(validate(&full).is_ok());
        full.remote_profiles
            .push(profile(&identifier(MAX_REMOTE_PROFILES)));
        assert!(validate(&full).is_err());
    }

    #[test]
    fn remote_data_is_never_accepted_from_an_older_schema() {
        let fixture = Fixture::new();
        let mut value = serde_json::to_value(SettingsDto::from(&remote_document())).unwrap();
        value["schemaVersion"] = serde_json::json!(12);
        let original = serde_json::to_vec(&value).unwrap();
        fs::write(fixture.settings(), &original).unwrap();
        assert_eq!(
            load_from(&fixture.settings()).unwrap_err(),
            NativeSettingsFailureKind::InvalidDocument
        );
        assert_eq!(fs::read(fixture.settings()).unwrap(), original);

        let mut profiles_only = serde_json::to_value(SettingsDto::from(&document())).unwrap();
        profiles_only["schemaVersion"] = serde_json::json!(12);
        profiles_only["remoteProfiles"] = serde_json::to_value(vec![profile(PROFILE_ID)]).unwrap();
        fs::write(
            fixture.settings(),
            serde_json::to_vec(&profiles_only).unwrap(),
        )
        .unwrap();
        assert_eq!(
            load_from(&fixture.settings()).unwrap_err(),
            NativeSettingsFailureKind::InvalidDocument
        );
    }

    #[test]
    fn invalid_or_unknown_remote_data_is_never_read_as_local() {
        let fixture = Fixture::new();
        // An authority with a field this version does not know is damaged,
        // not a local path.
        let mut value = serde_json::to_value(SettingsDto::from(&remote_document())).unwrap();
        value["activeWorktree"]["remote"]["hostKey"] = serde_json::json!("future");
        fs::write(fixture.settings(), serde_json::to_vec(&value).unwrap()).unwrap();
        let (state, loaded) = load_from(&fixture.settings()).unwrap();
        assert_eq!(state, NativeSettingsLoadState::RecoveredCorrupt);
        assert_eq!(loaded, NativeSettingsDocument::default());
        assert!(sibling(&fixture.settings(), ".corrupt").exists());

        // A remote identity with an invalid authority is an invalid document.
        let mut value = serde_json::to_value(SettingsDto::from(&remote_document())).unwrap();
        value["activeWorktree"]["remote"]["storeId"] = serde_json::json!("NOT-HEX");
        let original = serde_json::to_vec(&value).unwrap();
        fs::write(fixture.settings(), &original).unwrap();
        assert_eq!(
            load_from(&fixture.settings()).unwrap_err(),
            NativeSettingsFailureKind::InvalidDocument
        );
        assert_eq!(fs::read(fixture.settings()).unwrap(), original);
    }

    #[test]
    fn future_schema_with_remote_data_is_unsupported() {
        let fixture = Fixture::new();
        let mut value = serde_json::to_value(SettingsDto::from(&remote_document())).unwrap();
        value["schemaVersion"] = serde_json::json!(CURRENT_SCHEMA + 1);
        value["activeWorktree"]["remote"]["kind"] = serde_json::json!("futureLocation");
        let original = serde_json::to_vec(&value).unwrap();
        fs::write(fixture.settings(), &original).unwrap();
        assert_eq!(
            load_from(&fixture.settings()).unwrap_err(),
            NativeSettingsFailureKind::UnsupportedSchema
        );
        assert_eq!(fs::read(fixture.settings()).unwrap(), original);
    }

    #[test]
    fn newer_schema_is_not_replaced() {
        let fixture = Fixture::new();
        let original = br#"{"schemaVersion":99,"privateFutureField":"keep"}"#;
        fs::write(fixture.settings(), original).unwrap();
        assert_eq!(
            load_from(&fixture.settings()).unwrap_err(),
            NativeSettingsFailureKind::UnsupportedSchema
        );
        assert_eq!(fs::read(fixture.settings()).unwrap(), original);
    }

    #[test]
    fn native_path_units_round_trip_without_utf8_conversion() {
        #[cfg(unix)]
        {
            use std::os::unix::ffi::OsStringExt;
            let path = PathBuf::from(std::ffi::OsString::from_vec(vec![b'a', 0x80, b'z']));
            let identity = native_path_identity(&path);
            assert_eq!(native_path(&identity), Some(path));
        }
    }

    #[test]
    fn qualification_profile_root_is_absolute_and_bypasses_platform_storage() {
        let root = if cfg!(windows) {
            PathBuf::from(r"C:\gitlama-qualification")
        } else {
            PathBuf::from("/tmp/gitlama-qualification")
        };
        assert_eq!(
            default_settings_path(
                Some(root.clone()),
                Some(PathBuf::from("ignored-platform-base")),
                "GitLama",
            ),
            Some(root.join("settings.json")),
        );
        assert_eq!(
            default_settings_path(
                Some(PathBuf::from("relative-profile")),
                Some(PathBuf::from("ignored-platform-base")),
                "GitLama",
            ),
            None,
        );
    }

    #[test]
    fn invalid_workspace_and_credential_shaped_json_are_rejected_or_ignored() {
        let fixture = Fixture::new();
        fs::write(
            fixture.settings(),
            br#"{"schemaVersion":3,"token":"sentinel","openWorktrees":[{"platform":"unix","units":[120]}]}"#,
        )
        .unwrap();
        assert_eq!(
            load_from(&fixture.settings()).unwrap_err(),
            NativeSettingsFailureKind::InvalidDocument
        );
        assert!(fs::read_to_string(fixture.settings())
            .unwrap()
            .contains("sentinel"));
    }

    #[test]
    fn live_writer_is_rejected_but_leftover_lock_path_is_harmless() {
        let fixture = Fixture::new();
        let lock_path = sibling(&fixture.settings(), ".lock");
        let lock = SettingsLock::acquire(&lock_path).unwrap();
        assert_eq!(
            save_to(&fixture.settings(), &document()).unwrap_err(),
            NativeSettingsFailureKind::Locked
        );
        drop(lock);
        save_to(&fixture.settings(), &document()).unwrap();
    }

    #[test]
    fn interrupted_or_full_write_keeps_the_previous_document() {
        let fixture = Fixture::new();
        let first = document();
        save_to(&fixture.settings(), &first).unwrap();
        let original = fs::read(fixture.settings()).unwrap();
        let mut changed = document();
        changed.appearance.theme = "dark".into();

        let failure = save_to_with_writer(&fixture.settings(), &changed, |file, bytes| {
            file.write_all(&bytes[..bytes.len() / 2])?;
            Err(std::io::Error::new(
                std::io::ErrorKind::StorageFull,
                "injected storage full",
            ))
        })
        .unwrap_err();

        assert_eq!(failure, NativeSettingsFailureKind::Io);
        assert_eq!(fs::read(fixture.settings()).unwrap(), original);
    }

    #[test]
    fn unknown_fields_load_leniently_and_are_not_reemitted() {
        let fixture = Fixture::new();
        let mut value = serde_json::to_value(SettingsDto::from(&document())).unwrap();
        value["futurePresentationField"] = serde_json::json!({"value": 42});
        value["credential"] = serde_json::json!("sentinel-secret");
        fs::write(fixture.settings(), serde_json::to_vec(&value).unwrap()).unwrap();

        let (_, loaded) = load_from(&fixture.settings()).unwrap();
        save_to(&fixture.settings(), &loaded).unwrap();
        let saved = fs::read_to_string(fixture.settings()).unwrap();
        assert!(!saved.contains("futurePresentationField"));
        assert!(!saved.contains("sentinel-secret"));
        assert!(!saved.contains("\"credential\":"));
    }

    #[cfg(unix)]
    #[test]
    fn unreadable_document_has_a_distinct_failure() {
        use std::os::unix::fs::PermissionsExt;
        let fixture = Fixture::new();
        save_to(&fixture.settings(), &document()).unwrap();
        fs::set_permissions(fixture.settings(), fs::Permissions::from_mode(0o000)).unwrap();
        let result = load_from(&fixture.settings());
        fs::set_permissions(fixture.settings(), fs::Permissions::from_mode(0o600)).unwrap();
        assert_eq!(result.unwrap_err(), NativeSettingsFailureKind::Unreadable);
    }
}
