pub use gitlama_contract::hosting_reference::*;

use crate::hosting::NativeHostingRemoteReference;

const MAX_EDITOR_UNITS: usize = 32 * 1024;
const MAX_REFERENCE_ITEMS: usize = 50;

#[must_use]
pub fn project(
    text: Vec<u16>,
    selection_base: u32,
    selection_extent: u32,
    revision: u64,
    references: Vec<NativeHostingRemoteReference>,
    stale: bool,
) -> NativeHostingReferenceProjectionResult {
    if text.len() > MAX_EDITOR_UNITS || references.len() > 200 {
        return projection_failure(NativeHostingReferenceFailure::InvalidRequest);
    }
    let (Ok(base), Ok(extent)) = (
        usize::try_from(selection_base),
        usize::try_from(selection_extent),
    ) else {
        return projection_failure(NativeHostingReferenceFailure::InvalidRequest);
    };
    if base > text.len() || extent > text.len() {
        return no_projection();
    }
    let selection_start = base.min(extent);
    let selection_end = base.max(extent);
    let (hash_index, caret) = if selection_start == selection_end {
        let Some(hash_index) = text[..extent]
            .iter()
            .rposition(|unit| *unit == u16::from(b'#'))
        else {
            return no_projection();
        };
        (hash_index, extent)
    } else {
        if text.get(selection_start) != Some(&u16::from(b'#')) {
            return no_projection();
        }
        (selection_start, selection_end)
    };
    if hash_index > 0 {
        let previous = text[hash_index - 1];
        if previous == u16::from(b'\\') || is_token_unit(previous) {
            return no_projection();
        }
    }
    let query_units = &text[hash_index + 1..caret];
    if query_units.iter().any(|unit| {
        *unit == u16::from(b'#')
            || char::from_u32(u32::from(*unit)).is_some_and(char::is_whitespace)
    }) {
        return no_projection();
    }
    let Ok(query) = String::from_utf16(query_units) else {
        return projection_failure(NativeHostingReferenceFailure::InvalidRequest);
    };
    let normalized_query = query.to_lowercase();
    let mut candidates = references
        .into_iter()
        .filter(|reference| {
            normalized_query.is_empty()
                || reference.title.to_lowercase().contains(&normalized_query)
                || reference
                    .insertion
                    .to_lowercase()
                    .contains(&normalized_query)
                || reference.number.to_string().contains(&normalized_query)
        })
        .take(MAX_REFERENCE_ITEMS)
        .map(|reference| NativeHostingReferenceCandidate {
            stable_id: reference.stable_id,
            kind: reference.kind,
            number: reference.number,
            title: reference.title,
            insertion: reference.insertion,
            web_url: reference.web_url,
            stale,
        })
        .collect::<Vec<_>>();
    candidates.sort_by(|left, right| {
        left.number
            .cmp(&right.number)
            .then_with(|| left.stable_id.cmp(&right.stable_id))
    });
    NativeHostingReferenceProjectionResult {
        projection: Some(NativeHostingReferenceProjection {
            revision,
            text_hash: editor_hash(&text),
            replace_start: u32::try_from(hash_index).unwrap_or(u32::MAX),
            replace_end: u32::try_from(caret).unwrap_or(u32::MAX),
            query,
            candidates,
        }),
        failure: None,
    }
}

#[must_use]
pub fn apply(
    text: Vec<u16>,
    current_revision: u64,
    expected_revision: u64,
    expected_text_hash: u64,
    replace_start: u32,
    replace_end: u32,
    insertion: String,
) -> NativeHostingReferenceApplyResult {
    if current_revision != expected_revision {
        return apply_failure(text, NativeHostingReferenceFailure::StaleRevision);
    }
    if editor_hash(&text) != expected_text_hash {
        return apply_failure(text, NativeHostingReferenceFailure::ChangedText);
    }
    let (Ok(start), Ok(end)) = (usize::try_from(replace_start), usize::try_from(replace_end))
    else {
        return apply_failure(text, NativeHostingReferenceFailure::StaleRange);
    };
    if start >= end || end > text.len() || text[start] != u16::from(b'#') {
        return apply_failure(text, NativeHostingReferenceFailure::StaleRange);
    }
    if insertion.is_empty()
        || insertion.len() > 2048
        || insertion.chars().any(|character| character.is_control())
    {
        return apply_failure(text, NativeHostingReferenceFailure::InvalidRequest);
    }
    let insertion = insertion.encode_utf16().collect::<Vec<_>>();
    let mut output = Vec::with_capacity(text.len() - (end - start) + insertion.len());
    output.extend_from_slice(&text[..start]);
    output.extend_from_slice(&insertion);
    output.extend_from_slice(&text[end..]);
    NativeHostingReferenceApplyResult {
        caret: u32::try_from(start + insertion.len()).unwrap_or(u32::MAX),
        text: output,
        failure: None,
    }
}

fn is_token_unit(unit: u16) -> bool {
    char::from_u32(u32::from(unit)).is_some_and(|character| {
        character.is_alphanumeric() || character == '_' || character == '-'
    })
}

fn editor_hash(text: &[u16]) -> u64 {
    text.iter().fold(0xcbf2_9ce4_8422_2325, |hash, unit| {
        (hash ^ u64::from(*unit)).wrapping_mul(0x0000_0100_0000_01b3)
    })
}

