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
            Notifications.show(Array.isArray(values) ? L10n.t(key, values) : L10n.tn(key, values), error)
        }
    }
}
