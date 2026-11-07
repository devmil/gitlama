//! Drives the real helper binary over its standard streams against real Git repositories.
#![cfg(unix)]
mod common;

use common::{git, object, ordinary_repository, Helper, Root};
use gitlama_application::domain::limits::SESSIONS_PER_CONNECTION;
use gitlama_application::wire::runtime::{self as w, Value};
use std::time::{Duration, Instant};

fn session_arguments(open: &Value, generation: u64, extra: &[(&str, Value)]) -> Value {
    let session = &open["open"]["session"];
    let mut pairs = vec![
        ("sessionId", session["sessionId"].clone()),
        ("generation", Value::from(generation.to_string())),
    ];
    pairs.extend(extra.iter().cloned());
    object(&pairs)
}

#[test]
fn hello_reports_identity_and_read_capabilities_before_any_repository_work() {
    let home = Root::new("hello");
    let helper = Helper::spawn(&home.0);
    let hello = helper.hello.clone();
    assert_eq!(hello["kind"], "hello");
    assert_eq!(hello["magic"], "gitlama-remote-helper");
    assert_eq!(hello["protocolMajor"], 1);
    assert_eq!(
        hello["buildId"],
        gitlama_application::remote_session_policy::BUILD_ID
    );
    assert_eq!(hello["gitState"], "available");
    assert_eq!(hello["store"]["state"], "ready");
    let store_id = hello["store"]["storeId"].as_str().unwrap();
    assert_eq!(store_id.len(), 32);
    assert_eq!(
        hello["account"]["uid"],
        rustix::process::geteuid().as_raw().to_string()
    );
    let capabilities: Vec<&str> = hello["capabilities"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c.as_str().unwrap())
        .collect();
    assert!(capabilities.contains(&"read") && capabilities.contains(&"listDirectory"));
    drop(helper);
    // A second connection reports the same durable store.
    let again = Helper::spawn(&home.0);
    assert_eq!(again.hello["store"]["storeId"], store_id);
    assert_ne!(again.hello["helperIncarnation"], hello["helperIncarnation"]);
}

#[test]
fn rejected_acknowledgement_ends_the_connection_without_work() {
    let home = Root::new("reject");
    let mut helper = Helper::spawn(&home.0);
    helper.hello["buildId"] = Value::from("1".repeat(40));
    helper.acknowledge(&["read"]);
    let fatal = helper.next().expect("fatal frame");
    assert_eq!(fatal["kind"], "fatal");
    assert_eq!(fatal["code"], "handshakeRejected");
    let status = helper.wait_exit(Duration::from_secs(5)).expect("exits");
    assert!(!status.success());
}

#[test]
fn missing_acknowledgement_times_out() {
    let home = Root::new("timeout");
    let mut helper = Helper::spawn(&home.0);
    let started = Instant::now();
    let fatal = helper.next().expect("fatal frame");
    assert_eq!(fatal["code"], "handshakeTimeout");
    assert!(started.elapsed() >= Duration::from_secs(9));
    assert!(helper.wait_exit(Duration::from_secs(5)).is_some());
}

