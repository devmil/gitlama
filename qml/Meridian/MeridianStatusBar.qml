import QtQuick

// The window's bottom strip on `ground` (Flutter: MeridianStatusBar): live
// state and totals, never commands. Put items in `leading` (from the left,
// shrinking first) and `trailing` (ending at the right), `space-5` apart.
// Use MeridianStatusBarText for text that swaps with a rise.
Item {
    id: root

    default property alias leading: leadingRow.data
    property alias trailing: trailingRow.data

    implicitHeight: Metrics.statusBarHeight
    implicitWidth: 400

    Row {
        id: leadingRow
        anchors.left: parent.left
        anchors.leftMargin: Theme.space.s5
        anchors.right: trailingRow.left
        anchors.rightMargin: Theme.space.s5
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s5
        clip: true
    }
    Row {
        id: trailingRow
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.s5
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s5
    }
}
