pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// What a restack will do: each branch and
// its new base, an incomplete-plan warning, and the published-history
// acknowledgement. Answers whether published history was acknowledged.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var plan: ({})
    property bool acknowledged: false
    readonly property var steps: plan.steps ?? []
    readonly property bool needsAcknowledgement: (plan.publishedCount ?? 0) > 0
    signal answered(int id, var acknowledge)

    function ask(id, payload) {
        promptId = id
        plan = payload
        acknowledged = false
        open()
        cancelButton.forceActiveFocus()
    }
    function submit() {
        if (needsAcknowledgement && !acknowledged)
            return
        close()
        answered(promptId, acknowledged)
        promptId = -1
    }

    title: L10n.tn("restackPreviewTitle", { count: steps.length })
    description: L10n.t("restackPreviewSummary")
    submitDisabled: needsAcknowledgement && !acknowledged
    onSubmitted: submit()
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6
        MeridianBanner {
            visible: dialog.plan.incomplete === true
            width: parent.width
            tone: MeridianBanner.Warning
            message: L10n.t("restackIncompleteWarning")
        }
        ListWell {
            visible: dialog.steps.length > 0
            width: parent.width
            model: dialog.steps
            delegate: MeridianListRow {
                id: stepRow
                required property var modelData
                required property int index
                width: ListView.view.width
                text: modelData.branch
                subtitle: L10n.tn("restackStepOnto", { branch: modelData.onto })
                leading: Component { StepNumber { number: stepRow.index + 1 } }
                trailing: modelData.published ? publishedBadge : null
                Component { id: publishedBadge; MeridianCount { label: L10n.t("rebasePublishedBadge") } }
            }
        }
        MeridianCheckbox {
            visible: dialog.needsAcknowledgement
            width: parent.width
            text: L10n.t("restackPublishedWarning")
            checked: dialog.acknowledged
            onToggled: dialog.acknowledged = checked
        }
    }
    actions: [
        MeridianButton { id: cancelButton; text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            text: L10n.t("restackRun")
            variant: MeridianButton.Danger
            enabled: !dialog.needsAcknowledgement || dialog.acknowledged
            onClicked: dialog.submit()
        }
    ]
}
