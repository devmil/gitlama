# Release notes

## Unreleased Stable

- You can now revert a commit while you have local changes. Changes that don't touch the reverted files simply stay where they are. If some do, or some are staged, GitLama lists them and asks first; it then sets them aside, reverts and puts them back with their staging. If they conflict with the revert, you resolve them in Changes, and a recovery copy stays in Stashes. Hosts receive a new GitLama helper.
- GitLama is open source: About now links to its source code on GitHub, and so does the website.
- GitLama no longer offers Undo, Redo or Recovery history. They worked for only some actions, so you had to remember which ones could be taken back. The review before an action still says what it changes, and now says plainly what it deletes. Ctrl+Z and Cmd+Z now only undo typing. To keep a way back, save a named snapshot before you try something. Restoring a snapshot now keeps your current changes as a stash. Hosts receive a new GitLama helper.
- GitLama now remembers how you like diffs shown. Wrapping long lines, side-by-side or unified layout, whitespace, context lines, plus and minus markers and the minimap stay as you set them, in every diff and after a restart. Set them from the buttons above a diff or on the new Diffs page in Settings.
- Save any commit as a ZIP file: right-click it in History, or use the archive button next to its hash in the commit details. The ZIP holds every file and folder of that commit in one folder, including submodules and Git LFS files. It also works for repositories on another computer. Hosts receive a new GitLama helper.
- Unstaged files and folders can be added to .gitignore from their menu. GitLama suggests the entry that matches exactly that file or folder, and you can edit it first, for example to *.log. Hosts receive a new GitLama helper.
- The settings window is wider, keeps its size while you switch pages and shows its page list in smaller windows.
- When an action fails, GitLama now shows a dialog instead of a banner at the top of the window. It shows what Git reported and copies a support report, optionally with Git's output.
- When a fetch, pull or push fails for a reason GitLama recognises, it explains what happened and offers a fix. If another program, such as your editor, is using the repository, GitLama shows its lock files and lets you try again or remove stale locks. If two remote branches differ only in letter case, which macOS cannot store side by side, GitLama can repair this computer's copies and fetch again. If a push is rejected because the remote has newer commits, GitLama offers to fetch them. Remote hosts receive an updated helper.
- The Fetch dialog has an option to keep remote branches that were deleted on the server.
- Repositories on another computer keep working after that computer restarts instead of reporting a different identity. When a repository there really was replaced, its tab now lets you trust and open it again. Hosts receive a new GitLama helper.
- The app icon is now rounded on Linux, Windows and macOS and inside the app, matching other apps in the dock, taskbar and launcher.
- The portable Linux tar now includes the app icon and desktop entry.
- Changes and History now share diff viewing controls for layout, context, whitespace and display settings.
- Restart Northspline as a Flutter/Rust port of QSpline.
- Add an empty localized desktop shell, native bridge and pinned devmil-git dependency.
- Add parity specifications, architecture, package tooling, initial branding and an unpublished website preview.
- Add the QSpline 2.1 light/dark palette, three density modes, bundled Lucide icons and JetBrains Mono.
- Add shared accessible desktop controls and a localized component gallery with keyboard, semantics and viewport coverage.
- Match the QSpline repository toolbar with explicit mode and repository context, exact 52/44 px shell geometry, and a localized compact overflow below 1100 px.
- Add typed repository sessions, atomic settings, crash recovery and bounded native activity history.
- Add localized open, initialize and clone workflows with native-path recents, process-tree cancellation and safe partial-destination handling.
- Add bounded SSH host-key verification, ephemeral credential retry and stalled-transfer cleanup for clone operations.
- Add persistent multi-repository tabs, responsive workspace panes, per-repository navigation and safe desktop window restoration.
- Add bounded live status and ref projection, shared-watcher refresh, repository-scoped overflow recovery and persistent repository conditions.
- Add an application-wide operation center, bounded Activity details, shared command navigation, stable sidebar actions and safe index-lock recovery.
- Make CI portable across Fedora, macOS and Windows runners, build Linux releases in the pinned Ubuntu 22.04 Podman baseline, bypass offline target runners during recovery and clean only owner-marked shared dependency checkouts.
- Add an 88-command registry with one-to-one executable coverage of all 72 QSpline commands, focused Changes/History/Diff/Conflict/Rebase/Sidebar routing, persistent shortcut overrides, explicit unbinding, reset and cross-platform conflict/reserved-key checks.
- Add a measured 100k-commit history path with exact G-LANE-01 projection, bounded native pages and a fixed-extent Flutter renderer.
- Anchor ancestry-lighting transitions at commit nodes instead of history-row boundaries.
- Make history text search highlight and navigate matches without filtering topology, scale graph rows to dense branch layouts, reveal sidebar refs in History, expose remote branches, use native context menus, and consolidate staging actions in pane headers.
- Keep History details below the graph at every width, restore their persisted selection on launch, split changed files and diff into resizable columns, add list/tree modes for changed files, and keep the HEAD badge on the checked-out commit while selection changes.
- Add a measured 100k-row unified/split diff path with bounded bridge pages and byte-exact native partial-patch proofs.
- Add same-request progressive history completion with stable preview lanes and prioritized bounded metadata hydration.
- Add byte-safe commit trees, virtualized blame, rename/range history, anchored inspection navigation and stale-safe file restore previews.
- Add a paged production commit-diff surface with native line identities, unified/split layouts, context and whitespace controls, wrapping, search, hunk navigation, intraline/syntax styling, minimap and bounded image comparison.
- Add a durable, bounded recovery ledger with integrity-checked snapshots, sequential undo/redo, stale-state checks and explicit confirmation.
- Add previewed branch, tag, remote and reset commands with live ref rows, drift refusal, exact shared Git arguments and truthful recovery eligibility.
- Add byte-exact file, hunk, line, selected and all staging with partial untracked support, atomic index replacement, drift refusal and staged/unstaged workspace controls.
- Add an embedded commit editor with durable per-worktree drafts, templates, recent messages, amend and hook controls, exact drift refusal and distinct commit/push outcomes.
- Add irreversible tracked and partial discard plus untracked-only Clean with frozen scopes, exact drift refusal, explicit confirmation and no hidden recovery entries.
- Add exact patch export scopes, atomic overwrite-safe output, checked patch application, confined recovery snapshots and reversible multi-file apply.
- Add per-remote fetch, pull and push with policy-controlled pulls, exact force-with-lease protection, bounded authentication and cancellable reconciled progress.
- Add stable-identity stash workflows, selected and complete scopes, keep-index, authoritative graph decoration and explicit auto-stash checkout with retained failure recovery.
- Add previewed merge, ordered cherry-pick and revert workflows with isolated cancellable conflict prediction, publication warnings, sequencer truth and executable recovery.

## Unreleased Beta

- Record safe diagnostic events for fetch, pull and push, including background fetch, with start, result and failure events and detailed timing.

## [0.1.0-beta.65] - 2026-11-07

- GitLama is now open source under the MIT License. Its source code, releases and issue tracker are on GitHub.
- On Windows, executable files in a commit saved as ZIP now stay executable when the archive is unpacked on macOS or Linux.

