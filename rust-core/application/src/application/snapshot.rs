//! Projections of the shared repository snapshot (status, refs, identity) and its error kinds.
#![allow(clippy::wildcard_imports)]
use crate::dto::*;
use devmil_git::loading::refs::RefsSectionData;
use devmil_git::repository::{DiscoveryErrorKind, RepositoryKind};
use devmil_git::status::{
    BranchHead, ChangeKind, OperationKind, RepositoryStatus, StatusEntry, WorkingTreeState,
};
use devmil_git::types::HeadState;
use devmil_git::{RepositoryError, RepositoryErrorKind, RepositoryPhase, RepositorySnapshot};
use std::sync::Arc;

pub(crate) const REF_SIDEBAR_CAPACITY: usize = 512;

pub(crate) const STATUS_ENTRY_CAPACITY: usize = 10_000;

pub(crate) fn map_snapshot(snapshot: &Arc<RepositorySnapshot>) -> NativeRepositorySnapshot {
    NativeRepositorySnapshot {
        revision: snapshot.revision,
        phase: match snapshot.phase {
            RepositoryPhase::Unloaded => NativeRepositoryPhase::Unloaded,
            RepositoryPhase::Loading => NativeRepositoryPhase::Loading,
            RepositoryPhase::Ready => NativeRepositoryPhase::Ready,
            RepositoryPhase::Failed => NativeRepositoryPhase::Failed,
            RepositoryPhase::Closed => NativeRepositoryPhase::Closed,
        },
        failure: snapshot.error.as_ref().map(map_error),
        watch_failure: snapshot.watch_error.as_ref().map(map_error),
        identity: snapshot.repository.as_ref().map(map_identity),
        status: snapshot.status.as_deref().map(map_status),
        status_failure: snapshot
            .status_failure
            .map(|failure| NativeRepositoryFailure {
                kind: match failure {
                    devmil_git::loading::status::StatusFailure::MissingGit => {
                        NativeRepositoryFailureKind::MissingGit
                    }
                    devmil_git::loading::status::StatusFailure::UnsupportedGit => {
                        NativeRepositoryFailureKind::Unsupported
                    }
                    devmil_git::loading::status::StatusFailure::Canceled => {
                        NativeRepositoryFailureKind::Canceled
                    }
                    devmil_git::loading::status::StatusFailure::InvalidOutput => {
                        NativeRepositoryFailureKind::InvalidOutput
                    }
                    devmil_git::loading::status::StatusFailure::GitFailed => {
                        NativeRepositoryFailureKind::Read
                    }
                },
            }),
        refs_failure: snapshot
            .refs_failure
            .map(|failure| NativeRepositoryFailure {
                kind: match failure {
                    devmil_git::loading::refs::RefsFailureKind::MissingGit => {
                        NativeRepositoryFailureKind::MissingGit
                    }
                    devmil_git::loading::refs::RefsFailureKind::Canceled => {
                        NativeRepositoryFailureKind::Canceled
                    }
                    devmil_git::loading::refs::RefsFailureKind::InvalidOutput => {
                        NativeRepositoryFailureKind::InvalidOutput
                    }
                    devmil_git::loading::refs::RefsFailureKind::GitFailed => {
                        NativeRepositoryFailureKind::Read
                    }
                },
            }),
        ref_counts: map_ref_counts(&snapshot.refs),
        refs: map_repository_refs(&snapshot.refs),
    }
}

