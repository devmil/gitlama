import QtQuick
import QtQuick.Templates as T

// A continuous or stepped value (Flutter: MeridianSlider): a 4px
// `line-strong` track filled with `accent`, a `pane` thumb with an `accent`
// edge that grows while hovered or dragged. Arrow keys step, Home and End
// jump to the ends. `valueLabel(value)` is announced.
T.Slider {
    id: control

    property string label
    /// Colours along the track (a colour channel); the track then shows
    /// them instead of the `accent` fill.
    property var trackColors: []
    property var valueLabel: function (v) { return Math.round((v - from) / Math.max(1e-9, to - from) * 100) + "%" }
    readonly property real thumbSize: Theme.touch ? Metrics.sliderThumbTouch : Metrics.sliderThumb
    readonly property bool emphasis: enabled && (hovered || pressed)

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    implicitWidth: Metrics.sliderDefaultWidth
    implicitHeight: Math.max(Theme.size.control, Theme.size.minTarget)
    padding: 0
    leftPadding: 0
    rightPadding: 0
    live: true
    snapMode: stepSize > 0 ? T.Slider.SnapAlways : T.Slider.NoSnap

    Accessible.role: Accessible.Slider
    Accessible.name: label
    Accessible.description: valueLabel(value)

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) { value = from; moved(); event.accepted = true }
        else if (event.key === Qt.Key_End) { value = to; moved(); event.accepted = true }
    }

    background: Item {
        x: control.thumbSize / 2
        y: (control.height - height) / 2
        width: control.width - control.thumbSize
        height: Metrics.sliderTrack
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.colors.lineStrong
            visible: control.trackColors.length === 0
        }
        Canvas {
            id: trackCanvas
            visible: control.trackColors.length > 0
            anchors.fill: parent
            opacity: control.enabled ? 1 : 0.4
            onPaint: {
                const context = getContext("2d")
                context.reset()
                const colors = control.trackColors
                if (colors.length === 0)
                    return
                const gradient = context.createLinearGradient(0, 0, width, 0)
                for (let i = 0; i < colors.length; ++i)
                    gradient.addColorStop(i / Math.max(1, colors.length - 1), String(colors[i]))
                const r = height / 2
                context.beginPath()
                context.moveTo(r, 0)
                context.lineTo(width - r, 0)
                context.arc(width - r, r, r, -Math.PI / 2, Math.PI / 2, false)
                context.lineTo(r, height)
                context.arc(r, r, r, Math.PI / 2, 3 * Math.PI / 2, false)
                context.closePath()
                context.fillStyle = gradient
                context.fill()
            }
            onWidthChanged: requestPaint()
            Connections {
                target: control
                function onTrackColorsChanged() { trackCanvas.requestPaint() }
            }
        }
        Rectangle {
            visible: control.trackColors.length === 0
            width: parent.width * control.visualPosition
            height: parent.height
            radius: height / 2
            color: control.enabled ? Theme.colors.accent : Theme.colors.inkFaint
        }
    }

    handle: Rectangle {
        x: control.visualPosition * (control.width - control.thumbSize)
        y: (control.height - height) / 2
        width: control.thumbSize
        height: control.thumbSize
        radius: width / 2
        color: control.enabled && control.pressed ? Theme.pressed(Theme.colors.pane) : Theme.colors.pane
        border.width: control.emphasis ? Metrics.sliderThumbBorderActive : Metrics.sliderThumbBorder
        border.color: control.enabled ? Theme.colors.accent : Theme.colors.inkFaint
        scale: control.emphasis && !Motion.reduced ? Metrics.sliderThumbActiveScale : 1
        Behavior on scale { NumberAnimation { duration: Motion.quick; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard } }
        MeridianFocusRing {
            target: parent
            shown: control.visualFocus
            targetRadius: parent.radius
        }
    }
}
