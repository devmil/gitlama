import QtQuick
import Meridian

// Placeholder until the welcome screen and workspace are ported.
Rectangle {
    color: Theme.colors.ground
    MeridianText {
        anchors.centerIn: parent
        text: L10n.t("appTitle")
    }
    CaptionBand {}
}
