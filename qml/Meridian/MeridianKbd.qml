pragma ComponentBehavior: Bound
import QtQuick

// Keyboard keys as keycaps (Flutter: MeridianKbd): each of `keys` in a
// `pane-alt` cap with a `line-strong` edge and a 1px bottom shadow, `caption`
// text in `ink-muted`. `pressed` sinks the caps by the shadow's height (a
// shortcut being held). On an `accent` fill set `onAccent`.
Row {
    id: root

    property var keys: []
    property bool onAccent: false
    property bool pressed: false

    spacing: Metrics.kbdGap
    Accessible.ignored: true

    Repeater {
        model: root.keys
        delegate: Item {
            id: cap
            required property string modelData
            implicitWidth: Math.max(Metrics.kbdMinWidth, label.implicitWidth + 2 * Metrics.kbdPaddingX)
            implicitHeight: Math.max(Metrics.kbdHeight, label.implicitHeight) + Metrics.hairline
            // The bottom edge that gives the cap its depth.
            Rectangle {
                visible: !root.onAccent && !root.pressed
                y: Metrics.hairline
                width: parent.width
                height: parent.height - Metrics.hairline
                radius: Theme.radius.xs
                color: Theme.colors.lineStrong
            }
            Rectangle {
                y: root.pressed ? Metrics.hairline : 0
                width: parent.width
                height: parent.height - Metrics.hairline
                radius: Theme.radius.xs
                color: root.onAccent ? "transparent" : Theme.colors.paneAlt
                border.width: 1
                border.color: root.onAccent ? Theme.colors.inkOnAccentMuted : Theme.colors.lineStrong
                MeridianText {
                    id: label
                    anchors.centerIn: parent
                    role: MeridianText.Caption
                    text: cap.modelData
                    color: root.onAccent ? Theme.colors.inkOnAccent : Theme.colors.inkMuted
                }
            }
        }
    }
}
