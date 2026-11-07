//! Disposable presentation cache, one entry per repository.
//!
//! The interface layer owns the content and its schema. This module stores
//! opaque bytes privately and bounded, and never reports their content. Every
//! failure means "no entry": callers fall back to loading the repository.
pub use gitlama_contract::view_cache::*;

use crate::domain::path_identity::{NativePathIdentity, NativePathPlatform, PathIdentityLocation};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

/// One entry holds references, status and a first history page.
pub const VIEW_CACHE_ENTRY_CAPACITY: usize = 16 * 1024 * 1024;
/// Entries beyond this count are removed, oldest first.
pub const VIEW_CACHE_ENTRY_LIMIT: usize = 32;
const EXTENSION: &str = "view";

pub fn view_cache_default_directory() -> Option<String> {
    let settings = crate::storage::settings_default_path();
    settings
        .path
        .and_then(|path| PathBuf::from(path).parent().map(Path::to_path_buf))
        .map(|directory| directory.join("cache").join("views"))
        .and_then(|path| path.into_os_string().into_string().ok())
}

pub fn view_cache_read(
    directory: String,
    identity: NativePathIdentity,
) -> NativeViewCacheReadResult {
    match read_entry(Path::new(&directory), &identity) {
        Ok(bytes) => NativeViewCacheReadResult {
            bytes,
            failure: None,
        },
        Err(kind) => NativeViewCacheReadResult {
            bytes: None,
            failure: Some(NativeViewCacheFailure { kind }),
        },
    }
}

pub fn view_cache_write(
    directory: String,
    identity: NativePathIdentity,
    bytes: Vec<u8>,
) -> NativeViewCacheCommandResult {
    command(write_entry(Path::new(&directory), &identity, &bytes))
}

pub fn view_cache_remove(
    directory: String,
    identity: NativePathIdentity,
) -> NativeViewCacheCommandResult {
    command(remove_entry(Path::new(&directory), &identity))
}

fn command(result: Result<(), NativeViewCacheFailureKind>) -> NativeViewCacheCommandResult {
    match result {
        Ok(()) => NativeViewCacheCommandResult {
            accepted: true,
            failure: None,
        },
        Err(kind) => NativeViewCacheCommandResult {
            accepted: false,
            failure: Some(NativeViewCacheFailure { kind }),
        },
    }
}

/// The cache keeps local repositories only. A remote identity is rejected
/// before any file is touched: its units could equal a local path's, and R1
/// keeps no fetched remote content on disk.
fn usable(
    directory: &Path,
    identity: &NativePathIdentity,
) -> Result<(), NativeViewCacheFailureKind> {
    if identity.is_remote() {
        return Err(NativeViewCacheFailureKind::Unavailable);
    }
    if directory.as_os_str().is_empty() || !directory.is_absolute() {
        return Err(NativeViewCacheFailureKind::Unavailable);
    }
    Ok(())
}

/// The file name reveals nothing about the repository path.
fn entry_name(identity: &NativePathIdentity) -> String {
    let mut hasher = Sha256::new();
    hasher.update(match identity.platform {
        NativePathPlatform::Unix => b"unix\0".as_slice(),
        NativePathPlatform::Windows => b"windows\0".as_slice(),
    });
    for unit in &identity.units {
        hasher.update(unit.to_le_bytes());
    }
    let digest = hasher.finalize();
    let mut name = String::with_capacity(digest.len() * 2 + EXTENSION.len() + 1);
    for byte in digest {
        name.push_str(&format!("{byte:02x}"));
    }
    name.push('.');
    name.push_str(EXTENSION);
    name
}

fn read_entry(
    directory: &Path,
    identity: &NativePathIdentity,
) -> Result<Option<Vec<u8>>, NativeViewCacheFailureKind> {
    usable(directory, identity)?;
    let path = directory.join(entry_name(identity));
    let metadata = match fs::symlink_metadata(&path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err(NativeViewCacheFailureKind::Io),
    };
    if !metadata.is_file() {
        return Err(NativeViewCacheFailureKind::Io);
    }
    if metadata.len() > VIEW_CACHE_ENTRY_CAPACITY as u64 {
        return Err(NativeViewCacheFailureKind::TooLarge);
    }
    let bytes = fs::read(&path).map_err(|_| NativeViewCacheFailureKind::Io)?;
    if bytes.len() > VIEW_CACHE_ENTRY_CAPACITY {
        return Err(NativeViewCacheFailureKind::TooLarge);
    }
    Ok(Some(bytes))
}

