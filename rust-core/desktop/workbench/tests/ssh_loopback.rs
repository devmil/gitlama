//! The remote client over the installed OpenSSH against a loopback sshd fixture: helper
//! installation (and a damaged upload refused), the fixed launch, reads and a recorded stage
//! and commit, a helper missing for this build and an untrusted host key.
//!
//! Runs only inside `scripts/verify_remote_workspaces.py --ssh-loopback`, which starts the
//! fixture, removes the installed helper and passes the fixture through the environment:
//! `cargo test -p gitlama-workbench --test ssh_loopback -- --ignored --test-threads=1`.
//! Without the fixture the tests fail rather than pass.

use futures::future::{FutureExt, LocalBoxFuture};
use gitlama_contract::domain::path_identity::{
    NativePathIdentity, NativePathPlatform, NativeRemoteAuthority,
};
use gitlama_contract::remote_pending::NativeRemotePendingOperation;
use gitlama_core::api::*;
use gitlama_workbench::backend::SessionCalls;
use gitlama_workbench::remote::RemoteCapability;
use gitlama_workbench::remote::calls::{Ledger, RemoteSessions};
use gitlama_workbench::remote::channel::{Cancel, Channel};
use gitlama_workbench::remote::connector::Connector;
use gitlama_workbench::remote::model::{Failure, HelperArtifact, RemoteError};
use gitlama_workbench::rt::{self, Runtime};
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::collections::HashSet;
use std::path::PathBuf;
use std::rc::Rc;
use std::time::{Duration, Instant};

fn fixture(name: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => panic!("run through scripts/verify_remote_workspaces.py --ssh-loopback"),
    }
}

fn connector(build_id: &str) -> Connector {
    Connector::qualification(
        PathBuf::from(fixture("GITLAMA_SSH_FIXTURE_CONFIG")),
        build_id.to_owned(),
    )
}

fn all_capabilities() -> HashSet<RemoteCapability> {
    RemoteCapability::ALL.into_iter().collect()
}

fn run<T: 'static>(runtime: &Runtime, future: impl Future<Output = T> + 'static) -> T {
    let result = Rc::new(RefCell::new(None));
    let out = Rc::clone(&result);
    rt::spawn_detached(async move {
        *out.borrow_mut() = Some(future.await);
    });
    let deadline = Instant::now() + Duration::from_secs(120);
    while result.borrow().is_none() {
        assert!(Instant::now() < deadline, "timed out");
        runtime.run_until_stalled();
        std::thread::sleep(Duration::from_millis(2));
    }
    result.borrow_mut().take().unwrap()
}

fn open(
    runtime: &Runtime,
    connector: Rc<Connector>,
    alias: &'static str,
) -> Result<Rc<Channel>, RemoteError> {
    run(runtime, async move {
        connector
            .open(
                alias,
                all_capabilities(),
                Rc::new(Cancel::default()),
                &|_| {},
            )
            .await
    })
}

fn close(runtime: &Runtime, channel: &Rc<Channel>) {
    run(runtime, {
        let channel = Rc::clone(channel);
        async move { channel.close().await }
    });
}

#[derive(Default)]
struct MemoryLedger {
    records: RefCell<Vec<NativeRemotePendingOperation>>,
}

impl Ledger for MemoryLedger {
    fn record(
        &self,
        operation: NativeRemotePendingOperation,
    ) -> LocalBoxFuture<'static, Result<(), ()>> {
        self.records.borrow_mut().push(operation);
        async { Ok(()) }.boxed_local()
    }
}

