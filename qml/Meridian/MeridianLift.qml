import QtQuick

// Drag feedback (Flutter: MeridianLift; MM-28, NM-52, NM-70): while `lifted` the content
// scales to `lift-scale` and casts `shadow-float`, settling back on `spring-gentle` when
// dropped. A lift created lifted (a drag proxy) rises from rest. Reduce motion keeps the
// shadow and drops the scale.
//
// Put one item inside; the lift takes its implicit size.
Item {
    id: root

    property bool lifted: false
    /// The radius of the shadow's shape: the content's corner radius.
    property real radius: Theme.radius.sm
    default property alias content: holder.data

    readonly property Item _child: holder.children.length > 0 ? holder.children[0] : null
    /// 0 at rest, 1 lifted.
    property real progress: 0

    implicitWidth: _child ? _child.implicitWidth : 0
    implicitHeight: _child ? _child.implicitHeight : 0
    scale: 1 + (Motion.liftScale - 1) * progress

    Component.onCompleted: if (lifted) _animate()
    onLiftedChanged: _animate()

    function _animate() {
        settle.stop()
        settle.to = lifted ? 1 : 0
        settle.start()
    }

    NumberAnimation {
        id: settle
        target: root
        property: "progress"
        duration: Motion.gentle.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.gentle.curve
    }

    MeridianShadow {
        anchors.fill: parent
        visible: root.progress > 0
        opacity: Math.max(0, Math.min(1, root.progress))
        layers: Theme.shadows.float
        radius: root.radius
    }
    Item {
        id: holder
        anchors.fill: parent
    }
}
