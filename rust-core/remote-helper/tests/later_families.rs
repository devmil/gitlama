//! Merge, cherry-pick, conflict resolution, the sequencer, snapshots, file restores,
//! patches and amends through the real helper: each is admitted once with a durable receipt,
//! needs its capability and reports an outcome its evidence supports.
#![cfg(unix)]
mod common;

use common::{git, object, Helper, Root};
use gitlama_application::wire::runtime::{self as w, Value};
use std::path::{Path, PathBuf};

const ALL: &[&str] = &[
    "read",
    "listDirectory",
    "stage",
    "commit",
    "refs",
    "stash",
    "transfer",
    "discard",
    "history",
    "recovery",
    "extensions",
];

struct Opened {
    session: Value,
}

impl Opened {
    fn arguments(&self, extra: &[(&str, Value)]) -> Value {
        let mut pairs = vec![
            ("sessionId", self.session.clone()),
            ("generation", Value::from("1")),
        ];
        pairs.extend(extra.iter().cloned());
        object(&pairs)
    }
}

fn open(helper: &mut Helper, repository: &Path) -> Opened {
    let open = helper.open(repository, 1);
    Opened {
        session: open["open"]["session"]["sessionId"].clone(),
    }
}

fn operation_id(seed: u8) -> String {
    format!("{seed:02x}").repeat(16)
}

/// A clean repository on `main` with a `topic` branch one commit ahead. With `conflicting`,
/// `main` changes the same line afterwards.
fn diverged(parent: &Path, conflicting: bool) -> PathBuf {
    let repository = parent.join("diverged");
    std::fs::create_dir_all(&repository).unwrap();
    git(&repository, &["init", "-q"]);
    git(&repository, &["config", "user.name", "Fixture"]);
    git(
        &repository,
        &["config", "user.email", "fixture@example.invalid"],
    );
    git(&repository, &["config", "commit.gpgsign", "false"]);
    std::fs::write(repository.join("a.txt"), b"base\n").unwrap();
    git(&repository, &["add", "."]);
    git(&repository, &["commit", "-qm", "base"]);
    git(&repository, &["checkout", "-qb", "topic"]);
    std::fs::write(repository.join("a.txt"), b"topic\n").unwrap();
    std::fs::write(repository.join("topic.txt"), b"topic only\n").unwrap();
    git(&repository, &["add", "."]);
    git(&repository, &["commit", "-qm", "topic change"]);
    git(&repository, &["checkout", "-q", "main"]);
    if conflicting {
        std::fs::write(repository.join("a.txt"), b"main\n").unwrap();
        git(&repository, &["commit", "-qam", "main change"]);
    }
    repository
}

fn history_request(kind: &str, target: &str, source: Option<&str>) -> Value {
    object(&[
        ("kind", Value::from(kind)),
        ("targets", Value::Array(vec![Value::from(target)])),
        (
            "sourceName",
            source.map_or(Value::Null, |name| w::bytes_e(name.as_bytes())),
        ),
        ("mergeMode", Value::from("noFastForward")),
        ("acknowledgePublishedHistory", Value::Bool(true)),
        ("noCommit", Value::Bool(false)),
    ])
}

/// Previews and executes a previewed family; returns the execution reply.
fn admit(
    helper: &mut Helper,
    opened: &Opened,
    family: &str,
    request: Value,
    operation: u8,
) -> Value {
    let preview = helper.ok(
        &format!("preview{family}"),
        opened.arguments(&[("request", request)]),
    );
    assert!(!preview["token"].is_null(), "{preview}");
    helper.ok(
        &format!("execute{family}"),
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(operation))),
        ]),
    )
}

/// Previews and executes a direct family, which carries its request again.
fn admit_direct(
    helper: &mut Helper,
    opened: &Opened,
    family: &str,
    request: &Value,
    operation: u8,
) -> Value {
    let preview = helper.ok(
        &format!("preview{family}"),
        opened.arguments(&[("request", request.clone())]),
    );
    helper.ok(
        &format!("execute{family}"),
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(operation))),
            ("request", request.clone()),
        ]),
    )
}

