import QtQuick
import Meridian

// The changed-file count: its dot pops in when changes appear (NM-04) and
// the number rolls (NM-03). It does not pulse: dirty is a state.
Row {
    id: root

    property int dirty: 0
    /// Changes just appeared on a Compass that was already on screen.
    property bool popIn: false
    Component.onCompleted: {
        if (popIn && !Motion.reduced) {
            dot.scale = 0
            pop.restart()
        }
    }

    MeridianText {
        id: dot
        role: MeridianText.Caption
        color: Theme.colors.warning
        text: "●"
    }
    MeridianText {
        role: MeridianText.Caption
        color: Theme.colors.warning
        text: " "
    }
    MeridianRollingNumber {
        value: root.dirty
        role: MeridianText.Caption
        color: Theme.colors.warning
    }
    NumberAnimation {
        id: pop
        target: dot
        property: "scale"
        to: 1
        duration: Motion.pop.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.pop.curve
    }

    HoverHandler { id: hover }
    MeridianTooltip {
        shown: hover.hovered
        text: L10n.t("compassChangedFiles", [root.dirty])
    }
}
