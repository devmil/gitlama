import QtQuick

// A one-time fade and rise (`rise-content`, `motion-select`) when a keyed item first appears
// (Flutter: MeridianEntrance; MM-24, MM-67). `order` (Flutter: index) staggers the start by `motion-stagger`,
// at most `stagger-max` - 1 steps; `delay` waits before that. Keys are remembered in
// MeridianMotionMemory, so a recycled row or a re-created view shows its content at rest.
// An empty key shows the content at rest. Reduce motion: no entrance.
//
// Put one item inside; the entrance takes its size.
Item {
    id: root

    /// What appears; the entrance plays the first time a key is set.
    property string entranceKey: ""
    property int order: 0
    property int delay: 0
    /// The rise in pixels; -1 uses `rise-content`.
    property real rise: -1
    default property alias content: holder.data

    readonly property Item _child: holder.children.length > 0 ? holder.children[0] : null
    property real _t: 1

    implicitWidth: _child ? _child.implicitWidth : 0
    implicitHeight: _child ? _child.implicitHeight : 0

    Component.onCompleted: _start()
    onEntranceKeyChanged: _start()

    property string _startedKey: ""

    function _start() {
        // Creation sets the key and completes; the entrance starts once for it.
        if (entranceKey === _startedKey)
            return
        _startedKey = entranceKey
        if (entranceKey.length === 0 || !MeridianMotionMemory.markSeen(entranceKey) || Motion.reduced) {
            entrance.stop()
            _t = 1
            return
        }
        wait.duration = delay + Motion.staggerDelay(order)
        _t = 0
        entrance.restart()
    }

    SequentialAnimation {
        id: entrance
        PauseAnimation { id: wait }
        NumberAnimation {
            target: root
            property: "_t"
            to: 1
            duration: Motion.select
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.standard
        }
    }

    Item {
        id: holder
        anchors.fill: parent
        opacity: root._t
        transform: Translate { y: (root.rise >= 0 ? root.rise : Motion.riseContent) * (1 - root._t) }
    }
}
