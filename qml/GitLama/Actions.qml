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
