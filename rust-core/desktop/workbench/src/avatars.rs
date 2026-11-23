//! Author images from Gravatar: only while the
//! person enabled them, by the 64-character hash History rows carry; each
//! image loads once and is kept as a data URL. Turning them off clears the
//! cache.

use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::settings::SettingsService;
use base64::Engine;
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

/// A Gravatar hash: 64 lowercase hexadecimal characters.
pub fn valid_hash(hash: &str) -> bool {
    hash.len() == 64 && hash.bytes().all(|byte| byte.is_ascii_hexdigit())
}

/// The data URL of image `bytes`, by their signature.
pub fn data_url(bytes: &[u8]) -> Option<String> {
    let mime = if bytes.starts_with(&[0x89, b'P', b'N', b'G']) {
        "image/png"
    } else if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        "image/jpeg"
    } else if bytes.starts_with(b"GIF8") {
        "image/gif"
    } else if bytes.len() > 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        "image/webp"
    } else {
        return None;
    };
    Some(format!(
        "data:{mime};base64,{}",
        base64::engine::general_purpose::STANDARD.encode(bytes)
    ))
}

pub struct Avatars {
    settings: Rc<SettingsService>,
    notifier: Notifier,
    images: RefCell<HashMap<String, String>>,
    pending: RefCell<HashSet<String>>,
    enabled: Cell<bool>,
    generation: Cell<u64>,
}

impl Avatars {
    pub fn new(settings: Rc<SettingsService>, notifier: Notifier) -> Rc<Self> {
        let enabled = settings.with(|document| document.appearance.gravatar_enabled);
        Rc::new(Self {
            settings,
            notifier,
            images: RefCell::new(HashMap::new()),
            pending: RefCell::new(HashSet::new()),
            enabled: Cell::new(enabled),
            generation: Cell::new(0),
        })
    }

    pub fn enabled(&self) -> bool {
        self.enabled.get()
    }

    /// Follows the setting; turning it off forgets every image.
    pub fn sync(&self) {
        let enabled = self
            .settings
            .with(|document| document.appearance.gravatar_enabled);
        if enabled == self.enabled.get() {
            return;
        }
        self.enabled.set(enabled);
        self.generation.set(self.generation.get() + 1);
        self.images.borrow_mut().clear();
        self.pending.borrow_mut().clear();
        if !enabled {
            rt::spawn_detached(async { rt::blocking(gitlama_core::api::avatar_clear_cache).await });
        }
        self.notifier.notify(Topics::EVENTS);
    }

    pub fn images(&self) -> HashMap<String, String> {
        self.images.borrow().clone()
    }

    /// Loads the image of `hash` once, while enabled.
    pub fn request(self: &Rc<Self>, hash: String) {
        if !self.enabled.get()
            || !valid_hash(&hash)
            || self.images.borrow().contains_key(&hash)
            || !self.pending.borrow_mut().insert(hash.clone())
        {
            return;
        }
        let generation = self.generation.get();
        let this = Rc::clone(self);
        rt::spawn_detached(async move {
            let key = hash.clone();
            let image = rt::blocking(move || gitlama_core::api::avatar_image(key, true)).await;
            if this.generation.get() != generation {
                return;
            }
            this.pending.borrow_mut().remove(&hash);
            if let Some(url) = image.and_then(|image| data_url(&image.bytes)) {
                this.images.borrow_mut().insert(hash, url);
                this.notifier.notify(Topics::EVENTS);
            }
        });
    }

    pub fn set_enabled(&self, enabled: bool) -> bool {
        self.settings
            .update(|document| document.appearance.gravatar_enabled = enabled)
            .is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hashes_and_images_are_checked() {
        assert!(valid_hash(&"a".repeat(64)));
        assert!(!valid_hash("abc"));
        assert!(
            data_url(&[0x89, b'P', b'N', b'G', 0])
                .unwrap()
                .starts_with("data:image/png;base64,")
        );
        assert!(data_url(b"<svg/>").is_none());
    }
}
