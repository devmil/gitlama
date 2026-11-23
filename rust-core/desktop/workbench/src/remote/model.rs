//! Remote workspace values (the Dart `models/remote_workspace.dart`): failure codes,
//! connection phases, helper targets and the validation of profiles and paths.

use gitlama_application::wire::contract::{self, RemoteCapability};
use gitlama_contract::domain::path_identity::NativeRemoteAuthority;
use gitlama_contract::storage::{NativeRemoteHostProfile, NativeRemoteVerifiedIdentity};
use std::collections::HashSet;

/// Stable, localized remote failure codes. Raw SSH or helper output never becomes text.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Failure {
    OutcomeUnknown,
    SshUnavailable,
    SshUnsupported,
    SshConnectionFailed,
    HelperNotInstalled,
    InstallUnavailable,
    InstallDirectory,
    InstallWrite,
    InstallDigest,
    InstallExecute,
    InstallFailed,
    UnsupportedPlatform,
    BootstrapFailed,
    HandshakeTimeout,
    ProtocolMismatch,
    BuildMismatch,
    GitMissing,
    GitUnsupported,
    StoreUnavailable,
    IdentityChanged,
    IdentityMismatch,
    ProtocolViolation,
    Disconnected,
    TimedOut,
    Canceled,
    Capacity,
    Unsupported,
    PathInvalid,
    PathNotFound,
    PermissionDenied,
    NotDirectory,
    DirectoryChanged,
    CursorExpired,
    WriteNotPermitted,
    PreviewExpired,
    PreconditionFailed,
    OperationIdConflict,
    ReceiptCapacity,
    Internal,
}

impl Failure {
    /// The Dart enum value name, which the localized messages are keyed by.
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::OutcomeUnknown => "outcomeUnknown",
            Self::SshUnavailable => "sshUnavailable",
            Self::SshUnsupported => "sshUnsupported",
            Self::SshConnectionFailed => "sshConnectionFailed",
            Self::HelperNotInstalled => "helperNotInstalled",
            Self::InstallUnavailable => "installUnavailable",
            Self::InstallDirectory => "installDirectory",
            Self::InstallWrite => "installWrite",
            Self::InstallDigest => "installDigest",
            Self::InstallExecute => "installExecute",
            Self::InstallFailed => "installFailed",
            Self::UnsupportedPlatform => "unsupportedPlatform",
            Self::BootstrapFailed => "bootstrapFailed",
            Self::HandshakeTimeout => "handshakeTimeout",
            Self::ProtocolMismatch => "protocolMismatch",
            Self::BuildMismatch => "buildMismatch",
            Self::GitMissing => "gitMissing",
            Self::GitUnsupported => "gitUnsupported",
            Self::StoreUnavailable => "storeUnavailable",
            Self::IdentityChanged => "identityChanged",
            Self::IdentityMismatch => "identityMismatch",
            Self::ProtocolViolation => "protocolViolation",
            Self::Disconnected => "disconnected",
            Self::TimedOut => "timedOut",
            Self::Canceled => "canceled",
            Self::Capacity => "capacity",
            Self::Unsupported => "unsupported",
            Self::PathInvalid => "pathInvalid",
            Self::PathNotFound => "pathNotFound",
            Self::PermissionDenied => "permissionDenied",
            Self::NotDirectory => "notDirectory",
            Self::DirectoryChanged => "directoryChanged",
            Self::CursorExpired => "cursorExpired",
            Self::WriteNotPermitted => "writeNotPermitted",
            Self::PreviewExpired => "previewExpired",
            Self::PreconditionFailed => "preconditionFailed",
            Self::OperationIdConflict => "operationIdConflict",
            Self::ReceiptCapacity => "receiptCapacity",
            Self::Internal => "internal",
        }
    }

    /// Failures a (re)installation of the bundled helper can resolve.
    #[must_use]
    pub const fn install_resolves(self) -> bool {
        matches!(
            self,
            Self::HelperNotInstalled
                | Self::InstallDirectory
                | Self::InstallWrite
                | Self::InstallDigest
                | Self::InstallExecute
                | Self::InstallFailed
        )
    }

    /// Failures a later attempt can overcome without the user.
    #[must_use]
    pub const fn retriable(self) -> bool {
        matches!(
            self,
            Self::Disconnected
                | Self::TimedOut
                | Self::SshConnectionFailed
                | Self::HandshakeTimeout
                | Self::BootstrapFailed
        )
    }
}

