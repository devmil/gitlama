//! Durable write admission through the real helper: receipts, duplicates, previews, the normal
//! commit policy, hooks, lookups from a new connection and a helper killed mid-operation.
#![cfg(unix)]
mod common;

use common::{git, object, ordinary_repository, Helper, Root};
use gitlama_application::wire::runtime::{self as w, Value};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::time::Duration;

const ALL: &[&str] = &["read", "listDirectory", "stage", "commit"];

struct Opened {
    session: Value,
    generation: u64,
}

impl Opened {
    fn arguments(&self, extra: &[(&str, Value)]) -> Value {
        let mut pairs = vec![
            ("sessionId", self.session.clone()),
            ("generation", Value::from(self.generation.to_string())),
        ];
        pairs.extend(extra.iter().cloned());
        object(&pairs)
    }
}

fn open(helper: &mut Helper, repository: &Path, generation: u64) -> Opened {
    let open = helper.open(repository, generation);
    Opened {
        session: open["open"]["session"]["sessionId"].clone(),
        generation,
    }
}

/// Loads the unstaged diff and returns the staging request for `path`.
fn stage_request(helper: &mut Helper, opened: &Opened, path: &[u8]) -> Value {
    let diff = helper.ok(
        "repositorySessionWorkingDiffLoad",
        opened.arguments(&[(
            "options",
            object(&[
                ("side", Value::from("unstaged")),
                ("oldPath", Value::Null),
                ("newPath", Value::Null),
                ("contextLines", Value::from(3)),
                ("whitespace", Value::from("preserve")),
                ("layout", Value::from("unified")),
                ("maximumRows", Value::from(256)),
                ("forceText", Value::from(false)),
            ]),
        )]),
    );
    assert!(diff["failure"].is_null(), "{diff}");
    object(&[
        ("requestId", diff["page"]["requestId"].clone()),
        ("side", Value::from("unstaged")),
        ("scope", Value::from("files")),
        ("paths", Value::Array(vec![w::bytes_e(path)])),
        ("rowIds", Value::Array(Vec::new())),
    ])
}

fn commit_request(subject: &str) -> Value {
    object(&[
        ("subject", Value::from(subject)),
        ("description", Value::from("")),
        ("coauthors", Value::Array(Vec::new())),
        ("author", Value::Null),
        ("amend", Value::Bool(false)),
        ("skipHooks", Value::Bool(false)),
        ("signing", Value::from("useGitConfiguration")),
        ("signOff", Value::Bool(false)),
    ])
}

fn operation_id(seed: u8) -> String {
    format!("{seed:02x}").repeat(16)
}

fn receipt_path(home: &Path, epoch: &str, operation: &str) -> std::path::PathBuf {
    home.join(".local/state/gitlama/remote-helper/receipts")
        .join(epoch)
        .join(format!("{operation}.json"))
}

#[test]
fn write_capabilities_are_offered_only_with_a_usable_store() {
    let home = Root::new("writes-offer");
    let helper = Helper::spawn(&home.0);
    let capabilities: Vec<&str> = helper.hello["capabilities"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c.as_str().unwrap())
        .collect();
    assert!(capabilities.contains(&"stage") && capabilities.contains(&"commit"));
    drop(helper);
    // A store that cannot be created offers reads only.
    let blocked = Root::new("writes-blocked");
    std::fs::write(blocked.0.join(".local"), b"not a directory").unwrap();
    let helper = Helper::spawn(&blocked.0);
    assert_eq!(helper.hello["store"]["state"], "unavailable");
    let capabilities = helper.hello["capabilities"].as_array().unwrap();
    assert!(!capabilities.iter().any(|c| c == "stage" || c == "commit"));
}

