# ADR 0003: Fixed-extent bounded diff projection

- Status: accepted
- Date: 2026-09-19

## Context

GitLama must display unified and side-by-side diffs without transferring an entire large patch to Flutter, building one widget per source line, or reconstructing patches from rendered text. Line selection must retain the byte-safe identities produced by the shared Git parser. Wrapped source would make row heights content-dependent and substantially complicate synchronized split scrolling and bounded viewport projection.

## Decision

Committed diffs enter through `Repository::commit_diff`; working-tree reads and staging will use the shared `Repository::working_diff`, `DiffFile`, `DiffLineId`, `LineSelection` and `BytePatchBuilder` contracts. GitLama retains the accepted native diff and publishes pages of at most 512 display rows. A row carries a stable opaque identity and at most 16 KiB of display text. Binary/image and shared-parser too-large states remain typed fallbacks rather than synthetic text hunks.

Flutter renders a fixed 20-pixel `ListView.builder`. Unified and split layouts share one semantic row and vertical scroll position, so old/new panes cannot drift. Syntax work is injected only for live rows. Selection uses stable row identities and the newest request token; an older canceled request can never replace the current file.

Wrapping is off by default. Long lines stay a single clipped semantic row; the production Changes pane may add a shared horizontal viewport. The 16 KiB row ceiling is a display safeguard, not a patch boundary: patch construction always uses the retained native bytes. The shared 8 MiB patch ceiling and parser line limits produce the oversized fallback before Flutter transport.

Partial staging re-runs the accepted diff preflight, compares native `DiffFile` identity/content, constructs a patch from `DiffLineId` values, then crosses the irreversible boundary with `git apply --cached --recount --unidiff-zero`. Tests use isolated `GIT_INDEX_FILE` copies to prove exact index bytes without mutating the fixture's real index.

## Consequences

- Visible widget, syntax and bridge payload work are bounded by the viewport/page rather than total diff size.
- Split scrolling and selection remain synchronized by construction.
- Display truncation cannot corrupt staging because displayed strings are never patch input.
- Variable-height wrapping is deferred; adding it requires a measured virtual-extent index and a replacement ADR.
- P05 must turn the proven preflight/mutation sequence into the repository-session mutation workflow and preserve its stale-generation and index-lock checks.

## Rejected alternatives

- Sending the complete patch through one bridge call: unbounded copies and decoding.
- One widget per source line: unbounded element/render-object count.
- Rebuilding patches from selected display rows: loses CRLF, no-final-newline, binary and byte-path correctness.
- Independent split-pane lists: permits scroll and selection drift.
