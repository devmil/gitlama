//! Update checks and the release channel. Linux and Windows compare the installed build with the
//! public release index when the user asks and point to the downloads
//! page; nothing from the index is opened or downloaded. macOS hands the
//! work to Sparkle (`sparkle` below). A failure never blocks startup.

use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::settings::SettingsService;
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

pub const INDEX_URL: &str = "https://devmil.de/gitlama/_data/releases.json";
pub const DOWNLOADS_URL: &str = "https://devmil.de/gitlama/releases.html";
/// The index is signed metadata of at most this size; the publisher
/// enforces the same bound.
pub const INDEX_MAXIMUM_BYTES: usize = 1024 * 1024;
/// The publisher retains five releases per channel.
pub const INDEX_MAXIMUM_RELEASES: usize = 10;
const INDEX_TIMEOUT_SECONDS: u32 = 15;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Channel {
    Stable,
    Beta,
}

impl Channel {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "stable" => Some(Self::Stable),
            "beta" => Some(Self::Beta),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Stable => "stable",
            Self::Beta => "beta",
        }
    }

    /// A prerelease build follows the beta channel until the user chooses.
    pub fn of_version(version: &str) -> Self {
        if version.contains('-') {
            Self::Beta
        } else {
            Self::Stable
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Release {
    pub version: String,
    pub build: u64,
    pub channel: Channel,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Failure {
    Unsupported,
    Unavailable,
    InvalidIndex,
    NativeUpdater,
}

impl Failure {
    pub fn key(self) -> &'static str {
        match self {
            Self::Unsupported => "updatesFailureUnsupported",
            Self::Unavailable => "updatesFailureUnavailable",
            Self::InvalidIndex => "updatesFailureInvalid",
            Self::NativeUpdater => "updatesFailureUpdater",
        }
    }
}

/// Reads the releases of a GitLama release index, newest build first.
pub fn parse_index(bytes: &[u8]) -> Result<Vec<Release>, Failure> {
    if bytes.is_empty() || bytes.len() > INDEX_MAXIMUM_BYTES {
        return Err(Failure::InvalidIndex);
    }
    let document: Value = serde_json::from_slice(bytes).map_err(|_| Failure::InvalidIndex)?;
    if document["schema_version"] != json!(1) || document["product"] != json!("GitLama") {
        return Err(Failure::InvalidIndex);
    }
    let records = document["releases"]
        .as_array()
        .ok_or(Failure::InvalidIndex)?;
    if records.is_empty() || records.len() > INDEX_MAXIMUM_RELEASES {
        return Err(Failure::InvalidIndex);
    }
    let mut releases = Vec::new();
    let mut builds = std::collections::HashSet::new();
    for record in records {
        let version = record["version"]
            .as_str()
            .filter(|version| !version.is_empty() && version.len() <= 128);
        let build = record["build"].as_u64().filter(|build| *build >= 1);
        let channel = record["channel"].as_str().and_then(Channel::parse);
        let (Some(version), Some(build), Some(channel)) = (version, build, channel) else {
            return Err(Failure::InvalidIndex);
        };
        if version.contains('-') != (channel == Channel::Beta) || !builds.insert(build) {
            return Err(Failure::InvalidIndex);
        }
        releases.push(Release {
            version: version.to_owned(),
            build,
            channel,
        });
    }
    releases.sort_by_key(|release| std::cmp::Reverse(release.build));
    Ok(releases)
}

/// The newest release a subscriber of `channel` receives.
pub fn latest(releases: &[Release], channel: Channel) -> Option<&Release> {
    releases
        .iter()
        .filter(|release| channel == Channel::Beta || release.channel == Channel::Stable)
        .max_by_key(|release| release.build)
}

/// Whether this platform reports updates from the public index.
pub const INDEX_AVAILABLE: bool = cfg!(any(target_os = "linux", target_os = "windows"));

/// The outcome of the last check.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Outcome {
    NativeCheckerOpened,
    UpToDate,
    NoPublishedRelease,
    Available(Release),
}

pub struct UpdateService {
    settings: Rc<SettingsService>,
    notifier: Notifier,
    installed: Option<(String, u64)>,
    checking: Cell<bool>,
    generation: Cell<u64>,
    outcome: RefCell<Option<Result<Outcome, Failure>>>,
}

impl UpdateService {
    pub async fn new(settings: Rc<SettingsService>, notifier: Notifier) -> Rc<Self> {
        let release = rt::blocking(gitlama_core::api::application_release).await;
        let installed = (!release.version.is_empty() && release.build > 0)
            .then(|| (release.version, u64::from(release.build)));
        let this = Rc::new(Self {
            settings,
            notifier,
            installed,
            checking: Cell::new(false),
            generation: Cell::new(0),
            outcome: RefCell::new(None),
        });
        if this.sparkle_available() {
            this.configure_sparkle();
        }
        this
    }

    fn sparkle_available(&self) -> bool {
        self.installed.is_some() && sparkle::available()
    }

    pub fn is_supported(&self) -> bool {
        self.installed.is_some() && (sparkle::available() || INDEX_AVAILABLE)
    }

    pub fn channel(&self) -> Channel {
        self.settings
            .with(|document| document.release_channel.as_deref().and_then(Channel::parse))
            .or_else(|| {
                self.installed
                    .as_ref()
                    .map(|(version, _)| Channel::of_version(version))
            })
            .unwrap_or(Channel::Stable)
    }

    fn configure_sparkle(&self) {
        sparkle::configure(self.channel());
    }

    pub async fn select_channel(&self, channel: Channel) {
        let saved = self
            .settings
            .update_durable(
                |document| document.release_channel = Some(channel.name().to_owned()),
                |current, previous| current.release_channel = previous.release_channel.clone(),
            )
            .await;
        *self.outcome.borrow_mut() = saved.err().map(|_| Err(Failure::NativeUpdater));
        if self.sparkle_available() {
            self.configure_sparkle();
        }
        self.notifier.notify(Topics::UPDATES);
    }

    pub async fn check(&self) {
        let generation = self.generation.get() + 1;
        self.generation.set(generation);
        self.checking.set(true);
        *self.outcome.borrow_mut() = None;
        self.notifier.notify(Topics::UPDATES);
        let outcome = self.run_check().await;
        if self.generation.get() != generation {
            return;
        }
        self.checking.set(false);
        *self.outcome.borrow_mut() = Some(outcome);
        self.notifier.notify(Topics::UPDATES);
    }

    async fn run_check(&self) -> Result<Outcome, Failure> {
        let Some((_, build)) = self.installed.clone() else {
            return Err(Failure::Unsupported);
        };
        if self.sparkle_available() {
            self.configure_sparkle();
            return if sparkle::check() {
                Ok(Outcome::NativeCheckerOpened)
            } else {
                Err(Failure::NativeUpdater)
            };
        }
        if !INDEX_AVAILABLE {
            return Err(Failure::Unsupported);
        }
        let channel = self.channel();
        let bytes = rt::blocking(fetch_index).await?;
        let releases = parse_index(&bytes)?;
        Ok(match latest(&releases, channel) {
            None => Outcome::NoPublishedRelease,
            Some(release) if release.build > build => Outcome::Available(release.clone()),
            Some(_) => Outcome::UpToDate,
        })
    }

    pub fn value(&self) -> Value {
        let outcome = self.outcome.borrow();
        let (status, failure) = match outcome.as_ref() {
            None => (Value::Null, Value::Null),
            Some(Err(failure)) => (Value::Null, json!(failure.key())),
            Some(Ok(Outcome::NativeCheckerOpened)) => (Value::Null, Value::Null),
            Some(Ok(Outcome::UpToDate)) => (json!({"kind": "upToDate"}), Value::Null),
            Some(Ok(Outcome::NoPublishedRelease)) => (json!({"kind": "noRelease"}), Value::Null),
            Some(Ok(Outcome::Available(release))) => (
                json!({"kind": "available", "version": release.version, "build": release.build}),
                Value::Null,
            ),
        };
        json!({
            "supported": self.is_supported(),
            "installsUpdates": self.sparkle_available(),
            "installed": self.installed.as_ref().map(|(version, build)| json!({"version": version, "build": build})),
            "channel": self.channel().name(),
            "checking": self.checking.get(),
            "status": status,
            "failure": failure,
            "downloadsUrl": DOWNLOADS_URL,
        })
    }
}

/// Reads the index over HTTPS with curl: bounded in time and size, no
/// redirect. Socket, TLS and HTTP failures carry host details, so only the
/// failure kind is kept.
fn fetch_index() -> Result<Vec<u8>, Failure> {
    let output = std::process::Command::new("curl")
        .args([
            "--silent",
            "--fail",
            "--proto",
            "=https",
            "--max-redirs",
            "0",
            "--max-time",
            &INDEX_TIMEOUT_SECONDS.to_string(),
            "--max-filesize",
            &INDEX_MAXIMUM_BYTES.to_string(),
            "--header",
            "Accept: application/json",
            INDEX_URL,
        ])
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .map_err(|_| Failure::Unavailable)?;
    match output.status.code() {
        Some(0) => Ok(output.stdout),
        // 63: the maximum file size was exceeded.
        Some(63) => Err(Failure::InvalidIndex),
        _ => Err(Failure::Unavailable),
    }
}

/// The platform updater a host installs (Sparkle on macOS): whether it
/// loaded, configuring its channel and opening its check.
#[derive(Clone, Copy)]
pub struct NativeUpdater {
    pub loaded: fn() -> bool,
    pub configure: fn(&str) -> bool,
    pub check: fn() -> bool,
}

static NATIVE_UPDATER: std::sync::OnceLock<NativeUpdater> = std::sync::OnceLock::new();

/// Installs the platform updater; the macOS host calls this before startup.
pub fn set_native_updater(updater: NativeUpdater) {
    let _ = NATIVE_UPDATER.set(updater);
}

/// Sparkle drives updates on macOS: it checks on its own schedule and
/// installs after the user confirms. Debug builds and isolated profiles
/// have no updater, so they never touch the user's Sparkle state.
mod sparkle {
    use super::{Channel, NATIVE_UPDATER};

    pub fn available() -> bool {
        !cfg!(debug_assertions)
            && std::env::var_os("GITLAMA_PROFILE_ROOT").is_none()
            && NATIVE_UPDATER
                .get()
                .is_some_and(|updater| (updater.loaded)())
    }

    pub fn configure(channel: Channel) {
        if let Some(updater) = NATIVE_UPDATER.get() {
            (updater.configure)(channel.name());
        }
    }

    pub fn check() -> bool {
        NATIVE_UPDATER
            .get()
            .is_some_and(|updater| (updater.check)())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn index(releases: Value) -> Vec<u8> {
        serde_json::to_vec(
            &json!({"schema_version": 1, "product": "GitLama", "releases": releases}),
        )
        .unwrap()
    }

    #[test]
    fn the_index_lists_releases_newest_first() {
        let releases = parse_index(&index(json!([
            {"version": "0.1.0", "build": 3, "channel": "stable"},
            {"version": "0.2.0-beta.1", "build": 5, "channel": "beta"},
        ])))
        .unwrap();
        assert_eq!(releases[0].build, 5);
        assert_eq!(latest(&releases, Channel::Stable).unwrap().build, 3);
        assert_eq!(latest(&releases, Channel::Beta).unwrap().build, 5);
    }

    #[test]
    fn malformed_indexes_are_refused() {
        assert_eq!(parse_index(b""), Err(Failure::InvalidIndex));
        assert_eq!(parse_index(b"{}"), Err(Failure::InvalidIndex));
        // A stable channel with a prerelease version.
        assert_eq!(
            parse_index(&index(
                json!([{"version": "1.0.0-beta", "build": 1, "channel": "stable"}])
            )),
            Err(Failure::InvalidIndex)
        );
        // Duplicate builds.
        assert_eq!(
            parse_index(&index(json!([
                {"version": "1.0.0", "build": 1, "channel": "stable"},
                {"version": "1.0.1", "build": 1, "channel": "stable"},
            ]))),
            Err(Failure::InvalidIndex)
        );
        let other =
            serde_json::to_vec(&json!({"schema_version": 1, "product": "Other", "releases": []}))
                .unwrap();
        assert_eq!(parse_index(&other), Err(Failure::InvalidIndex));
    }

    #[test]
    fn prerelease_builds_follow_beta() {
        assert_eq!(Channel::of_version("0.1.0-beta.68"), Channel::Beta);
        assert_eq!(Channel::of_version("1.0.0"), Channel::Stable);
    }
}
