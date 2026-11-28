pragma ComponentBehavior: Bound
import QtQuick

// A number that rolls digit by digit when its value changes (Flutter: MeridianRollingNumber;
// MM-70). Unchanged characters stay still; changed ones roll up for an increase and down for a
// decrease over `motion-quick`, each starting 12 ms (two thirds of `motion-stagger`) after the
// one to its right. With `popOnIncrease` the whole number pops (`pop-scale` -> 1 on
// `spring-pop`) when it grows. Accessibility carries only the final value. Reduce motion
// changes it instantly.
Item {
    id: root

    property int value: 0
    property int role: MeridianText.Body
    property color color: Theme.colors.ink
    property bool popOnIncrease: false
    /// Formats the value; the default is the plain number.
    property var format: null
    /// Replaces the value as the accessible name.
    property string accessibleName: ""

    readonly property string text: _text(value)
    property string _from: ""
    property string _to: _text(value)
    property bool _up: true
    property real _elapsed: 0
    property int _previous: 0
    Component.onCompleted: _previous = value
    readonly property int _digitStagger: Math.round(Tokens.durations.stagger * 2 / 3)
    readonly property int _columns: Math.max(_from.length, _to.length)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    Accessible.role: Accessible.StaticText
    Accessible.name: accessibleName.length > 0 ? accessibleName : text

    function _text(number) {
        return format ? String(format(number)) : String(number)
    }

    onValueChanged: {
        const previous = _previous
        _previous = value
        if (value === previous)
            return
        roll.stop()
        // `text` may not have followed `value` yet: format the value itself.
        if (Motion.reduced) {
            _from = ""
            _to = _text(value)
            return
        }
        _from = _text(previous)
        _to = _text(value)
        _up = value > previous
        roll.duration = Motion.quick + _digitStagger * (_columns - 1)
        _elapsed = 0
        roll.restart()
        if (popOnIncrease && _up) {
            pop.stop()
            row.scale = Motion.popScale
            pop.restart()
        }
    }

    NumberAnimation {
        id: roll
        target: root
        property: "_elapsed"
        from: 0
        to: roll.duration
        onFinished: root._from = ""
    }
    NumberAnimation {
        id: pop
        target: row
        property: "scale"
        to: 1
        duration: Motion.pop.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.pop.curve
    }

    Row {
        id: row
        Repeater {
            model: root._from.length === 0 ? 1 : root._columns
            delegate: Item {
                id: digit
                required property int index
                readonly property bool rolling: root._from.length > 0
                readonly property string next: rolling ? root._to.padStart(root._columns)[index].trim() : root._to
                readonly property string old: rolling ? root._from.padStart(root._columns)[index].trim() : ""
                readonly property real t: !rolling || old === next ? 1
                    : root._ease(Math.max(0, Math.min(1,
                        (root._elapsed - root._digitStagger * (root._columns - 1 - index)) / Math.max(1, Motion.quick))))
                readonly property real sign: root._up ? 1 : -1
                implicitWidth: Math.max(nextText.implicitWidth, digit.t < 1 ? oldText.implicitWidth : 0)
                implicitHeight: nextText.implicitHeight
                clip: digit.t < 1
                MeridianText {
                    id: nextText
                    role: root.role
                    color: root.color
                    tabular: true
                    text: digit.next
                    opacity: digit.t
                    y: digit.sign * (1 - digit.t) * height
                    Accessible.ignored: true
                }
                MeridianText {
                    id: oldText
                    visible: digit.t < 1
                    role: root.role
                    color: root.color
                    tabular: true
                    text: digit.old
                    opacity: 1 - digit.t
                    y: -digit.sign * digit.t * height
                    Accessible.ignored: true
                }
            }
        }
    }

    // Meridian's quick curve (the standard cubic) for the per-digit progress.
    function _ease(t) {
        const c = Motion.standard
        if (c.length < 6)
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
