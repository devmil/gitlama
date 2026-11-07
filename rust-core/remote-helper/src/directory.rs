//! Bounded, read-only directory listing for the remote repository picker.
//!
//! Listing never follows links while reading entries and never descends below the listed
//! directory. A scan stops at 10 000 entries, 2 MiB of names or two seconds and reports that
//! it was truncated. Pages are served from the bounded sorted scan through cursors bound to the
//! directory's device, inode and modification time.
use gitlama_application::wire::runtime::{self as w, Map, Value};
use std::collections::VecDeque;
use std::ffi::OsString;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

pub const PAGE_ENTRIES: usize = 200;
const SCAN_ENTRIES: usize = 10_000;
const SCAN_NAME_BYTES: usize = 2 * 1024 * 1024;
const SCAN_TIME: Duration = Duration::from_secs(2);
const CURSOR_LIFETIME: Duration = Duration::from_mins(1);
const CURSORS: usize = 4;
/// The longest absolute path a client may name.
pub const PATH_BYTES: usize = gitlama_application::wire::contract::PATH_BYTES;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Kind {
    Directory,
    File,
    Symlink,
    Other,
}

impl Kind {
    const fn name(self) -> &'static str {
        match self {
            Self::Directory => "directory",
            Self::File => "file",
            Self::Symlink => "symlink",
            Self::Other => "other",
        }
    }
}

#[derive(Clone, Copy, Eq, PartialEq)]
struct Version {
    device: u64,
    inode: u64,
    modified_seconds: i64,
    modified_nanos: i64,
}

impl Version {
    fn of(metadata: &std::fs::Metadata) -> Self {
        Self {
            device: metadata.dev(),
            inode: metadata.ino(),
            modified_seconds: metadata.mtime(),
            modified_nanos: metadata.mtime_nsec(),
        }
    }
}

struct Cursor {
    token: String,
    directory: PathBuf,
    version: Version,
    entries: Vec<(Vec<u8>, Kind)>,
    offset: usize,
    truncated: bool,
    created: Instant,
}

/// Live cursors of one connection.
#[derive(Default)]
pub struct Listings {
    cursors: VecDeque<Cursor>,
}

/// A listing failure as a protocol error code.
pub type ListError = &'static str;

/// Validates an absolute client path: at most 16 KiB, no NUL.
///
/// # Errors
/// `pathInvalid`.
pub fn client_path(bytes: &[u8]) -> Result<PathBuf, ListError> {
    if bytes.is_empty() || bytes.len() > PATH_BYTES || bytes[0] != b'/' || bytes.contains(&0) {
        return Err("pathInvalid");
    }
    Ok(PathBuf::from(OsString::from_vec(bytes.to_vec())))
}

fn io_code(error: &std::io::Error) -> ListError {
    match error.kind() {
        std::io::ErrorKind::NotFound => "pathNotFound",
        std::io::ErrorKind::PermissionDenied => "permissionDenied",
        std::io::ErrorKind::NotADirectory => "notDirectory",
        _ => "pathInvalid",
    }
}

impl Listings {
    /// Answers one `listDirectory` call.
    ///
    /// # Errors
    /// A protocol error code.
    pub fn list(&mut self, arguments: &Value, home: Option<&Path>) -> Result<Value, ListError> {
        let object = w::object(arguments, "listDirectory", &["directory", "cursor"])
            .map_err(|_| "invalidRequest")?;
        self.cursors
            .retain(|cursor| cursor.created.elapsed() <= CURSOR_LIFETIME);
        if let Value::String(token) = object.field("cursor") {
            if !object.field("directory").is_null() {
                return Err("invalidRequest");
            }
            let index = self
                .cursors
                .iter()
                .position(|cursor| &cursor.token == token)
                .ok_or("cursorExpired")?;
            let mut cursor = self.cursors.remove(index).ok_or("cursorExpired")?;
            let current = std::fs::metadata(&cursor.directory).map_err(|e| io_code(&e))?;
            if Version::of(&current) != cursor.version {
                return Err("directoryChanged");
            }
            return Ok(self.page(&mut cursor));
        }
        if !object.field("cursor").is_null() {
            return Err("invalidRequest");
        }
        let requested = match object.field("directory") {
            Value::Null => home.ok_or("pathNotFound")?.to_path_buf(),
            value => client_path(&w::bytes_d(value).map_err(|_| "invalidRequest")?)?,
        };
        let directory = std::fs::canonicalize(&requested).map_err(|e| io_code(&e))?;
        let metadata = std::fs::metadata(&directory).map_err(|e| io_code(&e))?;
        if !metadata.is_dir() {
            return Err("notDirectory");
        }
        let (entries, truncated) = scan(&directory)?;
        let mut cursor = Cursor {
            token: crate::protocol::random_id().map_err(|_| "internal")?,
            directory,
            version: Version::of(&metadata),
            entries,
            offset: 0,
            truncated,
            created: Instant::now(),
        };
        Ok(self.page(&mut cursor))
    }

