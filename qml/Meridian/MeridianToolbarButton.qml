import QtQuick
import QtQuick.Templates as T

// A toolbar command on `ground` (Flutter: MeridianToolbarButton): a 18px
// icon over an optional `caption` label, `accent-soft` while `selected`.
// Give it a `menu` (a MeridianMenu) for a split button: the caret opens the
// menu below the whole button. `showLabel: false` keeps the label as the
// tooltip for narrow windows.
Item {
    id: root

    property string text
    property string iconName
    property bool selected: false
    property bool showLabel: true
    property string tooltip
    property string disabledReason
    property string menuLabel: "Show menu"
    property MeridianMenu menu: null
    property int badge: 0
    property int badgeTone: MeridianCount.Accent
    property int nudgeDirection: 0
    /// A MeridianNudge direction the icon moves on each click.
    property int nudge: MeridianNudge.None

    signal clicked()

    readonly property bool hasMenu: menu !== null
    readonly property real radius: Theme.radius.md

    implicitWidth: face.implicitWidth + (hasMenu ? caret.width : 0)
    implicitHeight: Metrics.toolbarButtonHeight

    T.AbstractButton {
        id: face
        height: parent.height
        hoverEnabled: true
        focusPolicy: Qt.TabFocus
        enabled: root.enabled
        implicitWidth: Math.max(root.showLabel ? Metrics.toolbarButtonMinWidth : Metrics.toolbarButtonCompactWidth,
                                content.implicitWidth + 2 * Theme.space.s3)
        Accessible.role: Accessible.Button
        Accessible.name: root.text
        Accessible.checked: root.selected
        Accessible.checkable: root.selected
        onClicked: {
            if (root.nudgeDirection !== 0)
                nudgeMotion.restart()
            nudger.play()
            root.clicked()
        }

        MeridianNudge { id: nudger; direction: root.nudge }

        scale: down ? Motion.pressScale : 1
        Behavior on scale {
            NumberAnimation {
                duration: face.down ? Motion.press : Motion.snappy.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: face.down ? Motion.exitCurve : Motion.snappy.curve
            }
        }

        MeridianTooltip {
            shown: face.hovered
            text: root.enabled ? (root.tooltip.length > 0 ? root.tooltip : root.text)
                               : (root.disabledReason.length > 0 ? root.disabledReason : root.tooltip.length > 0 ? root.tooltip : root.text)
        }

        contentItem: Column {
            id: content
            spacing: Metrics.toolbarLabelGap
            topPadding: (face.height - implicitHeight) / 2
            MeridianIcon {
                id: glyph
                anchors.horizontalCenter: parent.horizontalCenter
                name: root.iconName
                iconSize: MeridianIcon.Toolbar
                color: root.enabled ? Theme.colors.ink : Theme.colors.inkFaint
                rotation: nudger.angle
                transform: Translate { id: shift; x: nudger.xOffset; y: nudger.yOffset }
            }
            MeridianText {
                visible: root.showLabel
                anchors.horizontalCenter: parent.horizontalCenter
                role: MeridianText.Caption
                text: root.text.replace("…", "")
                color: !root.enabled ? Theme.colors.inkFaint
                     : face.hovered || face.down ? Theme.colors.ink : Theme.colors.inkMuted
            }
        }
        SequentialAnimation {
            id: nudgeMotion
            NumberAnimation { target: shift; property: "x"; to: root.nudgeDirection * Motion.nudgeDistance; duration: Motion.nudge }
            NumberAnimation { target: shift; property: "x"; to: 0; duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve }
        }

        background: Item {
            Rectangle {
                id: fill
                anchors.fill: parent
                radius: root.radius
                readonly property color rest: root.selected ? Theme.colors.accentSoft : Theme.clear(Theme.colors.groundHover)
                readonly property color hover: root.selected ? Theme.pressed(Theme.colors.accentSoft) : Theme.colors.groundHover
                color: !face.enabled ? rest : face.down ? Theme.pressed(hover) : face.hovered ? hover : rest
                Behavior on color { ColorAnimation { duration: Motion.hoverFor(face.hovered || face.down) } }
                // A split button's face has square trailing corners.
                Rectangle {
                    visible: root.hasMenu && parent.color.a > 0
                    anchors.right: parent.right
                    width: parent.radius
                    height: parent.height
                    color: parent.color
                }
            }
            MeridianBadgeDot {
                count: root.badge
                tone: root.badgeTone
                anchors.right: parent.right
                anchors.rightMargin: -Metrics.toolbarBadgeRight
                y: Metrics.toolbarBadgeTop
            }
            MeridianFocusRing {
                target: face
                shown: face.visualFocus
                targetRadius: root.radius
            }
        }
    }

    T.AbstractButton {
        id: caret
        visible: root.hasMenu
        x: face.width
        width: Metrics.splitCaretWidth
        height: parent.height
        hoverEnabled: true
        focusPolicy: Qt.TabFocus
        enabled: root.enabled
        Accessible.role: Accessible.ButtonMenu
        Accessible.name: root.menuLabel
        onClicked: if (root.menu) root.menu.popup(root, 0, root.height)

        MeridianTooltip {
            shown: caret.hovered && !(root.menu && root.menu.visible)
            text: root.menuLabel
        }
        contentItem: Item {
            MeridianIcon {
                anchors.centerIn: parent
                name: "chevron-down"
                extent: Metrics.splitCaretIconSize
                color: root.enabled ? Theme.colors.inkMuted : Theme.colors.inkFaint
            }
        }
        background: Rectangle {
            radius: root.radius
            readonly property color hover: Theme.colors.groundHover
            color: caret.down ? Theme.pressed(hover) : caret.hovered ? hover : Theme.clear(hover)
            Behavior on color { ColorAnimation { duration: Motion.hoverFor(caret.hovered || caret.down) } }
            // Square the leading corners against the face.
            Rectangle {
                width: parent.radius
                height: parent.height
                color: parent.color
                visible: parent.color.a > 0
            }
            MeridianFocusRing {
                target: caret
                shown: caret.visualFocus
                targetRadius: root.radius
            }
        }
    }
}
