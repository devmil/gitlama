import QtQuick
import Meridian

// A sidebar group's overline label (Workspace, Repository), with an
// optional trailing control.
Item {
    id: root

    property string label
    default property alias trailing: trailingSlot.data

    implicitHeight: Theme.space.s4 + Metrics.navSectionHeight

    MeridianText {
        x: Theme.space.s4
        y: Theme.space.s4 + (Metrics.navSectionHeight - height) / 2
        width: trailingSlot.x - x - Theme.space.s2
        role: MeridianText.Overline
        text: root.label.toUpperCase()
        color: Theme.colors.inkMuted
        elide: Text.ElideRight
    }
    Row {
        id: trailingSlot
        x: root.width - Theme.space.s4 - width
        y: Theme.space.s4 + (Metrics.navSectionHeight - height) / 2
    }
}
