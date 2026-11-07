//! The closed method set. Reads go to the generated dispatcher of allowlisted session reads;
//! writes go through the durable admission coordinator; initializing a repository in a missing
//! or empty destination needs no receipt. Nothing runs Git or a shell for the
//! client directly.
use crate::protocol::Capability;
use crate::server::{lock, Connection};
use gitlama_application::wire::generated as g;
use gitlama_application::wire::runtime::{self as w, Value};

/// Runs one admitted call.
///
/// # Errors
/// A protocol error code.
pub fn call(
    connection: &Connection,
    method: &str,
    arguments: &Value,
) -> Result<Value, &'static str> {
    match method {
        "listDirectory" => {
            require(connection, Capability::ListDirectory)?;
            lock(connection.listings()).list(arguments, connection.home.as_deref())
        }
        "initializeRepository" => {
            require(connection, Capability::Initialize)?;
            crate::initialize::call(arguments)
        }
        "openRepository" => {
            require(connection, Capability::Read)?;
            connection.sessions.open(arguments)
        }
        "closeRepository" => {
            require(connection, Capability::Read)?;
            connection.sessions.close(connection, arguments)
        }
        // The helper's own operation center: progress and results of this connection's
        // sessions, which run here and not in the client's core.
        "operationCenter" => {
            require(connection, Capability::Read)?;
            let object = w::object(arguments, "operationCenter", &["maximumEntries"])
                .map_err(|_| "invalidRequest")?;
            let maximum: u32 =
                w::int_d(object.field("maximumEntries")).map_err(|_| "invalidRequest")?;
            if maximum == 0 || maximum > 256 {
                return Err("invalidRequest");
            }
            Ok(g::enc_native_operation_center_result(
                &gitlama_application::application::operation_center::application_operation_center(
                    maximum,
                ),
            ))
        }
        "operationDismiss" => {
            require(connection, Capability::Read)?;
            connection.sessions.require(arguments)?;
            let object = w::object(
                arguments,
                "operationDismiss",
                &["sessionId", "generation", "activityId"],
            )
            .map_err(|_| "invalidRequest")?;
            let session: u64 = w::big_d(object.field("sessionId")).map_err(|_| "invalidRequest")?;
            let generation: u64 =
                w::big_d(object.field("generation")).map_err(|_| "invalidRequest")?;
            let activity: u64 =
                w::big_d(object.field("activityId")).map_err(|_| "invalidRequest")?;
            Ok(g::enc_native_repository_command_result(
                &gitlama_application::application::operation_center::application_operation_dismiss(
                    session, generation, activity,
                ),
            ))
        }
        "lookupOperation" => {
            if !Capability::RECEIPT_WRITES
                .into_iter()
                .any(|capability| connection.allows(capability))
            {
                return Err("writeNotPermitted");
            }
            let writes = connection.writes.as_ref().ok_or("writeNotPermitted")?;
            writes.call(connection, method, arguments)
        }
        _ if write_capability(method).is_some() => {
            require(connection, write_capability(method).ok_or("internal")?)?;
            let writes = connection.writes.as_ref().ok_or("writeNotPermitted")?;
            writes.call(connection, method, arguments)
        }
        _ if g::READ_METHODS.contains(&method) => {
            require(connection, Capability::Read)?;
            connection.sessions.require(arguments)?;
            match g::dispatch_read(method, arguments) {
                Some(Ok(value)) => Ok(value),
                Some(Err(_)) => Err("invalidRequest"),
                None => Err("unsupportedCommand"),
            }
        }
        _ => Err("unsupportedCommand"),
    }
}

/// The capability a preview or execute method needs.
fn write_capability(method: &str) -> Option<Capability> {
    let suffix = method
        .strip_prefix("preview")
        .or_else(|| method.strip_prefix("execute"))?;
    gitlama_application::wire::contract::RemoteWriteFamily::of_method(suffix)
        .map(gitlama_application::wire::contract::RemoteWriteFamily::capability)
}

fn require(connection: &Connection, capability: Capability) -> Result<(), &'static str> {
    if connection.allows(capability) {
        Ok(())
    } else if capability.is_write() {
        Err("writeNotPermitted")
    } else {
        Err("unsupportedCommand")
    }
}