## [0.1.0-beta.64] - 2026-11-04

- Fix Windows startup failing on accounts where Windows allows saved credentials only for the current sign-in session.

## [0.1.0-beta.63] - 2026-11-03

- Diagnostics now keep bounded recent history in memory instead of writing logs automatically. Settings lets you temporarily enable detailed diagnostics, review an export, save it, or share it where supported. Nothing is sent automatically.

## [0.1.0-beta.62] - 2026-11-03

- Checking out a remote branch now creates and switches to a local branch linked to that remote branch, so Pull and Push use its upstream. This fixes checkout failing with “the request could not be validated,” with or without local changes. Hosts receive a new helper.
- Settings > Git now shows Faster change checks for the open repository: whether Git's untracked cache and file system monitor are on, and a button to turn them on. Before, you could only turn them on from the offer GitLama shows when a repository is slow to check, and not again after you dismissed it.
- The CI status in the checked-out branch's chip in History is now clearly visible in light and dark themes.

## [0.1.0-beta.61] - 2026-11-01

- The default branch’s CI status now sits inside its branch chip in History, matching pull request chips.
- Creating a branch from the toolbar or sidebar now starts at the current commit. Creating one from History uses the chosen commit. If that commit is unavailable, GitLama lets you refresh and choose again while keeping your input. Switching repositories cannot apply an open branch dialog to another repository. Hosts receive a new GitLama helper.

## [0.1.0-beta.60] - 2026-11-01

- Files GitLama shows as binary can now be shown as text anyway with Show as text, in the Changes and History diffs and in the History file preview. This helps with text files Git mistakes for binary; for real binary files the result is unreadable. Lines of such a file cannot be staged one by one. Hosts receive a new GitLama helper.
- SSH destinations now accept `user@host` in the Add host form, `--remote` and `ssh://` links, using existing SSH keys and agent authentication.
- When a host already has the maximum number of repositories open, GitLama now explains the limit and asks you to close another repository tab on that host before trying again.
- Opening a worktree on a host that already has the maximum number of repositories open now shows the same explanation in the worktree's tab.
- You can now have up to 16 repositories open per host instead of 8. Hosts receive an updated GitLama helper the next time they connect.
- Open a repository on a host from the terminal or another app with `gitlama --remote <host> <path>` or `gitlama ssh://<host>/<path>`, using an SSH alias, hostname or `user@host`. If no saved host matches yet, GitLama offers to add it first.
- History now also shows whether CI passes on your repository's main branch, next to the main branch's chip.

## [0.1.0-beta.59] - 2026-10-30

- The sidebar's Integrations section now shows whether CI passes on your repository's main branch, next to the linked hosting account. Hover the badge to see the branch and result.
- Right after you push, a branch's pull request no longer stays marked as out of date with advice to fetch. GitLama now checks the pull request again shortly after, once the host has caught up with your push.
- Escape now closes Settings right after you open them with Ctrl+, or Cmd+,.
- In the conflict resolver, selected text in the Result stays visible over resolved conflicts. Each resolved block is now shaded across the whole line in the colour of the side it came from.

## [0.1.0-beta.58] - 2026-10-29

- Dates in History are no longer cut off: dates such as "Mon, Sep 28" now show their day number.
- Keep selecting files while GitLama stages or unstages changes, and queue more files without waiting for the first one. Pending files are marked, and you can cancel the waiting actions. GitLama shows whether it is waiting, checking changes, updating the index or refreshing the result. If staging cannot finish safely, it stops the waiting actions and tells you. Hosts receive a new GitLama helper.
- The conflict resolver now guides you through each file. A step line at the top shows whether to pick changes, review the result, resolve the file or continue, says what to do next and counts the resolved files. Deleted files are marked in the file list, and after you resolve a file GitLama opens the next one and tells you which.
- Resolving conflicts is clearer. When a file was deleted on one side, GitLama asks whether to keep the deletion or the file, highlights the side you picked, and shows that resolving will delete the file. You can take the choice back at any time. Once every file is resolved, the summary shows how each one was resolved, for example Deleted or Kept current version, so you can undo the right one before you continue.
- Worktrees of one repository now share a single tab. When a repository has more than one worktree open, its tab shows how many, and a second row below the tabs lists each worktree by its branch, so you can switch, reorder or close them. The row also opens the repository's other worktrees or adds a new one, and it disappears again when only one worktree is left open.
- Repositories on another computer can now use the hosting accounts configured on this computer. View pull requests, issues and checks, open reviews and provider pages, and choose an account in Settings → Repository link. GitLama contacts the provider from this computer; it needs network access and account permission there.
- Upgrade Flutter to 3.47.8 to include the eMudhra certificate security fix in future builds.
- The stage and unstage buttons that appear when you hover a changed file now use the same arrow as the toolbar's Stage selected and Unstage selected buttons, so they no longer look like Stage all and Unstage all.

## [0.1.0-beta.57] - 2026-10-28

- Windows releases can proceed if the resource soak fails. Its results are still kept for investigation; Linux resource checks and Windows installation checks still have to pass.
- In large repositories, selecting a changed file shows its diff without waiting for GitLama to finish checking the whole repository for changes. If Git takes longer, the diff says it is waiting for Git and appears when Git answers, instead of reporting that it could not be loaded.
- When checking a repository for changes is slow, GitLama offers to turn on Git's own speed-ups for it: the untracked cache and, on Windows and macOS, the file system monitor. Nothing changes until you choose Speed up.
- Hosts receive a new GitLama helper.

## [0.1.0-beta.56] - 2026-10-27

- Pull now offers “Stash, pull, and reapply my changes” when you have local changes. GitLama saves staged, unstaged and new files, pulls, and restores your staging too. A named recovery copy stays in Stashes until you remove it. If pulling or restoring stops, GitLama explains what completed and how to recover; conflicts open through Changes. Hosts receive a new GitLama helper.

## [0.1.0-beta.55] - 2026-10-27

- Keep the matching debug symbols and build details for new releases so crash reports can be traced to the shipped code. The debug files are stored privately outside the installers.
- The merge conflict file list can now be resized and switched to a folder tree. The resolver explains why apparently identical files still need review, including executable permissions, file types, line endings and other invisible text changes. Entry details show each version’s metadata. Deleted sides display correctly, and small windows keep the result and resolution controls accessible.
- Use Flutter's alternative renderer on macOS to avoid a known graphics-engine crash when returning to GitLama after sleep or time in the background.
- You can now report a problem from GitLama: Report an issue… in the Application menu opens the GitHub issue tracker in your browser.
- On Linux, windows opened from the inspector now look like the main window: rounded corners, no extra grey title bar, and the window buttons in the window itself.

## [0.1.0-beta.54] - 2026-10-21

