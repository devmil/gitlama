import QtQuick

// Keeps a removed row painted while it fades over `motion-exit` and collapses over
// `motion-layout`, then emits `removed` so the owner can drop it (Flutter:
// MeridianRemovingRow; MM-22). It starts on creation, or on `start()` when `autoStart` is
// false: a ListView delegate calls it from `ListView.onRemove` with `ListView.delayRemove`
// set, and clears that on `removed`. `delay` waits first, for a short bottom-up batch.
// Reduce motion removes at once.
//
// Put one item inside; the row takes its implicit size on the axis.
Item {
    id: root

    property int axis: MeridianReveal.Vertical
    /// Wait before the removal starts.
    property int delay: 0
    property bool autoStart: true
    /// Whether the removal started.
    readonly property bool removing: _started
    default property alias content: reveal.content
    signal removed()

    property bool _started: false

    implicitWidth: reveal.implicitWidth
    implicitHeight: reveal.implicitHeight
    clip: reveal.clip

    // After creation, like a post-frame start, so the reveal inside has settled first.
    Component.onCompleted: if (autoStart) Qt.callLater(() => root.start())

    /// Starts the removal; later calls do nothing.
    function start() {
        if (_started)
            return
        _started = true
        if (delay > 0 && !Motion.reduced)
            wait.start()
        else
            reveal.shown = false
    }

    /// Restores the row to its initial unremoved state (for reused ListView delegates).
    function reset() {
        wait.stop()
        _started = false
        reveal.resetShown()
    }

    Timer {
        id: wait
        interval: root.delay
        onTriggered: reveal.shown = false
    }

    MeridianReveal {
        id: reveal
        axis: root.axis
        onHidden: root.removed()
    }
}