#[test]
fn read_surface_projects_a_real_repository_without_touching_it() {
    let home = Root::new("read");
    let repository = ordinary_repository(&home.0);
    let index_before = std::fs::read(repository.join(".git/index")).unwrap();
    let refs_before = git(&repository, &["show-ref"]);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read", "listDirectory"]);

    let open = helper.open(&repository, 3);
    let binding = open["binding"].as_str().unwrap();
    assert_eq!(binding.len(), 64);
    let snapshot = &open["open"]["session"]["snapshot"];
    let root = w::units_d(&snapshot["identity"]["worktreeRoot"]["units"]).unwrap();
    assert_eq!(
        common::unit_bytes(&root),
        repository.as_os_str().as_encoded_bytes()
    );

    let history = helper.ok(
        "repositorySessionHistoryLoad",
        session_arguments(
            &open,
            3,
            &[
                ("complete", Value::Bool(true)),
                ("maximumRows", Value::from(64)),
                ("otherRefs", Value::Bool(false)),
            ],
        ),
    );
    assert!(history["failure"].is_null(), "{history}");
    let page = &history["page"];
    assert_eq!(page["totalRows"], "2");
    let head = git(&repository, &["rev-parse", "HEAD"]);
    let parent = git(&repository, &["rev-parse", "HEAD~1"]);

    let diff = helper.ok(
        "repositorySessionCommitDiffLoad",
        session_arguments(
            &open,
            3,
            &[(
                "options",
                object(&[
                    ("commit", Value::from(head.clone())),
                    ("firstParent", Value::from(parent)),
                    ("contextLines", Value::from(3)),
                    ("whitespace", Value::from("preserve")),
                    ("layout", Value::from("unified")),
                    ("oldPath", Value::Null),
                    ("newPath", Value::Null),
                    ("maximumRows", Value::from(128)),
                    ("forceText", Value::from(false)),
                ]),
            )],
        ),
    );
    assert!(diff["failure"].is_null(), "{diff}");
    let rows = diff["page"]["rows"].as_array().unwrap();
    assert!(!rows.is_empty());

    let inspection = helper.ok(
        "repositorySessionCommitInspection",
        session_arguments(
            &open,
            3,
            &[("commit", Value::from(head)), ("firstParent", Value::Null)],
        ),
    );
    assert!(inspection["failure"].is_null(), "{inspection}");

    let closed = helper.ok("closeRepository", session_arguments(&open, 3, &[]));
    assert_eq!(closed["accepted"], true);
    // Closed sessions are no longer addressable.
    assert_eq!(
        helper.error_code(
            "repositorySessionHistoryLoad",
            session_arguments(
                &open,
                3,
                &[
                    ("complete", Value::Bool(true)),
                    ("maximumRows", Value::from(64)),
                    ("otherRefs", Value::Bool(false)),
                ],
            ),
        ),
        "unknownSession"
    );
    assert_eq!(
        std::fs::read(repository.join(".git/index")).unwrap(),
        index_before
    );
    assert_eq!(git(&repository, &["show-ref"]), refs_before);
}

#[test]
fn stale_stat_data_never_rewrites_the_users_index() {
    let home = Root::new("index");
    let repository = ordinary_repository(&home.0);
    git(&repository, &["add", "README.md"]);
    let earlier = std::time::SystemTime::now() - Duration::from_hours(1);
    std::fs::File::options()
        .write(true)
        .open(repository.join("src.txt"))
        .unwrap()
        .set_times(std::fs::FileTimes::new().set_modified(earlier))
        .unwrap();
    let index_before = std::fs::read(repository.join(".git/index")).unwrap();
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read"]);
    helper.open(&repository, 1);
    // Wait for the status scan to publish Ready.
    let started = Instant::now();
    let mut ready = false;
    while !ready && started.elapsed() < Duration::from_secs(20) {
        let envelope = helper.next().unwrap();
        if envelope["kind"] == "publication" {
            ready = envelope["payload"]["events"]["events"]
                .as_array()
                .unwrap()
                .iter()
                .any(|event| event["snapshot"]["phase"] == "ready");
        }
    }
    assert!(ready);
    assert_eq!(
        std::fs::read(repository.join(".git/index")).unwrap(),
        index_before
    );
    assert!(!repository.join(".git/index.lock").exists());
}

#[test]
fn only_the_closed_read_surface_is_reachable() {
    let home = Root::new("surface");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read"]);
    let open = helper.open(&repository, 1);
    for method in [
        "repositorySessionStagingExecute",
        "repositorySessionCommitExecute",
        "repositorySessionDiscardExecute",
        "repositorySessionTransferPreview",
        "runGit",
        "shell",
    ] {
        assert_eq!(
            helper.error_code(method, session_arguments(&open, 1, &[])),
            "unsupportedCommand",
            "{method}"
        );
    }
    assert_eq!(
        helper.error_code("previewStage", session_arguments(&open, 1, &[])),
        "writeNotPermitted"
    );
    // listDirectory was not negotiated on this connection.
    assert_eq!(
        helper.error_code(
            "listDirectory",
            object(&[("directory", Value::Null), ("cursor", Value::Null)])
        ),
        "unsupportedCommand"
    );
    let forged = object(&[
        ("sessionId", Value::from("999999")),
        ("generation", Value::from("1")),
        ("complete", Value::Bool(true)),
        ("maximumRows", Value::from(10)),
        ("otherRefs", Value::Bool(false)),
    ]);
    assert_eq!(
        helper.error_code("repositorySessionHistoryLoad", forged),
        "unknownSession"
    );
    assert_eq!(
        helper.error_code(
            "repositorySessionHistoryLoad",
            session_arguments(&open, 1, &[("complete", Value::Bool(true))])
        ),
        "invalidRequest"
    );
}

