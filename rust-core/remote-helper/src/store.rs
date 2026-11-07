//! The account's private helper store under `$HOME/.local/state/gitlama/remote-helper`.
//!
//! Every component below the home directory is opened without following symbolic links and the
//! store's own directories are owner-only. The random store identity is created once, under an
//! exclusive lock, with file and directory synchronization. An unreadable or corrupt identity is
//! reported as unavailable; it is never replaced, because replacing it would silently move every
//! client's authority to a new store.
use rustix::fd::OwnedFd;
use rustix::fs::{self as fs, FlockOperation, Mode, OFlags};
use rustix::io::Errno;
use std::ffi::CStr;
use std::io::{Read, Write};
use std::path::Path;

/// Makes a directory's entries durable. On macOS `fsync` does not flush the drive's write
/// cache; a full flush does, as `File::sync_all` already does there for files.
pub fn sync_directory(directory: &impl rustix::fd::AsFd) -> rustix::io::Result<()> {
    #[cfg(target_vendor = "apple")]
    {
        rustix::fs::fcntl_fullfsync(directory)
    }
    #[cfg(not(target_vendor = "apple"))]
    {
        rustix::fs::fsync(directory)
    }
}

const COMPONENTS: [&CStr; 4] = [c".local", c"state", c"gitlama", c"remote-helper"];
/// Components the helper owns outright and keeps owner-only.
const PRIVATE_FROM: usize = 2;
const IDENTITY: &CStr = c"identity.json";
const LOCK: &CStr = c"store.lock";
const IDENTITY_LIMIT: u64 = 4096;

/// Why the store cannot back durable identity.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StoreError {
    /// `HOME` is unset or relative.
    Home,
    /// A component is a symbolic link, not a directory, foreign-owned or not private.
    Unsafe,
    /// Reading, creating or synchronizing failed.
    Io,
    /// The identity file exists but cannot be trusted.
    Corrupt,
    /// Randomness was unavailable.
    Random,
}

pub struct Store {
    directory: OwnedFd,
    id: String,
}

impl Store {
    /// Opens or creates the store below `home`.
    ///
    /// # Errors
    /// See [`StoreError`].
    pub fn open(home: &Path) -> Result<Self, StoreError> {
        if !home.is_absolute() {
            return Err(StoreError::Home);
        }
        // The home directory itself is the account's trusted root and may be a link.
        let mut directory = fs::open(
            home,
            OFlags::DIRECTORY | OFlags::RDONLY | OFlags::CLOEXEC,
            Mode::empty(),
        )
        .map_err(|_| StoreError::Home)?;
        let uid = rustix::process::geteuid();
        for (index, component) in COMPONENTS.iter().enumerate() {
            directory = open_component(&directory, component)?;
            let stat = fs::fstat(&directory).map_err(|_| StoreError::Io)?;
            if stat.st_uid != uid.as_raw() {
                return Err(StoreError::Unsafe);
            }
            if index >= PRIVATE_FROM && stat.st_mode & 0o077 != 0 {
                fs::fchmod(&directory, Mode::from_raw_mode(0o700))
                    .map_err(|_| StoreError::Unsafe)?;
            }
        }
        let lock = create_at(
            &directory,
            LOCK,
            OFlags::RDWR | OFlags::NOFOLLOW | OFlags::CLOEXEC,
        )
        .map_err(|_| StoreError::Io)?;
        fs::flock(&lock, FlockOperation::LockExclusive).map_err(|_| StoreError::Io)?;
        let id = match read_identity(&directory) {
            Ok(id) => id,
            Err(Some(error)) => return Err(error),
            Err(None) => create_identity(&directory)?,
        };
        drop(lock);
        Ok(Self { directory, id })
    }

    #[must_use]
    pub fn id(&self) -> &str {
        &self.id
    }

    /// The store's directory capability, for receipts and locks.
    #[must_use]
    pub fn directory(&self) -> &OwnedFd {
        &self.directory
    }
}

/// Opens or creates an owner-only file in a held directory.
///
/// APFS can report `ENOENT` for a create in a directory that exists while other threads create
/// entries in it. The directory is held open, so that answer is transient and the open repeats.
pub(crate) fn create_at(parent: &OwnedFd, name: &CStr, flags: OFlags) -> Result<OwnedFd, Errno> {
    let mut attempts = 0;
    loop {
        match fs::openat(
            parent,
            name,
            flags | OFlags::CREATE,
            Mode::from_raw_mode(0o600),
        ) {
            Err(Errno::NOENT) if attempts < 100 => {
                attempts += 1;
                std::thread::sleep(std::time::Duration::from_millis(1));
            }
            result => return result,
        }
    }
}

fn open_component(parent: &OwnedFd, name: &CStr) -> Result<OwnedFd, StoreError> {
    let flags = OFlags::DIRECTORY | OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::CLOEXEC;
    match fs::openat(parent, name, flags, Mode::empty()) {
        Ok(directory) => Ok(directory),
        Err(Errno::NOENT) => {
            match fs::mkdirat(parent, name, Mode::from_raw_mode(0o700)) {
                Ok(()) | Err(Errno::EXIST) => {}
                Err(_) => return Err(StoreError::Io),
            }
            sync_directory(parent).map_err(|_| StoreError::Io)?;
            fs::openat(parent, name, flags, Mode::empty()).map_err(|_| StoreError::Unsafe)
        }
        // ELOOP/ENOTDIR: a link or a non-directory where the store must be.
        Err(_) => Err(StoreError::Unsafe),
    }
}

