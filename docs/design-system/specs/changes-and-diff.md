# Changes, diff and commit specification

Status: normative. Meridian 3.0.
Oracles: [`diff-fixtures.json`](diff-fixtures.json) (`gitlama.diff-fixture.v1`) and [`patch-scopes.json`](patch-scopes.json). Components: `FileRow`, `StatusGlyph`, `DiffHunk`, `Composer`, `Banner`, `Dialog`.

## 1. Scope

This covers the Changes island (unstaged and staged file lists), the diff renderers (unified, split, image and fallbacks), line and hunk operations, and the Composer. The history graph is in [`graph.md`](graph.md).

## 2. Geometry

| Value | Meridian |
|---|---|
| Diff line height | 18 px (`code` style), fixed and not density-scaled |
| Line-number gutters | Two columns of 44 px each (old, new), `hash` style, `ink-muted`, right-aligned |
| Sign column | 18 px. `+` and `−` (U+2212) always render, in `added` / `deleted`, bold |
| Code area minimum | 280 px unified, 220 px per side in split |
| Hunk header strip | 30 px, `pane-alt`, `line` hairlines above and below, sticky at the top of the diff |
| Code face | JetBrains Mono 12 px |

Layout: Changes is one island holding the Unstaged and Staged lists (180 px minimum each) and the diff (320 px minimum). At or above 1100 px the lists sit left of the diff. Below that they stack above it. Sizes persist application-wide. List or tree mode persists per list, so Unstaged and Staged can differ.

## 3. Line intensities

| Intensity | Tokens | Applied to |
|---|---|---|
| Row | `added-bg` / `deleted-bg` | Whole-line fill of added / removed lines |
| Selected | `polar` at 10 % over the row fill, a 1 px `polar` frame around each run of selected lines, and the line numbers on `polar-soft`; selected text adds `polar` at 28 % behind the characters | Lines touched by the text selection, which staging, unstaging or discard act on |
| Intra-line | `added-strong` / `deleted-strong`, `radius-xs` | Changed words inside a changed line (`intraLineRule` in the fixtures) |

