//! Fixtures the session-level tests share: temporary repositories, transfers and waits.
#![allow(clippy::wildcard_imports, dead_code)]
use crate::activity::ActivityStore;
use crate::application::{session::*, snapshot::*};
use crate::dto::*;

use crate::history_operation::{
    NativeHistoryMergeMode, NativeHistoryMutationKind, NativeHistoryMutationRequest,
};

use crate::domain::path_identity::NativePathIdentity;

use devmil_git::RepositoryOptions;
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::AtomicU64;
use std::sync::atomic::Ordering;
use std::time::Duration;
use std::time::Instant;

pub(crate) static NEXT_FIXTURE: AtomicU64 = AtomicU64::new(1);

pub(crate) fn fixture_path(prefix: &str) -> PathBuf {
    let sequence = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
    let mut entropy = [0_u8; 16];
    getrandom::fill(&mut entropy).expect("fixture path entropy is available");
    let nonce = entropy
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    std::env::temp_dir().join(format!(
        "gitlama-{prefix}-{}-{sequence}-{nonce}",
        std::process::id()
    ))
}

pub(crate) fn configure_test_repository(path: &Path) {
    for (key, value) in [
        ("user.name", "GitLama Test"),
        ("user.email", "gitlama@example.invalid"),
        ("core.autocrlf", "false"),
        ("core.eol", "lf"),
    ] {
        transfer_git(path, &["config", key, value]);
    }
}

pub(crate) struct GitFixture(pub(crate) PathBuf);

impl GitFixture {
    pub(crate) fn new() -> Self {
        let path = fixture_path("session");
        fs::create_dir(&path).unwrap();
        let output = Command::new("git")
            .args(["init", "-q", "-b", "main"])
            .current_dir(&path)
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_CONFIG_GLOBAL", path.join("empty-config"))
            .output()
            .unwrap();
        assert!(output.status.success());
        configure_test_repository(&path);
        Self(path)
    }
}

impl Drop for GitFixture {
    fn drop(&mut self) {
        // A failed assertion can leave a repository worker holding a Windows
        // file handle. Cleanup must not panic while another panic is already
        // unwinding, or the test harness loses the original failure.
        let _ = fs::remove_dir_all(&self.0);
    }
}

pub(crate) struct TransferFixture {
    pub(crate) root: PathBuf,
    pub(crate) remote: PathBuf,
    pub(crate) client: PathBuf,
    pub(crate) peer: PathBuf,
}

impl TransferFixture {
    pub(crate) fn new() -> Self {
        let root = fixture_path("transfer");
        fs::create_dir(&root).unwrap();
        let remote = root.join("remote.git");
        let seed = root.join("seed");
        let client = root.join("client");
        let peer = root.join("peer");
        transfer_git(&root, &["init", "-q", "--bare", remote.to_str().unwrap()]);
        fs::create_dir(&seed).unwrap();
        transfer_git(&seed, &["init", "-q", "-b", "main"]);
        fs::write(seed.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&seed, &["add", "tracked.txt"]);
        transfer_git(&seed, &["commit", "-qm", "base"]);
        transfer_git(
            &seed,
            &["remote", "add", "origin", remote.to_str().unwrap()],
        );
        transfer_git(&seed, &["push", "-q", "-u", "origin", "main"]);
        transfer_git(&remote, &["symbolic-ref", "HEAD", "refs/heads/main"]);
        transfer_git(
            &root,
            &[
                "-c",
                "core.autocrlf=false",
                "clone",
                "-q",
                remote.to_str().unwrap(),
                client.to_str().unwrap(),
            ],
        );
        transfer_git(
            &root,
            &[
                "-c",
                "core.autocrlf=false",
                "clone",
                "-q",
                remote.to_str().unwrap(),
                peer.to_str().unwrap(),
            ],
        );
        for repository in [&client, &peer] {
            configure_test_repository(repository);
        }
        Self {
            root,
            remote,
            client,
            peer,
        }
    }

    pub(crate) fn commit(&self, directory: &Path, content: &[u8], message: &str) {
        fs::write(directory.join("tracked.txt"), content).unwrap();
        transfer_git(directory, &["add", "tracked.txt"]);
        transfer_git(directory, &["commit", "-qm", message]);
    }
}

impl Drop for TransferFixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