fn write_entry(
    directory: &Path,
    identity: &NativePathIdentity,
    bytes: &[u8],
) -> Result<(), NativeViewCacheFailureKind> {
    usable(directory, identity)?;
    if bytes.len() > VIEW_CACHE_ENTRY_CAPACITY {
        return Err(NativeViewCacheFailureKind::TooLarge);
    }
    crate::private_store::PrivateDir::application(directory)
        .and_then(|store| store.replace(&entry_name(identity), bytes))
        .map_err(|_| NativeViewCacheFailureKind::Io)?;
    prune(directory);
    Ok(())
}

fn remove_entry(
    directory: &Path,
    identity: &NativePathIdentity,
) -> Result<(), NativeViewCacheFailureKind> {
    usable(directory, identity)?;
    match fs::remove_file(directory.join(entry_name(identity))) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err(NativeViewCacheFailureKind::Io),
    }
}

/// Keeps the newest entries and removes abandoned temporary files.
fn prune(directory: &Path) {
    let Ok(listing) = fs::read_dir(directory) else {
        return;
    };
    let mut entries = Vec::new();
    for entry in listing.flatten() {
        let path = entry.path();
        let Ok(metadata) = fs::symlink_metadata(&path) else {
            continue;
        };
        if !metadata.is_file() {
            continue;
        }
        let modified = metadata
            .modified()
            .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.ends_with(".tmp") {
            let stale = modified
                .elapsed()
                .is_ok_and(|age| age > std::time::Duration::from_secs(600));
            if stale {
                let _ = fs::remove_file(&path);
            }
        } else if path.extension().is_some_and(|value| value == EXTENSION) {
            entries.push((modified, path));
        }
    }
    if entries.len() <= VIEW_CACHE_ENTRY_LIMIT {
        return;
    }
    entries.sort_by_key(|entry| std::cmp::Reverse(entry.0));
    for (_, path) in entries.into_iter().skip(VIEW_CACHE_ENTRY_LIMIT) {
        let _ = fs::remove_file(path);
    }
}

crate::family_failures!(NativeViewCacheFailureKind, "viewCache", {
    Unavailable => Unavailable,
    Io => Read,
    TooLarge => TooLarge,
});

#[cfg(test)]
mod tests {
    use super::*;

    fn identity(path: &str) -> NativePathIdentity {
        NativePathIdentity {
            platform: NativePathPlatform::Unix,
            units: path.bytes().map(u16::from).collect(),
            remote: None,
        }
    }

    #[test]
    fn remote_path_never_becomes_local_cache_entry() {
        let directory = scratch("remote");
        let text = directory.to_str().unwrap().to_owned();
        let local = identity("/work/shared");
        let remote = NativePathIdentity {
            remote: Some(crate::domain::path_identity::NativeRemoteAuthority {
                profile_id: "123e4567-e89b-42d3-a456-426614174000".into(),
                store_id: "0123456789abcdef0123456789abcdef".into(),
                account_uid: "1000".into(),
            }),
            ..local.clone()
        };
        let unavailable = Some(NativeViewCacheFailure {
            kind: NativeViewCacheFailureKind::Unavailable,
        });

        // Nothing is created for a remote identity.
        let refused = view_cache_write(text.clone(), remote.clone(), vec![7]);
        assert!(!refused.accepted);
        assert_eq!(refused.failure, unavailable);
        assert!(!directory.exists());

        // A local entry with the same units is neither read nor removed.
        assert!(view_cache_write(text.clone(), local.clone(), vec![1, 2]).accepted);
        let read = view_cache_read(text.clone(), remote.clone());
        assert_eq!(read.bytes, None);
        assert_eq!(read.failure, unavailable);
        let removed = view_cache_remove(text.clone(), remote);
        assert!(!removed.accepted);
        assert_eq!(removed.failure, unavailable);
        assert_eq!(view_cache_read(text, local).bytes, Some(vec![1, 2]));
        fs::remove_dir_all(directory.parent().unwrap()).unwrap();
    }

