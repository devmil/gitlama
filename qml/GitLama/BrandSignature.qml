import QtQuick
import Meridian

// The lama signature in the status bar: `ink-faint`, `ink-muted` on hover or
// focus; it opens About.
Item {
    id: brand
    signal activated()

    implicitWidth: Theme.size.control
    implicitHeight: Theme.size.control
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: L10n.t("aboutApp")
    Accessible.onPressAction: brand.activated()
    Keys.onReturnPressed: brand.activated()
    Keys.onSpacePressed: brand.activated()

    LamaSignature {
        anchors.centerIn: parent
        height: Theme.size.icon
        width: height * 96.7 / 89.8
        color: hover.hovered || brand.activeFocus ? Theme.colors.inkMuted : Theme.colors.inkFaint
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: brand.activated() }
    MeridianTooltip {
        shown: hover.hovered
        text: L10n.t("brandTooltip")
    }
}
