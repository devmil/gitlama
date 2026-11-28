import QtQuick

// A thin usage bar (Flutter: MeridianMeter): `accent` on `line`, `warning`
// and `danger` above their thresholds. `animated: false` for sampled
// telemetry, which updates in the sample frame instead of easing between
// polls.
Item {
    id: root

    /// 0–1.
    property real value: 0
    property real warningAt: -1
    property real dangerAt: -1
    /// Overrides the fill (a `series` colour, or ink on a strong selection).
    property color color: "transparent"
    property bool animated: true

    readonly property real clamped: Math.max(0, Math.min(1, value))
    readonly property color fillColor: color.a > 0 ? color
        : dangerAt >= 0 && clamped >= dangerAt ? Theme.colors.danger
        : warningAt >= 0 && clamped >= warningAt ? Theme.colors.warning
        : Theme.colors.accent

    implicitWidth: 64
    implicitHeight: Metrics.meterHeight
    Accessible.ignored: true

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Metrics.meterHeight
        radius: height / 2
        color: Theme.colors.line
        clip: true
        Rectangle {
            height: parent.height
            width: parent.width * root.clamped
            radius: height / 2
            color: root.fillColor
            Behavior on width {
                enabled: root.animated
                NumberAnimation { duration: Motion.emphasized; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
            }
        }
    }
}
