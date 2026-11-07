//! `initializeRepository` through the real helper: a new repository in a missing or empty
//! directory, the destinations it refuses, and the `initialize` capability it needs.
#![cfg(unix)]
mod common;

use common::{git, object, Helper, Root};
use gitlama_application::wire::runtime::{self as w, Value};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

fn arguments(path: &[u8], branch: &str, bare: bool) -> Value {
    object(&[
        ("path", w::bytes_e(path)),
        ("initialBranch", Value::from(branch)),
        ("bare", Value::Bool(bare)),
    ])
}

fn initialize(helper: &mut Helper, path: &Path, bare: bool) -> Value {
    let result = helper.ok(
        "initializeRepository",
        arguments(path.as_os_str().as_bytes(), "main", bare),
    );
    result["failure"].clone()
}

fn capabilities(helper: &Helper) -> Vec<String> {
    helper.hello["capabilities"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c.as_str().unwrap().to_owned())
        .collect()
}

#[test]
fn initializes_a_new_repository_and_opens_it() {
    let home = Root::new("initialize");
    let mut helper = Helper::spawn(&home.0);
    assert!(capabilities(&helper).contains(&"initialize".to_owned()));
    helper.acknowledge(&["read", "initialize"]);

    // Missing directories are created.
    let created = home.0.join("projects").join("new");
    assert!(initialize(&mut helper, &created, false).is_null());
    assert_eq!(git(&created, &["symbolic-ref", "HEAD"]), "refs/heads/main");
    let open = helper.open(&created, 1);
    assert!(open["open"]["failure"].is_null(), "{open}");

    // An empty directory is accepted, and a bare repository may be chosen.
    let empty = home.0.join("empty.git");
    std::fs::create_dir(&empty).unwrap();
    assert!(initialize(&mut helper, &empty, true).is_null());
    assert_eq!(git(&empty, &["rev-parse", "--is-bare-repository"]), "true");

    // A path that is not valid UTF-8 is passed through as bytes. APFS refuses names that are not
    // UTF-8, so macOS cannot hold this path.
    #[cfg(not(target_os = "macos"))]
    {
        let mut raw = home.0.as_os_str().as_bytes().to_vec();
        raw.extend_from_slice(b"/caf\xe9");
        let result = helper.ok("initializeRepository", arguments(&raw, "main", false));
        assert!(result["failure"].is_null(), "{result}");
        assert!(Path::new(std::ffi::OsStr::from_bytes(&raw))
            .join(".git")
            .is_dir());
    }
}

#[test]
fn refuses_destinations_that_are_not_missing_or_empty() {
    let home = Root::new("initialize-refused");
    let mut helper = Helper::spawn(&home.0);
    helper.acknowledge(&["read", "initialize"]);

    let existing = home.0.join("existing");
    assert!(initialize(&mut helper, &existing, false).is_null());
    // Asking again after a lost answer reports the repository that now exists.
    assert_eq!(
        initialize(&mut helper, &existing, false),
        "existingRepository"
    );

    let full = home.0.join("full");
    std::fs::create_dir(&full).unwrap();
    std::fs::write(full.join("notes.txt"), b"keep").unwrap();
    assert_eq!(initialize(&mut helper, &full, false), "destinationNotEmpty");
    assert_eq!(std::fs::read(full.join("notes.txt")).unwrap(), b"keep");
    assert!(!full.join(".git").exists());

    let file = home.0.join("file");
    std::fs::write(&file, b"x").unwrap();
    assert_eq!(
        initialize(&mut helper, &file, false),
        "destinationNotDirectory"
    );

    let link = home.0.join("link");
    std::os::unix::fs::symlink(home.0.join("missing"), &link).unwrap();
    assert_eq!(
        initialize(&mut helper, &link, false),
        "destinationNotDirectory"
    );

    let branch = helper.ok(
        "initializeRepository",
        arguments(
            home.0.join("branch").as_os_str().as_bytes(),
            "bad..branch",
            false,
        ),
    );
    assert_eq!(branch["failure"], "invalidOptions");
    assert!(!home.0.join("branch").exists());

    assert_eq!(
        helper.error_code(
            "initializeRepository",
            arguments(b"relative/path", "main", false)
        ),
        "pathInvalid"
    );
    assert_eq!(
        helper.error_code(
            "initializeRepository",
            object(&[("path", w::bytes_e(b"/tmp/x"))])
        ),
        "invalidRequest"
    );
}

#[test]
fn needs_the_initialize_capability() {
    let home = Root::new("initialize-denied");
    let mut helper = Helper::spawn(&home.0);
    // Every other write was negotiated, but not initialization.
    helper.acknowledge(&["read", "listDirectory", "stage", "commit"]);
    let destination = home.0.join("denied");
    assert_eq!(
        helper.error_code(
            "initializeRepository",
            arguments(destination.as_os_str().as_bytes(), "main", false)
        ),
        "writeNotPermitted"
    );
    assert!(!destination.exists());
    drop(helper);

    // A helper without a usable receipt store offers no initialization.
    let blocked = Root::new("initialize-blocked");
    std::fs::write(blocked.0.join(".local"), b"not a directory").unwrap();
    let helper = Helper::spawn(&blocked.0);
    assert_eq!(helper.hello["store"]["state"], "unavailable");
    assert!(!capabilities(&helper).contains(&"initialize".to_owned()));
}
