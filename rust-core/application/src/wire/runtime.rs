//! Value rules shared by every remote wire message.
//!
//! Integers that may exceed 2^53 travel as canonical decimal strings, byte strings as canonical
//! padded base64, and objects carry exactly their declared keys. Parsing rejects duplicate keys
//! and bounds nesting and collection sizes before building nested values.
use serde::de::{DeserializeSeed, Error as _, MapAccess, SeqAccess, Visitor};
pub use serde_json::{Map, Value};
use std::fmt;

/// A malformed or out-of-contract wire value. The detail is a fixed field or type name, never
/// received content.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WireError {
    pub detail: &'static str,
}

impl WireError {
    #[must_use]
    pub const fn invalid(detail: &'static str) -> Self {
        Self { detail }
    }
}

impl fmt::Display for WireError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "invalid wire value: {}", self.detail)
    }
}

impl std::error::Error for WireError {}

/// Structural parsing bounds.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ParseLimits {
    pub depth: usize,
    pub collection: usize,
}

impl ParseLimits {
    /// One frame: nesting 16, at most 4096 items per array or object.
    pub const FRAME: Self = Self {
        depth: super::contract::JSON_DEPTH,
        collection: super::contract::FRAME_COLLECTION,
    };
    /// A reassembled multi-frame transaction, already bounded by its total byte ceiling.
    pub const TRANSACTION: Self = Self {
        depth: super::contract::JSON_DEPTH,
        collection: super::contract::TRANSACTION_COLLECTION,
    };
}

/// Parses one JSON document with duplicate-key rejection and structural bounds.
///
/// # Errors
/// Invalid UTF-8 or JSON, a duplicate key, excessive nesting or an oversized collection.
pub fn parse(bytes: &[u8], limits: ParseLimits) -> Result<Value, WireError> {
    let mut deserializer = serde_json::Deserializer::from_slice(bytes);
    let value = StrictValue { limits, depth: 0 }
        .deserialize(&mut deserializer)
        .map_err(|_| WireError::invalid("json"))?;
    deserializer
        .end()
        .map_err(|_| WireError::invalid("trailing"))?;
    Ok(value)
}

/// Serializes a value as compact JSON.
#[must_use]
pub fn to_bytes(value: &Value) -> Vec<u8> {
    serde_json::to_vec(value).unwrap_or_default()
}

struct StrictValue {
    limits: ParseLimits,
    depth: usize,
}

impl<'de> DeserializeSeed<'de> for StrictValue {
    type Value = Value;

    fn deserialize<D: serde::Deserializer<'de>>(self, deserializer: D) -> Result<Value, D::Error> {
        deserializer.deserialize_any(self)
    }
}

impl<'de> Visitor<'de> for StrictValue {
    type Value = Value;

    fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("a bounded JSON value")
    }

    fn visit_bool<E>(self, value: bool) -> Result<Value, E> {
        Ok(Value::Bool(value))
    }

    fn visit_i64<E>(self, value: i64) -> Result<Value, E> {
        Ok(Value::from(value))
    }

    fn visit_u64<E>(self, value: u64) -> Result<Value, E> {
        Ok(Value::from(value))
    }

    fn visit_f64<E: serde::de::Error>(self, _value: f64) -> Result<Value, E> {
        // The protocol has no floating-point values.
        Err(E::custom("float"))
    }

    fn visit_str<E>(self, value: &str) -> Result<Value, E> {
        Ok(Value::String(value.to_owned()))
    }

    fn visit_string<E>(self, value: String) -> Result<Value, E> {
        Ok(Value::String(value))
    }

    fn visit_unit<E>(self) -> Result<Value, E> {
        Ok(Value::Null)
    }

    fn visit_none<E>(self) -> Result<Value, E> {
        Ok(Value::Null)
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut sequence: A) -> Result<Value, A::Error> {
        let depth = self.depth + 1;
        if depth > self.limits.depth {
            return Err(A::Error::custom("depth"));
        }
        let mut values = Vec::new();
        while let Some(value) = sequence.next_element_seed(StrictValue {
            limits: self.limits,
            depth,
        })? {
            if values.len() == self.limits.collection {
                return Err(A::Error::custom("collection"));
            }
            values.push(value);
        }
        Ok(Value::Array(values))
    }

    fn visit_map<A: MapAccess<'de>>(self, mut access: A) -> Result<Value, A::Error> {
        let depth = self.depth + 1;
        if depth > self.limits.depth {
            return Err(A::Error::custom("depth"));
        }
        let mut map = Map::new();
        while let Some(key) = access.next_key::<String>()? {
            if map.len() == self.limits.collection {
                return Err(A::Error::custom("collection"));
            }
            let value = access.next_value_seed(StrictValue {
                limits: self.limits,
                depth,
            })?;
            if map.insert(key, value).is_some() {
                return Err(A::Error::custom("duplicate key"));
            }
        }
        Ok(Value::Object(map))
    }
}

