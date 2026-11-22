import QtQuick

// The bar of a multi-selection (Flutter: MeridianSelectionBar): the count
// ("3 selected", announced as it changes), small actions, and a clear button.
// It rises in on `spring-gentle` and leaves downwards. Controls in it should
// set `surfaceColor: Theme.colors.accentSoft`.
Item {
    id: root

    property string label
    property string clearLabel
    property bool shown: true
    default property alias actions: actionRow.data

    signal clearRequested()

    implicitHeight: Theme.size.control + 2 * Theme.space.s2
    implicitWidth: 360
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Motion.fade(root.shown ? Motion.overlay : Motion.exit) } }

    Rectangle {
        id: bar
        width: parent.width
        height: parent.height
        radius: Theme.radius.md
        color: Theme.colors.accentSoft
        y: root.shown ? 0 : Motion.offsetToast
        Behavior on y {
            NumberAnimation {
                duration: root.shown ? Motion.gentle.duration : Motion.exit
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.shown ? Motion.gentle.curve : Motion.exitCurve
            }
        }

        MeridianText {
            id: count
            x: Theme.space.s5
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width / 3)
            role: MeridianText.Label
            text: root.label
            color: Theme.colors.accentInk
            tabular: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
        Row {
            id: actionRow
            x: count.x + count.width + Theme.space.s5
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s2
        }
        MeridianIconButton {
            objectName: "selectionBarClear"
            x: parent.width - width - Theme.space.s2
            anchors.verticalCenter: parent.verticalCenter
            iconName: "x"
            text: root.clearLabel
            controlSize: MeridianButton.Small
            surfaceColor: Theme.colors.accentSoft
            onClicked: root.clearRequested()
        }
    }
}
