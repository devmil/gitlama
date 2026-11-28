pragma ComponentBehavior: Bound
import QtQuick

// Holds a region while blocking work runs (Flutter: MeridianBusyOverlay).
// Fill the region with it: it takes pointer, wheel and keyboard input at
// once, but shows only after `motion-spinner-delay`, fading in over
// `motion-quick`, so fast work never flashes it (MM-68). A `scrim` at the
// busy-scrim share keeps the page readable; a raised card centres a
// spinner, the `message` and one `action` (usually Cancel).
FocusScope {
    id: root

    /// What is happening ("Verifying…"), announced when it appears.
    property string message
    /// The one thing the user can still do, such as cancelling.
    default property alias action: actionSlot.data

    /// A hidden action (Cancel when the work cannot stop) takes no room.
    readonly property bool hasAction: actionSlot.visibleChildren.length > 0

    Accessible.role: Accessible.AlertMessage
    Accessible.name: message

    // Input stops at once, before anything shows.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        preventStealing: true
        onWheel: wheel => wheel.accepted = true
    }
    Keys.onPressed: event => event.accepted = true

    Item {
        id: shown
        objectName: "busyOverlayContent"
        anchors.fill: parent
        opacity: 0

        Rectangle {
            anchors.fill: parent
            color: Theme.colors.scrim
            opacity: Metrics.opacityBusyScrim
        }
        MeridianShadow {
            anchors.fill: card
            layers: Theme.shadows.float
            radius: card.radius
        }
        Rectangle {
            id: card
            anchors.centerIn: parent
            readonly property real actionGap: root.hasAction ? Theme.space.s4 : 0
            width: Math.min(row.implicitWidth + actionGap + actionSlot.width + leftPad + rightPad, parent.width - 2 * Theme.space.s5)
            height: Math.max(row.implicitHeight, actionSlot.height) + 2 * vPad
            radius: Theme.radius.xl
            color: Theme.colors.raised
            readonly property real leftPad: Theme.space.s6
            readonly property real rightPad: root.hasAction ? Theme.space.s3 : Theme.space.s6
            readonly property real vPad: root.hasAction ? Theme.space.s3 : Theme.space.s5
            Row {
                id: row
                x: card.leftPad
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.s4
                MeridianSpinner {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Theme.size.icon
                    color: Theme.colors.accent
                    immediate: true
                }
                MeridianText {
                    visible: root.message.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, card.parent.width - 2 * Theme.space.s5 - card.leftPad - card.rightPad
                                    - Theme.size.icon - Theme.space.s4 - card.actionGap - actionSlot.width)
                    role: MeridianText.BodyStrong
                    text: root.message
                }
            }
            // Beside the row, not in it: a hidden action leaves no gap.
            Item {
                id: actionSlot
                x: row.x + row.width + card.actionGap
                anchors.verticalCenter: parent.verticalCenter
                width: root.hasAction ? childrenRect.width : 0
                height: root.hasAction ? childrenRect.height : 0
            }
        }

        SequentialAnimation on opacity {
            running: true
            PauseAnimation { duration: Motion.spinnerDelay }
            NumberAnimation { to: 1; duration: Motion.quick; easing.type: Easing.OutCubic }
        }
    }
}
