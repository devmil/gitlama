import QtQuick
import QtQuick.Templates as T

// One of mutually exclusive choices (Flutter: MeridianRadio): a round box,
// `accent` filled when chosen with an `on-accent` dot that pops in
// (`spring-pop`). Radios with the same parent are exclusive; `text` is the
// label and `description` a caption under it.
T.RadioButton {
    id: control

    property string description
    readonly property color fill: !enabled ? Theme.colors.pane
        : checked ? (down ? Theme.pressed(Theme.brighten(Theme.colors.accent, Theme.colors.inkOnAccent))
                    : hovered ? Theme.brighten(Theme.colors.accent, Theme.colors.inkOnAccent) : Theme.colors.accent)
        : down ? Theme.pressed(Theme.colors.paneHover) : hovered ? Theme.colors.paneHover : Theme.colors.pane
    property real _dot: checked ? 1 : 0

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    spacing: Metrics.checkboxLabelOffset
    padding: 0
    leftPadding: Metrics.checkboxSize + spacing
    implicitWidth: implicitContentWidth + leftPadding
    implicitHeight: Math.max(Theme.size.minTarget, Metrics.checkboxSize, implicitContentHeight)

    Accessible.role: Accessible.RadioButton
    Accessible.name: text
    Accessible.description: description
    Accessible.checked: checked

    onCheckedChanged: {
        if (checked && !Motion.reduced) {
            _dot = 0
            pop.restart()
        } else {
            pop.stop()
            _dot = checked ? 1 : 0
        }
    }
    NumberAnimation {
        id: pop
        target: control; property: "_dot"; to: 1
        duration: Motion.pop.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.pop.curve
    }

    indicator: Rectangle {
        width: Metrics.checkboxSize
        height: Metrics.checkboxSize
        y: control.description.length > 0 && !Theme.touch
           ? Math.max(0, (Theme.type.bodyLineHeight - height) / 2) : (control.height - height) / 2
        radius: width / 2
        color: control.fill
        border.width: 1
        border.color: !control.enabled ? Theme.colors.line : control.checked ? control.fill
            : control.hovered || control.down ? Theme.colors.inkMuted : Theme.colors.controlEdge
        Behavior on color { ColorAnimation { duration: Motion.select } }
        Rectangle {
            visible: control._dot > 0
            anchors.centerIn: parent
            width: Metrics.radioDot
            height: Metrics.radioDot
            radius: width / 2
            scale: control._dot
            color: control.enabled ? Theme.colors.inkOnAccent : Theme.colors.inkFaint
        }
        MeridianFocusRing {
            target: parent
            shown: control.visualFocus
            targetRadius: parent.radius
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
        }
    }
}
