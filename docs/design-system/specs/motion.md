# GitLama motion

This is GitLama's motion contract. It builds on the Meridian motion guide in `meridian_ui` (`design/project/guides/40-motion.md`), which defines the principles, the tokens (`MeridianDurations`, `MeridianCurves`, `MeridianSprings`, `MeridianMotionScales`), the helpers and the shared catalogue (MM-xx). Everything in the shared catalogue comes with the Meridian components. This file lists only what is GitLama's own: the highlight moments (NH-x) and the git-specific micro-animations (NM-xx).

The interactive prototype, Meridian Motion Lab (`specimens/motion-lab.html`), runs NH-1 to NH-7 and most NM rows in a working model of the workspace. Where this file and the prototype differ, this file wins.

Read the Meridian guide first. Every rule there applies here. In particular: nothing blocks input, everything retargets, reduce motion turns movement into an instant change or a crossfade of at most 100 ms, and only transform, opacity, colour, clip and painter progress are animated.

## Character

GitLama's motion is about **history taking shape**. The graph is the hero. Motion shows a commit landing on its lane, a lane lighting up its ancestry, a file travelling from Unstaged to Staged, and the Compass reporting that a sync finished. Everything else stays quiet and quick.

- **Highlights** are rare, earned and short. Each one plays only when the person's own action caused it, at most once per action. None of them delays the next input.
- **Micro-animations** are everywhere and almost invisible: 60–200 ms, a few pixels, springs for anything the pointer touches.

## GitLama motion values

These are added to `GitLamaMotion` in `lib/app/gitlama_layout.dart`. Anything not listed comes from the Meridian tokens.

| Name | Value | Use |
|---|---|---|
| `foregroundLogbookDelay` | 300 ms | Existing. Wait before a foreground operation opens the Logbook |
| `laneFocusDelay` | 400 ms | Existing. Hover time on a node before lane focus starts |
| `commitFlash` | removed | Replaced by `MeridianDurations.attention` (900 ms, exit-soft) |
| `laneDim` | 180 ms | Other lanes dimming to `GitLamaOpacity.unlit` when lane focus starts, and back |
| `laneFlowStep` | 12 ms | Per-row delay of the lit path flowing down the graph (NH-3) |
| `laneFlowMaxRows` | 16 | Rows beyond this light at once |
| `laneDrawStep` | 10 ms | Per-row delay of the lanes drawing in on first load and after a pull (NH-2, NH-7) |
| `laneDrawRow` | 140 ms | Duration of one row's lane stroke drawing in |
| `laneDrawMaxRows` | 24 | Rows beyond this appear without drawing |
| `commitLand` | 320 ms (`MeridianDurations.highlight`) | NH-1: the WIP ring becoming the new commit node |
| `glint` | 520 ms (`MeridianDurations.celebrate`) | NH-2: the glint sweeping across the Compass after a sync |
| `detailDebounce` | 150 ms | The detail island only swaps with motion when selection rests this long (keyboard scrubbing stays instant) |
| `refreshSpinDelay` | 150 ms (`MeridianDurations.spinnerDelay`) | Refresh icon starts spinning only if refreshing takes longer |
| `stageWash` | 240 ms (`MeridianDurations.emphasized`) | NH-4: the `added-strong` wash on a hunk that was just staged |
| `copiedHold` | 1200 ms | How long "Copied" stays after copying a hash |
| `paletteMorph` | 300 ms | Compass to command palette route transition |

## Highlights

Each highlight names its trigger, its choreography (with times from the start of the moment), what it must never do, and its reduce-motion version. All of them are interrupted by the next input: the next input finishes the moment instantly (every element jumps to its end state) and then handles the input.

### NH-1 Commit lands

**Trigger:** a commit made from the Composer succeeds (`RepositorySessionService.lastCommittedObjectId` changes with a new commit sequence). Not for commits that arrive by fetch, pull, rebase or an outside tool.