    fn scratch(name: &str) -> PathBuf {
        let mut entropy = [0_u8; 8];
        getrandom::fill(&mut entropy).unwrap();
        let suffix = entropy
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let root = std::env::temp_dir().join(format!("gitlama-view-cache-{name}-{suffix}"));
        fs::create_dir_all(&root).unwrap();
        root.canonicalize().unwrap().join("views")
    }

    #[test]
    fn entries_round_trip_privately_and_stay_separate() {
        let directory = scratch("round-trip");
        let text = directory.to_str().unwrap().to_owned();
        let first = identity("/work/first");
        let second = identity("/work/second");
        assert_eq!(
            view_cache_read(text.clone(), first.clone()),
            NativeViewCacheReadResult {
                bytes: None,
                failure: None
            }
        );
        assert!(view_cache_write(text.clone(), first.clone(), vec![1, 2, 3]).accepted);
        assert!(view_cache_write(text.clone(), second.clone(), vec![9]).accepted);
        assert!(view_cache_write(text.clone(), first.clone(), vec![4, 5]).accepted);
        assert_eq!(
            view_cache_read(text.clone(), first.clone()).bytes,
            Some(vec![4, 5])
        );
        assert_eq!(
            view_cache_read(text.clone(), second.clone()).bytes,
            Some(vec![9])
        );
        let names = fs::read_dir(&directory)
            .unwrap()
            .map(|entry| entry.unwrap().file_name().into_string().unwrap())
            .collect::<Vec<_>>();
        assert_eq!(names.len(), 2);
        assert!(names
            .iter()
            .all(|name| name.ends_with(".view") && !name.contains("first")));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = |path: &Path| fs::metadata(path).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode(&directory), 0o700);
            for name in &names {
                assert_eq!(mode(&directory.join(name)), 0o600);
            }
        }
        assert!(view_cache_remove(text.clone(), first.clone()).accepted);
        assert!(view_cache_remove(text.clone(), first.clone()).accepted);
        assert_eq!(view_cache_read(text, first).bytes, None);
        fs::remove_dir_all(directory.parent().unwrap()).unwrap();
    }

    #[test]
    fn oversized_and_unusable_requests_fail_typed() {
        let directory = scratch("bounds");
        let text = directory.to_str().unwrap().to_owned();
        let entry = identity("/work/large");
        let result = view_cache_write(
            text.clone(),
            entry.clone(),
            vec![0; VIEW_CACHE_ENTRY_CAPACITY + 1],
        );
        assert_eq!(
            result.failure.map(|failure| failure.kind),
            Some(NativeViewCacheFailureKind::TooLarge)
        );
        assert_eq!(view_cache_read(text, entry.clone()).bytes, None);
        for unusable in ["", "relative/views"] {
            assert_eq!(
                view_cache_read(unusable.into(), entry.clone())
                    .failure
                    .map(|failure| failure.kind),
                Some(NativeViewCacheFailureKind::Unavailable)
            );
            assert!(!view_cache_write(unusable.into(), entry.clone(), vec![1]).accepted);
        }
        fs::remove_dir_all(directory.parent().unwrap()).unwrap();
    }

    #[test]
    fn the_oldest_entries_are_pruned() {
        let directory = scratch("prune");
        let text = directory.to_str().unwrap().to_owned();
        for index in 0..VIEW_CACHE_ENTRY_LIMIT + 3 {
            let entry = identity(&format!("/work/{index}"));
            assert!(view_cache_write(text.clone(), entry.clone(), vec![1]).accepted);
            let path = directory.join(entry_name(&entry));
            let time = std::time::SystemTime::UNIX_EPOCH
                + std::time::Duration::from_secs(1_000_000 + index as u64);
            fs::File::options()
                .write(true)
                .open(path)
                .unwrap()
                .set_modified(time)
                .unwrap();
        }
        let newest = identity(&format!("/work/{}", VIEW_CACHE_ENTRY_LIMIT + 3));
        assert!(view_cache_write(text.clone(), newest.clone(), vec![7]).accepted);
        let count = fs::read_dir(&directory).unwrap().count();
        assert_eq!(count, VIEW_CACHE_ENTRY_LIMIT);
        assert_eq!(view_cache_read(text.clone(), newest).bytes, Some(vec![7]));
        assert_eq!(view_cache_read(text, identity("/work/0")).bytes, None);
        fs::remove_dir_all(directory.parent().unwrap()).unwrap();
    }
}
