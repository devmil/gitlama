pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The Compass's activity wash behind its text (NM-01): while an operation
// runs, the pill rests at a light `accent-soft` tint; a band with an `accent`
// crest sweeps across it while Git cannot tell the progress, and `accent-soft`
// fills it from its leading end to the progress once it can. When the
// operation ends the pill fills to 100%, a highlight crosses it once, it holds
// and fades (NH-2, MM-63). Every piece is a full-size rounded copy of the pill
// (clipped for the fill, a gradient for the bands), so the wash keeps the
// pill's rounded ends without a layer (a layer drew the text above it through
// a texture and blurred it).
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
    // Fills grow; new work after a finish starts empty instead of retracting.
    Behavior on _fraction {
        enabled: fill.shown && !Motion.reduced && fill._target >= fill._fraction
        NumberAnimation { duration: Motion.emphasized; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
    }
    readonly property color _crest: Theme.blend(Theme.colors.accentSoft, Theme.colors.accent,
                                                GitLamaLayout.compassFillCrest)
    readonly property color _shine: Theme.blend(Theme.colors.accentSoft, Theme.colors.accent,
                                                2 * GitLamaLayout.compassFillCrest)

    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.fade(fill.shown ? Motion.quick : Motion.exit) } }

    Accessible.role: Accessible.ProgressBar
    Accessible.name: indeterminate ? "" : Math.round(_target * 100) + "%"

    onActiveChanged: {
        finish.stop()
        shine.position = 0
        _finishing = !active && !Motion.reduced
        if (_finishing)
            finish.restart()
    }
    // Fill, one highlight across the full pill, hold; then the wash fades.
    SequentialAnimation {
        id: finish
        PauseAnimation { duration: Motion.emphasized }
        NumberAnimation {
            target: shine
            property: "position"
            from: 0
            to: 1
            duration: GitLamaLayout.compassFillShine
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.standard
        }
        PauseAnimation { duration: GitLamaLayout.compassFillFinishHold }
        ScriptAction { script: fill._finishing = false }
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

    // A soft (raised-cosine) band of `peak` at `position` (0: just before the
    // leading end, 1: just past the trailing end) on a rounded copy of the
    // pill. Stops outside the pill clamp to its ends with the band's value
    // there, so the band keeps the rounded ends.
    component Band: Rectangle {
        id: band
        property real position: 0
        property real span: GitLamaLayout.compassFillBandFraction
        property color peak: Theme.colors.accentSoft
        readonly property real start: position * (1 + span) - span
        readonly property int steps: 6

        anchors.fill: parent
        radius: fill.radius
        visible: opacity > 0

        function at(k) {
            return Math.max(0, Math.min(1, start + span * k / steps))
        }
        function tint(x) {
            const t = (x - start) / span * steps
            if (t <= 0 || t >= steps)
                return Theme.clear(peak)
            const i = Math.floor(t)
            const a = Math.pow(Math.sin(Math.PI * i / steps), 2)
            const b = Math.pow(Math.sin(Math.PI * (i + 1) / steps), 2)
            return Qt.rgba(peak.r, peak.g, peak.b, a + (b - a) * (t - i))
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

    // The resting tint: the pill reads as busy whatever the band is doing.
    Wash {
        objectName: "compassFillRest"
        width: fill.width
        alpha: GitLamaLayout.compassFillRest
    }

    Wash {
        objectName: "compassFillExtent"
        width: fill.width * fill._fraction
    }

    // The sweep while progress is unknown. It runs linearly and enters again
    // as soon as it leaves, so it never rests out of sight.
    Band {
        objectName: "compassFillSweep"
        peak: fill._crest
        position: sweep.position
        opacity: fill.indeterminate ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fade(Motion.quick) } }
    }

    // The finish highlight across the filled pill.
    Band {
        id: shineBand
        objectName: "compassFillShine"
        peak: fill._shine
        span: GitLamaLayout.compassFillShineFraction
        position: shine.position
        opacity: fill._finishing && shine.position > 0 && shine.position < 1 ? 1 : 0
    }

    QtObject {
        id: shine
        property real position: 0
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
            loops: Animation.Infinite
            running: fill.indeterminate && fill.visible && !Motion.reduced && Motion.loopsActive
            onRunningChanged: if (!running) sweep.position = 0.5
        }
    }
}
