//! Locked lifecycle markers and disk-authoritative Git recovery inspection.
pub use gitlama_contract::recovery::*;

use crate::activity::allocate_activity_id;
use crate::storage::{validate, NativeSettingsDocument};
use devmil_git::activity::ActivityEvent;
use devmil_git::process::ActivityGitRunner;
use devmil_git::repository::{DiscoveryRequest, RepositoryDiscovery};
use devmil_git::types::RepositoryPath;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{self, File, OpenOptions, TryLockError};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

const CHECKPOINT_SCHEMA: &str = "gitlama.safe-restore.v1";
const MAX_CHECKPOINT_BYTES: u64 = 8 * 1024 * 1024;
const MAX_MARKER_BYTES: u64 = 64;

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Checkpoint {
    schema: String,
    document: NativeSettingsDocument,
}

struct RecoveryRun {
    directory: PathBuf,
    marker: Option<File>,
}

impl RecoveryRun {
    fn new(directory: PathBuf) -> Self {
        Self {
            directory,
            marker: None,
        }
    }

    fn marker_path(&self) -> PathBuf {
        self.directory.join("run-state-v1")
    }

    fn checkpoint_path(&self) -> PathBuf {
        self.directory.join("restore-v1.json")
    }

    fn begin(
        &mut self,
    ) -> Result<(NativePreviousShutdown, NativeSettingsDocument), NativeRecoveryFailureKind> {
        if self.marker.is_some() {
            return Err(NativeRecoveryFailureKind::AlreadyRunning);
        }
        fs::create_dir_all(&self.directory).map_err(|_| NativeRecoveryFailureKind::Io)?;
        reject_symlink_or_non_directory(&self.directory)?;
        let marker_path = self.marker_path();
        reject_symlink_or_non_regular_if_present(&marker_path)?;
        let mut marker = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(marker_path)
            .map_err(|_| NativeRecoveryFailureKind::Io)?;
        marker.try_lock().map_err(|error| match error {
            TryLockError::WouldBlock => NativeRecoveryFailureKind::Locked,
            TryLockError::Error(_) => NativeRecoveryFailureKind::Io,
        })?;
        let length = marker
            .metadata()
            .map_err(|_| NativeRecoveryFailureKind::Io)?
            .len();
        if length > MAX_MARKER_BYTES {
            return Err(NativeRecoveryFailureKind::InvalidCheckpoint);
        }
        let mut prior = Vec::with_capacity(usize::try_from(length).unwrap_or(0));
        marker
            .read_to_end(&mut prior)
            .map_err(|_| NativeRecoveryFailureKind::Io)?;
        let previous = match prior.as_slice() {
            b"" | b"clean\n" => NativePreviousShutdown::Clean,
            b"running\n" => NativePreviousShutdown::Unclean,
            _ => return Err(NativeRecoveryFailureKind::InvalidCheckpoint),
        };
        let checkpoint = read_checkpoint(&self.checkpoint_path())?;
        write_marker(&mut marker, b"running\n")?;
        self.marker = Some(marker);
        Ok((previous, checkpoint))
    }

    fn checkpoint(
        &self,
        document: &NativeSettingsDocument,
    ) -> Result<(), NativeRecoveryFailureKind> {
        if self.marker.is_none() {
            return Err(NativeRecoveryFailureKind::NotRunning);
        }
        write_checkpoint(&self.checkpoint_path(), document)
    }

    fn finish(
        &mut self,
        document: &NativeSettingsDocument,
    ) -> Result<(), NativeRecoveryFailureKind> {
        self.checkpoint(document)?;
        let marker = self
            .marker
            .as_mut()
            .ok_or(NativeRecoveryFailureKind::NotRunning)?;
        write_marker(marker, b"clean\n")?;
        marker.unlock().map_err(|_| NativeRecoveryFailureKind::Io)?;
        self.marker = None;
        Ok(())
    }
}

impl Drop for RecoveryRun {
    fn drop(&mut self) {
        if let Some(marker) = self.marker.take() {
            let _ = marker.unlock();
        }
    }
}

static RECOVERY_RUNS: OnceLock<Mutex<HashMap<String, RecoveryRun>>> = OnceLock::new();

