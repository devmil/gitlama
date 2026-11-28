//! Syntax categories for texts the window holds, such as a conflicted file's sides and its
//! unsaved merge result. Each view colours one text at a time: a new text for a view cancels
//! the pages still coming for its previous one. Pages of `TEXT_SYNTAX_PAGE_LINES` lines are
//! parsed on the blocking pool, first to last, and published one by one; any state but Ready
//! leaves the rest of the text plain. A page that comes back deferred (the parser is busy) is
//! asked once more after `DEFERRED_RETRY`.

use crate::rt;
use gitlama_contract::diff::{
    NativeSyntaxSideState, NativeSyntaxTokenKind, NativeTextSyntaxLine, NativeTextSyntaxRequest,
};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;
use std::time::Duration;

/// Lines per request; the contract's page limit.
pub const PAGE_LINES: u32 = 128;
const DEFERRED_RETRY: Duration = Duration::from_millis(300);

/// One line's categories as `[start, end, kind]` triples over UTF-16 offsets of the line.
pub type LineSpans = Vec<(u32, u32, &'static str)>;

/// The name QML and the palettes use for a category.
#[must_use]
pub fn token_name(kind: NativeSyntaxTokenKind) -> &'static str {
    match kind {
        NativeSyntaxTokenKind::Plain => "plain",
        NativeSyntaxTokenKind::Comment => "comment",
        NativeSyntaxTokenKind::Keyword => "keyword",
        NativeSyntaxTokenKind::String => "string",
        NativeSyntaxTokenKind::Number => "number",
        NativeSyntaxTokenKind::Type => "type",
        NativeSyntaxTokenKind::Function => "function",
        NativeSyntaxTokenKind::Variable => "variable",
        NativeSyntaxTokenKind::Constant => "constant",
        NativeSyntaxTokenKind::Operator => "operator",
        NativeSyntaxTokenKind::Punctuation => "punctuation",
        NativeSyntaxTokenKind::Attribute => "attribute",
        NativeSyntaxTokenKind::Tag => "tag",
    }
}

/// A page's lines without plain spans; lines that are not Ready have none.
#[must_use]
pub fn line_spans(lines: &[NativeTextSyntaxLine]) -> Vec<LineSpans> {
    lines
        .iter()
        .map(|line| {
            if line.state != NativeSyntaxSideState::Ready {
                return Vec::new();
            }
            line.spans
                .iter()
                .filter(|span| span.kind != NativeSyntaxTokenKind::Plain && span.end > span.start)
                .map(|span| (span.start, span.end, token_name(span.kind)))
                .collect()
        })
        .collect()
}

/// The source of a page: the backend's call on the blocking pool, replaceable in tests.
pub type PageSource = Rc<
    dyn Fn(
        NativeTextSyntaxRequest,
    ) -> Pin<Box<dyn Future<Output = gitlama_contract::diff::NativeTextSyntaxResult>>>,
>;

#[derive(Default)]
pub struct TextSyntax {
    next_request: Cell<u64>,
    /// The generation each view colours now.
    generations: RefCell<HashMap<u64, u64>>,
}

impl TextSyntax {
    #[must_use]
    pub fn new() -> Rc<Self> {
        Rc::new(Self::default())
    }

    fn request_id(&self) -> u64 {
        let next = self.next_request.get().wrapping_add(1).max(1);
        self.next_request.set(next);
        next
    }

    fn current(&self, view: u64, generation: u64) -> bool {
        self.generations.borrow().get(&view) == Some(&generation)
    }

    /// Colours `text` for `view` (nonzero) with the grammar `path` selects, calling
    /// `publish(first_line, lines)` for each page while `generation` is the view's latest.
    pub fn colour(
        self: &Rc<Self>,
        view: u64,
        generation: u64,
        path: Vec<u8>,
        text: String,
        publish: impl FnMut(u32, Vec<LineSpans>) + 'static,
    ) {
        self.colour_with(
            view,
            generation,
            path,
            text,
            Rc::new(|request| {
                Box::pin(rt::blocking(move || {
                    gitlama_core::api::text_syntax_page(request)
                }))
            }),
            publish,
        );
    }

