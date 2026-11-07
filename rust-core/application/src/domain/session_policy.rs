//! How repository sessions behave, chosen by whoever opens them.
//!
//! The desktop bridge opens sessions with [`SessionPolicy::DESKTOP`]. The headless remote helper
//! opens them with [`SessionPolicy::HELPER`]: status scans keep stat-cache refreshes private
//! instead of replacing the user's index, and caches use the helper budget.

/// The helper's shared Repository cache budget per session.
pub const SESSION_CACHE_BYTES: usize = 64 * 1024 * 1024;

/// What a session may do to the repository it reads, and how much it caches.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SessionPolicy {
    /// Shared Repository cache budget.
    pub cache_bytes: usize,
    /// Status scans refresh stat data privately instead of installing the user's index.
    pub private_index_refresh: bool,
}

impl SessionPolicy {
    /// The desktop application's sessions.
    pub const DESKTOP: Self = Self {
        cache_bytes: 512 * 1024 * 1024,
        private_index_refresh: false,
    };

    /// The remote helper's sessions.
    pub const HELPER: Self = Self {
        cache_bytes: SESSION_CACHE_BYTES,
        private_index_refresh: true,
    };
}
