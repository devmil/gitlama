# Assets

| Path | Content | Source of truth in the app |
|---|---|---|
| `brand/gitlama-mark.svg` | The app mark: the ivory (`#FFF8EB`) Lama standing on a Git merge, on a full-bleed cerulean square (`#056CB3`, the light `polar`); the merge's hollow commits show the cerulean ground | `assets/brand/icon.svg` |
| `icons/*.svg` | 81 Lucide icons (lucide-static 1.37.0, ISC, upstream licence header kept), named after the Git action they stand for | `assets/icons/lucide/` |
| `icons/inventory.json` | For every icon: file, upstream Lucide name, purpose | — |
| `fonts/JetBrainsMono-Regular.ttf`, `fonts/OFL.txt` | The `mono` family, SIL Open Font License 1.1 | `assets/fonts/` |

The copies here are byte-identical to the app's files, and `scripts/check_design_contract.py` fails if they drift.

- **Mark:** use it on the welcome screen, in the About box and for platform icons, on the brand ground (`fjord`) or on its own square. Never place it inside the working UI, never recolour it. There is no wordmark: set "GitLama" in the `display` style next to the mark.
- **Icons:** single-ink `currentColor`, 24 × 24 viewBox, 2 px stroke with round caps and joins. Draw them at 16 px (`size-icon`), 14 px in chips and small controls, and 18 px with a 1.75 stroke in the toolbar. Tint: `ink` at rest, `ink-muted` when idle, `on-polar` on a `polar` fill.
- **Adding an icon:** copy it from lucide-static 1.37.0 with its licence header into `assets/icons/lucide/` and `docs/design-system/assets/icons/`, add a row to `inventory.json`, and update `THIRD_PARTY_NOTICES.md`, in one commit. A Lucide upgrade updates every icon at once; never mix versions.
- **Forbidden:** icon fonts, Unicode action glyphs (✓ ✗ ⚠), hand-drawn or generated substitutes, and a second icon family.
