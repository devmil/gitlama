import QtQuick

// A 6px state dot with its label (Flutter: MeridianStatusDot): running,
// synced, offline. Never colour alone: the label goes with it, or
// `semanticLabel` names it when the label is elsewhere in the row.
Item {
    id: root

    enum Tone { Neutral, Accent, Success, Warning, Danger, Attention }

    property int tone: MeridianStatusDot.Neutral
    property string label
    property string semanticLabel
    /// A soft static ring, for a live or running state.
    property bool halo: false
    /// A ring that grows and fades every `motion-pulse`; still under reduce motion.
    property bool live: false

    readonly property color dotColor: {
        const c = Theme.colors
        switch (tone) {
        case MeridianStatusDot.Accent: return c.accent
        case MeridianStatusDot.Success: return c.success
        case MeridianStatusDot.Warning: return c.warning
        case MeridianStatusDot.Danger: return c.danger
        case MeridianStatusDot.Attention: return c.attention
        default: return c.inkFaint
        }
    }

    implicitWidth: label.length > 0 ? dotBox.width + Theme.space.s3 + labelText.implicitWidth : dotBox.width
    implicitHeight: Math.max(dotBox.height, label.length > 0 ? labelText.implicitHeight : 0)

    Accessible.role: Accessible.StaticText
    Accessible.name: semanticLabel.length > 0 ? semanticLabel : label

    Item {
        id: dotBox
        width: Metrics.statusDot
        height: Metrics.statusDot
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            visible: root.halo && !root.live
            anchors.centerIn: parent
            width: Metrics.statusDot + 2 * Metrics.statusHaloSpread
            height: width
            radius: width / 2
            color: Qt.alpha(root.dotColor, Metrics.opacityStatusHalo)
        }
        Rectangle {
            id: pulse
            visible: root.live
            anchors.centerIn: parent
            width: Metrics.statusDot
            height: width
            radius: width / 2
            color: root.dotColor
            opacity: Motion.reduced ? Metrics.opacityStaticHalo : 0
            scale: 1
            SequentialAnimation on scale {
                running: root.live && !Motion.reduced && root.visible && Motion.loopsActive
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: Motion.pulseScale; duration: Motion.pulse; easing.type: Easing.OutCubic }
            }
            SequentialAnimation on opacity {
                running: root.live && !Motion.reduced && root.visible && Motion.loopsActive
                loops: Animation.Infinite
                NumberAnimation { from: Metrics.opacityPulseStart; to: 0; duration: Motion.pulse; easing.type: Easing.OutCubic }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.dotColor
            Behavior on color { ColorAnimation { duration: Motion.select } }
        }
    }

    MeridianText {
        id: labelText
        visible: root.label.length > 0
        x: dotBox.width + Theme.space.s3
        width: Math.max(0, root.width - x)
        anchors.verticalCenter: parent.verticalCenter
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        text: root.label
        Accessible.ignored: true
    }
}