- When you name a new branch, choosing a suggested folder such as feature with Enter keeps the cursor in the name field, so you can continue typing.
- Discard all now works when tracked changes and new files are mixed together. One confirmation explains what will be restored and permanently deleted. If only part of the action completes, GitLama tells you to check the remaining changes.
- Forgejo and Codeberg setup now explains that Confidential Client must be disabled. If an OAuth app rejects sign-in, GitLama explains what to check instead of only reporting “unavailable”.
- Check out any commit with detached HEAD from its History menu or by double-clicking it, after confirmation. With uncommitted changes, choose Dismiss, Stash, or Stash & reapply. Your changes stay in the stash if reapplying conflicts. If Git cannot stash the changes, checkout stops safely. Hosts receive a new GitLama helper.
- Discarding or staging from a selected file now affects all selected files. The file menu also offers Discard selected or Clean selected when applicable.
- Find a recent repository quickly: type in the filter above the recent repositories to show only those whose name or location matches, then press Enter to open the first one.
- The repository chooser now shows the GitLama app icon.
- After resolving conflicts, the resolved files appear in a tidy list you can scroll, each with its own undo button, and Undo all takes every resolution back at once.
- Resolve many conflicted files in one go: tick them in the conflict list (or use Select all, or hold Shift to tick a range) and choose Use current or Use incoming.
- Image diffs show the size of each version: its width and height in pixels and its file size.
- Press Ctrl+F (Cmd+F on macOS) while looking at a diff to search in it.

## [0.1.0-beta.53] - 2026-10-19

- A pull request in History now shows next to the commit it is at. If your local branch and its remote branch are at different commits, only the one the pull request points to shows it. The pull request also shows whether its checks passed, failed or are still running, and whether it has merge conflicts, when GitHub, GitLab or Forgejo reports this. Running checks update by themselves.
- Find branches quickly: click the search button in the sidebar, or just start typing while the sidebar has focus, to show only the branches, remote branches and tags that match. Press Escape or click the x to show everything again.

## [0.1.0-beta.52] - 2026-10-18

- Show other refs in History is now also in Settings → Appearance, next to the eye button menu in History.

## [0.1.0-beta.51] - 2026-10-18

- GitLama no longer offers Undo, Redo or Recovery history. They worked for only some actions, so you had to remember which ones could be taken back. The review before an action still says what it changes, and now says plainly what it deletes. Ctrl+Z and Cmd+Z now only undo typing. To keep a way back, save a named snapshot before you try something. Restoring a snapshot now keeps your current changes as a stash. Hosts receive a new GitLama helper.
- GitLama now remembers how you like diffs shown. Wrapping long lines, side-by-side or unified layout, whitespace, context lines, plus and minus markers and the minimap stay as you set them, in every diff and after a restart. Set them from the buttons above a diff or on the new Diffs page in Settings.
- History no longer shows commits that only other tools' refs reach, such as T3 Code checkpoints or Git notes, so the graph shows your branches, remote branches, tags and stashes. Turn on Show other refs in History's view options menu (the eye button) to see them again. When you open a commit History hides, History tells you and offers to show it. Hosts receive a new GitLama helper.

## [0.1.0-beta.50] - 2026-10-17

- Save any commit as a ZIP file: right-click it in History, or use the archive button next to its hash in the commit details. The ZIP holds every file and folder of that commit in one folder, including submodules and Git LFS files. It also works for repositories on another computer. Hosts receive a new GitLama helper.
- Unstaged files and folders can be added to .gitignore from their menu. GitLama suggests the entry that matches exactly that file or folder, and you can edit it first, for example to *.log. Hosts receive a new GitLama helper.
- When an action fails, GitLama now shows a dialog instead of a banner at the top of the window. It shows what Git reported and copies a support report, optionally with Git's output.
- When a fetch, pull or push fails for a reason GitLama recognises, it explains what happened and offers a fix. If another program, such as your editor, is using the repository, GitLama shows its lock files and lets you try again or remove stale locks. If two remote branches differ only in letter case, which macOS cannot store side by side, GitLama can repair this computer's copies and fetch again. If a push is rejected because the remote has newer commits, GitLama offers to fetch them. Remote hosts receive an updated helper.
- The Fetch dialog has an option to keep remote branches that were deleted on the server.

## [0.1.0-beta.49] - 2026-10-16

- Repositories on another computer keep working after that computer restarts instead of reporting a different identity. When a repository there really was replaced, its tab now lets you trust and open it again. Hosts receive a new GitLama helper.

## [0.1.0-beta.48] - 2026-10-16

- The settings window is wider, keeps its size while you switch pages and shows its page list in smaller windows.

## [0.1.0-beta.47] - 2026-10-15

- The conflict resolver now highlights syntax as diffs do: in both sides, the ancestor and the result you edit.

## [0.1.0-beta.46] - 2026-10-14

- Scrolling to the end of a diff now shows its last line in full: the horizontal scrollbar no longer covers it.

## [0.1.0-beta.45] - 2026-10-14

- Long lines in the conflict resolver are no longer cut off: they wrap by default, or scroll sideways when you turn wrapping off. The Take current and Take incoming buttons now sit above the side they take, and pointing at a side highlights it and shows what a click will do.
- Stage and unstage whole files even when their combined diff is too large to preview. Large files also no longer exceed an in-memory limit when preparing Discard or Clean. Failed actions now show a message that stays until you dismiss it, and appear in the Logbook with a support report you can copy. Reports contain failure codes and build information, without repository contents, paths or credentials. Hosts receive an updated remote helper on their next connection.
- Diffs now highlight code syntax in History, Changes and inspector windows, for repositories on this computer and on other computers. The text appears at once as before and the colours follow a moment later, without slowing down scrolling, selecting or staging. Hosts receive an updated remote helper on their next connection.
- Dialogs that only show information or let you manage something, such as Hosts, keyboard shortcuts and About, now close with the ✕ in their top corner, like Settings.
- Dismiss all in the Logbook now clears every warning, including those from other computers, and dismissing a single entry slides it away smoothly. Showing a new file's changes no longer adds a warning to the Logbook. Hosts receive an updated remote helper on their next connection.
- Image changes now preview SVG graphics with blur, shadow, pattern and mask effects. When an image cannot be previewed, GitLama says why.
- Repository tools, Snapshots and the custom commands settings are tidier: clear section headings, even spacing, results and facts laid out like the rest of the app, and a guided "Find a breaking commit" search that asks plain questions. File sizes now read like "47 KB" instead of long byte counts, and many messages avoid Git jargon such as "index" or "HEAD".
- Choosing single lines to stage, unstage, discard or turn into a patch now looks like the diff itself: line numbers, coloured added and removed lines and a checkbox beside each change. Tick a section header to take the whole section, and see how many lines you have picked, with Select all and Select none.
- Many smaller dialogs are clearer and calmer: About GitLama is redesigned, confirmations to run a diff renderer or another program show the program and its limits as simple facts with the exact command tucked away, the hosting setup guide is a numbered list of steps, the merge-or-rebase choice explains both options, and undo, restore and discard confirmations use plainer words. The Create patch / Apply patch switch no longer stretches across the dialog, and adding a line comment to a review now says "Add to review".
- Pushing, pulling, deleting tags and branches, creating repositories, worktrees and patches, and editing hosts use cleaner forms: labels sit above fields, options explain in plain words what they do (for example "Overwrite the remote branch" instead of force push with lease), and lists of remotes or files are tidy and bounded. Server keys, LFS pointers and patch previews show their details as clear facts.
- A dropped commit in the interactive rebase editor is now struck through only as far as its text.
- Long names in lists, such as branch names in the restack review, are no longer cut off while there is still room; the shorter text beside them gives way first.
- Rebasing, restacking, merging, cherry-picking, reverting and restoring a snapshot ask clearer questions. Each dialog says in one sentence what will happen, lists branches, steps or files tidily, keeps Git details tucked away, and only warns when something actually needs your attention.
- Creating a stash is clearer. Choose between all changes and only selected files; the file list looks like the Changes list and has Select all. The options now say in plain words what they do.
- The Logbook filter no longer cuts off its labels, also at larger text sizes, and the timeline line now continues through the selected entry.
- In the command palette, the search field no longer runs into the esc hint.
- The "Create patch from this diff" button in the diff toolbar now sits at the right edge, and narrow diff panes keep the toolbar controls clear of it.

