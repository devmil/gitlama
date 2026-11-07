//! `initializeRepository`: creates a repository in a missing or empty host directory with the
//! core's own checks and `git init`. It needs the `initialize` capability and has no receipt:
//! the destination is missing or empty, so a lost answer is resolved by asking again, which
//! then reports `existingRepository`, and by opening the path.
use gitlama_application::activity::ActivityStore;
use gitlama_application::repository_init::initialize_repository;
use gitlama_application::wire::generated as g;
use gitlama_application::wire::runtime::{self as w, Map, Value};

/// Runs one `initializeRepository` call and answers `{"failure": null | <failure kind>}`.
///
/// # Errors
/// `invalidRequest` for a malformed request, `pathInvalid` for an unacceptable path.
pub fn call(arguments: &Value) -> Result<Value, &'static str> {
    let object = w::object(
        arguments,
        "initializeRepository",
        &["path", "initialBranch", "bare"],
    )
    .map_err(|_| "invalidRequest")?;
    let bytes = w::bytes_d(object.field("path")).map_err(|_| "invalidRequest")?;
    let path = crate::directory::client_path(&bytes)?;
    let branch = object
        .field("initialBranch")
        .as_str()
        .ok_or("invalidRequest")?;
    let bare = object.field("bare").as_bool().ok_or("invalidRequest")?;
    let failure = match initialize_repository(&path, branch, bare, &ActivityStore::default()) {
        Ok(()) => Value::Null,
        Err(kind) => g::enc_native_repository_failure_kind(&kind),
    };
    let mut result = Map::new();
    result.insert("failure".into(), failure);
    Ok(Value::Object(result))
}
