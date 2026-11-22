import QtQuick

// The rounded work surface on ground: `pane`, `radius-lg`, `shadow-pane`
// (the shadow is the edge; islands have no border and never nest). While
// keyboard focus is inside, it draws a 1px `accent-soft` halo.
FocusScope {
    id: root

    property color color: Theme.colors.pane
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
