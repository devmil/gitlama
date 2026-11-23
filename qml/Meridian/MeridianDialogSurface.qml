import QtQuick
import QtQuick.Templates as T

// A modal surface for a custom layout (Flutter: MeridianDialogSurface): the
// dialog's scrim, surface, entrance and Escape, without its title, padding
// or footer. A workflow that fills the window (a review, a resolver) sets
// `fillWindow`; otherwise size it with width and height. One scrim stays
// when it opens another dialog.
T.Dialog {
    id: control

    /// Fills the window less `margin` on every side.
    property bool fillWindow: false
    property real margin: Theme.space.s3
    /// The accessible name of the surface.
    property string label
    default property alias content: body.data

    parent: T.Overlay.overlay
    modal: true
    focus: true
    closePolicy: T.Popup.CloseOnEscape
    anchors.centerIn: parent
    width: fillWindow && parent ? parent.width - 2 * margin : implicitWidth
    height: fillWindow && parent ? parent.height - 2 * margin : implicitHeight
    padding: 0

    T.Overlay.modal: Rectangle {
        color: Theme.colors.scrim
        Behavior on opacity { NumberAnimation { duration: Motion.fade(Motion.dialog) } }
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.fade(Motion.dialog) }
            NumberAnimation {
                property: "scale"; from: Motion.dialogEnterScale; to: 1; duration: Motion.dialog
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.enter
            }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.fade(Motion.exit) }
    }

    background: MeridianSurface {}

    contentItem: Item {
        id: body
        Accessible.role: Accessible.Dialog
        Accessible.name: control.label
        clip: true
    }
}
