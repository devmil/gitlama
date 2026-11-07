//! Application mutation policy layered over the shared Repository lease.

use devmil_git::activity::{ActivityEventSink, ActivityId, ActivityStatus};
use devmil_git::cancellation::Cancellation;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand};
use devmil_git::Repository;
use std::time::Duration;

/// A worktree scan after a large checkout can take many seconds on a cold or slow disk. Giving
/// up earlier reports a finished mutation as degraded although its refresh is merely running.
const RECONCILIATION_TIMEOUT: Duration = Duration::from_secs(30);

pub use crate::domain::outcome::MutationTerminalState;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ExecutionFailure {
    Canceled,
    Definite,
    Uncertain,
}

/// Runs a process-backed mutation through the shared process-tree owner. A canceled child is a
/// definite pre-commit cancellation; timeout, launch, and nonzero exit are definite failures.
/// The caller must construct the command so a successful exit is the external commit point.
pub fn coordinate_process_mutation(
    repository: &Repository,
    cancellation: &dyn Cancellation,
    command: GitProcessCommand,
    activity_id: ActivityId,
    activity_sink: &mut dyn ActivityEventSink,
) -> MutationTerminalState {
    coordinate_mutation(repository, cancellation, move |cancellation| {
        let activity =
            ActivityGitRunner::run(command, activity_id, Some(cancellation), activity_sink);
        match activity.status {
            ActivityStatus::Succeeded { .. } => Ok(()),
            ActivityStatus::Canceled { .. } => Err(ExecutionFailure::Canceled),
            ActivityStatus::Running
            | ActivityStatus::Failed { .. }
            | ActivityStatus::TimedOut { .. }
            | ActivityStatus::LaunchError { .. } => Err(ExecutionFailure::Definite),
        }
    })
}

/// Runs one mutation on the lease-owning thread. The mutation closure must return success only
/// after its external commit point. Cancellation after that return cannot recast the result.
pub fn coordinate_mutation<Mutate>(
    repository: &Repository,
    cancellation: &dyn Cancellation,
    mutate: Mutate,
) -> MutationTerminalState
where
    Mutate: FnOnce(&dyn Cancellation) -> Result<(), ExecutionFailure>,
{
    coordinate_leased_mutation(repository, cancellation, |cancellation, _| {
        mutate(cancellation)
    })
}

/// [`coordinate_mutation`] whose closure also receives the mutation lease, for reads that must
/// run under it such as [`devmil_git::model::RepositoryMutation::fresh_status`].
pub fn coordinate_leased_mutation<Mutate>(
    repository: &Repository,
    cancellation: &dyn Cancellation,
    mutate: Mutate,
) -> MutationTerminalState
where
    Mutate: FnOnce(
        &dyn Cancellation,
        &devmil_git::model::RepositoryMutation,
    ) -> Result<(), ExecutionFailure>,
{
    coordinate_leased_mutation_with_progress(repository, cancellation, || {}, mutate)
}