/// An object whose key set was checked against its declaration.
pub struct Object<'a> {
    map: &'a Map<String, Value>,
}

impl<'a> Object<'a> {
    /// The value of a declared key.
    #[must_use]
    pub fn field(&self, name: &str) -> &'a Value {
        self.map.get(name).unwrap_or(&Value::Null)
    }
}

/// Accepts an object with exactly the `names` keys.
///
/// # Errors
/// A non-object, a missing key or an undeclared key.
pub fn object<'a>(
    value: &'a Value,
    type_name: &'static str,
    names: &[&str],
) -> Result<Object<'a>, WireError> {
    let Value::Object(map) = value else {
        return Err(WireError::invalid(type_name));
    };
    if map.len() != names.len() || names.iter().any(|name| !map.contains_key(*name)) {
        return Err(WireError::invalid(type_name));
    }
    Ok(Object { map })
}

#[must_use]
pub fn bool_e(value: &bool) -> Value {
    Value::Bool(*value)
}

/// # Errors
/// A non-boolean.
pub fn bool_d(value: &Value) -> Result<bool, WireError> {
    value.as_bool().ok_or(WireError::invalid("bool"))
}

/// A small integer as a JSON number.
#[must_use]
pub fn int_e<T: Copy + Into<i64>>(value: &T) -> Value {
    Value::from((*value).into())
}

/// # Errors
/// A non-integer or an out-of-range value.
pub fn int_d<T: TryFrom<i64>>(value: &Value) -> Result<T, WireError> {
    let number = match value {
        Value::Number(number) => number
            .as_i64()
            .filter(|n| n.unsigned_abs() <= (1_u64 << 53))
            .ok_or(WireError::invalid("int"))?,
        _ => return Err(WireError::invalid("int")),
    };
    T::try_from(number).map_err(|_| WireError::invalid("int range"))
}

/// A 64-bit integer as a canonical decimal string.
#[must_use]
pub fn big_e<T: Copy + TryInto<i128>>(value: &T) -> Value {
    let wide: i128 = (*value).try_into().unwrap_or_default();
    Value::String(wide.to_string())
}

/// # Errors
/// A non-canonical decimal string or an out-of-range value.
pub fn big_d<T: TryFrom<i128>>(value: &Value) -> Result<T, WireError> {
    let text = str_ref(value)?;
    let digits = text.strip_prefix('-').unwrap_or(text);
    let canonical = !digits.is_empty()
        && digits.len() <= 20
        && digits.bytes().all(|b| b.is_ascii_digit())
        && (digits == "0" || !digits.starts_with('0'))
        && text != "-0";
    if !canonical {
        return Err(WireError::invalid("decimal"));
    }
    let wide: i128 = text.parse().map_err(|_| WireError::invalid("decimal"))?;
    T::try_from(wide).map_err(|_| WireError::invalid("decimal range"))
}

#[must_use]
pub fn str_e(value: &str) -> Value {
    Value::String(value.to_owned())
}

/// # Errors
/// A non-string.
pub fn str_ref(value: &Value) -> Result<&str, WireError> {
    value.as_str().ok_or(WireError::invalid("string"))
}

/// # Errors
/// A non-string.
pub fn str_d(value: &Value) -> Result<String, WireError> {
    str_ref(value).map(str::to_owned)
}

#[must_use]
pub fn bytes_e(value: &[u8]) -> Value {
    Value::String(base64_encode(value))
}

/// # Errors
/// A non-string or non-canonical padded base64.
pub fn bytes_d(value: &Value) -> Result<Vec<u8>, WireError> {
    base64_decode(str_ref(value)?).ok_or(WireError::invalid("base64"))
}

/// UTF-16 or Unix path units as base64 of little-endian pairs.
#[must_use]
pub fn units_e(value: &[u16]) -> Value {
    let bytes: Vec<u8> = value.iter().flat_map(|unit| unit.to_le_bytes()).collect();
    bytes_e(&bytes)
}

/// # Errors
/// Malformed base64 or an odd byte count.
pub fn units_d(value: &Value) -> Result<Vec<u16>, WireError> {
    let bytes = bytes_d(value)?;
    if !bytes.len().is_multiple_of(2) {
        return Err(WireError::invalid("units"));
    }
    Ok(bytes
        .chunks_exact(2)
        .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
        .collect())
}

pub fn opt_e<T>(value: &Option<T>, encode: impl Fn(&T) -> Value) -> Value {
    value.as_ref().map_or(Value::Null, encode)
}

/// # Errors
/// The inner decoder's error.
pub fn opt_d<T>(
    value: &Value,
    decode: impl Fn(&Value) -> Result<T, WireError>,
) -> Result<Option<T>, WireError> {
    if value.is_null() {
        Ok(None)
    } else {
        decode(value).map(Some)
    }
}