pub(crate) fn transfer_git(directory: &Path, arguments: &[&str]) -> Vec<u8> {
    let output = Command::new("git")
        .args(arguments)
        .current_dir(directory)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_AUTHOR_NAME", "GitLama Test")
        .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
        .env("GIT_COMMITTER_NAME", "GitLama Test")
        .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
        .env("GIT_TERMINAL_PROMPT", "0")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {arguments:?} failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    output.stdout
}

pub(crate) fn transfer_git_expect_failure(directory: &Path, arguments: &[&str]) {
    let output = Command::new("git")
        .args(arguments)
        .current_dir(directory)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_AUTHOR_NAME", "GitLama Test")
        .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
        .env("GIT_COMMITTER_NAME", "GitLama Test")
        .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
        .env("GIT_TERMINAL_PROMPT", "0")
        .output()
        .unwrap();
    assert!(
        !output.status.success(),
        "git {arguments:?} unexpectedly succeeded"
    );
}

pub(crate) fn patch_request(directory: &Path) -> NativePatchExportRequest {
    NativePatchExportRequest {
        working_diff_request_id: None,
        row_ids: vec![],
        selected_side: None,
        selected_paths: vec![],
        focused_side: None,
        comparison_old: None,
        comparison_new: None,
        range_commits: vec![],
        commit: None,
        history_paths: vec![],
        workspace_default: false,
        destination_directory: directory.to_string_lossy().into_owned(),
        overwrite: false,
    }
}

/// Every edge of a published window must end at a row the filter keeps.
pub(crate) fn assert_filtered_edges_closed(page: &NativeHistoryPage, all: &NativeHistoryPage) {
    let visible = all
        .rows
        .iter()
        .map(|row| row.object_id.as_str())
        .collect::<HashSet<_>>();
    for segment in &page.segments {
        assert!(visible.contains(segment.from_object_id.as_str()));
        assert!(
            visible.contains(segment.to_object_id.as_str()),
            "a filtered edge leaves the visible history"
        );
    }
}

