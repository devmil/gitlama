import QtQuick
import QtQuick.Templates as T

// A non-interactive `overline` heading over a group of menu items.
T.MenuItem {
    id: control
    enabled: false
    implicitWidth: Metrics.menuMinWidth
    implicitHeight: Theme.type.overlineLineHeight + 2 * Theme.space.s2
    leftPadding: Theme.space.s4
    rightPadding: Theme.space.s4
    Accessible.role: Accessible.Heading
    Accessible.name: text
    indicator: Item {}
    contentItem: MeridianText {
        role: MeridianText.Overline
        text: control.text
        color: Theme.colors.inkMuted
    }
    background: Item {}
}