fn runs() -> &'static Mutex<HashMap<String, RecoveryRun>> {
    RECOVERY_RUNS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub fn recovery_begin(directory: String) -> NativeRecoveryStartResult {
    let mut runs = runs()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if runs.contains_key(&directory) {
        return start_failure(NativeRecoveryFailureKind::AlreadyRunning);
    }
    let mut run = RecoveryRun::new(PathBuf::from(&directory));
    match run.begin() {
        Ok((previous_shutdown, checkpoint)) => {
            runs.insert(directory, run);
            NativeRecoveryStartResult {
                previous_shutdown: Some(previous_shutdown),
                checkpoint: Some(checkpoint),
                failure: None,
            }
        }
        Err(kind) => start_failure(kind),
    }
}

pub fn recovery_default_directory() -> NativeRecoveryPathResult {
    let settings = crate::storage::settings_default_path();
    if settings.failure.is_some() {
        return NativeRecoveryPathResult {
            path: None,
            failure: Some(NativeRecoveryFailure {
                kind: NativeRecoveryFailureKind::Io,
            }),
        };
    }
    let path = settings
        .path
        .and_then(|path| PathBuf::from(path).parent().map(Path::to_path_buf))
        .map(|directory| directory.join("recovery"))
        .and_then(|path| path.into_os_string().into_string().ok());
    match path {
        Some(path) => NativeRecoveryPathResult {
            path: Some(path),
            failure: None,
        },
        None => NativeRecoveryPathResult {
            path: None,
            failure: Some(NativeRecoveryFailure {
                kind: NativeRecoveryFailureKind::Io,
            }),
        },
    }
}

pub fn recovery_checkpoint(
    directory: String,
    document: NativeSettingsDocument,
) -> NativeRecoveryCommandResult {
    let runs = runs()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let Some(run) = runs.get(&directory) else {
        return command_failure(NativeRecoveryFailureKind::NotRunning);
    };
    match run.checkpoint(&safe_document(document)) {
        Ok(()) => command_success(),
        Err(kind) => command_failure(kind),
    }
}

pub fn recovery_finish_clean(
    directory: String,
    document: NativeSettingsDocument,
) -> NativeRecoveryCommandResult {
    let mut runs = runs()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let Some(run) = runs.get_mut(&directory) else {
        return command_failure(NativeRecoveryFailureKind::NotRunning);
    };
    match run.finish(&safe_document(document)) {
        Ok(()) => {
            runs.remove(&directory);
            command_success()
        }
        Err(kind) => command_failure(kind),
    }
}

pub fn recovery_inspect_repository(path: String) -> NativeSequencerInspectionResult {
    match inspect_repository(Path::new(&path)) {
        Ok(state) => NativeSequencerInspectionResult {
            state,
            failure: None,
        },
        Err(kind) => NativeSequencerInspectionResult {
            state: None,
            failure: Some(NativeRecoveryFailure { kind }),
        },
    }
}

fn safe_document(mut document: NativeSettingsDocument) -> NativeSettingsDocument {
    let open = document.open_worktrees.clone();
    document
        .worktrees
        .retain(|worktree| open.contains(&worktree.identity));
    for group in &mut document.tab_groups {
        group.members.retain(|member| open.contains(member));
    }
    document
        .tab_groups
        .retain(|group| !group.members.is_empty());
    document
}

fn inspect_repository(
    path: &Path,
) -> Result<Option<NativeSequencerState>, NativeRecoveryFailureKind> {
    let repository_path =
        RepositoryPath::new(path).map_err(|_| NativeRecoveryFailureKind::NotRepository)?;
    let request = DiscoveryRequest::new(repository_path);
    let mut sink = |_event: ActivityEvent| {};
    let discovered = RepositoryDiscovery::default()
        .discover(&request, &mut |command| {
            ActivityGitRunner::run(command, allocate_activity_id(), None, &mut sink)
        })
        .map_err(|_| NativeRecoveryFailureKind::NotRepository)?;
    let git_dir = discovered.worktree.git_dir().as_path();
    inspect_git_dir(git_dir, path)
}