pub(crate) fn fast_import_linear(path: &std::path::Path, count: usize) {
    use std::io::Write as _;
    let mut child = Command::new("git")
        .args(["fast-import", "--quiet"])
        .current_dir(path)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    {
        let input = child.stdin.as_mut().unwrap();
        for index in 0..count {
            writeln!(input, "commit refs/heads/main").unwrap();
            writeln!(input, "mark :{}", index + 1).unwrap();
            writeln!(
                input,
                "author Fixture <fixture@example.invalid> {} +0000",
                index + 1
            )
            .unwrap();
            writeln!(
                input,
                "committer Fixture <fixture@example.invalid> {} +0000",
                index + 1
            )
            .unwrap();
            let message = if count >= 100_000 && index + 1 == count {
                "x".repeat(devmil_git::loading::graph::MAX_METADATA_OBJECT_BYTES + 1)
            } else {
                format!("commit {index}")
            };
            writeln!(input, "data {}", message.len()).unwrap();
            writeln!(input, "{message}").unwrap();
            if index > 0 {
                writeln!(input, "from :{index}").unwrap();
            }
            writeln!(input).unwrap();
        }
        writeln!(input, "done").unwrap();
    }
    let output = child.wait_with_output().unwrap();
    assert!(
        output.status.success(),
        "fast-import failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

/// Puts the tracked files of `worktree` back to their index state, as a test's next case expects.
pub(crate) fn restore_tracked_files(worktree: &std::path::Path) {
    let output = std::process::Command::new("git")
        .args(["checkout", "--", "."])
        .current_dir(worktree)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", worktree.join("empty-config"))
        .output()
        .unwrap();
    assert!(output.status.success());
}

pub(crate) fn revert_test_session(
    fixture: &GitFixture,
    generation: u64,
) -> NativeRepositorySession {
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
    session
}

pub(crate) fn revert_test_request(target: String, no_commit: bool) -> NativeHistoryMutationRequest {
    NativeHistoryMutationRequest {
        kind: NativeHistoryMutationKind::Revert,
        targets: vec![target],
        source_name: None,
        merge_mode: NativeHistoryMergeMode::FastForwardIfPossible,
        acknowledge_published_history: false,
        no_commit,
    }
}

pub(crate) fn revert_test_fixture(conflict: bool) -> (GitFixture, String, String) {
    let fixture = GitFixture::new();
    fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
    transfer_git(&fixture.0, &["add", "."]);
    transfer_git(&fixture.0, &["commit", "-qm", "base"]);
    fs::write(fixture.0.join("tracked.txt"), b"target\n").unwrap();
    transfer_git(&fixture.0, &["commit", "-qam", "target"]);
    let target = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
        .unwrap()
        .trim()
        .to_owned();
    if conflict {
        fs::write(fixture.0.join("tracked.txt"), b"later\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "later"]);
    }
    let head = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
        .unwrap()
        .trim()
        .to_owned();
    (fixture, target, head)
}

pub(crate) fn refresh_session(session: &NativeRepositorySession) -> NativeRepositorySnapshot {
    let previous = repository_for_session(session.session_id, session.generation)
        .unwrap()
        .snapshot()
        .revision;
    assert!(repository_session_refresh(session.session_id, session.generation).accepted);
    wait_for_new_revision(session, previous)
}

pub(crate) fn refresh_session_at_head(
    session: &NativeRepositorySession,
    expected_head: &str,
) -> NativeRepositorySnapshot {
    refresh_session_until(session, |snapshot| {
        snapshot.status.as_ref().is_some_and(|status| {
            status.head_object_id.as_deref() == Some(expected_head) && status.entries.is_empty()
        })
    })
}

/// Refreshes until a snapshot satisfies [`test`]. A refresh already running when the test
/// changed the repository can publish first, from state read before that change.
pub(crate) fn refresh_session_until(
    session: &NativeRepositorySession,
    test: impl Fn(&NativeRepositorySnapshot) -> bool,
) -> NativeRepositorySnapshot {
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        let snapshot = refresh_session(session);
        if test(&snapshot) {
            return snapshot;
        }
    }
    panic!("repository refresh did not converge to the expected state")
}

pub(crate) fn refresh_session_at_client_head(
    session: &NativeRepositorySession,
    directory: &Path,
) -> NativeRepositorySnapshot {
    let head = String::from_utf8(transfer_git(directory, &["rev-parse", "HEAD"])).unwrap();
    refresh_session_until(session, |snapshot| {
        snapshot
            .status
            .as_ref()
            .and_then(|status| status.head_object_id.as_deref())
            == Some(head.trim())
    })
}

pub(crate) fn wait_for_new_revision(
    session: &NativeRepositorySession,
    previous: u64,
) -> NativeRepositorySnapshot {
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        let result = repository_session_events(session.session_id, session.generation, 32);
        assert!(result.failure.is_none());
        for event in result.events {
            if let Some(snapshot) = event.snapshot {
                if snapshot.phase == NativeRepositoryPhase::Ready && snapshot.revision > previous {
                    return snapshot;
                }
            }
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    panic!("repository did not publish a newer ready revision")
}

pub(crate) fn remote_identity_of(local: &NativePathIdentity) -> NativePathIdentity {
    NativePathIdentity {
        remote: Some(crate::domain::path_identity::NativeRemoteAuthority {
            profile_id: "123e4567-e89b-42d3-a456-426614174000".into(),
            store_id: "0123456789abcdef0123456789abcdef".into(),
            account_uid: "1000".into(),
        }),
        ..local.clone()
    }
}

pub(crate) fn wait_for_ready(session: &NativeRepositorySession) -> NativeRepositorySnapshot {
    wait_for_phase(session, NativeRepositoryPhase::Ready)
}

pub(crate) fn wait_for_phase(
    session: &NativeRepositorySession,
    phase: NativeRepositoryPhase,
) -> NativeRepositorySnapshot {
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        let result = repository_session_events(session.session_id, session.generation, 32);
        assert!(result.failure.is_none());
        for event in result.events {
            if let Some(snapshot) = event.snapshot {
                if snapshot.phase == phase {
                    return snapshot;
                }
            }
        }
        if let Ok(repository) = repository_for_session(session.session_id, session.generation) {
            let snapshot = map_snapshot(&repository.snapshot());
            if snapshot.phase == phase {
                return snapshot;
            }
            if snapshot.phase == NativeRepositoryPhase::Failed
                && phase != NativeRepositoryPhase::Failed
            {
                panic!(
                    "repository reached failed phase while waiting for {phase:?}: {:?}",
                    snapshot.failure.map(|failure| failure.kind)
                );
            }
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    panic!("repository did not reach requested phase")
}

static NEXT_SCRATCH: AtomicU64 = AtomicU64::new(1);

/// An empty temporary directory, removed when dropped.
pub(crate) struct ScratchDir(pub(crate) PathBuf);

impl ScratchDir {
    pub(crate) fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "gitlama-clone-{}-{}",
            std::process::id(),
            NEXT_SCRATCH.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }
}

impl Drop for ScratchDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