pub(crate) fn map_status(status: &RepositoryStatus) -> NativeRepositoryStatus {
    let (branch_name, head_object_id) = match &status.branch.head {
        BranchHead::Attached(name) => (
            Some(name.as_bytes().to_vec()),
            status
                .branch
                .oid
                .as_ref()
                .map(|oid| oid.as_str().to_owned()),
        ),
        BranchHead::Detached => (
            None,
            status
                .branch
                .oid
                .as_ref()
                .map(|oid| oid.as_str().to_owned()),
        ),
        BranchHead::Unborn { branch } => (Some(branch.as_bytes().to_vec()), None),
    };
    let total_entries = u64::try_from(status.entries.len()).unwrap_or(u64::MAX);
    NativeRepositoryStatus {
        working_tree: match status.working_tree {
            WorkingTreeState::Clean => NativeWorkingTreeState::Clean,
            WorkingTreeState::Dirty => NativeWorkingTreeState::Dirty,
            WorkingTreeState::Conflicted => NativeWorkingTreeState::Conflicted,
        },
        branch_name,
        head_object_id,
        upstream: status
            .branch
            .upstream
            .as_ref()
            .map(|upstream| upstream.as_bytes().to_vec()),
        ahead: status.branch.ahead,
        behind: status.branch.behind,
        entries: status
            .entries
            .iter()
            .take(STATUS_ENTRY_CAPACITY)
            .map(map_status_entry)
            .collect(),
        total_entries,
        entries_truncated: status.entries.len() > STATUS_ENTRY_CAPACITY,
        operations: status
            .operations
            .iter()
            .map(|operation| NativeOperationState {
                kind: match operation.kind {
                    OperationKind::Merge => NativeOperationKind::Merge,
                    OperationKind::Rebase => NativeOperationKind::Rebase,
                    OperationKind::CherryPick => NativeOperationKind::CherryPick,
                    OperationKind::Revert => NativeOperationKind::Revert,
                    OperationKind::Bisect => NativeOperationKind::Bisect,
                },
                current: operation.current,
                total: operation.total,
            })
            .collect(),
    }
}

pub(crate) fn map_status_entry(entry: &StatusEntry) -> NativeStatusEntry {
    let (kind, source, state) = match entry {
        StatusEntry::Ordinary(entry) => (NativeStatusEntryKind::Ordinary, None, entry.state),
        StatusEntry::Rename(entry) => (
            NativeStatusEntryKind::Rename,
            Some(crate::domain::path_identity::native_path_identity(
                entry.source.as_path(),
            )),
            entry.state,
        ),
        StatusEntry::Unmerged(entry) => (NativeStatusEntryKind::Unmerged, None, entry.state),
        StatusEntry::Untracked(_) => (
            NativeStatusEntryKind::Untracked,
            None,
            devmil_git::status::FileState {
                index: ChangeKind::Unmodified,
                worktree: ChangeKind::Added,
            },
        ),
        StatusEntry::Ignored(_) => (
            NativeStatusEntryKind::Ignored,
            None,
            devmil_git::status::FileState {
                index: ChangeKind::Unmodified,
                worktree: ChangeKind::Unmodified,
            },
        ),
    };
    NativeStatusEntry {
        kind,
        path: crate::domain::path_identity::native_path_identity(entry.path().as_path()),
        source,
        index: map_change_kind(state.index),
        worktree: map_change_kind(state.worktree),
    }
}

pub(crate) const fn map_change_kind(kind: ChangeKind) -> NativeChangeKind {
    match kind {
        ChangeKind::Unmodified => NativeChangeKind::Unmodified,
        ChangeKind::Modified => NativeChangeKind::Modified,
        ChangeKind::TypeChanged => NativeChangeKind::TypeChanged,
        ChangeKind::Added => NativeChangeKind::Added,
        ChangeKind::Deleted => NativeChangeKind::Deleted,
        ChangeKind::Renamed => NativeChangeKind::Renamed,
        ChangeKind::Copied => NativeChangeKind::Copied,
        ChangeKind::UpdatedButUnmerged => NativeChangeKind::UpdatedButUnmerged,
    }
}

pub(crate) fn map_ref_counts(refs: &[RefsSectionData]) -> NativeRepositoryRefCounts {
    let mut counts = NativeRepositoryRefCounts::default();
    for section in refs {
        match section {
            RefsSectionData::Branches { rows, .. } => counts.branches = rows.len() as u64,
            RefsSectionData::Remotes { remotes, .. } => counts.remotes = remotes.len() as u64,
            RefsSectionData::Tags(rows) => counts.tags = rows.len() as u64,
            RefsSectionData::Stashes(rows) => counts.stashes = rows.len() as u64,
            RefsSectionData::Worktrees(rows) => counts.worktrees = rows.len() as u64,
        }
    }
    counts
}

