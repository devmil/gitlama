//! Projections QML reads as plain values.

use serde::Serialize;
use serde_json::Value;

/// Serializes a projection; an unserializable value becomes null.
pub fn to_value(value: &impl Serialize) -> Value {
    serde_json::to_value(value).unwrap_or(Value::Null)
}
