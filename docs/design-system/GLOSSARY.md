# Terminology

One word per concept in each language. `scripts/check_l10n.py` fails when one
English message has two different German translations; add a term here before
introducing a new one.

| English | German | Meaning |
| --- | --- | --- |
| Commit (noun and action) | Commit | A recorded change; the button that records one |
| Amend | Ändern | Replace the last commit |
| Co-authors | Mitautoren | `Co-authored-by` trailers |
| Merge | Merge | Join another branch's history |
| Rebase, Interactive rebase | Rebase, Interaktiver Rebase | Replay commits |
| Stash; Drop stash | Stash; Stash löschen | Shelved changes; delete one |
| Worktree | Worktree | A linked checkout of the repository (`git worktree`) |
| Snapshot | Snapshot | A named recovery snapshot |
| Snapshot restore | Snapshot-Wiederherstellung | Restoring a named snapshot |
| Hunk; section (where lines are picked) | Block | A changed region of a diff |
| Lock file | Sperrdatei | Git's `index.lock`, left behind by an interrupted command |
| Find a breaking commit | Fehlerhaften Commit finden | The guided `git bisect` search in Repository tools |
| Unified diff | Unified Diff | The single-column diff layout and patch format |
| Diff renderer | Diff-Renderer | An external program that renders a diff |
| Shortcuts | Tastenkürzel | Keyboard shortcuts |
| Recent | Zuletzt verwendet | Recently used items |
| Choose (destination, folder) | auswählen | Pick in a file dialog |
| Retry | Erneut versuchen | Try a failed action again |
| Re-run (checks) | Erneut ausführen | Run CI checks again |
| Logbook | Logbuch | The panel listing running and past Git work (also the "show" command) |
| Remote changes | Remote-Änderungen | Writes sent to a remote host and their outcomes |
| Git operation | Git-Operation | One Git command GitLama ran |