| t (ms) | What happens |
|---|---|
| 0 | The Composer clears. The subject and description fields crossfade to empty (`motion-quick`); the primary button's success check draws (MM-04) |
| 0 | The Changes list removes the committed rows with `MeridianReveal` (fade `motion-exit`, then collapse `motion-layout`). If the list is now empty, the empty state enters (MM-67) |
| 0 | In the graph, the new commit row opens directly under the WIP row: the rows below slide down one row over `motion-layout` and the new row fades in over `motion-select`. (When nothing is left to commit, the WIP row itself is replaced.) The new node starts as the WIP node's dashed ring in the lane colour. Its dashes close into a solid ring (the dash gap shrinks to 0 over 160 ms, `curve-standard`). The node fill then scales from 0 to 1 with `spring-pop` (from 160 ms). The HEAD halo ring grows from the inner radius to `graphHeadOuterRadius` with `spring-snappy` (from 160 ms). The temporary ring fades out by 320 ms |
| 0 | The head chip (the checked-out branch's `GitLamaRefChip`) travels from its old row to the new commit row with `MeridianTravel` (`spring-gentle`). When the old row is not visible, the chip rises into place (`rise-content`, `motion-select`) |
| 120 | The new commit row's `accent-soft` attention tint starts and fades back over `motion-attention` (the existing commit flash, now `MeridianAttention`) |
| 0–320 | If the history list is scrolled away from the top, it does not scroll. The Compass's ahead count rolls up and pops (NM-03) |

**Never:** scroll the history, move focus out of the Composer, replay when the row scrolls out of view and back (the flash is recorded in `MeridianMotionMemory` by commit id plus sequence), or play for amend (amend plays only the attention tint on the rewritten row).

The Composer is mounted in Changes while the graph is mounted in History. A Composer commit keeps Changes open; this graph sequence plays once when History first opens on the new HEAD. The HEAD chip rises into place when there was no visible old chip to capture.

**Reduce motion:** the new row appears with the attention tint held for 300 ms; the chip is simply on the new row; the Composer clears instantly.

### NH-2 Sync settles

**Trigger:** a fetch, pull or push started by the person finishes successfully.

| t (ms) | What happens |
|---|---|
| 0 | The Compass progress rule fills to 100% (`motion-emphasized`), holds 300 ms and fades (MM-63) |
| 300 | A glint sweeps once across the Compass pill: a 40 px wide soft gradient of `accent-soft` at 60% opacity, clipped to the pill, moving left to right over `glint` with `curve-standard`. Only when the sync changed something (new commits, or ahead or behind changed) |
| 300 | The ahead and behind numbers in the Compass and in the sidebar's sync badges roll to their new values (`MeridianRollingNumber`, rolling down for decreases). A value that becomes 0 fades its arrow to `ink-faint` (`motion-select`) |
| 300 | After a pull or a fetch that shows new commits in the visible part of the graph, those rows enter with `MeridianEntrance` (rise 6 px, fade), staggered 18 ms, at most 6 rows. Their lane strokes draw in top to bottom (`laneDrawStep`, `laneDrawRow`, at most `laneDrawMaxRows` rows) |
| 300 | Remote ref chips that moved travel to their new rows (`MeridianTravel`, one flight per region: when several refs moved, only the checked-out branch's upstream chip travels; the others crossfade into place) |

**Never:** play the glint for background fetches, or when nothing changed. Background fetches only roll the numbers.

**Reduce motion:** numbers change instantly, the progress rule hides, no glint, no stagger or drawing.

### NH-3 Lane focus

**Trigger:** the pointer rests `laneFocusDelay` on a commit node, or keyboard lane focus is toggled (existing behaviour; the Rust core computes `lit` per row).

| t (ms) | What happens |
|---|---|
| 0 | Every unlit lane segment and node fades from full opacity to `GitLamaOpacity.unlit`, and the row text to `GitLamaOpacity.unlitText`, over `laneDim` (`curve-standard`) |
| 0 | The lit path flows down from the hovered node: each lit row below it switches to the lit stroke width (`graphStrokeLit`) `laneFlowStep` × its distance later, up to `laneFlowMaxRows` rows; rows beyond that light together with the last one. Rows above the node light at once |
| on leave | Everything returns over `motion-hover-out`, all rows together (no reverse flow) |

**Never:** delay the hover highlight or selection, or replay while the pointer moves along the same lit path (moving to another node on the same path keeps the current state).

**Reduce motion:** dim and light instantly.

### NH-4 Stage flight

**Trigger:** the person stages or unstages whole files (button, shortcut, double-click, drag and drop).

| t (ms) | What happens |
|---|---|
| 0 | For one file whose destination row is visible: the file row flies from the Unstaged list to its sorted place in the Staged list with `MeridianTravel` (`motion-highlight`, `spring-gentle`). The source row collapses with `MeridianReveal` while the destination row opens its slot (`motion-layout`) |
| 0 | For several files, or a destination that is not visible: no flight. Source rows collapse, destination rows enter with `MeridianEntrance`, staggered (at most 6) |
| 0 | The section header counts roll (NM-30) |
| 320 | The moved row gets `MeridianAttention` in its new list |

**Hunks and lines:** staging a hunk or lines in the diff washes the staged lines with `added-strong` that fades back to the normal `added` fill over `stageWash`. The hunk collapses out of the unstaged diff with `MeridianReveal` when nothing in it is left.

**Never:** fly more than one row, fly when the lists are scrolled so the destination is off screen, or keep the row from being selected, focused or acted on in its new list while it flies.

**Reduce motion:** rows change lists instantly; the attention tint plays for 300 ms.

### NH-5 Conflicts resolved

**Trigger:** the last conflicted file in a merge, rebase, cherry-pick or revert is marked resolved.

| t (ms) | What happens |
|---|---|
| 0 | The conflict banner changes tone from attention to success (MM-66); its icon swaps to `check` drawn by `MeridianStroke` |
| 0 | The Compass conflict count rolls to 0 and then leaves (`MeridianReveal` on its width) |
| 200 | The operation's Continue button (in the banner and in the resolver) plays one soft halo: a ring around the button growing from 0 to 8 px while fading from `accent` at 40% to transparent, over `motion-pulse`, once. It then stays still |
| 0 | In the resolver, the file list row's status mark crossfades from the conflict glyph to the resolved check (`MeridianSwap`, scale 0.8 → 1) |

**Reduce motion:** tone and counts change instantly; no halo.

### NH-6 Palette from the Compass

**Trigger:** the command palette opens from a click on the Compass (keyboard opening uses the normal dialog entrance MM-45).

| t (ms) | What happens |
|---|---|
| 0 | The palette surface grows out of the Compass pill: it starts at the pill's global rect and radius (`pill`) and springs to the palette's rect and `radius-lg` with `spring-snappy` (about 190 ms). The pill's content fades out over `motion-exit` |
| 60 | The query field and the first rows fade in (`motion-quick`); rows stagger 18 ms, at most 6 |
| close | When the palette closes without running a command, it shrinks back into the pill over `motion-dialog` with `curve-exit`. After running a command, it fades (`motion-exit`) |

The query field has focus from frame 0; typing during the morph works.

**Reduce motion:** the normal dialog fade.

### NH-7 Repository opens

**Trigger:** a repository tab shows its first loaded content (cold open or first activation this session). Not on tab switches after that.

| t (ms) | What happens |
|---|---|
| 0 | The islands enter one after the other with `MeridianEntrance`: sidebar (0), history (40), detail (80); fade plus rise `rise-content` |
| 120 | The first visible screen of graph rows draws its lanes in top to bottom (`laneDrawStep`, `laneDrawRow`, at most `laneDrawMaxRows` rows). Row text is visible immediately |

Switching between already-open tabs uses MM-74 (island content swap), not this.

**Reduce motion:** everything appears at once.

## Micro-animation catalogue

| ID | Where | Moment | Motion | Reduce motion |
|---|---|---|---|---|
| **Compass** | | | | |
| NM-01 | Compass | Operation starts / ends | The sync badge and counts swap with the operation text via `MeridianSwap(rise)`; the progress rule enters from the bottom edge (height 0 → 2 px, `motion-quick`) | Instant |
| NM-02 | Compass | Branch changes (checkout) | The branch name swaps with `MeridianSwap(rise)`; the pill's width follows over `motion-layout` | Crossfade |
| NM-03 | Compass | Ahead, behind, conflict or dirty count changes | `MeridianRollingNumber`; increases of ahead and conflicts pop | Instant |
| NM-04 | Compass | Dirty count goes 0 → n | The warning dot pops in (`spring-pop`). It does not pulse: dirty is a state, not live activity | Instant |
| NM-05 | Compass | Hover | Border fades in (MM-01); the Kbd hint cap (MM-17) sinks when the shortcut is pressed | Same |
| **Toolbar and tabs** | | | | |
| NM-10 | Toolbar | Fetch / Pull / Push / Refresh activated | MM-07 nudge: Fetch and Pull `down`, Push `up`, Refresh `rotate` (one full turn on `spring-snappy`) | None |
| NM-11 | Toolbar | Refresh running over `refreshSpinDelay` | The refresh icon spins (one turn per `motion-spinner`) until done, then finishes its turn and stops (no snap back) | Static |
| NM-12 | Toolbar | Logbook badge (running or failed count) | MM-06; a failure count pops with `attention` colour | Instant |
| NM-13 | Repo tabs | Active tab changes | The active pill glides (`MeridianGlide`, `spring-snappy`) | Instant |
| NM-14 | Repo tabs | Dirty dot appears / disappears | Pop in (`spring-pop`), shrink out (`motion-exit`) | Instant |
| NM-15 | Repo tabs | Tab opened / closed / reordered | MM-27 and MM-28 | Instant |
| **Sidebar** | | | | |
| NM-20 | Sidebar | Checkout | The current-branch mark (check and bold weight) travels from the old row to the new row with `spring-snappy` when both are visible; otherwise it crossfades (MM-25) | Instant |
| NM-21 | Sidebar | Sync badge changes | `MeridianRollingNumber` per number | Instant |
| NM-22 | Sidebar | Ref created / deleted / renamed | `MeridianReveal` for insert and remove, then `MeridianAttention` on the new row; a rename swaps the label with `MeridianSwap(rise)` | Instant |
| NM-23 | Sidebar | Section expand / collapse | MM-24 | Instant |
| **History** | | | | |
| NM-30 | History and Changes headers | Counts change | `MeridianRollingNumber` | Instant |
| NM-31 | History | Selection moves | MM-20 on the fixed-extent list (row extent `rowExtent`); the graph node's selected ring crossfades | Instant |
| NM-32 | History | Search active | Non-matching rows fade to `GitLamaOpacity.unlit` over `laneDim`; clearing the search returns over `motion-hover-out` | Instant |
| NM-33 | History | Search result navigation (next or previous match) | The match row gets `MeridianAttention` once after the scroll finishes | 300 ms tint |
| NM-34 | History | Copy hash | The hash text swaps to "Copied" with a `check` (`MeridianSwap(rise)`), held `copiedHold`, then swaps back | Instant swap |
| NM-35 | History | Ref chip added, moved or removed by an operation (outside NH-1 and NH-2) | Added: pop in (`spring-pop`, from 0.6). Removed: fade and shrink (`motion-exit`). Moved: crossfade on both rows | Instant |
| NM-36 | History | WIP row appears / disappears | `MeridianReveal` at the top; its dashed ring draws with `MeridianStroke` | Instant |
| NM-37 | History | WIP node while there are changes | Static. (The graph spec's WIP node does not pulse) | Static |
| NM-38 | History | Load more (footer reached) | The skeleton rows breathe (MM-64); new rows crossfade over them without a stagger | Static |
| **Detail and diff** | | | | |
| NM-40 | Detail island | Selected commit changes | MM-74 content swap, only after selection rests `detailDebounce`; during scrubbing the content changes instantly | Crossfade |
| NM-41 | Detail header | Hash, author, date change | Covered by NM-40; the avatar crossfades (MM-71) | Instant |
| NM-42 | Diff | Expand context ("show more lines") | The new lines reveal with `MeridianReveal` from the expanded edge | Instant |
| NM-43 | Diff | File section collapse / expand | Chevron rotates (`motion-quick`); body `MeridianReveal` | Instant |
| NM-44 | Diff | Find: current match changes | The match highlight fill pops (scale 1.08 → 1, `spring-pop`) and the scroll uses `motion-layout` when the target is less than one screen away (otherwise a jump) | Instant |
| NM-45 | Diff | Minimap viewport marker | Follows the scroll exactly (no lag); a click on the minimap scrolls with `motion-layout` | Jump |
| NM-46 | Diff | Unified ↔ split | Crossfade (`motion-select`); the scroll position stays on the same line | Instant |
| **Changes and Composer** | | | | |
| NM-50 | File rows | Status glyph changes (e.g. modified → added) | The glyph flips: scaleY 1 → 0 → 1 with a colour change at the middle (`motion-quick`) | Instant |
| NM-51 | File rows | Discard | The row fades (`motion-exit`) and collapses (`motion-layout`) | Instant |
| NM-52 | File rows | Drag starts | `MeridianLift` on the drag feedback; the drop list's edge becomes `accent` and its fill fades to `accent-soft` while hovered (MM-77 without marching) | No lift |
| NM-53 | File rows | Checkbox (partial staging) | MM-11 | Instant |
| NM-54 | Composer | Subject length passes 50 / 72 | The counter's colour changes to `warning` / `danger` over `motion-select`; at 72 the counter nudges 2 px right and back once (`spring-snappy`) | Colour only |
| NM-55 | Composer | Primary button label changes (Commit ↔ Amend, Commit and Push) | Label swaps with `MeridianSwap(rise)`; the width follows (`motion-layout`) | Instant |
| NM-56 | Composer | Commit fails | The failure banner reveals (MM-65); the Composer does not shake (the banner explains) | Instant |
| NM-57 | Composer | Description field grows | The height grows with the text over `motion-quick`, between the min and max line counts | Instant |
| **Logbook and operations** | | | | |
| NM-60 | Logbook | Opens | From its toolbar button: MM-40 with the transform origin at the button (top trailing), plus `rise-overlay` | Fade |
| NM-61 | Logbook | Entry added | The entry enters from the top with `MeridianReveal` and `MeridianEntrance`; the timeline rail extends with it (`motion-layout`) | Instant |
| NM-62 | Logbook | Entry completes | The mark's spinner crossfades into a `check` drawn by `MeridianStroke` (160 ms); the rail segment colour follows (`motion-select`) | Instant |
| NM-63 | Logbook | Entry fails | The mark swaps to `x` (`MeridianSwap`, scale 0.8 → 1, `spring-pop`) and the row shakes once (`shake-field`) if the Logbook is open; the toolbar badge pops (NM-12) | Instant swap |
| NM-64 | Logbook | Output shown / hidden | `MeridianReveal`; the chevron rotates | Instant |
| NM-65 | Logbook | Dismiss / Dismiss all | Rows fade and collapse; Dismiss all staggers from the bottom up, at most 6 | Instant |
| **Rebase and conflicts** | | | | |
| NM-70 | Rebase editor | Reorder (drag or keyboard) | `MeridianLift`; other rows spring out of the way (`spring-gentle`); keyboard moves glide the row one slot (`spring-snappy`) | Instant |
| NM-71 | Rebase editor | Action becomes squash / fixup | The row's indent glides to `rebaseIndent` (`spring-snappy`); the connecting curve to the row above draws with `MeridianStroke` (140 ms) | Instant |
| NM-72 | Rebase editor | Action becomes drop | A strike-through draws across the subject left to right (`MeridianStroke`, 160 ms) and the row fades to `GitLamaOpacity.ignoredRow` | Instant |
| NM-73 | Rebase editor | Action changes | The action chip label swaps (`MeridianSwap(rise)`) | Instant |
| NM-74 | Conflict resolver | Take ours / theirs / both | The chosen side's rail brightens (`conflictRailUnchosen` → `conflictRailChosen`) over `motion-select`, and the result pane's inserted lines get `MeridianAttention` once | Instant |
| NM-75 | Conflict resolver | Conflict count changes | `MeridianRollingNumber` | Instant |
| NM-76 | Conflict resolver | Next / previous conflict | Scroll with `motion-layout` when less than a screen away, else jump; the target region's rail pulses once (opacity 0.48 → 1 → 0.78 over `motion-highlight`) | Instant |
| **Window** | | | | |
| NM-80 | Status bar | Text changes | MM-76 | Instant |
| NM-81 | Drop a folder on the window | Drag enters | The drop prompt enters (MM-40) and its edge marches (MM-77) | No march |
| NM-82 | Window | Focus lost / regained | MM-78 | Instant |

## Rules specific to GitLama

1. **Graph painting stays per row.** Lane drawing, dimming and flowing are painter parameters (`drawProgress`, `dim`, `lit`) on `_HistoryGraphPainter`, driven by one controller per `HistoryGraphView`, not one controller per row. Rows read the current value from an inherited `HistoryMotion` notifier. `shouldRepaint` compares the values.
2. **Recycled rows never replay.** The history and changes lists are virtualised. Any one-time effect (attention tint, entrance, lane draw) is keyed in `MeridianMotionMemory` by a stable key (object id plus trigger sequence). The current commit flash, a `TweenAnimationBuilder` keyed by sequence, replays when the row scrolls out and back; NH-1 fixes that.
3. **Only one travel at a time per island.** NH-1's chip travel and NH-4's row flight use `MeridianTravel`; a second flight lands the first instantly.
4. **Background activity is quiet.** Background fetches, file watchers and status refreshes only roll numbers and change states. They never trigger a highlight, a travel, a stagger or an attention tint, apart from MM-23 for a row the person is looking at that changed underneath them.
5. **No literal durations or curves.** `scripts/check_meridian_usage.py` rejects `Curves.` and `Duration(` in animation parameters under `lib/`. Timers and debounces use named constants in `GitLamaMotion` or `MeridianDurations`.
6. **Evidence.** Every NH item has a widget test that pumps its timeline at the listed times and asserts the values. Every NM item is covered by a test that asserts its end state and zero duration under `disableAnimations`.
