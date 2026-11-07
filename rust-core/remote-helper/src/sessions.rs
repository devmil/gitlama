//! The repository sessions one connection opened, with their exact workspace bindings.
use crate::server::{lock, Connection};
use gitlama_application::domain::path_identity::{NativePathIdentity, NativePathPlatform};
use gitlama_application::dto::{
    NativeRepositoryOpenResult, NativeRepositoryPhase, NativeRepositorySnapshot,
};
use gitlama_application::wire::generated as g;
use gitlama_application::wire::runtime::{self as w, Map, Value};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// How long an open waits for the repository's discovered identity.
const IDENTITY_WAIT: Duration = Duration::from_secs(10);

struct Entry {
    generation: u64,
    workspace: Option<Workspace>,
}

/// The exact workspace a session is bound to, for write admission and evidence.
#[derive(Clone)]
pub struct Workspace {
    pub binding: String,
    /// SHA-256 of the common Git directory's filesystem and inode: linked worktrees share it.
    pub lock_key: String,
    pub git_dir: std::path::PathBuf,
    /// The worktree root, for evidence that covers the working files.
    pub worktree: std::path::PathBuf,
}

/// Where a file lives, stable across mounts: the filesystem ID and the inode.
struct FileIdentity {
    filesystem: u64,
    inode: u64,
}

impl FileIdentity {
    fn of(path: &Path) -> Option<Self> {
        let inode = std::fs::metadata(path).ok()?.ino();
        let filesystem = rustix::fs::statvfs(path).ok()?.f_fsid;
        Some(Self { filesystem, inode })
    }
}

pub struct Sessions {
    store_id: String,
    entries: Mutex<HashMap<u64, Entry>>,
    /// Opens in progress, counted against the session limit.
    opening: Mutex<usize>,
}

impl Sessions {
    pub fn new(store_id: String) -> Self {
        Self {
            store_id,
            entries: Mutex::new(HashMap::new()),
            opening: Mutex::new(0),
        }
    }

    /// The sessions the event pump drains.
    pub fn live(&self) -> Vec<(u64, u64)> {
        lock(&self.entries)
            .iter()
            .map(|(id, entry)| (*id, entry.generation))
            .collect()
    }

    pub fn is_live(&self, session_id: u64) -> bool {
        lock(&self.entries).contains_key(&session_id)
    }

