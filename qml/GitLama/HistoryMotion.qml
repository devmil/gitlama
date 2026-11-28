import QtQuick
import Meridian

// The History graph's motion (docs/design-system/specs/motion.md): lane lighting flowing down
// from the focused commit (NH-3), lanes drawing in on first load, after a pull and for a new
// working-tree row (NH-2, NH-7), a new commit's node landing (NH-1) and rows sliding when one
// is inserted or removed (NH-1, NM-36). One clock drives every row; rows read their values
// from here while it runs. The next input finishes every effect at once (`finishAll`).
Item {
    id: motion

    /// Milliseconds on the motion clock; advances only while an effect runs.
    property real now: 0
    readonly property bool reduced: Motion.reduced

    // ---------------------------------------------------------------- clock

    property real _drawEnd: 0
    property real _insertEnd: 0
    readonly property bool running: now < _drawEnd || now < _insertEnd

    FrameAnimation {
        id: clock
        running: motion.running
        onTriggered: motion.now += frameTime * 1000
    }

    // ---------------------------------------------------------------- lighting

    property int _focusIndex: -1
    property bool _returning: false
    property bool _instant: true
    property real _lastLightChange: 0

    /// The lit ancestry changed (a new selection lights its path, or lighting ended): rows
    /// whose lighting differs light up flowing down from `focusIndex` (`laneFlowStep` per row,
    /// at most `laneFlowMaxRows`), or dim over `laneDim`; when lighting ends everything returns
    /// over `motion-hover-out` at once. Changes faster than `detailDebounce` apart (keyboard
    /// scrubbing) and reduce motion switch at once.
    function lightingChanged(focusIndex, active) {
        const time = Date.now()
        _instant = reduced || (_lastLightChange > 0 && time - _lastLightChange < GitLamaLayout.detailDebounce)
        _lastLightChange = time
        _focusIndex = focusIndex
        _returning = !active
    }

    /// The delay and duration of row `index`'s lighting transition, or null when it switches
    /// at once.
    function lightingTiming(index) {
        if (_instant)
            return null
        if (_returning)
            return { delay: 0, duration: Motion.hoverOut }
        const distance = _focusIndex < 0 || index <= _focusIndex ? 0
            : Math.min(index - _focusIndex, GitLamaLayout.laneFlowMaxRows)
        return { delay: GitLamaLayout.laneFlowStep * distance, duration: GitLamaLayout.laneDim }
    }

    // ---------------------------------------------------------------- drawing

    property int _drawFirst: 0
    property int _drawCount: 0
    property real _drawStart: 0

    /// Draws the lanes of rows `firstIndex` to `firstIndex + count - 1` in from the top
    /// (`laneDrawStep` apart, `laneDrawRow` each, at most `laneDrawMaxRows` rows; the rest
    /// appear at once), after `delay`.
    function drawLanes(firstIndex, count, delay) {
        if (reduced || count <= 0) {
            _drawCount = 0
            return
        }
        _drawFirst = firstIndex
        _drawCount = Math.min(count, GitLamaLayout.laneDrawMaxRows)
        _drawStart = now + (delay ?? 0)
        _drawEnd = _drawStart + GitLamaLayout.laneDrawStep * (_drawCount - 1) + GitLamaLayout.laneDrawRow
    }

    /// How much of row `index`'s graph is drawn, 0..1 from the top; 1 when no draw runs.
    function drawProgress(index) {
        if (_drawCount === 0 || now >= _drawEnd)
            return 1
        const offset = index - _drawFirst
        if (offset < 0 || offset >= _drawCount)
            return 1
        const elapsed = now - (_drawStart + GitLamaLayout.laneDrawStep * offset)
        if (elapsed <= 0)
            return 0
        return _standard(Math.min(1, elapsed / GitLamaLayout.laneDrawRow))
    }

    // ---------------------------------------------------------------- landing

    property string landingId: ""
    property real ringClose: 0
    property real ringOpacity: 0
    property real core: 0
    property real halo: 0

    /// NH-1: the node of the new commit `objectId` lands: its temporary ring closes over
    /// `landRingClose`, then the core pops (`spring-pop`) and the HEAD halo grows
    /// (`spring-snappy`); the ring fades by `commitLand`.
    function landCommit(objectId) {
        landing.stop()
        if (reduced) {
            landingId = ""
            return
        }
        ringClose = 0
        ringOpacity = 1
        core = 0
        halo = 0
        landingId = objectId
        landing.restart()
    }

    ParallelAnimation {
        id: landing
        onFinished: motion.landingId = ""
        NumberAnimation {
            target: motion; property: "ringClose"; from: 0; to: 1
            duration: GitLamaLayout.landRingClose
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard
        }
        SequentialAnimation {
            PauseAnimation { duration: GitLamaLayout.landRingClose }
            NumberAnimation {
                target: motion; property: "ringOpacity"; from: 1; to: 0
                duration: GitLamaLayout.commitLand - GitLamaLayout.landRingClose
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: GitLamaLayout.landRingClose }
            NumberAnimation {
                target: motion; property: "core"; from: 0; to: 1
                duration: Motion.pop.duration
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.pop.curve
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: GitLamaLayout.landRingClose }
            NumberAnimation {
                target: motion; property: "halo"; from: 0; to: 1
                duration: Motion.snappy.duration
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve
            }
        }
    }

    // ---------------------------------------------------------------- insert

    property int _insertIndex: -1
    property int _insertDirection: 1
    property real _insertStart: 0

    /// A row was inserted at `index`: rows from it down slide from their old places over
    /// `motion-layout` and the new row fades in over `motion-select`.
    function insertRow(index) { _shift(index, 1) }
    /// The row at `index` went away: the rows below slide up from their old places.
    function removeRow(index) { _shift(index, -1) }

    function _shift(index, direction) {
        if (reduced) {
            _insertIndex = -1
            return
        }
        _insertIndex = index
        _insertDirection = direction
        _insertStart = now
        _insertEnd = now + Motion.layout
    }

    /// How many rows row `index` still sits from its place (positive is above).
    function insertionShift(index) {
        if (_insertIndex < 0 || now >= _insertEnd || index < _insertIndex)
            return 0
        const moved = _standard(Math.min(1, (now - _insertStart) / Motion.layout))
        return _insertDirection * (1 - moved)
    }

    /// An inserted row's opacity.
    function insertionOpacity(index) {
        if (_insertIndex < 0 || now >= _insertEnd || index !== _insertIndex || _insertDirection < 0)
            return 1
        return _standard(Math.min(1, (now - _insertStart) / Motion.select))
    }

    // ---------------------------------------------------------------- control

    /// Jumps every running effect to its end state.
    function finishAll() {
        _drawCount = 0
        _insertIndex = -1
        _drawEnd = now
        _insertEnd = now
        landing.complete()
        landingId = ""
    }

    // Meridian's standard curve (cubic-bezier 0.2, 0, 0, 1) for values the clock computes.
    function _standard(t) {
        const c = Motion.standard
        if (c.length < 6 || reduced)
            return t
        let lo = 0, hi = 1, s = t
        for (let i = 0; i < 12; ++i) {
            s = (lo + hi) / 2
            const x = 3 * (1 - s) * (1 - s) * s * c[0] + 3 * (1 - s) * s * s * c[2] + s * s * s
            if (x < t) lo = s; else hi = s
        }
        return 3 * (1 - s) * (1 - s) * s * c[1] + 3 * (1 - s) * s * s * c[3] + s * s * s
    }
}
