pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Meridian

// The window's dialogs: questions the core's workflows ask (prompts), and
// dialogs the UI opens itself.
Item {
    id: actions

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
    function showLicenses() {
        licenseDialog.packages = Store.settings.licenses()
        licenseDialog.open()
    }
    function showAbout() {}
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
    function deleteWorktree(index, name) {}
    function showRepositoryIconDialog(tab) {}
    function showTabGroupDialog(group, labels) {}

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
        const reason = Commands.reason(id, actions.availability)
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
            if (actions.conflictResolver && actions.conflictResolver.runCommand(id))
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
        case "refreshRepository": Store.history.reload(); return
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
            actions.answer(promptId, path)
            promptId = -1
        }
        onRejected: {
            if (promptId < 0)
                return
            actions.answer(promptId, null)
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
        onConfirmed: { actions.answer(promptId, true); promptId = -1 }
        onCancelled: { actions.answer(promptId, false); promptId = -1 }
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
        onConfirmed: { actions.answer(promptId, true); promptId = -1 }
        onCancelled: { actions.answer(promptId, false); promptId = -1 }
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
        onSubmitted: { if (confirmed) { close(); actions.answer(promptId, true); promptId = -1 } }
        onRejected: { actions.answer(promptId, false); promptId = -1 }
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
        onAnswered: (id, request) => actions.answer(id, request)
    }
    StashConfirmDialog {
        id: stashConfirm
        onAnswered: (id, confirmed) => actions.answer(id, confirmed)
    }
    HistoryMutationDialog {
        id: historyMutationDialog
        onAnswered: (id, request) => actions.answer(id, request)
    }
    HistoryMutationPreviewDialog {
        id: historyMutationPreview
        onAnswered: (id, confirmed) => actions.answer(id, confirmed)
    }
    BranchIntegrationDialog {
        id: branchIntegration
        onAnswered: (id, choice) => actions.answer(id, choice)
    }
    RebaseTargetDialog {
        id: rebaseTarget
        onAnswered: (id, branch) => actions.answer(id, branch)
    }
    RebaseEditorDialog {
        id: rebaseEditor
        onAnswered: (id, edit) => actions.answer(id, edit)
    }
    RebasePreviewDialog {
        id: rebasePreview
        onAnswered: (id, confirmed) => actions.answer(id, confirmed)
    }
    RestackRootDialog {
        id: restackRoot
        onAnswered: (id, branch) => actions.answer(id, branch)
    }
    RestackPreviewDialog {
        id: restackPreview
        onAnswered: (id, acknowledge) => actions.answer(id, acknowledge)
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
            actions.answer(promptId, cloneSource.text.trim())
            promptId = -1
        }
        widthClass: MeridianDialog.Form
        title: L10n.t("cloneRepository")
        description: L10n.t("cloneSourceDescription")
        submitDisabled: cloneSource.text.trim().length === 0
        onSubmitted: choose()
        onRejected: { actions.answer(promptId, null); promptId = -1 }
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
        onConfirmed: { actions.answer(promptId, true); promptId = -1 }
        onCancelled: { actions.answer(promptId, false); promptId = -1 }
    }
    SettingsDialog {
        id: settingsDialog
        onLicensesRequested: actions.showLicenses()
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
        onAnswered: (id, choice) => actions.answer(id, choice)
    }
    CommandPalette {
        id: commandPalette
        onRun: id => actions.runCommand(id, ({}))
    }
    RefMutationDialog {
        id: refDialog
        onAnswered: (id, request) => actions.answer(id, request)
    }
    RefConfirmDialog {
        id: refConfirm
        onAnswered: (id, confirmed) => actions.answer(id, confirmed)
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
        onConfirmed: { actions.answer(promptId, true); promptId = -1 }
        onCancelled: { actions.answer(promptId, false); promptId = -1 }
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
    IgnoreDialog {
        id: ignoreDialog
        onAnswered: (id, entry) => actions.answer(id, entry)
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
        onConfirmed: { actions.answer(promptId, true); promptId = -1 }
        onCancelled: { actions.answer(promptId, false); promptId = -1 }
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
    EditBranchDialog {
        id: editBranchDialog
        onAnswered: (id, edit) => actions.answer(id, edit)
    }
    MeridianConfirm {
        id: recoverTarget
        property int promptId: -1
        title: L10n.t("refMutationTargetUnavailableTitle")
        description: L10n.t("refMutationTargetUnavailableDetail")
        confirmLabel: L10n.t("refMutationRefreshTarget")
        cancelLabel: L10n.t("cancel")
        onConfirmed: { actions.answer(promptId, true); promptId = -1 }
        onCancelled: { actions.answer(promptId, false); promptId = -1 }
    }
    TransferDialog {
        id: transferDialog
        onAnswered: (id, request) => actions.answer(id, request)
    }
    HostKeyDialog {
        id: hostKeyDialog
        onAnswered: (id, trust) => actions.answer(id, trust)
    }
    CredentialDialog {
        id: credentialDialog
        onAnswered: (id, credentials) => actions.answer(id, credentials)
    }
    TransferFailureDialog {
        id: transferFailureDialog
        onAnswered: (id, remedy) => actions.answer(id, remedy)
    }
    MeridianConfirm {
        id: refetchConfirm
        property int promptId: -1
        title: L10n.t("transferMissingObjectTitle")
        confirmLabel: L10n.t("transferRefetchAction")
        cancelLabel: L10n.t("cancel")
        onConfirmed: { actions.answer(promptId, true); promptId = -1 }
        onCancelled: { actions.answer(promptId, false); promptId = -1 }
    }

    InitializeRepositoryDialog {
        id: initializeDialog
        onChosen: (id, choice) => actions.answer(id, choice)
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
            } else if (name === "lineStage") {
                Store.lineSelection.stage()
                lineSelectionDialog.close()
            } else if (name === "patchSubmit")
                patchDialog.submit()
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
                    actions.answer(pending, argument)
                }
            } else if (name === "settings")
                actions.showSettings(argument)
            else if (name === "licenses")
                actions.showLicenses()
        }
    }

    Connections {
        target: Store.app
        function onPrompt(id, kind, payload) {
            actions.handlePrompt(id, kind, payload)
        }
        function onNotice(key, args, error) {
            const values = args.length > 0 ? JSON.parse(args) : []
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