pub(crate) fn map_repository_refs(refs: &[RefsSectionData]) -> NativeRepositoryRefs {
    let mut result = NativeRepositoryRefs::default();
    let mut remaining = REF_SIDEBAR_CAPACITY;
    for section in refs {
        match section {
            RefsSectionData::Branches { rows, .. } => {
                let take = rows.len().min(remaining);
                for reference in rows.iter().take(take) {
                    result.branches.push(NativeRepositoryReference {
                        full_name: reference.id.as_bytes().to_vec(),
                        name: reference
                            .id
                            .as_bytes()
                            .strip_prefix(b"refs/heads/")
                            .unwrap_or(reference.id.as_bytes())
                            .to_vec(),
                        target: reference.target.as_str().to_owned(),
                        head: reference.is_head,
                        published: reference.upstream.is_some(),
                        upstream: reference
                            .upstream
                            .as_ref()
                            .map(|upstream| upstream.reference.as_bytes().to_vec()),
                        ahead: reference
                            .upstream
                            .as_ref()
                            .map_or(0, |upstream| upstream.ahead),
                        behind: reference
                            .upstream
                            .as_ref()
                            .map_or(0, |upstream| upstream.behind),
                        upstream_gone: reference
                            .upstream
                            .as_ref()
                            .is_some_and(|upstream| upstream.gone),
                    });
                }
                result.truncated |= rows.len() > take;
                remaining = remaining.saturating_sub(take);
            }
            RefsSectionData::Remotes {
                references,
                remotes,
            } => {
                let take = remotes.len().min(remaining);
                result
                    .remotes
                    .extend(remotes.iter().take(take).map(|remote| {
                        let mut prefix = b"refs/remotes/".to_vec();
                        prefix.extend_from_slice(remote.id.as_bytes());
                        prefix.push(b'/');
                        let branches = references
                            .iter()
                            .filter_map(|reference| {
                                let name =
                                    reference.id.as_bytes().strip_prefix(prefix.as_slice())?;
                                if name == b"HEAD" {
                                    return None;
                                }
                                Some(NativeRepositoryReference {
                                    name: name.to_vec(),
                                    full_name: reference.id.as_bytes().to_vec(),
                                    target: reference.target.as_str().to_owned(),
                                    head: false,
                                    published: true,
                                    upstream: None,
                                    ahead: 0,
                                    behind: 0,
                                    upstream_gone: false,
                                })
                            })
                            .collect();
                        NativeRepositoryRemote {
                            name: remote.id.as_bytes().to_vec(),
                            display_url: remote.display_url.clone(),
                            branches,
                        }
                    }));
                result.truncated |= remotes.len() > take;
                remaining = remaining.saturating_sub(take);
            }
            RefsSectionData::Tags(rows) => {
                let take = rows.len().min(remaining);
                result.tags.extend(rows.iter().take(take).map(|reference| {
                    NativeRepositoryReference {
                        full_name: reference.id.as_bytes().to_vec(),
                        name: reference
                            .id
                            .as_bytes()
                            .strip_prefix(b"refs/tags/")
                            .unwrap_or(reference.id.as_bytes())
                            .to_vec(),
                        target: reference
                            .peeled_target
                            .as_ref()
                            .unwrap_or(&reference.target)
                            .as_str()
                            .to_owned(),
                        head: false,
                        published: false,
                        upstream: None,
                        ahead: 0,
                        behind: 0,
                        upstream_gone: false,
                    }
                }));
                result.truncated |= rows.len() > take;
                remaining = remaining.saturating_sub(take);
            }
            RefsSectionData::Stashes(rows) => {
                let take = rows.len().min(remaining);
                result
                    .stashes
                    .extend(rows.iter().take(take).map(|entry| NativeRepositoryStash {
                        selector: entry.selector.clone(),
                        object_id: entry.id.0.as_str().to_owned(),
                        subject: entry.subject.clone(),
                    }));
                result.truncated |= rows.len() > take;
                remaining = remaining.saturating_sub(take);
            }
            RefsSectionData::Worktrees(_) => {}
        }
    }
    result
}

