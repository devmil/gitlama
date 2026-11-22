import QtQuick
import QtQuick.Shapes

// A 12px spinner that replaces an icon while something runs. It waits
// `motion-spinner-delay` before it shows, so fast work never flashes, and
// turns once per 700ms (2s with reduce motion: essential, so it keeps moving).
Item {
    id: root

    property bool running: true
    property real size: Metrics.spinnerSize
    property color color: Theme.colors.inkMuted
    /// Skip the appearance delay (the spinner is the whole content).
    property bool immediate: false
    readonly property bool shown: running && (immediate || delay.elapsed)

    implicitWidth: size
    implicitHeight: size
    Accessible.role: Accessible.Animation
    Accessible.ignored: !shown

    Timer {
        id: delay
        property bool elapsed: false
        interval: Motion.spinnerDelay
        running: root.running && !root.immediate
        onTriggered: elapsed = true
    }
    // A one-shot timer stops itself when it fires, so reset on the spinner's
    // own state, not the timer's.
    onRunningChanged: if (!running) delay.elapsed = false

    Shape {
        id: arc
        objectName: "spinnerArc"
        anchors.fill: parent
        opacity: root.shown ? 1 : 0
        visible: opacity > 0
        preferredRendererType: Shape.CurveRenderer
        Behavior on opacity { NumberAnimation { duration: Motion.fade(Motion.quick) } }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: Metrics.spinnerStroke
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: (root.size - Metrics.spinnerStroke) / 2
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 270
            }
        }
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: Motion.spinner
            loops: Animation.Infinite
            running: root.shown && root.visible
        }
    }
}