pub fn list_e<T>(values: &[T], encode: impl Fn(&T) -> Value) -> Value {
    Value::Array(values.iter().map(encode).collect())
}

/// # Errors
/// A non-array or an element error.
pub fn list_d<T>(
    value: &Value,
    decode: impl Fn(&Value) -> Result<T, WireError>,
) -> Result<Vec<T>, WireError> {
    let Value::Array(values) = value else {
        return Err(WireError::invalid("list"));
    };
    values.iter().map(decode).collect()
}

const BASE64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

#[must_use]
pub fn base64_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [
            chunk[0],
            chunk.get(1).copied().unwrap_or(0),
            chunk.get(2).copied().unwrap_or(0),
        ];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        for (index, shift) in [18, 12, 6, 0].into_iter().enumerate() {
            if index <= chunk.len() {
                out.push(char::from(BASE64[((n >> shift) & 63) as usize]));
            } else {
                out.push('=');
            }
        }
    }
    out
}

/// Decodes canonical padded base64; any other spelling of the same bytes is rejected.
#[must_use]
pub fn base64_decode(text: &str) -> Option<Vec<u8>> {
    let bytes = text.as_bytes();
    if !bytes.len().is_multiple_of(4) {
        return None;
    }
    let mut out = Vec::with_capacity(bytes.len() / 4 * 3);
    for (index, chunk) in bytes.chunks(4).enumerate() {
        let last = index + 1 == bytes.len() / 4;
        let padding = chunk.iter().rev().take_while(|b| **b == b'=').count();
        if padding > 2 || (padding > 0 && !last) {
            return None;
        }
        let mut n = 0_u32;
        for (position, byte) in chunk.iter().enumerate() {
            let value = if position >= 4 - padding {
                0
            } else {
                u32::try_from(BASE64.iter().position(|c| c == byte)?).ok()?
            };
            n = (n << 6) | value;
        }
        let decoded = [(n >> 16) as u8, (n >> 8) as u8, n as u8];
        // Canonical encodings leave the unused low bits of the last symbol zero.
        if (padding == 1 && decoded[2] != 0) || (padding == 2 && decoded[1] != 0) {
            return None;
        }
        out.extend_from_slice(&decoded[..3 - padding]);
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duplicate_keys_nesting_and_collections_are_rejected() {
        assert!(parse(br#"{"a":1,"a":2}"#, ParseLimits::FRAME).is_err());
        assert!(parse(br#"{"a":1,"b":{"a":2}}"#, ParseLimits::FRAME).is_ok());
        let deep = "[".repeat(17) + &"]".repeat(17);
        assert!(parse(deep.as_bytes(), ParseLimits::FRAME).is_err());
        let ok = "[".repeat(16) + &"]".repeat(16);
        assert!(parse(ok.as_bytes(), ParseLimits::FRAME).is_ok());
        let wide = format!("[{}]", vec!["0"; 4097].join(","));
        assert!(parse(wide.as_bytes(), ParseLimits::FRAME).is_err());
        assert!(parse(wide.as_bytes(), ParseLimits::TRANSACTION).is_ok());
        assert!(parse(b"1.5", ParseLimits::FRAME).is_err());
        assert!(parse(b"{} x", ParseLimits::FRAME).is_err());
        assert!(parse(b"\"\xff\"", ParseLimits::FRAME).is_err());
    }

    #[test]
    fn decimal_strings_are_canonical_and_range_checked() {
        assert_eq!(big_d::<u64>(&Value::from("0")), Ok(0));
        assert_eq!(
            big_d::<u64>(&Value::from("18446744073709551615")),
            Ok(u64::MAX)
        );
        for bad in [
            "",
            "01",
            "-0",
            "+1",
            "1 ",
            "18446744073709551616",
            "1e3",
            "0x1",
        ] {
            assert!(big_d::<u64>(&Value::from(bad)).is_err(), "{bad}");
        }
        assert!(big_d::<u64>(&Value::from(1)).is_err());
        assert_eq!(big_d::<i64>(&Value::from("-5")), Ok(-5));
        assert_eq!(big_e(&u64::MAX), Value::from("18446744073709551615"));
    }

    #[test]
    fn base64_round_trips_and_rejects_non_canonical_spellings() {
        for length in 0..12 {
            let bytes: Vec<u8> = (0..length).map(|i| (i * 37 + 250) as u8).collect();
            assert_eq!(base64_decode(&base64_encode(&bytes)), Some(bytes));
        }
        assert_eq!(base64_encode(b"\xff\xfe"), "//4=");
        for bad in [
            "//5=", "Zg", "Zg=", "Zg===", "Z===", "Zm9v\n", "Zg==Zg==", "Zm9-",
        ] {
            assert_eq!(base64_decode(bad), None, "{bad}");
        }
    }

    #[test]
    fn objects_require_their_exact_keys() {
        let value = parse(br#"{"a":1,"b":null}"#, ParseLimits::FRAME).unwrap();
        assert!(object(&value, "T", &["a", "b"]).is_ok());
        assert!(object(&value, "T", &["a"]).is_err());
        assert!(object(&value, "T", &["a", "b", "c"]).is_err());
        assert!(object(&value, "T", &["a", "c"]).is_err());
    }

    #[test]
    fn small_integers_stay_exact() {
        assert_eq!(int_d::<u32>(&Value::from(7)), Ok(7));
        assert!(int_d::<u32>(&Value::from(-1)).is_err());
        assert!(int_d::<u32>(&Value::from(u64::MAX)).is_err());
        assert!(int_d::<u32>(&Value::from("7")).is_err());
    }
}

#[cfg(test)]
mod fuzz {
    //! Seeded, bounded mutation fuzzing. Failures must be typed errors, never panics.
    use super::*;

    struct XorShift(u64);

    impl XorShift {
        fn next(&mut self) -> u64 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            self.0
        }

        fn below(&mut self, bound: usize) -> usize {
            usize::try_from(self.next() % u64::try_from(bound.max(1)).unwrap_or(1)).unwrap_or(0)
        }
    }

    const SEED: u64 = 0x5eed_6175_6c61_6d61;
    pub const ITERATIONS: usize = 20_000;

    fn corpus() -> Vec<Vec<u8>> {
        vec![
            br#"{"protocolMajor":1,"connectionNonce":"00112233445566778899aabbccddeeff","helperIncarnation":"ffeeddccbbaa99887766554433221100","requestId":"7","kind":"call","payload":{"method":"listDirectory","args":{"directory":"L2hvbWU=","cursor":null}}}"#.to_vec(),
            br#"{"events":[{"kind":"snapshot","snapshot":null,"readId":"18446744073709551615","cacheHit":false,"watchOverflowRevision":null}],"failure":null}"#.to_vec(),
            br#"[[[[{"a":[1,2,3],"b":"\u00e9\ud83d\ude00"}]]]]"#.to_vec(),
        ]
    }

    fn mutate(random: &mut XorShift, input: &[u8]) -> Vec<u8> {
        let mut bytes = input.to_vec();
        for _ in 0..=random.below(4) {
            match random.below(6) {
                0 if !bytes.is_empty() => {
                    let index = random.below(bytes.len());
                    bytes[index] ^= 1 << random.below(8);
                }
                1 if !bytes.is_empty() => bytes.truncate(random.below(bytes.len())),
                2 => {
                    let index = random.below(bytes.len() + 1);
                    let token: &[u8] = [
                        &b"\""[..],
                        b"{",
                        b"}",
                        b"[",
                        b"]",
                        b",",
                        b":",
                        b"\\u",
                        b"-0",
                        b"1e9",
                        b"\xff",
                        b"\"a\":1,\"a\":2",
                    ][random.below(12)];
                    bytes.splice(index..index, token.iter().copied());
                }
                3 if bytes.len() > 1 => {
                    let start = random.below(bytes.len());
                    let end = (start + random.below(16)).min(bytes.len());
                    let slice = bytes[start..end].to_vec();
                    let at = random.below(bytes.len());
                    bytes.splice(at..at, slice);
                }
                4 => {
                    bytes = (0..random.below(64))
                        .map(|_| u8::try_from(random.next() & 0xff).unwrap_or(0))
                        .collect()
                }
                _ => {}
            }
        }
        bytes
    }

    #[test]
    fn parser_and_generated_decoders_fail_only_with_typed_errors() {
        let mut random = XorShift(SEED);
        let corpus = corpus();
        let (mut parsed, mut rejected) = (0, 0);
        for iteration in 0..ITERATIONS {
            let input = mutate(&mut random, &corpus[iteration % corpus.len()]);
            match parse(&input, ParseLimits::FRAME) {
                Ok(value) => {
                    parsed += 1;
                    // Any value is fed to decoders; they may only return errors.
                    let _ = crate::wire::generated::dec_native_repository_events_result(&value);
                    let _ = crate::wire::generated::dec_native_history_result(&value);
                    let _ = big_d::<u64>(&value);
                    let _ = bytes_d(&value);
                    // A value that parsed re-encodes to bytes that parse to the same value.
                    assert_eq!(
                        parse(&to_bytes(&value), ParseLimits::FRAME).ok(),
                        Some(value)
                    );
                }
                Err(_) => rejected += 1,
            }
        }
        assert_eq!(parsed + rejected, ITERATIONS);
        assert!(
            parsed > 0 && rejected > 0,
            "the corpus exercises both outcomes"
        );
    }
}