fn inspect_git_dir(
    git_dir: &Path,
    worktree: &Path,
) -> Result<Option<NativeSequencerState>, NativeRecoveryFailureKind> {
    use devmil_git::status::{discover_operations_checked, OperationDiscoveryError, OperationKind};
    let mut operations = discover_operations_checked(git_dir)
        .map_err(|error| match error {
            OperationDiscoveryError::Unreadable => NativeRecoveryFailureKind::Io,
            OperationDiscoveryError::UnsafeState
            | OperationDiscoveryError::Ambiguous
            | OperationDiscoveryError::Malformed => NativeRecoveryFailureKind::UnsafeGitState,
        })?
        .operations;
    // Recovery offers one action at a time, so any combination is left to Git's own tools.
    if operations.len() > 1 {
        return Err(NativeRecoveryFailureKind::UnsafeGitState);
    }
    let Some(operation) = operations.pop() else {
        return Ok(None);
    };
    let kind = match operation.kind {
        OperationKind::Rebase => NativeSequencerKind::Rebase,
        OperationKind::Merge => NativeSequencerKind::Merge,
        OperationKind::CherryPick => NativeSequencerKind::CherryPick,
        OperationKind::Revert => NativeSequencerKind::Revert,
        OperationKind::Bisect => NativeSequencerKind::Bisect,
    };
    let (current, total) = (operation.current, operation.total);
    let conflicts = index_has_conflicts(worktree)?;
    Ok(Some(NativeSequencerState {
        kind,
        current,
        total,
        index_has_conflicts: conflicts,
        can_continue: !conflicts,
        can_abort: true,
    }))
}

fn index_has_conflicts(worktree: &Path) -> Result<bool, NativeRecoveryFailureKind> {
    devmil_git::probes::unmerged_paths(
        std::ffi::OsStr::new("git"),
        worktree,
        &mut crate::git_probe::ProbeExecutor::new(None),
    )
    .map(|paths| !paths.is_empty())
    .map_err(|_| NativeRecoveryFailureKind::UnsafeGitState)
}

fn write_checkpoint(
    path: &Path,
    document: &NativeSettingsDocument,
) -> Result<(), NativeRecoveryFailureKind> {
    validate(document).map_err(|()| NativeRecoveryFailureKind::InvalidCheckpoint)?;
    let checkpoint = Checkpoint {
        schema: CHECKPOINT_SCHEMA.into(),
        document: document.clone(),
    };
    let bytes = serde_json::to_vec_pretty(&checkpoint)
        .map_err(|_| NativeRecoveryFailureKind::InvalidCheckpoint)?;
    if bytes.len() as u64 > MAX_CHECKPOINT_BYTES {
        return Err(NativeRecoveryFailureKind::InvalidCheckpoint);
    }
    write_atomic(path, &bytes)
}

fn read_checkpoint(path: &Path) -> Result<NativeSettingsDocument, NativeRecoveryFailureKind> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(NativeSettingsDocument::default());
        }
        Err(_) => return Err(NativeRecoveryFailureKind::Io),
    };
    if metadata.file_type().is_symlink()
        || !metadata.is_file()
        || metadata.len() > MAX_CHECKPOINT_BYTES
    {
        return Err(NativeRecoveryFailureKind::InvalidCheckpoint);
    }
    let bytes = fs::read(path).map_err(|_| NativeRecoveryFailureKind::Io)?;
    let checkpoint: Checkpoint =
        serde_json::from_slice(&bytes).map_err(|_| NativeRecoveryFailureKind::InvalidCheckpoint)?;
    if checkpoint.schema != CHECKPOINT_SCHEMA || validate(&checkpoint.document).is_err() {
        return Err(NativeRecoveryFailureKind::InvalidCheckpoint);
    }
    Ok(checkpoint.document)
}

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), NativeRecoveryFailureKind> {
    let temporary = path.with_extension(format!("tmp.{}", std::process::id()));
    let backup = path.with_extension(format!("backup.{}", std::process::id()));
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(&temporary)
        .map_err(|_| NativeRecoveryFailureKind::Io)?;
    file.write_all(bytes)
        .and_then(|()| file.sync_all())
        .map_err(|_| NativeRecoveryFailureKind::Io)?;
    drop(file);
    if path.exists() {
        if backup.exists() {
            fs::remove_file(&backup).map_err(|_| NativeRecoveryFailureKind::Io)?;
        }
        fs::rename(path, &backup).map_err(|_| NativeRecoveryFailureKind::Io)?;
    }
    if fs::rename(&temporary, path).is_err() {
        if backup.exists() && !path.exists() {
            let _ = fs::rename(&backup, path);
        }
        return Err(NativeRecoveryFailureKind::Io);
    }
    sync_parent(path)?;
    if backup.exists() {
        fs::remove_file(backup).map_err(|_| NativeRecoveryFailureKind::Io)?;
        sync_parent(path)?;
    }
    Ok(())
}