#[test]
fn staging_is_admitted_once_with_a_durable_receipt() {
    let home = Root::new("writes-stage");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository, 1);
    let request = stage_request(&mut helper, &opened, b"README.md");
    let preview = helper.ok(
        "previewStage",
        opened.arguments(&[("request", request.clone())]),
    );
    let token = preview["token"].as_str().unwrap().to_owned();
    let epoch = preview["epoch"].as_str().unwrap().to_owned();
    let digest = preview["digest"].as_str().unwrap().to_owned();
    assert_eq!(preview["expiresInMs"], "120000");
    let execute = |helper: &mut Helper, operation: &str, request: &Value| {
        helper.call(
            "executeStage",
            opened.arguments(&[
                ("token", Value::from(token.clone())),
                ("epoch", Value::from(epoch.clone())),
                ("digest", Value::from(digest.clone())),
                ("operationId", Value::from(operation)),
                ("request", request.clone()),
            ]),
        )
    };
    let first = execute(&mut helper, &operation_id(1), &request);
    let operation = &first["ok"]["operation"];
    assert_eq!(operation["state"], "terminal", "{first}");
    assert_eq!(operation["outcome"], "succeeded");
    assert_eq!(first["ok"]["result"]["state"], "completed");
    assert!(git(&repository, &["diff", "--cached", "--name-only"]).contains("README.md"));
    let receipt = std::fs::read(receipt_path(&home.0, &epoch, &operation_id(1))).unwrap();
    let receipt = w::parse(&receipt, w::ParseLimits::FRAME).unwrap();
    assert_eq!(receipt["state"], "terminal");
    assert_ne!(
        receipt["evidence"]["indexBefore"],
        receipt["evidence"]["indexAfter"]
    );

    // The same operation again is answered from its receipt without executing.
    let duplicate = execute(&mut helper, &operation_id(1), &request);
    assert_eq!(duplicate["ok"]["operation"]["outcome"], "succeeded");
    assert!(duplicate["ok"]["result"].is_null());
    // The token was consumed by the first execution.
    assert_eq!(
        execute(&mut helper, &operation_id(2), &request)["error"]["code"],
        "previewExpired"
    );
    // A known identifier with different intent is a conflict, never a second execution.
    let other = helper.call(
        "executeStage",
        opened.arguments(&[
            ("token", Value::from(token.clone())),
            ("epoch", Value::from(epoch.clone())),
            ("digest", Value::from("0".repeat(64))),
            ("operationId", Value::from(operation_id(1))),
            ("request", request.clone()),
        ]),
    );
    assert_eq!(other["error"]["code"], "operationIdConflict");
}

#[test]
fn a_changed_request_does_not_match_its_preview() {
    let home = Root::new("writes-digest");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository, 1);
    let request = stage_request(&mut helper, &opened, b"README.md");
    let preview = helper.ok(
        "previewStage",
        opened.arguments(&[("request", request.clone())]),
    );
    let mut changed = request.clone();
    changed["paths"] = Value::Array(vec![w::bytes_e(b"src.txt")]);
    let refused = helper.call(
        "executeStage",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(3))),
            ("request", changed),
        ]),
    );
    assert_eq!(refused["error"]["code"], "preconditionFailed");
    assert!(!git(&repository, &["diff", "--cached", "--name-only"]).contains("README.md"));
    // A preview from another connection is unknown here.
    let mut other = Helper::spawn(&home.0);
    other.acknowledge(ALL);
    let elsewhere = open(&mut other, &repository, 1);
    let foreign = other.call(
        "executeStage",
        elsewhere.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(4))),
            ("request", request),
        ]),
    );
    assert_eq!(foreign["error"]["code"], "previewExpired");
}

