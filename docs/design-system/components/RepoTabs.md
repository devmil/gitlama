# RepoTabs

One tab per open repository, on `ground` under the toolbar. The consumer provides `tabs` (`name`, `dirty`, `hint`) and the `active` index.

A tab shows the repository's folder name unless the user named it. A second click on the active tab, or Rename tab… in its context menu, edits the name in place inside the pill (with a `focus` edge): ↵ or leaving the field keeps it, Esc cancels, an empty name (or Use folder name) restores the folder's. The name belongs to the repository, so it returns when the repository is opened again.

The strip is Meridian's `MeridianTabStrip`; its guideline (TabStrip) owns the pill, chip, rule, motion and drag behaviour. GitLama supplies the repository's icon, name, sync tooltip and uncommitted-changes dot, the native menus and the workspace's order.

Tabs and group chips are dragged as in browsers: the other tabs slide aside while a tab passes them, and it settles where it is dropped. A tab joins a group once it passes the group's chip or between two of its tabs; at the group's end the rule shows whether it is in, and a short nudge outwards takes it out. Dragging a chip carries the whole group. Escape cancels a drag.

Tabs can be grouped. A group's tabs stand side by side behind its chip: a `radius-md` pill, 20 px tall, tinted with the group's colour (one of the eight `series` colours, 18% at rest, 28% on hover) and showing the name in `label`, or only a colour dot when unnamed. A 2 px rule in the group's colour runs under the chip and its tabs, across the gaps between them, rounded where the group starts and ends. A click on the chip collapses the group: its tabs fold away (`motion-layout`), the chip shows their count in `ink-muted` and the rule goes. Collapsing the active tab's group activates the nearest tab outside it; activating a hidden tab opens its group again. A group may show an icon from the repository icon catalogue, `icon-sm` in the group's colour, before its name or, unnamed, in place of the dot. The chip's context menu renames the group in place, changes its colour or icon, collapses or expands it, ungroups it, or closes its tabs. A tab's context menu adds it to a new group (whose name is edited at once) or an existing one, or removes it from its group. Groups are saved with the open tabs.

The active tab is a `pane` pill with `shadow-pane`: it's the top of the workspace below it. Inactive tabs are `ink-muted` text only. A `modified` dot marks uncommitted changes. The close cross appears on hover and on the active tab. Tabs shrink to 110px, then scroll. They never wrap.

Specimen: [`../specimens/components/RepoTabs.html`](../specimens/components/RepoTabs.html). Reference implementation: `GitLama.RepoTabs` in `reference/bundle.js`, props in `reference/index.d.ts`.