// The lane removes the installed helper, so this test runs first (the lane passes
// `--test-threads=1`, and Rust runs tests in name order).
#[test]
#[ignore = "needs the loopback sshd fixture of scripts/verify_remote_workspaces.py"]
fn a_01_a_missing_helper_is_installed_through_ssh_and_then_connects() {
    let runtime = Runtime::install();
    let build_id = fixture("GITLAMA_SSH_FIXTURE_BUILD_ID");
    let bytes = std::fs::read(fixture("GITLAMA_SSH_FIXTURE_HELPER")).unwrap();
    let sha256: String = Sha256::digest(&bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    let connector = Rc::new(connector(&build_id));

    let missing = open(&runtime, Rc::clone(&connector), "gitlama-loopback")
        .err()
        .expect("no helper is installed yet");
    assert_eq!(missing.code, Failure::HelperNotInstalled);
    let target = missing
        .host_target
        .expect("the missing line names the host");

    let artifact = HelperArtifact {
        build_id: build_id.clone(),
        target,
        sha256: sha256.clone(),
        bytes: bytes.clone(),
    };
    let installed = run(&runtime, {
        let connector = Rc::clone(&connector);
        async move {
            connector
                .install_helper("gitlama-loopback", &artifact, Rc::new(Cancel::default()))
                .await
        }
    });
    assert_eq!(installed, Ok(()));
    let channel = open(&runtime, Rc::clone(&connector), "gitlama-loopback").expect("connect");
    close(&runtime, &channel);

    // A damaged upload is refused and leaves the working helper in place.
    let mut damaged_bytes = bytes;
    *damaged_bytes.last_mut().unwrap() ^= 1;
    let damaged = HelperArtifact {
        build_id,
        target,
        sha256,
        bytes: damaged_bytes,
    };
    let refused = run(&runtime, {
        let connector = Rc::clone(&connector);
        async move {
            connector
                .install_helper("gitlama-loopback", &damaged, Rc::new(Cancel::default()))
                .await
        }
    });
    assert_eq!(refused, Err(Failure::InstallDigest));
    let channel = open(&runtime, connector, "gitlama-loopback").expect("connect after refusal");
    close(&runtime, &channel);
}

#[test]
#[ignore = "needs the loopback sshd fixture of scripts/verify_remote_workspaces.py"]
fn a_02_the_installed_openssh_client_reads_stages_and_commits_through_the_fixed_launch() {
    let runtime = Runtime::install();
    let connector = Rc::new(connector(&fixture("GITLAMA_SSH_FIXTURE_BUILD_ID")));
    let channel = open(&runtime, connector, "gitlama-loopback").expect("connect");
    let helper = channel.helper();
    assert!(helper.capabilities.contains(&RemoteCapability::Stage));
    assert!(helper.capabilities.contains(&RemoteCapability::Commit));

    let authority = NativeRemoteAuthority {
        profile_id: "0123abcd-0000-4000-8000-0123456789ab".to_owned(),
        store_id: helper.store_id.clone(),
        account_uid: helper.account_uid.clone(),
    };
    let ledger = Rc::new(MemoryLedger::default());
    let next = Rc::new(std::cell::Cell::new(1_u64 << 62));
    let sessions = RemoteSessions::new(
        Rc::clone(&channel),
        authority.clone(),
        Rc::clone(&ledger) as Rc<dyn Ledger>,
        Rc::new(move || {
            next.set(next.get() + 1);
            next.get()
        }),
        Rc::new(|_| None),
        Rc::new(|_, _| {}),
    );
    let calls: Rc<dyn SessionCalls> = sessions.calls();
    let identity = NativePathIdentity {
        platform: NativePathPlatform::Unix,
        units: fixture("GITLAMA_SSH_FIXTURE_REPOSITORY")
            .bytes()
            .map(u16::from)
            .collect(),
        remote: Some(authority),
    };
    let opened = run(
        &runtime,
        calls.repository_session_open_identity(identity, 1),
    )
    .expect("open");
    let session = opened.session.expect("a session");
    let history = run(
        &runtime,
        calls.repository_session_history_load(session.session_id, 1, true, 64, false),
    )
    .expect("history");
    assert!(history.failure.is_none());
    assert!(history.page.expect("a history page").total_rows > 0);

    let staged = run(
        &runtime,
        calls.repository_session_staging_execute(
            session.session_id,
            1,
            NativeStagingRequest {
                request_id: 0,
                side: NativeStagingSide::Unstaged,
                scope: NativeStagingScope::All,
                paths: Vec::new(),
                row_ids: Vec::new(),
            },
        ),
    )
    .expect("stage");
    assert_eq!(staged.state, NativeStagingExecutionState::Completed);

    let preview = run(
        &runtime,
        calls.repository_session_commit_preview(
            session.session_id,
            1,
            NativeCommitRequest {
                subject: "Committed over SSH".to_owned(),
                description: String::new(),
                coauthors: Vec::new(),
                author: None,
                amend: false,
                skip_hooks: false,
                signing: NativeCommitSigning::UseGitConfiguration,
                sign_off: false,
            },
        ),
    )
    .expect("preview");
    let token = preview.preview.expect("a commit preview").token;
    let committed = run(
        &runtime,
        calls.repository_session_commit_execute(session.session_id, 1, token),
    )
    .expect("commit");
    assert_eq!(committed.state, NativeCommitExecutionState::Completed);
    let records = ledger.records.borrow().clone();
    assert!(
        records.iter().any(|record| record.state == "terminal"),
        "the writes resolved"
    );
    let closed = run(
        &runtime,
        calls.repository_session_close(session.session_id, 1),
    )
    .unwrap();
    assert!(closed.accepted);
    close(&runtime, &channel);
}

#[test]
#[ignore = "needs the loopback sshd fixture of scripts/verify_remote_workspaces.py"]
fn a_03_a_helper_not_installed_for_this_build_is_reported_as_such() {
    let runtime = Runtime::install();
    let connector = Rc::new(connector(&"f".repeat(40)));
    let failure = open(&runtime, connector, "gitlama-loopback")
        .err()
        .expect("no helper of this build");
    assert_eq!(failure.code, Failure::HelperNotInstalled);
}

#[test]
#[ignore = "needs the loopback sshd fixture of scripts/verify_remote_workspaces.py"]
fn a_04_an_untrusted_host_key_fails_without_trusting_it() {
    let runtime = Runtime::install();
    let known_hosts = PathBuf::from(fixture("GITLAMA_SSH_FIXTURE_UNTRUSTED_HOSTS"));
    let before = std::fs::read(&known_hosts).unwrap();
    let connector = Rc::new(connector(&fixture("GITLAMA_SSH_FIXTURE_BUILD_ID")));
    let failure = open(&runtime, connector, "gitlama-untrusted")
        .err()
        .expect("an unknown host key");
    assert_eq!(failure.code, Failure::SshConnectionFailed);
    assert_eq!(std::fs::read(&known_hosts).unwrap(), before);
}
