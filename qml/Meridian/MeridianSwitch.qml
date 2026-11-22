import QtQuick
import QtQuick.Templates as T

// A setting that applies straight away (Flutter: MeridianSwitch). `text` is
// the label and the accessible name; `description` is a caption under it.
// The switch confirms the change itself: no Save button, no toast.
T.Switch {
    id: control

    property string description
    /// A settings row already shows the label.
    property bool showLabel: true
    /// Label at the start and the track at the end (touch settings lists).
    property bool labelFirst: false

    readonly property real trackWidth: Theme.touch ? Metrics.switchWidth * 1.4 : Metrics.switchWidth
    readonly property real trackHeight: Theme.touch ? Metrics.switchHeight * 1.4 : Metrics.switchHeight
    readonly property real thumbSize: trackHeight - 2 * Metrics.switchThumbInset

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    spacing: Theme.space.s4
    padding: 0
    readonly property real _indicatorSpace: trackWidth + (showLabel ? spacing : 0)
    leftPadding: showLabel && labelFirst ? 0 : _indicatorSpace
    rightPadding: showLabel && labelFirst ? _indicatorSpace : 0
    implicitWidth: showLabel ? implicitContentWidth + leftPadding + rightPadding : trackWidth
    implicitHeight: Math.max(Theme.size.minTarget, trackHeight, showLabel ? implicitContentHeight : 0)

    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.description: description
    Accessible.checked: checked

    indicator: Rectangle {
        id: track
        objectName: "switchTrack"
        x: control.labelFirst && control.showLabel ? control.width - width : 0
        y: control.showLabel && control.implicitContentHeight > Theme.type.bodyLineHeight
           ? Math.max(0, (Theme.type.bodyLineHeight - height) / 2) : (control.height - height) / 2
        width: control.trackWidth
        height: control.trackHeight
        radius: height / 2
        color: !control.enabled ? Theme.colors.line
             : control.checked ? (control.hovered ? Theme.brighten(Theme.colors.accent, Theme.colors.inkOnAccent) : Theme.colors.accent)
             : (control.hovered ? Theme.pressed(Theme.colors.lineStrong) : Theme.colors.lineStrong)
        border.width: control.checked ? 0 : 1
        border.color: Theme.colors.controlEdge
        Behavior on color { ColorAnimation { duration: Motion.select } }

        Rectangle {
            id: thumb
            objectName: "switchThumb"
            readonly property real stretch: control.down ? Metrics.switchThumbStretch : 0
            y: Metrics.switchThumbInset
            height: control.thumbSize
            width: control.thumbSize + stretch
            radius: height / 2
            color: Theme.colors.pane
            x: control.checked ? track.width - Metrics.switchThumbInset - width : Metrics.switchThumbInset
            Behavior on x {
                NumberAnimation { duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve }
            }
            Behavior on width {
                NumberAnimation { duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve }
            }
        }

        MeridianFocusRing {
            target: control
            shown: control.visualFocus
            x: -_outset
            y: -_outset
            width: track.width + 2 * _outset
            height: track.height + 2 * _outset
            targetRadius: track.radius
        }
    }

    contentItem: Item {
        visible: control.showLabel
        implicitWidth: Math.max(labelText.implicitWidth, descriptionText.visible ? descriptionText.implicitWidth : 0)
        implicitHeight: labelText.height + (descriptionText.visible ? descriptionText.height : 0)
        MeridianText {
            id: labelText
            width: parent.width
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
