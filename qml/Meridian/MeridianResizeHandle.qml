import QtQuick

// Resizes the islands on either side of the gutter it sits in (Flutter:
// MeridianResizeHandle): a sidebar, an inspector, a split between two lists.
//
// It is the `space-3` gap itself, invisible at rest. 150 ms into a hover a
// 2px `accent` rule grows from the centre; dragging shows it full length,
// keyboard focus shows it in `focus`. Dragging reports the pointer's
// movement along `orientation` through `dragged(delta)`; the arrow keys move
// it by `keyboardStep`; a double click or Enter emits `reset`.
//
// The API follows Flutter's: `semanticLabel`, `orientation` (Flutter's
// `direction`), `thickness`, `dragged`/`dragStarted`/`dragFinished`, `reset`.
Item {
    id: root

    /// Qt.Horizontal: a vertical gutter between side-by-side islands.
    /// Qt.Vertical: a horizontal gutter between stacked islands.
    property int orientation: Qt.Horizontal
    /// The gutter's width across the drag axis.
    property real thickness: Theme.space.s3
    property real keyboardStep: Metrics.resizeKeyboardStep
    property string semanticLabel

    readonly property bool horizontal: orientation === Qt.Horizontal
    readonly property bool hovered: area.containsMouse
    readonly property bool dragging: area.pressed
    /// 0 at rest, 1 when the hover rule has fully grown.
    property real grow: 0

    signal dragged(real delta)
    signal dragStarted()
    signal dragFinished()
    signal reset()

    implicitWidth: horizontal ? thickness : 0
    implicitHeight: horizontal ? 0 : thickness
    activeFocusOnTab: true

    Accessible.role: Accessible.Slider
    Accessible.name: semanticLabel
    Accessible.focusable: true

    Keys.onPressed: event => {
        const back = horizontal ? Qt.Key_Left : Qt.Key_Up
        const forward = horizontal ? Qt.Key_Right : Qt.Key_Down
        if (event.key === back) {
            dragged(-keyboardStep)
            event.accepted = true
        } else if (event.key === forward) {
            dragged(keyboardStep)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            reset()
            event.accepted = true
        }
    }

    // The rule grows only after a short hover, so sweeping across the
    // gutter does not flash it.
    Timer {
        id: hoverDelay
        interval: Motion.spinnerDelay
        onTriggered: if (root.hovered) growAnimation.restart()
    }
    NumberAnimation {
        id: growAnimation
        target: root
        property: "grow"
        to: 1
        duration: Motion.quick
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.standard
    }
    NumberAnimation {
        id: shrinkAnimation
        target: root
        property: "grow"
        to: 0
        duration: Motion.exit
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.exitCurve
    }
    onHoveredChanged: {
        if (hovered) {
            shrinkAnimation.stop()
            hoverDelay.restart()
        } else {
            hoverDelay.stop()
            growAnimation.stop()
            shrinkAnimation.restart()
        }
    }

    Rectangle {
        id: rule
        objectName: "resizeRule"
        readonly property bool full: root.dragging || root.activeFocus
        readonly property real extent: root.horizontal
                                       ? Math.max(0, root.height - 2 * Theme.space.s5)
                                       : Math.max(0, root.width - 2 * Theme.space.s5)
        readonly property real fraction: full ? 1 : root.grow
        anchors.centerIn: parent
        width: root.horizontal ? Metrics.resizeRule : extent * fraction
        height: root.horizontal ? extent * fraction : Metrics.resizeRule
        radius: Theme.radius.pill
        visible: fraction > 0
        color: root.dragging ? Theme.colors.accent
             : root.activeFocus ? Theme.colors.focus
             : root.hovered ? Theme.colors.accent
             : Theme.clear(Theme.colors.accent)
        Behavior on color {
            ColorAnimation { duration: root.hovered || root.dragging ? Motion.hover : Motion.hoverOut }
        }
    }

    MouseArea {
        id: area
        objectName: "resizeArea"
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: root.horizontal ? Qt.SplitHCursor : Qt.SplitVCursor
        property real last: 0

        function along(mouse) {
            const point = mapToGlobal(mouse.x, mouse.y)
            return root.horizontal ? point.x : point.y
        }
        // The handle moves with the islands it resizes, so the drag follows
        // the pointer in global coordinates.
        onPressed: mouse => {
            last = along(mouse)
            root.dragStarted()
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return
            const now = along(mouse)
            const delta = now - last
            last = now
            if (delta !== 0)
                root.dragged(delta)
        }
        onReleased: root.dragFinished()
        onCanceled: root.dragFinished()
        onDoubleClicked: root.reset()
    }
}
