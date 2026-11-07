//! Ref changes, stashes and transfers through the real helper: each family is admitted once with
//! a durable receipt, needs its own capability and reports an outcome its evidence supports.
#![cfg(unix)]
mod common;

use common::{git, object, ordinary_repository, Helper, Root};
use gitlama_application::wire::runtime::{self as w, Value};
use std::path::Path;
use std::time::Duration;

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

fn open(helper: &mut Helper, repository: &Path) -> Opened {
    let open = helper.open(repository, 1);
    Opened {
        session: open["open"]["session"]["sessionId"].clone(),
        generation: 1,
    }
}

fn operation_id(seed: u8) -> String {
    format!("{seed:02x}").repeat(16)
}

fn text(value: Option<&str>) -> Value {
    value.map_or(Value::Null, Value::from)
}

fn refs_request(kind: &str, name: Option<&str>, target: Option<&str>) -> Value {
    object(&[
        ("kind", Value::from(kind)),
        ("name", text(name)),
        ("secondName", Value::Null),
        ("target", text(target)),
        ("message", Value::Null),
        ("url", Value::Null),
        ("force", Value::Bool(false)),
        ("resetMode", Value::Null),
        ("checkout", Value::Bool(false)),
    ])
}

/// A stash entry is named by its selector and object, so a moved entry is never touched.
fn stash_request(kind: &str, entry: Option<(&str, &str)>) -> Value {
    object(&[
        ("kind", Value::from(kind)),
        ("message", text((kind == "push").then_some("remote stash"))),
        ("selector", text(entry.map(|(selector, _)| selector))),
        ("objectId", text(entry.map(|(_, object)| object))),
        ("paths", Value::Array(Vec::new())),
        ("includeUntracked", Value::Bool(false)),
        ("keepIndex", Value::Bool(false)),
        ("targetBranch", Value::Null),
    ])
}

fn transfer_request(kind: &str, remote: &str, branch: Option<&str>) -> Value {
    object(&[
        ("kind", Value::from(kind)),
        ("remote", Value::from(remote)),
        ("branch", text(branch)),
        ("pullStrategy", Value::from("fastForwardOnly")),
        ("allowDirty", Value::Bool(false)),
        ("stashBeforePull", Value::Bool(false)),
        ("forceWithLease", Value::Bool(false)),
        ("setUpstream", Value::Bool(false)),
        ("refetch", Value::Bool(false)),
        ("prune", Value::Bool(true)),
    ])
}

fn discard_request(kind: &str, path: &[u8]) -> Value {
    object(&[
        ("kind", Value::from(kind)),
        ("scope", Value::from("files")),
        ("workingDiffRequestId", Value::Null),
        ("paths", Value::Array(vec![w::bytes_e(path)])),
        ("rowIds", Value::Array(Vec::new())),
    ])
}

/// Previews `request` with `family` and executes it as `operation`; returns the preview and the
/// execution reply.
fn admit(
    helper: &mut Helper,
    opened: &Opened,
    family: &str,
    request: Value,
    operation: u8,
) -> (Value, Value) {
    let preview = helper.ok(
        &format!("preview{family}"),
        opened.arguments(&[("request", request)]),
    );
    assert!(preview["preview"]["failure"].is_null(), "{preview}");
    assert!(!preview["token"].is_null(), "{preview}");
    let executed = helper.ok(
        &format!("execute{family}"),
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(operation))),
        ]),
    );
    (preview, executed)
}

fn head(repository: &Path) -> String {
    git(repository, &["rev-parse", "HEAD"])
}

#[test]
fn ref_stash_and_transfer_capabilities_are_offered_with_the_store() {
    let home = Root::new("family-offer");
    let helper = Helper::spawn(&home.0);
    let capabilities: Vec<&str> = helper.hello["capabilities"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c.as_str().unwrap())
        .collect();
    for family in ["refs", "stash", "transfer", "discard"] {
        assert!(capabilities.contains(&family), "{family}");
    }
}

