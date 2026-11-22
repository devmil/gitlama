import QtQuick

// Desktop wheel and touchpad scrolling for a Flickable, ListView or
// TableView, the same on Linux (Wayland and X11), macOS and Windows.
// Declare it inside the view:
//     ListView { id: view; MeridianWheelScroll { flickable: view } }
//
// Why not Qt's own: Qt Quick restarts its wheel animation from wherever the
// content is on every notch, so a fast spin loses distance and the content
// keeps gliding after the wheel stops; and on Qt Wayland a wheel notch also
// carries libinput's ~15 px pixel delta, which code that prefers pixel
// deltas scrolls by, a quarter of the system's distance.
//
// The rules, after KDE Kirigami's WheelHandler (which VLC also adopted):
//
// - A wheel notch (`phase` NoScrollPhase) moves `stepSize` px per 120 of
//   angle delta and ignores the pixel delta. The move animates for at most
//   `smoothDuration` ms, shorter for small (high-resolution) steps, and the
//   next notch extends the running animation's target, so notches add up
//   linearly and the content stops when the wheel stops.
// - A touchpad gesture (`phase` Begin, Update, End, Momentum: Qt Wayland
//   fingers, macOS trackpads) follows the pixel delta one to one with no
//   animation. macOS and others send their own momentum, which it follows.
//   Qt Wayland sends none, so on Wayland lifting the fingers continues
//   with their last speed and decelerates (`syntheticMomentum`).
// - Shift, or a view that only scrolls sideways, turns vertical motion
//   horizontal. Dragging or flicking the view stops it.
// - Reduced motion: no animation and no synthetic momentum.
WheelHandler {
    id: scroller

    required property Flickable flickable

    /// The distance of one text line; a notch is at least
    /// `wheelScrollLines` of them.
    property real lineHeight: 20
    /// Pixels per wheel notch along each axis. As GTK, it grows with the
    /// viewport (extent^(2/3)) so long views scroll further per notch,
    /// floored at `wheelScrollLines` lines and scaled by the platform's
    /// wheel-lines setting (3 is the default everywhere).
    readonly property real _lines: Math.max(1, Application.styleHints.wheelScrollLines)
    property real verticalStepSize: _stepFor(flickable ? flickable.height : 0)
    property real horizontalStepSize: _stepFor(flickable ? flickable.width : 0)

    /// Animate wheel notches. Named platform timing, not a token: Kirigami's
    /// and Plasma's 200 ms.
    property bool smoothScroll: !Motion.reduced
    property int smoothDuration: 200
    /// Continue a lifted touchpad gesture. Only Qt Wayland lacks inertia.
    property bool syntheticMomentum: Qt.platform.pluginName === "wayland" && !Motion.reduced

    /// True while a wheel animation or synthetic momentum moves the view.
    readonly property bool animating: xAnim.running || yAnim.running
                                      || xMomentum.running || yMomentum.running

    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    function _stepFor(extent) {
        return Math.max(_lines * lineHeight, Math.pow(Math.max(0, extent), 2 / 3) * _lines / 3)
    }

    /// Stops any wheel animation or momentum where the content is now.
    function stop() {
        xAnim.stop()
        yAnim.stop()
        xMomentum.stop()
        yMomentum.stop()
    }

    // Extents in content coordinates: [low, high] the content position may take.
    function _low(origin, before) { return origin - before }
    function _high(origin, size, before, after, extent) {
        return Math.max(origin - before, origin + size + after - extent)
    }
    function _clampY(value) {
        const f = flickable
        return Math.max(_low(f.originY, f.topMargin),
                        Math.min(value, _high(f.originY, f.contentHeight, f.topMargin, f.bottomMargin, f.height)))
    }
    function _clampX(value) {
        const f = flickable
        return Math.max(_low(f.originX, f.leftMargin),
                        Math.min(value, _high(f.originX, f.contentWidth, f.leftMargin, f.rightMargin, f.width)))
    }
    function _canScrollX() { return flickable.contentWidth + flickable.leftMargin + flickable.rightMargin > flickable.width }
    function _canScrollY() { return flickable.contentHeight + flickable.topMargin + flickable.bottomMargin > flickable.height }

    // Moves one axis by `change` px (positive scrolls towards the start, as
    // wheel deltas do). Animated moves extend a running animation's target.
    function _move(anim, property, current, change, clamp, step, animate) {
        const from = anim.running ? anim.to : current
        const to = Math.round(clamp(from - change))
        if (to === from && !anim.running)
            return false
        anim.stop()
        const distance = Math.abs(to - current)
        // Proportional to the distance, capped at smoothDuration, at least
        // three 60 Hz frames; skipped for a pixel or two.
        const duration = animate && distance > 2
            ? Math.max(50, Math.min(smoothDuration, Math.round(distance * smoothDuration / Math.max(1, step))))
            : 0
        if (duration === 0) {
            flickable[property] = to
        } else {
            anim.from = current
            anim.to = to
            anim.duration = duration
            anim.start()
        }
        return true
    }

    // Touchpad samples for synthetic momentum: [time ms, dx, dy].
    property var _samples: []
    property bool _nativeMomentum: false

    function _record(dx, dy) {
        const now = Date.now()
        const s = _samples
        if (s.length && now - s[s.length - 1][0] > 100)
            s.length = 0
        s.push([now, dx, dy])
        while (s.length > 7)
            s.shift()
    }

    // Kirigami's inertia: the last samples' speed times 2.5, decelerating at
    // 10000 px/s², bounded to the content.
    function _startMomentum() {
        const s = _samples
        _samples = []
        if (s.length < 3)
            return
        const elapsed = Math.max(1, s[s.length - 1][0] - s[0][0])
        let tx = 0, ty = 0
        for (let i = 0; i < s.length; ++i) {
            tx += s[i][1]
            ty += s[i][2]
        }
        const factor = 2.5
        const decel = 4000 * factor
        _fling(xMomentum, "contentX", -tx * 1000 / elapsed * factor, decel, _clampX)
        _fling(yMomentum, "contentY", -ty * 1000 / elapsed * factor, decel, _clampY)
    }
    function _fling(anim, property, velocity, decel, clamp) {
        if (Math.abs(velocity) < 50)
            return
        const start = flickable[property]
        const time = Math.abs(velocity / decel)
        const end = start + time * velocity / 2
        const bounded = clamp(end)
        if (bounded === start)
            return
        // OutQuad covers (bounded - start)/(end - start) of the way in
        // time * (1 - sqrt(1 - fraction)).
        const fraction = Math.min(1, (bounded - start) / (end - start))
        anim.from = start
        anim.to = bounded
        anim.duration = Math.max(1, Math.round(time * (1 - Math.sqrt(1 - fraction)) * 1000))
        anim.start()
    }

    /// Handles one wheel event; `event` needs angleDelta, pixelDelta, phase
    /// and modifiers. Returns whether the view moved. Public for tests.
    function handleWheel(event) {
        const f = flickable
        if (!f || !f.interactive || !f.visible)
            return false
        const gesture = event.phase !== Qt.NoScrollPhase
        if (event.phase === Qt.ScrollBegin) {
            stop()
            _samples = []
        }
        if (event.phase === Qt.ScrollMomentum) {
            // The platform's own inertia: no synthetic momentum after it.
            _nativeMomentum = true
            _samples = []
        }
        if (event.phase === Qt.ScrollEnd) {
            if (syntheticMomentum && !_nativeMomentum)
                _startMomentum()
            _samples = []
            return false
        }

        let dx, dy
        if (gesture) {
            // A null pixel delta inside a gesture is rounding of slow
            // finger motion, not a wheel notch: stand still.
            dx = event.pixelDelta.x
            dy = event.pixelDelta.y
        } else {
            dx = event.angleDelta.x / 120 * horizontalStepSize
            dy = event.angleDelta.y / 120 * verticalStepSize
        }
        // Shift, or a view that only scrolls sideways, turns the wheel horizontal.
        const sideways = _canScrollX() && !_canScrollY()
        if ((sideways || (event.modifiers & Qt.ShiftModifier)) && dx === 0) {
            dx = gesture ? dy : dy / verticalStepSize * horizontalStepSize
            dy = 0
        }
        if (dx === 0 && dy === 0)
            return false

        f.cancelFlick()
        xMomentum.stop()
        yMomentum.stop()
        if (gesture) {
            xAnim.stop()
            yAnim.stop()
            _record(dx, dy)
        }
        const animate = smoothScroll && !gesture
        let moved = false
        if (dx !== 0 && _canScrollX())
            moved = _move(xAnim, "contentX", f.contentX, dx, _clampX, horizontalStepSize, animate) || moved
        if (dy !== 0 && _canScrollY())
            moved = _move(yAnim, "contentY", f.contentY, dy, _clampY, verticalStepSize, animate) || moved
        return moved
    }

    // Connected rather than `onWheel`, so a view that declares its own
    // `onWheel` on this handler (to observe events) does not replace it.
    Component.onCompleted: wheel.connect(handleWheel)

    // A WheelHandler has no default property: helpers live in properties.
    readonly property NumberAnimation _xAnim: NumberAnimation {
        id: xAnim
        target: scroller.flickable
        property: "contentX"
        easing.type: Easing.OutCubic
    }
    readonly property NumberAnimation _yAnim: NumberAnimation {
        id: yAnim
        target: scroller.flickable
        property: "contentY"
        easing.type: Easing.OutCubic
    }
    readonly property NumberAnimation _xMomentum: NumberAnimation {
        id: xMomentum
        target: scroller.flickable
        property: "contentX"
        easing.type: Easing.OutQuad
    }
    readonly property NumberAnimation _yMomentum: NumberAnimation {
        id: yMomentum
        target: scroller.flickable
        property: "contentY"
        easing.type: Easing.OutQuad
    }

    // Any direct manipulation of the view takes over from the wheel.
    readonly property Connections _viewWatch: Connections {
        target: scroller.flickable
        function onDraggingChanged() { if (scroller.flickable.dragging) scroller.stop() }
        function onFlickStarted() { scroller.stop() }
        function onContentHeightChanged() {
            // Content that shrank under a running animation: keep the target valid.
            if (yAnim.running && scroller._clampY(yAnim.to) !== yAnim.to) {
                yAnim.stop()
                scroller.flickable.contentY = scroller._clampY(scroller.flickable.contentY)
            }
        }
    }
}
