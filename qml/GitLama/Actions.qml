pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import QtQuick.Controls.Basic as C
import QtCore
import Meridian

// The window's dialogs: questions the core's workflows ask (prompts), and
// dialogs the UI opens itself.
Item {
    id: actionsRoot

    required property var window
    /// The shown conflict resolver, which takes the conflict commands.
    property var conflictResolver: null

    function answer(id, value) {
        Store.app.answerPrompt(id, value === undefined || value === null ? "" : JSON.stringify(value))
    }

    /// Shows the dialog a workflow asks for and answers it.
    function handlePrompt(id, kind, payloadText) {
        const payload = payloadText.length > 0 ? JSON.parse(payloadText) : ({})
        switch (kind) {
        case "chooseDirectory":
            folderDialog.ask(id)
            return
        case "initializeRepository":
            initializeDialog.ask(id, payload.initiallyBare === true)
            return
        case "confirmDiscard":
            discardConfirm.ask(id, payload)
            return
        case "confirmPublishedAmend":
            amendConfirm.promptId = id
            amendConfirm.open()
            return
        case "confirmSkipHooks":
            skipHooksDialog.ask(id)
            return
        case "chooseTransfer":
            transferDialog.ask(id, payload)
            return
        case "trustHostKey":
            hostKeyDialog.ask(id, payload)
            return
        case "gitCredentials":
            credentialDialog.ask(id, payload)
            return
        case "transferFailure":
            transferFailureDialog.ask(id, payload)
            return
        case "chooseRefMutation":
            refDialog.ask(id, payload)
            return
        case "confirmRefMutation":
            refConfirm.ask(id, payload)
            return
        case "editBranch":
            editBranchDialog.ask(id, payload)
            return
        case "recoverRefTarget":
            recoverTarget.promptId = id
            recoverTarget.open()
            return
        case "chooseStash":
            stashDialog.ask(id, payload)
            return
        case "confirmRestore":
            restoreConfirm.ask(id, payload)
            return
        case "confirmWorktreeDelete":
            worktreeDeleteConfirm.promptId = id
            worktreeDeleteConfirm.path = payload.path ?? ""
            worktreeDeleteConfirm.open()
            return
        case "confirmSnapshotRestore":
            snapshotRestore.ask(id, payload)
            return
        case "chooseSnapshotBranch":
            snapshotBranch.promptId = id
            snapshotBranch.branches = payload.branches ?? []
            snapshotBranchField.text = ""
            snapshotBranch.open()
            snapshotBranchField.forceActiveFocus()
            return
        case "lfsPointer":
            lfsPointer.promptId = id
            lfsPointer.pointer = payload
            lfsPointer.open()
            return
        case "confirmRenderer":
        case "confirmRendererSave":
            rendererConfirm.ask(id, payload)
            return
        case "confirmIndexLock":
            indexLockConfirm.promptId = id
            indexLockConfirm.sizeBytes = payload.sizeBytes ?? 0
            indexLockConfirm.open()
            return
        case "confirmBisect":
            bisectConfirm.promptId = id
            bisectConfirm.action = payload.action ?? "start"
            bisectConfirm.command = payload.command ?? ""
            bisectConfirm.open()
            return
        case "confirmSnapshotDelete":
            snapshotDelete.promptId = id
            snapshotDelete.name = payload.name ?? ""
            snapshotDelete.open()
            return
        case "ignorePath":
            ignoreDialog.ask(id, payload)
            return
        case "confirmIntegration":
            integrationConfirm.promptId = id
            integrationConfirm.commands = payload.commands ?? []
            integrationConfirm.summary = payload.summary ?? "integrationRunSummary"
            integrationConfirm.open()
            return
        case "confirmStash":
            stashConfirm.ask(id, payload)
            return
        case "chooseHistoryMutation":
            historyMutationDialog.ask(id, payload)
            return
        case "confirmHistoryMutation":
            historyMutationPreview.ask(id, payload)
            return
        case "chooseBranchIntegration":
            branchIntegration.ask(id, payload)
            return
        case "chooseRebaseTarget":
            rebaseTarget.ask(id, payload)
            return
        case "editRebase":
            rebaseEditor.ask(id, payload)
            return
        case "confirmRebase":
            rebasePreview.ask(id, payload)
            return
        case "chooseRestackRoot":
            restackRoot.ask(id, payload)
            return
        case "reviewRestack":
            restackPreview.ask(id, payload)
            return
        case "chooseCloneSource":
            cloneSourceDialog.ask(id)
            return
        case "confirmSequencer": {
            const abort = payload.action === "abort"
            sequencerConfirm.promptId = id
            sequencerConfirm.title = L10n.t(abort ? "conflictAbortTitle" : "conflictSkipTitle")
            sequencerConfirm.description = L10n.t(abort ? "conflictAbortMessage" : "conflictSkipMessage")
            sequencerConfirm.confirmLabel = L10n.t(abort ? "conflictAbort" : "conflictSkip")
            sequencerConfirm.open()
            return
        }
        case "confirmCommitCheckout":
            commitCheckout.ask(id, payload)
            return
        case "offerRefetch":
            refetchConfirm.promptId = id
            refetchConfirm.description = L10n.tn("transferMissingObjectDetail", { remote: payload.remote ?? "" })
            refetchConfirm.open()
            return
        default:
            answer(id, null)
        }
    }

    function showSettings(category) { settingsDialog.show(category ?? "appearance") }
    /// Reviews a pull request (the review workspace); until it is ported,
    /// its page opens in the browser.
    function showPullRequestReview(pull) {
        if (pull && Store.hosting.openable(pull.webUrl))
            Qt.openUrlExternally(pull.webUrl)
    }
    function showLicenses() {
        licenseDialog.packages = Store.settings.licenses()
        licenseDialog.open()
    }
    function showAbout() { aboutDialog.open() }
    /// A Refresh began (the toolbar spins if it lasts).
    signal refreshStarted()
    /// Find (the Dart _findInRepository): the focused diff's find field,
    /// else the Changes diff's, else the history search.
    function findInRepository() {
        const working = Store.workingDiffPane
        const commit = Store.inspectorView
        for (const pane of [working && working.diffFocused ? working : null,
                            commit && commit.diffFocused ? commit : null,
                            Store.workspace && Store.workspace.active && Store.workspace.active.pane === "changes" ? working : null]) {
            if (pane && pane.focusFind())
                return
        }
        Store.sidebar.selectPane("history")
        Qt.callLater(() => { if (Store.historyPane) Store.historyPane.focusSearch() })
    }
    ShortcutReferenceDialog { id: shortcutReference }
    // Where a zip snapshot goes, then its progress (the Dart saveCommitArchive).
    FileDialog {
        id: archiveDestination
        property string commit
        property string prefix
        fileMode: FileDialog.SaveFile
        nameFilters: ["*.zip"]
        defaultSuffix: "zip"
        onAccepted: {
            const url = selectedFile.toString()
            Store.workflows.saveCommitArchive(commit, prefix,
                url.startsWith("file://") ? decodeURIComponent(url.slice(Qt.platform.os === "windows" ? 8 : 7)) : url)
        }
    }
    MeridianDialog {
        id: archiveProgress
        readonly property var archive: Store.workflows ? (Store.workflows.archive ?? ({})) : ({})
        readonly property bool running: archive.running === true
        property bool canceled: false
        onRunningChanged: {
            if (running) {
                canceled = false
                open()
            } else {
                close()
            }
        }
        closePolicy: C.Popup.NoAutoClose
        title: L10n.t("archiveProgressTitle")
        Column {
            width: parent ? parent.width : 0
            spacing: Theme.space.s4
            MeridianProgressBar {
                width: parent.width
                track: true
                persistent: true
                value: archiveProgress.archive.started === true && archiveProgress.archive.writing !== true && (archiveProgress.archive.total ?? 0) > 0
                    ? Math.min(1, archiveProgress.archive.files / archiveProgress.archive.total) : -1
            }
            MeridianText {
                objectName: "commit-archive-progress"
                width: parent.width
                color: Theme.colors.inkMuted
                text: archiveProgress.archive.started !== true ? L10n.t("archiveProgressPreparing")
                    : archiveProgress.archive.writing === true ? L10n.t("archiveProgressWriting")
                    : L10n.tn("archiveProgressFiles", { files: archiveProgress.archive.files ?? 0, total: archiveProgress.archive.total ?? 0 })
            }
        }
        actions: [
            MeridianButton {
                objectName: "commit-archive-cancel"
                text: L10n.t("cancel")
                variant: MeridianButton.Quiet
                enabled: !archiveProgress.canceled
                onClicked: { archiveProgress.canceled = true; Store.workflows.cancelCommitArchive() }
            }
        ]
    }
    AboutDialog { id: aboutDialog; onOpenLicenses: actionsRoot.showLicenses() }
    /// Opens the patch dialog in `mode` for what the active pane shows: the
    /// Changes selection, else History's (or `commit`).
    function showPatchWorkflow(mode, commit) {
        const active = Store.workspace ? Store.workspace.active : null
        if (active && active.pane === "changes")
            patchDialog.show({ kind: "selection" }, mode)
        else
            patchDialog.show({ kind: "history", commit: commit ?? "" }, mode)
    }
    /// Opens the patch dialog for `source` ({kind, ...}; see PatchDialog).
    function showPatchDialog(source, mode) { patchDialog.show(source, mode) }
    PatchDialog { id: patchDialog }
    /// Opens "Select changed lines" for the Changes file `key` on `side`.
    function showLineSelection(side, key) { lineSelectionDialog.show(side, key) }
    LineSelectionDialog { id: lineSelectionDialog }

    /// Opens the local folder `path` itself in the file manager.
    function openFolder(path) { Store.workflows.openFolder(path) }
    function deleteWorktree(index, name) { Store.workflows.deleteWorktree(index) }
    function findWell(item) {
        if (!item)
            return null
        if (item.objectName === "meridian-color-custom")
            return item
        for (const child of item.children) {
            const found = findWell(child)
            if (found)
                return found
        }
        return null
    }
    function showRepositoryIconDialog(tab) { repositoryIconDialog.show(tab) }
    function showTabGroupDialog(group, labels) { tabGroupDialog.show(group, labels) }
    RepositoryIconDialog { id: repositoryIconDialog }
    TabGroupDialog { id: tabGroupDialog }

    /// Copies `text` and confirms it with `message` in the status bar.
    function copyText(text, message) {
        clipboard.text = text
        clipboard.selectAll()
        clipboard.copy()
        clipboard.text = ""
        Notifications.show(message, false)
    }
    TextEdit { id: clipboard; visible: false }

    /// Runs command `id` when the shared policy allows it now, and
    /// otherwise says why (the Flutter shell's _executeCommand).
    function runCommand(id, options) {
        const reason = Commands.reason(id, actionsRoot.availability)
        if (reason.length > 0) {
            Notifications.show(Commands.reasonText(reason), false)
            return
        }
        switch (id) {
        case "openRepository": Store.workspace.openRepository(); return
        case "initializeRepository": Store.workspace.initializeRepository(false); return
        case "closeRepositoryTab": Store.workspace.closeTab(Store.workspace.activeTabId); return
        case "showSettings": showSettings(); return
        case "cloneRepository": cloneRepository(); return
        case "showLicenses": showLicenses(); return
        case "showShortcutReference": shortcutReference.show(); return
        case "showSnapshots": if (Store.shell) Store.shell.togglePanel("snapshots"); return
        case "diffRenderConfigured": Store.settings.diffRenderer("render", ({})); return
        case "showIntegrations": if (Store.shell) Store.shell.togglePanel("integrations"); return
        case "hostingCreatePullRequest": {
            const url = Store.hosting ? Store.hosting.resourceLink("createChangeRequest", 0) : ""
            if (url.length > 0 && Store.hosting.openable(url))
                Qt.openUrlExternally(url)
            else
                Notifications.show(Commands.reasonText("contextRequired"), false)
            return
        }
        case "showPowerTools": if (Store.shell) Store.shell.togglePanel("powerTools"); return
        case "addIntegration": showSettings("customCommands"); return
        case "addWorktree": if (Store.shell) Store.shell.togglePanel("extensions"); return
        case "trackLfsPattern": if (Store.shell) Store.shell.showExtensions(true); return
        case "showRepositoryDetails": if (Store.shell) Store.shell.showRepositoryDetails(); return
        case "saveCommitArchive": {
            const selected = (Store.history.state.selectedIds ?? []).filter(id => id !== "wip")
            const commit = options.initialTarget ?? (selected.length === 1 ? selected[0] : "")
            const active = Store.workspace ? Store.workspace.active : null
            if (commit.length === 0 || !active)
                return
            archiveDestination.commit = commit
            archiveDestination.prefix = Store.workflows.archiveName(active.label ?? "", commit)
            archiveDestination.currentFile = "file://" + StandardPaths.writableLocation(StandardPaths.DownloadLocation).toString().replace("file://", "")
                + "/" + archiveDestination.prefix + ".zip"
            archiveDestination.open()
            return
        }
        case "showCommandPalette": commandPalette.show(); return
        case "fetch":
        case "remoteFetch":
            Store.workflows.transfer("fetch", { initialRemote: options.initialName ?? null }); return
        case "pull":
            Store.workflows.transfer("pull", { initialRemote: options.initialName ?? null }); return
        case "push":
        case "remotePush":
            Store.workflows.transfer("push", { initialRemote: options.initialName ?? null, initialForce: options.force === true }); return
        case "createBranch":
        case "deleteBranch":
        case "createTag":
        case "deleteTag":
        case "addRemote":
        case "editRemote":
        case "renameRemote":
        case "removeRemote":
            Store.workflows.reference(id, { initialName: options.initialName ?? null, initialTarget: options.initialTarget ?? null }); return
        case "resetBranch":
            Store.workflows.reference("reset", { initialTarget: options.initialTarget ?? null }); return
        case "checkoutCommit": {
            const selected = (Store.history.state.selectedIds ?? []).filter(id => id !== "wip")
            Store.workflows.checkoutCommit(options.initialTarget ?? (selected.length === 1 ? selected[0] : "")); return
        }
        case "createStash": Store.workflows.stash("push", ({})); return
        case "applyStash": Store.workflows.stash("apply", { selector: options.initialName ?? "" }); return
        case "popStash": Store.workflows.stash("pop", { selector: options.initialName ?? "" }); return
        case "dropStash": Store.workflows.stash("drop", { selector: options.initialName ?? "" }); return
        case "renameStash": Store.workflows.stash("rename", { selector: options.initialName ?? "" }); return
        case "autoStashCheckout": Store.workflows.stash("autoStashCheckout", { targetBranch: options.initialName ?? "" }); return
        case "mergeBranch":
            Store.workflows.mutateHistory("merge", options.initialName ?? "", options.initialTarget ?? ""); return
        case "showOperations": if (Store.shell) Store.shell.toggleOperations(); return
        case "showActivity": if (Store.shell) Store.shell.activityVisible = !Store.shell.activityVisible; return
        case "activityCopy":
            if (Store.shell && Store.shell.activityVisible && Store.shell.activityIsland)
                Store.shell.activityIsland.copySelected()
            return
        case "activityRetry": Store.operations.runLatest(true); return
        case "activityCancel": Store.operations.runLatest(false); return
        case "rebaseContinue": Store.conflicts.sequence("continue"); return
        case "rebaseAbort": Store.conflicts.sequence("abort"); return
        case "conflictNext": case "conflictPrevious": case "conflictTakeCurrent": case "conflictTakeIncoming":
        case "conflictTakeBoth":
            if (actionsRoot.conflictResolver && actionsRoot.conflictResolver.runCommand(id))
                return
            Notifications.show(Commands.reasonText("contextRequired"), false)
            return
        case "integrateBranch":
            Store.workflows.integrateBranch(options.initialName ?? "", options.initialTarget ?? ""); return
        case "rebaseBranch":
            Store.workflows.rebase(options.initialTarget ?? ""); return
        case "interactiveRebase":
            Store.workflows.rebase(""); return
        case "restackBranches":
            Store.workflows.restack(options.initialName ?? ""); return
        case "cherryPickSelected":
            Store.workflows.mutateHistory("cherryPick", "", options.initialTarget ?? ""); return
        case "revertSelected":
            Store.workflows.mutateHistory("revert", "", options.initialTarget ?? ""); return
        case "renameBranch":
            Store.workflows.editBranch(options.initialName ?? ""); return
        case "checkoutBranch":
            Store.workflows.checkout(options.initialName ?? "", options.initialReference ?? ""); return
        case "deleteRemoteBranch":
            Store.workflows.deleteRemoteBranch(options.initialReference ?? ""); return
        case "pushTag":
            Store.workflows.transfer("pushTag", { initialBranch: options.initialName ?? null }); return
        case "find": findInRepository(); return
        case "reportIssue":
            if (!Qt.openUrlExternally("https://github.com/devmil/gitlama/issues"))
                Notifications.show(L10n.t("reportIssueOpenFailed"), true)
            return
        case "inspectIndexLock": Store.workflows.inspectIndexLock(); return
        case "showChanges": Store.sidebar.selectPane("changes"); return
        case "showHistory": Store.sidebar.selectPane("history"); return
        case "nextPane": Store.sidebar.nextPane(); return
        case "stageToggle": Store.changes.toggleFocused(); return
        case "stageSelection": Store.changes.stageSelection("unstaged"); return
        case "unstageSelection": Store.changes.stageSelection("staged"); return
        case "discardChanges": Store.changes.discardSelection(); return
        case "inspectorLensDiff": Store.inspector.selectLens("diff"); return
        case "inspectorLensContents": Store.inspector.selectLens("contents"); return
        case "inspectorLensBlame": case "historyBlame": Store.inspector.selectLens("blame"); return
        case "inspectorLensHistory": case "historyPathHistory": Store.inspector.selectLens("history"); return
        case "inspectorUp": Store.inspector.up(); return
        case "inspectorBack": Store.inspector.back(); return
        case "inspectorForward": Store.inspector.forward(); return
        case "refreshRepository": refreshStarted(); Store.workspace.refresh(); return
        case "createPatch": showPatchWorkflow("create", options.initialTarget ?? ""); return
        case "applyPatch": showPatchWorkflow("apply", ""); return
        case "openInEditor": Store.workflows.openTool("editor", ""); return
        case "openInTerminal": Store.workflows.openTool("terminal", ""); return
        case "openInFileManager": Store.workflows.openTool("fileManager", ""); return
        default:
            Notifications.show(Commands.label(id), false)
        }
    }

    /// The state the command policy reads (the Flutter CommandMenuState):
    /// busy, selections, the inspector and the diffs on screen.
    readonly property var availability: {
        const changes = Store.changes ? (Store.changes.state ?? ({})) : ({})
        const history = Store.history ? (Store.history.state ?? ({})) : ({})
        const inspector = Store.inspector ? (Store.inspector.state ?? ({})) : ({})
        const active = Store.workspace ? Store.workspace.active : null
        const pane = active ? active.pane : ""
        const location = inspector.location ?? null
        return {
            busy: changes.blocked === true,
            canQueueStaging: changes.canQueue === true,
            selectedCommits: history.selectedIds ?? [],
            mergeCommits: [],
            disabledSelections: changes.disabled ?? ["stageToggle", "stageSelection", "unstageSelection", "discardChanges"],
            hasHistoryPath: location !== null && !!location.path,
            inspectorCanBack: inspector.canBack === true,
            inspectorCanForward: inspector.canForward === true,
            inspectorShown: location !== null,
            canBrowseAllFiles: location !== null && location.kind === "commit" && location.scope !== "all",
            hasDiff: (pane === "changes" && changes.detail && changes.detail.hasDiff === true)
                || (pane === "history" && inspector.hasDiff === true),
            hasActivity: false,
            canRetryActivity: false,
            canCancelActivity: false,
            remote: null,
        }
    }
    function openRemoteRepository() {}
    function cloneRepository() { Store.workspace.cloneRepository() }
    function openRecent(recent) {
        if (recent.remote)
            return
        Store.workspace.openRecent(recent.index)
    }

    FolderDialog {
        id: folderDialog
        property int promptId: -1
        function ask(id) {
            promptId = id
            open()
        }
        onAccepted: {
            const url = selectedFolder.toString()
            const path = url.startsWith("file://") ? decodeURIComponent(url.slice(Qt.platform.os === "windows" ? 8 : 7)) : url
            actionsRoot.answer(promptId, path)
            promptId = -1
        }
        onRejected: {
            if (promptId < 0)
                return
            actionsRoot.answer(promptId, null)
            promptId = -1
        }
    }

    // Discard and Clean review what they remove permanently.
    MeridianConfirm {
        id: discardConfirm
        property int promptId: -1
        property bool clean: false
        function ask(id, review) {
            promptId = id
            clean = (review.trackedFiles ?? 0) === 0
            const mixed = (review.trackedFiles ?? 0) > 0 && (review.untrackedFiles ?? 0) > 0
            title = clean ? L10n.t("cleanConfirmTitle") : L10n.t("discardConfirmTitle")
            description = mixed
                ? L10n.tn("discardMixedConfirmMessage", { tracked: review.trackedFiles, untracked: review.untrackedFiles })
                : L10n.tn("discardConfirmMessage", { count: (review.trackedFiles ?? 0) + (review.untrackedFiles ?? 0) })
            open()
        }
        confirmLabel: clean ? L10n.t("cleanConfirmAction") : L10n.t("discardConfirmAction")
        cancelLabel: L10n.t("cancel")
        destructive: true
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
    }

    // Amending a commit others may have.
    MeridianConfirm {
        id: amendConfirm
        property int promptId: -1
        title: L10n.t("commitConfirmAmend")
        description: L10n.t("commitPublishedWarning")
        confirmLabel: L10n.t("commitConfirmAmend")
        cancelLabel: L10n.t("cancel")
        destructive: true
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
    }

    // Skipping hooks asks for SKIP to be typed.
    MeridianDialog {
        id: skipHooksDialog
        property int promptId: -1
        function ask(id) {
            promptId = id
            skipField.text = ""
            open()
            skipField.forceActiveFocus()
        }
        readonly property bool confirmed: skipField.text.trim().toUpperCase() === "SKIP"
        title: L10n.t("commitSkipHooksConfirmTitle")
        description: L10n.t("commitSkipHooksConfirmBody")
        submitDisabled: !confirmed
        onSubmitted: { if (confirmed) { close(); actionsRoot.answer(promptId, true); promptId = -1 } }
        onRejected: { actionsRoot.answer(promptId, false); promptId = -1 }
        MeridianTextField {
            id: skipField
            width: parent ? parent.width : 0
            Accessible.name: L10n.t("commitSkipHooksConfirmInput")
            placeholderText: L10n.t("commitSkipHooksConfirmInput")
        }
        actions: [
            MeridianButton {
                text: L10n.t("cancel")
                variant: MeridianButton.Quiet
                onClicked: skipHooksDialog.reject()
            },
            MeridianButton {
                text: L10n.t("commitSkipHooks")
                variant: MeridianButton.Danger
                enabled: skipHooksDialog.confirmed
                onClicked: skipHooksDialog.submitted()
            }
        ]
    }

    StashDialog {
        id: stashDialog
        onAnswered: (id, request) => actionsRoot.answer(id, request)
    }
    StashConfirmDialog {
        id: stashConfirm
        onAnswered: (id, confirmed) => actionsRoot.answer(id, confirmed)
    }
    HistoryMutationDialog {
        id: historyMutationDialog
        onAnswered: (id, request) => actionsRoot.answer(id, request)
    }
    HistoryMutationPreviewDialog {
        id: historyMutationPreview
        onAnswered: (id, confirmed) => actionsRoot.answer(id, confirmed)
    }
    BranchIntegrationDialog {
        id: branchIntegration
        onAnswered: (id, choice) => actionsRoot.answer(id, choice)
    }
    RebaseTargetDialog {
        id: rebaseTarget
        onAnswered: (id, branch) => actionsRoot.answer(id, branch)
    }
    RebaseEditorDialog {
        id: rebaseEditor
        onAnswered: (id, edit) => actionsRoot.answer(id, edit)
    }
    RebasePreviewDialog {
        id: rebasePreview
        onAnswered: (id, confirmed) => actionsRoot.answer(id, confirmed)
    }
    RestackRootDialog {
        id: restackRoot
        onAnswered: (id, branch) => actionsRoot.answer(id, branch)
    }
    RestackPreviewDialog {
        id: restackPreview
        onAnswered: (id, acknowledge) => actionsRoot.answer(id, acknowledge)
    }
    MeridianDialog {
        id: cloneSourceDialog
        property int promptId: -1
        function ask(id) {
            promptId = id
            cloneSource.text = ""
            open()
            cloneSource.forceActiveFocus()
        }
        function choose() {
            if (cloneSource.text.trim().length === 0)
                return
            close()
            actionsRoot.answer(promptId, cloneSource.text.trim())
            promptId = -1
        }
        widthClass: MeridianDialog.Form
        title: L10n.t("cloneRepository")
        description: L10n.t("cloneSourceDescription")
        submitDisabled: cloneSource.text.trim().length === 0
        onSubmitted: choose()
        onRejected: { actionsRoot.answer(promptId, null); promptId = -1 }
        Column {
            width: parent ? parent.width : 0
            spacing: Theme.space.s2
            MeridianText { width: parent.width; role: MeridianText.Label; text: L10n.t("cloneSourceLabel") }
            MeridianTextField {
                id: cloneSource
                objectName: "clone-source"
                width: parent.width
                monospace: true
                placeholderText: L10n.t("cloneSourceHint")
                Accessible.name: L10n.t("cloneSourceLabel")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
            }
        }
        actions: [
            MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: cloneSourceDialog.reject() },
            MeridianButton {
                text: L10n.t("chooseCloneDestination")
                variant: MeridianButton.Primary
                enabled: cloneSource.text.trim().length > 0
                onClicked: cloneSourceDialog.choose()
            }
        ]
    }
    MeridianConfirm {
        id: sequencerConfirm
        property int promptId: -1
        cancelLabel: L10n.t("cancel")
        destructive: true
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
    }
    SettingsDialog {
        id: settingsDialog
        onLicensesRequested: actionsRoot.showLicenses()
    }
    MeridianLicenseDialog {
        id: licenseDialog
        title: L10n.t("licensesTitle")
        applicationName: L10n.t("appTitle")
        applicationVersion: Store.platform.version ?? ""
        applicationIcon: "qrc:/GitLama/brand/tile-64.png"
        closeLabel: L10n.t("close")
        backLabel: L10n.t("licensesBack")
        filterPlaceholder: L10n.t("licensesFilter")
        noMatchesLabel: L10n.t("licensesNoMatches")
        countText: count => L10n.tn("licensesCount", { count: count })
    }
    CommitCheckoutDialog {
        id: commitCheckout
        onAnswered: (id, choice) => actionsRoot.answer(id, choice)
    }
    CommandPalette {
        id: commandPalette
        onRun: id => actionsRoot.runCommand(id, ({}))
    }
    RefMutationDialog {
        id: refDialog
        onAnswered: (id, request) => actionsRoot.answer(id, request)
    }
    RefConfirmDialog {
        id: refConfirm
        onAnswered: (id, confirmed) => actionsRoot.answer(id, confirmed)
    }
    // Restoring a file to a commit's version (the Dart confirmRestore).
    MeridianConfirm {
        id: restoreConfirm
        property int promptId: -1
        property var payload: ({})
        function ask(id, value) {
            promptId = id
            payload = value
            open()
        }
        /// Two different sizes that round alike are shown exactly.
        readonly property bool exact: payload.current !== null && payload.current !== undefined
            && payload.current !== payload.source
            && Labels.byteSize(payload.current) === Labels.byteSize(payload.source ?? 0)
        function size(bytes) { return exact ? L10n.tn("byteCount", { count: bytes }) : Labels.byteSize(bytes) }
        title: L10n.t("historyRestoreFile")
        description: L10n.tn("historyRestorePreview", { path: payload.path ?? "" })
        confirmLabel: L10n.t("historyRestoreConfirm")
        cancelLabel: L10n.t("cancel")
        destructive: true
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
        MeridianPropertyList {
            width: parent ? parent.width : 0
            properties: [
                { label: L10n.t("historyRestoreSourceSize"), value: restoreConfirm.size(restoreConfirm.payload.source ?? 0), selectable: false },
                { label: L10n.t("historyRestoreCurrentSize"), selectable: false,
                    value: restoreConfirm.payload.current === null || restoreConfirm.payload.current === undefined
                        ? L10n.t("historyRestoreNoCurrentFile") : restoreConfirm.size(restoreConfirm.payload.current) },
            ]
        }
    }
    // Asks before a linked worktree and its files are removed (the Dart
    // confirmWorktreeDeletion).
    MeridianConfirm {
        id: worktreeDeleteConfirm
        property int promptId: -1
        property string path
        title: L10n.t("extensionWorktreeDeleteTitle")
        description: L10n.tn("extensionWorktreeDeleteBody", { path: path })
        confirmLabel: L10n.t("delete")
        cancelLabel: L10n.t("cancel")
        destructive: true
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
    }
    // Replacing the current changes with a snapshot's (the Dart
    // NamedSnapshotRestoreDialog).
    MeridianDialog {
        id: snapshotRestore
        property int promptId: -1
        property var payload: ({})
        property bool acknowledged: false
        function ask(id, value) {
            promptId = id
            payload = value
            acknowledged = false
            open()
        }
        function answer(value) {
            const pending = promptId
            promptId = -1
            close()
            actionsRoot.answer(pending, value)
        }
        title: L10n.tn("namedSnapshotRestoreTitle", { name: payload.name ?? "" })
        description: L10n.t("namedSnapshotRestoreSummary")
        submitDisabled: !acknowledged
        onSubmitted: answer(true)
        onRejected: { if (promptId >= 0) { actionsRoot.answer(promptId, false); promptId = -1 } }
        Column {
            width: parent ? parent.width : 0
            spacing: Theme.space.s6
            Column {
                visible: (snapshotRestore.payload.paths ?? []).length > 0
                width: parent.width
                spacing: Theme.space.s3
                ListWell {
                    width: parent.width
                    implicitHeight: Math.min(view.contentHeight, maxHeight)
                    model: snapshotRestore.payload.paths ?? []
                    header: Item {
                        width: parent ? parent.width : 0
                        height: restoreCount.implicitHeight + Theme.space.s4
                        MeridianText {
                            id: restoreCount
                            x: Theme.space.s6
                            y: Theme.space.s4
                            role: MeridianText.Caption
                            color: Theme.colors.inkMuted
                            text: L10n.tn("namedSnapshotRestoreFileCount", { count: (snapshotRestore.payload.paths ?? []).length })
                        }
                    }
                    delegate: FileRow {
                        required property string modelData
                        width: ListView.view ? ListView.view.width : 0
                        path: modelData
                        activeFocusOnTab: false
                        leading: Component { MeridianIcon { name: "file"; iconSize: MeridianIcon.Small; color: Theme.colors.inkMuted } }
                    }
                }
                MeridianText {
                    visible: snapshotRestore.payload.truncated === true
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: L10n.t("namedSnapshotPathsTruncated")
                }
            }
            MeridianText {
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                text: L10n.t("namedSnapshotRestoreStash")
            }
            MeridianCheckbox {
                text: L10n.t("namedSnapshotAcknowledgeReplacement")
                checked: snapshotRestore.acknowledged
                onToggled: snapshotRestore.acknowledged = checked
            }
        }
        actions: [
            MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: snapshotRestore.reject() },
            MeridianButton {
                text: L10n.t("namedSnapshotRestore")
                variant: MeridianButton.Danger
                enabled: snapshotRestore.acknowledged
                onClicked: snapshotRestore.answer(true)
            }
        ]
    }
    // A branch from a snapshot.
    MeridianDialog {
        id: snapshotBranch
        property int promptId: -1
        property var branches: []
        readonly property string name: snapshotBranchField.text.trim()
        function answer(value) {
            const pending = promptId
            promptId = -1
            close()
            actionsRoot.answer(pending, value)
        }
        widthClass: MeridianDialog.Form
        title: L10n.t("namedSnapshotBranchTitle")
        submitDisabled: name.length === 0
        onSubmitted: answer(name)
        onRejected: { if (promptId >= 0) { actionsRoot.answer(promptId, null); promptId = -1 } }
        ReferenceField {
            id: snapshotBranchField
            width: parent ? parent.width : 0
            label: L10n.t("refMutationName")
            names: snapshotBranch.branches
            normalize: true
            suggestSegments: true
        }
        actions: [
            MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: snapshotBranch.reject() },
            MeridianButton {
                text: L10n.t("namedSnapshotBranch")
                variant: MeridianButton.Primary
                enabled: snapshotBranch.name.length > 0
                onClicked: snapshotBranch.answer(snapshotBranch.name)
            }
        ]
    }
    MeridianConfirm {
        id: snapshotDelete
        property int promptId: -1
        property string name
        title: L10n.t("namedSnapshotDeleteTitle")
        description: L10n.tn("namedSnapshotDeleteMessage", { name: name })
        confirmLabel: L10n.t("delete")
        cancelLabel: L10n.t("cancel")
        destructive: true
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
    }
    IgnoreDialog {
        id: ignoreDialog
        onAnswered: (id, entry) => actionsRoot.answer(id, entry)
    }
    // Asks to run a configured tool that needs confirmation (the Dart
    // confirmIntegration).
    MeridianConfirm {
        id: integrationConfirm
        property int promptId: -1
        property var commands: []
        property string summary: "integrationRunSummary"
        widthClass: MeridianDialog.Form
        title: L10n.t("integrationPreviewTitle")
        confirmLabel: L10n.t("integrationRun")
        cancelLabel: L10n.t("cancel")
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
        Column {
            width: parent ? parent.width : 0
            spacing: Theme.space.s4
            MeridianText {
                width: parent.width
                role: MeridianText.Body
                wrapMode: Text.Wrap
                text: L10n.t(integrationConfirm.summary)
            }
            GitCommands {
                width: parent.width
                title: L10n.t("commandDetails")
                commands: integrationConfirm.commands
            }
        }
    }
    DiffRendererConfirm {
        id: rendererConfirm
        onAnswered: (id, value) => actionsRoot.answer(id, value)
    }
    // An LFS pointer's facts (lfsPointer).
    MeridianDialog {
        id: lfsPointer
        objectName: "lfs-pointer-dialog"
        property int promptId: -1
        property var pointer: ({})
        readonly property bool isPointer: pointer.oid !== null && pointer.oid !== undefined
        title: L10n.t("extensionLfsPointerTitle")
        description: isPointer ? L10n.t("extensionLfsPointerDescription") : L10n.t("extensionLfsNotPointer")
        closeLabel: L10n.t("close")
        onClosed: { if (promptId >= 0) actionsRoot.answer(promptId, true); promptId = -1 }
        MeridianPropertyList {
            objectName: "lfs-pointer-details"
            width: parent ? parent.width : 0
            properties: [{ label: L10n.t("extensionLfsPointerFile"), value: lfsPointer.pointer.path ?? "", monospace: true }].concat(
                lfsPointer.isPointer ? [
                    { label: L10n.t("extensionLfsPointerOid"), value: lfsPointer.pointer.oid, monospace: true },
                    { label: L10n.t("extensionLfsPointerSize"), value: Labels.byteSize(lfsPointer.pointer.size ?? 0), selectable: false },
                ] : [])
        }
    }
    // Author images from Gravatar: what enabling sends (the Dart GravatarOfferDialog).
    function offerGravatar() { gravatarOffer.open() }
    MeridianConfirm {
        id: gravatarOffer
        title: L10n.t("avatarGravatarTitle")
        description: L10n.t("avatarGravatarHint")
        confirmLabel: L10n.t("avatarEnableGravatar")
        cancelLabel: L10n.t("avatarGravatarNotNow")
        onConfirmed: Store.workflows.setGravatar(true)
    }
    // Removing Git's index lock (the Dart confirmIndexLockRemoval).
    MeridianConfirm {
        id: indexLockConfirm
        property int promptId: -1
        property real sizeBytes: 0
        title: L10n.t("indexLockConfirmationTitle")
        description: L10n.tn("indexLockConfirmation", { size: Labels.byteSize(sizeBytes) })
        confirmLabel: L10n.t("indexLockRemove")
        cancelLabel: L10n.t("cancel")
        destructive: true
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
    }

    // One bisect step with its Git command (confirmBisect).
    MeridianConfirm {
        id: bisectConfirm
        property int promptId: -1
        property string action: "start"
        property string command: ""
        readonly property string suffix: action.charAt(0).toUpperCase() + action.slice(1)
        widthClass: MeridianDialog.Form
        title: L10n.t("bisect" + suffix + "Title")
        confirmLabel: L10n.t(action === "good" ? "bisectConfirmGood" : action === "bad" ? "bisectConfirmBad" : "powerBisect" + suffix)
        cancelLabel: L10n.t("cancel")
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
        Column {
            width: parent ? parent.width : 0
            spacing: Theme.space.s4
            MeridianText {
                width: parent.width
                role: MeridianText.Body
                wrapMode: Text.Wrap
                text: L10n.t("bisect" + bisectConfirm.suffix + "Summary")
            }
            GitCommands {
                width: parent.width
                title: L10n.t("commandDetails")
                commands: [bisectConfirm.command]
            }
        }
    }
    EditBranchDialog {
        id: editBranchDialog
        onAnswered: (id, edit) => actionsRoot.answer(id, edit)
    }
    MeridianConfirm {
        id: recoverTarget
        property int promptId: -1
        title: L10n.t("refMutationTargetUnavailableTitle")
        description: L10n.t("refMutationTargetUnavailableDetail")
        confirmLabel: L10n.t("refMutationRefreshTarget")
        cancelLabel: L10n.t("cancel")
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
    }
    TransferDialog {
        id: transferDialog
        onAnswered: (id, request) => actionsRoot.answer(id, request)
    }
    HostKeyDialog {
        id: hostKeyDialog
        onAnswered: (id, trust) => actionsRoot.answer(id, trust)
    }
    CredentialDialog {
        id: credentialDialog
        onAnswered: (id, credentials) => actionsRoot.answer(id, credentials)
    }
    TransferFailureDialog {
        id: transferFailureDialog
        onAnswered: (id, remedy) => actionsRoot.answer(id, remedy)
    }
    MeridianConfirm {
        id: refetchConfirm
        property int promptId: -1
        title: L10n.t("transferMissingObjectTitle")
        confirmLabel: L10n.t("transferRefetchAction")
        cancelLabel: L10n.t("cancel")
        onConfirmed: { actionsRoot.answer(promptId, true); promptId = -1 }
        onCancelled: { actionsRoot.answer(promptId, false); promptId = -1 }
    }

    InitializeRepositoryDialog {
        id: initializeDialog
        onChosen: (id, choice) => actionsRoot.answer(id, choice)
    }

    // Development screenshots can submit the transfer dialog.
    Connections {
        target: Store
        function onScreenshotStepRequested(name, argument) {
            if (name === "submitTransfer")
                transferDialog.submit()
            else if (name === "refName")
                refDialog.fill(argument)
            else if (name === "submitRef")
                refDialog.submit()
            else if (name === "confirmRef")
                refConfirm.submitted()
            else if (name === "submitStash")
                stashDialog.submit()
            else if (name === "confirmStash")
                stashConfirm.submitted()
            else if (name === "mutationSource")
                historyMutationDialog.chooseSource(argument)
            else if (name === "patchDestination")
                Store.patches.chooseDestination(argument)
            else if (name === "patchFile")
                Store.patches.chooseFile(argument)
            else if (name === "lineToggle") {
                // lineToggle:<row index> toggles that row of "Select changed lines".
                const row = Store.lineRows.get(Number(argument))
                if (row)
                    Store.lineSelection.toggle(row.rowId, row.checked !== true)
            } else if (name === "deleteWorktree") {
                actionsRoot.deleteWorktree(Number(argument), "")
            } else if (name === "confirmWorktreeDelete") {
                worktreeDeleteConfirm.close()
                worktreeDeleteConfirm.confirmed()
            } else if (name === "lineStage") {
                Store.lineSelection.stage()
                lineSelectionDialog.close()
            } else if (name === "patchSubmit")
                patchDialog.submit()
            else if (name === "iconDialog")
                actionsRoot.showRepositoryIconDialog({ id: Store.workspace.activeTabId })
            else if (name === "iconPick") {
                // iconPick:<icon>=<series index>
                const parts = argument.split("=")
                repositoryIconDialog.icon = parts[0]
                repositoryIconDialog.color = { series: Number(parts[1]) }
            } else if (name === "iconSave")
                repositoryIconDialog.save()
            else if (name === "createGroup")
                Store.workspace.createTabGroup(Store.workspace.activeTabId)
            else if (name === "groupDialog") {
                const group = Store.workspace.groups[0]
                if (group)
                    actionsRoot.showTabGroupDialog(group, Store.workspace.tabs.filter(tab => tab.groupId === group.id).map(tab => tab.label))
            } else if (name === "colorWell") {
                // Opens the custom colour well of the open dialog's colour row.
                const dialogs = [repositoryIconDialog, tabGroupDialog]
                for (const d of dialogs)
                    if (d.opened) {
                        const well = actionsRoot.findWell(d.contentItem)
                        if (well) well.clicked()
                    }
            }
            else if (name === "archiveTo") {
                // archiveTo:<path>: saves the selected commit's snapshot there.
                const selected = (Store.history.state.selectedIds ?? []).filter(id => id !== "wip")
                Store.workflows.saveCommitArchive(selected[0], Store.workflows.archiveName(Store.workspace.active.label ?? "", selected[0]), argument)
            }
            else if (name === "snapshotAction") {
                const entry = (Store.workflows.snapshots.entries ?? [])[0]
                if (entry) Store.workflows.snapshot(argument, { id: entry.id })
            }
            else if (name === "powerTool") {
                // powerTool:<action>=<options json>
                const split = argument.indexOf("=")
                Store.workflows.powerTool(split < 0 ? argument : argument.slice(0, split), split < 0 ? ({}) : JSON.parse(argument.slice(split + 1)))
            }
            else if (name === "extension") {
                // extension:<action>=<options json>
                const split = argument.indexOf("=")
                Store.workflows.extension(split < 0 ? argument : argument.slice(0, split), split < 0 ? ({}) : JSON.parse(argument.slice(split + 1)))
            }
            else if (name === "updateCheck")
                Store.settings.updateAction("check", "")
            else if (name === "statusAcceleration")
                Store.settings.statusAcceleration(argument)
            else if (name === "settingsTool") {
                // settingsTool:<action>=<options json>
                const split = argument.indexOf("=")
                Store.settings.tool(split < 0 ? argument : argument.slice(0, split), split < 0 ? ({}) : JSON.parse(argument.slice(split + 1)))
            }
            else if (name === "createWorktreeDialog") {
                if (Store.shell && Store.shell.extensionsPanel)
                    Store.shell.extensionsPanel.showCreateWorktree()
            }
            else if (name === "confirmRenderer") {
                rendererConfirm.close()
                rendererConfirm.confirmed()
            }
            else if (name === "rendererSave")
                Store.settings.diffRenderer("save", JSON.parse(argument))
            else if (name === "conflictTree" && actionsRoot.conflictResolver)
                actionsRoot.conflictResolver.treeMode = argument !== "off"
            else if (name === "conflictFileMenu" && actionsRoot.conflictResolver)
                actionsRoot.conflictResolver.showFileMenu(actionsRoot.conflictResolver.files[Number(argument)], actionsRoot.conflictResolver, 10, 10)
            else if (name === "conflictExternal")
                Store.conflicts.mergeExternally(argument)
            else if (name === "confirmIntegrationRun") {
                integrationConfirm.close()
                integrationConfirm.confirmed()
            }
            else if (name === "confirmBisect") {
                bisectConfirm.close()
                bisectConfirm.confirmed()
            }
            else if (name === "snapshotCreate")
                Store.workflows.snapshot("create", { name: argument, includeUntracked: true, keepIndex: false })
            else if (name === "about")
                actionsRoot.showAbout()
            else if (name === "submitIgnore")
                ignoreDialog.submit()
            else if (name === "submitMutation")
                historyMutationDialog.finish(argument === "applyOnly")
            else if (name === "confirmMutation")
                historyMutationPreview.submitted()
            else if (name === "rebaseAction") {
                const parts = argument.split("=")
                rebaseEditor.setAction(Number(parts[0]), parts[1])
            } else if (name === "rebaseMove") {
                const parts = argument.split(">")
                rebaseEditor.move(Number(parts[0]), Number(parts[1]))
            } else if (name === "submitRebaseTarget")
                rebaseTarget.submit()
            else if (name === "submitRebase")
                rebaseEditor.submit()
            else if (name === "confirmRebase")
                rebasePreview.submitted()
            else if (name === "conflictTake") {
                const parts = argument.split("=")
                Store.conflicts.takeRegion(Number(parts[0]), parts[1], false)
            } else if (name === "conflictSide")
                Store.conflicts.chooseSide(argument)
            else if (name === "conflictSave")
                Store.conflicts.save()
            else if (name === "conflictSelect")
                Store.conflicts.select(Number(argument), false)
            else if (name === "cloneSource") {
                cloneSource.text = argument
                cloneSourceDialog.choose()
            } else if (name === "chooseFolder") {
                // Answers the open folder dialog without the platform picker.
                const pending = folderDialog.promptId
                if (pending >= 0) {
                    folderDialog.promptId = -1
                    folderDialog.close()
                    actionsRoot.answer(pending, argument)
                }
            } else if (name === "settings")
                actionsRoot.showSettings(argument)
            else if (name === "licenses")
                actionsRoot.showLicenses()
        }
    }

    Connections {
        target: Store.app
        function onPrompt(id, kind, payload) {
            actionsRoot.handlePrompt(id, kind, payload)
        }
        function onNotice(key, args, error) {
            const values = args.length > 0 ? JSON.parse(args) : []
            // Several localized sentences shown as one message.
            if (key === "@join") {
                Notifications.show((values.parts ?? []).map(part => part.args ? L10n.tn(part.l10n, part.args) : L10n.t(part.l10n)).join(" "), error)
                return
            }
            if (values !== null && !Array.isArray(values)) {
                // An argument {l10n: key} is itself a localized text.
                for (const name in values) {
                    const value = values[name]
                    if (value !== null && typeof value === "object" && value.l10n !== undefined)
                        values[name] = value.args ? L10n.tn(value.l10n, value.args) : L10n.t(value.l10n)
                }
            }
            Notifications.show(values === null ? L10n.t(key)
                : Array.isArray(values) ? L10n.t(key, values) : L10n.tn(key, values), error)
        }
    }
}
