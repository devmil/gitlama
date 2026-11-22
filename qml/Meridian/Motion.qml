pragma Singleton
import QtQuick

// Meridian's motion tokens with reduce-motion substitution
// (design/project/guides/40-motion.md).
//
// Every primitive takes its durations and curves from here, so reduce motion
// is honoured everywhere: movement becomes an instant state change, or a
// crossfade of at most `reducedFade` ms through `fade()`. Springs, shakes,
// pulses, pops and staggers are off.
//
// A zero duration must still reach the terminal state. Animate the property
// itself (Behavior or a NumberAnimation `to:` value). Never scale a reveal
// by the duration.
QtObject {
    id: motion

    readonly property bool reduced: Theme.reducedMotion

    // Durations in ms; zero under reduce motion.
    readonly property int hover: _d("hover")
    readonly property int hoverOut: _d("hoverOut")
    readonly property int press: _d("press")
    readonly property int quick: _d("quick")
    readonly property int select: _d("select")
    readonly property int exit: _d("exit")
    readonly property int overlay: _d("overlay")
    readonly property int dialog: _d("dialog")
    readonly property int layout: _d("layout")
    readonly property int sheet: _d("sheet")
    readonly property int emphasized: _d("emphasized")
    readonly property int highlight: _d("highlight")
    readonly property int celebrate: _d("celebrate")
    readonly property int attention: _d("attention")
    readonly property int nudge: _d("nudge")
    readonly property int shakeField: _d("shakeField")
    readonly property int shakeSurface: _d("shakeSurface")
    readonly property int stagger: _d("stagger")
    readonly property int pulse: _d("pulse")
    readonly property int skeletonPulse: _d("skeletonPulse")
    readonly property int march: _d("march")

    // Waits and holds are not motion: they keep their value.
    readonly property int reducedFade: Tokens.durations.reducedFade
    readonly property int spinnerDelay: Tokens.durations.spinnerDelay
    readonly property int skeletonDelay: Tokens.durations.skeletonDelay
    readonly property int hold: Tokens.durations.hold
    readonly property int progressHold: Tokens.durations.progressHold
    readonly property int tooltipWait: Tokens.durations.tooltipWait
    readonly property int tooltipWarm: Tokens.durations.tooltipWarm
    readonly property int toast: Tokens.durations.toast
    readonly property int toastAction: Tokens.durations.toastAction
    /// Essential indicators keep moving under reduce motion, more slowly.
    readonly property int spinner: reduced ? Tokens.durations.spinnerReduced : Tokens.durations.spinner
    readonly property int progress: Tokens.durations.progress

    // Curves for `easing.type: Easing.BezierSpline`. Linear under reduce motion.
    readonly property var linearCurve: [0, 0, 1, 1, 1, 1]
    readonly property var standard: reduced ? linearCurve : Tokens.curves.standard
    readonly property var enter: reduced ? linearCurve : Tokens.curves.enter
    readonly property var exitCurve: reduced ? linearCurve : Tokens.curves.exit
    readonly property var exitSoft: reduced ? linearCurve : Tokens.curves.exitSoft

    // Springs as a fixed-duration spline through the spring's settle path
    // (stiffness and damping ratio from the tokens, mass 1). Zero duration
    // under reduce motion.
    readonly property SpringSpec snappy: SpringSpec { name: "snappy"; reduced: motion.reduced }
    readonly property SpringSpec gentle: SpringSpec { name: "gentle"; reduced: motion.reduced }
    readonly property SpringSpec pop: SpringSpec { name: "pop"; reduced: motion.reduced }

    // Scales and distances. Under reduce motion, travel and scale collapse to
    // rest so a component that multiplies by them stays put.
    readonly property real pressScale: reduced ? 1 : (Theme.touch ? Tokens.scales.pressTouch : Tokens.scales.press)
    readonly property real overlayEnterScale: reduced ? 1 : Tokens.scales.overlayEnter
    readonly property real dialogEnterScale: reduced ? 1 : Tokens.scales.dialogEnter
    readonly property real popScale: reduced ? 1 : Tokens.scales.pop
    readonly property real liftScale: reduced ? 1 : Tokens.scales.lift
    readonly property real riseOverlay: reduced ? 0 : Tokens.scales.riseOverlay
    readonly property real riseContent: reduced ? 0 : Tokens.scales.riseContent
    readonly property real riseDialog: reduced ? 0 : Tokens.scales.riseDialog
    readonly property real offsetToast: reduced ? 0 : Tokens.scales.offsetToast
    readonly property real nudgeDistance: reduced ? 0 : Tokens.scales.nudge
    readonly property real shakeFieldDistance: reduced ? 0 : Tokens.scales.shakeField
    readonly property real shakeSurfaceDistance: reduced ? 0 : Tokens.scales.shakeSurface
    readonly property int shakeCycles: Tokens.scales.shakeCycles
    readonly property int staggerMax: Tokens.scales.staggerMax
    readonly property real pulseScale: Tokens.scales.pulseScale
    readonly property int glideMaxRows: Tokens.scales.glideMaxRows

    /// The duration of a crossfade that replaces movement: the token, or at
    /// most `reducedFade` under reduce motion.
    function fade(ms) {
        return reduced ? Math.min(ms, reducedFade) : ms
    }

    /// The token `ms`, or zero under reduce motion.
    function duration(ms) {
        return reduced ? 0 : ms
    }

    /// Entrance delay of the item at `index` in a staggered group. Items past
    /// `staggerMax` share the last delay; reduce motion staggers nothing.
    function staggerDelay(index, step) {
        if (reduced)
            return 0
        const s = step === undefined ? Tokens.durations.stagger : step
        return Math.min(Math.max(index, 0), staggerMax - 1) * s
    }

    /// A hover fill fades in fast and out slowly.
    function hoverFor(active) {
        return active ? hover : hoverOut
    }

    function _d(name) {
        return reduced ? 0 : Tokens.durations[name]
    }
}