#[test]
fn each_family_needs_its_own_capability() {
    let home = Root::new("family-capability");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read", "stage", "commit"]);
    let opened = open(&mut helper, &repository);
    let commit = head(&repository);
    for (method, request) in [
        (
            "previewRefs",
            refs_request("createBranch", Some("x"), Some(&commit)),
        ),
        ("previewStash", stash_request("push", None)),
        ("previewTransfer", transfer_request("fetch", "origin", None)),
        ("previewDiscard", discard_request("discard", b"README.md")),
    ] {
        assert_eq!(
            helper.error_code(method, opened.arguments(&[("request", request)])),
            "writeNotPermitted",
            "{method}"
        );
    }
}

#[test]
fn exact_commit_checkout_and_stash_choices_cross_the_remote_wire() {
    for mode in [
        "checkoutCommit",
        "stashCheckoutCommit",
        "autoStashCheckoutCommit",
    ] {
        let home = Root::new("family-detached-checkout");
        let repository = ordinary_repository(&home.0);
        let mut helper = Helper::spawn(&home.0);
        helper.acknowledge(ALL);
        let opened = open(&mut helper, &repository);
        let target = head(&repository);
        let branch_head = git(&repository, &["rev-parse", "main"]);
        let (family, request) = if mode == "checkoutCommit" {
            ("Refs", refs_request(mode, None, Some(&target)))
        } else {
            let mut request = stash_request(mode, None);
            request["objectId"] = Value::from(target.clone());
            ("Stash", request)
        };
        let (_, result) = admit(&mut helper, &opened, family, request, 1);
        assert_eq!(
            result["operation"]["outcome"], "succeeded",
            "{mode}: {result}"
        );
        assert_eq!(git(&repository, &["rev-parse", "HEAD"]), target);
        assert!(git(&repository, &["branch", "--show-current"]).is_empty());
        assert_eq!(git(&repository, &["rev-parse", "main"]), branch_head);
        assert_eq!(
            git(&repository, &["stash", "list"]).is_empty(),
            mode != "stashCheckoutCommit"
        );
    }
}

#[test]
fn branches_tags_and_resets_are_admitted_once() {
    let home = Root::new("family-refs");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);
    let commit = head(&repository);

    // A reset names its mode, and only a reset has one.
    assert_eq!(
        helper.error_code(
            "previewRefs",
            opened.arguments(&[(
                "request",
                refs_request("reset", Some("main"), Some(&commit))
            )])
        ),
        "invalidRequest"
    );
    let mut moded = refs_request("createBranch", Some("x"), Some(&commit));
    moded["resetMode"] = Value::from("hard");
    assert_eq!(
        helper.error_code("previewRefs", opened.arguments(&[("request", moded)])),
        "invalidRequest"
    );

    let (preview, created) = admit(
        &mut helper,
        &opened,
        "Refs",
        refs_request("createBranch", Some("feature"), Some(&commit)),
        1,
    );
    assert_eq!(created["operation"]["outcome"], "succeeded", "{created}");
    assert_eq!(git(&repository, &["rev-parse", "feature"]), commit);

    // The same operation again answers from its receipt without running Git.
    let again = helper.ok(
        "executeRefs",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(1))),
        ]),
    );
    assert_eq!(again["operation"]["outcome"], "succeeded");
    assert!(again["result"].is_null());

    let (_, tagged) = admit(
        &mut helper,
        &opened,
        "Refs",
        refs_request("createTag", Some("v1"), Some(&commit)),
        2,
    );
    assert_eq!(tagged["operation"]["outcome"], "succeeded", "{tagged}");
    assert_eq!(git(&repository, &["rev-parse", "v1^{commit}"]), commit);

    // Switching keeps the local changes: the new branch is at HEAD.
    let (_, switched) = admit(
        &mut helper,
        &opened,
        "Refs",
        refs_request("checkoutBranch", Some("feature"), None),
        3,
    );
    assert_eq!(switched["operation"]["outcome"], "succeeded", "{switched}");
    assert_eq!(
        git(&repository, &["symbolic-ref", "HEAD"]),
        "refs/heads/feature"
    );
    assert!(git(&repository, &["status", "--porcelain"]).contains("README.md"));

    // A hard reset to the parent discards the local changes on the host, as it would here.
    let parent = git(&repository, &["rev-parse", "HEAD~1"]);
    let mut reset = refs_request("reset", Some("feature"), Some(&parent));
    reset["resetMode"] = Value::from("hard");
    let (_, reset) = admit(&mut helper, &opened, "Refs", reset, 4);
    assert_eq!(reset["operation"]["outcome"], "succeeded", "{reset}");
    assert_eq!(head(&repository), parent);
    assert!(git(&repository, &["status", "--porcelain"]).is_empty());
}

