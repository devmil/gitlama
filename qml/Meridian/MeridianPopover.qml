import QtQuick
import QtQuick.Templates as T

// Floating content that needs a field, check boxes or its own layout, opened
// from a trigger (Flutter: MeridianPopover). One task; bigger work is a
// Dialog. Escape and a click outside close it. Position it with x/y relative
// to its parent (below the trigger by default).
T.Popup {
    id: control

    property real maxHeight: Metrics.popoverMaxHeight

    width: Metrics.popoverWidth
    implicitHeight: Math.min(maxHeight, implicitContentHeight + topPadding + bottomPadding)
    padding: Theme.space.s6
    focus: true
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent
    transformOrigin: T.Popup.Top
    y: parent ? parent.height + Theme.space.s2 : 0


    background: MeridianSurface {}

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.fade(Motion.overlay) }
            NumberAnimation {
                property: "scale"; from: Motion.overlayEnterScale; to: 1; duration: Motion.overlay
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.enter
            }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.fade(Motion.exit) }
    }
}