## [0.1.0-beta.44] - 2026-10-13

- The repository details that open from the repository name in the title bar have a new look: their colour shows at a glance whether the repository is clean, has changes or conflicts, or is busy, and branch, upstream and changes are shown side by side.
- A long commit message no longer pushes the changed files and diff out of view in History; the message scrolls instead.
- Commits, blame and file history of repositories on a remote host can open in their own window again. The window reads through the main window's connection to the host; when the host is not connected, it says so and you can try again after reconnecting.
- In Changes, the discard buttons are now red and kept apart from the staging buttons, so it is harder to discard changes by accident.

## [0.1.0-beta.43] - 2026-10-12

- Remote workspaces: hosts receive an updated GitLama helper on their next connection.
- Reduce motion and Full motion are now saved, and choosing them no longer stops later settings changes from being saved.
- Remote workspaces: an undo, redo or patch whose result could not be confirmed is now listed under Remote changes for review instead of being reported as done.
- Dragging several files to the other change list now stages or unstages them as expected.
- Remote workspaces: when GitLama cannot confirm whether a change was applied on the host, it now tells you to review it under Remote changes instead of failing silently.
- Diffs always open in place, even when Blame, Contents and History are set to open in a window.
- The conflict resolver's Resolve button and saving now agree, and a file with a Markdown heading underline is staged once resolved.
- Commit is disabled until something is staged, and its shortcut follows the same rule.
- Deleting a worktree from the sidebar respects a remote host's read-only setting.
- A paused revert offers Skip in the repository banner.
- The patch dialog uses its full width again.
- The history search and reflog no longer carry over to another tab.
- Remote workspaces: tabs reopen whenever their host connects, also after connecting from the host dialog.
- The shortcut reference shows conflicts among your own shortcuts.
- Restack no longer applies a configured auto-stash.
- Remote workspaces: staging up to 256 files at once now works on hosts as it does locally, and a change whose preview went stale on the host now says so instead of failing.
- Settings changes are no longer lost when a remote host or account fails to save at the same time.
- Confirmation buttons now say what they do, and pressing Enter in a form dialog such as Create branch submits it.
- Signing in for a clone or a push/pull now uses the same dialog.
- Find bars, section headers and empty states look and behave the same everywhere; destructive menu items are marked and listed last.
- German texts now use one word per term throughout.
- Pull and push work for branches tracking a remote whose name contains a slash.
- Staging, discarding or cleaning a file with a name like `*.txt` now affects only that file.
- Commit failures from hooks and signing are recognized reliably in every language.
- Interactive rebase opens plans with commits that have no subject, and warns about every commit that was already pushed anywhere.
- Adding a self-hosted server connection now accepts only secure `https` addresses, as saving it requires.
- Recovery snapshots and other private files GitLama stores are readable only by you.
- The inspector no longer offers to open a file in your editor or file manager when the file is missing from your working copy.
- Inspector windows now follow your theme, density and reduced-motion settings, and offer Try again when they cannot start.
- A lost connection to a remote host during a merge, rebase or restack is now reported.
- The keyboard shortcut reference shows Shift and Alt correctly on Windows and Linux.
- Conflict resolution keeps your unsaved choices when you switch to another tab and back.
- Discard is no longer offered for a selection that mixes new and changed files.
- File menus no longer offer Show contents for a submodule.
- When Git may have changed your repository but GitLama could not confirm it, GitLama now says so and asks you to check the repository before trying again, instead of reporting a failure.
- The operation center lists worktree, submodule, LFS, bisect and custom-command changes as your own operations, so their failures are reported instead of appearing as background warnings.

## [0.1.0-beta.42] - 2026-10-11

- Clicking the repository name in the toolbar now opens its details: where it lives, its path, branch and upstream, changes, and what is running. Copy the path or open the folder from there.
- The command palette has its own **Commands** button next to the repository name. The keyboard shortcut works as before.
- Right-click a repository tab to copy its path.
- Remote workspaces: you can now initialize a new repository on a remote host. Choose the host in the Initialize repository dialog, pick an empty folder or type the path of a new one, and the repository opens in a remote tab. Hosts need changes allowed and receive an updated GitLama helper on their next connection.
- Deleting a remote branch, or pushing or deleting a tag, no longer fails with "The transfer request is invalid." when you have no local branch of that name.

## [0.1.0-beta.41] - 2026-10-11

- Remote workspaces: when a host is missing the GitLama helper, for example after an update, you can install it right in the tab that could not connect, and its tabs reopen afterwards.
- Remote workspaces: hosts can install the helper automatically, so updates no longer stop you with a missing helper.
- Remote workspaces: the new Remote hosts page in Settings lists all your hosts and lets you change their access, automatic installation, name and SSH alias.
- Remote workspaces: GitLama updates no longer need a new helper on your hosts unless the helper itself changed. This update installs the helper once more.
- Remote workspaces: on hosts where you allow changes you can now merge, cherry-pick, revert, rebase, resolve conflicts, undo and redo, use snapshots and bisect, restore files, apply patches, amend commits, reset branches and manage worktrees, submodules and Git LFS.
- Remote workspaces: the status bar shows whether GitLama may only read or also change the current host, and lets you switch it with one click.

## [0.1.0-beta.40] - 2026-10-10

- Remote workspaces are no longer experimental: open repositories on other computers without turning on a setting first.
- Choosing whether GitLama may change a host's repositories is now a clear Read only / Allow changes choice that takes effect immediately.
- Hosts can have their own color and icon, shown on their tabs so you can tell at a glance which computer a tab belongs to.
- Remote workspaces: image changes, including SVG files, are now shown for repositories on another computer, and external diff tools and diff renderers work for them too.
- Remote workspaces: you can now create patches from a repository on another computer; the patch is saved on this computer.

## [0.1.0-beta.39] - 2026-10-09

- Experimental remote workspaces: a lost connection is now restored automatically, and the tab shows why it was lost and when the next attempt runs. Remote tabs also reconnect when GitLama starts.
- You can now rename a remote. "Edit remote" is now called "Change remote URL".
- Experimental remote workspaces: Discard and Delete now work on the remote computer when changes are allowed for the host.
- Features that are not available for a remote repository are now shown greyed out with the reason instead of being hidden.
- The remote folder picker now follows the path as you type it and shows whether that folder exists on the host.
- Opening a remote repository from a new tab now uses that tab, as opening a local folder does.
- The remote folder picker now starts at the top of each folder you open.

