//! Projections QML reads as plain values.

use serde::Serialize;
use serde_json::Value;

/// Serializes a projection; an unserializable value becomes null.
pub fn to_value(value: &impl Serialize) -> Value {
    serde_json::to_value(value).unwrap_or(Value::Null)
}

/// `value` with every whole-number float as an integer. QML hands every number
/// over as a float, which integer fields of a settings document reject.
pub fn integral_numbers(value: Value) -> Value {
    match value {
        Value::Number(number) if !number.is_i64() && !number.is_u64() => number
            .as_f64()
            .filter(|float| float.fract() == 0.0 && float.abs() < 2f64.powi(53))
            .map_or(Value::Number(number), |float| Value::from(float as i64)),
        Value::Array(values) => Value::Array(values.into_iter().map(integral_numbers).collect()),
        Value::Object(fields) => Value::Object(
            fields
                .into_iter()
                .map(|(key, value)| (key, integral_numbers(value)))
                .collect(),
        ),
        other => other,
    }
}

/// A non-negative whole number from QML, which hands numbers over as floats.
pub fn whole(value: &Value) -> Option<u64> {
    integral_numbers(value.clone()).as_u64()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn whole_floats_become_integers_and_fractions_stay() {
        let patch = json!({"windowWidth": 1100.0, "windowX": -40.0, "ratio": 0.5, "nested": [2.0], "flag": true});
        assert_eq!(
            integral_numbers(patch),
            json!({"windowWidth": 1100, "windowX": -40, "ratio": 0.5, "nested": [2], "flag": true})
        );
        let appearance: gitlama_contract::storage::NativeAppearanceSettings = serde_json::from_value(
            integral_numbers(json!({"windowWidth": 1100.0, "windowHeight": 700.0, "windowX": 0.0, "windowY": 0.0})),
        )
        .unwrap();
        assert_eq!(appearance.window_width, Some(1100));
        assert_eq!(whole(&json!(3.0)), Some(3));
        assert_eq!(whole(&json!(3)), Some(3));
        assert_eq!(whole(&json!(2.5)), None);
        assert_eq!(whole(&json!(-1.0)), None);
    }
}
