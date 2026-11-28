//! The remote client against the real helper binary: handshake, open, events, a read, a
//! recorded write and its lookup. The helper runs directly (`--stdio`) in a private home; no
//! SSH is involved.

use futures::future::{FutureExt, LocalBoxFuture};
use gitlama_application::wire::contract::RemoteCapability;
use gitlama_contract::domain::path_identity::{
    NativePathIdentity, NativePathPlatform, NativeRemoteAuthority,
};
use gitlama_contract::remote_pending::NativeRemotePendingOperation;
use gitlama_core::api::*;
use gitlama_workbench::backend::SessionCalls;
use gitlama_workbench::remote::calls::{Ledger, RemoteSessions};
use gitlama_workbench::remote::channel::Channel;
use gitlama_workbench::remote::process::RemoteProcess;
use gitlama_workbench::rt::{self, Runtime};
use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::rc::Rc;
use std::time::{Duration, Instant};

fn helper() -> Option<PathBuf> {
    let target =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../target/debug/gitlama-remote-helper");
    target.is_file().then_some(target)
}

fn git(directory: &Path, args: &[&str]) {
    let status = Command::new("git")
        .args([
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "init.defaultBranch=main",
        ])
        .args(args)
        .current_dir(directory)
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .status()
        .unwrap();
    assert!(status.success(), "git {args:?}");
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

fn run<T: 'static>(runtime: &Runtime, future: impl Future<Output = T> + 'static) -> T {
    let result = Rc::new(RefCell::new(None));
    let out = Rc::clone(&result);
    rt::spawn_detached(async move {
        *out.borrow_mut() = Some(future.await);
    });
    let deadline = Instant::now() + Duration::from_secs(60);
    while result.borrow().is_none() {
        assert!(Instant::now() < deadline, "timed out");
        runtime.run_until_stalled();
        std::thread::sleep(Duration::from_millis(2));
    }
    result.borrow_mut().take().unwrap()
}

#[test]
fn the_client_reads_and_writes_through_the_real_helper() {
    let Some(helper) = helper() else {
        eprintln!("skipped: build gitlama-remote-helper first (cargo test runs it earlier)");
        return;
    };
    let root = std::env::temp_dir().join(format!(
        "gitlama-client-it-{}",
        gitlama_workbench::remote::model::random_hex32()
    ));
    let home = root.join("home");
    let repository = root.join("repository");
    std::fs::create_dir_all(&home).unwrap();
    std::fs::create_dir_all(&repository).unwrap();
    git(&repository, &["init", "-q"]);
    git(&repository, &["config", "user.name", "Fixture"]);
    git(
        &repository,
        &["config", "user.email", "fixture@example.invalid"],
    );
    git(&repository, &["config", "commit.gpgsign", "false"]);
    std::fs::write(repository.join("README.md"), b"hello\n").unwrap();
    git(&repository, &["add", "."]);
    git(&repository, &["commit", "-qm", "initial"]);
    std::fs::write(repository.join("README.md"), b"hello\nworld\n").unwrap();

    let runtime = Runtime::install();
    let environment = vec![
        ("HOME".to_owned(), home.display().to_string()),
        ("PATH".to_owned(), std::env::var("PATH").unwrap_or_default()),
        ("GIT_CONFIG_GLOBAL".to_owned(), "/dev/null".to_owned()),
        ("GIT_CONFIG_NOSYSTEM".to_owned(), "1".to_owned()),
    ];
    let (process, events) =
        RemoteProcess::start(&helper, &["--stdio".to_owned()], Some(&environment)).unwrap();
    let build_id = gitlama_core::api::remote_helper_build_id();
    let capabilities = [
        RemoteCapability::Read,
        RemoteCapability::ListDirectory,
        RemoteCapability::Stage,
    ]
    .into_iter()
    .collect();
    let channel = run(
        &runtime,
        Channel::connect(process, events, build_id, capabilities, None),
    )
    .expect("handshake");
    let helper_info = channel.helper();
    assert!(helper_info.capabilities.contains(&RemoteCapability::Read));
    let stage_offered = helper_info.capabilities.contains(&RemoteCapability::Stage);

    let authority = NativeRemoteAuthority {
        profile_id: "0123abcd-0000-4000-8000-0123456789ab".to_owned(),
        store_id: helper_info.store_id.clone(),
        account_uid: helper_info.account_uid.clone(),
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

    // Listing starts at the private home.
    let page = run(&runtime, {
        let sessions = Rc::clone(&sessions);
        async move { sessions.list_directory(None, None).await }
    })
    .expect("listing");
    assert_eq!(
        page.directory,
        std::fs::canonicalize(&home)
            .unwrap()
            .display()
            .to_string()
            .into_bytes()
    );

    let path = std::fs::canonicalize(&repository)
        .unwrap()
        .display()
        .to_string()
        .into_bytes();
    let identity = NativePathIdentity {
        platform: NativePathPlatform::Unix,
        units: path.iter().map(|byte| u16::from(*byte)).collect(),
        remote: Some(authority.clone()),
    };
    let opened = run(
        &runtime,
        calls.repository_session_open_identity(identity, 1),
    )
    .expect("open");
    let session = opened.session.expect("a session");
    assert!(
        session.session_id > 1 << 62,
        "local identifiers are allocated here"
    );
    let worktree = session
        .snapshot
        .identity
        .as_ref()
        .unwrap()
        .worktree_root
        .clone();
    assert_eq!(
        worktree.remote,
        Some(authority.clone()),
        "host paths carry the authority"
    );

    let history = run(
        &runtime,
        calls.repository_session_history_load(session.session_id, 1, true, 50, false),
    )
    .expect("history");
    assert!(history.failure.is_none());

    // Events arrive as publications and drain locally.
    let deadline = Instant::now() + Duration::from_secs(20);
    let mut seen = 0;
    while seen == 0 && Instant::now() < deadline {
        seen += run(
            &runtime,
            calls.repository_session_events(session.session_id, 1, 64),
        )
        .unwrap()
        .events
        .len();
        std::thread::sleep(Duration::from_millis(50));
    }

    assert!(seen > 0, "the helper published session events");
    assert!(stage_offered, "a helper with a usable store offers staging");
    {
        let request = NativeStagingRequest {
            request_id: 0,
            side: NativeStagingSide::Unstaged,
            scope: NativeStagingScope::Files,
            paths: vec![b"README.md".to_vec()],
            row_ids: Vec::new(),
        };
        let staged = run(
            &runtime,
            calls.repository_session_staging_execute(session.session_id, 1, request),
        )
        .expect("stage");
        assert_ne!(staged.state, NativeStagingExecutionState::Stale);
        let records = ledger.records.borrow().clone();
        assert!(
            records.len() >= 2,
            "recorded before execute and resolved after"
        );
        assert_eq!(records[0].state, "pending");
        assert_eq!(records.last().unwrap().state, "terminal");
        let looked = run(&runtime, {
            let sessions = Rc::clone(&sessions);
            let operation = records[0].clone();
            async move { sessions.lookup(&operation).await }
        })
        .expect("lookup");
        assert_eq!(looked.state, "terminal");
    }

    let closed = run(
        &runtime,
        calls.repository_session_close(session.session_id, 1),
    )
    .unwrap();
    assert!(closed.accepted);
    run(&runtime, {
        let channel = Rc::clone(&channel);
        async move { channel.close().await }
    });
    assert_eq!(channel.closed(), Some(None));
    let _ = std::fs::remove_dir_all(root);
}