/// `Err(None)` means the identity does not exist yet.
fn read_identity(directory: &OwnedFd) -> Result<String, Option<StoreError>> {
    let file = match fs::openat(
        directory,
        IDENTITY,
        OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
        Mode::empty(),
    ) {
        Ok(file) => file,
        Err(Errno::NOENT) => return Err(None),
        Err(_) => return Err(Some(StoreError::Corrupt)),
    };
    let stat = fs::fstat(&file).map_err(|_| Some(StoreError::Io))?;
    if stat.st_mode & 0o170_000 != 0o100_000 {
        return Err(Some(StoreError::Corrupt));
    }
    let mut bytes = Vec::new();
    std::fs::File::from(file)
        .take(IDENTITY_LIMIT + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| Some(StoreError::Io))?;
    if bytes.len() as u64 > IDENTITY_LIMIT {
        return Err(Some(StoreError::Corrupt));
    }
    let value = gitlama_application::wire::runtime::parse(
        &bytes,
        gitlama_application::wire::runtime::ParseLimits::FRAME,
    )
    .map_err(|_| Some(StoreError::Corrupt))?;
    let object =
        gitlama_application::wire::runtime::object(&value, "identity", &["schema", "storeId"])
            .map_err(|_| Some(StoreError::Corrupt))?;
    let id = object.field("storeId").as_str().unwrap_or_default();
    if object.field("schema").as_u64() != Some(1) || !crate::protocol::is_hex(id, 32) {
        return Err(Some(StoreError::Corrupt));
    }
    Ok(id.to_owned())
}

fn create_identity(directory: &OwnedFd) -> Result<String, StoreError> {
    let id = crate::protocol::random_id().map_err(|_| StoreError::Random)?;
    let suffix = crate::protocol::random_id().map_err(|_| StoreError::Random)?;
    let temporary = std::ffi::CString::new(format!("identity.json.{suffix}.tmp"))
        .map_err(|_| StoreError::Io)?;
    let file = create_at(
        directory,
        &temporary,
        OFlags::WRONLY | OFlags::EXCL | OFlags::NOFOLLOW | OFlags::CLOEXEC,
    )
    .map_err(|_| StoreError::Io)?;
    let mut file = std::fs::File::from(file);
    let written = file
        .write_all(format!("{{\"schema\":1,\"storeId\":\"{id}\"}}\n").as_bytes())
        .and_then(|()| file.sync_all());
    drop(file);
    let installed = written.is_ok()
        && fs::renameat(directory, &temporary, directory, IDENTITY).is_ok()
        && sync_directory(directory).is_ok();
    if !installed {
        let _ = fs::unlinkat(directory, &temporary, fs::AtFlags::empty());
        return Err(StoreError::Io);
    }
    Ok(id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::{symlink, PermissionsExt};
    use std::path::PathBuf;

    struct Root(PathBuf);

    impl Root {
        fn new(name: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "gitlama-helper-store-{name}-{}-{}",
                std::process::id(),
                crate::protocol::random_id().unwrap()
            ));
            std::fs::create_dir_all(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for Root {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn identity_is_created_once_private_and_stable() {
        let root = Root::new("stable");
        let first = Store::open(&root.0).unwrap();
        let second = Store::open(&root.0).unwrap();
        assert_eq!(first.id(), second.id());
        let store = root.0.join(".local/state/gitlama/remote-helper");
        let mode = std::fs::metadata(&store).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o700);
        let identity = std::fs::metadata(store.join("identity.json")).unwrap();
        assert_eq!(identity.permissions().mode() & 0o777, 0o600);
    }

    #[test]
    fn concurrent_starts_share_one_identity() {
        let root = Root::new("concurrent");
        let path = root.0.clone();
        let ids: Vec<String> = (0..8)
            .map(|_| {
                let path = path.clone();
                std::thread::spawn(move || Store::open(&path).unwrap().id().to_owned())
            })
            .collect::<Vec<_>>()
            .into_iter()
            .map(|thread| thread.join().unwrap())
            .collect();
        assert!(ids.windows(2).all(|pair| pair[0] == pair[1]));
    }

    #[test]
    fn every_component_link_is_refused_without_touching_its_target() {
        for (index, _) in COMPONENTS.iter().enumerate() {
            let root = Root::new("link");
            let outside = root.0.join("outside");
            std::fs::create_dir_all(&outside).unwrap();
            let mut path = root.0.clone();
            for component in &COMPONENTS[..index] {
                path.push(component.to_str().unwrap());
                std::fs::create_dir_all(&path).unwrap();
            }
            symlink(&outside, path.join(COMPONENTS[index].to_str().unwrap())).unwrap();
            assert_eq!(Store::open(&root.0).err(), Some(StoreError::Unsafe));
            assert_eq!(std::fs::read_dir(&outside).unwrap().count(), 0);
        }
    }

    #[test]
    fn unreadable_or_corrupt_identity_is_not_replaced() {
        let root = Root::new("corrupt");
        Store::open(&root.0).unwrap();
        let identity = root
            .0
            .join(".local/state/gitlama/remote-helper/identity.json");
        std::fs::write(&identity, b"{\"schema\":1,\"storeId\":\"nope\"}").unwrap();
        assert_eq!(Store::open(&root.0).err(), Some(StoreError::Corrupt));
        assert_eq!(
            std::fs::read(&identity).unwrap(),
            b"{\"schema\":1,\"storeId\":\"nope\"}"
        );
        std::fs::remove_file(&identity).unwrap();
        symlink("/dev/null", &identity).unwrap();
        assert_eq!(Store::open(&root.0).err(), Some(StoreError::Corrupt));
    }
}