pub(crate) fn map_identity(
    repository: &devmil_git::repository::DiscoveredRepository,
) -> NativeRepositoryIdentity {
    let (head_kind, head_reference, head_object_id) = match &repository.head {
        HeadState::Attached { branch, target } => (
            NativeHeadKind::Attached,
            Some(branch.as_bytes().to_vec()),
            Some(target.as_str().to_owned()),
        ),
        HeadState::Detached { target } => (
            NativeHeadKind::Detached,
            None,
            Some(target.as_str().to_owned()),
        ),
        HeadState::Unborn { branch } => (
            NativeHeadKind::Unborn,
            Some(branch.as_bytes().to_vec()),
            None,
        ),
    };
    NativeRepositoryIdentity {
        common_git_dir: crate::domain::path_identity::native_path_identity(
            repository.worktree.repository().common_git_dir().as_path(),
        ),
        worktree_root: crate::domain::path_identity::native_path_identity(
            repository.worktree.worktree_root().as_path(),
        ),
        git_dir: crate::domain::path_identity::native_path_identity(
            repository.worktree.git_dir().as_path(),
        ),
        kind: match repository.kind {
            RepositoryKind::Worktree => NativeRepositoryKind::Worktree,
            RepositoryKind::Bare => NativeRepositoryKind::Bare,
        },
        head_kind,
        head_reference,
        head_object_id,
        git_major: repository.git_version.major,
        git_minor: repository.git_version.minor,
        git_patch: repository.git_version.patch,
    }
}

pub(crate) fn map_error(error: &RepositoryError) -> NativeRepositoryFailure {
    NativeRepositoryFailure {
        kind: map_error_kind(error.kind),
    }
}

pub(crate) const fn map_error_kind(kind: RepositoryErrorKind) -> NativeRepositoryFailureKind {
    match kind {
        RepositoryErrorKind::Canceled => NativeRepositoryFailureKind::Canceled,
        RepositoryErrorKind::MissingObject => NativeRepositoryFailureKind::MissingObject,
        RepositoryErrorKind::TooLarge => NativeRepositoryFailureKind::TooLarge,
        RepositoryErrorKind::InvalidOutput => NativeRepositoryFailureKind::InvalidOutput,
        RepositoryErrorKind::MissingGit => NativeRepositoryFailureKind::MissingGit,
        RepositoryErrorKind::Unsupported => NativeRepositoryFailureKind::Unsupported,
        RepositoryErrorKind::InvalidOptions => NativeRepositoryFailureKind::InvalidOptions,
        RepositoryErrorKind::Discovery => NativeRepositoryFailureKind::Discovery,
        RepositoryErrorKind::Read => NativeRepositoryFailureKind::Read,
        RepositoryErrorKind::Watch => NativeRepositoryFailureKind::Watch,
        RepositoryErrorKind::Closed => NativeRepositoryFailureKind::Closed,
        RepositoryErrorKind::Capacity => NativeRepositoryFailureKind::Capacity,
        RepositoryErrorKind::TimedOut => NativeRepositoryFailureKind::TimedOut,
    }
}