#[test]
fn bindings_detect_mismatches_and_sessions_are_bounded() {
    let home = Root::new("binding");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read"]);
    let first = helper.open(&repository, 1);
    let binding = first["binding"].as_str().unwrap().to_owned();
    // A symlink alias resolves to the same workspace binding.
    let alias = home.0.join("alias");
    std::os::unix::fs::symlink(&repository, &alias).unwrap();
    let aliased = helper.open(&alias, 2);
    assert_eq!(aliased["binding"], binding.as_str());
    let mismatch = helper.error_code(
        "openRepository",
        object(&[
            (
                "path",
                w::bytes_e(repository.as_os_str().as_encoded_bytes()),
            ),
            ("generation", Value::from("3")),
            ("expectedBinding", Value::from("0".repeat(64))),
        ]),
    );
    assert_eq!(mismatch, "identityMismatch");
    // Two sessions are open; fill the connection.
    let full = 4 + SESSIONS_PER_CONNECTION as u64 - 2;
    for generation in 4..full {
        helper.open(&repository, generation);
    }
    assert_eq!(
        helper.error_code(
            "openRepository",
            object(&[
                (
                    "path",
                    w::bytes_e(repository.as_os_str().as_encoded_bytes())
                ),
                ("generation", Value::from(full.to_string())),
                ("expectedBinding", Value::Null),
            ]),
        ),
        "capacity"
    );
    assert_eq!(
        helper.error_code(
            "openRepository",
            object(&[
                ("path", w::bytes_e(b"relative/path")),
                ("generation", Value::from((full + 1).to_string())),
                ("expectedBinding", Value::Null),
            ]),
        ),
        "pathInvalid"
    );
}

#[test]
fn replaced_root_changes_the_binding() {
    let home = Root::new("replaced");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read"]);
    let first = helper.open(&repository, 1)["binding"]
        .as_str()
        .unwrap()
        .to_owned();
    helper.ok(
        "closeRepository",
        object(&[
            ("sessionId", Value::from("1")),
            ("generation", Value::from("1")),
        ]),
    );
    std::fs::rename(&repository, home.0.join("moved")).unwrap();
    let replacement = ordinary_repository(&home.0);
    assert_eq!(replacement, repository);
    let second = helper.open(&repository, 2)["binding"]
        .as_str()
        .unwrap()
        .to_owned();
    assert_ne!(first, second);
}

#[test]
fn external_changes_arrive_as_publications() {
    let home = Root::new("events");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read"]);
    let open = helper.open(&repository, 1);
    let session_id = open["open"]["session"]["sessionId"].clone();
    std::thread::sleep(Duration::from_millis(500));
    std::fs::write(repository.join("external.txt"), b"external\n").unwrap();
    let started = Instant::now();
    let mut seen = false;
    let mut last_sequence = 0_u64;
    while !seen && started.elapsed() < Duration::from_secs(20) {
        let envelope = helper.next().unwrap();
        if envelope["kind"] != "publication" {
            continue;
        }
        assert_eq!(envelope["requestId"], "0");
        assert_eq!(envelope["payload"]["sessionId"], session_id);
        let sequence: u64 = envelope["payload"]["sequence"]
            .as_str()
            .unwrap()
            .parse()
            .unwrap();
        assert!(sequence > last_sequence);
        last_sequence = sequence;
        for event in envelope["payload"]["events"]["events"].as_array().unwrap() {
            let entries = event["snapshot"]["status"]["entries"].as_array();
            if entries.is_some_and(|entries| {
                entries.iter().any(|entry| {
                    w::units_d(&entry["path"]["units"])
                        .is_ok_and(|units| common::unit_bytes(&units).ends_with(b"external.txt"))
                })
            }) {
                seen = true;
            }
        }
    }
    assert!(seen, "the watcher's status refresh reaches the client");
}

#[test]
fn large_snapshots_travel_as_verified_transactions() {
    let home = Root::new("large");
    let repository = ordinary_repository(&home.0);
    let directory = repository.join("generated");
    std::fs::create_dir(&directory).unwrap();
    let name =
        |index: usize| directory.join(format!("tracked-file-with-a-long-name-{index:06}.txt"));
    for index in 0..12_000 {
        std::fs::write(name(index), b"x").unwrap();
    }
    git(&repository, &["add", "generated"]);
    git(&repository, &["commit", "-qm", "many"]);
    for index in 0..12_000 {
        std::fs::write(name(index), b"changed").unwrap();
    }
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read"]);
    helper.open(&repository, 1);
    // The core bounds a status snapshot and reports the true total; the bounded snapshot is
    // still far above one frame's chunk size.
    let status = loop {
        let envelope = helper.next().expect("the ready snapshot");
        if envelope["kind"] != "publication" {
            continue;
        }
        let ready = envelope["payload"]["events"]["events"]
            .as_array()
            .unwrap()
            .iter()
            .rev()
            .find(|event| event["snapshot"]["phase"] == "ready")
            .map(|event| event["snapshot"]["status"].clone());
        if let Some(status) = ready {
            break status;
        }
    };
    // 12 000 modified files plus the unstaged README; the commit took staged.txt.
    assert_eq!(status["totalEntries"], "12001");
    assert_eq!(status["entriesTruncated"], true);
    assert_eq!(status["entries"].as_array().unwrap().len(), 10_000);
    assert!(
        helper.transactions > 0,
        "the snapshot travelled as a chunk transaction"
    );
}

