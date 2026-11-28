//! Development timing: with `GITLAMA_DEV_SPANS=<ms>` set, GUI-thread spans
//! that take at least that long are written to standard error by their
//! static name only, in order with Qt's own messages.

use std::sync::OnceLock;
use std::time::Instant;

fn threshold() -> Option<f64> {
    static THRESHOLD: OnceLock<Option<f64>> = OnceLock::new();
    *THRESHOLD.get_or_init(|| {
        std::env::var("GITLAMA_DEV_SPANS")
            .ok()
            .and_then(|value| value.parse::<f64>().ok())
    })
}

pub(crate) struct Span {
    name: &'static str,
    start: Option<Instant>,
}

impl Span {
    pub(crate) fn new(name: &'static str) -> Self {
        Self {
            name,
            start: threshold().map(|_| Instant::now()),
        }
    }
}

impl Drop for Span {
    fn drop(&mut self) {
        if let (Some(start), Some(threshold)) = (self.start, threshold()) {
            let elapsed = start.elapsed().as_secs_f64() * 1000.0;
            if elapsed >= threshold {
                eprintln!("gitlama-dev-span {} {elapsed:.1}", self.name);
            }
        }
    }
}
