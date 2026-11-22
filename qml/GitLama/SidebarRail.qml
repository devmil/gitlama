import QtQuick
import Meridian

// The compact sidebar: Changes and History as icon buttons.
Rectangle {
    id: rail

    property string pane
    signal selectPane(string pane)

    color: Theme.colors.ground

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.space.s3
        spacing: Theme.space.s2

        MeridianIconButton {
            text: L10n.t("workspaceChanges")
            iconName: "changes"
            onGround: true
            active: rail.pane === "changes"
            onClicked: rail.selectPane("changes")
        }
        MeridianIconButton {
            text: L10n.t("workspaceHistory")
            iconName: "history"
            onGround: true
            active: rail.pane === "history"
            onClicked: rail.selectPane("history")
        }
    }
}
