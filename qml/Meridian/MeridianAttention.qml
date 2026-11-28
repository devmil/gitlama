import QtQuick

// Tints the area behind its content `accent-soft` and fades it back over `motion-attention`
// (exit-soft) each time `trigger` increases (Flutter: MeridianAttention; MM-23). With
// `memoryKey`, a trigger plays only once per (memoryKey, trigger) in MeridianMotionMemory: a
// recycled row does not replay it, and a row first created with an unseen positive trigger
// plays it. Reduce motion holds the tint `motion-highlight` and removes it.
//
// Put the content inside; the tint sits behind it with the given radius.
Item {
    id: root

    property int trigger: 0
    property int delay: 0
    property string memoryKey: ""
    /// The tint; `accent-soft` by default.
    property color color: Theme.colors.accentSoft
    property real radius: Theme.radius.sm
    default property alias content: holder.data

    /// The tint's strength, 1 full to 0 gone.
    property real progress: 0
    property int _previous: 0

    implicitWidth: holder.childrenRect.width
    implicitHeight: holder.childrenRect.height

    Component.onCompleted: {
        _previous = trigger
        if (memoryKey.length > 0 && trigger > 0)
            _play()
    }
    onTriggerChanged: {
        const increased = trigger > _previous
        _previous = trigger
        if (increased)
            _play()
    }

    function _play() {
        if (memoryKey.length > 0 && !MeridianMotionMemory.markSeen(memoryKey + "|" + trigger))
            return
        tint.stop()
        progress = 0
        wait.duration = delay
        hold.duration = Motion.reduced ? Tokens.durations.highlight : 0
        fade.duration = Motion.reduced ? 0 : Tokens.durations.attention
        tint.restart()
    }

    SequentialAnimation {
        id: tint
        PauseAnimation { id: wait }
        PropertyAction { target: root; property: "progress"; value: 1 }
        PauseAnimation { id: hold }
        NumberAnimation {
            id: fade
            target: root
            property: "progress"
            to: 0
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Tokens.curves.exitSoft
        }
        PropertyAction { target: root; property: "progress"; value: 0 }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.progress > 0
        radius: root.radius
        color: Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * root.progress)
    }
    Item {
        id: holder
        anchors.fill: parent
    }
}