#[test]
fn a_branch_created_after_its_preview_is_not_applied() {
    let home = Root::new("family-refs-stale");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);
    let commit = head(&repository);
    let preview = helper.ok(
        "previewRefs",
        opened.arguments(&[(
            "request",
            refs_request("createBranch", Some("late"), Some(&commit)),
        )]),
    );
    git(&repository, &["branch", "late", "HEAD~1"]);
    let executed = helper.ok(
        "executeRefs",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(4))),
        ]),
    );
    assert_eq!(executed["operation"]["outcome"], "notApplied", "{executed}");
    assert_eq!(
        git(&repository, &["rev-parse", "late"]),
        git(&repository, &["rev-parse", "HEAD~1"])
    );
}

#[test]
fn a_conflicting_pop_is_partial_and_keeps_the_stash() {
    let home = Root::new("family-stash");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);

    let (_, pushed) = admit(
        &mut helper,
        &opened,
        "Stash",
        stash_request("push", None),
        5,
    );
    assert_eq!(pushed["operation"]["outcome"], "succeeded", "{pushed}");
    assert_eq!(git(&repository, &["stash", "list"]).lines().count(), 1);
    assert_eq!(git(&repository, &["status", "--porcelain"]), "");

    // A commit on the same line makes the stashed change conflict.
    std::fs::write(repository.join("README.md"), b"hello\ncommitted\n").unwrap();
    git(&repository, &["commit", "-qam", "conflicting"]);
    let stashed = git(&repository, &["rev-parse", "stash@{0}"]);
    let (_, popped) = admit(
        &mut helper,
        &opened,
        "Stash",
        stash_request("pop", Some(("stash@{0}", &stashed))),
        6,
    );
    assert_eq!(popped["operation"]["outcome"], "partial", "{popped}");
    assert_eq!(popped["result"]["stashRetained"], true, "{popped}");
    assert_eq!(git(&repository, &["stash", "list"]).lines().count(), 1);
}

#[test]
fn discard_and_clean_are_admitted_once_and_a_changed_file_is_kept() {
    let home = Root::new("family-discard");
    let repository = ordinary_repository(&home.0);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);

    let (preview, discarded) = admit(
        &mut helper,
        &opened,
        "Discard",
        discard_request("discard", b"README.md"),
        7,
    );
    assert_eq!(preview["preview"]["preview"]["fileCount"], "1", "{preview}");
    assert_eq!(
        discarded["operation"]["outcome"], "succeeded",
        "{discarded}"
    );
    assert_eq!(
        std::fs::read(repository.join("README.md")).unwrap(),
        b"hello\n"
    );
    // The staged file is untouched.
    assert_eq!(
        git(&repository, &["diff", "--cached", "--name-only"]),
        "staged.txt"
    );

    std::fs::write(repository.join("scratch.txt"), b"scratch\n").unwrap();
    let (_, cleaned) = admit(
        &mut helper,
        &opened,
        "Discard",
        discard_request("clean", b"scratch.txt"),
        8,
    );
    assert_eq!(cleaned["operation"]["outcome"], "succeeded", "{cleaned}");
    assert!(!repository.join("scratch.txt").exists());

    // A file that changes after its preview is never discarded.
    std::fs::write(repository.join("README.md"), b"hello\nfirst\n").unwrap();
    let preview = helper.ok(
        "previewDiscard",
        opened.arguments(&[("request", discard_request("discard", b"README.md"))]),
    );
    std::fs::write(repository.join("README.md"), b"hello\nsecond\n").unwrap();
    let refused = helper.ok(
        "executeDiscard",
        opened.arguments(&[
            ("token", preview["token"].clone()),
            ("epoch", preview["epoch"].clone()),
            ("digest", preview["digest"].clone()),
            ("operationId", Value::from(operation_id(9))),
        ]),
    );
    assert_eq!(refused["operation"]["outcome"], "notApplied", "{refused}");
    assert_eq!(
        std::fs::read(repository.join("README.md")).unwrap(),
        b"hello\nsecond\n"
    );
}

