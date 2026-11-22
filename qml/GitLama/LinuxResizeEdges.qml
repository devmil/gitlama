pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window

// Resize handles along the edges of the frameless Linux window. Compositors
// that tile (Hyprland) never deliver these; floating ones get native resizes.
Item {
    id: root

    readonly property real grip: 6

    component Edge: Item {
        id: edge
        required property int edges
        required property int cursor
        HoverHandler { cursorShape: edge.cursor }
        DragHandler {
            target: null
            onActiveChanged: if (active) root.Window.window.startSystemResize(edge.edges)
        }
    }

    Edge { edges: Qt.LeftEdge; cursor: Qt.SizeHorCursor; x: 0; y: root.grip; width: root.grip; height: parent.height - 2 * root.grip }
    Edge { edges: Qt.RightEdge; cursor: Qt.SizeHorCursor; x: parent.width - root.grip; y: root.grip; width: root.grip; height: parent.height - 2 * root.grip }
    Edge { edges: Qt.TopEdge; cursor: Qt.SizeVerCursor; x: root.grip; y: 0; width: parent.width - 2 * root.grip; height: root.grip }
    Edge { edges: Qt.BottomEdge; cursor: Qt.SizeVerCursor; x: root.grip; y: parent.height - root.grip; width: parent.width - 2 * root.grip; height: root.grip }
    Edge { edges: Qt.TopEdge | Qt.LeftEdge; cursor: Qt.SizeFDiagCursor; width: root.grip; height: root.grip }
    Edge { edges: Qt.BottomEdge | Qt.RightEdge; cursor: Qt.SizeFDiagCursor; x: parent.width - root.grip; y: parent.height - root.grip; width: root.grip; height: root.grip }
    Edge { edges: Qt.TopEdge | Qt.RightEdge; cursor: Qt.SizeBDiagCursor; x: parent.width - root.grip; width: root.grip; height: root.grip }
    Edge { edges: Qt.BottomEdge | Qt.LeftEdge; cursor: Qt.SizeBDiagCursor; y: parent.height - root.grip; width: root.grip; height: root.grip }
}
