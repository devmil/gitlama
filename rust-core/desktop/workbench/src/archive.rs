//! Zip snapshots of commits: the core builds the archive while its progress is
//! polled, then it is written page by page to the chosen file on this
//! computer. Cancel stops between steps; the outcome is a status message.

use crate::backend::SessionCalls;
use crate::notices::Notices;
use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::workspace::WorkspaceService;
use gitlama_contract::archive::{
    NativeArchiveFailureKind, NativeArchiveState, NativeArchiveStatus,
};
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Duration;

const POLL: Duration = Duration::from_millis(100);

/// The snapshot's file and top folder name: the repository's name and the
/// commit's short hash, with characters file systems reject replaced.
pub fn archive_name(repository: &str, commit: &str) -> String {
    let replaced: String = repository
        .chars()
        .map(|ch| {
            if matches!(ch, '\\' | '/' | ':' | '*' | '?' | '"' | '<' | '>' | '|') || ch.is_control()
            {
                '-'
            } else {
                ch
            }
        })
        .collect();
    let spaced = replaced.split_whitespace().collect::<Vec<_>>().join("-");
    let trimmed = spaced.trim_matches(|ch| ch == '.' || ch == '-');
    let name = if trimmed.is_empty() {
        "snapshot"
    } else {
        trimmed
    };
    let short: String = commit.chars().take(7).collect();
    format!("{name}-{short}")
}

pub fn failure_key(kind: NativeArchiveFailureKind) -> &'static str {
    match kind {
        NativeArchiveFailureKind::Stale => "archiveFailureStale",
        NativeArchiveFailureKind::MissingCommit => "archiveFailureMissingCommit",
        NativeArchiveFailureKind::TooLarge => "archiveFailureTooLarge",
        NativeArchiveFailureKind::Busy => "archiveFailureBusy",
        NativeArchiveFailureKind::Write => "archiveFailureWrite",
        _ => "archiveFailureGit",
    }
}

/// The progress the dialog shows: {files, total, writing}.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Progress {
    pub running: bool,
    pub started: bool,
    pub files: u64,
    pub total: u64,
    pub writing: bool,
}

enum Outcome {
    Saved(NativeArchiveStatus),
    Failed(NativeArchiveFailureKind),
    Canceled,
}

pub struct ArchiveService {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    notices: Rc<Notices>,
    notifier: Notifier,
    progress: RefCell<Progress>,
    canceled: Cell<bool>,
}

