//! Inspecting and removing a stale Git index lock.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::domain::ids::SessionKey;
use crate::dto::*;
use devmil_git::index_lock::{inspect_index_lock, remove_index_lock, IndexLockError};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

/// The index lock a session last inspected, and the token that removes it.
#[derive(Default)]
pub(crate) struct IndexLockState {
    pub(crate) next_token: u64,
    pub(crate) inspected: Option<(u64, devmil_git::index_lock::IndexLockSnapshot)>,
}

#[must_use]
pub fn repository_session_inspect_index_lock(
    session_id: u64,
    generation: u64,
) -> NativeIndexLockInspectionResult {
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return index_lock_inspection_failure(map_missing_index_lock_failure(kind)),
    };
    session.index_lock.inspected = None;
    let snapshot = session.repository.snapshot();
    if snapshot
        .status
        .as_ref()
        .is_some_and(|status| !status.operations.is_empty())
    {
        return index_lock_inspection_failure(NativeIndexLockFailureKind::ActiveOperation);
    }
    let Some(repository) = snapshot.repository.as_ref() else {
        return index_lock_inspection_failure(NativeIndexLockFailureKind::RepositoryNotReady);
    };
    match inspect_index_lock(&repository.worktree) {
        Ok(Some(inspected)) => {
            session.index_lock.next_token = session.index_lock.next_token.saturating_add(1).max(1);
            let token = session.index_lock.next_token;
            let size_bytes = inspected.size_bytes();
            session.index_lock.inspected = Some((token, inspected));
            NativeIndexLockInspectionResult {
                present: true,
                token: Some(token),
                size_bytes: Some(size_bytes),
                failure: None,
            }
        }
        Ok(None) => NativeIndexLockInspectionResult {
            present: false,
            token: None,
            size_bytes: None,
            failure: None,
        },
        Err(error) => index_lock_inspection_failure(map_index_lock_error(error)),
    }
}

#[must_use]
pub fn repository_session_remove_index_lock(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeIndexLockRemovalResult {
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return index_lock_removal_failure(map_missing_index_lock_failure(kind)),
    };
    let Some((inspected_token, inspected)) = session.index_lock.inspected.take() else {
        return index_lock_removal_failure(NativeIndexLockFailureKind::InvalidToken);
    };
    if token == 0 || token != inspected_token {
        return index_lock_removal_failure(NativeIndexLockFailureKind::InvalidToken);
    }
    if session
        .repository
        .snapshot()
        .status
        .as_ref()
        .is_some_and(|status| !status.operations.is_empty())
    {
        return index_lock_removal_failure(NativeIndexLockFailureKind::ActiveOperation);
    }
    let cancellation = Arc::new(AtomicBool::new(false));
    let deadline = Arc::clone(&cancellation);
    let _cancel_thread = std::thread::spawn(move || {
        // A just-released mutation schedules one repository refresh. Give that
        // bounded worker pass time to finish without weakening the immediate
        // same-thread nested-mutation refusal.
        std::thread::sleep(Duration::from_secs(2));
        deadline.store(true, Ordering::Release);
    });
    let mutation = match session
        .repository
        .begin_mutation_with_cancellation(cancellation.as_ref())
    {
        Ok(mutation) => mutation,
        Err(_) => {
            return index_lock_removal_failure(NativeIndexLockFailureKind::ActiveOperation);
        }
    };
    let result = remove_index_lock(&inspected);
    drop(mutation);
    match result {
        Ok(()) => NativeIndexLockRemovalResult {
            removed: true,
            failure: None,
        },
        Err(error) => index_lock_removal_failure(map_index_lock_error(error)),
    }
}

pub(crate) fn index_lock_inspection_failure(
    failure: NativeIndexLockFailureKind,
) -> NativeIndexLockInspectionResult {
    NativeIndexLockInspectionResult {
        present: false,
        token: None,
        size_bytes: None,
        failure: Some(failure),
    }
}

pub(crate) fn index_lock_removal_failure(
    failure: NativeIndexLockFailureKind,
) -> NativeIndexLockRemovalResult {
    NativeIndexLockRemovalResult {
        removed: false,
        failure: Some(failure),
    }
}

pub(crate) const fn map_index_lock_error(error: IndexLockError) -> NativeIndexLockFailureKind {
    match error {
        IndexLockError::Missing => NativeIndexLockFailureKind::Missing,
        IndexLockError::Changed => NativeIndexLockFailureKind::Changed,
        IndexLockError::UnsafeFile => NativeIndexLockFailureKind::UnsafeFile,
        IndexLockError::Io => NativeIndexLockFailureKind::Io,
    }
}

pub(crate) const fn map_missing_index_lock_failure(
    failure: NativeRepositoryFailureKind,
) -> NativeIndexLockFailureKind {
    match failure {
        NativeRepositoryFailureKind::RetiredSession => NativeIndexLockFailureKind::RetiredSession,
        NativeRepositoryFailureKind::StaleGeneration => NativeIndexLockFailureKind::StaleGeneration,
        _ => NativeIndexLockFailureKind::UnknownSession,
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::index_lock::*;

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[test]
    fn index_lock_removal_requires_fresh_token_and_refuses_active_work() {
        let fixture = GitFixture::new();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            75,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let lock_path = fixture.0.join(".git/index.lock");
        fs::write(&lock_path, b"first").unwrap();
        let inspected = repository_session_inspect_index_lock(session.session_id, 75);
        assert!(inspected.present);
        assert_eq!(inspected.size_bytes, Some(5));
        fs::write(&lock_path, b"replaced-and-changed").unwrap();
        let changed =
            repository_session_remove_index_lock(session.session_id, 75, inspected.token.unwrap());
        assert_eq!(changed.failure, Some(NativeIndexLockFailureKind::Changed));
        assert!(lock_path.exists());

        let inspected = repository_session_inspect_index_lock(session.session_id, 75);
        let mutation = {
            let sessions = lock_sessions();
            sessions
                .active
                .get(&session.session_id)
                .unwrap()
                .repository
                .begin_mutation()
                .unwrap()
        };
        let active =
            repository_session_remove_index_lock(session.session_id, 75, inspected.token.unwrap());
        assert_eq!(
            active.failure,
            Some(NativeIndexLockFailureKind::ActiveOperation)
        );
        assert!(lock_path.exists());
        drop(mutation);

        let inspected = repository_session_inspect_index_lock(session.session_id, 75);
        let removed =
            repository_session_remove_index_lock(session.session_id, 75, inspected.token.unwrap());
        assert!(removed.removed);
        assert!(!lock_path.exists());
        assert!(repository_session_close(session.session_id, 75).accepted);
    }
}
