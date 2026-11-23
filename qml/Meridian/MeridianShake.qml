import QtQuick

// Shakes its content horizontally once each time `trigger` increases: 0, -a, a, -a, a, -a, 0,
// linear between the points, over `shake-field` (3 px, MM-09) or `shake-surface` (4 px,
// MM-47) (Flutter: MeridianShake). Reduce motion: none.
Item {
    id: root

    enum Strength { Field, Surface }

    property int trigger: 0
    property int strength: MeridianShake.Field
    default property alias content: holder.data

    property real _t: 1
    property int _previous: 0
    /// The horizontal offset now, for an item that shakes without being inside the shake.
    readonly property real offset: offsetAt(_t, strength === MeridianShake.Field
        ? Motion.shakeFieldDistance : Motion.shakeSurfaceDistance)

    implicitWidth: holder.childrenRect.width
    implicitHeight: holder.childrenRect.height

    Component.onCompleted: _previous = trigger
    onTriggerChanged: {
        const increased = trigger > _previous
        _previous = trigger
        if (!increased || Motion.reduced)
            return
        shake.duration = strength === MeridianShake.Field ? Motion.shakeField : Motion.shakeSurface
        shake.restart()
    }

    /// The offset at `t` (0..1) for amplitude `a`.
    function offsetAt(t, a) {
        const points = [0, -1, 1, -1, 1, -1, 0]
        const segments = points.length - 1
        const x = Math.max(0, Math.min(1, t)) * segments
        const i = Math.min(Math.floor(x), segments - 1)
        return a * (points[i] + (points[i + 1] - points[i]) * (x - i))
    }

    NumberAnimation { id: shake; target: root; property: "_t"; from: 0; to: 1 }

    Item {
        id: holder
        anchors.fill: parent
        transform: Translate { x: root.offset }
    }
}
