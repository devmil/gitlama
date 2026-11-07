//! Wall-clock readings in the units persisted records use. A clock before the epoch reads as
//! zero; one beyond the representable range saturates.
use std::time::{SystemTime, UNIX_EPOCH};

/// Milliseconds since the Unix epoch.
#[must_use]
pub fn unix_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

/// Seconds since the Unix epoch.
#[must_use]
pub fn unix_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    #[test]
    fn readings_agree() {
        let seconds = super::unix_seconds();
        let millis = super::unix_millis();
        assert!(millis / 1000 >= seconds);
        assert!(millis / 1000 - seconds <= 1);
    }
}