## [0.1.0-beta.38] - 2026-10-09

- Fixed: while connected to another computer, local repositories could show Git commands as failed and older commits would not open until GitLama was restarted.
- Remote fetch, pull, push and other operations now show their progress and result in the operation island.
- Remote workspaces: when Pull, Push, Branch or other changes are unavailable for a remote repository, GitLama now tells you why, for example that you need to turn on Allow changes for the host or reconnect.

## [0.1.0-beta.37] - 2026-10-08

- Experimental: remote workspaces also work with a Raspberry Pi or another 64-bit Arm Linux computer running a 64-bit system such as Raspberry Pi OS Bookworm.
- Experimental: remote workspaces now also work with Macs as the other computer. GitLama recognizes whether it is a Linux PC or a Mac and installs the matching helper.
- Experimental remote workspaces: create, rename, delete and switch branches, manage tags, upstreams and remotes, use stashes, and fetch, pull or push on the other computer. Fetch, pull and push sign in with the credentials set up on that computer. If GitLama cannot confirm whether a change was applied, it lists it under Remote changes instead of trying again.
- Fixed: adding a remote host from a new tab failed with "The host could not be saved". Settings changes made while a new tab is open are now saved as well.
- When a remote host cannot be saved, GitLama now tells you why and shows an error code you can report.
- Fixed: remote URLs such as `git@github.com:owner/repo.git` show their SSH login instead of `[REDACTED]`.
- Fixed: Edit remote can no longer replace a remote's URL with a hidden placeholder. When the current URL contains a password or token, the field starts empty and asks for the complete new URL.

## [0.1.0-beta.36] - 2026-10-07

- Fixed: with remote workspaces turned on, Open Remote Repository… now appears on the start page and in a new tab. Dropping repository folders onto the window and reviewing pull requests from the Integrations panel work again as well.

## [0.1.0-beta.35] - 2026-10-07

- Experimental: open repositories that live on another Linux computer over SSH. Turn it on in Settings, add the computer with the SSH alias you already use, and let GitLama install its matching helper there after you confirm. You can browse history, changes and diffs; staging and committing can be allowed separately for each computer.
- If a connection drops during a remote change, GitLama tells you whether the change was applied, or that it could not tell, instead of guessing or trying again.
- History diffs now show the stored file contents even when a repository configures a textconv filter.
- A clearer way to explore history. Every commit opens in one inspector with a breadcrumb and Back and Forward buttons that always stay in place, and the graph follows when you go back.
- Look at any file as its diff, its contents, its blame or its history with one switch. File history shows each change's diff right next to the list.
- "All files" now lists the whole tree of a commit with the same rows and actions as the changed files.
- Pop any view out into its own window, which has the same tools and can show its commit in the main window again. A setting chooses whether blame and history open in the detail area or in a window.
- Every file menu now offers the same actions, wherever the file is listed.

## [0.1.0-beta.34] - 2026-10-06

- Comparing two commits on different branches now shows their changes. When the comparison is too large to show at once, its changed files are listed and open one at a time.
- A comparison now highlights only the commits that differ between the two selected commits, not every row in between.

## [0.1.0-beta.33] - 2026-10-06

- GitLama returns to blue: a cerulean app icon and accent for selections, focus and primary actions. The orange-red accent clashed with the red that marks errors and conflicts.
- Reduce Linux window-rendering CPU while keeping smooth rounded corners, themed borders and native resize edges.

## [0.1.0-beta.32] - 2026-10-05

- GitLama now wears Git's own orange-red: a new app icon and a warmer accent for selections, focus and primary actions, so it stands apart from the other Lama apps in the dock.
- Open a repository with `open -a "GitLama.app" /path/to/repository` on macOS, whether GitLama is starting or already running.
- The app icon is now rounded on Linux, Windows and macOS and inside the app, matching other apps in the dock, taskbar and launcher.
- The portable Linux tar now includes the app icon and desktop entry.

## [0.1.0-beta.31] - 2026-10-04

- GitLama has a bolder app icon that is easier to recognize.
- The GitLama website has a new design and updated download pages.

## [0.1.0-beta.30] - 2026-10-04

- NorthSpline is now GitLama, with a new icon and About screen. This development transition starts a fresh app profile; existing NorthSpline development profiles are left untouched.
- Pull requests whose branch was deleted, for example after merging, no longer stay in the sidebar.
- Tab groups have a new Edit group dialog: set the name, color and icon in one place and see the result in a live preview. Tab groups and repository icons can now use any custom color, not just the eight palette colors.
- Remote branches can now be deleted directly: right-click a remote branch and choose Delete remote branch. It is deleted only if it has not changed since your last fetch, and you no longer need a local branch to do it.
- Image diffs now also show BMP, ICO (such as favicons), TIFF and QOI images, and files with upper-case extensions like `.JPG`.

## [0.1.0-beta.29] - 2026-10-03

- Files above 8 MiB show their size and type in Changes, History and comparisons instead of keeping the diff loading.
- Large files in a repository no longer block staging other changes.
- Fetching now removes remote branches that were deleted on the server, and deleting a remote branch that is already gone (for example after a merged pull request) no longer fails.
- Pushing a branch without an upstream now sets the upstream by default.

## [0.1.0-beta.28] - 2026-10-03

- Amend now fills the last commit’s subject and description even when selected immediately after opening Changes. Draft edits are preserved.
- Open diffs for new files left at a staged rename's original path, and for unstaged edits to its destination.
- Preview SVG icons and other supported vector artwork in image comparisons.
- Choose the new worktree's destination with the system folder picker, or enter its path directly.
- Fix staging new files and folders individually, which could fail even when "Stage all" worked.
- Fixed cut-out window corners on Linux while keeping the rounded appearance.
- Move the Linux window by dragging anywhere on the open screen's title area, including over the Northspline name.

## [0.1.0-beta.27] - 2026-10-02

- Delete worktrees whose folders are missing. If a deletion fails, an error now stays visible beside the worktree list.
- Worktree names now follow branch switches automatically. A checkmark and bold name make the current worktree easier to spot.
- Hosting connections now renew expiring access tokens automatically, so Forgejo and GitLab keep working without repeated sign-ins.
- Right-click a commit or any of its chips to access commit actions directly, without opening a commit submenu.

## [0.1.0-beta.26] - 2026-10-02

