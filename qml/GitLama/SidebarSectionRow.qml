import QtQuick
import QtQuick.Templates as T
import Meridian

// A sidebar section's header: chevron, overline
// label and the section's count, which a plus button replaces on hover or
// keyboard focus. Insert and the plus run the section's command.
T.Control {
    id: root

    required property var row
    property bool hasRepository: false
    signal toggled()
    signal command(string id)

    readonly property string commandId: row.section
    readonly property string reason: {
        const reason = Commands.reason(commandId, Store.actions ? Store.actions.availability : ({}))
        // Only a remote tab's reason disables the button; other reasons are
        // explained when the command runs.
        return reason === "repositoryRequired" || reason.startsWith("remote") ? reason : ""
    }
    readonly property bool keyboardFocus: visualFocus
    readonly property bool showPlus: hover.hovered || root.keyboardFocus

    implicitHeight: Theme.space.s4 + Metrics.navSectionHeight
    focusPolicy: Qt.StrongFocus
    padding: 0

    Accessible.role: Accessible.Button
    Accessible.name: label.text

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Insert) {
            if (root.reason.length === 0)
                root.command(root.commandId)
            event.accepted = true
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                   && root.row.hasChildren) {
            root.toggled()
            event.accepted = true
        } else if (event.key === Qt.Key_Left && root.row.expanded || event.key === Qt.Key_Right && !root.row.expanded) {
            if (root.row.hasChildren)
                root.toggled()
            event.accepted = true
        }
    }

    contentItem: Item {
    Item {
        id: header
        y: Theme.space.s4
        width: parent.width
        height: Metrics.navSectionHeight

        HoverHandler { id: hover }
        TapHandler {
            onTapped: {
                root.forceActiveFocus()
                if (root.row.hasChildren)
                    root.toggled()
            }
        }

        MeridianIcon {
            id: chevron
            visible: root.row.hasChildren
            x: Theme.space.s4 + (Metrics.chevronSize - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            name: root.row.expanded ? "chevron-down" : "chevron-right"
            iconSize: MeridianIcon.Small
            color: Theme.colors.inkMuted
        }
        MeridianText {
            id: label
            x: Theme.space.s4 + (root.row.hasChildren ? Metrics.chevronSize + Theme.space.s2 : 0)
            anchors.verticalCenter: parent.verticalCenter
            width: trailing.x - x - Theme.space.s2
            role: MeridianText.Overline
            text: L10n.t(root.row.name).toUpperCase()
            color: Theme.colors.inkMuted
            elide: Text.ElideRight
        }
        Item {
            id: trailing
            width: Theme.size.controlSmall
            height: parent.height
            x: parent.width - Theme.space.s4 - width

            MeridianIconButton {
                visible: root.showPlus
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Commands.label(root.commandId)
                iconName: "plus"
                controlSize: MeridianButton.Small
                onGround: true
                focusPolicy: Qt.NoFocus
                disabledReason: root.reason.length > 0 ? Commands.reasonText(root.reason) : ""
                enabled: root.reason.length === 0
                onClicked: root.command(root.commandId)
            }
            MeridianCount {
                visible: !root.showPlus
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: String(root.row.count)
                tone: MeridianCount.Quiet
            }
        }
    }
    }
    MeridianFocusRing {
        target: header
        shown: root.keyboardFocus
        targetRadius: Theme.radius.sm
    }
}
