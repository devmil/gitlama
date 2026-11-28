import QtQuick

// Meridian's keyboard focus ring: 2px `focus`, 1px outside its target. It
// shows for keyboard focus only: bind `shown` to the control's
// `visualFocus` (Qt Quick Templates), never to `activeFocus`, so a pointer
// press draws no ring.
Rectangle {
    id: ring

    /// The item the ring surrounds. Its parent should be `target`.
    property Item target: parent
    property bool shown: false
    /// The target's own corner radius.
    property real targetRadius: Theme.radius.md
    readonly property real _outset: Metrics.focusRingOffset + Metrics.focusRingWidth

    x: -_outset
    y: -_outset
    width: (target ? target.width : 0) + 2 * _outset
    height: (target ? target.height : 0) + 2 * _outset
    radius: targetRadius + _outset
    color: "transparent"
    border.width: Metrics.focusRingWidth
    border.color: Theme.colors.focus
    visible: shown
    z: 100
    Accessible.ignored: true
}