fn head(repository: &Path) -> String {
    git(repository, &["rev-parse", "HEAD"])
}

#[test]
fn later_capabilities_are_offered_with_the_store_and_required() {
    let home = Root::new("later-capability");
    let repository = diverged(&home.0, false);
    let mut helper = Helper::spawn(&home.0);
    let offered: Vec<&str> = helper.hello["capabilities"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c.as_str().unwrap())
        .collect();
    for capability in ["history", "recovery", "extensions"] {
        assert!(offered.contains(&capability), "{capability}");
    }
    helper.acknowledge(&["read", "refs"]);
    let opened = open(&mut helper, &repository);
    let topic = git(&repository, &["rev-parse", "topic"]);
    for (method, request) in [
        (
            "previewHistory",
            history_request("cherryPick", &topic, None),
        ),
        (
            "previewSnapshotRestore",
            object(&[("snapshotId", Value::from("1"))]),
        ),
        (
            "previewSequencer",
            object(&[("action", Value::from("abort")), ("message", Value::Null)]),
        ),
    ] {
        assert_eq!(
            helper.error_code(method, opened.arguments(&[("request", request)])),
            "writeNotPermitted",
            "{method}"
        );
    }
}

#[test]
fn a_cherry_pick_is_admitted_once() {
    let home = Root::new("later-cherry-pick");
    let repository = diverged(&home.0, false);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);
    let before = head(&repository);
    let topic = git(&repository, &["rev-parse", "topic"]);

    let picked = admit(
        &mut helper,
        &opened,
        "History",
        history_request("cherryPick", &topic, None),
        1,
    );
    assert_eq!(picked["operation"]["outcome"], "succeeded", "{picked}");
    assert_ne!(head(&repository), before);
    assert_eq!(
        std::fs::read(repository.join("topic.txt")).unwrap(),
        b"topic only\n"
    );
}

#[test]
fn a_conflicting_merge_is_partial_and_finishes_through_resolution_and_the_sequencer() {
    let home = Root::new("later-merge");
    let repository = diverged(&home.0, true);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);
    let topic = git(&repository, &["rev-parse", "topic"]);

    let merged = admit(
        &mut helper,
        &opened,
        "History",
        history_request("merge", &topic, Some("topic")),
        1,
    );
    assert_eq!(merged["operation"]["outcome"], "partial", "{merged}");
    assert_eq!(merged["result"]["state"], "conflict", "{merged}");

    let conflicts = helper.ok("repositorySessionConflicts", opened.arguments(&[]));
    let file = &conflicts["snapshot"]["files"][0];
    assert_eq!(file["path"], w::bytes_e(b"a.txt"), "{conflicts}");
    let choose = object(&[
        ("action", Value::from("chooseSide")),
        ("path", w::bytes_e(b"a.txt")),
        ("expectedFingerprint", file["fingerprint"].clone()),
        ("side", Value::from("incoming")),
        ("regionIndex", Value::Null),
        ("region", Value::Null),
        ("result", Value::Null),
    ]);
    let resolved = admit_direct(&mut helper, &opened, "Conflict", &choose, 2);
    assert_eq!(resolved["operation"]["outcome"], "succeeded", "{resolved}");
    assert_eq!(std::fs::read(repository.join("a.txt")).unwrap(), b"topic\n");

    let finish = object(&[
        ("action", Value::from("continue_")),
        ("message", Value::from("Merge topic")),
    ]);
    let finished = admit_direct(&mut helper, &opened, "Sequencer", &finish, 3);
    assert_eq!(finished["operation"]["outcome"], "succeeded", "{finished}");
    assert_eq!(
        git(&repository, &["rev-list", "--parents", "-n1", "HEAD"])
            .split(' ')
            .count(),
        3
    );
    assert!(git(&repository, &["status", "--porcelain"]).is_empty());
}

