pragma ComponentBehavior: Bound
import QtQuick
import "travel.js" as Travel

// Flies a snapshot of an item from its old place to its new one (Flutter: MeridianTravel;
// NH-1, NH-4): a row moving between lists or into a new home, on `spring-gentle`.
//
// Wrap both the source and the destination. Before the change that moves the item, call
// `capture()` on the source; the next MeridianTravel with the same `travelKey` that appears
// (another instance than the source) flies in from there. Its real content stays hidden
// until the flight lands. One flight per window: a new one lands the previous one at once.
// A capture older than `motion-celebrate` is dropped. Reduce motion: no flight.
//
// Put one item inside; the travel takes its implicit size.
Item {
    id: root

    property string travelKey: ""
    /// Paints the flying snapshot raised: `raised` fill and `shadow-float`.
    property bool raised: true
    property real radius: Theme.radius.sm
    default property alias content: holder.data
    readonly property bool flying: _flight !== null

    readonly property Item _child: holder.children.length > 0 ? holder.children[0] : null
    property Item _flight: null
    property var _capture: null
    property real _t: 1

    implicitWidth: _child ? _child.implicitWidth : 0
    implicitHeight: _child ? _child.implicitHeight : 0

    /// Records this item's place and image for its key.
    function capture() {
        if (Motion.reduced || travelKey.length === 0 || !visible || width <= 0 || height <= 0 || !Window.window)
            return
        const at = mapToItem(null, 0, 0)
        const key = travelKey
        const window = Window.window
        const started = Date.now()
        holder.grabToImage(result => {
            Travel.put(key, { source: root, window: window, x: at.x, y: at.y, width: root.width,
                              height: root.height, image: result, at: started })
        })
    }

    /// Whether a flight is on screen (tests).
    function anyFlying() {
        return Travel.flying()
    }

    /// Ends the flight at once.
    function land() {
        if (_flight === null)
            return
        flight.stop()
        const item = _flight
        _flight = null
        item.destroy()
        _capture = null
        Travel.landed(Window.window, root)
        holder.opacity = 1
    }

    Component.onCompleted: _check()
    Component.onDestruction: land()
    onTravelKeyChanged: _check()

    function _check() {
        if (travelKey.length > 0 && Travel.peek(travelKey) !== null)
            Qt.callLater(() => root._consume())
    }

    function _consume() {
        const capture = Travel.peek(travelKey)
        if (capture === null || capture.source === root)
            return
        Travel.take(travelKey)
        if (Date.now() - capture.at > Motion.celebrate || Motion.reduced || !Window.window
                || capture.window !== Window.window)
            return
        const to = mapToItem(null, 0, 0)
        if (Math.hypot(to.x - capture.x, to.y - capture.y) < 1)
            return
        Travel.fly(Window.window, root)
        land()
        _capture = capture
        _flight = flightComponent.createObject(Window.contentItem, { capture: capture })
        holder.opacity = 0
        _t = 0
        flight.restart()
    }

    onXChanged: _follow()
    onYChanged: _follow()
    on_TChanged: _follow()

    // The flight follows the destination as it settles or scrolls.
    function _follow() {
        if (_flight === null)
            return
        const capture = _capture
        const to = mapToItem(null, 0, 0)
        _flight.x = capture.x + (to.x - capture.x) * _t
        _flight.y = capture.y + (to.y - capture.y) * _t
        _flight.width = capture.width + (width - capture.width) * _t
        _flight.height = capture.height + (height - capture.height) * _t
    }

    NumberAnimation {
        id: flight
        target: root
        property: "_t"
        to: 1
        duration: Motion.gentle.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.gentle.curve
        onFinished: root.land()
    }

    Component {
        id: flightComponent
        Item {
            id: flyingItem
            property var capture
            z: 1000000
            x: capture.x
            y: capture.y
            width: capture.width
            height: capture.height
            MeridianShadow {
                anchors.fill: parent
                visible: root.raised
                layers: Theme.shadows.float
                radius: root.radius
            }
            Rectangle {
                anchors.fill: parent
                visible: root.raised
                radius: root.radius
                color: Theme.colors.raised
            }
            Image {
                anchors.fill: parent
                source: flyingItem.capture.image.url
                smooth: true
            }
        }
    }

    Item {
        id: holder
        anchors.fill: parent
    }
}
