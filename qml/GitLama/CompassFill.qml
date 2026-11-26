pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The Compass's activity wash behind its text (NM-01): while an operation
// runs, `accent-soft` fills the pill from its leading end to the known
// progress, or a soft band sweeps across while it cannot tell. When the
// operation ends it fills to 100%, holds `motion-progress-hold` and fades
// (NH-2, MM-63). The fill clips a full-size rounded copy of the pill and the
// band is a gradient on one, so both keep the pill's rounded ends without a
// layer (a layer drew the text above them through a texture and blurred it).
Item {
    id: fill

    property bool active: false
    /// 0..1, or -1 while it cannot tell.
    property real progress: -1
    property real radius: height / 2
    property bool _finishing: false
    readonly property bool shown: active || _finishing
    readonly property bool indeterminate: !_finishing && progress < 0
    readonly property real _target: _finishing ? 1 : indeterminate ? 0 : Math.max(0, Math.min(1, progress))
    /// The filled fraction; animated as a fraction so a resizing window does not lag it.
    property real _fraction: _target
    Behavior on _fraction {
        enabled: fill.shown && !Motion.reduced
        NumberAnimation { duration: Motion.emphasized; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
    }

    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.fade(fill.shown ? Motion.quick : Motion.exit) } }

    Accessible.role: Accessible.ProgressBar
    Accessible.name: indeterminate ? "" : Math.round(_target * 100) + "%"

    onActiveChanged: {
        finish.stop()
        _finishing = !active && !Motion.reduced
        if (_finishing)
            finish.restart()
    }
    Timer {
        id: finish
        interval: Motion.emphasized + Motion.progressHold
        onTriggered: fill._finishing = false
    }

    component Wash: Item {
        id: wash
        height: fill.height
        clip: true
        property real alpha: 1
        Rectangle {
            x: -wash.x
            width: fill.width
            height: fill.height
            radius: fill.radius
            color: Theme.colors.accentSoft
            opacity: wash.alpha
        }
    }

    Wash {
        objectName: "compassFillExtent"
        width: fill.width * fill._fraction
    }

    // The sweep: one rounded copy of the pill with a horizontal gradient whose
    // soft (raised-cosine) band moves across it. Stops outside the pill clamp to
    // its ends with the band's value there, so the band keeps the rounded ends.
    Rectangle {
        id: band
        anchors.fill: parent
        radius: fill.radius
        opacity: fill.indeterminate ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Motion.fade(Motion.quick) } }
        readonly property real span: GitLamaLayout.compassFillBandFraction
        readonly property real start: sweep.position * (1 + span) - span
        readonly property int steps: 6

        function at(k) {
            return Math.max(0, Math.min(1, start + span * k / steps))
        }
        function tint(x) {
            const t = (x - start) / span * steps
            if (t <= 0 || t >= steps)
                return Theme.clear(Theme.colors.accentSoft)
            const i = Math.floor(t)
            const a = Math.pow(Math.sin(Math.PI * i / steps), 2)
            const b = Math.pow(Math.sin(Math.PI * (i + 1) / steps), 2)
            const c = Theme.colors.accentSoft
            return Qt.rgba(c.r, c.g, c.b, a + (b - a) * (t - i))
        }

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: band.tint(0) }
            GradientStop { position: band.at(0); color: band.tint(band.at(0)) }
            GradientStop { position: band.at(1); color: band.tint(band.at(1)) }
            GradientStop { position: band.at(2); color: band.tint(band.at(2)) }
            GradientStop { position: band.at(3); color: band.tint(band.at(3)) }
            GradientStop { position: band.at(4); color: band.tint(band.at(4)) }
            GradientStop { position: band.at(5); color: band.tint(band.at(5)) }
            GradientStop { position: band.at(6); color: band.tint(band.at(6)) }
            GradientStop { position: 1; color: band.tint(1) }
        }
    }

    QtObject {
        id: sweep
        // Holds still with reduce motion.
        property real position: 0.5
        property NumberAnimation run: NumberAnimation {
            target: sweep
            property: "position"
            from: 0
            to: 1
            duration: GitLamaLayout.compassFillSweep
            easing.type: Easing.InOutQuad
            loops: Animation.Infinite
            running: fill.indeterminate && fill.visible && !Motion.reduced && Motion.loopsActive
            onRunningChanged: if (!running) sweep.position = 0.5
        }
    }
}
