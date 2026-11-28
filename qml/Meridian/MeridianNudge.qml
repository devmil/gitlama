import QtQuick

// A one-shot nudge for a command's icon (Flutter: MeridianNudgeIcon): `play()`
// moves it `nudge` px in `direction` over `motion-nudge` and springs back on
// `spring-snappy`; `Rotate` turns it once on `spring-snappy`. It never
// delays the command. Bind the icon's transform to `xOffset`, `yOffset` and
// add `angle` to its rotation. Reduce motion: none.
QtObject {
    id: root

    enum Direction { None, Up, Down, Left, Right, Rotate }

    property int direction: MeridianNudge.None
    property real xOffset: 0
    property real yOffset: 0
    property real angle: 0

    function play() {
        if (direction === MeridianNudge.None || Motion.reduced)
            return
        if (direction === MeridianNudge.Rotate) {
            _turn.restart()
            return
        }
        _move.restart()
    }

    readonly property real _dx: direction === MeridianNudge.Left ? -Motion.nudgeDistance
        : direction === MeridianNudge.Right ? Motion.nudgeDistance : 0
    readonly property real _dy: direction === MeridianNudge.Up ? -Motion.nudgeDistance
        : direction === MeridianNudge.Down ? Motion.nudgeDistance : 0

    property SequentialAnimation _move: SequentialAnimation {
        ParallelAnimation {
            NumberAnimation { target: root; property: "xOffset"; to: root._dx; duration: Motion.nudge; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
            NumberAnimation { target: root; property: "yOffset"; to: root._dy; duration: Motion.nudge; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "xOffset"; to: 0; duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve }
            NumberAnimation { target: root; property: "yOffset"; to: 0; duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve }
        }
    }

    property NumberAnimation _turn: NumberAnimation {
        target: root
        property: "angle"
        from: 0
        to: 360
        duration: Motion.snappy.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.snappy.curve
        onFinished: root.angle = 0
    }
}
