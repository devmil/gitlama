import QtQuick
import Meridian

// Placeholder until the workspace shell is ported.
Rectangle {
    color: Theme.colors.ground
    MeridianText {
        anchors.centerIn: parent
        text: Store.workspace.tabs.map(tab => tab.label + " (" + tab.phase + ")").join(", ")
    }
    CaptionBand {}
}
