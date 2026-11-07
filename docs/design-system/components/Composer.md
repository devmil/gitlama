# Composer

The commit message editor, docked at the bottom of the Changes island on `pane-alt`. It's never a modal. The consumer provides `subject`, `body`, `staged` (count), `branch` and `amend`.

The description shows 2 to 5 lines on its own. Once the splitter above the Composer gives it a height, the description fills whatever the subject and footer leave; a double click on the splitter returns to the natural height.

The subject counter follows the 50/72 convention: `ink-muted` up to 50, `modified` past 50, `danger` and bold past 72. The primary button names the target branch ("Commit to windows-soak-cleanup") and is disabled while the subject is empty. ⌘↵ commits, ⌘⇧↵ commits and pushes. Amend loads the previous message and changes the button to "Amend 857ece8".

Specimen: [`../specimens/components/Composer.html`](../specimens/components/Composer.html). Reference implementation: `GitLama.Composer` in `reference/bundle.js`, props in `reference/index.d.ts`.
