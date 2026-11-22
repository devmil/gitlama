pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Meridian

// The window's dialogs: questions the core's workflows ask (prompts), and
// dialogs the UI opens itself.
Item {
    id: actions

    required property var window

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
        default:
            answer(id, null)
        }
    }

    function showSettings() {}
    function showAbout() {}
    function openFolder(path) {}
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
        default:
            Notifications.show(Commands.label(id), false)
        }
    }

    /// What panes contribute to command availability.
    property var availability: ({})
    function openRemoteRepository() {}
    function cloneRepository() {}
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

    InitializeRepositoryDialog {
        id: initializeDialog
        onChosen: (id, choice) => actions.answer(id, choice)
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
                        values[name] = L10n.t(value.l10n)
                }
            }
            Notifications.show(values === null ? L10n.t(key)
                : Array.isArray(values) ? L10n.t(key, values) : L10n.tn(key, values), error)
        }
    }
}
