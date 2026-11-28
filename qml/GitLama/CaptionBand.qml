import QtQuick
import Meridian

// A caption strip over the top edge of a screen without a toolbar row (the
// startup screen): a drag area with the window buttons at their edges.
Item {
    visible: Store.drawsCaption
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Theme.size.toolbar

    WindowDragArea { anchors.fill: parent }
    WindowControls {
        side: "leading"
        anchors.left: parent.left
        anchors.leftMargin: Theme.space.s5
        anchors.verticalCenter: parent.verticalCenter
    }
    WindowControls {
        side: "trailing"
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.s5
        anchors.verticalCenter: parent.verticalCenter
    }
}
