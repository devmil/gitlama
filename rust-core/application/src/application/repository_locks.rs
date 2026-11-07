//! Inspecting the Git lock files of a repository and removing stale ones.
#![allow(clippy::wildcard_imports)]
use crate::application::index_lock::{map_index_lock_error, map_missing_index_lock_failure};
use crate::application::session::*;
use crate::domain::ids::SessionKey;
use crate::dto::*;
use devmil_git::git_locks::{
    inspect_git_locks, remove_git_lock, GitLockError, GitLockLimits, GitLockScope, GitLockSnapshot,
};
use devmil_git::index_lock::IndexLockError;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime};

/// The lock files a session last inspected, each with the token that removes it.
#[derive(Default)]
pub(crate) struct RepositoryLockState {
    pub(crate) next_token: u64,
    pub(crate) inspected: Vec<(u64, GitLockSnapshot)>,
}

/// Lists the repository's lock files. Reading metadata changes nothing, so this
/// runs while other work is in progress.
#[must_use]
pub fn repository_session_inspect_locks(
    session_id: u64,
    generation: u64,
) -> NativeRepositoryLockInspectionResult {
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return inspection_failure(map_missing_index_lock_failure(kind)),
    };
    session.repository_locks.inspected.clear();
    let snapshot = session.repository.snapshot();
    let Some(repository) = snapshot.repository.as_ref() else {
        return inspection_failure(NativeIndexLockFailureKind::RepositoryNotReady);
    };
    let inspection = match inspect_git_locks(&repository.worktree, GitLockLimits::default()) {
        Ok(inspection) => inspection,
        Err(error) => return inspection_failure(map_error(error)),
    };
    let now = SystemTime::now();
    let state = &mut session.repository_locks;
    let mut locks = Vec::with_capacity(inspection.locks.len());
    for lock in inspection.locks {
        state.next_token = state.next_token.saturating_add(1).max(1);
        locks.push(NativeRepositoryLock {
            token: state.next_token,
            path: lock
                .relative_path()
                .to_string_lossy()
                .replace(std::path::MAIN_SEPARATOR, "/"),
            worktree_scoped: lock.scope() == GitLockScope::Worktree,
            size_bytes: lock.size_bytes(),
            age_seconds: lock
                .modified()
                .and_then(|modified| now.duration_since(modified).ok())
                .map(|age| age.as_secs()),
        });
        state.inspected.push((state.next_token, lock));
    }
    NativeRepositoryLockInspectionResult {
        locks,
        truncated: inspection.truncated,
        failure: None,
    }
}

/// Removes the inspected lock named by [token] once the user confirmed. The
/// lock is removed only while it is the file that was inspected. A token is
/// good for one attempt; the other inspected locks keep theirs.
#[must_use]
pub fn repository_session_remove_lock(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeIndexLockRemovalResult {
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return removal_failure(map_missing_index_lock_failure(kind)),
    };
    let inspected = &mut session.repository_locks.inspected;
    let Some(position) = inspected
        .iter()
        .position(|(inspected, _)| token != 0 && *inspected == token)
    else {
        return removal_failure(NativeIndexLockFailureKind::InvalidToken);
    };
    let (_, lock) = inspected.swap_remove(position);
    let cancellation = Arc::new(AtomicBool::new(false));
    let deadline = Arc::clone(&cancellation);
    let _cancel_thread = std::thread::spawn(move || {
        // As for the index lock: let a just-released mutation's refresh finish.
        std::thread::sleep(Duration::from_secs(2));
        deadline.store(true, Ordering::Release);
    });
    let Ok(mutation) = session
        .repository
        .begin_mutation_with_cancellation(cancellation.as_ref())
    else {
        return removal_failure(NativeIndexLockFailureKind::ActiveOperation);
    };
    let result = remove_git_lock(&lock);
    drop(mutation);
    match result {
        Ok(()) => NativeIndexLockRemovalResult {
            removed: true,
            failure: None,
        },
        Err(error) => removal_failure(map_error(error)),
    }
}

const fn map_error(error: GitLockError) -> NativeIndexLockFailureKind {
    map_index_lock_error(match error {
        GitLockError::Missing => IndexLockError::Missing,
        GitLockError::Changed => IndexLockError::Changed,
        GitLockError::UnsafeFile => IndexLockError::UnsafeFile,
        GitLockError::Io => IndexLockError::Io,
    })
}

fn inspection_failure(failure: NativeIndexLockFailureKind) -> NativeRepositoryLockInspectionResult {
    NativeRepositoryLockInspectionResult {
        locks: Vec::new(),
        truncated: false,
        failure: Some(failure),
    }
}

const fn removal_failure(failure: NativeIndexLockFailureKind) -> NativeIndexLockRemovalResult {
    NativeIndexLockRemovalResult {
        removed: false,
        failure: Some(failure),
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::application::repository_locks::*;
    use crate::test_support::*;
    use devmil_git::RepositoryOptions;
    use std::fs;

    #[test]
    fn ref_and_index_locks_are_listed_and_removed_only_while_unchanged() {
        let fixture = GitFixture::new();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            76,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let empty = repository_session_inspect_locks(session.session_id, 76);
        assert_eq!(empty.failure, None);
        assert!(empty.locks.is_empty());

        fs::create_dir_all(fixture.0.join(".git/refs/remotes/origin")).unwrap();
        let ref_lock = fixture.0.join(".git/refs/remotes/origin/topic.lock");
        let index_lock = fixture.0.join(".git/index.lock");
        fs::write(&ref_lock, b"ref").unwrap();
        fs::write(&index_lock, b"index").unwrap();
        let inspected = repository_session_inspect_locks(session.session_id, 76);
        let paths: Vec<_> = inspected
            .locks
            .iter()
            .map(|lock| lock.path.as_str())
            .collect();
        assert_eq!(paths, ["index.lock", "refs/remotes/origin/topic.lock"]);
        assert!(inspected
            .locks
            .iter()
            .all(|lock| lock.age_seconds.is_some()));

        // A changed lock stays; its token is spent, the other lock's is not.
        fs::write(&index_lock, b"changed index").unwrap();
        let (index, reference) = (&inspected.locks[0], &inspected.locks[1]);
        let changed = repository_session_remove_lock(session.session_id, 76, index.token);
        assert_eq!(changed.failure, Some(NativeIndexLockFailureKind::Changed));
        assert!(index_lock.exists());
        let spent = repository_session_remove_lock(session.session_id, 76, index.token);
        assert_eq!(
            spent.failure,
            Some(NativeIndexLockFailureKind::InvalidToken)
        );
        let removed = repository_session_remove_lock(session.session_id, 76, reference.token);
        assert!(removed.removed);
        assert!(!ref_lock.exists());

        let inspected = repository_session_inspect_locks(session.session_id, 76);
        assert_eq!(inspected.locks.len(), 1);
        let removed =
            repository_session_remove_lock(session.session_id, 76, inspected.locks[0].token);
        assert!(removed.removed);
        assert!(!index_lock.exists());
        assert!(repository_session_close(session.session_id, 76).accepted);
    }
}
