//! Owner-only application files.
//!
//! Every private file GitLama writes goes through a [`PrivateDir`]: directories are created
//! owner-only (Unix mode `0700`, a Windows DACL that grants only the current user), files are
//! created exclusively and owner-only before any byte is written (`0600`, or `0700` for helper
//! scripts), and replacements are written to a temporary sibling and renamed into place.
//! Repository stores live below `<common Git directory>/gitlama` and are opened through a
//! capability that never follows a symbolic link, so a link planted in the Git directory cannot
//! redirect a write.
//!
//! Values carry no paths into errors: callers map [`std::io::Error`] to their own failure codes.

use cap_std::fs::{Dir, DirBuilder, OpenOptions};
use std::io::{self, Read as _, Write as _};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

/// The directory below the common Git directory that holds GitLama's repository state.
pub(crate) const REPOSITORY_ROOT: &str = "gitlama";

static TEMPORARY_SEQUENCE: AtomicU64 = AtomicU64::new(0);

/// An owner-only directory and its ambient path. The path is for handing files to other
/// programs (Git, editors); every read and write here goes through the directory handle.
#[derive(Debug)]
/// Holds an open handle to its directory. On Windows a directory with an open handle cannot be
/// deleted, so drop the `PrivateDir` (and its children) before removing its path.
pub(crate) struct PrivateDir {
    dir: Dir,
    path: PathBuf,
}

fn unsafe_entry() -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidInput,
        "a private store entry is a link or has the wrong type",
    )
}

fn valid_name(name: &str) -> io::Result<()> {
    if name.is_empty()
        || name == "."
        || name == ".."
        || name.contains(['/', '\\', '\0'])
        || Path::new(name).components().count() != 1
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "a private store name must be one path component",
        ));
    }
    Ok(())
}

