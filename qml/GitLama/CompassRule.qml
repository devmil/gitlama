import QtQuick
import Meridian

// The Compass's progress rule: it enters from the bottom edge over
// `motion-quick` (NM-01); when the operation ends it fills to 100%, holds
// and fades (NH-2, MM-63).
MeridianReveal {
    id: rule

    property bool active: false
    /// 0..1, or -1 while it cannot tell.
    property real progress: -1
    property bool _finishing: false

    shown: active || _finishing
    axisAlignment: 1
    duration: Motion.quick

    onActiveChanged: {
        if (!active) {
            finish.stop()
            if (Motion.reduced)
                return
            _finishing = true
            finish.restart()
        } else {
            finish.stop()
            _finishing = false
        }
    }
    Timer {
        id: finish
        interval: Motion.emphasized + Motion.progressHold + Motion.exit
        onTriggered: rule._finishing = false
    }

    MeridianProgressBar {
        implicitWidth: rule.width
        value: rule._finishing ? 1 : rule.progress
        persistent: rule.active
    }
}
