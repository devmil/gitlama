pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// How to bring another branch into the current one: merge (the default) or rebase, each explained
// in a sentence.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property string sourceName: ""
    signal answered(int id, var choice)

    function ask(id, payload) {
        promptId = id
        sourceName = payload.sourceName ?? ""
        open()
        mergeButton.forceActiveFocus()
    }
    function choose(choice) {
        close()
        answered(promptId, choice)
        promptId = -1
    }

    title: L10n.t("branchIntegrationTitle")
    description: sourceName.length === 0 ? L10n.t("branchIntegrationHintAny")
        : L10n.tn("branchIntegrationHint", { branch: sourceName })
    onSubmitted: choose("merge")
    onRejected: { answered(promptId, null); promptId = -1 }

    MeridianPropertyList {
        width: parent ? parent.width : 0
        properties: [
            { label: L10n.t("branchIntegrationMerge"), value: L10n.t("branchIntegrationMergeDetail"), selectable: false },
            { label: L10n.t("branchIntegrationRebase"), selectable: false,
              value: dialog.sourceName.length === 0 ? L10n.t("branchIntegrationRebaseDetailAny")
                   : L10n.tn("branchIntegrationRebaseDetail", { branch: dialog.sourceName }) },
        ]
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton { text: L10n.t("branchIntegrationRebaseAction"); onClicked: dialog.choose("rebase") },
        MeridianButton {
            id: mergeButton
            text: L10n.t("branchIntegrationMergeAction")
            variant: MeridianButton.Primary
            onClicked: dialog.choose("merge")
        }
    ]
}
