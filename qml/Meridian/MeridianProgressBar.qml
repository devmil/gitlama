import QtQuick

// A 2px `accent` rule. Indeterminate (a sliding 30% bar) until `value` is
// known, then determinate. At 100% it holds `motion-progress-hold` and fades
// unless `persistent`. Give it a bounded width.
Item {
    id: root

    /// 0..1, or a negative number while indeterminate.
    property real value: -1
    /// Paint a `line` track (a standalone bar). Off along an edge.
    property bool track: false
    property bool persistent: false
    readonly property bool indeterminate: value < 0
    readonly property real clamped: Math.max(0, Math.min(1, value))
    /// The shown fraction: animates towards `clamped`. The bar's width follows the
    /// bar's own width at once, so resizing a window does not animate (and repaint) it.
    property real _shown: clamped
    Behavior on _shown {
        enabled: !root.indeterminate
        NumberAnimation { duration: Motion.emphasized; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
    }
    property bool _done: false

    implicitHeight: Metrics.progressHeight
    implicitWidth: 120
    clip: true
    Accessible.role: Accessible.ProgressBar
    Accessible.name: indeterminate ? "" : Math.round(clamped * 100) + "%"

    onValueChanged: {
        _done = false
        hold.stop()
        if (value >= 1 && !persistent)
            hold.restart()
    }

    Timer {
        id: hold
        interval: Motion.progressHold
        onTriggered: root._done = true
    }

    Rectangle {
        anchors.fill: parent
        visible: root.track
        color: Theme.colors.line
        radius: height / 2
    }

    Rectangle {
        id: bar
        objectName: "progressFill"
        height: parent.height
        radius: height / 2
        color: Theme.colors.accent
        opacity: root._done ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Motion.fade(Motion.exit) } }
        width: root.indeterminate ? root.width * Metrics.progressIndeterminateFraction
                                  : root.width * root._shown
        x: root.indeterminate ? sweep.position * (root.width + width) - width : 0
    }

    QtObject {
        id: sweep
        property real position: Motion.reduced ? 0.5 : 0
        // Holds still with reduce motion.
        property NumberAnimation run: NumberAnimation {
            target: sweep
            property: "position"
            from: 0
            to: 1
            duration: Motion.progress
            easing.type: Easing.InOutQuad
            loops: Animation.Infinite
            running: root.indeterminate && !Motion.reduced && root.visible && Motion.loopsActive
        }
    }
}