/// Notifies after a confirmed write, before waiting for its authoritative refresh.
/// The notification cannot change the terminal outcome or release its safety barrier.
pub fn coordinate_leased_mutation_with_progress<Mutate, Committed>(
    repository: &Repository,
    cancellation: &dyn Cancellation,
    committed: Committed,
    mutate: Mutate,
) -> MutationTerminalState
where
    Mutate: FnOnce(
        &dyn Cancellation,
        &devmil_git::model::RepositoryMutation,
    ) -> Result<(), ExecutionFailure>,
    Committed: FnOnce(),
{
    let lease = match repository.begin_mutation_with_cancellation(cancellation) {
        Ok(lease) => lease,
        Err(error) => {
            return if error.kind == devmil_git::RepositoryErrorKind::Canceled {
                MutationTerminalState::CanceledBeforeCommit
            } else {
                MutationTerminalState::FailedBeforeCommit
            };
        }
    };
    let execution = mutate(cancellation, &lease);
    drop(lease);
    match execution {
        Err(ExecutionFailure::Canceled) => MutationTerminalState::CanceledBeforeCommit,
        Err(ExecutionFailure::Definite) => MutationTerminalState::FailedBeforeCommit,
        Err(ExecutionFailure::Uncertain) => MutationTerminalState::OutcomeUncertain,
        Ok(()) => {
            committed();
            let reconciled = repository.reload().is_ok_and(|ticket| {
                ticket
                    .recv_timeout(RECONCILIATION_TIMEOUT)
                    .is_some_and(|result| result.is_ok())
            });
            if reconciled {
                MutationTerminalState::Succeeded
            } else {
                MutationTerminalState::SucceededRefreshFailed
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use devmil_git::RepositoryOptions;
    use std::fs;
    use std::path::PathBuf;
    use std::process::Command;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::time::{SystemTime, UNIX_EPOCH};

    static NEXT_FIXTURE: AtomicUsize = AtomicUsize::new(1);

    struct GitFixture(PathBuf);

    impl GitFixture {
        fn new() -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let sequence = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "gitlama-mutation-{}-{nonce}-{sequence}",
                std::process::id()
            ));
            fs::create_dir_all(&path).unwrap();
            fs::write(path.join("empty-config"), []).unwrap();
            let output = Command::new("git")
                .args(["init", "-q", "-b", "main"])
                .current_dir(&path)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", path.join("empty-config"))
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "git init failed: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            Self(path)
        }

        fn repository(&self) -> Repository {
            Repository::new(
                &self.0,
                RepositoryOptions {
                    watch: false,
                    ..RepositoryOptions::default()
                },
            )
            .unwrap()
        }
    }

    impl Drop for GitFixture {
        fn drop(&mut self) {
            fs::remove_dir_all(&self.0).unwrap();
        }
    }

    #[test]
    fn committed_progress_is_only_emitted_after_successful_mutation() {
        let fixture = GitFixture::new();
        let repository = fixture.repository();
        let cancellation = AtomicBool::new(false);
        let committed = std::cell::Cell::new(false);
        let result = coordinate_leased_mutation_with_progress(
            &repository,
            &cancellation,
            || committed.set(true),
            |_, _| {
                assert!(!committed.get());
                Ok(())
            },
        );
        assert!(result.committed());
        assert!(committed.get());
        committed.set(false);
        let result = coordinate_leased_mutation_with_progress(
            &repository,
            &cancellation,
            || committed.set(true),
            |_, _| Err(ExecutionFailure::Definite),
        );
        assert_eq!(result, MutationTerminalState::FailedBeforeCommit);
        assert!(!committed.get());
    }

    #[test]
    fn cancellation_before_commit_never_runs_mutation() {
        let fixture = GitFixture::new();
        let repository = fixture.repository();
        let cancellation = AtomicBool::new(true);
        let outcome = coordinate_mutation(&repository, &cancellation, |_| {
            panic!("pre-canceled mutation ran")
        });
        assert_eq!(outcome, MutationTerminalState::CanceledBeforeCommit);
        assert!(!outcome.committed());
    }

    #[test]
    fn cancellation_after_commit_keeps_success() {
        let fixture = GitFixture::new();
        let repository = fixture.repository();
        let cancellation = AtomicBool::new(false);
        let outcome = coordinate_mutation(&repository, &cancellation, |_| {
            cancellation.store(true, Ordering::Release);
            Ok(())
        });
        assert_eq!(outcome, MutationTerminalState::Succeeded);
        assert!(outcome.committed());
    }

    #[test]
    fn a_failed_refresh_degrades_without_recasting_success() {
        let fixture = GitFixture::new();
        let repository = fixture.repository();
        let cancellation = AtomicBool::new(false);
        let refresh = coordinate_mutation(&repository, &cancellation, |_| {
            repository.close();
            Ok(())
        });
        assert_eq!(refresh, MutationTerminalState::SucceededRefreshFailed);
        assert!(refresh.committed());
    }

    #[test]
    fn uncertain_execution_requires_reconciliation_before_retry() {
        let fixture = GitFixture::new();
        let repository = fixture.repository();
        let cancellation = AtomicBool::new(false);
        let outcome = coordinate_mutation(&repository, &cancellation, |_| {
            Err(ExecutionFailure::Uncertain)
        });
        assert_eq!(outcome, MutationTerminalState::OutcomeUncertain);
        assert!(!outcome.committed());
    }

    #[test]
    fn repository_lease_serializes_competing_mutations() {
        let fixture = GitFixture::new();
        let repository = Arc::new(fixture.repository());
        let active = Arc::new(AtomicUsize::new(0));
        let maximum = Arc::new(AtomicUsize::new(0));
        let mut workers = Vec::new();
        for _ in 0..2 {
            let repository = Arc::clone(&repository);
            let active = Arc::clone(&active);
            let maximum = Arc::clone(&maximum);
            workers.push(std::thread::spawn(move || {
                let cancellation = AtomicBool::new(false);
                coordinate_mutation(&repository, &cancellation, |_| {
                    let now = active.fetch_add(1, Ordering::AcqRel) + 1;
                    maximum.fetch_max(now, Ordering::AcqRel);
                    std::thread::sleep(Duration::from_millis(30));
                    active.fetch_sub(1, Ordering::AcqRel);
                    Ok(())
                })
            }));
        }
        for worker in workers {
            assert!(worker.join().unwrap().committed());
        }
        assert_eq!(maximum.load(Ordering::Acquire), 1);
    }

    #[cfg(unix)]
    #[test]
    fn process_cancellation_reaps_descendants_without_changing_repository() {
        use devmil_git::activity::ActivityId;
        use devmil_git::process::GitProcessCommand;
        use std::os::unix::fs::PermissionsExt;
        use std::time::Instant;

        let fixture = GitFixture::new();
        let repository = fixture.repository();
        let marker = fixture.0.join("unchanged");
        fs::write(&marker, b"before").unwrap();
        let executable = fixture.0.join("blocking-mutation");
        let parent_pid = fixture.0.join("parent.pid");
        let child_pid = fixture.0.join("child.pid");
        fs::write(
            &executable,
            format!(
                "#!/bin/sh\nprintf '%s' \"$$\" > '{}'\nsleep 30 &\nprintf '%s' \"$!\" > '{}'\nwait\n",
                parent_pid.display(),
                child_pid.display()
            ),
        )
        .unwrap();
        fs::set_permissions(&executable, fs::Permissions::from_mode(0o700)).unwrap();

        let cancellation = Arc::new(AtomicBool::new(false));
        let cancellation_for_thread = Arc::clone(&cancellation);
        let parent_for_thread = parent_pid.clone();
        let child_for_thread = child_pid.clone();
        let canceler = std::thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(5);
            while Instant::now() < deadline {
                if parent_for_thread.exists() && child_for_thread.exists() {
                    cancellation_for_thread.store(true, Ordering::Release);
                    return;
                }
                std::thread::sleep(Duration::from_millis(10));
            }
            panic!("process tree did not start before the cancellation deadline");
        });
        let command = GitProcessCommand::new(&executable).current_dir(&fixture.0);
        let mut sink = |_event| {};
        let outcome = coordinate_process_mutation(
            &repository,
            cancellation.as_ref(),
            command,
            ActivityId::new(1).unwrap(),
            &mut sink,
        );
        canceler.join().unwrap();

        assert_eq!(outcome, MutationTerminalState::CanceledBeforeCommit);
        assert!(!outcome.committed());
        assert_eq!(fs::read(&marker).unwrap(), b"before");
        for pid_file in [&parent_pid, &child_pid] {
            let pid = fs::read_to_string(pid_file).unwrap();
            let deadline = Instant::now() + Duration::from_secs(2);
            while Instant::now() < deadline
                && Command::new("kill")
                    .args(["-0", pid.trim()])
                    .output()
                    .is_ok_and(|output| output.status.success())
            {
                std::thread::sleep(Duration::from_millis(10));
            }
            assert!(
                !Command::new("kill")
                    .args(["-0", pid.trim()])
                    .output()
                    .unwrap()
                    .status
                    .success(),
                "process {pid} survived cancellation"
            );
        }
    }
}
