import QtQuick

// Insert and remove with `motion-layout` (Flutter: MeridianReveal; MM-22,
// MM-24, MM-65). Insert: the size grows from 0 over `motion-layout` while
// the content fades in over `motion-select`. Remove: the content fades out
// over `motion-exit`, then the size collapses over `motion-layout`. While
// collapsed the content is hidden, so it takes no focus. Reduce motion is
// instant.
//
// Put one item inside; the reveal takes its implicit size on the axis.
Item {
    id: root

    enum Axis { Vertical, Horizontal }

    property bool shown: true
    property int axis: MeridianReveal.Vertical
    /// Fade without changing size.
    property bool fadeOnly: false
    /// Animate in on creation when shown (a row that was just inserted).
    property bool appear: false
    /// Overrides `motion-layout` for the size change; -1 keeps it.
    property int duration: -1
    /// Where the content sits while the size changes: -1 start, 1 end.
    property int axisAlignment: -1
    default property alias content: holder.data
    signal hidden()

    readonly property Item _child: holder.children.length > 0 ? holder.children[0] : null
    readonly property real _childWidth: _child ? (_child.implicitWidth > 0 ? _child.implicitWidth : _child.width) : 0
    readonly property real _childHeight: _child ? (_child.implicitHeight > 0 ? _child.implicitHeight : _child.height) : 0
    property real _factor: shown && !appear ? 1 : 0
    property real _fade: shown && !appear ? 1 : 0
    readonly property int _sizeDuration: duration >= 0 ? (Motion.reduced ? 0 : duration) : Motion.layout

    implicitWidth: axis === MeridianReveal.Horizontal && !fadeOnly ? _childWidth * _factor : _childWidth
    implicitHeight: axis === MeridianReveal.Vertical && !fadeOnly ? _childHeight * _factor : _childHeight
    clip: _factor < 1
    visible: _factor > 0 || _fade > 0

    Component.onCompleted: if (shown && appear) _show()
    onShownChanged: shown ? _show() : _hide()

    function _show() {
        hide.stop()
        show.restart()
    }
    function _hide() {
        show.stop()
        hide.restart()
    }

    ParallelAnimation {
        id: show
        NumberAnimation { target: root; property: "_factor"; to: 1; duration: root._sizeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
        NumberAnimation { target: root; property: "_fade"; to: 1; duration: Motion.select; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
    }
    SequentialAnimation {
        id: hide
        NumberAnimation { target: root; property: "_fade"; to: 0; duration: Motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve }
        NumberAnimation { target: root; property: "_factor"; to: 0; duration: root._sizeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
        ScriptAction { script: root.hidden() }
    }

    Item {
        id: holder
        opacity: root._fade
        enabled: root.shown
        width: root._childWidth
        height: root._childHeight
        x: root.axis === MeridianReveal.Horizontal && root.axisAlignment > 0 ? root.width - width : 0
        y: root.axis === MeridianReveal.Vertical && root.axisAlignment > 0 ? root.height - height : 0
    }
}