/// A bare repository at `home/origin.git` that `repository` pushes to as `origin`.
fn origin(home: &Path, repository: &Path) -> std::path::PathBuf {
    let bare = home.join("origin.git");
    git(home, &["init", "-q", "--bare", "origin.git"]);
    git(
        repository,
        &["remote", "add", "origin", bare.to_str().unwrap()],
    );
    bare
}

#[test]
fn pushes_use_the_host_remote_and_a_rejection_is_failed() {
    let home = Root::new("family-transfer");
    let repository = ordinary_repository(&home.0);
    let bare = origin(&home.0, &repository);
    git(&repository, &["push", "-q", "origin", "main"]);
    // The branch moves ahead locally; the push sends it.
    git(&repository, &["commit", "-qm", "ahead"]);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);
    let (_, pushed) = admit(
        &mut helper,
        &opened,
        "Transfer",
        transfer_request("push", "origin", Some("main")),
        7,
    );
    assert_eq!(pushed["operation"]["outcome"], "succeeded", "{pushed}");
    assert_eq!(git(&bare, &["rev-parse", "main"]), head(&repository));

    // The helper's operation center reports the push, as the island shows it.
    let center = helper.ok(
        "operationCenter",
        object(&[("maximumEntries", Value::from(16))]),
    );
    let entries = center["snapshot"]["entries"].as_array().unwrap();
    assert!(
        entries
            .iter()
            .any(|entry| entry["action"] == "push" && entry["state"] == "succeeded"),
        "{center}"
    );
    assert_eq!(
        helper.error_code(
            "operationCenter",
            object(&[("maximumEntries", Value::from(0))])
        ),
        "invalidRequest"
    );

    // Another clone advances the server; this branch diverges and is rejected.
    let other = home.0.join("other");
    git(
        &home.0,
        &[
            "clone",
            "-q",
            bare.to_str().unwrap(),
            other.to_str().unwrap(),
        ],
    );
    git(
        &other,
        &["commit", "-q", "--allow-empty", "-m", "elsewhere"],
    );
    git(&other, &["push", "-q", "origin", "main"]);
    git(
        &repository,
        &["commit", "-q", "--allow-empty", "-m", "diverged"],
    );
    let server = git(&bare, &["rev-parse", "main"]);
    let (_, rejected) = admit(
        &mut helper,
        &opened,
        "Transfer",
        transfer_request("push", "origin", Some("main")),
        8,
    );
    assert_eq!(rejected["operation"]["outcome"], "failed", "{rejected}");
    assert_eq!(git(&bare, &["rev-parse", "main"]), server);

    // Fetching brings the other commit in.
    let (_, fetched) = admit(
        &mut helper,
        &opened,
        "Transfer",
        transfer_request("fetch", "origin", None),
        9,
    );
    assert_eq!(fetched["operation"]["outcome"], "succeeded", "{fetched}");
    assert_eq!(git(&repository, &["rev-parse", "origin/main"]), server);
}

