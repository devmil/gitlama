import QtQuick

// Content that swaps with motion when `swapKey` changes (Flutter:
// MeridianSwap): the outgoing content is frozen as it was and fades out over
// `motion-exit` moving half the rise; the new content rises in over
// `motion-select`. `Fade` crossfades. Under reduce motion it crossfades in at
// most 100 ms. Changes faster than `skipIfFasterThan` ms apart swap at once
// (keyboard scrubbing). Put one item inside; its implicit size is the
// swap's.
Item {
    id: root

    enum Style { Fade, Rise }

    property var swapKey
    property int style: MeridianSwap.Rise
    property real rise: Motion.riseContent
    property int skipIfFasterThan: 0
    /// Where the frozen content and the new one align horizontally: -1
    /// start, 1 end.
    property int alignment: -1
    default property alias content: live.data

    readonly property Item _child: live.children.length > 0 ? live.children[0] : null
    implicitWidth: _child ? _child.implicitWidth : 0
    implicitHeight: _child ? _child.implicitHeight : 0

    property var _shownKey: swapKey
    property bool _ready: false
    property double _lastSwap: 0
    Component.onCompleted: _ready = true

    onSwapKeyChanged: {
        if (!_ready || swapKey === _shownKey || !visible) {
            _shownKey = swapKey
            return
        }
        _shownKey = swapKey
        const now = Date.now()
        const fast = skipIfFasterThan > 0 && now - _lastSwap < skipIfFasterThan
        _lastSwap = now
        if (fast) {
            swap.complete()
            return
        }
        // Freeze what is shown now, then let the live content change.
        frozen.width = live.width
        frozen.height = live.height
        frozen.x = root.alignment > 0 ? root.width - live.width : 0
        frozen.sourceItem = live
        frozen.scheduleUpdate()
        frozen.visible = true
        Qt.callLater(() => { frozen.sourceItem = null })
        swap.restart()
    }

    ShaderEffectSource {
        id: frozen
        visible: false
        live: false
        hideSource: false
        recursive: false
        opacity: 0
    }

    Item {
        id: live
        width: root._child ? root._child.implicitWidth : 0
        height: root._child ? root._child.implicitHeight : 0
        x: root.alignment > 0 ? root.width - width : 0
    }

    ParallelAnimation {
        id: swap
        readonly property bool fade: Motion.reduced || root.style === MeridianSwap.Fade
        NumberAnimation { target: live; property: "opacity"; from: 0; to: 1; duration: swap.fade ? Motion.fade(Tokens.durations.select) : Motion.select }
        NumberAnimation { target: live; property: "y"; from: swap.fade ? 0 : root.rise; to: 0; duration: swap.fade ? 0 : Motion.select; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
        NumberAnimation { target: frozen; property: "opacity"; from: 1; to: 0; duration: swap.fade ? Motion.fade(Tokens.durations.exit) : Motion.exit }
        NumberAnimation { target: frozen; property: "y"; from: 0; to: swap.fade ? 0 : -root.rise / 2; duration: swap.fade ? 0 : Motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve }
        onFinished: frozen.visible = false
    }
}
