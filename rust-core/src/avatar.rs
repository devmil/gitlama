//! Bounded, opt-in avatar loading. Hashes are supplied by the Git adapter.
pub use gitlama_contract::avatar::*;
use std::collections::HashMap;
use std::io::{Cursor, Write};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

const IMAGE_TTL: Duration = Duration::from_secs(24 * 60 * 60);
const MISS_TTL: Duration = Duration::from_secs(5 * 60);
const MAX_IMAGE_BYTES: usize = 128 * 1024;
const MAX_ENTRIES: usize = 256;

struct Entry {
    image: Option<NativeAvatarImage>,
    expires: Instant,
}

static CACHE: OnceLock<Mutex<HashMap<String, Entry>>> = OnceLock::new();
static CACHE_GENERATION: AtomicU64 = AtomicU64::new(0);

fn cache() -> &'static Mutex<HashMap<String, Entry>> {
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn valid_hash(hash: &str) -> bool {
    hash.len() == 64
        && hash
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

pub fn avatar_image(hash: String, enabled: bool) -> Option<NativeAvatarImage> {
    cached_image(hash, enabled, Instant::now(), fetch_gravatar)
}

fn cached_image(
    hash: String,
    enabled: bool,
    now: Instant,
    fetch: impl FnOnce(&str) -> Option<Vec<u8>>,
) -> Option<NativeAvatarImage> {
    if !enabled || !valid_hash(&hash) {
        return None;
    }
    let generation = CACHE_GENERATION.load(Ordering::Acquire);
    if let Ok(entries) = cache().lock() {
        if let Some(entry) = entries.get(&hash) {
            if entry.expires > now {
                return entry.image.clone();
            }
        }
    }
    let image = fetch(&hash).map(|bytes| NativeAvatarImage {
        source: NativeAvatarSource::Gravatar,
        bytes,
    });
    if CACHE_GENERATION.load(Ordering::Acquire) != generation {
        return None;
    }
    if let Ok(mut entries) = cache().lock() {
        if CACHE_GENERATION.load(Ordering::Acquire) != generation {
            return None;
        }
        entries.retain(|_, entry| entry.expires > now);
        if entries.len() >= MAX_ENTRIES {
            if let Some(oldest) = entries
                .iter()
                .min_by_key(|(_, entry)| entry.expires)
                .map(|(key, _)| key.clone())
            {
                entries.remove(&oldest);
            }
        }
        entries.insert(
            hash,
            Entry {
                expires: now + if image.is_some() { IMAGE_TTL } else { MISS_TTL },
                image: image.clone(),
            },
        );
    }
    image
}

pub fn avatar_clear_cache() {
    CACHE_GENERATION.fetch_add(1, Ordering::AcqRel);
    if let Ok(mut entries) = cache().lock() {
        entries.clear();
    }
}

fn fetch_gravatar(hash: &str) -> Option<Vec<u8>> {
    let url = format!("https://gravatar.com/avatar/{hash}?s=64&r=g&d=404");
    let mut child = Command::new("curl")
        .args([
            "-q",
            "--fail",
            "--silent",
            "--max-time",
            "5",
            "--connect-timeout",
            "3",
            "--max-filesize",
            "131072",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--max-redirs",
            "0",
            "--output",
            "-",
            "--config",
            "-",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let config = format!("url = \"{url}\"\n");
    let Some(mut stdin) = child.stdin.take() else {
        let _ = child.kill();
        let _ = child.wait();
        return None;
    };
    if stdin.write_all(config.as_bytes()).is_err() {
        let _ = child.kill();
        let _ = child.wait();
        return None;
    }
    drop(stdin);
    let output = child.wait_with_output().ok()?;
    if !output.status.success() || output.stdout.is_empty() || output.stdout.len() > MAX_IMAGE_BYTES
    {
        return None;
    }
    let format = image::guess_format(&output.stdout).ok()?;
    if !matches!(
        format,
        image::ImageFormat::Png
            | image::ImageFormat::Jpeg
            | image::ImageFormat::WebP
            | image::ImageFormat::Gif
    ) {
        return None;
    }
    let mut reader = image::ImageReader::new(Cursor::new(&output.stdout));
    reader.set_format(format);
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(256);
    limits.max_image_height = Some(256);
    limits.max_alloc = Some(4 * 1024 * 1024);
    reader.limits(limits);
    reader.decode().ok()?;
    Some(output.stdout)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    static TEST_CACHE_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn disabled_or_invalid_hash_never_fetches() {
        assert_eq!(avatar_image("a".repeat(64), false), None);
        assert_eq!(avatar_image("../unsafe".into(), true), None);
        assert_eq!(avatar_image("A".repeat(64), true), None);
    }

    #[test]
    fn positive_and_negative_entries_have_bounded_ttls() {
        let _guard = TEST_CACHE_LOCK.lock().unwrap();
        avatar_clear_cache();
        let now = Instant::now();
        let hash = "b".repeat(64);
        let calls = Cell::new(0);
        let fetch = |_: &str| {
            calls.set(calls.get() + 1);
            Some(vec![1, 2, 3])
        };
        assert!(cached_image(hash.clone(), true, now, fetch).is_some());
        assert!(cached_image(
            hash.clone(),
            true,
            now + IMAGE_TTL - Duration::from_secs(1),
            fetch
        )
        .is_some());
        assert_eq!(calls.get(), 1);
        assert!(cached_image(hash, true, now + IMAGE_TTL, fetch).is_some());
        assert_eq!(calls.get(), 2);

        let missing = "c".repeat(64);
        let misses = Cell::new(0);
        let missing_fetch = |_: &str| {
            misses.set(misses.get() + 1);
            None
        };
        assert!(cached_image(missing.clone(), true, now, missing_fetch).is_none());
        assert!(cached_image(
            missing.clone(),
            true,
            now + MISS_TTL - Duration::from_secs(1),
            missing_fetch
        )
        .is_none());
        assert_eq!(misses.get(), 1);
        assert!(cached_image(missing, true, now + MISS_TTL, missing_fetch).is_none());
        assert_eq!(misses.get(), 2);
        avatar_clear_cache();
    }

    #[test]
    fn clearing_during_a_fetch_discards_its_result() {
        let _guard = TEST_CACHE_LOCK.lock().unwrap();
        avatar_clear_cache();
        let hash = "d".repeat(64);
        let result = cached_image(hash.clone(), true, Instant::now(), |_| {
            avatar_clear_cache();
            Some(vec![1])
        });
        assert!(result.is_none());
        assert!(!cache().lock().unwrap().contains_key(&hash));
    }
}