#[test]
fn protected_pull_crosses_the_wire_and_requires_stash_capability() {
    let home = Root::new("family-protected-pull");
    let repository = ordinary_repository(&home.0);
    let bare = origin(&home.0, &repository);
    git(&repository, &["push", "-q", "origin", "main"]);
    let peer = home.0.join("peer");
    git(
        &home.0,
        &[
            "clone",
            "-q",
            "-b",
            "main",
            bare.to_str().unwrap(),
            peer.to_str().unwrap(),
        ],
    );
    std::fs::write(peer.join("upstream.txt"), b"upstream\n").unwrap();
    git(&peer, &["add", "upstream.txt"]);
    git(&peer, &["commit", "-qm", "upstream"]);
    git(&peer, &["push", "-q", "origin", "main"]);
    let staged = git(&repository, &["diff", "--cached", "--binary"]);
    let unstaged = git(&repository, &["diff", "--binary"]);
    let mut request = transfer_request("pull", "origin", Some("main"));
    request["stashBeforePull"] = Value::Bool(true);
    let mut restricted = Helper::spawn(&home.0);
    restricted.acknowledge(&["read", "transfer"]);
    let opened = open(&mut restricted, &repository);
    assert_eq!(
        restricted.error_code(
            "previewTransfer",
            opened.arguments(&[("request", request.clone())])
        ),
        "writeNotPermitted"
    );
    drop(restricted);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);
    let (_, pulled) = admit(&mut helper, &opened, "Transfer", request, 11);
    assert_eq!(pulled["operation"]["outcome"], "succeeded", "{pulled}");
    assert_eq!(
        pulled["result"]["stash"]["pullCompleted"],
        Value::Bool(true)
    );
    assert_eq!(
        pulled["result"]["stash"]["reapplyCompleted"],
        Value::Bool(true)
    );
    assert_eq!(git(&repository, &["rev-parse", "HEAD"]), head(&peer));
    assert_eq!(git(&repository, &["diff", "--cached", "--binary"]), staged);
    assert_eq!(git(&repository, &["diff", "--binary"]), unstaged);
    assert!(!git(&repository, &["stash", "list"]).is_empty());
}

#[test]
fn a_helper_killed_mid_branch_change_reports_unknown_and_never_replays() {
    let home = Root::new("family-crash");
    let repository = ordinary_repository(&home.0);
    let commit = head(&repository);
    let mut helper = Helper::spawn_with(&home.0, &[("GITLAMA_HELPER_FAULT", "before-terminal")]);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);
    let preview = helper.ok(
        "previewRefs",
        opened.arguments(&[(
            "request",
            refs_request("createBranch", Some("crashed"), Some(&commit)),
        )]),
    );
    let execute = opened.arguments(&[
        ("token", preview["token"].clone()),
        ("epoch", preview["epoch"].clone()),
        ("digest", preview["digest"].clone()),
        ("operationId", Value::from(operation_id(10))),
    ]);
    helper.send_call("executeRefs", execute.clone());
    assert!(!helper
        .wait_exit(Duration::from_secs(30))
        .expect("the faulted helper exits")
        .success());
    // The branch exists, but nothing durable proves it.
    assert_eq!(git(&repository, &["rev-parse", "crashed"]), commit);
    let mut fresh = Helper::spawn(&home.0);
    fresh.acknowledge(ALL);
    let lookup = fresh.ok(
        "lookupOperation",
        object(&[
            ("epoch", preview["epoch"].clone()),
            ("operationId", Value::from(operation_id(10))),
            ("digest", preview["digest"].clone()),
        ]),
    );
    assert_eq!(lookup["operation"]["outcome"], "unknown");
    let reopened = open(&mut fresh, &repository);
    let mut again = execute;
    again["sessionId"] = reopened.session.clone();
    assert!(fresh.ok("executeRefs", again)["result"].is_null());
}

#[test]
fn a_remote_branch_is_deleted_through_the_helper() {
    let home = Root::new("family-delete-branch");
    let repository = ordinary_repository(&home.0);
    let bare = origin(&home.0, &repository);
    git(
        &repository,
        &["push", "-q", "origin", "main", "main:t3code/feature"],
    );
    git(&repository, &["fetch", "-q", "origin"]);
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(ALL);
    let opened = open(&mut helper, &repository);
    let (preview, deleted) = admit(
        &mut helper,
        &opened,
        "Transfer",
        transfer_request("deleteBranch", "origin", Some("t3code/feature")),
        11,
    );
    assert_eq!(
        deleted["operation"]["outcome"], "succeeded",
        "{preview} {deleted}"
    );
    assert!(git(&bare, &["branch", "--list", "t3code/feature"]).is_empty());
}