    /// Accepts a session-scoped call only for a session this connection opened.
    ///
    /// # Errors
    /// `unknownSession`.
    pub fn require(&self, arguments: &Value) -> Result<(), &'static str> {
        let session_id: u64 = arguments
            .get("sessionId")
            .ok_or("invalidRequest")
            .and_then(|value| w::big_d(value).map_err(|_| "invalidRequest"))?;
        if self.is_live(session_id) {
            Ok(())
        } else {
            Err("unknownSession")
        }
    }

    /// Answers `openRepository`.
    ///
    /// # Errors
    /// A protocol error code.
    pub fn open(&self, arguments: &Value) -> Result<Value, &'static str> {
        let object = w::object(
            arguments,
            "openRepository",
            &["path", "generation", "expectedBinding"],
        )
        .map_err(|_| "invalidRequest")?;
        let path = w::bytes_d(object.field("path")).map_err(|_| "invalidRequest")?;
        crate::directory::client_path(&path)?;
        let generation: u64 = w::big_d(object.field("generation")).map_err(|_| "invalidRequest")?;
        let expected = match object.field("expectedBinding") {
            Value::Null => None,
            Value::String(binding) if crate::protocol::is_hex(binding, 64) => Some(binding.clone()),
            _ => return Err("invalidRequest"),
        };
        {
            let entries = lock(&self.entries);
            let mut opening = lock(&self.opening);
            if entries.len() + *opening >= crate::protocol::SESSIONS_PER_CONNECTION {
                return Err("capacity");
            }
            *opening += 1;
        }
        let result = self.open_session(&path, generation, expected.as_deref());
        *lock(&self.opening) -= 1;
        result
    }

    fn open_session(
        &self,
        path: &[u8],
        generation: u64,
        expected: Option<&str>,
    ) -> Result<Value, &'static str> {
        let identity = NativePathIdentity {
            platform: NativePathPlatform::Unix,
            units: path.iter().map(|byte| u16::from(*byte)).collect(),
            remote: None,
        };
        let mut result = gitlama_application::application::session::open_identity(
            identity,
            generation,
            gitlama_application::remote_session_policy::SessionPolicy::HELPER,
        );
        let Some(session) = result.session.as_mut() else {
            return Ok(open_value(None, &result));
        };
        let session_id = session.session_id;
        // The client binds the tab to the discovered workspace, so wait for discovery. Events
        // drained here are summarized by the newest snapshot the reply carries.
        let started = Instant::now();
        while !settled(&session.snapshot) {
            if started.elapsed() > IDENTITY_WAIT {
                let _ = gitlama_application::application::session::repository_session_close(
                    session_id, generation,
                );
                return Err("timedOut");
            }
            let events = gitlama_application::application::session::repository_session_events(
                session_id, generation, 64,
            );
            for event in events.events {
                if let Some(snapshot) = event.snapshot {
                    session.snapshot = snapshot;
                }
            }
            if events.failure.is_some() {
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let workspace = session
            .snapshot
            .identity
            .as_ref()
            .and_then(|identity| self.workspace(identity));
        let binding = workspace
            .as_ref()
            .map(|workspace| workspace.binding.clone());
        if let Some(expected) = expected {
            if binding.as_deref() != Some(expected) {
                let _ = gitlama_application::application::session::repository_session_close(
                    session_id, generation,
                );
                return Err("identityMismatch");
            }
        }
        lock(&self.entries).insert(
            session_id,
            Entry {
                generation,
                workspace,
            },
        );
        Ok(open_value(binding.as_deref(), &result))
    }

    /// SHA-256 over the store and the filesystem identity of the worktree and common Git
    /// directory. A replaced or moved repository gets a different binding; a host restart
    /// does not, so the filesystem is named by its ID rather than its device number, which
    /// btrfs subvolumes, for one, are assigned anew at each mount.
    fn workspace(
        &self,
        identity: &gitlama_application::dto::NativeRepositoryIdentity,
    ) -> Option<Workspace> {
        let path = |native: &NativePathIdentity| -> Option<(Vec<u8>, FileIdentity)> {
            let bytes: Vec<u8> = native
                .units
                .iter()
                .map(|unit| u8::try_from(*unit).ok())
                .collect::<Option<_>>()?;
            let identity = FileIdentity::of(Path::new(std::ffi::OsStr::from_bytes(&bytes)))?;
            Some((bytes, identity))
        };
        let root = path(&identity.worktree_root)?;
        let common = path(&identity.common_git_dir)?;
        let git_dir = path(&identity.git_dir)?;
        let mut digest = Sha256::new();
        digest.update(b"gitlama-remote-binding-v1\0");
        digest.update(self.store_id.as_bytes());
        for (bytes, identity) in [&root, &common] {
            digest.update(identity.filesystem.to_be_bytes());
            digest.update(identity.inode.to_be_bytes());
            digest.update(u32::try_from(bytes.len()).ok()?.to_be_bytes());
            digest.update(bytes);
        }
        let mut lock = Sha256::new();
        lock.update(b"gitlama-remote-common-dir-v1\0");
        lock.update(common.1.filesystem.to_be_bytes());
        lock.update(common.1.inode.to_be_bytes());
        Some(Workspace {
            binding: crate::protocol::hex(&digest.finalize()),
            lock_key: crate::protocol::hex(&lock.finalize()),
            git_dir: std::path::PathBuf::from(std::ffi::OsStr::from_bytes(&git_dir.0)),
            worktree: std::path::PathBuf::from(std::ffi::OsStr::from_bytes(&root.0)),
        })
    }

    /// Answers `closeRepository`.
    ///
    /// # Errors
    /// `invalidRequest`.
    pub fn close(&self, connection: &Connection, arguments: &Value) -> Result<Value, &'static str> {
        let object = w::object(arguments, "closeRepository", &["sessionId", "generation"])
            .map_err(|_| "invalidRequest")?;
        let session_id: u64 = w::big_d(object.field("sessionId")).map_err(|_| "invalidRequest")?;
        let generation: u64 = w::big_d(object.field("generation")).map_err(|_| "invalidRequest")?;
        let removed = {
            let mut entries = lock(&self.entries);
            match entries.get(&session_id) {
                Some(entry) if entry.generation == generation => entries.remove(&session_id),
                _ => None,
            }
        };
        connection.forget_session(session_id);
        let result = if removed.is_some() {
            gitlama_application::application::session::repository_session_close(
                session_id, generation,
            )
        } else {
            gitlama_application::dto::NativeRepositoryCommandResult {
                accepted: true,
                failure: None,
            }
        };
        Ok(g::enc_native_repository_command_result(&result))
    }

    /// Closes every session at teardown. Admission is already closed.
    pub fn close_all(&self, connection: &Connection) {
        let entries: Vec<(u64, u64)> = lock(&self.entries)
            .drain()
            .map(|(id, entry)| (id, entry.generation))
            .collect();
        for (session_id, generation) in entries {
            connection.forget_session(session_id);
            let _ = gitlama_application::application::session::repository_session_close(
                session_id, generation,
            );
        }
    }

    /// The generation and workspace of a live session, for write admission.
    pub fn workspace_of(&self, session_id: u64) -> Option<(u64, Workspace)> {
        lock(&self.entries).get(&session_id).and_then(|entry| {
            entry
                .workspace
                .clone()
                .map(|workspace| (entry.generation, workspace))
        })
    }
}

fn settled(snapshot: &NativeRepositorySnapshot) -> bool {
    snapshot.identity.is_some()
        || snapshot.failure.is_some()
        || matches!(
            snapshot.phase,
            NativeRepositoryPhase::Failed | NativeRepositoryPhase::Closed
        )
}

fn open_value(binding: Option<&str>, result: &NativeRepositoryOpenResult) -> Value {
    let mut map = Map::new();
    map.insert("binding".into(), binding.map_or(Value::Null, Value::from));
    map.insert("open".into(), g::enc_native_repository_open_result(result));
    Value::Object(map)
}
