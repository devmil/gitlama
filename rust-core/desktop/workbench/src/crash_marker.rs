//! A small marker that survives a crash: the panic hook writes which build
//! panicked, where in GitLama's own source and on which thread, and the next
//! launch moves it into the diagnostic history. The history itself stays in
//! memory (the devmil-logging contract); the marker never holds a panic
//! message, a path outside the source tree or any repository content.

use crate::diagnostics;
use std::cell::Cell;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

const FILE_NAME: &str = "last-session-panic";
/// A marker larger than this is not GitLama's and is ignored.
const MAX_MARKER_BYTES: u64 = 512;

static MARKER: OnceLock<(PathBuf, String)> = OnceLock::new();

thread_local! {
    static IN_HOOK: Cell<bool> = const { Cell::new(false) };
}

/// The marker's location in the settings directory (`settings` names the
/// settings file).
pub fn marker_path(settings: &Path) -> Option<PathBuf> {
    settings.parent().map(|dir| dir.join(FILE_NAME))
}

/// What a marker records.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Marker {
    pub build: String,
    pub location: String,
    pub thread: String,
}

impl Marker {
    fn render(&self) -> String {
        format!(
            "build {}\nlocation {}\nthread {}\n",
            self.build, self.location, self.thread
        )
    }

    fn parse(text: &str) -> Option<Self> {
        let mut build = None;
        let mut location = None;
        let mut thread = None;
        for line in text.lines() {
            let (key, value) = line.split_once(' ')?;
            if !public(value) {
                return None;
            }
            match key {
                "build" => build = Some(value.to_owned()),
                "location" => location = Some(value.to_owned()),
                "thread" => thread = Some(value.to_owned()),
                _ => {}
            }
        }
        Some(Self {
            build: build?,
            location: location?,
            thread: thread?,
        })
    }
}

/// Text a marker may carry: short, and only characters of source file
/// names, build identifiers and thread names.
fn public(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 96
        && value.bytes().all(|b| {
            b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-' | b'/' | b':' | b'+')
        })
}

/// The last two components of a source file, so a dependency's location
/// does not carry the builder's home directory.
pub fn source_location(file: &str, line: u32) -> String {
    let mut parts = file.rsplit(['/', '\\']).filter(|part| !part.is_empty());
    let name = parts.next().unwrap_or("unknown");
    let location = match parts.next() {
        Some(dir) => format!("{dir}/{name}:{line}"),
        None => format!("{name}:{line}"),
    };
    if public(&location) {
        location
    } else {
        "unknown".to_owned()
    }
}

fn thread_label(name: Option<&str>) -> String {
    match name {
        Some(name) if public(name) && name.len() <= 32 => name.to_owned(),
        Some(_) => "other".to_owned(),
        None => "unnamed".to_owned(),
    }
}

/// Reads and removes the previous session's marker, recording it in the
/// diagnostic history, then installs the panic hook that writes this
/// session's. `build` identifies this build.
pub fn install(settings: &Path, build: &str) -> Option<Marker> {
    let path = marker_path(settings)?;
    let previous = take(&path);
    if let Some(marker) = &previous {
        diagnostics::warning(
            "Launcher",
            "previous_session_panicked",
            &[
                ("location", marker.location.as_str().into()),
                ("thread", marker.thread.as_str().into()),
                ("same_build", (marker.build == build).into()),
            ],
        );
    }
    if MARKER.set((path, build.to_owned())).is_ok() {
        let default = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            record_panic(
                info.location()
                    .map(|at| source_location(at.file(), at.line())),
            );
            default(info);
        }));
    }
    previous
}

fn record_panic(location: Option<String>) {
    // A panic inside the hook (or the history it writes) must not recurse.
    if IN_HOOK.with(|flag| flag.replace(true)) {
        return;
    }
    let marker = Marker {
        build: MARKER
            .get()
            .map_or_else(|| "unknown".to_owned(), |(_, build)| build.clone()),
        location: location.unwrap_or_else(|| "unknown".to_owned()),
        thread: thread_label(std::thread::current().name()),
    };
    if let Some((path, _)) = MARKER.get() {
        let _ = std::fs::write(path, marker.render());
    }
    diagnostics::severe(
        "Launcher",
        "panic",
        &[
            ("location", marker.location.as_str().into()),
            ("thread", marker.thread.as_str().into()),
        ],
    );
    IN_HOOK.with(|flag| flag.set(false));
}

/// A clean exit: a panic this session survived is already in the history.
pub fn clear() {
    if let Some((path, _)) = MARKER.get() {
        let _ = std::fs::remove_file(path);
    }
}

fn take(path: &Path) -> Option<Marker> {
    let metadata = std::fs::metadata(path).ok()?;
    let text = (metadata.is_file() && metadata.len() <= MAX_MARKER_BYTES)
        .then(|| std::fs::read_to_string(path).ok())
        .flatten();
    let _ = std::fs::remove_file(path);
    text.as_deref().and_then(Marker::parse)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_location_keeps_only_the_last_two_components() {
        assert_eq!(
            source_location("desktop/workbench/src/changes.rs", 12),
            "src/changes.rs:12"
        );
        assert_eq!(
            source_location("/home/someone/.cargo/registry/src/x/serde-1.0/src/de.rs", 3),
            "src/de.rs:3"
        );
        assert_eq!(
            source_location("C:\\Users\\a b\\src\\x.rs", 1),
            "src/x.rs:1"
        );
        assert_eq!(source_location("src/a b.rs", 1), "unknown");
        assert_eq!(source_location("main.rs", 7), "main.rs:7");
    }

    #[test]
    fn thread_names_outside_the_public_set_are_hidden() {
        assert_eq!(thread_label(Some("repository-worker")), "repository-worker");
        assert_eq!(thread_label(Some("my secret repo")), "other");
        assert_eq!(thread_label(None), "unnamed");
    }

    #[test]
    fn a_marker_round_trips_and_is_removed_when_read() {
        let dir = std::env::temp_dir().join(format!("gitlama-marker-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = marker_path(&dir.join("settings.json")).unwrap();
        let marker = Marker {
            build: "0.1.0+42".into(),
            location: "src/changes.rs:12".into(),
            thread: "main".into(),
        };
        std::fs::write(&path, marker.render()).unwrap();
        assert_eq!(take(&path), Some(marker));
        assert!(!path.exists());
        assert_eq!(take(&path), None);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_marker_with_foreign_text_is_dropped() {
        assert_eq!(
            Marker::parse("build 1\nlocation /home/x y\nthread main\n"),
            None
        );
        assert_eq!(Marker::parse("build 1\nthread main\n"), None);
    }
}
