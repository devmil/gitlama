pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The active repository's recent Git commands: a
// timeline under the workspace; the selected command shows its output.
MeridianIsland {
    id: island

    property string selectedId: ""
    readonly property var records: Store.operations ? (Store.operations.activity ?? []) : []
    readonly property var selected: records.find(record => record.id === selectedId) ?? records[records.length - 1] ?? null

    title: L10n.t("workspaceActivity")
    implicitHeight: GitLamaLayout.activityHeight

    function copySelected() {
        const record = selected
        if (!record || record.output.length === 0)
            return
        const command = record.executable + " " + record.arguments
        Store.actions.copyText(command + "\n\n" + record.output, L10n.t("activityCopied"))
    }
    function refresh() { Store.operations.loadActivity() }

    Component.onCompleted: refresh()
    // Activity changes as operations run and finish.
    Connections {
        target: Store.operations
        function onCenterChanged() { island.refresh() }
    }
    Connections {
        target: Store.workspace
        function onActiveChanged() { island.selectedId = ""; island.refresh() }
    }

    actions: [
        MeridianIconButton {
            iconName: "copy"
            text: L10n.t("activityCopy")
            controlSize: MeridianButton.Small
            onClicked: island.copySelected()
        }
    ]

    MeridianEmptyState {
        visible: island.records.length === 0
        anchors.fill: parent
        compact: true
        title: L10n.t("operationsEmpty")
    }
    ListView {
        id: list
        visible: island.records.length > 0
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: island.records
        MeridianWheelScroll { flickable: list }
        C.ScrollBar.vertical: MeridianScrollBar {}
        delegate: TimelineRow {
            id: recordRow
            required property var modelData
            required property int index
            width: ListView.view.width
            state_: ({ running: "running", succeeded: "succeeded", failed: "failed", canceled: "cancelled" })[modelData.status] ?? "failed"
            verb: modelData.executable
            target: modelData.arguments
            metadata: L10n.t("operationState" + modelData.status.charAt(0).toUpperCase() + modelData.status.slice(1))
            time: Qt.formatTime(new Date(modelData.started), Qt.locale().timeFormat(Locale.ShortFormat))
            first: index === 0
            last: index === island.records.length - 1
            selected: island.selected !== null && island.selected.id === modelData.id
            onActivated: island.selectedId = modelData.id
            details: Component {
                Column {
                    width: parent ? parent.width : 0
                    MeridianText {
                        width: parent.width
                        role: MeridianText.CodeSm
                        color: Theme.colors.inkMuted
                        text: recordRow.modelData.executable + " " + recordRow.modelData.arguments
                    }
                    Flickable {
                        id: output
                        width: parent.width
                        height: Math.min(GitLamaLayout.activityOutputMaxHeight, outputText.implicitHeight)
                        contentHeight: outputText.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        MeridianWheelScroll { flickable: output }
                        MeridianSelectableText {
                            id: outputText
                            width: output.width
                            role: MeridianText.CodeSm
                            color: Theme.colors.inkMuted
                            wrapMode: Text.Wrap
                            text: recordRow.modelData.output
                        }
                    }
                }
            }
        }
    }
}
