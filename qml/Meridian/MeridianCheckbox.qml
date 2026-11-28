import QtQuick
import QtQuick.Templates as T

// A choice in a list of independent options (Flutter: MeridianCheckbox).
// Checking pops the box in (`spring-pop`) and draws the check after a short
// delay; unchecking fades it out. `text` is the label; `description` a
// caption under it.
T.CheckBox {
    id: control

    property string description
    readonly property bool on: checkState !== Qt.Unchecked
    readonly property bool mixed: checkState === Qt.PartiallyChecked

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    spacing: Metrics.checkboxLabelOffset
    padding: 0
    leftPadding: Metrics.checkboxSize + spacing
    implicitWidth: implicitContentWidth + leftPadding
    implicitHeight: Math.max(Theme.size.minTarget, Metrics.checkboxSize, implicitContentHeight)

    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.description: description
    Accessible.checked: checked

    readonly property color onFill: !enabled ? Theme.colors.inkFaint
        : down ? Theme.pressed(Theme.brighten(Theme.colors.accent, Theme.colors.inkOnAccent))
        : hovered ? Theme.brighten(Theme.colors.accent, Theme.colors.inkOnAccent) : Theme.colors.accent
    readonly property color offFill: !enabled ? Theme.colors.paneAlt
        : down ? Theme.pressed(Theme.colors.paneHover) : hovered ? Theme.colors.paneHover : Theme.colors.pane

    property real _fill: on ? 1 : 0
    property real _scale: 1
    property real _check: on ? 1 : 0
    onOnChanged: {
        if (on) {
            if (Motion.reduced) {
                _fill = 1; _scale = 1; _check = 1
                return
            }
            pop.restart()
        } else {
            pop.stop()
            unpop.restart()
        }
    }
    ParallelAnimation {
        id: pop
        SequentialAnimation {
            PropertyAction { target: control; property: "_scale"; value: Metrics.opacityBadgeLeaveScale }
            NumberAnimation { target: control; property: "_scale"; to: 1; duration: Motion.pop.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.pop.curve }
        }
        NumberAnimation { target: control; property: "_fill"; to: 1; duration: Tokens.durations.quick; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
        SequentialAnimation {
            PauseAnimation { duration: Metrics.checkboxCheckDelay }
            NumberAnimation { target: control; property: "_check"; to: 1; duration: Metrics.checkboxCheckDraw; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
        }
    }
    ParallelAnimation {
        id: unpop
        NumberAnimation { target: control; property: "_fill"; to: 0; duration: Motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve }
        NumberAnimation { target: control; property: "_check"; to: 0; duration: Motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve }
    }

    indicator: Item {
        width: Metrics.checkboxSize
        height: Metrics.checkboxSize
        y: control.description.length > 0 && !Theme.touch
           ? Math.max(0, (Theme.type.bodyLineHeight - height) / 2) : (control.height - height) / 2
        readonly property bool settled: control.on && control._fill >= 1 && Math.abs(control._scale - 1) < 0.001

        Rectangle {
            anchors.fill: parent
            radius: Metrics.checkboxRadius
            color: parent.settled ? control.onFill : control.offFill
            border.width: 1
            border.color: control.on ? control.onFill
                : !control.enabled ? Theme.colors.line
                : control.hovered || control.down ? Theme.colors.inkMuted : Theme.colors.controlEdge
            Behavior on color { ColorAnimation { duration: Motion.hoverFor(control.hovered || control.down) } }
        }
        Rectangle {
            anchors.fill: parent
            radius: Metrics.checkboxRadius
            color: control.onFill
            opacity: parent.settled ? 0 : Math.max(0, Math.min(1, control._fill))
            scale: control._scale
        }
        Rectangle {
            visible: control.mixed
            anchors.centerIn: parent
            width: Metrics.checkboxIconSize - 4
            height: 2
            radius: 1
            color: control.enabled ? Theme.colors.inkOnAccent : Theme.colors.pane
        }
        MeridianIcon {
            visible: !control.mixed && control._check > 0
            anchors.centerIn: parent
            name: "check"
            extent: Metrics.checkboxIconSize
            color: control.enabled ? Theme.colors.inkOnAccent : Theme.colors.pane
            opacity: Math.min(1, control._check)
            scale: 0.6 + 0.4 * control._check
        }
        MeridianFocusRing {
            target: parent
            shown: control.visualFocus
            targetRadius: Metrics.checkboxRadius
        }
    }

    contentItem: Item {
        implicitWidth: Math.max(labelText.implicitWidth, descriptionText.visible ? descriptionText.implicitWidth : 0)
        implicitHeight: labelText.height + (descriptionText.visible ? descriptionText.height : 0)
        MeridianText {
            id: labelText
            width: parent.width
            anchors.verticalCenter: descriptionText.visible ? undefined : parent.verticalCenter
            text: control.text
            color: control.enabled ? Theme.colors.ink : Theme.colors.inkFaint
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        MeridianText {
            id: descriptionText
            y: labelText.height
            width: parent.width
            visible: control.description.length > 0
            role: MeridianText.Caption
            text: control.description
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
    }
}
