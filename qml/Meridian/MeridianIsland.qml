import QtQuick

// The rounded work surface on ground: `pane`, `radius-lg`, `shadow-pane`
// (the shadow is the edge; islands have no border and never nest). While
// keyboard focus is inside, it draws a 1px `accent-soft` halo.
FocusScope {
    id: root

    property color color: Theme.colors.pane
    readonly property bool focused: activeFocus
    default property alias content: surface.data

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
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: Theme.radius.lg + 1
        color: "transparent"
        border.width: 1
        border.color: Theme.colors.accentSoft
        opacity: root.focused ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.quick } }
    }
}
