pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The branch to rebase onto.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var branches: []
    readonly property var selected: branches.find(b => b.name === field.text.trim()) ?? null
    signal answered(int id, var branch)

    function ask(id, payload) {
        promptId = id
        branches = payload.branches ?? []
        field.text = branches.length > 0 ? branches[0].name : ""
        open()
        field.forceActiveFocus()
    }
    function submit() {
        if (selected === null)
            return
        close()
        answered(promptId, selected)
        promptId = -1
    }

    widthClass: MeridianDialog.Form
    title: Commands.dialogTitle(Commands.label("rebaseBranch"))
    submitDisabled: selected === null
    onSubmitted: submit()
    onRejected: { answered(promptId, null); promptId = -1 }

    ReferenceField {
        id: field
        width: parent ? parent.width : 0
        label: L10n.t("historyMutationSourceBranch")
        names: dialog.branches.map(b => b.name)
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            text: L10n.t("rebaseEditPlan")
            variant: MeridianButton.Primary
            enabled: dialog.selected !== null
            onClicked: dialog.submit()
        }
    ]
}
