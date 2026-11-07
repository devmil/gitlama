# SidebarRow

Rows of the repository sidebar, grouped by SidebarSection. SidebarSection takes `title` (set as an `overline`), an optional `count` and an `action` icon (shown on hover). SidebarRow takes `name`, `icon`, `depth` (14px per level), `expandable`/`open`, `current` (the checked-out branch: a check mark and `body-strong`), `ahead`/`behind`, `count` and `state` (`selected` = `polar-soft`, `focused` = `polar` when the sidebar has keyboard focus).

The sidebar sits straight on `ground`, not in an island. Hover is `ground-hover`, inset with `radius-sm`. Every tracked branch shows its sync state, so you never need to open a branch to know whether to pull. Double-click checks out. The context menu holds everything else.

Specimen: [`../specimens/components/SidebarRow.html`](../specimens/components/SidebarRow.html). Reference implementation: `GitLama.SidebarRow` in `reference/bundle.js`, props in `reference/index.d.ts`.
