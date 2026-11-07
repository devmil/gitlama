//! The bridge types of `storage`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.
use crate::diff_renderer::NativeDiffRendererSettings;
use crate::domain::path_identity::NativePathIdentity;
use crate::hosting_settings::{NativeHostingBindingSettings, NativeHostingConnectionSettings};
use crate::integrations::NativeIntegrationSettings;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeSettingsLoadState {
    Absent,
    Loaded,
    Migrated,
    RecoveredCorrupt,
    RestoredBackup,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeSettingsFailureKind {
    Io,
    Locked,
    Unreadable,
    InvalidDocument,
    UnsupportedSchema,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeSettingsFailure {
    pub kind: NativeSettingsFailureKind,
    /// For a rejected document, the stable name of the rule it broke.
    pub rule: Option<String>,
}

/// The identity a helper verified for a profile, recorded after an explicit
/// first attachment or rebind.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeRemoteVerifiedIdentity {
    pub store_id: String,
    pub account_uid: String,
    /// Display data only; never part of an authority.
    pub account_name: String,
}

/// A locally stored connection to a computer through an OpenSSH alias. It
/// holds no credentials, options or commands.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeRemoteHostProfile {
    pub id: String,
    pub label: String,
    pub alias: String,
    #[serde(default)]
    pub verified: Option<NativeRemoteVerifiedIdentity>,
    #[serde(default)]
    pub writes_allowed: bool,
    /// Whether GitLama installs its helper on the host without asking when the host lacks the
    /// helper of this version. A changed alias or identity withdraws it.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub auto_install_helper: bool,
    /// A colour from the appearance catalogue the host's tabs show.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    /// An icon from the appearance catalogue the host's tabs show.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct NativeAppearanceSettings {
    pub theme: String,
    pub density: String,
    pub reduce_motion: String,
    pub date_format: String,
    pub gravatar_enabled: bool,
    pub sidebar_width: u32,
    pub diff_width: u32,
    pub changes_unstaged_mode: String,
    pub changes_staged_mode: String,
    pub changes_split_ratio: u32,
    /// List or tree arrangement of a commit's changed files.
    pub commit_files_mode: String,
    /// Where file inspection opens: the Detail "pane" or a new "window".
    pub inspection_open_in: String,
    /// Whether long diff lines wrap instead of scrolling sideways.
    pub diff_wrap: bool,
    /// The diff layout: "unified" or "sideBySide".
    pub diff_layout: String,
    /// Which whitespace changes diffs ignore.
    pub diff_whitespace: String,
    /// Unchanged lines shown around each diff hunk.
    pub diff_context_lines: u32,
    /// Whether diff rows show their + and - markers.
    pub diff_indicators: bool,
    /// Whether diffs show the change minimap.
    pub diff_minimap: bool,
    /// Whether History also shows commits only references outside branches,
    /// remote-tracking branches, tags and the stash reach.
    pub history_other_refs: bool,
    pub window_x: Option<i32>,
    pub window_y: Option<i32>,
    pub window_width: Option<u32>,
    pub window_height: Option<u32>,
    pub window_maximized: bool,
}