#[test]
fn normal_commits_use_the_remote_environment_and_report_their_commit() {
    let home = Root::new("writes-commit");
    let repository = ordinary_repository(&home.0);
    git(&repository, &["config", "user.name", "Remote Person"]);
    git(
        &repository,
        &["config", "user.email", "remote@example.invalid"],
    );
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository, 1);
    for (field, value) in [
        ("amend", Value::Bool(true)),
        ("skipHooks", Value::Bool(true)),
        ("signing", Value::from("disable")),
    ] {
        // The user's explicit choices are previewed on the host as here.
        let mut request = commit_request("chosen");
        request[field] = value;
        let preview = helper.ok("previewCommit", opened.arguments(&[("request", request)]));
        assert!(
            preview["preview"]["failure"].is_null(),
            "{field}: {preview}"
        );
        assert!(!preview["token"].is_null(), "{field}");
    }
    // A message too large for one commit is still refused.
    let mut oversized = commit_request("x");
    oversized["description"] = Value::from("x".repeat(1024 * 1024 + 1));
    assert_eq!(
        helper.error_code("previewCommit", opened.arguments(&[("request", oversized)])),
        "invalidRequest"
    );
    let subject = "Remote commit with $(metacharacters) and \"quotes\"";
    let preview = helper.ok(
        "previewCommit",
        opened.arguments(&[("request", commit_request(subject))]),
    );
    assert!(preview["preview"]["failure"].is_null(), "{preview}");
    let executed = helper.ok(
        "executeCommit",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(5))),
        ]),
    );
    assert_eq!(executed["operation"]["outcome"], "succeeded", "{executed}");
    let head = git(&repository, &["rev-parse", "HEAD"]);
    assert_eq!(executed["operation"]["resultObjectId"], head.as_str());
    assert_eq!(git(&repository, &["log", "-1", "--format=%s"]), subject);
    assert_eq!(
        git(&repository, &["log", "-1", "--format=%an"]),
        "Remote Person"
    );
    assert_eq!(git(&repository, &["rev-list", "--count", "HEAD"]), "3");

    // A new connection looks the operation up without its expired token.
    drop(helper);
    let mut reconnected = Helper::spawn(&home.0);
    reconnected.acknowledge(ALL);
    let lookup = reconnected.ok(
        "lookupOperation",
        object(&[
            ("epoch", preview["epoch"].clone()),
            ("operationId", Value::from(operation_id(5))),
            ("digest", preview["digest"].clone()),
        ]),
    );
    assert_eq!(lookup["operation"]["state"], "terminal");
    assert_eq!(lookup["operation"]["outcome"], "succeeded");
    let absent = reconnected.ok(
        "lookupOperation",
        object(&[
            ("epoch", preview["epoch"].clone()),
            ("operationId", Value::from(operation_id(6))),
            ("digest", preview["digest"].clone()),
        ]),
    );
    assert_eq!(absent["operation"]["state"], "absent");
    assert_eq!(absent["operation"]["outcome"], "unknown");
    assert_eq!(git(&repository, &["rev-list", "--count", "HEAD"]), "3");
}

#[test]
fn a_rejecting_hook_leaves_head_and_reports_failure() {
    let home = Root::new("writes-hook");
    let repository = ordinary_repository(&home.0);
    let hook = repository.join(".git/hooks/pre-commit");
    std::fs::write(&hook, b"#!/bin/sh\necho rejected >&2\nexit 1\n").unwrap();
    std::os::unix::fs::PermissionsExt::set_mode(
        &mut std::fs::metadata(&hook).unwrap().permissions(),
        0o755,
    );
    std::fs::set_permissions(&hook, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    let head = git(&repository, &["rev-parse", "HEAD"]);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository, 1);
    let preview = helper.ok(
        "previewCommit",
        opened.arguments(&[("request", commit_request("hooked"))]),
    );
    let executed = helper.ok(
        "executeCommit",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(7))),
        ]),
    );
    assert_eq!(executed["operation"]["outcome"], "failed", "{executed}");
    assert_eq!(git(&repository, &["rev-parse", "HEAD"]), head);
}

