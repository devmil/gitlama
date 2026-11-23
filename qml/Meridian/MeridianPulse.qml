import QtQuick

// A halo behind its content (Flutter: MeridianPulse) that grows to
// `pulse-scale` × `size` while it fades from `startOpacity` to 0, looping
// every `motion-pulse` while `active`. With `once` it plays one loop each
// time `active` becomes true. With `spread` ≥ 0 it is a ring around the
// content instead of a disc: its edge grows from the content's edge to
// `spread` px outside it (the Continue halo).
//
// Reduced motion: a static disc at `pulse-scale` × with
// `opacityStaticHalo`, or nothing for `once` and rings.
Item {
    id: root

    property bool active: false
    property color color: Theme.colors.accent
    /// The disc's diameter at rest; 0 takes the content's width.
    property real size: 0
    property bool once: false
    /// The ring's growth in px; negative draws a disc.
    property real spread: -1
    property real radius: 0
    property real startOpacity: Metrics.opacityPulseStart
    default property alias content: holder.data

    /// The loop's eased position, 0 → 1; 0 or 1 shows no halo.
    property real progress: 0
    readonly property bool ring: spread >= 0
    readonly property real eased: progress
    /// Reduced motion keeps a looping disc as a still halo.
    readonly property bool staticHalo: Motion.reduced && active && !once && !ring

    implicitWidth: holder.childrenRect.width
    implicitHeight: holder.childrenRect.height

    function start() {
        if (Motion.reduced)
            return
        loop.stop()
        progress = 0
        loop.loops = once ? 1 : Animation.Infinite
        loop.start()
    }

    onActiveChanged: {
        if (active)
            start()
        else if (!once) {
            loop.stop()
            progress = 0
        }
    }
    Component.onCompleted: if (active) start()

    NumberAnimation {
        id: loop
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: Tokens.durations.pulse
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Tokens.curves.standard
    }

    // The disc.
    Rectangle {
        readonly property real base: root.size > 0 ? root.size : Math.max(root.width, root.height)
        readonly property bool shownStatic: root.staticHalo
        visible: !root.ring && (shownStatic || (root.progress > 0 && root.progress < 1))
        anchors.centerIn: parent
        width: base
        height: base
        radius: base / 2
        color: root.color
        scale: shownStatic ? Tokens.scales.pulseScale : 1 + (Tokens.scales.pulseScale - 1) * root.eased
        opacity: shownStatic ? Metrics.opacityStaticHalo : root.startOpacity * (1 - root.eased)
    }
    // The ring.
    Rectangle {
        readonly property real grow: root.spread * root.eased
        visible: root.ring && root.progress > 0 && root.progress < 1
        x: -grow
        y: -grow
        width: root.width + 2 * grow
        height: root.height + 2 * grow
        radius: root.radius + grow
        color: "transparent"
        border.width: Math.max(Metrics.hairline, grow)
        border.color: Qt.alpha(root.color, root.color.a * root.startOpacity * (1 - root.eased))
    }
    Item {
        id: holder
        anchors.fill: parent
    }
}
