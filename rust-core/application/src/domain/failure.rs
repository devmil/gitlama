//! The product failure taxonomy: one closed set of categories every family's failure kinds
//! map into, with a stable code per kind.
//!
//! The families keep their own failure enums: they are the bridge and wire contracts the
//! client already maps and localizes. Each family states, in one place next to its enum, which
//! category every kind belongs to, so synonyms across families (fourteen `Canceled` kinds, the
//! stale preview, generation, revision and authorization kinds) are one category here.

/// What kind of failure a product failure is, whichever family reported it.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum FailureCategory {
    /// The request itself was malformed or incomplete.
    InvalidRequest,
    /// The repository is not in a state the operation accepts: dirty, detached, busy with
    /// another operation, or missing what the operation needs.
    Precondition,
    /// What the request named does not exist.
    NotFound,
    /// The preview, session or revision the request relied on changed.
    Stale,
    /// The operation stopped at conflicts.
    Conflict,
    /// Another operation holds what this one needs, or a capacity is reached.
    Busy,
    Canceled,
    TimedOut,
    /// An input or output exceeded its bound.
    TooLarge,
    /// A tool, service or platform capability is not available.
    Unavailable,
    /// The operation is not supported for this repository or input.
    Unsupported,
    /// Credentials, tokens or host keys were missing, refused or untrusted.
    Authentication,
    PermissionDenied,
    /// A hook, a server or an external program refused the change.
    Rejected,
    /// The external effect may have happened but could not be confirmed.
    Uncertain,
    Read,
    Write,
    /// Git failed.
    Git,
    /// Output or state GitLama could not interpret.
    Internal,
}

impl FailureCategory {
    /// The stable code of the category.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::InvalidRequest => "invalidRequest",
            Self::Precondition => "precondition",
            Self::NotFound => "notFound",
            Self::Stale => "stale",
            Self::Conflict => "conflict",
            Self::Busy => "busy",
            Self::Canceled => "canceled",
            Self::TimedOut => "timedOut",
            Self::TooLarge => "tooLarge",
            Self::Unavailable => "unavailable",
            Self::Unsupported => "unsupported",
            Self::Authentication => "authentication",
            Self::PermissionDenied => "permissionDenied",
            Self::Rejected => "rejected",
            Self::Uncertain => "uncertain",
            Self::Read => "read",
            Self::Write => "write",
            Self::Git => "git",
            Self::Internal => "internal",
        }
    }
}

/// A failure in product terms: its category and the stable code of the family kind behind it
/// (`family.Kind`). Neither carries user content.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct ProductFailure {
    pub category: FailureCategory,
    pub detail: &'static str,
}

/// A family's failure kind, mapped into the product taxonomy.
pub trait FamilyFailure: Copy + 'static {
    /// Every kind of the family, for exhaustive checks.
    const ALL: &'static [Self];

    fn product_failure(self) -> ProductFailure;
}

/// Maps a family failure enum into the taxonomy: `family_failures!(Enum, "family", { Kind =>
/// Category, … })`. The match is exhaustive, so a new kind needs a category.
#[macro_export]
macro_rules! family_failures {
    ($kind:ident, $family:literal, { $($variant:ident => $category:ident),* $(,)? }) => {
        impl $crate::domain::failure::FamilyFailure for $kind {
            const ALL: &'static [Self] = &[$($kind::$variant),*];

            fn product_failure(self) -> $crate::domain::failure::ProductFailure {
                match self {
                    $($kind::$variant => $crate::domain::failure::ProductFailure {
                        category: $crate::domain::failure::FailureCategory::$category,
                        detail: concat!($family, ".", stringify!($variant)),
                    },)*
                }
            }
        }
    };
}

/// The product failures of every kind of `F`.
#[must_use]
pub fn product_failures<F: FamilyFailure>() -> Vec<ProductFailure> {
    F::ALL.iter().map(|kind| kind.product_failure()).collect()
}