#[test]
fn directory_listing_pages_the_home_directory() {
    let home = Root::new("listing");
    ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read", "listDirectory"]);
    let listing = helper.ok(
        "listDirectory",
        object(&[("directory", Value::Null), ("cursor", Value::Null)]),
    );
    assert_eq!(
        w::bytes_d(&listing["directory"]).unwrap(),
        home.0.as_os_str().as_encoded_bytes()
    );
    let entries = listing["entries"].as_array().unwrap();
    assert!(entries.iter().any(|entry| {
        w::bytes_d(&entry["name"]).unwrap() == b"ordinary" && entry["repository"] == true
    }));
}

#[test]
fn ping_shutdown_and_end_of_input_tear_down_promptly() {
    let home = Root::new("teardown");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read"]);
    helper.open(&repository, 1);
    let ping = helper.envelope("ping", object(&[]));
    loop {
        let envelope = helper.next().unwrap();
        if envelope["kind"] == "pong" {
            assert_eq!(envelope["requestId"], ping.to_string());
            break;
        }
    }
    let shutdown = helper.envelope("shutdown", object(&[]));
    let started = Instant::now();
    loop {
        let envelope = helper.next().expect("goodbye before exit");
        if envelope["kind"] == "goodbye" {
            assert_eq!(envelope["requestId"], shutdown.to_string());
            break;
        }
    }
    assert!(helper.wait_exit(Duration::from_secs(5)).unwrap().success());
    assert!(started.elapsed() < Duration::from_secs(5));

    let mut second = Helper::spawn(&home.0);
    second.acknowledge(&["read"]);
    second.open(&repository, 1);
    second.close_stdin();
    assert!(second.wait_exit(Duration::from_secs(6)).is_some());
}

#[test]
fn protocol_violations_close_the_connection() {
    let home = Root::new("violation");
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read"]);
    helper.send_raw(&object(&[("unexpected", Value::Bool(true))]));
    let fatal = helper.next().expect("fatal");
    assert_eq!(fatal["kind"], "fatal");
    assert_eq!(fatal["payload"]["code"], "protocolViolation");
    assert!(helper.wait_exit(Duration::from_secs(6)).is_some());
}

#[test]
fn version_and_usage() {
    let output = std::process::Command::new(common::HELPER)
        .arg("--version")
        .output()
        .unwrap();
    assert!(output.status.success());
    let text = String::from_utf8(output.stdout).unwrap();
    assert!(text.contains(gitlama_application::remote_session_policy::BUILD_ID));
    assert!(text.contains(gitlama_application::remote_session_policy::SOURCE_COMMIT));
    // The ID is the compatibility version, not the source commit.
    let version = include_str!("../COMPATIBILITY")
        .lines()
        .find_map(|line| line.strip_prefix("version "))
        .unwrap();
    assert_eq!(
        gitlama_application::remote_session_policy::BUILD_ID,
        format!("{version:0>40}")
    );
    let status = std::process::Command::new(common::HELPER)
        .arg("--unknown")
        .output()
        .unwrap()
        .status;
    assert_eq!(status.code(), Some(2));
}

