import QtQuick

// The floating surface of menus, popovers, toasts and dialogs: `raised`,
// `radius-xl`, `shadow-float`. Always transient, never a pane.
Item {
    id: root
    property real radius: Theme.radius.xl
    property color color: Theme.colors.raised
    default property alias content: body.data

    MeridianShadow {
        anchors.fill: parent
        layers: Theme.shadows.float
        radius: root.radius
    }
    Rectangle {
        id: body
        anchors.fill: parent
        radius: root.radius
        color: root.color
    }
}