impl Default for NativeAppearanceSettings {
    // flutter_rust_bridge reads this crate as a third-party input and would expose a Dart
    // `default_()` for every `Default` impl; the bridge types carry no functions.
    /// flutter_rust_bridge:ignore
    fn default() -> Self {
        Self {
            theme: "system".into(),
            density: "regular".into(),
            reduce_motion: "followSystem".into(),
            date_format: "relative".into(),
            gravatar_enabled: false,
            sidebar_width: 248,
            diff_width: 420,
            changes_unstaged_mode: "list".into(),
            changes_staged_mode: "list".into(),
            changes_split_ratio: 500,
            commit_files_mode: "tree".into(),
            inspection_open_in: "pane".into(),
            diff_wrap: false,
            diff_layout: "unified".into(),
            diff_whitespace: "preserve".into(),
            diff_context_lines: 3,
            diff_indicators: true,
            diff_minimap: true,
            history_other_refs: false,
            window_x: None,
            window_y: None,
            window_width: None,
            window_height: None,
            window_maximized: false,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeCommitDraft {
    pub subject: String,
    pub description: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeWorktreeSettings {
    pub identity: NativePathIdentity,
    pub filter: String,
    pub anchor: Option<String>,
    pub pane: String,
    pub route: String,
    pub changes_scroll_offset: u64,
    pub history_scroll_offset: u64,
    pub draft: NativeCommitDraft,
    /// Full reference names the history graph is filtered to; empty shows all.
    /// Recovery checkpoints written before the field existed omit it.
    #[serde(default)]
    pub branch_filter: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeShortcutOverride {
    pub command_id: String,
    pub binding: Option<String>,
}

/// How a repository's tab identifies it: an image file, or an icon and colour
/// from the application's catalogues, and a name replacing the folder's.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeRepositoryAppearance {
    pub identity: NativePathIdentity,
    #[serde(default)]
    pub icon: Option<String>,
    #[serde(default)]
    pub color: Option<String>,
    #[serde(default)]
    pub image: Option<NativePathIdentity>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
}

/// Open repository tabs kept together under a name, a colour and an optional
/// icon from the appearance catalogues, in tab order.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeTabGroup {
    #[serde(default)]
    pub name: String,
    pub color: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
    #[serde(default)]
    pub collapsed: bool,
    pub members: Vec<NativePathIdentity>,
}

/// Fetching the remotes of open repositories in the background.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct NativeAutoFetchSettings {
    pub enabled: bool,
    pub interval_minutes: u32,
}

impl Default for NativeAutoFetchSettings {
    // flutter_rust_bridge reads this crate as a third-party input and would expose a Dart
    // `default_()` for every `Default` impl; the bridge types carry no functions.
    /// flutter_rust_bridge:ignore
    fn default() -> Self {
        Self {
            enabled: true,
            interval_minutes: 10,
        }
    }
}

/// What one repository overrides; an absent value follows the application.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeRepositoryOptions {
    pub identity: NativePathIdentity,
    #[serde(default)]
    pub auto_fetch: Option<bool>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeSettingsDocument {
    pub appearance: NativeAppearanceSettings,
    pub recent_repositories: Vec<NativePathIdentity>,
    pub worktrees: Vec<NativeWorktreeSettings>,
    pub open_worktrees: Vec<NativePathIdentity>,
    pub active_worktree: Option<NativePathIdentity>,
    pub integrations: Vec<NativeIntegrationSettings>,
    pub diff_renderer: Option<NativeDiffRendererSettings>,
    #[serde(default)]
    pub hosting_connections: Vec<NativeHostingConnectionSettings>,
    #[serde(default)]
    pub hosting_bindings: Vec<NativeHostingBindingSettings>,
    #[serde(default)]
    pub hosting_expanded_nodes: Vec<String>,
    #[serde(default)]
    pub shortcut_overrides: Vec<NativeShortcutOverride>,
    #[serde(default)]
    pub repository_appearances: Vec<NativeRepositoryAppearance>,
    /// The update channel the user chose; absent follows the installed build.
    #[serde(default)]
    pub release_channel: Option<String>,
    #[serde(default)]
    pub auto_fetch: NativeAutoFetchSettings,
    #[serde(default)]
    pub repository_options: Vec<NativeRepositoryOptions>,
    #[serde(default)]
    pub tab_groups: Vec<NativeTabGroup>,
    /// Remote host profiles. Remote identities elsewhere in the document may
    /// name a profile that no longer exists; such entries stay recoverable.
    #[serde(default)]
    pub remote_profiles: Vec<NativeRemoteHostProfile>,
    /// No longer read: remote workspaces are always offered. Kept so documents of older versions
    /// load, and written as true so those versions keep showing them.
    #[serde(default)]
    pub remote_workspaces_enabled: bool,
}

// A derived impl would carry no `flutter_rust_bridge:ignore` marker.
#[allow(clippy::derivable_impls)]
impl Default for NativeSettingsDocument {
    // flutter_rust_bridge reads this crate as a third-party input and would expose a Dart
    // `default_()` for every `Default` impl; the bridge types carry no functions.
    /// flutter_rust_bridge:ignore
    fn default() -> Self {
        Self {
            appearance: Default::default(),
            recent_repositories: Default::default(),
            worktrees: Default::default(),
            open_worktrees: Default::default(),
            active_worktree: Default::default(),
            integrations: Default::default(),
            diff_renderer: Default::default(),
            hosting_connections: Default::default(),
            hosting_bindings: Default::default(),
            hosting_expanded_nodes: Default::default(),
            shortcut_overrides: Default::default(),
            repository_appearances: Default::default(),
            release_channel: Default::default(),
            auto_fetch: Default::default(),
            repository_options: Default::default(),
            tab_groups: Default::default(),
            remote_profiles: Default::default(),
            remote_workspaces_enabled: Default::default(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeSettingsLoadResult {
    pub state: NativeSettingsLoadState,
    pub document: Option<NativeSettingsDocument>,
    pub failure: Option<NativeSettingsFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeSettingsSaveResult {
    pub saved: bool,
    pub failure: Option<NativeSettingsFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeSettingsPathResult {
    pub path: Option<String>,
    pub failure: Option<NativeSettingsFailure>,
}