#[test]
#[allow(clippy::too_many_lines)]
fn syntax_colours_are_parsed_on_the_host_beside_foreground_reads() {
    use std::fmt::Write as _;
    let home = Root::new("syntax");
    let repository = home.0.join("syntax");
    std::fs::create_dir_all(&repository).unwrap();
    git(&repository, &["init", "-q"]);
    git(&repository, &["config", "user.name", "Fixture"]);
    git(
        &repository,
        &["config", "user.email", "fixture@example.invalid"],
    );
    git(&repository, &["config", "commit.gpgsign", "false"]);
    let mut source = String::from("/* opened far above the hunk\n");
    for index in 0..40 {
        writeln!(source, "   comment line {index}").unwrap();
    }
    source.push_str("*/\nfn main() {}\n");
    std::fs::write(repository.join("lib.rs"), &source).unwrap();
    git(&repository, &["add", "."]);
    git(&repository, &["commit", "-qm", "base"]);
    let parent = git(&repository, &["rev-parse", "HEAD"]);
    let changed = source.replace("comment line 39", "changed comment");
    std::fs::write(repository.join("lib.rs"), changed).unwrap();
    git(&repository, &["commit", "-qam", "change"]);
    let head = git(&repository, &["rev-parse", "HEAD"]);

    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read"]);
    let open = helper.open(&repository, 5);
    let diff = helper.ok(
        "repositorySessionCommitDiffLoad",
        session_arguments(
            &open,
            5,
            &[(
                "options",
                object(&[
                    ("commit", Value::from(head)),
                    ("firstParent", Value::from(parent)),
                    ("contextLines", Value::from(3)),
                    ("whitespace", Value::from("preserve")),
                    ("layout", Value::from("unified")),
                    ("oldPath", Value::Null),
                    ("newPath", Value::Null),
                    ("maximumRows", Value::from(128)),
                    ("forceText", Value::from(false)),
                ]),
            )],
        ),
    );
    let page = &diff["page"];
    let request_id = page["requestId"].clone();
    let rows = page["rows"].as_array().unwrap().clone();
    let syntax_request = |syntax_id: u64| {
        object(&[
            ("origin", Value::from("committed")),
            ("diffRequestId", request_id.clone()),
            ("syntaxRequestId", Value::from(syntax_id.to_string())),
            ("offset", Value::from("0")),
            ("maximumRows", Value::from(rows.len().min(32))),
        ])
    };

    // The syntax read waits in the bulk lane; a foreground read beside it answers.
    let syntax = helper.send_call(
        "repositorySessionDiffSyntaxPage",
        session_arguments(&open, 5, &[("request", syntax_request(1))]),
    );
    let foreground = helper.send_call(
        "repositorySessionDiffPage",
        session_arguments(
            &open,
            5,
            &[
                ("requestId", request_id.clone()),
                ("offset", Value::from("0")),
                ("maximumRows", Value::from(16)),
            ],
        ),
    );
    let foreground = helper.result(foreground);
    assert!(foreground["ok"]["failure"].is_null(), "{foreground}");
    let mut result = helper.result(syntax)["ok"].clone();
    for _ in 0..20 {
        let deferred = result["page"]["rows"]
            .as_array()
            .unwrap()
            .iter()
            .any(|row| row["oldState"] == "deferred_" || row["newState"] == "deferred_");
        if !deferred {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
        result = helper.ok(
            "repositorySessionDiffSyntaxPage",
            session_arguments(&open, 5, &[("request", syntax_request(2))]),
        );
    }
    assert!(result["failure"].is_null(), "{result}");
    let syntax_rows = result["page"]["rows"].as_array().unwrap();
    let index = rows
        .iter()
        .position(|row| {
            row["kind"] == "addition" && w::bytes_d(&row["text"]).unwrap() == b"   changed comment"
        })
        .unwrap();
    let row = &syntax_rows[index];
    assert_eq!(row["stableId"], rows[index]["stableId"]);
    assert_eq!(row["newState"], "ready", "{row}");
    // The comment opened 40 lines above the hunk, which the host parsed.
    assert!(row["newSpans"]
        .as_array()
        .unwrap()
        .iter()
        .all(|span| span["kind"] == "comment"));
    assert!(!row["newSpans"].as_array().unwrap().is_empty());

    // Cancelling is idempotent and a stale projection answers a failure.
    let cancel = helper.ok(
        "repositorySessionDiffSyntaxCancel",
        session_arguments(
            &open,
            5,
            &[
                ("origin", Value::from("committed")),
                ("diffRequestId", request_id.clone()),
                ("syntaxRequestId", Value::from("99")),
            ],
        ),
    );
    assert_eq!(cancel["accepted"], true);
    let stale = helper.ok(
        "repositorySessionDiffSyntaxPage",
        session_arguments(
            &open,
            5,
            &[(
                "request",
                object(&[
                    ("origin", Value::from("committed")),
                    ("diffRequestId", Value::from("999")),
                    ("syntaxRequestId", Value::from("3")),
                    ("offset", Value::from("0")),
                    ("maximumRows", Value::from(4)),
                ]),
            )],
        ),
    );
    assert_eq!(stale["failure"]["kind"], "staleGeneration", "{stale}");
}
