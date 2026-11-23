//! Git's lock files (the Dart IndexLockWorkflow and the transfer failure
//! dialog's RepositoryLockControls): Inspect index lock removes a left
//! behind `index.lock` after a confirmation, and a transfer that failed on a
//! lock lists every lock file of its repository, with their ages, and
//! removes them before a retry.

use crate::backend::SessionCalls;
use crate::notices::Notices;
use crate::prompts::Prompts;
use crate::session::{BackendKind, SessionIdentity};
use crate::workspace::WorkspaceService;
use gitlama_contract::dto::{NativeIndexLockFailureKind, NativeRepositoryLockInspectionResult};
use serde_json::{Value, json};
use std::rc::Rc;

/// A lock younger than this is probably held by a Git program still running.
pub const RECENT_AGE_SECONDS: u64 = 60;
/// Locks at least this old were probably left behind by a stopped process.
pub const STALE_AGE_SECONDS: u64 = 5 * 60;

/// The advice under an inspection's list (the Dart repositoryLockAdvice):
/// "none", "recent", "stale", or nothing to say.
pub fn advice(inspection: &NativeRepositoryLockInspectionResult) -> Option<&'static str> {
    if inspection.locks.is_empty() {
        return (!inspection.truncated).then_some("none");
    }
    if inspection
        .locks
        .iter()
        .any(|lock| lock.age_seconds.unwrap_or(0) < RECENT_AGE_SECONDS)
    {
        return Some("recent");
    }
    if inspection
        .locks
        .iter()
        .any(|lock| lock.age_seconds.is_some_and(|age| age >= STALE_AGE_SECONDS))
    {
        return Some("stale");
    }
    None
}

/// The localized message of a refused removal (the Dart
/// repositoryLockRemovalMessage).
pub fn removal_failure_key(kind: NativeIndexLockFailureKind) -> &'static str {
    match kind {
        NativeIndexLockFailureKind::Changed => "repositoryLockChanged",
        NativeIndexLockFailureKind::ActiveOperation => "repositoryLockBusy",
        _ => "repositoryLockRemoveFailed",
    }
}

pub struct RepositoryLocks {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
}

impl RepositoryLocks {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            prompts,
            notices,
        })
    }

    fn active(&self) -> Option<SessionIdentity> {
        self.workspace.current().map(|session| session.identity)
    }

    /// Inspect index lock: removes a left behind `index.lock` once the person
    /// confirms, and says what happened.
    pub async fn inspect_index_lock(&self) {
        let Some(session) = self.active() else {
            return;
        };
        let inspection = self
            .calls
            .repository_session_inspect_index_lock(session.native_id, session.generation)
            .await;
        let inspection = match inspection {
            Ok(result) => result,
            Err(_) => return self.notices.error("indexLockUnavailable", Value::Null),
        };
        if let Some(kind) = inspection.failure {
            return self.refused(kind);
        }
        if !inspection.present {
            return self.notices.status("indexLockNotFound", Value::Null);
        }
        let Some(token) = inspection.token else {
            return;
        };
        let answer = self
            .prompts
            .ask(
                "confirmIndexLock",
                json!({"sizeBytes": inspection.size_bytes.unwrap_or(0)}),
            )
            .await;
        if answer != Some(Value::Bool(true)) {
            return;
        }
        match self
            .calls
            .repository_session_remove_index_lock(session.native_id, session.generation, token)
            .await
        {
            Ok(result) => match result.failure {
                Some(kind) => self.refused(kind),
                None => self.notices.status("indexLockRemoved", Value::Null),
            },
            Err(_) => self.notices.error("indexLockUnavailable", Value::Null),
        }
    }

    fn refused(&self, kind: NativeIndexLockFailureKind) {
        let key = match kind {
            NativeIndexLockFailureKind::Missing => {
                return self.notices.status("indexLockNotFound", Value::Null);
            }
            NativeIndexLockFailureKind::Changed => "indexLockChanged",
            NativeIndexLockFailureKind::ActiveOperation => "indexLockActiveOperation",
            _ => "indexLockUnavailable",
        };
        self.notices.error(key, Value::Null);
    }

    /// Every lock file of the active repository, for the transfer failure
    /// dialog: {canRemove, truncated, advice, locks: [{token, path, age}]},
    /// or null when they could not be read.
    pub async fn inspect(&self) -> Value {
        let Some(session) = self.active() else {
            return Value::Null;
        };
        let result = self
            .calls
            .repository_session_inspect_locks(session.native_id, session.generation)
            .await;
        let Ok(inspection) = result else {
            return Value::Null;
        };
        if inspection.failure.is_some() {
            return Value::Null;
        }
        json!({
            // Locks of a repository on another computer are only listed.
            "canRemove": session.backend == BackendKind::Local,
            "truncated": inspection.truncated,
            "advice": advice(&inspection),
            "locks": inspection.locks.iter().map(|lock| json!({
                // Tokens exceed what a QML number keeps exactly.
                "token": lock.token.to_string(),
                "path": lock.path,
                "ageSeconds": lock.age_seconds,
            })).collect::<Vec<_>>(),
        })
    }

    /// Removes these locks of the last inspection, stopping at the first that
    /// changed; one already gone counts as handled. Answers how many were
    /// removed, or the localized reason it stopped.
    pub async fn remove(&self, tokens: Vec<u64>) -> Result<usize, &'static str> {
        let Some(session) = self.active() else {
            return Err("repositoryLockRemoveFailed");
        };
        let mut removed = 0;
        for token in tokens {
            let result = self
                .calls
                .repository_session_remove_lock(session.native_id, session.generation, token)
                .await
                .map_err(|_| "repositoryLockRemoveFailed")?;
            match result.failure {
                None if result.removed => removed += 1,
                None | Some(NativeIndexLockFailureKind::Missing) => {}
                Some(kind) => return Err(removal_failure_key(kind)),
            }
        }
        Ok(removed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_contract::dto::NativeRepositoryLock;

    fn inspection(ages: &[Option<u64>], truncated: bool) -> NativeRepositoryLockInspectionResult {
        NativeRepositoryLockInspectionResult {
            locks: ages
                .iter()
                .enumerate()
                .map(|(index, age)| NativeRepositoryLock {
                    token: index as u64,
                    path: format!("lock{index}.lock"),
                    worktree_scoped: false,
                    size_bytes: 0,
                    age_seconds: *age,
                })
                .collect(),
            truncated,
            failure: None,
        }
    }

    #[test]
    fn advice_follows_the_lock_ages() {
        assert_eq!(advice(&inspection(&[], false)), Some("none"));
        assert_eq!(advice(&inspection(&[], true)), None);
        assert_eq!(
            advice(&inspection(&[Some(10), Some(900)], false)),
            Some("recent")
        );
        assert_eq!(advice(&inspection(&[None], false)), Some("recent"));
        assert_eq!(advice(&inspection(&[Some(300)], false)), Some("stale"));
        assert_eq!(advice(&inspection(&[Some(120)], false)), None);
    }

    #[test]
    fn refused_removals_say_why() {
        assert_eq!(
            removal_failure_key(NativeIndexLockFailureKind::Changed),
            "repositoryLockChanged"
        );
        assert_eq!(
            removal_failure_key(NativeIndexLockFailureKind::ActiveOperation),
            "repositoryLockBusy"
        );
        assert_eq!(
            removal_failure_key(NativeIndexLockFailureKind::Io),
            "repositoryLockRemoveFailed"
        );
    }
}
