//! The application's private, bounded diagnostic history (the devmil-logging
//! contract): reviewed codes with public or
//! numeric fields, kept in memory only. Detailed capture is off by default and
//! expires after at most fifteen minutes. Native events recorded through
//! `devmil_logging` are drained into the same history.

use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub const MAX_EVENTS: usize = 1000;
pub const MAX_BYTES: usize = 256 * 1024;
pub const MAX_EVENT_BYTES: usize = 2048;
pub const MAX_DETAILED: Duration = Duration::from_secs(15 * 60);

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    Fine,
    Info,
    Warning,
    Severe,
}

impl Level {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Fine => "FINE",
            Self::Info => "INFO",
            Self::Warning => "WARNING",
            Self::Severe => "SEVERE",
        }
    }
}

/// A field value: public text (codes, enum names) or a number.
#[derive(Clone, Debug)]
pub enum Field {
    Text(String),
    Number(f64),
}

impl From<&str> for Field {
    fn from(value: &str) -> Self {
        Self::Text(value.to_owned())
    }
}
impl From<String> for Field {
    fn from(value: String) -> Self {
        Self::Text(value)
    }
}
impl From<u64> for Field {
    fn from(value: u64) -> Self {
        Self::Number(value as f64)
    }
}
impl From<usize> for Field {
    fn from(value: usize) -> Self {
        Self::Number(value as f64)
    }
}
impl From<i64> for Field {
    fn from(value: i64) -> Self {
        Self::Number(value as f64)
    }
}
impl From<u32> for Field {
    fn from(value: u32) -> Self {
        Self::Number(f64::from(value))
    }
}
impl From<f64> for Field {
    fn from(value: f64) -> Self {
        Self::Number(value)
    }
}
impl From<bool> for Field {
    fn from(value: bool) -> Self {
        Self::Text(value.to_string())
    }
}

struct History {
    events: VecDeque<String>,
    bytes: usize,
    detailed_until: Option<Instant>,
}

static HISTORY: Mutex<History> = Mutex::new(History {
    events: VecDeque::new(),
    bytes: 0,
    detailed_until: None,
});

fn valid_code(code: &str) -> bool {
    let bytes = code.as_bytes();
    !bytes.is_empty()
        && bytes.len() <= 101
        && bytes[0].is_ascii_alphabetic()
        && bytes[1..]
            .iter()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'.' | b'-'))
}

/// Removes what could identify a person, a path or a secret from public text.
pub fn redact(value: &str) -> String {
    let mut out = String::with_capacity(value.len().min(520));
    for word in value.split_inclusive(char::is_whitespace) {
        let trimmed = word.trim_end();
        let suffix = &word[trimmed.len()..];
        let lower = trimmed.to_ascii_lowercase();
        let replaced = if lower.starts_with("http://") || lower.starts_with("https://") {
            "<redacted-uri>".to_owned()
        } else if trimmed.contains('@') && trimmed.contains('.') {
            "<redacted-email>".to_owned()
        } else if trimmed.starts_with('/')
            || (trimmed.len() > 2
                && trimmed.as_bytes()[1] == b':'
                && matches!(trimmed.as_bytes()[2], b'\\' | b'/'))
        {
            "<redacted-path>".to_owned()
        } else if ["password", "token", "secret", "cookie", "authorization"]
            .iter()
            .any(|secret| lower.contains(secret) && (lower.contains('=') || lower.contains(':')))
        {
            "<redacted>".to_owned()
        } else {
            trimmed.to_owned()
        };
        out.push_str(&replaced);
        out.push_str(suffix);
    }
    if out.chars().count() > 512 {
        let cut: String = out.chars().take(512).collect();
        return format!("{cut}…<truncated>");
    }
    out
}

fn iso_now() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let seconds = now.as_secs() as i64;
    let millis = now.subsec_millis();
    let days = seconds.div_euclid(86_400);
    let rest = seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{millis:03}Z",
        rest / 3600,
        (rest % 3600) / 60,
        rest % 60
    )
}

fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

fn admit(line: String) {
    if line.len() > MAX_EVENT_BYTES {
        return;
    }
    let Ok(mut history) = HISTORY.lock() else {
        return;
    };
    while history.events.len() >= MAX_EVENTS || history.bytes + line.len() > MAX_BYTES {
        match history.events.pop_front() {
            Some(old) => history.bytes -= old.len(),
            None => break,
        }
    }
    history.bytes += line.len();
    history.events.push_back(line);
}

