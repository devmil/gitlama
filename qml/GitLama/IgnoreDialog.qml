pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Asks for the `.gitignore` entry that hides a changed path, prefilled with the entry that matches exactly that path.
// A failed write asks again with the entry kept and the failure shown.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var payload: ({})
    readonly property bool empty: entryField.text.trim().length === 0
    property string failure: ""
    signal answered(int id, var request)

    function ask(id, value) {
        promptId = id
        payload = value
        entryField.text = value.entry ?? ""
        failure = value.failure ?? ""
        open()
        entryField.forceActiveFocus()
    }
    function submit() {
        if (empty)
            return
        close()
        answered(promptId, entryField.text)
        promptId = -1
    }

    widthClass: MeridianDialog.Form
    title: L10n.t("ignoreDialogTitle")
    description: {
        const text = L10n.t(payload.directory ? "ignoreDialogFolderDescription" : "ignoreDialogFileDescription")
        return payload.tracked ? text + " " + L10n.t("ignoreDialogTrackedNote") : text
    }
    submitDisabled: empty
    onSubmitted: submit()
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s2
        MeridianText { role: MeridianText.Label; text: L10n.t("ignoreDialogEntry") }
        MeridianTextField {
            id: entryField
            objectName: "ignore-entry"
            width: parent.width
            monospace: true
            error: dialog.failure.length > 0
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            Accessible.name: L10n.t("ignoreDialogEntry")
            onTextEdited: dialog.failure = ""
        }
        MeridianText {
            width: parent.width
            role: MeridianText.Caption
            color: dialog.failure.length > 0 ? Theme.colors.danger : Theme.colors.inkMuted
            wrapMode: Text.Wrap
            text: dialog.failure.length > 0 ? L10n.t(dialog.failure) : L10n.t("ignoreDialogEntryHint")
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            objectName: "ignore-add"
            text: L10n.t("ignoreDialogAdd")
            variant: MeridianButton.Primary
            enabled: !dialog.empty
            onClicked: dialog.submit()
        }
    ]
}