- Revert a commit by creating a new commit or leaving the reversed changes staged for review. Commit or stash existing changes first. Apply without committing works with one commit at a time; merge commits cannot be reverted yet.
- Find commands in grouped menus. Right-clicking a commit or one of its chips now opens the same menu, with a submenu for every branch, tag and stash at that commit.
- Unavailable actions stay visible but disabled, including checkout for the current branch and its tracked remote branch.
- Cancel now stops a running merge, cherry-pick, revert or stash.
- Merges and other history operations now show what they are doing, with a spinner and Cancel, over their own repository only. Your other tabs stay usable meanwhile.
- After a merge, cherry-pick, revert, rebase or pull, History selects the new commit.
- Clicking a commit that is already visible, or one of its branch labels, no longer scrolls it to the top.
- Absolute commit dates in History are no longer cut off.
- Tabs now drag like in a web browser: the other tabs make room as you drag, and you can drag a whole tab group by its name.
- Drag a tab into a group or out of it; the coloured line under the group shows whether the tab will belong to it.
- Tab groups can show an icon: right-click the group and choose one under Icon.
- Branches in History now show their open pull request next to them, fetched as they scroll into view. Click the number to open the pull request.
- The Pull requests section in the sidebar lists your own open pull requests and those of the branches you have looked at. It starts collapsed.
- Branches also show their merged pull request, marked with a merge symbol, when they have no open one.
- Pull request links appear right away, also after restarting Northspline, and are refreshed in the background.
- Branch pull requests also work with Forgejo.
- Loading more pull requests no longer repeats the first page, and a finished load is no longer lost when another one starts.
- The toolbar shows a renamed tab's name, together with its group's name.

## [0.1.0-beta.25] - 2026-10-02

- History now keeps remote branches visually separate from your current commit until they join at their actual parent.
- If a pull fails because Git objects are missing locally, Northspline now offers to fetch the objects again. Check any changes left by the failed pull before retrying it.

## [0.1.0-beta.24] - 2026-10-02

- Northspline uses much less additional memory over time while it stays open and repositories keep changing.
- Reduced memory growth as new commits arrive in History on Linux. History content is temporarily unavailable to Linux screen readers while this workaround is in place.
- Repository tabs can be renamed: click the active tab again, or choose Rename tab… from its menu.
- Repository tabs can be grouped. Each group gets a name and a colour, and collapses to a single chip when you click it. Groups come back when you reopen Northspline.
- The commit description grows with the commit area: drag the divider above it to make room for longer messages, and double-click the divider to return.
- Dividers between panes now show where to drag when you point at them.
- When a commit's ancestry is highlighted in History, the other commits' text fades with their lines.
- A filter above the changed files narrows the Unstaged and Staged lists by path. Staging, unstaging or discarding everything then acts only on the files you see.

## [0.1.0-beta.23] - 2026-09-30

- The History branch filter lists branches as a tree of local branches and remotes with folders, and search opens the folders that match.
- The sidebar marks branches that the History branch filter shows.
- The keyboard shortcut reference no longer shows the Insert key as a conflict; Insert adds an item in whichever sidebar section has focus.
- The Push button shows how many commits are waiting to be pushed, like the Pull button shows how many can be pulled.

## [0.1.0-beta.22] - 2026-09-30

- Hosting connections that use the GitHub CLI or GitHub Enterprise are now saved. They used to show an error, stay listed until you quit, and be gone after a restart.
- In Changes, the diff of the highlighted file no longer goes blank after you choose Changes again, and a file without line changes says so.
- A repository without local changes opens on History.
- The Tags section of the sidebar starts collapsed and shows its count.
- The add button of a sidebar section and the stage button of a file only appear on hover or keyboard focus; they no longer stay after a click.
- Settings can be opened from the welcome screen.
- Northspline fetches your open repositories in the background every 10 minutes. You can switch this off, change the interval, or decide per repository under Settings → Git. A background fetch never asks for a password.

## [0.1.0-beta.21] - 2026-09-30

- Large repositories respond faster after a pull, fetch, checkout, commit or staging: Northspline now rescans the repository once instead of twice, and History updates about a second earlier in a repository of 63,000 files.
- The Logbook no longer fills with failed "Refresh repository" entries in large repositories, and an operation that finished is no longer reported as needing attention only because the following refresh took long.
- The warning that repository changes "arrived faster than they could be displayed" no longer appears after Northspline's own pull or checkout.
- A running fetch, pull or push now shows what it is doing and how far it is, for example "Pull · Updating files 85%". Downloads of Git LFS files are shown as their own step.
- The Logbook lists your operations without the "Git operation" entries that every refresh added.
- When you pull with uncommitted changes, the Pull dialog now asks you to confirm before you can start, instead of failing after it closed.
- While a repository opens, the toolbar shows its branch instead of "Detached HEAD".
- Closing a repository tab during a running operation can no longer hang.
- After a pull, History scrolls to the new HEAD and selects it, so the commits you just pulled are in view.

## [0.1.0-beta.20] - 2026-09-30

- On Linux, right-click menus and toolbar menus such as the Pull and Push options now open.
- On Linux, Northspline now uses the title area like on macOS: the toolbar replaces the separate title bar and the window buttons sit at the right end of the toolbar.
- History no longer blanks to placeholder rows while a repository refreshes after a slow pull or fetch; the graph and the open commit stay visible and update when the new state is ready.
- Switching repositories now shows the details of the selected commit right away.
- Selecting a branch in the sidebar that the branch filter hides now shows it in History for as long as it stays selected.
- Selecting a tag or the newest stash in the sidebar also shows it in a filtered History.
- Repositories with a branch filter now show their last known History immediately when you switch to them or start the app.
- The toolbar has a Branch button next to Pull and Push.
- A new branch is checked out as soon as it is created, and your uncommitted changes come along. Clear "Check out the new branch" in the dialog to only create it.
- Undo no longer offers to remove a branch you are currently on.
- GitHub Enterprise Cloud accounts on a `ghe.com` address can now be connected.
- When a hosting connection fails, Northspline now says why, for example that the server could not be reached or does not know the address, instead of "unavailable".
- Repository tabs that are not selected are now separated by a thin line, so each one reads as a tab.
- A configured diff renderer that does not read its input no longer falls back to the built-in diff at random.

## [0.1.0-beta.19] - 2026-09-29

- The changes dot on a repository tab now sits right next to the repository name.
- The Integrations section in the sidebar shows the hosting account linked to the repository and your configured tools.

## [0.1.0-beta.18] - 2026-09-29

- Large repositories open much faster. Branches and the history graph appear while Northspline is still checking your working copy, and a copied repository is slow only the first time you open it.

## [0.1.0-beta.17] - 2026-09-29

- Fetch, pull, push and clone use the credentials from your Git configuration. If a remote works with `git` on the command line because a credential helper is set in `.gitconfig`, it now works in Northspline too.
- Commit and push now pushes exactly like Push: after the commit you get the same push dialog, and sign-in or host-key questions work the same way.
- Filtering the graph to a branch also shows the remote branch it tracks. You can remove that one from the filter again.
- The main branch comes first in the sidebar and in the graph filter.
- The sidebar's scrollbar appears only while the pointer is over the sidebar or while you scroll.

## [0.1.0-beta.16] - 2026-09-29

- Git LFS works again when you start Northspline from Finder or the Dock. Git could not find `git-lfs` there, so refreshing a repository failed.
- Every diff has a Create patch button. It writes what you see: the commit or comparison in History, only the open file when you opened one, or the changes of the file in Changes.
- You can return from one file to the diff of all files: choose All changes at the top of the file list, or the back arrow in front of the file name.
- Context menus are grouped and have icons. With several commits or files selected, the menu says which entries act on the selection and which on the one you clicked.

## [0.1.0-beta.15] - 2026-09-29

