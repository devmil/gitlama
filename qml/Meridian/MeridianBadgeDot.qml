import QtQuick

// A toolbar badge (Flutter: the toolbar badge, MM-06): a small count pill
// that pops in on `spring-pop`, rolls its number, and shrinks and fades away
// over `motion-exit` when it goes. Hidden at zero.
Item {
    id: root
    property int count: 0
    property int tone: MeridianCount.Accent
    /// The count shown while the badge leaves.
    property int _shown: count
    property bool _present: count > 0

    implicitWidth: _shown > 0 ? pill.implicitWidth : 0
    implicitHeight: _shown > 0 ? pill.implicitHeight : 0
    visible: _shown > 0 && opacity > 0

    onCountChanged: {
        if (count > 0) {
            const appearing = !_present
            _present = true
            _shown = count
            leave.stop()
            if (appearing && !Motion.reduced) {
                pill.scale = 0
                opacity = 0
                pop.restart()
            } else {
                pill.scale = 1
                opacity = 1
            }
        } else if (_present) {
            _present = false
            if (Motion.reduced) {
                _shown = 0
                return
            }
            pop.stop()
            leave.restart()
        }
    }

    MeridianCount {
        id: pill
        tone: root.tone
        label: root._shown > 99 ? "99+" : String(root._shown)
    }

    ParallelAnimation {
        id: pop
        NumberAnimation { target: pill; property: "scale"; to: 1; duration: Motion.pop.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.pop.curve }
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: Motion.quick; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
    }
    SequentialAnimation {
        id: leave
        ParallelAnimation {
            NumberAnimation { target: pill; property: "scale"; to: Metrics.opacityBadgeLeaveScale; duration: Motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve }
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve }
        }
        ScriptAction { script: { if (root.count === 0) root._shown = 0 } }
    }
}