#[test]
fn a_helper_killed_mid_commit_leaves_an_unknown_outcome_and_no_replay() {
    let home = Root::new("writes-kill");
    let repository = ordinary_repository(&home.0);
    let hook = repository.join(".git/hooks/pre-commit");
    let marker = home.0.join("hook-ran");
    std::fs::write(
        &hook,
        format!("#!/bin/sh\ntouch '{}'\nsleep 3\n", marker.display()).as_bytes(),
    )
    .unwrap();
    std::fs::set_permissions(&hook, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository, 1);
    let preview = helper.ok(
        "previewCommit",
        opened.arguments(&[("request", commit_request("killed"))]),
    );
    helper.send_call(
        "executeCommit",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(8))),
        ]),
    );
    let started = std::time::Instant::now();
    while !marker.exists() && started.elapsed() < Duration::from_secs(20) {
        std::thread::sleep(Duration::from_millis(20));
    }
    assert!(marker.exists(), "the hook started");
    helper.child.kill().unwrap();
    helper.child.wait().unwrap();
    let mut reconnected = Helper::spawn(&home.0);
    reconnected.acknowledge(ALL);
    let lookup = reconnected.ok(
        "lookupOperation",
        object(&[
            ("epoch", preview["epoch"].clone()),
            ("operationId", Value::from(operation_id(8))),
            ("digest", preview["digest"].clone()),
        ]),
    );
    assert_eq!(lookup["operation"]["state"], "started");
    assert_eq!(lookup["operation"]["outcome"], "unknown");
    // Executing the same operation again returns the receipt instead of committing.
    let opened = open(&mut reconnected, &repository, 1);
    let again = reconnected.ok(
        "executeCommit",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(8))),
        ]),
    );
    assert_eq!(again["operation"]["state"], "started");
    assert!(again["result"].is_null());
}

#[test]
fn writes_need_their_negotiated_capability() {
    let home = Root::new("writes-capability");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read"]);
    let opened = open(&mut helper, &repository, 1);
    assert_eq!(
        helper.error_code(
            "previewCommit",
            opened.arguments(&[("request", commit_request("x"))])
        ),
        "writeNotPermitted"
    );
    assert_eq!(
        helper.error_code(
            "lookupOperation",
            object(&[
                ("epoch", Value::from("0".repeat(32))),
                ("operationId", Value::from(operation_id(9))),
                ("digest", Value::from("0".repeat(64))),
            ])
        ),
        "writeNotPermitted"
    );
}

/// What a fresh helper reports after the first one died at `boundary`, and the effect count.
struct Crash {
    lookup: Value,
    repository: std::path::PathBuf,
    _home: Root,
}

fn crash_at(boundary: &str, family: &str) -> Crash {
    let home = Root::new(&format!("crash-{family}-{boundary}"));
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn_with(&home.0, &[("GITLAMA_HELPER_FAULT", boundary)]);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository, 1);
    let operation = operation_id(0x42);
    let (preview, execute) = if family == "stage" {
        let request = stage_request(&mut helper, &opened, b"README.md");
        let preview = helper.ok(
            "previewStage",
            opened.arguments(&[("request", request.clone())]),
        );
        let execute = opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation.clone())),
            ("request", request),
        ]);
        (preview, ("executeStage", execute))
    } else {
        let preview = helper.ok(
            "previewCommit",
            opened.arguments(&[("request", commit_request("crash"))]),
        );
        let execute = opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation.clone())),
        ]);
        (preview, ("executeCommit", execute))
    };
    helper.send_call(execute.0, execute.1.clone());
    let status = helper
        .wait_exit(Duration::from_secs(30))
        .expect("the faulted helper exits");
    assert!(!status.success(), "{boundary} aborts the helper");
    let mut fresh = Helper::spawn(&home.0);
    fresh.acknowledge(ALL);
    let lookup = fresh.ok(
        "lookupOperation",
        object(&[
            ("epoch", preview["epoch"].clone()),
            ("operationId", Value::from(operation.clone())),
            ("digest", preview["digest"].clone()),
        ]),
    );
    // Executing the same operation again never runs Git a second time.
    let reopened = open(&mut fresh, &repository, 1);
    let mut again = execute.1.clone();
    again["sessionId"] = reopened.session.clone();
    let repeated = fresh.ok(execute.0, again);
    assert!(
        repeated["result"].is_null(),
        "{boundary}: no second execution"
    );
    Crash {
        lookup: lookup["operation"].clone(),
        repository,
        _home: home,
    }
}

fn staged(repository: &Path) -> bool {
    git(repository, &["diff", "--cached", "--name-only"]).contains("README.md")
}

fn commits(repository: &Path) -> String {
    git(repository, &["rev-list", "--count", "HEAD"])
}

