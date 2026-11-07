//! Session entry points of commit zip snapshots.
//!
//! A snapshot is built on a background thread into a private temporary file of the computer
//! that holds the repository, and read back in pages of at most one wire frame. The same
//! calls serve a repository on this computer and, through the remote helper, one on another
//! computer: the desktop writes the pages to the file the person chose. Releasing the job,
//! closing the session or replacing it deletes the temporary file.
pub use gitlama_contract::archive::*;

use crate::application::session::{lock_sessions, repository_for_session};
use crate::domain::ids::SessionKey;
use devmil_git::archive::{write_commit_zip, ArchiveError, ArchiveRequest};
use devmil_git::types::ObjectId;
use std::collections::HashMap;
use std::fs;
use std::io::{BufWriter, Read, Seek, SeekFrom, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

/// Bytes one page carries; a page stays within one wire frame.
pub const ARCHIVE_PAGE_BYTES: usize = 1024 * 1024;
/// Snapshots one session builds or keeps at once.
const ARCHIVES_PER_SESSION: usize = 2;
const PREFIX_BYTES: usize = 255;

static NEXT_FILE: AtomicU64 = AtomicU64::new(0);

#[derive(Default)]
pub(crate) struct ArchiveState {
    next_token: u64,
    jobs: HashMap<u64, ArchiveHandle>,
}

struct Shared {
    cancel: AtomicBool,
    status: Mutex<NativeArchiveStatus>,
    path: PathBuf,
}

impl Shared {
    fn status(&self) -> NativeArchiveStatus {
        self.status
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    fn update(&self, change: impl FnOnce(&mut NativeArchiveStatus)) {
        change(
            &mut self
                .status
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        );
    }
}

/// The session's hold on one snapshot. Dropping it stops the build and deletes the file.
struct ArchiveHandle(Arc<Shared>);

impl Drop for ArchiveHandle {
    fn drop(&mut self) {
        self.0.cancel.store(true, Ordering::Relaxed);
        let _ = fs::remove_file(&self.0.path);
    }
}

fn status(
    state: NativeArchiveState,
    failure: Option<NativeArchiveFailureKind>,
) -> NativeArchiveStatus {
    NativeArchiveStatus {
        state,
        files: 0,
        total_files: 0,
        content_bytes: 0,
        archive_bytes: 0,
        missing_submodules: Vec::new(),
        missing_submodule_count: 0,
        unresolved_lfs: Vec::new(),
        unresolved_lfs_count: 0,
        failure: failure.map(|kind| NativeArchiveFailure { kind }),
    }
}

fn start_failure(kind: NativeArchiveFailureKind) -> NativeArchiveStartResult {
    NativeArchiveStartResult {
        token: None,
        failure: Some(NativeArchiveFailure { kind }),
    }
}

fn page_failure(kind: NativeArchiveFailureKind) -> NativeArchivePage {
    NativeArchivePage {
        bytes: Vec::new(),
        failure: Some(NativeArchiveFailure { kind }),
    }
}

fn failure_kind(error: ArchiveError) -> NativeArchiveFailureKind {
    match error {
        ArchiveError::InvalidRequest => NativeArchiveFailureKind::InvalidRequest,
        ArchiveError::MissingCommit => NativeArchiveFailureKind::MissingCommit,
        ArchiveError::TooLarge => NativeArchiveFailureKind::TooLarge,
        ArchiveError::Git => NativeArchiveFailureKind::Git,
        ArchiveError::Io => NativeArchiveFailureKind::Write,
        ArchiveError::Canceled => NativeArchiveFailureKind::Canceled,
    }
}

fn temporary_archive() -> Option<(PathBuf, fs::File)> {
    let path = std::env::temp_dir().join(format!(
        "gitlama-archive-{}-{}.zip",
        std::process::id(),
        NEXT_FILE.fetch_add(1, Ordering::Relaxed)
    ));
    let mut options = fs::OpenOptions::new();
    options.read(true).write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(&path).ok().map(|file| (path, file))
}

/// Starts the zip snapshot of `commit` with every file under the folder `prefix`, submodules
/// at their recorded commits and LFS files with their content.
#[must_use]
pub fn repository_session_archive_start(
    session_id: u64,
    generation: u64,
    commit: String,
    prefix: String,
) -> NativeArchiveStartResult {
    let Ok(commit) = ObjectId::parse(commit) else {
        return start_failure(NativeArchiveFailureKind::InvalidRequest);
    };
    if prefix.len() > PREFIX_BYTES {
        return start_failure(NativeArchiveFailureKind::InvalidRequest);
    }
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return start_failure(NativeArchiveFailureKind::Stale);
    };
    let snapshot = repository.snapshot();
    let Some(discovered) = snapshot.repository.as_ref() else {
        return start_failure(NativeArchiveFailureKind::Git);
    };
    let request = ArchiveRequest {
        git: repository.git_executable().to_owned(),
        repository: discovered.worktree.worktree_root().as_path().to_path_buf(),
        worktree: Some(discovered.worktree.worktree_root().as_path().to_path_buf()),
        commit,
        prefix,
        submodules: true,
        lfs: true,
    };
    let mut sessions = lock_sessions();
    let Ok(session) = sessions.session_mut(SessionKey::new(session_id, generation)) else {
        return start_failure(NativeArchiveFailureKind::Stale);
    };
    let archives = &mut session.archives;
    if archives.jobs.len() >= ARCHIVES_PER_SESSION {
        return start_failure(NativeArchiveFailureKind::Busy);
    }
    let Some((path, file)) = temporary_archive() else {
        return start_failure(NativeArchiveFailureKind::Write);
    };
    let shared = Arc::new(Shared {
        cancel: AtomicBool::new(false),
        status: Mutex::new(status(NativeArchiveState::Running, None)),
        path,
    });
    archives.next_token += 1;
    let token = archives.next_token;
    archives
        .jobs
        .insert(token, ArchiveHandle(Arc::clone(&shared)));
    drop(sessions);
    let worker = Arc::clone(&shared);
    let spawned = std::thread::Builder::new()
        .name("gitlama-archive".to_owned())
        .spawn(move || build(&request, file, &worker));
    if spawned.is_err() {
        shared.update(|status| {
            status.state = NativeArchiveState::Failed;
            status.failure = Some(NativeArchiveFailure {
                kind: NativeArchiveFailureKind::Write,
            });
        });
    }
    NativeArchiveStartResult {
        token: Some(token),
        failure: None,
    }
}

fn build(request: &ArchiveRequest, file: fs::File, shared: &Shared) {
    let result = write_commit_zip(
        request,
        BufWriter::new(file),
        &shared.cancel,
        &mut |progress| {
            shared.update(|status| {
                status.files = progress.files;
                status.total_files = progress.total_files;
                status.content_bytes = progress.bytes;
            });
        },
    )
    .and_then(|(writer, summary)| {
        let mut file = writer.into_inner().map_err(|_| ArchiveError::Io)?;
        file.flush().map_err(|_| ArchiveError::Io)?;
        let bytes = file.seek(SeekFrom::End(0)).map_err(|_| ArchiveError::Io)?;
        Ok((bytes, summary))
    });
    let canceled = shared.cancel.load(Ordering::Relaxed);
    shared.update(|status| match result {
        Ok((bytes, summary)) if !canceled => {
            status.state = NativeArchiveState::Completed;
            status.files = summary.files;
            status.content_bytes = summary.bytes;
            status.archive_bytes = bytes;
            status.missing_submodules = summary.missing_submodules;
            status.missing_submodule_count = summary.missing_submodule_count;
            status.unresolved_lfs = summary.unresolved_lfs;
            status.unresolved_lfs_count = summary.unresolved_lfs_count;
        }
        Ok(_) | Err(ArchiveError::Canceled) => {
            status.state = NativeArchiveState::Canceled;
            status.failure = Some(NativeArchiveFailure {
                kind: NativeArchiveFailureKind::Canceled,
            });
        }
        Err(error) => {
            status.state = NativeArchiveState::Failed;
            status.failure = Some(NativeArchiveFailure {
                kind: failure_kind(error),
            });
        }
    });
    if shared.status().state != NativeArchiveState::Completed
        || shared.cancel.load(Ordering::Relaxed)
    {
        let _ = fs::remove_file(&shared.path);
    }
}

fn job(
    session_id: u64,
    generation: u64,
    token: u64,
) -> Result<Arc<Shared>, NativeArchiveFailureKind> {
    let sessions = lock_sessions();
    let session = sessions
        .session(SessionKey::new(session_id, generation))
        .map_err(|_| NativeArchiveFailureKind::Stale)?;
    session
        .archives
        .jobs
        .get(&token)
        .map(|handle| Arc::clone(&handle.0))
        .ok_or(NativeArchiveFailureKind::InvalidRequest)
}

/// The progress or result of the snapshot `token`.
#[must_use]
pub fn repository_session_archive_status(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeArchiveStatus {
    match job(session_id, generation, token) {
        Ok(shared) => shared.status(),
        Err(kind) => status(NativeArchiveState::Failed, Some(kind)),
    }
}

/// The finished snapshot's bytes from `offset`, at most [`ARCHIVE_PAGE_BYTES`]; empty at the
/// end.
#[must_use]
pub fn repository_session_archive_page(
    session_id: u64,
    generation: u64,
    token: u64,
    offset: u64,
) -> NativeArchivePage {
    let shared = match job(session_id, generation, token) {
        Ok(shared) => shared,
        Err(kind) => return page_failure(kind),
    };
    let status = shared.status();
    if status.state != NativeArchiveState::Completed || offset > status.archive_bytes {
        return page_failure(NativeArchiveFailureKind::InvalidRequest);
    }
    let read = || -> std::io::Result<Vec<u8>> {
        let mut file = fs::File::open(&shared.path)?;
        file.seek(SeekFrom::Start(offset))?;
        let wanted = (status.archive_bytes - offset).min(ARCHIVE_PAGE_BYTES as u64);
        let mut bytes = Vec::with_capacity(usize::try_from(wanted).unwrap_or(0));
        file.take(wanted).read_to_end(&mut bytes)?;
        Ok(bytes)
    };
    match read() {
        Ok(bytes) => NativeArchivePage {
            bytes,
            failure: None,
        },
        Err(_) => page_failure(NativeArchiveFailureKind::Write),
    }
}

/// Stops the snapshot `token` if it is still being built and deletes it.
#[must_use]
pub fn repository_session_archive_release(session_id: u64, generation: u64, token: u64) -> bool {
    let mut sessions = lock_sessions();
    let Ok(session) = sessions.session_mut(SessionKey::new(session_id, generation)) else {
        return false;
    };
    session.archives.jobs.remove(&token).is_some()
}

/// Files of this computer that snapshot pages are written to: a private part file beside the
/// destination that replaces it only once complete.
struct ArchiveFile {
    part: PathBuf,
    destination: PathBuf,
    file: Option<fs::File>,
}

impl Drop for ArchiveFile {
    fn drop(&mut self) {
        self.file = None;
        let _ = fs::remove_file(&self.part);
    }
}

const ARCHIVE_FILES: usize = 4;

fn archive_files() -> std::sync::MutexGuard<'static, (u64, HashMap<u64, ArchiveFile>)> {
    static FILES: std::sync::OnceLock<Mutex<(u64, HashMap<u64, ArchiveFile>)>> =
        std::sync::OnceLock::new();
    FILES
        .get_or_init(|| Mutex::new((0, HashMap::new())))
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Starts writing a snapshot to the absolute `destination` of this computer, which the person
/// chose in a save dialog; an existing file there is replaced when the write completes.
/// Returns the write's token, or `None` when the destination cannot be written.
#[must_use]
pub fn archive_file_begin(destination: String) -> Option<u64> {
    let destination = PathBuf::from(destination);
    let name = destination.file_name()?.to_str()?.to_owned();
    let parent = destination.parent()?;
    if !destination.is_absolute()
        || !parent.is_dir()
        || fs::symlink_metadata(&destination).is_ok_and(|metadata| metadata.is_dir())
    {
        return None;
    }
    let mut files = archive_files();
    if files.1.len() >= ARCHIVE_FILES {
        return None;
    }
    let part = parent.join(format!(
        ".{name}.gitlama-{}-{}.part",
        std::process::id(),
        NEXT_FILE.fetch_add(1, Ordering::Relaxed)
    ));
    let file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&part)
        .ok()?;
    files.0 += 1;
    let token = files.0;
    files.1.insert(
        token,
        ArchiveFile {
            part,
            destination,
            file: Some(file),
        },
    );
    Some(token)
}

/// Appends `bytes` to the write `token`; a failed write is abandoned.
#[must_use]
pub fn archive_file_append(token: u64, bytes: Vec<u8>) -> bool {
    let mut files = archive_files();
    let written = files
        .1
        .get_mut(&token)
        .and_then(|entry| entry.file.as_mut())
        .is_some_and(|file| file.write_all(&bytes).is_ok());
    if !written {
        files.1.remove(&token);
    }
    written
}

/// Completes the write `token`: the destination now holds exactly the appended bytes.
#[must_use]
pub fn archive_file_commit(token: u64) -> bool {
    let Some(mut entry) = archive_files().1.remove(&token) else {
        return false;
    };
    let Some(file) = entry.file.take() else {
        return false;
    };
    if file.sync_all().is_err() {
        return false;
    }
    drop(file);
    fs::rename(&entry.part, &entry.destination).is_ok()
}

/// Abandons the write `token` and deletes its part file.
pub fn archive_file_abort(token: u64) {
    archive_files().1.remove(&token);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_session_builds_pages_and_releases_a_snapshot() {
        use crate::activity::ActivityStore;
        use crate::application::session::{
            repository_session_close, repository_session_open_with_options,
        };
        use crate::test_support::{transfer_git, wait_for_ready, GitFixture};

        let fixture = GitFixture::new();
        fs::write(fixture.0.join("readme.txt"), b"hello\n").unwrap();
        transfer_git(&fixture.0, &["add", "readme.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        let commit = String::from_utf8(
            std::process::Command::new("git")
                .args(["rev-parse", "HEAD"])
                .current_dir(&fixture.0)
                .output()
                .unwrap()
                .stdout,
        )
        .unwrap()
        .trim()
        .to_owned();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_301,
            devmil_git::RepositoryOptions {
                watch: false,
                ..devmil_git::RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let (id, generation) = (session.session_id, session.generation);

        let refused = repository_session_archive_start(id, generation, "nope".into(), "x".into());
        assert_eq!(
            refused.failure.unwrap().kind,
            NativeArchiveFailureKind::InvalidRequest
        );
        let token = repository_session_archive_start(id, generation, commit, "repo-1".into())
            .token
            .unwrap();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(30);
        let status = loop {
            let status = repository_session_archive_status(id, generation, token);
            if status.state != NativeArchiveState::Running {
                break status;
            }
            assert!(std::time::Instant::now() < deadline);
            std::thread::sleep(std::time::Duration::from_millis(20));
        };
        assert_eq!(status.state, NativeArchiveState::Completed);
        assert_eq!(status.files, 1);
        let mut bytes = Vec::new();
        loop {
            let page = repository_session_archive_page(id, generation, token, bytes.len() as u64);
            assert!(page.failure.is_none());
            if page.bytes.is_empty() {
                break;
            }
            bytes.extend(page.bytes);
        }
        assert_eq!(bytes.len() as u64, status.archive_bytes);
        assert!(bytes.starts_with(b"PK"));
        assert!(repository_session_archive_release(id, generation, token));
        assert_eq!(
            repository_session_archive_status(id, generation, token)
                .failure
                .unwrap()
                .kind,
            NativeArchiveFailureKind::InvalidRequest
        );
        assert!(repository_session_close(id, generation).accepted);
    }

    #[test]
    fn archive_files_replace_the_destination_only_when_complete() {
        let directory = std::env::temp_dir().join(format!(
            "gitlama-archive-file-{}-{}",
            std::process::id(),
            NEXT_FILE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&directory).unwrap();
        let destination = directory.join("snapshot.zip");
        fs::write(&destination, b"old").unwrap();
        let path = destination.to_str().unwrap().to_owned();

        let abandoned = archive_file_begin(path.clone()).unwrap();
        assert!(archive_file_append(abandoned, b"partial".to_vec()));
        archive_file_abort(abandoned);
        assert_eq!(fs::read(&destination).unwrap(), b"old");

        let token = archive_file_begin(path).unwrap();
        assert!(archive_file_append(token, b"new ".to_vec()));
        assert!(archive_file_append(token, b"zip".to_vec()));
        assert!(archive_file_commit(token));
        assert_eq!(fs::read(&destination).unwrap(), b"new zip");
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
        assert!(!archive_file_commit(token));

        assert!(archive_file_begin("relative.zip".to_owned()).is_none());
        assert!(archive_file_begin(directory.to_str().unwrap().to_owned()).is_none());
        fs::remove_dir_all(&directory).unwrap();
    }
}
