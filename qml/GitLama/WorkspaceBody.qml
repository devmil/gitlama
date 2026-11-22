import QtQuick
import Meridian

// Placeholder: the active repository's panes.
Item {
    MeridianText {
        anchors.centerIn: parent
        color: Theme.colors.inkMuted
        text: Store.workspace.active ? Store.workspace.active.pane : ""
    }
}