/// A failure with the helper the host needs, when the launch reported it missing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RemoteError {
    pub code: Failure,
    pub host_target: Option<HelperTarget>,
}

impl From<Failure> for RemoteError {
    fn from(code: Failure) -> Self {
        Self {
            code,
            host_target: None,
        }
    }
}

/// The connection lifecycle, orthogonal to the repository phase.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Idle,
    Installing,
    Connecting,
    Handshaking,
    Ready,
    Disconnecting,
    Disconnected,
    Failed,
    IdentityChanged,
    Retired,
}

impl Phase {
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Installing => "installing",
            Self::Connecting => "connecting",
            Self::Handshaking => "handshaking",
            Self::Ready => "ready",
            Self::Disconnecting => "disconnecting",
            Self::Disconnected => "disconnected",
            Self::Failed => "failed",
            Self::IdentityChanged => "identityChanged",
            Self::Retired => "retired",
        }
    }
}

/// Why a live host connection grants no writes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WriteBlock {
    NotAllowed,
    Reconnect,
    LedgerUnavailable,
}

impl WriteBlock {
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::NotAllowed => "notAllowed",
            Self::Reconnect => "reconnect",
            Self::LedgerUnavailable => "ledgerUnavailable",
        }
    }
}

/// A host platform a remote helper is built for.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum HelperTarget {
    LinuxX86_64,
    LinuxArm64,
    MacosArm64,
    MacosX86_64,
}

impl HelperTarget {
    pub const ALL: [Self; 4] = [
        Self::LinuxX86_64,
        Self::LinuxArm64,
        Self::MacosArm64,
        Self::MacosX86_64,
    ];

    /// The bundle directory that carries this helper.
    #[must_use]
    pub const fn directory(self) -> &'static str {
        match self {
            Self::LinuxX86_64 => "linux-x86_64",
            Self::LinuxArm64 => "linux-arm64",
            Self::MacosArm64 => "macos-arm64",
            Self::MacosX86_64 => "macos-x86_64",
        }
    }

    /// The Rust target the helper is compiled for.
    #[must_use]
    pub const fn triple(self) -> &'static str {
        match self {
            Self::LinuxX86_64 => "x86_64-unknown-linux-gnu",
            Self::LinuxArm64 => "aarch64-unknown-linux-gnu",
            Self::MacosArm64 => "aarch64-apple-darwin",
            Self::MacosX86_64 => "x86_64-apple-darwin",
        }
    }

    /// `uname -s` and `uname -m` of a host that runs it.
    #[must_use]
    pub const fn host(self) -> &'static str {
        match self {
            Self::LinuxX86_64 => "Linux/x86_64",
            Self::LinuxArm64 => "Linux/aarch64",
            Self::MacosArm64 => "Darwin/arm64",
            Self::MacosX86_64 => "Darwin/x86_64",
        }
    }
}

/// A helper that ships with this application, for one host platform.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HelperArtifact {
    pub build_id: String,
    pub target: HelperTarget,
    pub sha256: String,
    pub bytes: Vec<u8>,
}

impl HelperArtifact {
    /// Where the installation places it on a host, relative to the home.
    #[must_use]
    pub fn install_path(&self) -> String {
        format!(
            "~/.local/lib/gitlama/remote/{}/gitlama-remote-helper",
            self.build_id
        )
    }
}

