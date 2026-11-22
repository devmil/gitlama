import QtQuick
import QtQuick.Templates as T

// Splits menu groups; destructive commands follow the last one.
T.MenuSeparator {
    implicitWidth: Metrics.menuMinWidth
    implicitHeight: Theme.space.s4 + 1
    padding: 0
    // The control stretches its content item over the whole gap; the 1px
    // rule sits centred inside it.
    contentItem: Item {
        implicitHeight: 1
        Rectangle {
            x: Theme.space.s4
            width: parent.width - 2 * Theme.space.s4
            height: 1
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.colors.line
        }
    }
}
