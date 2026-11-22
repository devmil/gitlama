import QtQuick

// Text that swaps with motion when it changes (Flutter: MeridianSwap):
// `Rise` brings the new text up a few px over `motion-select` while the old
// fades out over `motion-exit`, moving half as far; `Roll` rolls a full
// line; `Fade` crossfades. Under reduce motion every style crossfades in at
// most 100 ms.
Item {
    id: root

    enum Style { Fade, Rise, Roll }

    property string text
    property int style: MeridianSwapText.Rise
    property real rise: Motion.riseContent
    /// Roll direction: positive brings the new text from below.
    property int direction: 1
    property int role: MeridianText.Body
    property color color: Theme.colors.ink
    property bool tabular: false
    /// False swaps at once. For text that changes on every refresh: each
    /// animation frame redraws the whole window.
    property bool animated: true
    property int horizontalAlignment: Text.AlignLeft
    property int elide: Text.ElideRight
    readonly property real contentWidth: current.implicitWidth

    implicitWidth: current.implicitWidth
    implicitHeight: current.implicitHeight
    clip: style === MeridianSwapText.Roll && leaving.opacity > 0

    property bool _ready: false
    property string _shown: text

    onTextChanged: {
        // Hidden text has nothing to show moving.
        if (!_ready || text === _shown || !animated || !visible) {
            swap.complete()
            _shown = text
            return
        }
        leaving.text = _shown
        _shown = text
        swap.restart()
    }
    Component.onCompleted: _ready = true

    MeridianText {
        id: leaving
        width: root.width
        height: root.height
        role: root.role
        color: root.color
        tabular: root.tabular
        horizontalAlignment: root.horizontalAlignment
        elide: root.elide
        opacity: 0
        Accessible.ignored: true
    }
    MeridianText {
        id: current
        width: root.width
        height: root.height
        role: root.role
        color: root.color
        tabular: root.tabular
        horizontalAlignment: root.horizontalAlignment
        elide: root.elide
        text: root._shown
    }

    ParallelAnimation {
        id: swap
        readonly property bool reduced: Motion.reduced || root.style === MeridianSwapText.Fade
        readonly property real travelIn: reduced ? 0 : root.style === MeridianSwapText.Roll ? root.direction * current.height : root.rise
        readonly property real travelOut: reduced ? 0 : root.style === MeridianSwapText.Roll ? -root.direction * current.height : -root.rise / 2
        NumberAnimation { target: current; property: "opacity"; from: 0; to: 1; duration: swap.reduced ? Motion.fade(Tokens.durations.select) : (root.style === MeridianSwapText.Roll ? Tokens.durations.quick : Tokens.durations.select) }
        NumberAnimation {
            target: current; property: "y"; from: swap.travelIn; to: 0
            duration: swap.reduced ? 0 : (root.style === MeridianSwapText.Roll ? Tokens.durations.quick : Tokens.durations.select)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.enter
        }
        NumberAnimation { target: leaving; property: "opacity"; from: 1; to: 0; duration: swap.reduced ? Motion.fade(Tokens.durations.exit) : (root.style === MeridianSwapText.Roll ? Tokens.durations.quick : Tokens.durations.exit) }
        NumberAnimation {
            target: leaving; property: "y"; from: 0; to: swap.travelOut
            duration: swap.reduced ? 0 : (root.style === MeridianSwapText.Roll ? Tokens.durations.quick : Tokens.durations.exit)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve
        }
    }
}
