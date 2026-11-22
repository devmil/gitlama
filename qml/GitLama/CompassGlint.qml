import QtQuick
import Meridian

// The one-shot sync sweep: a 40 px `accent-soft` band crosses the Compass
// after a changed, person-started transfer (after `syncGlintDelay`, over
// `glint`). Reduce motion: none.
Item {
    id: glint

    property int sequence: 0
    property bool changed: false
    property real _progress: 0
    property int _previous: sequence

    onSequenceChanged: {
        if (sequence === _previous)
            return
        _previous = sequence
        sweep.stop()
        delay.stop()
        _progress = 0
        band.visible = changed && !Motion.reduced
        if (band.visible)
            delay.restart()
    }

    Timer {
        id: delay
        interval: GitLamaLayout.syncGlintDelay
        onTriggered: sweep.restart()
    }
    NumberAnimation {
        id: sweep
        target: glint
        property: "_progress"
        from: 0
        to: 1
        duration: GitLamaLayout.glint
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.standard
        onFinished: band.visible = false
    }

    Rectangle {
        id: band
        visible: false
        width: GitLamaLayout.glintWidth
        height: parent.height
        x: -GitLamaLayout.glintWidth + (glint.width + GitLamaLayout.glintWidth) * glint._progress
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.clear(Theme.colors.accentSoft) }
            GradientStop { position: 0.5; color: Qt.rgba(Theme.colors.accentSoft.r, Theme.colors.accentSoft.g, Theme.colors.accentSoft.b, GitLamaLayout.opacityGlint) }
            GradientStop { position: 1; color: Theme.clear(Theme.colors.accentSoft) }
        }
    }
}