pub(crate) const fn map_discovery_error_kind(
    kind: DiscoveryErrorKind,
) -> NativeRepositoryFailureKind {
    match kind {
        DiscoveryErrorKind::NotFound => NativeRepositoryFailureKind::PathNotFound,
        DiscoveryErrorKind::AccessDenied => NativeRepositoryFailureKind::PermissionDenied,
        DiscoveryErrorKind::NotRepository | DiscoveryErrorKind::ParentDiscoveryDisabled => {
            NativeRepositoryFailureKind::NotRepository
        }
        DiscoveryErrorKind::GitMissing => NativeRepositoryFailureKind::MissingGit,
        DiscoveryErrorKind::InvalidGitOutput => NativeRepositoryFailureKind::InvalidOutput,
        DiscoveryErrorKind::Canceled => NativeRepositoryFailureKind::Canceled,
        DiscoveryErrorKind::GitFailed => NativeRepositoryFailureKind::Discovery,
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{session::*, snapshot::*};

    use devmil_git::RepositoryOptions;

    use std::fs;

    use std::process::Command;

    use std::time::Duration;
    use std::time::Instant;

    #[test]
    fn coherent_snapshot_projects_bounded_status_and_ref_counts() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("tracked.txt"), b"initial\n").unwrap();
        let added = Command::new("git")
            .args(["add", "--", "tracked.txt"])
            .current_dir(&fixture.0)
            .output()
            .unwrap();
        assert!(added.status.success());
        let committed = Command::new("git")
            .args(["commit", "-q", "-m", "initial"])
            .current_dir(&fixture.0)
            .env("GIT_AUTHOR_NAME", "Fixture")
            .env("GIT_AUTHOR_EMAIL", "fixture@example.invalid")
            .env("GIT_COMMITTER_NAME", "Fixture")
            .env("GIT_COMMITTER_EMAIL", "fixture@example.invalid")
            .output()
            .unwrap();
        assert!(committed.status.success());
        for arguments in [["branch", "topic"], ["tag", "v1"]] {
            assert!(Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .output()
                .unwrap()
                .status
                .success());
        }
        assert!(Command::new("git")
            .args([
                "remote",
                "add",
                "origin",
                "https://user:fixture-secret@example.invalid/repo.git",
            ])
            .current_dir(&fixture.0)
            .output()
            .unwrap()
            .status
            .success());
        assert!(Command::new("git")
            .args(["update-ref", "refs/remotes/origin/main", "HEAD"])
            .current_dir(&fixture.0)
            .output()
            .unwrap()
            .status
            .success());
        assert!(Command::new("git")
            .args(["branch", "--set-upstream-to=origin/main", "main"])
            .current_dir(&fixture.0)
            .output()
            .unwrap()
            .status
            .success());
        fs::write(fixture.0.join("tracked.txt"), b"changed\n").unwrap();
        fs::write(fixture.0.join("untracked.txt"), b"new\n").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            71,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let snapshot = wait_for_ready(&session);
        let status = snapshot.status.unwrap();
        assert_eq!(status.working_tree, NativeWorkingTreeState::Dirty);
        assert_eq!(status.branch_name.as_deref(), Some(b"main".as_slice()));
        assert_eq!(status.total_entries, 2);
        assert_eq!(status.entries.len(), 2);
        assert!(!status.entries_truncated);
        assert_eq!(snapshot.ref_counts.branches, 2);
        assert_eq!(snapshot.ref_counts.remotes, 1);
        assert_eq!(snapshot.ref_counts.tags, 1);
        assert_eq!(snapshot.ref_counts.worktrees, 1);
        assert_eq!(snapshot.refs.branches.len(), 2);
        assert!(snapshot
            .refs
            .branches
            .iter()
            .any(|branch| branch.name == b"main" && branch.head));
        assert_eq!(
            snapshot
                .refs
                .branches
                .iter()
                .find(|branch| branch.name == b"main")
                .unwrap()
                .upstream
                .as_deref(),
            Some(b"refs/remotes/origin/main".as_slice())
        );
        assert!(snapshot
            .refs
            .branches
            .iter()
            .any(|branch| branch.name == b"topic" && !branch.head));
        assert_eq!(snapshot.refs.tags[0].name, b"v1");
        assert_eq!(snapshot.refs.remotes[0].name, b"origin");
        assert_eq!(snapshot.refs.remotes[0].branches.len(), 1);
        assert_eq!(snapshot.refs.remotes[0].branches[0].name, b"main");
        assert!(!snapshot.refs.remotes[0]
            .display_url
            .windows(b"fixture-secret".len())
            .any(|window| window == b"fixture-secret"));
        assert!(!snapshot.refs.truncated);

        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "ahead"]);
        transfer_git(
            &fixture.0,
            &["update-ref", "refs/remotes/origin/topic", "HEAD"],
        );
        transfer_git(
            &fixture.0,
            &["branch", "--set-upstream-to=origin/topic", "topic"],
        );
        assert!(repository_session_refresh(session.session_id, 71).accepted);
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            let refreshed = map_snapshot(
                &repository_for_session(session.session_id, 71)
                    .unwrap()
                    .snapshot(),
            );
            let main = refreshed
                .refs
                .branches
                .iter()
                .find(|branch| branch.name == b"main");
            let topic = refreshed
                .refs
                .branches
                .iter()
                .find(|branch| branch.name == b"topic");
            if main.is_some_and(|branch| branch.ahead == 1)
                && topic.is_some_and(|branch| branch.behind == 1)
            {
                assert_eq!(main.unwrap().behind, 0);
                assert_eq!(topic.unwrap().ahead, 0);
                break;
            }
            assert!(
                Instant::now() < deadline,
                "branch tracking counts did not refresh"
            );
            std::thread::sleep(Duration::from_millis(25));
        }
        assert!(repository_session_close(session.session_id, 71).accepted);
    }
}
