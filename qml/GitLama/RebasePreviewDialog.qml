pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The rebase as Git will run it: every
// step with its action, what squashes join and rewords say, and the todo.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var preview: ({})
    readonly property var instructions: preview.instructions ?? []
    signal answered(int id, bool confirmed)

    function ask(id, payload) {
        promptId = id
        preview = payload
        open()
        cancelButton.forceActiveFocus()
    }
    function detail(instruction) {
        if (instruction.action === "squash" || instruction.action === "fixup") {
            const base = instructions.find(item => item.id === instruction.baseId)
            return base ? L10n.tn("rebaseStepCombinedWith", { subject: base.subject }) : L10n.t("rebaseStepCombinedAbove")
        }
        if (instruction.action === "reword" && instruction.message !== null && instruction.message !== undefined)
            return L10n.tn("rebaseStepNewMessage", { message: instruction.message.split("\n")[0] })
        return ""
    }

    widthClass: MeridianDialog.Form
    title: L10n.t("rebasePreviewTitle")
    description: L10n.t("rebasePreviewSummary")
    onSubmitted: { close(); answered(promptId, true); promptId = -1 }
    onRejected: { answered(promptId, false); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6
        ListWell {
            visible: dialog.instructions.length > 0
            width: parent.width
            model: dialog.instructions
            delegate: MeridianListRow {
                id: step
                required property var modelData
                required property int index
                readonly property string detailText: dialog.detail(modelData)
                width: ListView.view.width
                text: modelData.subject
                subtitle: detailText
                twoLine: detailText.length > 0
                meta: L10n.t("rebaseAction" + modelData.action.charAt(0).toUpperCase() + modelData.action.slice(1))
                dimmed: modelData.action === "drop"
                leading: Component { StepNumber { number: step.index + 1 } }
            }
        }
        MeridianText {
            visible: (dialog.preview.autosquashApplied ?? 0) > 0
            width: parent.width
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: L10n.tn("rebaseAutosquashApplied", { count: dialog.preview.autosquashApplied ?? 0 })
        }
        GitCommands { width: parent.width; commands: dialog.preview.commands ?? [] }
    }
    actions: [
        MeridianButton { id: cancelButton; text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton { text: L10n.t("rebaseStart"); variant: MeridianButton.Danger; onClicked: dialog.submitted() }
    ]
}
