pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// A list inside a dialog: rows on `pane-alt`
// in a `radius-lg` well that scrolls past `maxHeight`.
Rectangle {
    id: well

    property alias model: list.model
    property alias delegate: list.delegate
    property alias header: list.header
    property real maxHeight: GitLamaLayout.dialogListMaxHeight
    readonly property alias view: list

    implicitHeight: Math.min(list.contentHeight, maxHeight)
    color: Theme.colors.paneAlt
    radius: Theme.radius.lg
    clip: true

    ListView {
        id: list
        anchors.fill: parent
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        MeridianWheelScroll { flickable: list }
        C.ScrollBar.vertical: MeridianScrollBar {}
    }
}