#[cfg(unix)]
fn sync_parent(path: &Path) -> Result<(), NativeRecoveryFailureKind> {
    File::open(path.parent().ok_or(NativeRecoveryFailureKind::Io)?)
        .and_then(|directory| directory.sync_all())
        .map_err(|_| NativeRecoveryFailureKind::Io)
}

#[cfg(windows)]
fn sync_parent(path: &Path) -> Result<(), NativeRecoveryFailureKind> {
    path.parent()
        .is_some()
        .then_some(())
        .ok_or(NativeRecoveryFailureKind::Io)
}

fn write_marker(file: &mut File, bytes: &[u8]) -> Result<(), NativeRecoveryFailureKind> {
    file.seek(SeekFrom::Start(0))
        .and_then(|_| file.set_len(0))
        .and_then(|()| file.write_all(bytes))
        .and_then(|()| file.sync_all())
        .map_err(|_| NativeRecoveryFailureKind::Io)
}

fn reject_symlink_or_non_directory(path: &Path) -> Result<(), NativeRecoveryFailureKind> {
    let metadata = fs::symlink_metadata(path).map_err(|_| NativeRecoveryFailureKind::Io)?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        Err(NativeRecoveryFailureKind::InvalidCheckpoint)
    } else {
        Ok(())
    }
}

fn reject_symlink_or_non_regular_if_present(path: &Path) -> Result<(), NativeRecoveryFailureKind> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            Err(NativeRecoveryFailureKind::InvalidCheckpoint)
        }
        Ok(_) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err(NativeRecoveryFailureKind::Io),
    }
}

fn start_failure(kind: NativeRecoveryFailureKind) -> NativeRecoveryStartResult {
    NativeRecoveryStartResult {
        previous_shutdown: None,
        checkpoint: None,
        failure: Some(NativeRecoveryFailure { kind }),
    }
}

fn command_success() -> NativeRecoveryCommandResult {
    NativeRecoveryCommandResult {
        completed: true,
        failure: None,
    }
}

fn command_failure(kind: NativeRecoveryFailureKind) -> NativeRecoveryCommandResult {
    NativeRecoveryCommandResult {
        completed: false,
        failure: Some(NativeRecoveryFailure { kind }),
    }
}