#[test]
fn fault_matrix_stage() {
    let prepared = crash_at("after-prepared", "stage");
    assert_eq!(prepared.lookup["state"], "prepared");
    assert_eq!(prepared.lookup["outcome"], "notApplied");
    assert!(!staged(&prepared.repository));

    let started = crash_at("after-started", "stage");
    assert_eq!(started.lookup["state"], "started");
    assert_eq!(started.lookup["outcome"], "unknown");
    assert!(!staged(&started.repository), "Git never ran");

    let effect = crash_at("before-terminal", "stage");
    assert_eq!(effect.lookup["state"], "started");
    assert_eq!(
        effect.lookup["outcome"], "unknown",
        "the effect exists but is not proven"
    );
    assert!(staged(&effect.repository));

    let terminal = crash_at("after-terminal", "stage");
    assert_eq!(terminal.lookup["state"], "terminal");
    assert_eq!(terminal.lookup["outcome"], "succeeded");
    assert!(staged(&terminal.repository));
}

#[test]
fn fault_matrix_commit() {
    // The ordinary fixture has two commits and a staged file.
    let prepared = crash_at("after-prepared", "commit");
    assert_eq!(prepared.lookup["outcome"], "notApplied");
    assert_eq!(commits(&prepared.repository), "2");

    let started = crash_at("after-started", "commit");
    assert_eq!(started.lookup["outcome"], "unknown");
    assert_eq!(commits(&started.repository), "2");

    let effect = crash_at("before-terminal", "commit");
    assert_eq!(effect.lookup["outcome"], "unknown");
    assert_eq!(
        commits(&effect.repository),
        "3",
        "exactly one commit, never replayed"
    );

    let terminal = crash_at("after-terminal", "commit");
    assert_eq!(terminal.lookup["outcome"], "succeeded");
    assert_eq!(
        terminal.lookup["resultObjectId"],
        git(&terminal.repository, &["rev-parse", "HEAD"]).as_str()
    );
    assert_eq!(commits(&terminal.repository), "3");
}

/// Loads the unstaged working diff and returns its page.
fn working_diff(helper: &mut Helper, opened: &Opened) -> Value {
    let diff = helper.ok(
        "repositorySessionWorkingDiffLoad",
        opened.arguments(&[(
            "options",
            object(&[
                ("side", Value::from("unstaged")),
                ("oldPath", Value::Null),
                ("newPath", Value::Null),
                ("contextLines", Value::from(3)),
                ("whitespace", Value::from("preserve")),
                ("layout", Value::from("unified")),
                ("maximumRows", Value::from(256)),
                ("forceText", Value::from(false)),
            ]),
        )]),
    );
    assert!(diff["failure"].is_null(), "{diff}");
    diff["page"].clone()
}

/// Previews and executes one staging request; returns the operation object.
fn stage(helper: &mut Helper, opened: &Opened, request: &Value, operation: u8) -> Value {
    let preview = helper.ok(
        "previewStage",
        opened.arguments(&[("request", request.clone())]),
    );
    helper.ok(
        "executeStage",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(operation))),
            ("request", request.clone()),
        ]),
    )
}

#[test]
fn selected_lines_stage_exactly_their_bytes() {
    let home = Root::new("writes-lines");
    let repository = ordinary_repository(&home.0);
    std::fs::write(repository.join("README.md"), b"hello\n").unwrap();
    std::fs::write(repository.join("src.txt"), b"ONE\n2\nTHREE\n").unwrap();
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository, 1);
    let page = working_diff(&mut helper, &opened);
    let rows = page["rows"].as_array().unwrap();
    // The first deleted and the first added line: `one` → `ONE`.
    let pick = |kind: &str| {
        rows.iter()
            .find(|row| row["kind"] == kind && row["selectable"] == true)
            .map(|row| row["stableId"].clone())
            .unwrap()
    };
    let request = object(&[
        ("requestId", page["requestId"].clone()),
        ("side", Value::from("unstaged")),
        ("scope", Value::from("rows")),
        ("paths", Value::Array(Vec::new())),
        (
            "rowIds",
            Value::Array(vec![pick("deletion"), pick("addition")]),
        ),
    ]);
    let executed = stage(&mut helper, &opened, &request, 0x21);
    assert_eq!(executed["operation"]["outcome"], "succeeded", "{executed}");
    assert_eq!(git(&repository, &["show", ":src.txt"]), "ONE\n2\nthree");
    assert_eq!(
        std::fs::read(repository.join("src.txt")).unwrap(),
        b"ONE\n2\nTHREE\n"
    );
}