    fn page(&mut self, cursor: &mut Cursor) -> Value {
        let end = (cursor.offset + PAGE_ENTRIES).min(cursor.entries.len());
        let entries: Vec<Value> = cursor.entries[cursor.offset..end]
            .iter()
            .map(|(name, kind)| {
                let path = cursor.directory.join(std::ffi::OsStr::from_bytes(name));
                let repository = *kind == Kind::Directory
                    && std::fs::symlink_metadata(path.join(".git")).is_ok();
                let mut entry = Map::new();
                entry.insert("name".into(), w::bytes_e(name));
                entry.insert("kind".into(), Value::from(kind.name()));
                entry.insert("repository".into(), Value::Bool(repository));
                Value::Object(entry)
            })
            .collect();
        cursor.offset = end;
        let mut result = Map::new();
        result.insert(
            "directory".into(),
            w::bytes_e(cursor.directory.as_os_str().as_bytes()),
        );
        result.insert(
            "parent".into(),
            cursor.directory.parent().map_or(Value::Null, |parent| {
                w::bytes_e(parent.as_os_str().as_bytes())
            }),
        );
        result.insert("entries".into(), Value::Array(entries));
        result.insert("truncated".into(), Value::Bool(cursor.truncated));
        if end < cursor.entries.len() {
            result.insert("cursor".into(), Value::from(cursor.token.clone()));
            if self.cursors.len() == CURSORS {
                self.cursors.pop_front();
            }
            self.cursors.push_back(Cursor {
                token: cursor.token.clone(),
                directory: cursor.directory.clone(),
                version: cursor.version,
                entries: std::mem::take(&mut cursor.entries),
                offset: cursor.offset,
                truncated: cursor.truncated,
                created: cursor.created,
            });
        } else {
            result.insert("cursor".into(), Value::Null);
        }
        Value::Object(result)
    }
}

/// Sorted entry names and kinds, and whether the scan was truncated.
type Scan = (Vec<(Vec<u8>, Kind)>, bool);

