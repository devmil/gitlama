# Meridian foundations

Meridian is GitLama's design language: a dense, keyboard-first Git workspace that should feel calm. Every screen answers three questions without a click: **where am I** (repo, branch, sync state), **what is selected** and **what is running**.

## Principles

1. **Islands on a ground.** The window is a tinted `ground`. The work sits on it as rounded islands (`pane`, `radius-lg`, `shadow-pane`), separated by a `space-3` gutter. Don't draw hairlines between regions. The gap between islands is the divider. The sidebar, toolbar and repo tabs have no island. They sit straight on `ground`, so the islands read as the content and everything else as chrome.
2. **One accent, spent on intent.** `polar` (cerulean, the app icon's ground) marks the focused selection, the primary action, focus and progress, and nothing else. Status colours (`added`, `deleted`, `modified`, `conflict`) only describe Git state. Lane colours only describe topology.
3. **Hierarchy through weight, not size.** The UI runs at 13px. Differences come from `body` → `body-strong`, `ink` → `ink-muted`, and sans → mono. Keep mono for things a person could paste into a terminal: hashes, paths in diffs, commands. Authors and dates are never mono.
4. **Focus is a place.** Only one island owns keyboard focus at a time. The focused island's selection is solid `polar` with `on-polar` text. In other islands the selection drops to `polar-soft`. Glance at the window and you know where your arrow keys go.
5. **Operations are visible, never modal.** Anything Git runs shows up in the Compass (progress) and the Logbook (history). Only destructive or conflicting steps ask a question.

## Anatomy of the window

```
┌ ground ───────────────────────────────────────────────────────────────┐
│ ● ● ●  [Fetch][Pull][Push][Stash]   ⟨ Compass: repo · branch ↑2 ↓6 ⟩   [⌘K] │ size-toolbar 52
│ ▭ GitLama  ▭ CrossProton  ▭ QSpline  +                               │ size-tabbar 34
│ Sidebar (on ground)   ┌ History island ───────────────────────────────┐ │
│  BRANCHES             │ graph · subject · refs · who · hash · date    │ │
│   ✓ main  ↑0 ↓6       │ ▓ selected row (polar)                        │ │
│  REMOTES …            └───────────────────────────────────────────────┘ │
│                       ┌ Detail island ────────────────────────────────┐ │
│                       │ subject · metadata  │  files  │  diff         │ │
│                       └───────────────────────────────────────────────┘ │
│ status bar (caption, ink-muted)                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

- **Toolbar.** Unified with the title bar. Git verbs sit on the left as `ToolbarButton`s (icon over a `caption` label). The Compass sits in the centre. View toggles and settings go on the right as icon-only buttons.
- **Repo tabs.** Quiet pills on `ground`. The active tab is a `pane`-coloured pill with `shadow-control`, so it looks like the top of the island below. A dot shows uncommitted changes. Hovering over it (never a toast) shows ahead/behind.
- **Sidebar.** `overline` section headers. Rows are `size-row` with `radius-sm` inset hover on `ground-hover`. The checked-out branch is `body-strong` with a check mark. Every tracked branch carries a sync badge (↑ahead ↓behind) on the right.
- **History island.** Graph, subject with ref chips, author, hash, relative date. The Detail island always sits below it, so history rows keep their full width and the diff gets the window's width; a horizontal splitter sets the split.
- **Detail island.** `subject` headline, a metadata line (`Avatar`, author, date, hash chip, parents), then a file list next to the diff.

## Signature patterns

These are what give GitLama its own character. Keep them.

- **Compass.** A pill in the title bar with the repo name, the branch in `polar-ink` and a sync readout (↑2 ↓6). While an operation runs, a 2px `polar` progress rule runs along its bottom edge and the text says the verb ("Fetching origin…"). Click it for the repository's details: where it lives, its path, branch, upstream, changes and running work. The Commands button beside it, or ⌘P / Ctrl P, opens the palette to run any command. The Logbook hangs off its right edge.
- **Spline graph.** Lanes are 2px strokes, `size-lane` apart. A lane changes column along a curve, never a diagonal (the "spline"). Commit nodes are 8px rings in the lane colour, cut out of `pane`. HEAD is a filled node with a 2px `pane` gap and an outer ring. Merges are a ring with a centre dot. Stash entries are dashed rings. Hovering a node for 400ms follows that commit's first-parent line and fades every other lane to `ink-faint`.
- **Tracking pairs.** When a local branch and its upstream point at the same commit, they share one chip: `● main ⟷ origin`. When they diverge, each gets its own chip and the local one shows ↑/↓. Tags are notched chips in `tag-bg`. HEAD never gets its own chip: the checked-out branch's chip is solid `ink` with `pane` text.
- **Status glyphs.** File state is a 16px tile with a letter (M A D R C U ! ?) on a tint of its status colour. Letter and colour always come together, so no state relies on colour alone.
- **Logbook.** The operation history is a timeline: one row per command with its verb, target, duration and a result glyph. Expand a row to see the exact `git …` line in `hash` and its output in `code`. Warnings tint `modified-bg`, failures tint `danger-bg`. Background fetches collapse into one "Fetched origin ×12 · up to date" line.
- **Composer.** The commit message field docks at the bottom of the Changes island on `pane-alt`. Its subject line has a live 50/72 guide: the counter turns `modified` past 50 and `danger` past 72. ⌘↵ commits, ⌘⇧↵ commits and pushes.
- **Hover actions.** Row-level actions (stage, discard, copy hash) appear as `size-control-sm` icon buttons at the row's right edge on hover or focus. They are always reachable from the context menu and keyboard too.

## Content

- Sentence case everywhere: "Push to origin", not "Push To Origin". Capitals only in `overline` section headers.
- Buttons are Git verbs, and the verb is the command: Fetch, Pull, Push, Stash, Commit, Stage hunk, Discard lines. Don't soften them into "Sync" or "Save".
- Say the real names: "Rebase windows-soak-cleanup onto origin/main", never "Rebase current branch".
- Errors say what happened, then what to do: "Push rejected: origin/main has 6 commits you don't have. Pull first, or force-push with lease."
- Show hashes at 10 characters in lists and 12 in detail. Always copyable.
- Dates are relative in lists ("7 min", "2 h", "3 d") and absolute in detail and tooltips ("Thu 24 Sep 2026, 23:00").
- Every string ships in English and German. Leave room for German lengths: labels may be 40% longer, so never fix a button's width.
- No emoji, no exclamation marks, no "Oops".

## Visual foundations

**Colour.** Build light and dark from the same token names. Put `ink` on `pane`, `pane-alt`, `ground`, `raised` and `polar-soft`, and `ink-muted` on the same grounds. Both clear 5:1 in both themes. Put `on-polar` and `on-polar-muted` only on `polar`. Diff lines use `added-bg` / `deleted-bg` with `ink` text. The changed words inside get `added-strong` / `deleted-strong` at `radius-xs`. `fjord` (the mark's square) is brand-only: welcome hero, About box, cover. Give graph lanes to branches in order `lane-1`…`lane-8`. `lane-1` always belongs to HEAD's first-parent line, so your own work is always blue.

**Type.** The UI uses the platform face (`sans`: SF Pro on macOS, Segoe UI Variable on Windows, Cantarell or Noto Sans on Linux), so GitLama sits natively next to the OS. Code, hashes and commands use JetBrains Mono (`mono`, bundled). Use `body` for rows, `label` for controls, `caption` for toolbar labels and metadata, `overline` for section headers, `subject` for the Detail headline, `title` for dialogs, and `display` only on the welcome screen. Never go below 11px.

**Spacing & density.** It's a 2px grid, with `space-4` (8px) as the working unit. Islands are `space-3` apart and `space-3` from the window edge. Row height follows density: `size-row-compact` 24, `size-row` 28 (default), `size-row-comfortable` 32. Density changes row height and nothing else: type and icon sizes stay the same.

**Shape.** Rows `radius-sm`, controls `radius-md`, islands `radius-lg`, floating surfaces `radius-xl`, and the Compass, counts and switches `radius-pill`. The selected row is an inset rounded bar, `space-2` in from the island edge. It never runs full width.

**Depth.** Two levels only. `shadow-pane` for islands and `shadow-float` for anything that floats (popover, menu, Logbook, palette, dialog). Controls get at most a 1px lip (`shadow-control`). No inner shadows, no gradients.

**Motion.** Quick and physical. Hover and press: 80ms. Selection bar move: 120ms ease-out. Popover and palette enter: 140ms, fading in while rising 4px. Island resize: follows the pointer with no easing. The Compass progress rule is indeterminate until Git reports progress, then determinate. Honour Reduce Motion by replacing movement with a fade.

**States** (every control): rest, hover (`pane-hover` or `ground-hover`), pressed (hover plus 4% `ink`), focus (2px `focus` ring, 1px offset, `radius-md`), disabled (`ink-faint` label, no hover), loading (label kept, spinner replaces the icon), error (`danger` edge plus message below). Keyboard focus is always visible. Mouse focus shows the ring only on text fields.

**Accessibility.** Every text pair in this system clears 4.5:1 in both themes. Control edges, the focus ring, icons and lanes clear 3:1. Status is never colour-only: glyph letters, ↑/↓ arrows and icons go with every colour. Every drag (stage by dragging, reorder in interactive rebase) has a keyboard route and a menu item. Test at 130% text scale.

## Iconography

Use the Lucide icons in [`assets/icons/`](assets/icons/) (lucide-static 1.37.0, ISC). They are byte-identical to the app's `assets/icons/lucide/`, and [`assets/icons/inventory.json`](assets/icons/inventory.json) records the source name and purpose of each. They're 24×24 viewBox, 2px stroke, round caps and joins, drawn at `size-icon` (16px) and 14px in chips. They are single-ink `currentColor` SVGs: colour them `ink` at rest, `ink-muted` when idle in toolbars, and `on-polar` on selection. Icons only go with verbs and objects Git already has a word for. Don't use decorative icons in headers. The app mark is [`assets/brand/gitlama-mark.svg`](assets/brand/gitlama-mark.svg). It's the blue Git path turning into a north-pointing N on the fjord square, used in the About box, the welcome screen and platform icons only, never inside the working UI.