#[test]
fn an_index_changed_after_the_diff_is_not_staged_over() {
    let home = Root::new("writes-stale");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository, 1);
    let request = stage_request(&mut helper, &opened, b"README.md");
    let preview = helper.ok(
        "previewStage",
        opened.arguments(&[("request", request.clone())]),
    );
    // Another Git client stages something else between preview and execution.
    std::fs::write(repository.join("src.txt"), b"external\n").unwrap();
    git(&repository, &["add", "src.txt"]);
    let executed = helper.ok(
        "executeStage",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(0x22))),
            ("request", request),
        ]),
    );
    assert_eq!(executed["operation"]["outcome"], "notApplied", "{executed}");
    let staged = git(&repository, &["diff", "--cached", "--name-only"]);
    assert!(
        !staged.contains("README.md"),
        "the reviewed bytes are stale"
    );
    assert!(staged.contains("src.txt"), "the external change stays");
}

#[test]
fn untracked_non_utf8_paths_stage_by_exact_bytes() {
    let home = Root::new("writes-bytes");
    let repository = ordinary_repository(&home.0);
    std::fs::write(repository.join("README.md"), b"hello\n").unwrap();
    let name: &[u8] = b"caf\xe9 \"quoted\" -dash.txt";
    match std::fs::write(
        repository.join(std::ffi::OsStr::from_bytes(name)),
        b"bytes\n",
    ) {
        Ok(()) => {}
        // APFS refuses names that are not UTF-8 (EILSEQ), so no such path can exist there.
        Err(error) if error.raw_os_error() == Some(92) && cfg!(target_os = "macos") => return,
        Err(error) => panic!("{error}"),
    }
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository, 1);
    // Untracked files come from the loaded status, as in the application.
    wait_ready(&mut helper);
    let request = stage_request(&mut helper, &opened, name);
    let executed = stage(&mut helper, &opened, &request, 0x23);
    assert_eq!(executed["operation"]["outcome"], "succeeded", "{executed}");
    let listed = std::process::Command::new("git")
        .args(["ls-files", "-z", "--cached"])
        .current_dir(&repository)
        .output()
        .unwrap()
        .stdout;
    assert!(listed.split(|byte| *byte == 0).any(|entry| entry == name));
}

#[test]
fn noisy_hooks_succeed_with_bounded_output() {
    let home = Root::new("writes-noisy");
    let repository = ordinary_repository(&home.0);
    let hook = repository.join(".git/hooks/pre-commit");
    std::fs::write(
        &hook,
        b"#!/bin/sh\nhead -c 6000000 /dev/zero | tr '\\0' x\nhead -c 6000000 /dev/zero | tr '\\0' y >&2\nexit 0\n",
    )
    .unwrap();
    std::fs::set_permissions(&hook, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository, 1);
    let preview = helper.ok(
        "previewCommit",
        opened.arguments(&[("request", commit_request("noisy"))]),
    );
    let executed = helper.ok(
        "executeCommit",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(0x24))),
        ]),
    );
    assert_eq!(executed["operation"]["outcome"], "succeeded", "{executed}");
    let output: usize = executed["result"]["output"]
        .as_array()
        .unwrap()
        .iter()
        .map(|line| line.as_str().unwrap().len())
        .sum();
    assert!(
        output < 1024 * 1024,
        "hook output is bounded ({output} bytes)"
    );
}

/// Waits until a session publishes a ready snapshot with its status.
fn wait_ready(helper: &mut Helper) {
    loop {
        let envelope = helper.next().expect("a ready snapshot");
        if envelope["kind"] == "publication"
            && envelope["payload"]["events"]["events"]
                .as_array()
                .unwrap()
                .iter()
                .any(|event| event["snapshot"]["phase"] == "ready")
        {
            return;
        }
    }
}