Base text is `ink` on every intensity. Validated syntax categories may change only the foreground of code text (Meridian's `syntax-*` tokens, section 6); added, removed, changed-word, search and selection meanings stay backgrounds, rails, frames and signs. Colour never works alone: the sign column carries + / −, and selection carries the frame.

## 4. Hunks

- The header strip shows the range in `hash` style (`@@ -169,3 +169,12 @@`), the enclosing context line, and on the right the hunk actions. For unstaged content these are `Discard` (danger-quiet) and `Stage hunk`. For staged content it is `Unstage hunk`. Actions on selected lines float on the selection (section 5).
- Expand context with `chevrons-down-up` at each hunk edge. It steps 3 lines, up to the file bounds. Expansion is view-local and resets when the model changes.
- Whitespace mode (`whitespace` Segmented in the diff header): Show, Marks (pilcrow and dot glyphs in `ink-faint`), Ignore (whitespace-only changes collapse to a muted "Whitespace only" row).

## 5. Selection and operations

- Diff text is selected like editor text: click places the caret, drag selects characters, double-click a word, triple-click or a gutter click a whole line, and dragging down the gutter whole lines. ⇧-click and ⇧←→↑↓ extend, ⌘/Ctrl-A selects all (up to 4096 lines), Esc clears. Clicking a hunk header selects the whole hunk.
- Every line the text selection touches is selected implicitly and gets the selected intensity. A selection that ends at the start of a line, or starts at its end, leaves that line out.
- On unstaged content, `Stage` and `Discard Changes…` (secondary, small) float at the top end of the frame; staged content shows `Unstage`. They act on the changed lines among the selected lines and are absent when those lines hold no change. The context menu lists the same actions above `Copy` and `Copy as Patch`.
- `Copy` (⌘/Ctrl-C) copies the selected text; `Copy as Patch` builds a patch of the selected changed lines.
- Keys on a selection: `S` stages, `U` unstages, `D` discards (confirmed).
- Partial staging writes a patch through Rust. Staged lines re-render in the staged list with the same intensities.
- Untracked files show a virtual add-only diff with the same controls (fixture `untracked`).
- **Discard is irreversible.** It always opens a `Dialog` with a `danger` primary action that names the scope: "Discard 3 lines in ci.yml", "Discard 4 files". The dialog says it cannot be undone. Discard never runs on a single click.

## 6. Line rendering

- Wrap (`wrap` toggle): continuation lines indent to 106 px (two gutters plus the sign column). One semantic row keeps one line number, and intra-line spans may wrap (fixture `wrap-mode`).
- Wrapped rows add their full visual height to the virtualized diff.
- Wrap, layout, whitespace, context lines, sign markers and the minimap are one stored choice shared by every diff view (Changes, the inspector and the conflict comparison). The diff toolbar and the Diffs settings page change it; "Show more context" widens only the diff on screen.
- No newline at end of file: a muted "No newline at end of file" row on `pane-alt` (fixture `nonewline`).
- Syntax colours are an overlay that arrives after the plain text. The core parses each side's exact source (old and new separately, from the start of the file) where the repository is, on this computer or its host, and returns categories for the rows on screen once the person pauses; scrolling, dragging and typing hold them back. A deletion shows the old side's colours, an addition the new side's, a context line the new side's (or the old side's when only it matches); split cells each show their own side.
- Colours change the foreground only: same font, size, weight and metrics, never animated, never moving the scroll position, selection or focus. A category that would read below 4.5:1 on the row's fill, its changed-word mark or the selection keeps `ink`. Changed-word marks are computed independently of colours.
- If no grammar matches, the source cannot be proven to be the version shown, the text is Latin-1, invalid UTF-8, truncated or over a bound, or the core is busy, the diff stays silently `ink` on the fills (fixture `syntax-unavailable`). There is no spinner, message or retry loop for colours.
- At most 6 intra-line spans per line. Beyond that the whole line takes the intra-line fill.

## 7. Find in diff

⌘F / Ctrl F opens a `TextField` (search variant) in the diff header with a trailing count "2/2", previous/next `IconButton`s and a case toggle. The current match is `polar-soft` with a 1 px `polar` outline; other matches are `pane-hover`. ↵ moves to the next match and wraps (fixture `find-in-diff`). Esc closes the field and clears highlights.

## 8. File rows

File rows follow the `FileRow` component. Status is a `StatusGlyph` letter tile, never hue alone:

| State | Glyph | Colour |
|---|---|---|
| Modified | M | `modified` on `modified-bg` |
| Added | A | `added` on `added-bg` |
| Deleted | D | `deleted` on `deleted-bg` |
| Renamed | R (the row shows `from → to` and similarity %) | `renamed` on `polar-soft` |
| Copied | C | `renamed` on `polar-soft` |
| Conflicted | U | `conflict` on `conflict-bg` |
| Untracked | ? | `ink-muted`, outlined |
| Ignored | ! | `ink-faint`; row at 60% opacity |
| Submodule | `box` icon plus old → new short hashes | `ink-muted` |
| LFS | `Count` "LFS" | neutral |
| Binary | `Count` "BIN" | neutral |
| Partially staged | a split glyph (upper half tint, lower half `pane-alt`) plus "partial" in `caption` | — |
| Unavailable | `ban` icon; actions disabled with a reason | `ink-faint` |

- Row anatomy: glyph, directory in `ink-muted`, file name in `ink`, then +N / −N counts in `hash` style. On hover or focus the counts are replaced by hover actions: Stage or Unstage (`stage-all` / `unstage-all`), and Discard (`undo`, unstaged only). Actions are `IconButton size="sm"` with tooltips and accessible names.
- Space stages or unstages the current file. ⇧ range and ⌘/Ctrl toggle multi-select. Every hover action is also in the context menu (Stage, Discard, Open externally, Copy path, Reveal in Finder / Explorer, Create patch…).
- Folder rows in tree mode keep the disclosure chevron separate from the folder's stage action.
- Dragging between lists shows a named badge ("Stage 3 files → Index"). Dragging is never the only route.
- A search `TextField` ("Filter files") above the Unstaged list narrows both lists to the paths that contain every word typed, ignoring case; the path a file was renamed from counts. While it filters, its trailing text says how many files it shows ("3 of 12"), the section counts show the shown files, a list with no match says "No matching files", and Esc or the clear button empties it. The selection keeps only shown files, and Stage all, Unstage all and Discard all become Stage shown, Unstage shown and Discard shown, acting on the shown files only. The Composer still commits everything staged.
- The History inspector's file list (Changed / All files, its rows and menus) is defined by the [inspector spec](inspector.md) §4.5, §7 and §8.

## 9. Fallback panels

These are centred in the diff area, each with an icon, one `body` sentence and at most two Buttons:

- `binary`: size, "Open externally", and an image diff when both sides are images.
- `image`: side by side by default, with old and new labelled. Swipe and onion-skin are Settings choices, not chrome.
- `submodule`: commit bump lines.
- `mode-only`: "100644 → 100755, no content changes".
- `too-large`: when either file side exceeds 8 MiB, show the size and filename extension before generating a patch. This applies to working, staged, history and comparison diffs. Do not read the file body to display this panel. Whole-file staging remains available; line and hunk actions require an inline diff. Metadata fallback rows have a 180 px extent and scroll their contents at narrow widths or larger text sizes. Existing output/line limits still bound smaller inline diffs.
- `decode-error`: "Not valid UTF-8. Choose an encoding in Settings → Diff."
- A renderer slot, used when an extension claims the file type.

## 10. Composer (commit editor)

The Composer docks at the bottom of the Changes island on `pane-alt`. It is never a modal.

- Subject: single line, `body-strong`, with a live counter. The counter is `ink-muted` up to 50, `modified` past 50, and `danger` bold past 72.
- Description: multi-line. It shows 2 lines, grows to 5, then scrolls. Dragging the splitter above the Composer gives the Composer a height; the description then takes all of it that the subject and footer leave (never less than 2 lines; below that the Composer scrolls). A double click on the splitter returns the Composer to its own height.
- Footer: `Checkbox` Amend, the staged count, a secondary `Button` "Commit & push" (⌘⇧↵), and a primary `Button` "Commit to <branch>" (⌘↵). An overflow `IconButton` holds Template (`template`), Recent messages (`history`), Co-authors (`co-author`), Spellcheck (`spellcheck`), Fixup / Squash (`fixup`, `squash`), Sign (`signature` / `badge-check`) and Skip hooks.
- Validation: an empty subject disables Commit with the reason in the tooltip. Trailing whitespace in the subject shows an inline `caption` warning.
- Hook failure: an inline `Banner` (tone `error`) above the Composer with the exit code and the first 40 lines of output, plus the actions Retry and Skip hooks. Skip hooks needs a typed confirmation. A signing failure works the same way, with Retry and Commit unsigned.
- Success: the Composer clears, the new row is selected in History, and the Logbook records "Committed 857ece8". There is no toast. Amend pre-fills the HEAD message and the primary button becomes "Amend 857ece8".
- Tab order: subject → description → footer actions.

## 11. Acceptance

1. `diff-fixtures.json` renders in both themes: all three intensities, rule-derived intra-line spans, the 106 px wrap indent, find states and all file kinds.
2. Partial staging round-trips through Rust and re-renders with the selected intensity in the staged list.
3. Composer states (validation, hook failure, signing failure, amend, success) match this spec in both themes and at 130% text scale.
4. Patch creation infers its scope only from `patch-scopes.json` precedence.