fn scan(directory: &Path) -> Result<Scan, ListError> {
    let started = Instant::now();
    let mut entries = Vec::new();
    let mut name_bytes = 0;
    let mut truncated = false;
    for entry in std::fs::read_dir(directory).map_err(|e| io_code(&e))? {
        if entries.len() == SCAN_ENTRIES || started.elapsed() > SCAN_TIME {
            truncated = true;
            break;
        }
        let Ok(entry) = entry else {
            continue;
        };
        let name = entry.file_name().into_vec();
        if name_bytes + name.len() > SCAN_NAME_BYTES {
            truncated = true;
            break;
        }
        name_bytes += name.len();
        // The directory entry's own type: links are reported, never followed.
        let kind = match entry.file_type() {
            Ok(kind) if kind.is_symlink() => Kind::Symlink,
            Ok(kind) if kind.is_dir() => Kind::Directory,
            Ok(kind) if kind.is_file() => Kind::File,
            _ => Kind::Other,
        };
        entries.push((name, kind));
    }
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    Ok((entries, truncated))
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_application::wire::runtime::{parse, ParseLimits};

    fn arguments(directory: Option<&Path>, cursor: Option<&str>) -> Value {
        let mut map = Map::new();
        map.insert(
            "directory".into(),
            directory.map_or(Value::Null, |path| w::bytes_e(path.as_os_str().as_bytes())),
        );
        map.insert("cursor".into(), cursor.map_or(Value::Null, Value::from));
        Value::Object(map)
    }

    fn temporary(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "gitlama-helper-list-{name}-{}-{}",
            std::process::id(),
            crate::protocol::random_id().unwrap()
        ));
        std::fs::create_dir_all(&path).unwrap();
        std::fs::canonicalize(path).unwrap()
    }

    #[test]
    fn pages_are_sorted_bounded_and_invalidated_by_changes() {
        let root = temporary("pages");
        for index in 0..450 {
            std::fs::write(root.join(format!("f{index:04}")), b"").unwrap();
        }
        std::fs::create_dir(root.join("repo")).unwrap();
        std::fs::create_dir(root.join("repo/.git")).unwrap();
        std::os::unix::fs::symlink("/", root.join("link")).unwrap();
        // APFS refuses names that are not UTF-8, so macOS cannot hold this entry.
        let invalid_names = !cfg!(target_os = "macos");
        if invalid_names {
            std::fs::write(root.join(b"zbad\xff".as_slice().to_os_str()), b"").unwrap();
        }
        let mut listings = Listings::default();
        let first = listings.list(&arguments(Some(&root), None), None).unwrap();
        let entries = first["entries"].as_array().unwrap();
        assert_eq!(entries.len(), PAGE_ENTRIES);
        let names: Vec<Vec<u8>> = entries
            .iter()
            .map(|entry| w::bytes_d(&entry["name"]).unwrap())
            .collect();
        assert!(names.windows(2).all(|pair| pair[0] < pair[1]));
        let cursor = first["cursor"].as_str().unwrap().to_owned();
        let second = listings
            .list(&arguments(None, Some(&cursor)), None)
            .unwrap();
        assert_eq!(second["entries"].as_array().unwrap().len(), PAGE_ENTRIES);
        let third_cursor = second["cursor"].as_str().unwrap().to_owned();
        let third = listings
            .list(&arguments(None, Some(&third_cursor)), None)
            .unwrap();
        let last = third["entries"].as_array().unwrap();
        assert_eq!(
            last.len(),
            452 + usize::from(invalid_names) - 2 * PAGE_ENTRIES
        );
        assert!(third["cursor"].is_null());
        let kinds: Vec<(Vec<u8>, String, bool)> = last
            .iter()
            .map(|entry| {
                (
                    w::bytes_d(&entry["name"]).unwrap(),
                    entry["kind"].as_str().unwrap().to_owned(),
                    entry["repository"].as_bool().unwrap(),
                )
            })
            .collect();
        assert!(kinds.contains(&(b"link".to_vec(), "symlink".into(), false)));
        assert!(kinds.contains(&(b"repo".to_vec(), "directory".into(), true)));
        assert_eq!(
            kinds.contains(&(b"zbad\xff".to_vec(), "file".into(), false)),
            invalid_names
        );

        let fresh = listings.list(&arguments(Some(&root), None), None).unwrap();
        let cursor = fresh["cursor"].as_str().unwrap().to_owned();
        std::thread::sleep(Duration::from_millis(20));
        std::fs::write(root.join("new"), b"").unwrap();
        assert_eq!(
            listings.list(&arguments(None, Some(&cursor)), None).err(),
            Some("directoryChanged")
        );
        assert_eq!(
            listings
                .list(&arguments(None, Some("0".repeat(32).as_str())), None)
                .err(),
            Some("cursorExpired")
        );
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn paths_are_validated_and_errors_are_typed() {
        let mut listings = Listings::default();
        let relative = parse(br#"{"directory":"cmVs","cursor":null}"#, ParseLimits::FRAME).unwrap();
        assert_eq!(listings.list(&relative, None).err(), Some("pathInvalid"));
        let nul = arguments(None, None);
        assert_eq!(listings.list(&nul, None).err(), Some("pathNotFound"));
        let mut map = Map::new();
        map.insert("directory".into(), w::bytes_e(b"/tmp\0x"));
        map.insert("cursor".into(), Value::Null);
        assert_eq!(
            listings.list(&Value::Object(map), None).err(),
            Some("pathInvalid")
        );
        let missing = Path::new("/nonexistent-gitlama-helper-test");
        assert_eq!(
            listings.list(&arguments(Some(missing), None), None).err(),
            Some("pathNotFound")
        );
        let root = temporary("file");
        std::fs::write(root.join("file"), b"").unwrap();
        assert_eq!(
            listings
                .list(&arguments(Some(&root.join("file")), None), None)
                .err(),
            Some("notDirectory")
        );
        let home = listings.list(&arguments(None, None), Some(&root)).unwrap();
        assert_eq!(
            w::bytes_d(&home["directory"]).unwrap(),
            root.as_os_str().as_bytes()
        );
        std::fs::remove_dir_all(root).unwrap();
    }

    trait ToOsStr {
        fn to_os_str(&self) -> &std::ffi::OsStr;
    }

    impl ToOsStr for [u8] {
        fn to_os_str(&self) -> &std::ffi::OsStr {
            std::ffi::OsStr::from_bytes(self)
        }
    }
}
