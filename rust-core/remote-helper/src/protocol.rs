//! Hello, acknowledgement and envelope rules of protocol 1.0 (docs/remote-workspaces/PROTOCOL.md).
use gitlama_application::wire::runtime::{self as w, Map, Value};

pub const PROTOCOL_MAJOR: u64 = 1;
pub const PROTOCOL_MINOR: u64 = 0;
pub const MAGIC: &str = "gitlama-remote-helper";

pub use gitlama_application::wire::contract::{
    CHUNK_BYTES, REQUESTS_PER_CONNECTION, SESSIONS_PER_CONNECTION, TRANSACTION_BYTES,
};

/// The closed capabilities, from the generated contract. `WRITES` includes `Initialize`;
/// `RECEIPT_WRITES` are those whose operations carry a receipt. Every write is offered only
/// when the receipt store is usable.
pub use gitlama_application::wire::contract::RemoteCapability as Capability;

/// 16 random bytes as 32 lowercase hex characters.
///
/// # Errors
/// The operating system's random source failed.
pub fn random_id() -> Result<String, getrandom::Error> {
    let mut bytes = [0_u8; 16];
    getrandom::fill(&mut bytes)?;
    Ok(hex(&bytes))
}

#[must_use]
pub fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    let mut text = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        let _ = write!(text, "{byte:02x}");
    }
    text
}

/// Whether `value` is exactly `length` lowercase hex digits.
#[must_use]
pub fn is_hex(value: &str, length: usize) -> bool {
    value.len() == length
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// What the helper reports about itself.
pub struct HelloFacts<'a> {
    pub build_id: &'a str,
    pub incarnation: &'a str,
    pub git_state: &'a str,
    pub git_version: Option<&'a str>,
    pub store_id: Option<&'a str>,
    pub account_uid: u32,
    pub account_name: &'a str,
    pub capabilities: &'a [Capability],
}

#[must_use]
pub fn hello(facts: &HelloFacts<'_>) -> Value {
    let mut store = Map::new();
    store.insert(
        "state".into(),
        Value::from(if facts.store_id.is_some() {
            "ready"
        } else {
            "unavailable"
        }),
    );
    store.insert(
        "storeId".into(),
        facts.store_id.map_or(Value::Null, Value::from),
    );
    let mut account = Map::new();
    account.insert("uid".into(), Value::from(facts.account_uid.to_string()));
    account.insert("name".into(), Value::from(facts.account_name));
    let mut limits = Map::new();
    limits.insert(
        "frameBytes".into(),
        Value::from(crate::frame::MAX_FRAME_BYTES.to_string()),
    );
    limits.insert(
        "transactionBytes".into(),
        Value::from(TRANSACTION_BYTES.to_string()),
    );
    limits.insert(
        "requestsPerConnection".into(),
        Value::from(REQUESTS_PER_CONNECTION.to_string()),
    );
    limits.insert(
        "sessionsPerConnection".into(),
        Value::from(SESSIONS_PER_CONNECTION.to_string()),
    );
    let mut hello = Map::new();
    hello.insert("kind".into(), Value::from("hello"));
    hello.insert("magic".into(), Value::from(MAGIC));
    hello.insert("protocolMajor".into(), Value::from(PROTOCOL_MAJOR));
    hello.insert("protocolMinor".into(), Value::from(PROTOCOL_MINOR));
    hello.insert("buildId".into(), Value::from(facts.build_id));
    hello.insert("platform".into(), Value::from(std::env::consts::OS));
    hello.insert("architecture".into(), Value::from(std::env::consts::ARCH));
    hello.insert("gitState".into(), Value::from(facts.git_state));
    hello.insert(
        "gitVersion".into(),
        facts.git_version.map_or(Value::Null, Value::from),
    );
    hello.insert("helperIncarnation".into(), Value::from(facts.incarnation));
    hello.insert("store".into(), Value::Object(store));
    hello.insert("account".into(), Value::Object(account));
    hello.insert(
        "capabilities".into(),
        Value::Array(
            facts
                .capabilities
                .iter()
                .map(|capability| Value::from(capability.name()))
                .collect(),
        ),
    );
    hello.insert("limits".into(), Value::Object(limits));
    Value::Object(hello)
}

