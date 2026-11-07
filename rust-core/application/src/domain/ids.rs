//! Application-owned identities.

/// A repository session as its caller names it: the session's identity and the generation the
/// caller opened. Reopening a repository starts a new generation, so a key from before the
/// reopen no longer reaches the session.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct SessionKey {
    pub id: u64,
    pub generation: u64,
}

impl SessionKey {
    #[must_use]
    pub const fn new(id: u64, generation: u64) -> Self {
        Self { id, generation }
    }
}