fn detailed_active() -> bool {
    HISTORY
        .lock()
        .ok()
        .and_then(|history| history.detailed_until)
        .is_some_and(|until| Instant::now() < until)
}

/// Whether detailed diagnostic capture is currently active.
pub fn is_detailed() -> bool {
    detailed_active()
}

/// Records `code` from `component`. FINE events are kept only while detailed
/// capture is on.
pub fn record(level: Level, component: &str, code: &str, fields: &[(&str, Field)]) {
    if !valid_code(code) || !valid_code(component) {
        return;
    }
    if level == Level::Fine && !detailed_active() {
        return;
    }
    let mut line = format!("{} {} {component}: {code}", iso_now(), level.name());
    for (key, value) in fields {
        if !valid_code(key) {
            continue;
        }
        let rendered = match value {
            Field::Text(text) => redact(text),
            Field::Number(number) if number.is_finite() => {
                if number.fract() == 0.0 && number.abs() < 1e15 {
                    format!("{}", *number as i64)
                } else {
                    format!("{number}")
                }
            }
            Field::Number(_) => continue,
        };
        line.push_str(&format!(" {key}={rendered}"));
    }
    admit(line);
}

pub fn info(component: &str, code: &str, fields: &[(&str, Field)]) {
    record(Level::Info, component, code, fields);
}

pub fn warning(component: &str, code: &str, fields: &[(&str, Field)]) {
    record(Level::Warning, component, code, fields);
}

pub fn severe(component: &str, code: &str, fields: &[(&str, Field)]) {
    record(Level::Severe, component, code, fields);
}

pub fn debug(component: &str, code: &str, fields: &[(&str, Field)]) {
    record(Level::Fine, component, code, fields);
}

/// Moves the native layer's bounded events into the history.
pub fn drain_native() {
    for line in devmil_logging_drain() {
        admit(format!("{} NATIVE {}", iso_now(), redact(&line)));
    }
}

fn devmil_logging_drain() -> Vec<String> {
    gitlama_core::api::drain_native_diagnostics()
}

/// Turns detailed capture on for at most [`MAX_DETAILED`], or off.
pub fn set_detailed(enabled: bool) {
    if let Ok(mut history) = HISTORY.lock() {
        history.detailed_until = enabled.then(|| Instant::now() + MAX_DETAILED);
    }
    gitlama_core::api::configure_native_diagnostics(enabled, false);
}

/// When detailed capture ends, or None when it is off.
pub fn detailed_remaining() -> Option<Duration> {
    let until = HISTORY.lock().ok()?.detailed_until?;
    until.checked_duration_since(Instant::now())
}

/// Erases the history, including detailed events.
pub fn clear() {
    if let Ok(mut history) = HISTORY.lock() {
        history.events.clear();
        history.bytes = 0;
    }
    gitlama_core::api::configure_native_diagnostics(detailed_active(), true);
}

/// The retained history, oldest first.
pub fn snapshot() -> Vec<String> {
    drain_native();
    HISTORY
        .lock()
        .map(|history| history.events.iter().cloned().collect())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redaction_hides_paths_addresses_and_secrets() {
        assert_eq!(
            redact("open /home/someone/repo failed"),
            "open <redacted-path> failed"
        );
        assert_eq!(redact("see https://example.com/x"), "see <redacted-uri>");
        assert_eq!(redact("a@b.example"), "<redacted-email>");
        assert_eq!(redact("token=abc"), "<redacted>");
        assert_eq!(redact("C:\\Users\\x"), "<redacted-path>");
        assert_eq!(redact("plain_code"), "plain_code");
    }

    #[test]
    fn fine_events_need_detailed_capture() {
        clear();
        set_detailed(false);
        assert!(!is_detailed());
        debug("Test", "fine_event", &[]);
        assert!(!snapshot().iter().any(|line| line.contains("fine_event")));
        info("Test", "info_event", &[("count", 3_u64.into())]);
        assert!(
            snapshot()
                .iter()
                .any(|line| line.ends_with("Test: info_event count=3"))
        );
        set_detailed(true);
        assert!(is_detailed());
        debug(
            "Test",
            "fine_event_enabled",
            &[("elapsed_ms", 12_u64.into())],
        );
        assert!(
            snapshot()
                .iter()
                .any(|line| line.ends_with("Test: fine_event_enabled elapsed_ms=12"))
        );
        set_detailed(false);
    }
}
