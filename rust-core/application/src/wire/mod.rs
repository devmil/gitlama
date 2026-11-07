//! JSON codecs for the remote workspace protocol. The helper executes the core's session API
//! in its own process and these codecs carry the same typed values the bridge carries locally.
pub mod contract;
pub mod generated;
pub mod runtime;

#[cfg(test)]
mod tests {
    use crate::diff_syntax::{
        row_json, NativeDiffSyntaxRow, NativeSyntaxSideState, NativeSyntaxSpan,
        NativeSyntaxTokenKind,
    };

    /// The syntax worker measures replies with its own encoding; it must equal the codec's.
    #[test]
    fn syntax_reply_measurement_matches_the_generated_codec() {
        use NativeSyntaxSideState as S;
        use NativeSyntaxTokenKind as K;
        let states = [
            S::Ready,
            S::Unsupported,
            S::InvalidEncoding,
            S::TooLarge,
            S::SourceChanged,
            S::LimitReached,
            S::Deferred,
            S::Unavailable,
        ];
        let kinds = [
            K::Plain,
            K::Comment,
            K::Keyword,
            K::String,
            K::Number,
            K::Type,
            K::Function,
            K::Variable,
            K::Constant,
            K::Operator,
            K::Punctuation,
            K::Attribute,
            K::Tag,
        ];
        for (index, state) in states.into_iter().enumerate() {
            let row = NativeDiffSyntaxRow {
                stable_id: format!("l:\"{index}é"),
                old_state: state,
                new_state: states[(index + 3) % states.len()],
                old_spans: kinds
                    .iter()
                    .enumerate()
                    .map(|(at, kind)| NativeSyntaxSpan {
                        start: at as u32,
                        end: at as u32 + 1,
                        kind: *kind,
                    })
                    .collect(),
                new_spans: Vec::new(),
            };
            assert_eq!(
                row_json(&row),
                super::generated::enc_native_diff_syntax_row(&row)
            );
        }
    }
}
