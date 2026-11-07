//! Length-prefixed frames on blocking byte streams.
use std::io::{self, Read, Write};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// The largest frame payload either peer accepts.
pub const MAX_FRAME_BYTES: usize = gitlama_application::wire::contract::FRAME_BYTES;
/// The largest hello or hello acknowledgement.
pub const MAX_HELLO_BYTES: usize = gitlama_application::wire::contract::HELLO_BYTES;
/// How long one frame may take from its first byte to its last.
pub const PARTIAL_FRAME_DEADLINE: Duration = Duration::from_secs(15);

#[derive(Debug, Eq, PartialEq)]
pub enum FrameError {
    /// The stream ended cleanly between frames.
    End,
    /// The stream ended or failed inside a frame.
    Truncated,
    /// A zero or oversized length; nothing was allocated for it.
    Length,
}

/// Records when the frame being read started, so a watchdog can enforce the absolute
/// partial-frame deadline while the reader is blocked.
#[derive(Clone)]
pub struct FrameClock {
    origin: Instant,
    started_millis: Arc<AtomicU64>,
}

impl FrameClock {
    #[must_use]
    pub fn new() -> Self {
        Self {
            origin: Instant::now(),
            started_millis: Arc::new(AtomicU64::new(0)),
        }
    }

    fn start(&self) {
        let elapsed = u64::try_from(self.origin.elapsed().as_millis()).unwrap_or(u64::MAX);
        self.started_millis.store(elapsed.max(1), Ordering::Release);
    }

    fn finish(&self) {
        self.started_millis.store(0, Ordering::Release);
    }

    /// Whether a frame has been incomplete for longer than the deadline.
    #[must_use]
    pub fn expired(&self) -> bool {
        let started = self.started_millis.load(Ordering::Acquire);
        if started == 0 {
            return false;
        }
        let now = u64::try_from(self.origin.elapsed().as_millis()).unwrap_or(u64::MAX);
        now.saturating_sub(started) > u64::try_from(PARTIAL_FRAME_DEADLINE.as_millis()).unwrap_or(0)
    }
}

impl Default for FrameClock {
    fn default() -> Self {
        Self::new()
    }
}

/// Reads one frame of at most `limit` bytes.
///
/// # Errors
/// End of stream, truncation or an invalid length.
pub fn read_frame(
    input: &mut impl Read,
    limit: usize,
    clock: &FrameClock,
) -> Result<Vec<u8>, FrameError> {
    let mut header = [0_u8; 4];
    let mut filled = 0;
    while filled < header.len() {
        match input.read(&mut header[filled..]) {
            Ok(0) => {
                clock.finish();
                return Err(if filled == 0 {
                    FrameError::End
                } else {
                    FrameError::Truncated
                });
            }
            Ok(read) => {
                if filled == 0 {
                    clock.start();
                }
                filled += read;
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
            Err(_) => {
                clock.finish();
                return Err(FrameError::Truncated);
            }
        }
    }
    let length = u32::from_be_bytes(header) as usize;
    if length == 0 || length > limit {
        clock.finish();
        return Err(FrameError::Length);
    }
    let mut payload = vec![0_u8; length];
    let result = input.read_exact(&mut payload);
    clock.finish();
    result.map_err(|_| FrameError::Truncated)?;
    Ok(payload)
}

/// Writes one frame and flushes it.
///
/// # Errors
/// The underlying write failed or the payload is not a valid frame size.
pub fn write_frame(output: &mut impl Write, payload: &[u8]) -> io::Result<()> {
    if payload.is_empty() || payload.len() > MAX_FRAME_BYTES {
        return Err(io::ErrorKind::InvalidInput.into());
    }
    let length = u32::try_from(payload.len()).map_err(|_| io::ErrorKind::InvalidInput)?;
    output.write_all(&length.to_be_bytes())?;
    output.write_all(payload)?;
    output.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Dribble(Vec<u8>, usize);

    impl Read for Dribble {
        fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
            if self.1 >= self.0.len() || buffer.is_empty() {
                return Ok(0);
            }
            buffer[0] = self.0[self.1];
            self.1 += 1;
            Ok(1)
        }
    }

    #[test]
    fn frames_split_at_every_byte_and_coalesced_frames_decode() {
        let mut bytes = Vec::new();
        write_frame(&mut bytes, b"{\"a\":1}").unwrap();
        write_frame(&mut bytes, b"[]").unwrap();
        let clock = FrameClock::new();
        let mut dribble = Dribble(bytes.clone(), 0);
        assert_eq!(read_frame(&mut dribble, 64, &clock).unwrap(), b"{\"a\":1}");
        assert_eq!(read_frame(&mut dribble, 64, &clock).unwrap(), b"[]");
        assert_eq!(read_frame(&mut dribble, 64, &clock), Err(FrameError::End));
        let mut whole = io::Cursor::new(bytes);
        assert_eq!(read_frame(&mut whole, 64, &clock).unwrap(), b"{\"a\":1}");
        assert_eq!(read_frame(&mut whole, 64, &clock).unwrap(), b"[]");
        assert!(!clock.expired());
    }

    #[test]
    fn invalid_lengths_are_rejected_before_allocation() {
        let clock = FrameClock::new();
        for header in [0_u32, u32::try_from(MAX_FRAME_BYTES + 1).unwrap(), u32::MAX] {
            let mut input = io::Cursor::new(header.to_be_bytes().to_vec());
            assert_eq!(
                read_frame(&mut input, MAX_FRAME_BYTES, &clock),
                Err(FrameError::Length)
            );
        }
        let mut truncated = io::Cursor::new(vec![0, 0, 0, 4, b'{']);
        assert_eq!(
            read_frame(&mut truncated, 64, &clock),
            Err(FrameError::Truncated)
        );
        let mut half_header = io::Cursor::new(vec![0, 0]);
        assert_eq!(
            read_frame(&mut half_header, 64, &clock),
            Err(FrameError::Truncated)
        );
        assert!(write_frame(&mut Vec::new(), b"").is_err());
    }
}
