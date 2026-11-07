# Button

A labelled command. Use **primary** at most once per island, for the thing that island exists to do (Commit, Rebase, Continue). **secondary** is the default. Use **quiet** for inline and low-stakes actions. **danger** only goes in a confirming dialog. Inside rows and headers use **danger-quiet**.

- The consumer provides: `children` (a Git verb in sentence case), optional `icon` (Lucide name), `kbd` (the shortcut keys, shown inside the button), `size="sm"` inside island headers and hunk headers (22px), `loading` (keeps the label and swaps the icon for a spinner), `disabled`.
- Label with the real verb and object: "Commit to windows-soak-cleanup", "Discard 3 files". Never "OK".
- The width follows the label. Don't fix it, because German runs up to 40% longer.
- Focus: 2px `focus` ring. Hover: `pane-hover`, or brightens primary by 6%. Height is `size-control` (28px).

Specimen: [`../specimens/components/Button.html`](../specimens/components/Button.html). Reference implementation: `GitLama.Button` in `reference/bundle.js`, props in `reference/index.d.ts`.