/// A validated acknowledgement.
pub struct Acknowledgement {
    pub nonce: String,
    pub capabilities: Vec<Capability>,
}

/// Validates a hello acknowledgement against this helper's hello.
///
/// # Errors
/// Any deviation; the helper then rejects the handshake.
pub fn acknowledgement(
    value: &Value,
    build_id: &str,
    incarnation: &str,
    offered: &[Capability],
) -> Result<Acknowledgement, ()> {
    let object = w::object(
        value,
        "helloAck",
        &[
            "kind",
            "protocolMajor",
            "protocolMinor",
            "buildId",
            "helperIncarnation",
            "connectionNonce",
            "capabilities",
        ],
    )
    .map_err(|_| ())?;
    let text = |name: &str| object.field(name).as_str().ok_or(());
    if text("kind")? != "helloAck"
        || object.field("protocolMajor").as_u64() != Some(PROTOCOL_MAJOR)
        || object.field("protocolMinor").as_u64().is_none()
        || text("buildId")? != build_id
        || text("helperIncarnation")? != incarnation
    {
        return Err(());
    }
    let nonce = text("connectionNonce")?;
    if !is_hex(nonce, 32) {
        return Err(());
    }
    let Value::Array(names) = object.field("capabilities") else {
        return Err(());
    };
    let mut capabilities = Vec::new();
    for name in names {
        let capability = name.as_str().and_then(Capability::parse).ok_or(())?;
        if !offered.contains(&capability) || capabilities.contains(&capability) {
            return Err(());
        }
        capabilities.push(capability);
    }
    Ok(Acknowledgement {
        nonce: nonce.to_owned(),
        capabilities,
    })
}

/// One validated client envelope.
pub struct Envelope {
    pub request_id: u64,
    pub kind: String,
    pub payload: Value,
}

/// The connection identity every envelope repeats.
#[derive(Clone)]
pub struct Session {
    pub nonce: String,
    pub incarnation: String,
}

impl Session {
    /// Validates a client envelope.
    ///
    /// # Errors
    /// A wrong identity, a malformed request identifier or an unexpected shape.
    pub fn parse(&self, value: &Value) -> Result<Envelope, ()> {
        let object = w::object(
            value,
            "envelope",
            &[
                "protocolMajor",
                "connectionNonce",
                "helperIncarnation",
                "requestId",
                "kind",
                "payload",
            ],
        )
        .map_err(|_| ())?;
        if object.field("protocolMajor").as_u64() != Some(PROTOCOL_MAJOR)
            || object.field("connectionNonce").as_str() != Some(self.nonce.as_str())
            || object.field("helperIncarnation").as_str() != Some(self.incarnation.as_str())
        {
            return Err(());
        }
        let request_id: u64 = w::big_d(object.field("requestId")).map_err(|_| ())?;
        let kind = object.field("kind").as_str().ok_or(())?.to_owned();
        let payload = object.field("payload").clone();
        if request_id == 0 || !payload.is_object() {
            return Err(());
        }
        Ok(Envelope {
            request_id,
            kind,
            payload,
        })
    }

    /// Builds a helper envelope.
    #[must_use]
    pub fn envelope(&self, request_id: u64, kind: &str, payload: Value) -> Value {
        let mut map = Map::new();
        map.insert("protocolMajor".into(), Value::from(PROTOCOL_MAJOR));
        map.insert("connectionNonce".into(), Value::from(self.nonce.as_str()));
        map.insert(
            "helperIncarnation".into(),
            Value::from(self.incarnation.as_str()),
        );
        map.insert("requestId".into(), Value::from(request_id.to_string()));
        map.insert("kind".into(), Value::from(kind));
        map.insert("payload".into(), payload);
        Value::Object(map)
    }
}