- Northspline can now update itself. On macOS it looks for new versions in the background and installs one after you confirm. On Linux and Windows, check under Settings > Updates and open the downloads page from there. You can choose between stable and beta releases.
- Resolving conflicts is easier to follow. A conflicted file opens on its first conflict, and the sources and the result scroll together, so the conflict you look at is at the same height on both sides.
- Previous conflict and Next conflict (F8 and Shift+F8) step through every conflict and continue in the next file.
- History opens with a commit selected: the one you had selected before, or the current branch's latest commit.
- Connected repositories now load pull requests automatically when opened, without first opening the Integrations panel.
- Fixed history graph lines stopping abruptly when their connected commits are farther down the history.
- Branch and tag clicks now keep the target commit in view on the first click. Tabs keep their close button on the right and update their background when an icon changes. Use arrow keys and Enter in the command palette. Staging retries once after harmless filesystem drift and shows a subtle error if it still fails.
- Filter History by branch. Open Branches in the History toolbar to show only one branch or pick several, with search for repositories that have thousands of branches. You can also right-click a branch in the sidebar or in the graph. Each repository remembers its filter.
- Large repositories stay smooth: scrolling, hovering and selecting no longer stutter when a repository has thousands of branches.
- Reopening a repository shows its branches, changes and history at once while Northspline refreshes them in the background.
- Branch and tag markers in History fit their names, and long names keep their beginning and end.
- Branch folders and remotes in the sidebar start collapsed. The folder with your current branch stays open.
- Selecting another commit no longer breaks the diff's pinned hunk header for a moment.
- Keep scrolling and interaction responsive after large repositories finish loading their branches and tags.
- Large repositories open History much sooner and no longer fail when merges extend beyond the first page. Repeated status scans are faster, and a slow ignore scan no longer incorrectly reports that automatic updates are unavailable.

## [0.1.0-beta.14] - 2026-09-28

- Staging a visible file moves it into the other list; staging several files brings them in together. Discarded rows leave smoothly.
- The current branch, Logbook, rebase editor and conflict completion now give clearer motion cues. Logbook entries and output open and close smoothly.
- Clicking the Compass opens the command palette from the pill. Status messages and the repository drop prompt animate, and the diff minimap now tracks scrolling and responds to clicks.
- Diff hunks can show more surrounding lines, and files in a committed diff can be collapsed or expanded.
- The Compass, toolbar, repository tabs and history graph now move with your work. Counts roll into place, the active tab glides, and the graph traces the selected commit's lane. After a commit, the Composer clears smoothly and shows success; its new node lands when you open History. Reduced motion remains available.
- The stage and discard buttons on a selected file are visible again.
- The commit message area opens at its full height without a scrollbar, and its focus outline is no longer cut off.
- Long diff lines scroll sideways when line wrapping is off, with a horizontal scrollbar; line numbers and hunk buttons stay visible.
- Diffs in History and Changes can be selected line by line. Copy the selection as text or as a patch from the right-click menu or with Cmd/Ctrl+C. In Changes the same menu stages, unstages or discards the selected lines.
- Diff text can now be selected like in an editor: drag across it, double-click a word or triple-click a line. The lines you touch are framed, and Stage, Unstage or Discard Changes… buttons on the frame act on just those lines. Copy takes exactly the text you selected.
- History now always sits above the commit details.
- New Edit branch dialog: rename a branch and choose or remove the remote branch it tracks.
- Fetch, pull and push no longer keep a dialog open while they run; follow and cancel them in the operation center. Their dialogs are tidier and clearer.
- Northspline shows its logo while it starts.
- Right-click a repository tab to open its folder in Finder (or your file manager), give it an icon, or close it. A middle click closes a tab too.
- Give each repository tab an icon and colour, or your own image, so you can spot it at a glance.
- Right-click a worktree in the sidebar to open it, show it in Finder (or your file manager) or delete it.
- When a Git command such as a checkout fails, you now see Git's actual message, for example that the branch is already checked out in another worktree.
- Dragging a repository tab no longer shows a strange box behind it.
- The shortcut keys shown in the Compass are no longer cut off.

## [0.1.0-beta.13] - 2026-09-26

- Search and filter fields now have a clear button inside the field.

## [0.1.0-beta.12] - 2026-09-26

- Changed images now appear directly in the diff for staged, unstaged and committed changes, with side-by-side, swipe and onion-skin views.
- Northspline links now show a new branded feature graphic that matches the website, with no app screenshot.
- Northspline now uses the shared Meridian design system. The Compass and repository tabs fit their content, dialogs have room again, diff actions keep their full labels, and menus stay native to your operating system.
- Northspline’s new Meridian design brings a clearer island layout, Compass and Logbook, a smoother history graph and consistent controls across light and dark themes.
- Welcome, Settings and repository tools now share a more consistent Meridian layout. In conflicts, you can click a Current or Incoming source line, or use the per-region buttons, to build the result without typing; selected actions clearly say how to remove a choice. The separate inspection window can switch between Blame and Path history with a clear Close action. Transfer, stash and patch dialogs show actions and progress more clearly. Power Tools search can match case and search either all references or the current branch.
- The Logbook now opens under the repository Compass with clearer operation history and details. Activity uses the same timeline, and repository warnings and conflicts appear inside the workspace with actions where available.
- Changes now groups staged and unstaged files above the commit Composer. File actions appear on hover, long paths keep their file names visible, and the Composer shows a subject counter, staged count, commit destination and clearer failure recovery.
- Commit details and diffs now follow Meridian spacing and colours. Changed files, code gutters, selected lines, hunk actions and image comparison are easier to scan.
- History now follows Meridian’s graph and row design. Branch labels, selection, commit metadata, loading states and upstream updates are clearer in both themes.
- The sidebar now follows Meridian’s spacing and typography, with clearer current and selected branches and readable ahead/behind indicators.
- The repository Compass, tabs and workspace now follow Meridian’s desktop layout. Changes stays reachable in smaller windows, and toolbar actions line up consistently in light and dark themes.
- Repository actions, dialogs and settings now use the same Meridian buttons, fields and choices as the rest of the app. Image comparison has a keyboard accessible range control.
- Dialogs, the command palette and notices now use Meridian styling. The component gallery covers the complete design catalog, and lists respond to focused work areas.
- Forms and reference pickers now use Meridian fields and selection controls, with clearer focus, errors and search results.
- Buttons, toolbar actions, status marks and progress indicators now follow Meridian styling in light and dark themes.
- Lucide icons now appear consistently in menus, settings, Git references and hosting status.
- Northspline now uses Meridian colours and typography in both themes, with updated row spacing, tooltips and scrollbars.
- Windows command forwarding now recovers when a brief connection closes during app startup.
- Windows forwarded commands now receive their result reliably when the app finishes handling them.
- Deleting a branch can also delete its upstream on the remote. Northspline only deletes it if nobody has pushed to it since your last fetch.
- Fetch, pull and push dialogs are more compact, and the delete-branch options line up with the rest of the dialog.
- Shortcut hints stay out of the way until you hold ⌘ (Ctrl on Windows and Linux), and always use key symbols.
- Clicking a toolbar command such as Fetch no longer takes keyboard focus away from where you were working.
- Stashes appear correctly in the history graph.
- The website has a new look that matches the app.