fn projection_failure(
    failure: NativeHostingReferenceFailure,
) -> NativeHostingReferenceProjectionResult {
    NativeHostingReferenceProjectionResult {
        projection: None,
        failure: Some(failure),
    }
}

const fn no_projection() -> NativeHostingReferenceProjectionResult {
    NativeHostingReferenceProjectionResult {
        projection: None,
        failure: None,
    }
}

fn apply_failure(
    text: Vec<u16>,
    failure: NativeHostingReferenceFailure,
) -> NativeHostingReferenceApplyResult {
    NativeHostingReferenceApplyResult {
        caret: 0,
        text,
        failure: Some(failure),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hosting::NativeHostingRemoteReferenceKind;

    fn reference(insertion: &str, title: &str, number: u64) -> NativeHostingRemoteReference {
        NativeHostingRemoteReference {
            stable_id: format!("issue:{number}"),
            kind: NativeHostingRemoteReferenceKind::Issue,
            number,
            title: title.into(),
            insertion: insertion.into(),
            web_url: format!("https://example.test/issues/{number}"),
        }
    }

    fn utf16(value: &str) -> Vec<u16> {
        value.encode_utf16().collect()
    }

    #[test]
    fn trigger_requires_a_reference_boundary_and_preserves_utf16_ranges() {
        let references = vec![reference("#12", "Änderung 🧪", 12)];
        for text in [r"escaped \#", "inside#", "dash-#"] {
            assert!(project(
                utf16(text),
                text.encode_utf16().count() as u32,
                text.encode_utf16().count() as u32,
                1,
                references.clone(),
                false,
            )
            .projection
            .is_none());
        }
        let text = utf16("🧪 e\u{301} #änd");
        let projection = project(
            text.clone(),
            text.len() as u32,
            text.len() as u32,
            7,
            references,
            true,
        )
        .projection
        .unwrap();
        assert_eq!(projection.query, "änd");
        assert_eq!(projection.replace_start, 6);
        assert_eq!(projection.replace_end, 10);
        assert!(projection.candidates[0].stale);
    }

    #[test]
    fn apply_is_revision_hash_and_range_bound() {
        let text = utf16("Prefix 🧪 #12 suffix");
        let projection = project(
            text.clone(),
            13,
            13,
            9,
            vec![reference("group/project#12", "Issue", 12)],
            false,
        )
        .projection
        .unwrap();
        let applied = apply(
            text.clone(),
            9,
            projection.revision,
            projection.text_hash,
            projection.replace_start,
            projection.replace_end,
            projection.candidates[0].insertion.clone(),
        );
        assert_eq!(
            String::from_utf16(&applied.text).unwrap(),
            "Prefix 🧪 group/project#12 suffix"
        );
        assert_eq!(applied.caret, 26);
        assert_eq!(
            apply(
                text.clone(),
                10,
                projection.revision,
                projection.text_hash,
                projection.replace_start,
                projection.replace_end,
                "#12".into(),
            )
            .failure,
            Some(NativeHostingReferenceFailure::StaleRevision)
        );
        let mut changed = text;
        changed[0] = u16::from(b'p');
        assert_eq!(
            apply(
                changed,
                9,
                projection.revision,
                projection.text_hash,
                projection.replace_start,
                projection.replace_end,
                "#12".into(),
            )
            .failure,
            Some(NativeHostingReferenceFailure::ChangedText)
        );
    }

    #[test]
    fn selected_reference_is_replaced_for_forward_and_reverse_selections() {
        let text = utf16("Änderung #alt bleibt");
        for (base, extent) in [(9, 13), (13, 9)] {
            let projection = project(
                text.clone(),
                base,
                extent,
                3,
                vec![reference("#12", "alt", 12)],
                false,
            )
            .projection
            .unwrap();
            assert_eq!(projection.query, "alt");
            let applied = apply(
                text.clone(),
                3,
                projection.revision,
                projection.text_hash,
                projection.replace_start,
                projection.replace_end,
                projection.candidates[0].insertion.clone(),
            );
            assert_eq!(
                String::from_utf16(&applied.text).unwrap(),
                "Änderung #12 bleibt"
            );
            assert_eq!(applied.caret, 12);
        }
    }

    #[test]
    fn provider_native_insertions_are_preserved_without_reconstruction() {
        let syntaxes = [
            ("gitlab-cross", "group/project#12"),
            ("gitlab-same", "#12"),
            ("github", "#12"),
            ("forgejo", "#12"),
            ("codeberg", "#12"),
        ];
        for (provider, insertion) in syntaxes {
            let text = utf16("See #");
            let projection = project(
                text.clone(),
                text.len() as u32,
                text.len() as u32,
                4,
                vec![NativeHostingRemoteReference {
                    stable_id: format!("{provider}:12"),
                    kind: NativeHostingRemoteReferenceKind::Issue,
                    number: 12,
                    title: provider.into(),
                    insertion: insertion.into(),
                    web_url: format!("https://example.test/{provider}/12"),
                }],
                false,
            )
            .projection
            .unwrap();
            assert_eq!(projection.candidates[0].insertion, insertion);
            let applied = apply(
                text,
                4,
                projection.revision,
                projection.text_hash,
                projection.replace_start,
                projection.replace_end,
                projection.candidates[0].insertion.clone(),
            );
            assert_eq!(
                String::from_utf16(&applied.text).unwrap(),
                format!("See {insertion}")
            );
        }
    }
}
