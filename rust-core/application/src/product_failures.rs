//! Every family's failure kinds in the product taxonomy, checked as one closed set.
use crate::domain::failure::{product_failures, FailureCategory, ProductFailure};

/// Every family's product failures, in a fixed order.
fn all() -> Vec<ProductFailure> {
    let mut all = Vec::new();
    all.extend(product_failures::<crate::dto::NativeRepositoryFailureKind>());
    all.extend(product_failures::<crate::dto::NativeIndexLockFailureKind>());
    all.extend(product_failures::<crate::dto::NativeHistoryMetadataFailure>());
    all.extend(product_failures::<crate::dto::NativeCommitFailureKind>());
    all.extend(product_failures::<crate::dto::NativeCloneFailureKind>());
    all.extend(product_failures::<crate::stash::NativeStashFailureKind>());
    all.extend(product_failures::<crate::transfer::NativeTransferFailureKind>());
    all.extend(product_failures::<
        crate::named_snapshot::NativeNamedSnapshotFailureKind,
    >());
    all.extend(product_failures::<
        crate::extensions::NativeExtensionFailureKind,
    >());
    all.extend(product_failures::<
        crate::integrations::NativeIntegrationFailureKind,
    >());
    all.extend(product_failures::<crate::power_tools::NativePowerFailureKind>());
    all.extend(product_failures::<
        crate::history_operation::NativeHistoryMutationFailureKind,
    >());
    all.extend(product_failures::<
        crate::rebase_operation::NativeRebaseFailureKind,
    >());
    all.extend(product_failures::<
        crate::advanced_rebase::NativeAdvancedRebaseFailureKind,
    >());
    all.extend(product_failures::<crate::conflict::NativeConflictFailureKind>());
    all.extend(product_failures::<
        crate::diff_renderer::NativeDiffRendererFailureKind,
    >());
    all.extend(product_failures::<crate::storage::NativeSettingsFailureKind>());
    all.extend(product_failures::<crate::recovery::NativeRecoveryFailureKind>());
    all.extend(product_failures::<
        crate::view_cache::NativeViewCacheFailureKind,
    >());
    all.extend(product_failures::<
        crate::image_decoder::NativeImageDecodeFailureKind,
    >());
    // The desktop-only families, mapped in `desktop_families`.
    all.extend(product_failures::<
        gitlama_contract::hosting::NativeHostingFailureKind,
    >());
    all.extend(product_failures::<
        gitlama_contract::hosting_reference::NativeHostingReferenceFailure,
    >());
    all.extend(product_failures::<
        gitlama_contract::hosting_review::NativeHostingReviewFailure,
    >());
    all.extend(product_failures::<
        gitlama_contract::hosting_runtime::NativeHostingOAuthFailure,
    >());
    all.extend(product_failures::<
        gitlama_contract::hosting_runtime::NativeHostingResourceFailure,
    >());
    all.extend(product_failures::<
        gitlama_contract::cli_forwarding::NativeCliFailureKind,
    >());
    all
}

#[test]
fn every_failure_kind_has_one_stable_code() {
    let all = all();
    let mut details = all.iter().map(|failure| failure.detail).collect::<Vec<_>>();
    details.sort_unstable();
    let count = details.len();
    details.dedup();
    assert_eq!(details.len(), count, "a stable code names two kinds");
    // The recorded codes: changing one changes what diagnostics report.
    let recorded = include_str!("../test-fixtures/product_failures.txt");
    let current = all
        .iter()
        .map(|failure| format!("{} {}", failure.detail, failure.category.code()))
        .collect::<Vec<_>>()
        .join("\n");
    assert_eq!(current.trim(), recorded.trim());
}

#[test]
fn synonyms_across_families_share_one_category() {
    for failure in all() {
        let (_, kind) = failure.detail.split_once('.').unwrap();
        let expected = match kind {
            "Canceled" => Some(FailureCategory::Canceled),
            "TimedOut" => Some(FailureCategory::TimedOut),
            kind if kind.starts_with("Stale") => Some(FailureCategory::Stale),
            "UnknownSession" | "RetiredSession" => Some(FailureCategory::Stale),
            _ => None,
        };
        if let Some(expected) = expected {
            assert_eq!(failure.category, expected, "{}", failure.detail);
        }
    }
}
