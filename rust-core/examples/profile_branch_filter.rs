//! Branch-filter timings through the production native API. Never prints repository content.
use gitlama_application::domain::history::MAX_HISTORY_BRANCH_FILTER_REFS;
use gitlama_core::api::*;
use std::process::Command;
use std::time::Instant;

fn refs(path: &str, pattern: &str) -> Vec<Vec<u8>> {
    let output = Command::new("git")
        .args(["-C", path, "for-each-ref", "--format=%(refname)", pattern])
        .output()
        .expect("git for-each-ref");
    output
        .stdout
        .split(|byte| *byte == b'\n')
        .filter(|line| !line.is_empty())
        .map(<[u8]>::to_vec)
        .collect()
}

fn main() {
    let path = std::env::args()
        .nth(1)
        .expect("repository argument required");
    let session = repository_session_open(path.clone(), 1)
        .session
        .expect("open failed");
    let preview = repository_session_history_load(session.session_id, 1, false, 512, false)
        .page
        .expect("preview failed");
    let complete =
        repository_session_history_complete(session.session_id, 1, preview.request_id, 512)
            .page
            .expect("completion failed");
    println!("rows={}", complete.total_rows);
    let local = refs(&path, "refs/heads");
    let remote = refs(&path, "refs/remotes");
    let all = local.iter().chain(&remote).cloned().collect::<Vec<_>>();
    let cases: Vec<(&str, Vec<Vec<u8>>)> = vec![
        ("one_local", local.iter().take(1).cloned().collect()),
        ("five", all.iter().take(5).cloned().collect()),
        ("fifty", all.iter().take(50).cloned().collect()),
        (
            "maximum",
            all.iter()
                .take(MAX_HISTORY_BRANCH_FILTER_REFS)
                .cloned()
                .collect(),
        ),
        ("clear", Vec::new()),
    ];
    // Alternate with a different filter so every measured call is a change.
    let other = remote.iter().rev().take(1).cloned().collect::<Vec<_>>();
    for (label, filter) in cases {
        let mut samples = Vec::new();
        let mut last = None;
        for _ in 0..5 {
            assert!(repository_session_history_branch_filter(
                session.session_id,
                1,
                complete.request_id,
                other.clone(),
                0,
                512,
            )
            .failure
            .is_none());
            let started = Instant::now();
            let result = repository_session_history_branch_filter(
                session.session_id,
                1,
                complete.request_id,
                filter.clone(),
                0,
                512,
            );
            samples.push(started.elapsed().as_secs_f64() * 1000.0);
            last = Some(result.page.expect("filter failed"));
        }
        samples.sort_by(f64::total_cmp);
        let page = last.unwrap();
        println!(
            "{label} refs={} median_ms={:.2} max_ms={:.2} rows={} lanes={} payload_bytes={}",
            filter.len(),
            samples[samples.len() / 2],
            samples[samples.len() - 1],
            page.total_rows,
            page.lane_count,
            page.payload_bytes,
        );
    }
    assert!(repository_session_close(session.session_id, 1).accepted);
}