    /// [`Self::colour`] with the page source given.
    pub fn colour_with(
        self: &Rc<Self>,
        view: u64,
        generation: u64,
        path: Vec<u8>,
        text: String,
        source: PageSource,
        mut publish: impl FnMut(u32, Vec<LineSpans>) + 'static,
    ) {
        if view == 0 {
            return;
        }
        self.generations.borrow_mut().insert(view, generation);
        let this = Rc::clone(self);
        let source_bytes = Rc::new(text.into_bytes());
        let path = Rc::new(path);
        rt::spawn_detached(async move {
            let lines = source_bytes.iter().filter(|byte| **byte == b'\n').count() as u32 + 1;
            let mut first = 1u32;
            let mut retried = false;
            while first <= lines && this.current(view, generation) {
                let request = NativeTextSyntaxRequest {
                    view_id: view,
                    syntax_request_id: this.request_id(),
                    path: (*path).clone(),
                    source: (*source_bytes).clone(),
                    first_line: first,
                    maximum_lines: PAGE_LINES,
                };
                let result = source(request).await;
                if !this.current(view, generation) {
                    return;
                }
                let Some(page) = result.page else {
                    return;
                };
                match page.state {
                    NativeSyntaxSideState::Ready => {}
                    NativeSyntaxSideState::Deferred if !retried => {
                        retried = true;
                        rt::sleep(DEFERRED_RETRY).await;
                        continue;
                    }
                    _ => return,
                }
                retried = false;
                let count = page.lines.len() as u32;
                publish(page.first_line, line_spans(&page.lines));
                if count < PAGE_LINES {
                    return;
                }
                first += count;
                // Lets input and painting run between pages.
                rt::sleep(Duration::ZERO).await;
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_contract::diff::{NativeSyntaxSpan, NativeTextSyntaxPage, NativeTextSyntaxResult};

    fn line(spans: &[(u32, u32, NativeSyntaxTokenKind)]) -> NativeTextSyntaxLine {
        NativeTextSyntaxLine {
            state: NativeSyntaxSideState::Ready,
            spans: spans
                .iter()
                .map(|&(start, end, kind)| NativeSyntaxSpan { start, end, kind })
                .collect(),
        }
    }

    #[test]
    fn spans_drop_plain_and_empty_runs() {
        let lines = [
            line(&[
                (0, 2, NativeSyntaxTokenKind::Keyword),
                (2, 3, NativeSyntaxTokenKind::Plain),
                (3, 3, NativeSyntaxTokenKind::Number),
            ]),
            NativeTextSyntaxLine {
                state: NativeSyntaxSideState::Deferred,
                spans: vec![NativeSyntaxSpan {
                    start: 0,
                    end: 1,
                    kind: NativeSyntaxTokenKind::Comment,
                }],
            },
        ];
        assert_eq!(
            line_spans(&lines),
            vec![vec![(0, 2, "keyword")], Vec::new()]
        );
    }

    fn pages(total: u32, state: NativeSyntaxSideState) -> PageSource {
        Rc::new(move |request: NativeTextSyntaxRequest| {
            let count = PAGE_LINES.min(total + 1 - request.first_line);
            let page = NativeTextSyntaxPage {
                view_id: request.view_id,
                syntax_request_id: request.syntax_request_id,
                first_line: request.first_line,
                state,
                lines: (0..count)
                    .map(|_| line(&[(0, 1, NativeSyntaxTokenKind::Keyword)]))
                    .collect(),
            };
            Box::pin(async move {
                NativeTextSyntaxResult {
                    page: Some(page),
                    failure: None,
                }
            })
        })
    }

    #[test]
    fn colours_every_page_in_order() {
        let runtime = rt::Runtime::install();
        let syntax = TextSyntax::new();
        let seen = Rc::new(RefCell::new(Vec::new()));
        let record = Rc::clone(&seen);
        let text = vec!["x"; 300].join("\n");
        syntax.colour_with(
            1,
            1,
            b"a.rs".to_vec(),
            text,
            pages(300, NativeSyntaxSideState::Ready),
            move |first, lines| record.borrow_mut().push((first, lines.len())),
        );
        runtime.run_until_stalled();
        assert_eq!(*seen.borrow(), vec![(1, 128), (129, 128), (257, 44)]);
    }

    #[test]
    fn a_newer_text_stops_the_older_one_and_unsupported_stays_plain() {
        let runtime = rt::Runtime::install();
        let syntax = TextSyntax::new();
        let seen = Rc::new(RefCell::new(Vec::new()));
        let old = Rc::clone(&seen);
        syntax.colour_with(
            2,
            1,
            Vec::new(),
            "a\nb".to_owned(),
            pages(2, NativeSyntaxSideState::Ready),
            move |first, _| old.borrow_mut().push(("old", first)),
        );
        let new = Rc::clone(&seen);
        syntax.colour_with(
            2,
            2,
            Vec::new(),
            "a".to_owned(),
            pages(1, NativeSyntaxSideState::Unsupported),
            move |first, _| new.borrow_mut().push(("new", first)),
        );
        runtime.run_until_stalled();
        assert!(seen.borrow().is_empty());
    }
}
