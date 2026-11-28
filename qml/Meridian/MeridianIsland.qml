pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

// The rounded work surface on ground: `pane`, `radius-lg`, `shadow-pane`
// (the shadow is the edge; islands have no border and never nest). While
// keyboard focus is inside, it draws a 1px `accent-soft` halo. Its content
// keeps the rounded corners even where it paints its own background: a clip
// is rectangular, so the corners outside the rounding are covered with the
// ground the island sits on.
FocusScope {
    id: root

    property color color: Theme.colors.pane
    /// What the island sits on, shown at its corners outside the rounding.
    property color groundColor: Theme.colors.ground
    readonly property bool focused: activeFocus
    default property alias content: body.data

    /// Header title (`body-strong`). No header without a title, an icon, a
    /// leading item or actions.
    property string title
    property string iconName
    property Component leading
    /// A quiet count after the header title; -1 shows none.
    property int count: -1
    property string countLabel
    /// Header metadata next to the title (a count, a path).
    property string subtitle
    /// The hairline under the header; off when the content starts with its
    /// own edge (a toolbar, a column header).
    property bool headerDivider: true
    /// Header actions: small icon buttons and small buttons.
    property alias actions: header.actions
    /// The content's height: the header is above it.
    readonly property real contentHeight: body.height
    readonly property bool hasHeader: title.length > 0 || iconName.length > 0 || leading !== null
        || header.actions.length > 0

    MeridianShadow {
        anchors.fill: parent
        layers: Theme.shadows.pane
        radius: Theme.radius.lg
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Theme.radius.lg
        color: root.color
        clip: true

        MeridianSectionHeader {
            id: header
            visible: root.hasHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: visible ? implicitHeight : 0
            title: root.title
            iconName: root.iconName
            leading: root.leading
            count: root.count
            countLabel: root.countLabel
            caption: root.subtitle
            divider: root.headerDivider
        }

        Item {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
        }
    }

    // Above the content, each corner outside the rounding in `groundColor`:
    // a square of `radius-lg` at its corner minus the quarter circle.
    component Corner: Shape {
        id: corner
        property bool atRight: false
        property bool atBottom: false
        readonly property real cornerX: atRight ? width : 0
        readonly property real cornerY: atBottom ? height : 0
        width: Theme.radius.lg
        height: Theme.radius.lg
        x: atRight ? root.width - width : 0
        y: atBottom ? root.height - height : 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillColor: root.groundColor
            startX: corner.cornerX; startY: corner.cornerY
            PathLine { x: corner.width - corner.cornerX; y: corner.cornerY }
            PathArc {
                x: corner.cornerX
                y: corner.height - corner.cornerY
                radiusX: corner.width
                radiusY: corner.height
                // A mirrored corner turns the other way.
                direction: corner.atRight !== corner.atBottom ? PathArc.Clockwise : PathArc.Counterclockwise
            }
            PathLine { x: corner.cornerX; y: corner.cornerY }
        }
    }
    Item {
        objectName: "meridianIslandCorners"
        anchors.fill: parent
        Corner { }
        Corner { atRight: true }
        Corner { atRight: true; atBottom: true }
        Corner { atBottom: true }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: Theme.radius.lg + 1
        color: "transparent"
        border.width: 1
        border.color: Theme.colors.accentSoft
        opacity: root.focused ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.focused ? Motion.select : Motion.hoverOut } }
    }
}
