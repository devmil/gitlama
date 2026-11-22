import QtQuick

// Shows MeridianToasts at the bottom of its area (put it over the window's
// content, or in the root window when a result outlives its surface). One
// toast at a time; a new one replaces the current. Hovering or focusing it
// pauses the countdown. `show` returns the toast's id; `actionTriggered`
// reports that id, so the caller can match the Undo to its operation.
Item {
    id: host

    property int nextId: 1
    property int currentId: 0
    property string message
    property int tone: MeridianToast.Neutral
    property string actionLabel
    property bool showing: false
    property real elapsed: 0
    readonly property int duration: actionLabel.length > 0 ? Motion.toastAction : Motion.toast

    signal actionTriggered(int toastId)
    signal dismissed(int toastId)

    function show(text, toneValue, action) {
        message = text
        tone = toneValue === undefined ? MeridianToast.Neutral : toneValue
        actionLabel = action ?? ""
        elapsed = 0
        currentId = nextId++
        showing = true
        return currentId
    }

    function hide() {
        if (!showing)
            return
        showing = false
        dismissed(currentId)
    }

    Timer {
        interval: 50
        repeat: true
        running: host.showing && !toast.paused
        onTriggered: {
            host.elapsed += interval
            if (host.elapsed >= host.duration)
                host.hide()
        }
    }

    MeridianToast {
        id: toast
        objectName: "toast"
        message: host.message
        tone: host.tone
        actionLabel: host.actionLabel
        remaining: Math.max(0, 1 - host.elapsed / host.duration)
        x: host.width - width - Theme.space.s6 + offset
        y: host.height - height - Theme.space.s6 + rise
        width: Math.min(implicitWidth, host.width - 2 * Theme.space.s6)
        property real rise: host.showing ? 0 : Motion.offsetToast
        property real offset: host.showing ? 0 : Motion.offsetToast
        opacity: host.showing ? 1 : 0
        visible: opacity > 0
        Behavior on rise { NumberAnimation { duration: host.showing ? Motion.gentle.duration : Motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: host.showing ? Motion.gentle.curve : Motion.exitCurve } }
        Behavior on offset { NumberAnimation { duration: host.showing ? Motion.gentle.duration : Motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: host.showing ? Motion.gentle.curve : Motion.exitCurve } }
        Behavior on opacity { NumberAnimation { duration: Motion.fade(host.showing ? Motion.overlay : Motion.exit) } }
        onActionTriggered: {
            const id = host.currentId
            host.hide()
            host.actionTriggered(id)
        }
    }
}
