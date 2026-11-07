//! Timings of one fast-forward pull through the production native API, followed by the
//! refreshes it causes. Prints Git subcommands and durations, never repository content.
//!
//! Prepare a worktree that is behind a reachable remote, for example a local clone reset to an
//! older commit, and pass its path.
use gitlama_application::transfer::{
    NativePullStrategy, NativeTransferKind, NativeTransferRequest,
};
use gitlama_core::api::*;
use std::time::{Duration, Instant};

fn main() {
    let path = std::env::args()
        .nth(1)
        .expect("repository argument required");
    let settle = std::env::args()
        .nth(2)
        .and_then(|value| value.parse().ok())
        .map_or(Duration::from_secs(8), Duration::from_secs);
    let start = Instant::now();
    let session = repository_session_open(path, 1)
        .session
        .expect("open failed");
    let id = session.session_id;
    wait_ready(id, start, "open");
    // Let the opening watcher and ignore discovery finish before measuring the transfer.
    drain(id, start, Duration::from_secs(3));
    let preview = repository_session_transfer_preview(
        id,
        1,
        NativeTransferRequest {
            kind: NativeTransferKind::Pull,
            remote: None,
            branch: None,
            pull_strategy: NativePullStrategy::FastForwardOnly,
            allow_dirty: false,
            stash_before_pull: false,
            force_with_lease: false,
            set_upstream: false,
            refetch: false,
            prune: true,
        },
    );
    println!("preview_failure={:?}", preview.failure);
    let preview = preview.preview.expect("preview failed");
    println!("behind={} ahead={}", preview.behind, preview.ahead);
    let pull = Instant::now();
    // The window keeps reading while a transfer runs; these reads queue behind the mutation.
    let reader = std::env::var_os("PROFILE_CONCURRENT_READS").map(|_| {
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(300));
            let t = Instant::now();
            let preview = repository_session_history_load(id, 1, false, 512, false);
            let loaded = t.elapsed().as_millis();
            let complete = preview.page.map(|page| {
                repository_session_history_complete(id, 1, page.request_id, 512)
                    .page
                    .map(|page| page.total_rows)
            });
            println!(
                "queued_history_ms={loaded} complete_ms={} rows={complete:?}",
                t.elapsed().as_millis()
            );
        })
    });
    let result = repository_session_transfer_execute(id, 1, preview.token);
    println!(
        "execute_ms={} state={:?} failure={:?}",
        pull.elapsed().as_millis(),
        result.state,
        result.failure
    );
    if let Some(reader) = reader {
        reader.join().expect("reader failed");
    }
    // What the window does next: optionally request its own refresh, then reload the graph.
    if std::env::var_os("PROFILE_FOLLOW_UP_REFRESH").is_some() {
        assert!(repository_session_refresh(id, 1).accepted);
    }
    let graph = Instant::now();
    let reloaded = repository_session_history_load(id, 1, false, 512, false);
    println!(
        "graph_after_execute_ms={} failure={:?} total_ms={}",
        graph.elapsed().as_millis(),
        reloaded.failure,
        pull.elapsed().as_millis()
    );
    drain(id, start, settle);
    let page = repository_session_activity(id, 1, 64)
        .page
        .expect("activity failed");
    let origin = page
        .records
        .iter()
        .map(|record| record.started_at_unix_ms)
        .min()
        .unwrap_or(0);
    for record in &page.records {
        println!(
            "activity at_ms={} ms={} status={:?} exit={:?} git {}",
            record.started_at_unix_ms - origin,
            record
                .finished_at_unix_ms
                .map_or(-1, |end| (end - record.started_at_unix_ms) as i64),
            record.status,
            record.exit_code,
            record
                .arguments
                .iter()
                .filter(|argument| !argument.starts_with('/'))
                .take(6)
                .cloned()
                .collect::<Vec<_>>()
                .join(" ")
        );
    }
    assert!(repository_session_close(id, 1).accepted);
}

fn wait_ready(id: u64, start: Instant, label: &str) {
    loop {
        let events = repository_session_events(id, 1, 256);
        if events
            .events
            .iter()
            .filter_map(|event| event.snapshot.as_ref())
            .any(|snapshot| snapshot.phase == NativeRepositoryPhase::Ready)
        {
            break;
        }
        assert!(start.elapsed() < Duration::from_secs(120), "ready timeout");
        std::thread::sleep(Duration::from_millis(10));
    }
    println!("{label}_ready_ms={}", start.elapsed().as_millis());
}

fn drain(id: u64, start: Instant, duration: Duration) {
    let until = Instant::now() + duration;
    while Instant::now() < until {
        for event in repository_session_events(id, 1, 256).events {
            println!(
                "event at_ms={} kind={:?} phase={:?} revision={:?} overflow={:?}",
                start.elapsed().as_millis(),
                event.kind,
                event.snapshot.as_ref().map(|snapshot| snapshot.phase),
                event.snapshot.as_ref().map(|snapshot| snapshot.revision),
                event.watch_overflow_revision
            );
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}
