import QtQuick

// Draws an icon's strokes progressively (Flutter: MeridianStrokeIcon; MM-04, MM-11, NM-62).
// When `drawn` turns true the strokes draw over `duration` (default `motion-quick`) after
// `delay`; when it turns false they erase over `motion-exit`. `appear` draws on creation.
// Reduce motion shows the whole icon at once.
Item {
    id: root

    /// Lucide name, e.g. "check".
    property string name
    property int iconSize: MeridianIcon.Regular
    /// An explicit extent in logical pixels; overrides `iconSize` when > 0.
    property real extent: 0
    property color color: Theme.colors.ink
    property bool drawn: true
    property bool appear: false
    /// The draw's duration; -1 uses `motion-quick`.
    property int duration: -1
    property int delay: 0
    /// How much is drawn, 0..1.
    property real progress: 1

    readonly property real dimension: extent > 0 ? extent
        : iconSize === MeridianIcon.Small ? Theme.size.iconSmall
        : iconSize === MeridianIcon.Toolbar ? Theme.size.iconToolbar
        : Theme.size.icon
    readonly property string resolvedName: Theme.iconAliases[name] ?? name

    implicitWidth: dimension
    implicitHeight: dimension
    Accessible.ignored: true

    Component.onCompleted: {
        if (!drawn || appear)
            progress = 0
        if (appear && drawn)
            _draw()
    }
    onDrawnChanged: drawn ? _draw() : _erase()

    function _draw() {
        erase.stop()
        if (Motion.reduced) {
            draw.stop()
            progress = 1
            return
        }
        drawWait.duration = delay
        drawStroke.duration = duration >= 0 ? duration : Motion.quick
        draw.restart()
    }
    function _erase() {
        draw.stop()
        if (Motion.reduced) {
            erase.stop()
            progress = 0
            return
        }
        erase.restart()
    }

    SequentialAnimation {
        id: draw
        PauseAnimation { id: drawWait }
        NumberAnimation {
            id: drawStroke
            target: root
            property: "progress"
            to: 1
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.standard
        }
    }
    NumberAnimation {
        id: erase
        target: root
        property: "progress"
        to: 0
        duration: Motion.exit
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.exitCurve
    }

    MeridianStroke {
        width: root.dimension
        height: root.dimension
        viewSize: 24
        pathData: IconData.paths[root.resolvedName] ?? ""
        progress: root.progress
        color: root.color
    }
}