crate::family_failures!(NativeRecoveryFailureKind, "recovery", {
    Io => Read,
    Locked => Busy,
    AlreadyRunning => Busy,
    NotRunning => Unavailable,
    InvalidCheckpoint => InvalidRequest,
    UnsafeGitState => Precondition,
    NotRepository => NotFound,
});

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT: AtomicU64 = AtomicU64::new(1);

    struct Fixture(PathBuf);

    impl Fixture {
        fn new(name: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "gitlama-recovery-{name}-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            fs::remove_dir_all(&self.0).unwrap();
        }
    }

    #[test]
    fn stale_running_marker_reports_unclean_but_live_owner_is_locked() {
        let fixture = Fixture::new("marker");
        let mut first = RecoveryRun::new(fixture.0.clone());
        assert_eq!(first.begin().unwrap().0, NativePreviousShutdown::Clean);
        let mut second = RecoveryRun::new(fixture.0.clone());
        assert_eq!(
            second.begin().unwrap_err(),
            NativeRecoveryFailureKind::Locked
        );
        drop(first);
        assert_eq!(second.begin().unwrap().0, NativePreviousShutdown::Unclean);
    }

    #[test]
    fn checkpoint_contains_only_open_safe_state_and_clean_transition() {
        let fixture = Fixture::new("checkpoint");
        let mut run = RecoveryRun::new(fixture.0.clone());
        run.begin().unwrap();
        let document = NativeSettingsDocument::default();
        run.checkpoint(&document).unwrap();
        run.finish(&document).unwrap();
        let mut restarted = RecoveryRun::new(fixture.0.clone());
        let (previous, restored) = restarted.begin().unwrap();
        assert_eq!(previous, NativePreviousShutdown::Clean);
        assert_eq!(restored, document);
    }

    #[test]
    fn malformed_and_symlinked_checkpoints_fail_closed() {
        let fixture = Fixture::new("unsafe-checkpoint");
        fs::write(fixture.0.join("restore-v1.json"), b"private malformed").unwrap();
        let mut run = RecoveryRun::new(fixture.0.clone());
        assert_eq!(
            run.begin().unwrap_err(),
            NativeRecoveryFailureKind::InvalidCheckpoint
        );
    }

    #[test]
    fn additive_settings_fields_do_not_invalidate_an_older_safe_checkpoint() {
        let fixture = Fixture::new("additive-checkpoint");
        let path = fixture.0.join("restore-v1.json");
        fs::write(
            &path,
            include_bytes!("../test-fixtures/recovery/safe-restore-v1-before-changes-layout.json"),
        )
        .unwrap();

        let restored = read_checkpoint(&path).unwrap();
        assert_eq!(restored.appearance.changes_unstaged_mode, "list");
        assert_eq!(restored.appearance.changes_staged_mode, "list");
        assert_eq!(restored.appearance.changes_split_ratio, 500);
        assert_eq!(restored.worktrees.len(), 1);
        assert_eq!(restored.shortcut_overrides, Vec::new());
    }

    #[test]
    fn disk_sequencer_truth_overrides_absent_checkpoint_operation_state() {
        let fixture = Fixture::new("merge");
        git(&fixture.0, &["init", "-q", "-b", "main"]);
        git(&fixture.0, &["config", "user.name", "GitLama Test"]);
        git(
            &fixture.0,
            &["config", "user.email", "test@example.invalid"],
        );
        fs::write(fixture.0.join("tracked"), b"base\n").unwrap();
        git(&fixture.0, &["add", "tracked"]);
        git(&fixture.0, &["commit", "-qm", "base"]);
        let head = git_output(&fixture.0, &["rev-parse", "HEAD"]);
        fs::write(fixture.0.join(".git/MERGE_HEAD"), &head).unwrap();

        let state = inspect_git_dir(&fixture.0.join(".git"), &fixture.0)
            .unwrap()
            .unwrap();
        assert_eq!(state.kind, NativeSequencerKind::Merge);
        assert!(state.can_continue);
        assert!(state.can_abort);
    }

    #[test]
    fn ambiguous_or_symlinked_git_markers_fail_closed_without_cleanup() {
        let fixture = Fixture::new("ambiguous");
        git(&fixture.0, &["init", "-q", "-b", "main"]);
        let git_dir = fixture.0.join(".git");
        let oid = b"1111111111111111111111111111111111111111\n";
        fs::write(git_dir.join("MERGE_HEAD"), oid).unwrap();
        fs::write(git_dir.join("CHERRY_PICK_HEAD"), oid).unwrap();
        let unrelated = fixture.0.join("unrelated-dirty-file");
        fs::write(&unrelated, b"keep").unwrap();

        assert_eq!(
            inspect_git_dir(&git_dir, &fixture.0).unwrap_err(),
            NativeRecoveryFailureKind::UnsafeGitState
        );
        assert_eq!(fs::read(unrelated).unwrap(), b"keep");
    }

    fn git(path: &Path, arguments: &[&str]) {
        let output = Command::new("git")
            .args(arguments)
            .current_dir(path)
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_CONFIG_GLOBAL", path.join("empty-config"))
            .output()
            .unwrap();
        assert!(output.status.success());
    }

    fn git_output(path: &Path, arguments: &[&str]) -> Vec<u8> {
        let output = Command::new("git")
            .args(arguments)
            .current_dir(path)
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_CONFIG_GLOBAL", path.join("empty-config"))
            .output()
            .unwrap();
        assert!(output.status.success());
        output.stdout
    }
}
