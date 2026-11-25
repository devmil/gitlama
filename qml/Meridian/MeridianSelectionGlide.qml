import QtQuick

// The selection bar of a fixed-extent scrolling list (Flutter: MeridianSelectionGlide; MM-20).
// Declare it inside the ListView: it lands in the view's content under the rows, so it
// scrolls with them at every frame. A new `selectedIndex` springs there on `spring-snappy`;
// jumps longer than `glide-max-rows`, or from or to a row outside the viewport, place the bar
// at once and fade it in over `motion-quick`. Rows paint their selected fill transparent
// while a glide paints it for them. -1 hides the bar. Reduce motion jumps.
//
// The default bar is MeridianSelectionFill's: `accent-soft` (`accent` when `solid`),
// `radius-sm`; put an item inside for another.
Item {
    id: root

    /// The list the bar belongs to.
    required property Flickable view
    property real itemExtent: Theme.size.row
    property int selectedIndex: -1
    /// The y of the first row in the view's content (a header above it).
    property real originY: 0
    /// The island has keyboard focus: the default bar is solid `accent`.
    property bool solid: false
    default property alias indicator: custom.data

    property real _index: 0
    property real _fade: 1
    property int _previous: -1

    parent: view ? view.contentItem : null
    x: 0
    y: (view ? view.originY : 0) + originY + _index * itemExtent
    z: -1
    width: view ? view.width - (view.leftMargin ?? 0) - (view.rightMargin ?? 0) : 0
    height: itemExtent
    visible: selectedIndex >= 0
    opacity: _fade

    Component.onCompleted: _follow()
    onSelectedIndexChanged: _follow()

    function _follow() {
        const from = _previous
        const to = selectedIndex
        _previous = to
        if (to < 0 || from === to)
            return
        if (from < 0 || Motion.reduced) {
            glide.stop()
            fade.stop()
            _index = to
            _fade = 1
            return
        }
        if (Math.abs(to - from) <= Motion.glideMaxRows && _shown(_index) && _shown(to)) {
            fade.stop()
            _fade = 1
            glide.stop()
            glide.to = to
            glide.start()
        } else {
            glide.stop()
            _index = to
            _fade = 0
            fade.restart()
        }
    }

    /// Whether row `index` shows in the viewport.
    function _shown(index) {
        if (!view || view.height <= 0)
            return true
        const top = view.originY + originY + index * itemExtent - view.contentY
        return top + itemExtent > 0 && top < view.height
    }

    NumberAnimation {
        id: glide
        target: root
        property: "_index"
        duration: Motion.snappy.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.snappy.curve
    }
    NumberAnimation {
        id: fade
        target: root
        property: "_fade"
        to: 1
        duration: Motion.quick
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.standard
    }

    Rectangle {
        anchors.fill: parent
        visible: custom.children.length === 0
        radius: Theme.radius.sm
        color: root.solid ? Theme.colors.accent : Theme.colors.accentSoft
        Behavior on color { ColorAnimation { duration: Motion.select } }
    }
    Item {
        id: custom
        anchors.fill: parent
    }
}
