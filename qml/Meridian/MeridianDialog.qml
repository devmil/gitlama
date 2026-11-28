import QtQuick
import QtQuick.Templates as T

// A modal question or form (Flutter: MeridianDialog). The title is the full
// command with real names ("Delete Linear algebra"); the primary button
// carries the verb, never "OK". Put buttons in `actions`, Cancel first and
// the verb last. Enter runs `submitted` (unless a button has focus); Escape
// closes. When `submitDisabled`, Enter shakes the dialog instead.
//
// A dialog that only informs or manages passes `closeLabel` and shows a ✕ in
// its title row instead of a footer button.
T.Dialog {
    id: control

    enum Width { Confirm, Form, Workflow }

    property string description
    property int widthClass: MeridianDialog.Confirm
    property bool submitDisabled: false
    /// Accessible name of the ✕ for informing dialogs; empty for questions.
    property string closeLabel
    default property alias content: body.data
    property alias actions: actionRow.data
    property int rejectCount: 0

    signal submitted()

    readonly property real preferredWidth: [Metrics.dialogConfirmWidth, Metrics.dialogFormWidth,
        Metrics.dialogWorkflowWidth][widthClass]
    readonly property real pad: Theme.touch ? Theme.space.s8 : Theme.space.s7

    // Templates compute no implicit size for a dialog.
    implicitWidth: preferredWidth
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
        + (implicitHeaderHeight > 0 ? implicitHeaderHeight + spacing : 0)
        + (implicitFooterHeight > 0 ? implicitFooterHeight + spacing : 0)
    parent: T.Overlay.overlay
    modal: true
    focus: true
    closePolicy: T.Popup.CloseOnEscape
    anchors.centerIn: parent
    width: Math.min(preferredWidth, (parent ? parent.width : preferredWidth) - 2 * Theme.space.s6)
    height: Math.min(implicitHeight, (parent ? parent.height : implicitHeight) * 0.85)
    padding: pad
    // Under a title the body starts `space-4` below it (Flutter:
    // MeridianDialog), not a full padding plus the footer spacing.
    topPadding: implicitHeaderHeight > 0 ? Theme.space.s4 - spacing : pad
    spacing: Theme.space.s6


    function submit() {
        if (submitDisabled) {
            rejectCount += 1
            return
        }
        submitted()
    }

    onRejectCountChanged: shake.restart()

    // Enter and Escape reach the body only while focus is inside the dialog.
    // An opened dialog whose content took no focus (no field, no focused
    // button) leaves it on the popup itself, where Enter would do nothing:
    // give it to the body then. A field or button the dialog focused keeps it.
    onOpened: dialogBody.takeFocusUnlessInside()

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

    background: MeridianSurface {
        transform: Translate { id: shiver }
    }

    SequentialAnimation {
        id: shake
        loops: Motion.shakeCycles
        NumberAnimation { target: shiver; property: "x"; to: -Motion.shakeSurfaceDistance; duration: Motion.shakeSurface / (4 * Motion.shakeCycles) }
        NumberAnimation { target: shiver; property: "x"; to: Motion.shakeSurfaceDistance; duration: Motion.shakeSurface / (2 * Motion.shakeCycles) }
        NumberAnimation { target: shiver; property: "x"; to: 0; duration: Motion.shakeSurface / (4 * Motion.shakeCycles) }
    }

    header: Item {
        implicitHeight: titleText.implicitHeight + control.pad
        MeridianText {
            id: titleText
            x: control.pad
            y: control.pad
            width: parent.width - 2 * control.pad - (closeButton.visible ? closeButton.width + Theme.space.s4 : 0)
            role: MeridianText.Title
            text: control.title
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        MeridianIconButton {
            id: closeButton
            visible: control.closeLabel.length > 0
            x: parent.width - control.pad - width + Theme.space.s3
            y: control.pad - Theme.space.s2
            iconName: "x"
            text: control.closeLabel
            surfaceColor: Theme.colors.raised
            onClicked: control.reject()
        }
    }

    contentItem: Flickable {
        id: dialogBody
        function takeFocusUnlessInside() {
            const focused = Window.activeFocusItem
            let item = focused
            while (item && item !== parent)
                item = item.parent
            if (!item || focused === parent)
                forceActiveFocus()
        }
        MeridianWheelScroll { flickable: dialogBody }
        Accessible.role: Accessible.Dialog
        Accessible.name: control.title
        implicitWidth: column.implicitWidth
        implicitHeight: column.implicitHeight
        contentWidth: width
        // The description sits `space-5` above the body.
        contentHeight: column.height
        clip: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: column
            // The popup's width, not the content item's: that one follows
            // its children and would collapse to zero.
            width: control.availableWidth
            spacing: Theme.space.s5
            MeridianText {
                width: parent.width
                visible: control.description.length > 0
                text: control.description
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            Column {
                id: body
                width: parent.width
                spacing: Theme.space.s4
            }
        }
        Keys.onReturnPressed: event => { control.submit(); event.accepted = true }
        Keys.onEnterPressed: event => { control.submit(); event.accepted = true }
    }

    footer: Item {
        visible: actionRow.children.length > 0
        implicitHeight: visible ? actionRow.height + control.pad : 0
        // Actions in declaration order, end-aligned: Cancel first, the verb
        // last at the trailing edge.
        Row {
            id: actionRow
            x: Math.max(control.pad, parent.width - control.pad - width)
            spacing: Theme.space.s4
        }
    }
}
