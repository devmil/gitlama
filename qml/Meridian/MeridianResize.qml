import QtQuick

// Follows its content's implicit size over `motion-layout` (a button whose label or icon slot
// changes, MM-03; Flutter: MeridianResize). The first size and reduce motion are taken at once.
// The content keeps its own size and sits at the start; the resize clips while it is smaller.
Item {
    id: root

    /// Overrides `motion-layout`; -1 keeps it.
    property int duration: -1
    default property alias content: holder.data

    readonly property Item _child: holder.children.length > 0 ? holder.children[0] : null
    readonly property real _targetWidth: _child ? _child.implicitWidth : 0
    readonly property real _targetHeight: _child ? _child.implicitHeight : 0
    property bool _ready: false
    readonly property int _duration: Motion.reduced || !_ready ? 0 : (duration >= 0 ? duration : Motion.layout)

    implicitWidth: _targetWidth
    implicitHeight: _targetHeight
    clip: width < _targetWidth || height < _targetHeight

    Behavior on implicitWidth {
        enabled: root._duration > 0
        NumberAnimation { duration: root._duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
    }
    Behavior on implicitHeight {
        enabled: root._duration > 0
        NumberAnimation { duration: root._duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
    }

    Component.onCompleted: Qt.callLater(() => root._ready = true)

    Item {
        id: holder
        width: root._targetWidth
        height: root._targetHeight
    }
}