impl PrivateDir {
    /// Opens `<common_git_dir>/gitlama/<components…>`, creating missing directories owner-only.
    /// The common Git directory itself must be a real directory; no component may be a link.
    pub(crate) fn repository(common_git_dir: &Path, components: &[&str]) -> io::Result<Self> {
        let metadata = std::fs::symlink_metadata(common_git_dir)?;
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            return Err(unsafe_entry());
        }
        let common = Self {
            dir: Dir::open_ambient_dir(common_git_dir, cap_std::ambient_authority())?,
            path: common_git_dir.to_path_buf(),
        };
        let mut current = common.child(REPOSITORY_ROOT)?;
        for component in components {
            current = current.child(component)?;
        }
        Ok(current)
    }

    /// Opens an application directory (an absolute path outside any repository), creating it
    /// and its parents. The directory itself is made owner-only; parents keep their permissions.
    pub(crate) fn application(path: &Path) -> io::Result<Self> {
        if !path.is_absolute() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "a private application directory must be absolute",
            ));
        }
        let parent = path.parent().ok_or_else(unsafe_entry)?;
        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or_else(unsafe_entry)?;
        std::fs::create_dir_all(parent)?;
        let parent = Self {
            dir: Dir::open_ambient_dir(parent, cap_std::ambient_authority())?,
            path: parent.to_path_buf(),
        };
        parent.child(name)
    }

    /// A new owner-only directory below the system temporary directory, named
    /// `<prefix>-<process>-<sequence>`. It is created exclusively, so an existing directory of
    /// that name is never reused; the temporary directory itself keeps its permissions.
    pub(crate) fn temporary(prefix: &str) -> io::Result<Self> {
        let parent_path = std::env::temp_dir();
        let parent = Self {
            dir: Dir::open_ambient_dir(&parent_path, cap_std::ambient_authority())?,
            path: parent_path,
        };
        for _ in 0..16 {
            let name = format!(
                "{prefix}-{}-{}",
                std::process::id(),
                TEMPORARY_SEQUENCE.fetch_add(1, Ordering::Relaxed)
            );
            match parent.open_child(&name, true) {
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
                other => return other,
            }
        }
        Err(io::ErrorKind::AlreadyExists.into())
    }

    /// Opens the child directory `name`, creating it owner-only when missing. An existing child
    /// is made owner-only again on Unix.
    pub(crate) fn child(&self, name: &str) -> io::Result<Self> {
        self.open_child(name, false)
    }

    fn open_child(&self, name: &str, exclusive: bool) -> io::Result<Self> {
        valid_name(name)?;
        let path = self.path.join(name);
        match self.dir.symlink_metadata(name) {
            Ok(_) if exclusive => return Err(io::ErrorKind::AlreadyExists.into()),
            Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => {}
            Ok(_) => return Err(unsafe_entry()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                #[cfg_attr(not(unix), allow(unused_mut))]
                let mut builder = DirBuilder::new();
                #[cfg(unix)]
                {
                    use cap_std::fs::DirBuilderExt as _;
                    builder.mode(0o700);
                }
                self.dir.create_dir_with(name, &builder)?;
                #[cfg(windows)]
                crate::windows_security::owner_only(&path)?;
            }
            Err(error) => return Err(error),
        }
        let parent = self.dir.try_clone()?.into_std_file();
        let child = Dir::from_std_file(cap_primitives::fs::open_dir_nofollow(
            &parent,
            Path::new(name),
        )?);
        #[cfg(unix)]
        {
            use cap_std::fs::PermissionsExt as _;
            self.dir
                .set_permissions(name, cap_std::fs::Permissions::from_mode(0o700))?;
        }
        Ok(Self { dir: child, path })
    }

    /// The directory's ambient path, for handing its files to other programs.
    pub(crate) fn path(&self) -> &Path {
        &self.path
    }

    /// The ambient path of the entry `name` in this directory.
    pub(crate) fn entry_path(&self, name: &str) -> PathBuf {
        self.path.join(name)
    }

    fn create(&self, name: &str, executable: bool) -> io::Result<cap_std::fs::File> {
        valid_name(name)?;
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use cap_std::fs::OpenOptionsExt as _;
            options.mode(if executable { 0o700 } else { 0o600 });
        }
        #[cfg(not(unix))]
        let _ = executable;
        let file = self.dir.open_with(name, &options)?;
        #[cfg(windows)]
        crate::windows_security::owner_only(&self.path.join(name))?;
        Ok(file)
    }

    fn write_created(&self, name: &str, bytes: &[u8], executable: bool) -> io::Result<()> {
        let mut file = self.create(name, executable)?;
        let written = file.write_all(bytes).and_then(|()| file.sync_all());
        drop(file);
        if written.is_err() {
            let _ = self.dir.remove_file(name);
        }
        written
    }

    /// Writes a new owner-only file; fails when `name` exists.
    pub(crate) fn write_new(&self, name: &str, bytes: &[u8]) -> io::Result<()> {
        self.write_created(name, bytes, false)
    }

    /// Writes a new owner-only helper script that only its owner may execute (Unix `0700`).
    #[cfg_attr(not(unix), allow(dead_code))]
    pub(crate) fn write_new_executable(&self, name: &str, bytes: &[u8]) -> io::Result<()> {
        self.write_created(name, bytes, true)
    }

    /// Replaces `name` atomically with an owner-only file holding `bytes`.
    pub(crate) fn replace(&self, name: &str, bytes: &[u8]) -> io::Result<()> {
        self.replace_with(name, bytes, false)
    }

    /// [`Self::replace`] for a helper script that only its owner may execute.
    #[cfg_attr(not(unix), allow(dead_code))]
    pub(crate) fn replace_executable(&self, name: &str, bytes: &[u8]) -> io::Result<()> {
        self.replace_with(name, bytes, true)
    }

    fn replace_with(&self, name: &str, bytes: &[u8], executable: bool) -> io::Result<()> {
        valid_name(name)?;
        let temporary = format!(
            ".{name}.{}-{}.tmp",
            std::process::id(),
            TEMPORARY_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        );
        self.write_created(&temporary, bytes, executable)?;
        let result = match self.dir.symlink_metadata(name) {
            Ok(metadata) if !metadata.is_file() || metadata.file_type().is_symlink() => {
                Err(unsafe_entry())
            }
            Ok(_) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
        .and_then(|()| self.dir.rename(&temporary, &self.dir, name))
        .and_then(|()| self.sync());
        if result.is_err() {
            let _ = self.dir.remove_file(&temporary);
        }
        result
    }

    /// Makes completed renames durable (Unix); a no-op elsewhere.
    fn sync(&self) -> io::Result<()> {
        #[cfg(unix)]
        {
            // The confined handle may be a path-only descriptor that cannot be synced.
            std::fs::File::open(&self.path)?.sync_all()
        }
        #[cfg(not(unix))]
        {
            Ok(())
        }
    }

    /// Reads the regular file `name` up to `limit` bytes; `Ok(None)` when it is missing.
    pub(crate) fn read(&self, name: &str, limit: u64) -> io::Result<Option<Vec<u8>>> {
        valid_name(name)?;
        let metadata = match self.dir.symlink_metadata(name) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error),
        };
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(unsafe_entry());
        }
        if metadata.len() > limit {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "a private store file exceeds its bound",
            ));
        }
        let mut bytes = Vec::new();
        self.dir
            .open(name)?
            .take(limit + 1)
            .read_to_end(&mut bytes)?;
        if bytes.len() as u64 > limit {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "a private store file exceeds its bound",
            ));
        }
        Ok(Some(bytes))
    }

    /// Removes the entry `name` (a file, or a directory with its contents); missing is success.
    pub(crate) fn remove(&self, name: &str) -> io::Result<()> {
        valid_name(name)?;
        let result = match self.dir.symlink_metadata(name) {
            Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => {
                self.dir.remove_dir_all(name)
            }
            Ok(_) => self.dir.remove_file(name),
            Err(error) => Err(error),
        };
        match result {
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            other => other,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temporary_root(label: &str) -> PathBuf {
        let mut entropy = [0_u8; 8];
        getrandom::fill(&mut entropy).unwrap();
        let suffix = entropy
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let root = std::env::temp_dir().join(format!("gitlama-private-{label}-{suffix}"));
        std::fs::create_dir(&root).unwrap();
        root
    }

    #[test]
    fn repository_stores_are_owner_only_and_replace_atomically() {
        let common = temporary_root("store");
        let store = PrivateDir::repository(&common, &["snapshots", "v1"]).unwrap();
        assert_eq!(store.path(), common.join("gitlama/snapshots/v1"));
        store.replace("index.json", b"one").unwrap();
        store.replace("index.json", b"two").unwrap();
        assert_eq!(store.read("index.json", 16).unwrap().unwrap(), b"two");
        assert!(store.read("index.json", 2).is_err());
        assert_eq!(store.read("missing", 16).unwrap(), None);
        assert!(store.write_new("index.json", b"x").is_err());
        store
            .write_new_executable("helper", b"#!/bin/sh\n")
            .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            let mode = |path: &Path| std::fs::metadata(path).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode(&common.join("gitlama")), 0o700);
            assert_eq!(mode(store.path()), 0o700);
            assert_eq!(mode(&store.entry_path("index.json")), 0o600);
            assert_eq!(mode(&store.entry_path("helper")), 0o700);
        }
        // No temporary file survives a replacement.
        assert_eq!(std::fs::read_dir(store.path()).unwrap().count(), 2);
        let child = store.child("active").unwrap();
        child.write_new("id", b"1").unwrap();
        drop(child);
        store.remove("active").unwrap();
        store.remove("active").unwrap();
        assert!(!store.entry_path("active").exists());
        assert!(store.child("../escape").is_err());
        assert!(store.write_new("a/b", b"x").is_err());
        drop(store);
        std::fs::remove_dir_all(common).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn links_in_the_store_are_refused() {
        let common = temporary_root("links");
        let elsewhere = temporary_root("elsewhere");
        std::os::unix::fs::symlink(&elsewhere, common.join("gitlama")).unwrap();
        assert!(PrivateDir::repository(&common, &[]).is_err());
        std::fs::remove_file(common.join("gitlama")).unwrap();
        let store = PrivateDir::repository(&common, &[]).unwrap();
        std::os::unix::fs::symlink(elsewhere.join("target"), store.entry_path("file")).unwrap();
        assert!(store.replace("file", b"x").is_err());
        assert!(store.read("file", 16).is_err());
        assert!(!elsewhere.join("target").exists());
        std::fs::remove_dir_all(common).unwrap();
        std::fs::remove_dir_all(elsewhere).unwrap();
    }

    #[test]
    fn temporary_directories_are_new_and_owner_only() {
        let first = PrivateDir::temporary("gitlama-private-test").unwrap();
        let second = PrivateDir::temporary("gitlama-private-test").unwrap();
        assert_ne!(first.path(), second.path());
        assert_eq!(first.path().parent(), Some(std::env::temp_dir().as_path()));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            let mode = std::fs::metadata(first.path())
                .unwrap()
                .permissions()
                .mode()
                & 0o777;
            assert_eq!(mode, 0o700);
        }
        let paths = [first.path().to_path_buf(), second.path().to_path_buf()];
        drop((first, second));
        for path in paths {
            std::fs::remove_dir_all(path).unwrap();
        }
    }

    #[test]
    fn application_directories_are_created_with_their_parents() {
        let root = temporary_root("application");
        let store = PrivateDir::application(&root.join("a/b")).unwrap();
        store.replace("file", b"x").unwrap();
        assert_eq!(std::fs::read(root.join("a/b/file")).unwrap(), b"x");
        assert!(PrivateDir::application(Path::new("relative")).is_err());
        drop(store);
        std::fs::remove_dir_all(root).unwrap();
    }
}