impl ArchiveService {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        notices: Rc<Notices>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            notices,
            notifier,
            progress: RefCell::new(Progress::default()),
            canceled: Cell::new(false),
        })
    }

    pub fn progress(&self) -> Progress {
        self.progress.borrow().clone()
    }

    fn set(&self, progress: Progress) {
        if *self.progress.borrow() != progress {
            *self.progress.borrow_mut() = progress;
            self.notifier.notify(Topics::OPERATIONS);
        }
    }

    pub fn cancel(&self) {
        self.canceled.set(true);
    }

    /// Saves the snapshot of `commit` to `destination`, every file under
    /// the folder `prefix`.
    pub async fn save(&self, commit: String, prefix: String, destination: String) {
        if self.progress.borrow().running {
            return;
        }
        let Some(identity) = self.workspace.current().map(|session| session.identity) else {
            return;
        };
        self.canceled.set(false);
        self.set(Progress {
            running: true,
            ..Progress::default()
        });
        let outcome = self
            .run(
                identity.native_id,
                identity.generation,
                commit,
                prefix,
                destination.clone(),
            )
            .await;
        self.set(Progress::default());
        match outcome {
            Outcome::Saved(status) => {
                let file = destination
                    .rsplit(['/', '\\'])
                    .next()
                    .unwrap_or_default()
                    .to_owned();
                let mut parts = vec![json!({"l10n": "archiveSaved", "args": {"name": file}})];
                if status.missing_submodule_count > 0 {
                    parts.push(json!({"l10n": "archiveMissingSubmodules", "args": {"count": status.missing_submodule_count}}));
                }
                if status.unresolved_lfs_count > 0 {
                    parts.push(json!({"l10n": "archiveUnresolvedLfs", "args": {"count": status.unresolved_lfs_count}}));
                }
                self.notices.status("@join", json!({"parts": parts}));
            }
            Outcome::Failed(kind) => self.notices.error(failure_key(kind), Value::Null),
            Outcome::Canceled => {}
        }
    }

    async fn run(
        &self,
        session: u64,
        generation: u64,
        commit: String,
        prefix: String,
        destination: String,
    ) -> Outcome {
        let started = match self
            .calls
            .repository_session_archive_start(session, generation, commit, prefix)
            .await
        {
            Ok(started) => started,
            Err(_) => return Outcome::Failed(NativeArchiveFailureKind::Stale),
        };
        if let Some(failure) = started.failure {
            return Outcome::Failed(failure.kind);
        }
        let Some(token) = started.token else {
            return Outcome::Failed(NativeArchiveFailureKind::Git);
        };
        let mut sink: Option<u64> = None;
        let outcome = self
            .write(session, generation, token, &destination, &mut sink)
            .await;
        if let Some(file) = sink {
            rt::blocking(move || gitlama_core::api::archive_file_abort(file)).await;
        }
        // The host deletes the snapshot when the session closes anyway.
        let _ = self
            .calls
            .repository_session_archive_release(session, generation, token)
            .await;
        outcome
    }

    async fn write(
        &self,
        session: u64,
        generation: u64,
        token: u64,
        destination: &str,
        sink: &mut Option<u64>,
    ) -> Outcome {
        let status = loop {
            if self.canceled.get() {
                return Outcome::Canceled;
            }
            let Ok(status) = self
                .calls
                .repository_session_archive_status(session, generation, token)
                .await
            else {
                return Outcome::Failed(NativeArchiveFailureKind::Stale);
            };
            let running = status.state == NativeArchiveState::Running;
            self.set(Progress {
                running: true,
                started: true,
                files: status.files,
                total: status.total_files,
                writing: !running,
            });
            if !running {
                break status;
            }
            rt::sleep(POLL).await;
        };
        if status.state != NativeArchiveState::Completed {
            return Outcome::Failed(
                status
                    .failure
                    .as_ref()
                    .map_or(NativeArchiveFailureKind::Git, |failure| failure.kind),
            );
        }
        let path = destination.to_owned();
        let Some(file) = rt::blocking(move || gitlama_core::api::archive_file_begin(path)).await
        else {
            return Outcome::Failed(NativeArchiveFailureKind::Write);
        };
        *sink = Some(file);
        let mut offset = 0u64;
        loop {
            if self.canceled.get() {
                return Outcome::Canceled;
            }
            let Ok(page) = self
                .calls
                .repository_session_archive_page(session, generation, token, offset)
                .await
            else {
                return Outcome::Failed(NativeArchiveFailureKind::Stale);
            };
            if let Some(failure) = page.failure {
                return Outcome::Failed(failure.kind);
            }
            if page.bytes.is_empty() {
                break;
            }
            let length = page.bytes.len() as u64;
            let bytes = page.bytes;
            if !rt::blocking(move || gitlama_core::api::archive_file_append(file, bytes)).await {
                *sink = None;
                return Outcome::Failed(NativeArchiveFailureKind::Write);
            }
            offset += length;
        }
        if offset != status.archive_bytes {
            return Outcome::Failed(NativeArchiveFailureKind::Write);
        }
        *sink = None;
        if !rt::blocking(move || gitlama_core::api::archive_file_commit(file)).await {
            return Outcome::Failed(NativeArchiveFailureKind::Write);
        }
        Outcome::Saved(status)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_names_are_safe_file_names() {
        assert_eq!(
            archive_name("gitlama", "0123456789abcdef"),
            "gitlama-0123456"
        );
        assert_eq!(
            archive_name("my repo: v2/next", "abc"),
            "my-repo--v2-next-abc"
        );
        assert_eq!(archive_name("..", "abcdef12"), "snapshot-abcdef1");
        assert_eq!(archive_name("  -name.  ", "abcdef12"), "name-abcdef1");
    }
}
