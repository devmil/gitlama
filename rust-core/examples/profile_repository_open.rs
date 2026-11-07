//! Read-only timings through the production native API. Never prints repository content.
use gitlama_core::api::*;
use std::time::{Duration, Instant};
fn main() {
    let path = std::env::args()
        .nth(1)
        .expect("repository argument required");
    let start = Instant::now();
    let session = repository_session_open(path, 1)
        .session
        .expect("open failed");
    println!("open_ms={}", start.elapsed().as_millis());
    let t = Instant::now();
    let preview = repository_session_history_load(session.session_id, 1, false, 512, false)
        .page
        .expect("preview failed");
    println!("preview_ms={}", t.elapsed().as_millis());
    let t = Instant::now();
    let result =
        repository_session_history_complete(session.session_id, 1, preview.request_id, 512);
    println!("completion_failure={:?}", result.failure);
    let complete = result.page.expect("completion failed");
    println!(
        "complete_ms={} rows={}",
        t.elapsed().as_millis(),
        complete.total_rows
    );
    let t = Instant::now();
    for offset in (0..complete.total_rows).step_by(512) {
        assert!(repository_session_history_page(
            session.session_id,
            1,
            preview.request_id,
            offset,
            512
        )
        .failure
        .is_none());
    }
    println!("all_pages_ms={}", t.elapsed().as_millis());
    loop {
        let events = repository_session_events(session.session_id, 1, 256);
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
    println!("ready_ms={}", start.elapsed().as_millis());
    let mut samples = Vec::new();
    for offset in (0..complete.total_rows)
        .step_by((complete.total_rows as usize / 32).max(1))
        .take(32)
    {
        let page =
            repository_session_history_page(session.session_id, 1, complete.request_id, offset, 1)
                .page
                .unwrap();
        let t = Instant::now();
        let selected = repository_session_history_select(
            session.session_id,
            1,
            complete.request_id,
            NativeHistorySelectionOptions {
                object_id: Some(page.rows[0].object_id.clone()),
                toggle: false,
                reveal: true,
                focus: true,
                offset: 0,
                maximum_rows: 512,
            },
        );
        assert!(selected.failure.is_none());
        samples.push(t.elapsed().as_micros());
    }
    samples.sort_unstable();
    println!(
        "selection_samples={} median_us={} p95_us={} max_us={}",
        samples.len(),
        samples[samples.len() / 2],
        samples[(samples.len() * 95).div_ceil(100) - 1],
        samples.last().unwrap()
    );
    for _ in 0..3 {
        let _ = repository_session_events(session.session_id, 1, 256);
        let t = Instant::now();
        assert!(repository_session_refresh(session.session_id, 1).accepted);
        loop {
            let events = repository_session_events(session.session_id, 1, 256);
            if events
                .events
                .iter()
                .filter_map(|event| event.snapshot.as_ref())
                .any(|snapshot| snapshot.phase == NativeRepositoryPhase::Ready)
            {
                break;
            }
            assert!(t.elapsed() < Duration::from_secs(120), "refresh timeout");
            std::thread::sleep(Duration::from_millis(10));
        }
        println!("refresh_ms={}", t.elapsed().as_millis());
    }
    let t = Instant::now();
    assert!(repository_session_close(session.session_id, 1).accepted);
    println!("close_ms={}", t.elapsed().as_millis());
}