/// What a helper reported in its hello, after validation.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HelperInfo {
    pub build_id: String,
    pub incarnation: String,
    pub store_id: String,
    pub account_uid: String,
    pub account_name: String,
    pub git_version: Option<String>,
    /// The negotiated intersection.
    pub capabilities: HashSet<RemoteCapability>,
}

/// One profile's connection as the user sees it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConnectionState {
    pub profile_id: String,
    pub phase: Phase,
    pub failure: Option<Failure>,
    pub helper: Option<HelperInfo>,
}

impl ConnectionState {
    #[must_use]
    pub fn new(profile_id: &str, phase: Phase) -> Self {
        Self {
            profile_id: profile_id.to_owned(),
            phase,
            failure: None,
            helper: None,
        }
    }

    #[must_use]
    pub fn failed(profile_id: &str, phase: Phase, failure: Failure) -> Self {
        Self {
            failure: Some(failure),
            ..Self::new(profile_id, phase)
        }
    }

    #[must_use]
    pub fn ready(&self) -> bool {
        self.phase == Phase::Ready
    }
}

/// An entry of a remote directory listing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EntryKind {
    Directory,
    File,
    Symlink,
    Other,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DirectoryEntry {
    pub name: Vec<u8>,
    pub kind: EntryKind,
    pub repository: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DirectoryPage {
    pub directory: Vec<u8>,
    pub parent: Option<Vec<u8>>,
    pub entries: Vec<DirectoryEntry>,
    pub cursor: Option<String>,
    pub truncated: bool,
}

/// At most this many profiles are kept.
pub const PROFILE_CAPACITY: usize = 64;

fn is_alias_part(part: &str) -> bool {
    let mut characters = part.chars();
    characters
        .next()
        .is_some_and(|first| first.is_ascii_alphanumeric())
        && characters.all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
}

/// Whether `alias` is a host or `user@host`, at most 128 ASCII characters.
#[must_use]
pub fn is_valid_alias(alias: &str) -> bool {
    if alias.len() > 128 {
        return false;
    }
    match alias.split_once('@') {
        Some((user, host)) => is_alias_part(user) && is_alias_part(host),
        None => is_alias_part(alias),
    }
}

fn displayable(c: char) -> bool {
    let code = u32::from(c);
    code >= 0x20 && !(0x7f..=0x9f).contains(&code)
}

/// Whether `label` is a valid profile label.
#[must_use]
pub fn is_valid_label(label: &str) -> bool {
    let count = label.chars().count();
    count > 0 && count <= 128 && !label.trim().is_empty() && label.chars().all(displayable)
}

fn is_lower_hex(text: &str, length: usize) -> bool {
    text.len() == length
        && text
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

pub fn is_valid_profile_id(id: &str) -> bool {
    let parts: Vec<&str> = id.split('-').collect();
    parts.len() == 5
        && [8, 4, 4, 4, 12]
            .iter()
            .zip(&parts)
            .all(|(length, part)| is_lower_hex(part, *length))
}

pub fn is_valid_store_id(id: &str) -> bool {
    is_lower_hex(id, 32)
}

pub fn is_valid_account_uid(uid: &str) -> bool {
    !uid.is_empty()
        && uid.len() <= 10
        && uid.bytes().all(|byte| byte.is_ascii_digit())
        && (uid == "0" || !uid.starts_with('0'))
        && uid
            .parse::<u64>()
            .is_ok_and(|value| value <= u64::from(u32::MAX))
}

pub fn is_valid_account_name(name: &str) -> bool {
    name.len() <= 128 && name.chars().all(displayable)
}

/// Whether `bytes` are an absolute remote path: 1–16 KiB, starting with `/`, without NUL.
#[must_use]
pub fn is_valid_path(bytes: &[u8]) -> bool {
    !bytes.is_empty()
        && bytes.len() <= contract::PATH_BYTES
        && bytes[0] == b'/'
        && !bytes.contains(&0)
}

/// The authority a profile's verified identity grants.
#[must_use]
pub fn authority_of(profile: &NativeRemoteHostProfile) -> Option<NativeRemoteAuthority> {
    profile
        .verified
        .as_ref()
        .map(|identity| NativeRemoteAuthority {
            profile_id: profile.id.clone(),
            store_id: identity.store_id.clone(),
            account_uid: identity.account_uid.clone(),
        })
}

/// The identity a hello reported.
#[must_use]
pub fn identity_of(helper: &HelperInfo) -> NativeRemoteVerifiedIdentity {
    NativeRemoteVerifiedIdentity {
        store_id: helper.store_id.clone(),
        account_uid: helper.account_uid.clone(),
        account_name: helper.account_name.clone(),
    }
}

/// A fresh random lowercase UUID (version 4).
#[must_use]
pub fn new_uuid() -> String {
    let mut bytes = [0_u8; 16];
    let _ = getrandom::fill(&mut bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex = hex(&bytes);
    format!(
        "{}-{}-{}-{}-{}",
        &hex[0..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..32]
    )
}

/// 16 random bytes as 32 lowercase hex digits.
#[must_use]
pub fn random_hex32() -> String {
    let mut bytes = [0_u8; 16];
    let _ = getrandom::fill(&mut bytes);
    hex(&bytes)
}

#[must_use]
pub fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    bytes.iter().fold(String::new(), |mut out, byte| {
        let _ = write!(out, "{byte:02x}");
        out
    })
}

/// Renders native path bytes for display: valid UTF-8 as text, other bytes as `\xNN`.
/// Never parsed back into a path.
#[must_use]
pub fn display_path(bytes: &[u8]) -> String {
    let mut out = String::new();
    let mut index = 0;
    while index < bytes.len() {
        let byte = bytes[index];
        let length = match byte {
            0..=0x7f => 1,
            0xc2..=0xdf => 2,
            0xe0..=0xef => 3,
            0xf0..=0xf4 => 4,
            _ => 0,
        };
        let decoded = (length > 0 && index + length <= bytes.len())
            .then(|| std::str::from_utf8(&bytes[index..index + length]).ok())
            .flatten()
            .and_then(|text| text.chars().next())
            .filter(|c| displayable(*c));
        match decoded {
            Some('\\') => out.push_str("\\\\"),
            Some(c) => out.push(c),
            None => {
                out.push_str(&format!("\\x{byte:02x}"));
                index += 1;
                continue;
            }
        }
        index += length;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aliases_are_hosts_or_user_at_host() {
        for valid in ["host", "alice@build-1.example", "a", "x_y.z"] {
            assert!(is_valid_alias(valid), "{valid}");
        }
        for invalid in [
            "",
            "-oProxyCommand=x",
            "ssh://host",
            "host:22",
            "a b",
            "@host",
            "user@",
            "a@b@c",
            &"a".repeat(129),
        ] {
            assert!(!is_valid_alias(invalid), "{invalid}");
        }
    }

    #[test]
    fn identities_and_labels_are_validated() {
        assert!(is_valid_profile_id("0123abcd-0000-4000-8000-0123456789ab"));
        assert!(!is_valid_profile_id("0123ABCD-0000-4000-8000-0123456789ab"));
        assert!(is_valid_store_id(&"a".repeat(32)));
        assert!(is_valid_account_uid("0") && is_valid_account_uid("4294967295"));
        assert!(!is_valid_account_uid("01") && !is_valid_account_uid("4294967296"));
        assert!(
            is_valid_label("Build server") && !is_valid_label("  ") && !is_valid_label("a\u{7}")
        );
        assert!(is_valid_profile_id(&new_uuid()));
    }

    #[test]
    fn paths_display_without_reinterpretation() {
        assert_eq!(display_path(b"/home/al\xc3\xa9"), "/home/alé");
        assert_eq!(display_path(b"/a\xffb\\"), "/a\\xffb\\\\");
        assert_eq!(display_path(b"/\x01"), "/\\x01");
        assert!(is_valid_path(b"/x") && !is_valid_path(b"x") && !is_valid_path(b"/a\0"));
    }
}
