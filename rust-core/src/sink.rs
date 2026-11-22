//! A callback sink for events a background thread reports to the application.

use std::sync::Arc;

/// Delivers events to the application. `add` fails once the receiver is gone,
/// so the producer can stop.
pub struct StreamSink<T> {
    deliver: Arc<dyn Fn(T) -> bool + Send + Sync>,
}

impl<T> StreamSink<T> {
    pub fn new(deliver: impl Fn(T) -> bool + Send + Sync + 'static) -> Self {
        Self {
            deliver: Arc::new(deliver),
        }
    }

    /// Delivers `event`; an error means the receiver no longer listens.
    #[allow(clippy::result_unit_err)]
    pub fn add(&self, event: T) -> Result<(), ()> {
        if (self.deliver)(event) {
            Ok(())
        } else {
            Err(())
        }
    }
}

impl<T> Clone for StreamSink<T> {
    fn clone(&self) -> Self {
        Self {
            deliver: Arc::clone(&self.deliver),
        }
    }
}
