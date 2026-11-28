import QtQuick
import QtQuick.Templates as T

// A short label over a control (Flutter: MeridianTooltip): `caption` in
// `pane` on `ink`, `radius-sm`, after `motion-tooltip-wait` of hover, below
// the target by default. Put it inside the control and bind `shown` to the
// control's hover.
T.ToolTip {
    id: control

    property bool shown: false
    property bool preferBelow: true
    readonly property Item target: parent

    visible: shown && text.length > 0
    delay: Motion.tooltipWait
    timeout: -1
    x: target ? Math.round((target.width - width) / 2) : 0
    y: target ? (preferBelow ? target.height + Theme.space.s2 : -height - Theme.space.s2) : 0
    margins: Theme.space.s2
    padding: 0
    leftPadding: Theme.space.s3
    rightPadding: Theme.space.s3
    topPadding: Theme.space.s2
    bottomPadding: Theme.space.s2
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent | T.Popup.CloseOnReleaseOutsideParent
    implicitWidth: Math.min(Metrics.tooltipMaxWidth, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding

    contentItem: MeridianText {
        role: MeridianText.Caption
        color: Theme.colors.pane
        text: control.text
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        lineHeightMode: Text.ProportionalHeight
        lineHeight: 1
    }
    background: Rectangle {
        radius: Theme.radius.sm
        color: Theme.colors.ink
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.fade(Tokens.durations.quick) }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.fade(Tokens.durations.exit) }
    }
}