/// A `result` payload carrying a value.
#[must_use]
pub fn ok(value: Value) -> Value {
    let mut map = Map::new();
    map.insert("ok".into(), value);
    Value::Object(map)
}

/// A `result` or `fatal` payload carrying a protocol error code.
#[must_use]
pub fn error(code: &str) -> Value {
    let mut inner = Map::new();
    inner.insert("code".into(), Value::from(code));
    let mut map = Map::new();
    map.insert("error".into(), Value::Object(inner));
    Value::Object(map)
}

/// A pre-handshake `fatal` message.
#[must_use]
pub fn fatal(code: &str) -> Value {
    let mut map = Map::new();
    map.insert("kind".into(), Value::from("fatal"));
    map.insert("code".into(), Value::from(code));
    Value::Object(map)
}

/// A post-handshake `fatal` payload.
#[must_use]
pub fn fatal_payload(code: &str) -> Value {
    let mut map = Map::new();
    map.insert("code".into(), Value::from(code));
    Value::Object(map)
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_application::wire::runtime::{parse, ParseLimits};

    const BUILD: &str = "0123456789abcdef0123456789abcdef01234567";
    const INCARNATION: &str = "00112233445566778899aabbccddeeff";

    fn ack(text: &str) -> Result<Acknowledgement, ()> {
        acknowledgement(
            &parse(text.as_bytes(), ParseLimits::FRAME).unwrap(),
            BUILD,
            INCARNATION,
            &[Capability::Read, Capability::ListDirectory],
        )
    }

    fn valid(build: &str, capabilities: &str) -> String {
        format!(
            r#"{{"kind":"helloAck","protocolMajor":1,"protocolMinor":0,"buildId":"{build}","helperIncarnation":"{INCARNATION}","connectionNonce":"ffeeddccbbaa99887766554433221100","capabilities":{capabilities}}}"#
        )
    }

    #[test]
    fn acknowledgement_requires_the_exact_build_and_offered_capabilities() {
        let accepted = ack(&valid(BUILD, r#"["read"]"#)).unwrap();
        assert_eq!(accepted.capabilities, vec![Capability::Read]);
        assert!(ack(&valid(&"1".repeat(40), r#"["read"]"#)).is_err());
        assert!(ack(&valid(BUILD, r#"["stage"]"#)).is_err());
        assert!(ack(&valid(BUILD, r#"["read","read"]"#)).is_err());
        assert!(ack(&valid(BUILD, r#"["shell"]"#)).is_err());
        assert!(ack(&valid(BUILD, r#"["read"]"#).replace("ffee", "FFEE")).is_err());
        assert!(ack(
            &valid(BUILD, r#"["read"]"#).replace(r#""protocolMajor":1"#, r#""protocolMajor":2"#)
        )
        .is_err());
    }

    #[test]
    fn envelopes_bind_the_connection_identity() {
        let session = Session {
            nonce: "ffeeddccbbaa99887766554433221100".into(),
            incarnation: INCARNATION.into(),
        };
        let envelope = session.envelope(7, "call", Value::Object(Map::new()));
        let parsed = session.parse(&envelope).unwrap();
        assert_eq!(parsed.request_id, 7);
        let other = Session {
            nonce: "0".repeat(32),
            incarnation: INCARNATION.into(),
        };
        assert!(other.parse(&envelope).is_err());
        assert!(session
            .parse(&session.envelope(0, "call", Value::Object(Map::new())))
            .is_err());
    }

    #[test]
    fn identifiers_are_lowercase_hex() {
        let id = random_id().unwrap();
        assert!(is_hex(&id, 32));
        assert_ne!(id, random_id().unwrap());
        assert!(!is_hex("ABCDEF0123456789abcdef0123456789", 32));
    }
}
