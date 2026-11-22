pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The header of a full-pane workflow (the Dart GitLamaWorkflowHeader): its
// title and status on `ground`, then its actions, its primary action and
// Exit.
Rectangle {
    id: header

    property string title
    property string status
    property string exitLabel
    default property alias actions: actionRow.data
    property alias primary: primarySlot.data
    signal exit()

    readonly property bool showContext: width >= 700

    implicitHeight: GitLamaLayout.workflowHeaderHeight
    color: Theme.colors.ground

    MeridianText {
        id: titleText
        x: Theme.space.s3
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, end.x - x - Theme.space.s4)
        role: MeridianText.BodyStrong
        text: header.title
    }
    MeridianText {
        visible: header.showContext && header.status.length > 0
        x: titleText.x + titleText.width + Theme.space.s4
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(implicitWidth, end.x - x - Theme.space.s4))
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        text: header.status
    }
    Row {
        id: end
        x: parent.width - width - Theme.space.s3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s4
        Row {
            id: actionRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s1
        }
        Row {
            id: primarySlot
            anchors.verticalCenter: parent.verticalCenter
            visible: children.length > 0
        }
        MeridianButton {
            anchors.verticalCenter: parent.verticalCenter
            text: header.exitLabel
            variant: MeridianButton.Quiet
            controlSize: MeridianButton.Small
            onClicked: header.exit()
        }
    }
}
