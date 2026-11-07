//! Offering Git's status accelerators to a repository whose status scans are slow.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::application::snapshot::map_error_kind;
use crate::domain::ids::SessionKey;
use crate::dto::*;
use devmil_git::activity::ActivityStatus;
use devmil_git::probes::ProbeFailure;
use devmil_git::status_acceleration::{self, StatusAcceleration};
use std::ffi::OsString;
use std::path::PathBuf;
use std::sync::Arc;

struct Target {
    repository: Arc<devmil_git::Repository>,
    activity: crate::activity::ActivityStore,
    executable: OsString,
    worktree: PathBuf,
    version: devmil_git::version::GitVersion,
    last_scan_millis: Option<u64>,
}

fn target(session_id: u64, generation: u64) -> Result<Target, NativeRepositoryFailureKind> {
    let mut sessions = lock_sessions();
    let session = sessions.session_mut(SessionKey::new(session_id, generation))?;
    let snapshot = session.repository.snapshot();
    let Some(discovered) = snapshot.repository.as_ref() else {
        return Err(NativeRepositoryFailureKind::Discovery);
    };
    if discovered.kind == devmil_git::repository::RepositoryKind::Bare {
        return Err(NativeRepositoryFailureKind::Unsupported);
    }
    Ok(Target {
        repository: Arc::clone(&session.repository),
        activity: session.activity.clone(),
        executable: session.repository.git_executable().to_os_string(),
        worktree: discovered.worktree.worktree_root().as_path().to_path_buf(),
        version: discovered.git_version,
        last_scan_millis: last_scan_millis(&snapshot.status_activities),
    })
}

/// The wall time of the status scan the snapshot's status came from.
fn last_scan_millis(activities: &[devmil_git::activity::ActivityRecord]) -> Option<u64> {
    let finished = activities
        .iter()
        .filter(|record| matches!(record.status, ActivityStatus::Succeeded { .. }))
        .filter_map(|record| record.finished_at_unix_ms)
        .max()?;
    let started = activities
        .iter()
        .map(|record| record.started_at_unix_ms)
        .min()?;
    finished.checked_sub(started)
}

const fn failure_kind(failure: ProbeFailure) -> NativeRepositoryFailureKind {
    match failure {
        ProbeFailure::MissingGit => NativeRepositoryFailureKind::MissingGit,
        ProbeFailure::Canceled => NativeRepositoryFailureKind::Canceled,
        ProbeFailure::InvalidArgument => NativeRepositoryFailureKind::InvalidOptions,
        ProbeFailure::InvalidOutput | ProbeFailure::TooMany => {
            NativeRepositoryFailureKind::InvalidOutput
        }
        ProbeFailure::GitFailed => NativeRepositoryFailureKind::Read,
    }
}

fn read(target: &Target) -> Result<StatusAcceleration, NativeRepositoryFailureKind> {
    status_acceleration::read(
        &target.executable,
        &target.worktree,
        target.version,
        &mut crate::git_probe::ProbeExecutor::new(None),
    )
    .map_err(failure_kind)
}

fn result(
    target: &Target,
    acceleration: Result<StatusAcceleration, NativeRepositoryFailureKind>,
) -> NativeStatusAccelerationResult {
    match acceleration {
        Ok(acceleration) => NativeStatusAccelerationResult {
            acceleration: Some(NativeStatusAcceleration {
                untracked_cache: acceleration.untracked_cache,
                fsmonitor: acceleration.fsmonitor,
                fsmonitor_available: acceleration.fsmonitor_available,
                last_scan_millis: target.last_scan_millis,
            }),
            failure: None,
        },
        Err(kind) => failure(kind),
    }
}

const fn failure(kind: NativeRepositoryFailureKind) -> NativeStatusAccelerationResult {
    NativeStatusAccelerationResult {
        acceleration: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

/// Reads the effective accelerator settings. Changes nothing.
#[must_use]
pub fn repository_session_status_acceleration(
    session_id: u64,
    generation: u64,
) -> NativeStatusAccelerationResult {
    match target(session_id, generation) {
        Ok(target) => {
            let acceleration = read(&target);
            result(&target, acceleration)
        }
        Err(kind) => failure(kind),
    }
}

/// Writes the missing accelerators to the repository's local configuration under the
/// session's mutation lease and records the writes in its activity. Releasing the lease
/// rescans status, which populates Git's caches.
#[must_use]
pub fn repository_session_enable_status_acceleration(
    session_id: u64,
    generation: u64,
) -> NativeStatusAccelerationResult {
    let target = match target(session_id, generation) {
        Ok(target) => target,
        Err(kind) => return failure(kind),
    };
    let mutation = match target.repository.begin_mutation() {
        Ok(mutation) => mutation,
        Err(error) => return failure(map_error_kind(error.kind)),
    };
    let enabled = read(&target).and_then(|current| {
        crate::git_probe::run_published_probe(&target.activity, |executor| {
            status_acceleration::enable(&target.executable, &target.worktree, current, executor)
        })
        .map_err(failure_kind)
    });
    let after = enabled.and_then(|()| read(&target));
    drop(mutation);
    result(&target, after)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::activity::ActivityStore;
    use crate::application::session::repository_session_open_with_options;
    use crate::test_support::*;
    use devmil_git::RepositoryOptions;
    use std::process::Command;

    #[test]
    fn reports_the_last_scan_and_enables_the_untracked_cache_locally() {
        let fixture = GitFixture::new();
        let generation = 931;
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            generation,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let before = repository_session_status_acceleration(session.session_id, generation)
            .acceleration
            .unwrap();
        assert!(before.last_scan_millis.is_some());
        let enabled = repository_session_enable_status_acceleration(session.session_id, generation);
        assert!(enabled.failure.is_none(), "{:?}", enabled.failure);
        assert!(enabled.acceleration.unwrap().untracked_cache);
        let local = Command::new("git")
            .args(["config", "--local", "--get", "core.untrackedCache"])
            .current_dir(&fixture.0)
            .output()
            .unwrap();
        assert_eq!(String::from_utf8_lossy(&local.stdout).trim(), "true");
        assert!(
            repository_session_status_acceleration(session.session_id, u64::MAX)
                .failure
                .is_some()
        );
        let _ =
            crate::application::session::repository_session_close(session.session_id, generation);
    }
}
