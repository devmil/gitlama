//! The name, icon, colour or image that identifies each repository's tab, and the bounded images read for
//! them.

use crate::appearance::normalize_tab_name;
use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::session::display_path;
use crate::settings::{SettingsError, SettingsService};
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::storage::NativeRepositoryAppearance;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

/// Larger files are not icons; refusing them keeps a tab strip cheap.
pub const MAXIMUM_IMAGE_BYTES: u64 = 2 * 1024 * 1024;
/// Images are kept at most this many pixels on the longer side.
const IMAGE_SIDE: u32 = 64;

pub fn has_mark(appearance: &NativeRepositoryAppearance) -> bool {
    appearance.icon.is_some() || appearance.color.is_some() || appearance.image.is_some()
}

fn is_empty(appearance: &NativeRepositoryAppearance) -> bool {
    !has_mark(appearance) && appearance.name.is_none()
}

pub struct AppearanceService {
    settings: Rc<SettingsService>,
    notifier: Notifier,
    images: RefCell<HashMap<NativePathIdentity, Option<Rc<str>>>>,
    loading: RefCell<HashSet<NativePathIdentity>>,
}

impl AppearanceService {
    pub fn new(settings: Rc<SettingsService>, notifier: Notifier) -> Rc<Self> {
        Rc::new(Self {
            settings,
            notifier,
            images: RefCell::new(HashMap::new()),
            loading: RefCell::new(HashSet::new()),
        })
    }

    pub fn appearance_for(
        &self,
        identity: Option<&NativePathIdentity>,
    ) -> Option<NativeRepositoryAppearance> {
        let identity = identity?;
        self.settings.with(|document| {
            document
                .repository_appearances
                .iter()
                .find(|appearance| &appearance.identity == identity)
                .cloned()
        })
    }

    /// The name the user gave the tab, or None for the folder's.
    pub fn name_for(&self, identity: Option<&NativePathIdentity>) -> Option<String> {
        self.appearance_for(identity)
            .and_then(|appearance| appearance.name)
    }

    /// Names the tab; a blank name restores the folder's name.
    pub async fn rename(
        &self,
        identity: NativePathIdentity,
        name: Option<String>,
    ) -> Result<(), SettingsError> {
        let normalized = name.as_deref().and_then(normalize_tab_name);
        let mut current = self
            .appearance_for(Some(&identity))
            .unwrap_or_else(|| empty(identity.clone()));
        if current.name == normalized {
            return Ok(());
        }
        current.name = normalized;
        self.save(current).await
    }

    /// Removes the icon, colour and image, keeping the name.
    pub async fn remove_mark(&self, identity: NativePathIdentity) -> Result<(), SettingsError> {
        let mut current = self
            .appearance_for(Some(&identity))
            .unwrap_or_else(|| empty(identity.clone()));
        current.icon = None;
        current.color = None;
        current.image = None;
        self.save(current).await
    }

    /// Saves `appearance`; an empty one removes the repository's entry.
    pub async fn save(&self, appearance: NativeRepositoryAppearance) -> Result<(), SettingsError> {
        let result = self
            .settings
            .update_durable(
                |document| {
                    document
                        .repository_appearances
                        .retain(|entry| entry.identity != appearance.identity);
                    if !is_empty(&appearance) {
                        document.repository_appearances.push(appearance.clone());
                    }
                },
                |current, previous| {
                    current.repository_appearances = previous.repository_appearances.clone();
                },
            )
            .await;
        self.notifier.notify(Topics::WORKSPACE);
        result
    }

    /// The image at `path` as a PNG data URL once read; starts the read on
    /// first request and notifies when it finishes. None while reading or
    /// when unusable.
    pub fn image_at(self: &Rc<Self>, path: &NativePathIdentity) -> Option<Rc<str>> {
        if let Some(image) = self.images.borrow().get(path) {
            return image.clone();
        }
        if self.loading.borrow_mut().insert(path.clone()) {
            let this = Rc::clone(self);
            let path = path.clone();
            rt::spawn_detached(async move {
                let image = this.load(path.clone()).await;
                this.loading.borrow_mut().remove(&path);
                this.images.borrow_mut().insert(path, image.map(Rc::from));
                this.notifier.notify(Topics::WORKSPACE);
            });
        }
        None
    }

    /// Whether `path` was read and could not be used.
    pub fn image_failed(&self, path: &NativePathIdentity) -> bool {
        matches!(self.images.borrow().get(path), Some(None))
    }

    /// Forgets a read image, so an edited file shows its new content.
    pub fn forget_image(&self, path: &NativePathIdentity) {
        self.images.borrow_mut().remove(path);
    }

    async fn load(&self, path: NativePathIdentity) -> Option<String> {
        // A remote path is never read as a file on this computer.
        if path.remote.is_some() {
            return None;
        }
        let file = display_path(&path);
        rt::blocking(move || {
            let metadata = std::fs::metadata(&file).ok()?;
            if metadata.len() == 0 || metadata.len() > MAXIMUM_IMAGE_BYTES {
                return None;
            }
            let bytes = std::fs::read(&file).ok()?;
            crate::images::png_data_url(bytes, IMAGE_SIDE)
        })
        .await
    }
}

fn empty(identity: NativePathIdentity) -> NativeRepositoryAppearance {
    NativeRepositoryAppearance {
        identity,
        icon: None,
        color: None,
        image: None,
        name: None,
    }
}