#[test]
fn snapshots_restores_patches_and_amends_are_admitted() {
    let home = Root::new("later-recovery");
    let repository = diverged(&home.0, true);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);
    let base = git(&repository, &["rev-parse", "main~1"]);

    // A snapshot of a local change, then deleted again.
    std::fs::write(repository.join("a.txt"), b"draft\n").unwrap();
    let create = object(&[
        ("action", Value::from("create")),
        ("name", Value::from("draft")),
        ("includeUntracked", Value::Bool(false)),
        ("keepIndex", Value::Bool(false)),
        ("snapshotId", Value::Null),
        ("branch", Value::Null),
    ]);
    let created = admit_direct(&mut helper, &opened, "Snapshot", &create, 1);
    assert_eq!(created["operation"]["outcome"], "succeeded", "{created}");
    let id = created["result"]["snapshot"]["id"].clone();
    let listed = helper.ok(
        "repositorySessionNamedSnapshots",
        opened.arguments(&[("offset", Value::from(0)), ("maximum", Value::from(10))]),
    );
    assert_eq!(listed["entries"][0]["name"], "draft", "{listed}");
    let delete = object(&[
        ("action", Value::from("delete")),
        ("name", Value::Null),
        ("includeUntracked", Value::Bool(false)),
        ("keepIndex", Value::Bool(false)),
        ("snapshotId", id),
        ("branch", Value::Null),
    ]);
    let deleted = admit_direct(&mut helper, &opened, "Snapshot", &delete, 2);
    assert_eq!(deleted["operation"]["outcome"], "succeeded", "{deleted}");
    git(&repository, &["checkout", "--", "a.txt"]);

    // A file restored from an older commit.
    let restore = object(&[
        ("commit", Value::from(base.as_str())),
        ("path", w::bytes_e(b"a.txt")),
        ("byteLimit", Value::from(1_048_576)),
    ]);
    let restored = admit(&mut helper, &opened, "Restore", restore, 3);
    assert_eq!(restored["operation"]["outcome"], "succeeded", "{restored}");
    assert_eq!(std::fs::read(repository.join("a.txt")).unwrap(), b"base\n");
    git(&repository, &["checkout", "--", "a.txt"]);

    // A patch from this computer, kept privately on the host only until it is applied.
    let patch =
        b"diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n-main\n+patched\n";
    let applied = admit(
        &mut helper,
        &opened,
        "Patch",
        object(&[("content", w::bytes_e(patch))]),
        4,
    );
    assert_eq!(applied["operation"]["outcome"], "succeeded", "{applied}");
    assert_eq!(
        std::fs::read(repository.join("a.txt")).unwrap(),
        b"patched\n"
    );
    let kept = home.0.join(".local/state/gitlama/remote-helper/patches");
    assert_eq!(std::fs::read_dir(kept).unwrap().count(), 0);

    // An amend replaces HEAD, keeping its parent.
    git(&repository, &["add", "a.txt"]);
    let parent = git(&repository, &["rev-parse", "HEAD~1"]);
    let amend = object(&[
        ("subject", Value::from("main change, amended")),
        ("description", Value::from("")),
        ("coauthors", Value::Array(Vec::new())),
        ("author", Value::Null),
        ("amend", Value::Bool(true)),
        ("skipHooks", Value::Bool(true)),
        ("signing", Value::from("disable")),
        ("signOff", Value::Bool(false)),
    ]);
    let amended = admit(&mut helper, &opened, "Commit", amend, 5);
    assert_eq!(amended["operation"]["outcome"], "succeeded", "{amended}");
    assert_eq!(git(&repository, &["rev-parse", "HEAD~1"]), parent);
    assert_eq!(
        git(&repository, &["log", "-1", "--format=%s"]),
        "main change, amended"
    );
}