## [0.1.0-beta.11] - 2026-09-24

- Windows release qualification now waits for the installed app to accept commands. A successful release run shows a separate publication job for Forgejo and the verified GitHub mirror.

## [0.1.0-beta.10] - 2026-09-24

- Adjusted Windows command forwarding for the installed-app release check.
- History no longer reloads the commit graph for file-only changes that leave its displayed summary unchanged.
- Large repositories can show status and load History while filesystem watching starts in the background.

## [0.1.0-beta.9] - 2026-09-24

- Press Cmd+A on Mac or Ctrl+A on Linux and Windows to select every file in the focused staged or unstaged list.
- The conflict editor now keeps both sides visible without a page-wide horizontal scrollbar. Aligned lines have continuous, lighter highlights, and the result is easier to read while you edit it.
- Commit messages stay in place until the commit succeeds, and Enter in the subject moves to the description. Create patches from selected commits or changed files. History keeps multiple selected commits through refresh and highlights the range between two selections; Cmd-click also visibly deselects a commit.
- Conflict resolution now keeps a draft open while you move between conflict blocks, combine sides, and edit the highlighted result. Click Resolve file to save the finished file.
- Conflicts from stashes and merges now open in Changes. Compare both sides, choose a whole file or individual conflict, edit the result, and review the proposed merge message before completing a merge.
- Right-click a branch or tag badge in History for the same actions available in the sidebar.
- History shows each stash as one graph entry by default. Use the merge expand action to inspect its underlying index commit.
- The Push toolbar button now includes its options arrow. Click Push for the usual flow, or the attached arrow for choices such as force push with lease.
- Browse tree now opens files as they existed in the selected commit. File history remains one click away.
- Tag deletion can include selected remotes. Destructive confirmations explain their effects and use a red action button, with Git commands in optional details.
- Hosting account setup now includes platform guidance, automatic Forgejo API addresses, and detected GitHub and GitLab CLI options. The setup form closes after authorization.
- Repositories using a custom SSH port can link to the matching hosting account. Open repository views update when accounts change.
- The selected Settings section remains readable in light and dark themes.

## [0.1.0-beta.8] - 2026-09-21

- Recover a non-publishing rehearsal from its verified runner retention before consulting remote release hosts.

## [0.1.0-beta.7] - 2026-09-21

- Wait for installed Windows settings readiness within a bounded timeout on slow runners instead of requiring persistence exactly five seconds after launch.

## [0.1.0-beta.6] - 2026-09-21

- Make installed Windows launch qualification compatible with Windows PowerShell 5.1 while preserving repository paths that contain spaces.

## [0.1.0-beta.5] - 2026-09-21

- Match Flutter 3.47.5's numeric macOS bundle-version transform, clean root-owned Podman stage output inside the container, and give installed Windows native qualification its slow-runner timeout budget.

## [0.1.0-beta.4] - 2026-09-21

- Qualify Apple prerelease bundles against their numeric bundle version, relabel CI Podman mounts when using the hardened wrapper, and fail Windows packaging on every native-command or missing-artifact error.

## [0.1.0-beta.3] - 2026-09-21

- Install both Apple Rust targets before the universal Flutter release build, then thin and qualify the signed arm64 package.

## [0.1.0-beta.2] - 2026-09-21

- Harden the protected release rehearsal across macOS, Fedora/Podman and Windows runners, align secret store attachment names, and remove a slow-runner authentication-test race.

## [0.1.0-beta.1] - 2026-09-21

- Restart Northspline as a Flutter/Rust port of QSpline.
- Add an empty localized desktop shell, native bridge and pinned devmil-git dependency.
- Add parity specifications, architecture, package tooling, initial branding and an unpublished website preview.
- Add the QSpline 2.1 light/dark palette, three density modes, bundled Lucide icons and JetBrains Mono.
- Add shared accessible desktop controls and a localized component gallery with keyboard, semantics and viewport coverage.
- Match the QSpline repository toolbar with explicit mode and repository context, exact 52/44 px shell geometry, and a localized compact overflow below 1100 px.
- Add typed repository sessions, atomic settings, crash recovery and bounded native activity history.
- Add localized open, initialize and clone workflows with native-path recents, process-tree cancellation and safe partial-destination handling.
- Add bounded SSH host-key verification, ephemeral credential retry and stalled-transfer cleanup for clone operations.
- Add persistent multi-repository tabs, responsive workspace panes, per-repository navigation and safe desktop window restoration.
- Add bounded live status and ref projection, shared-watcher refresh, repository-scoped overflow recovery and persistent repository conditions.
- Add an application-wide operation center, bounded Activity details, shared command navigation, stable sidebar actions and safe index-lock recovery.
- Make CI portable across Fedora, macOS and Windows runners, build Linux releases in the pinned Ubuntu 22.04 Podman baseline, bypass offline target runners during recovery and clean only owner-marked shared dependency checkouts.
- Add an 88-command registry with one-to-one executable coverage of all 72 QSpline commands, focused Changes/History/Diff/Conflict/Rebase/Sidebar routing, persistent shortcut overrides, explicit unbinding, reset and cross-platform conflict/reserved-key checks.
- Add a measured 100k-commit history path with exact G-LANE-01 projection, bounded native pages and a fixed-extent Flutter renderer.
- Add a measured 100k-row unified/split diff path with bounded bridge pages and byte-exact native partial-patch proofs.
- Add same-request progressive history completion with stable preview lanes and prioritized bounded metadata hydration.
- Add byte-safe commit trees, virtualized blame, rename/range history, anchored inspection navigation and stale-safe file restore previews.
- Add a paged production commit-diff surface with native line identities, unified/split layouts, context and whitespace controls, wrapping, search, hunk navigation, intraline/syntax styling, minimap and bounded image comparison.
- Add a durable, bounded recovery ledger with integrity-checked snapshots, sequential undo/redo, stale-state checks and explicit confirmation.
- Add previewed branch, tag, remote and reset commands with live ref rows, drift refusal, exact shared Git arguments and truthful recovery eligibility.
- Add byte-exact file, hunk, line, selected and all staging with partial untracked support, atomic index replacement, drift refusal and staged/unstaged workspace controls.
- Add an embedded commit editor with durable per-worktree drafts, templates, recent messages, amend and hook controls, exact drift refusal and distinct commit/push outcomes.
- Add irreversible tracked and partial discard plus untracked-only Clean with frozen scopes, exact drift refusal, explicit confirmation and no hidden recovery entries.
- Add exact patch export scopes, atomic overwrite-safe output, checked patch application, confined recovery snapshots and reversible multi-file apply.
- Add per-remote fetch, pull and push with policy-controlled pulls, exact force-with-lease protection, bounded authentication and cancellable reconciled progress.
- Add stable-identity stash workflows, selected and complete scopes, keep-index, authoritative graph decoration and explicit auto-stash checkout with retained failure recovery.
- Add previewed merge, ordered cherry-pick and revert workflows with isolated cancellable conflict prediction, publication warnings, sequencer truth and executable recovery.
