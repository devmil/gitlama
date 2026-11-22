pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

// Picks one of two to four peer options that change a view (Flutter:
// MeridianSegmented). Never for commands; more than four options is a Select.
//
// `segments` is an array of { value, label, icon, tooltip, enabled }. Arrow
// keys (and Home and End) move the selection and step over disabled
// segments; with `manualActivation` they move only the focus ring and Space
// or Enter selects. The raised tile glides to the chosen segment. Without
// `expand` the control hugs its labels; narrower than that, segments share
// the width and ellipsize.
T.Control {
    id: root

    property var segments: []
    property var value
    /// The group's accessible name.
    property string label
    property int controlSize: MeridianButton.Regular
    property bool manualActivation: false
    property bool expand: false

    signal activated(var value)

    readonly property int selectedIndex: _indexOf(value)
    property int focusIndex: selectedIndex >= 0 ? selectedIndex : 0
    readonly property real extent: controlSize === MeridianButton.Small ? Theme.size.controlSmall : Theme.size.control
    readonly property real inset: Metrics.segmentedTrackPadding
    property bool _keyboardNav: false
    // Geometry of the selected segment, published by that delegate, so the
    // tile follows it as segments resize (Repeater.itemAt in a binding would
    // not re-evaluate).
    property real _tileX: 0
    property real _tileWidth: 0

    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    padding: 0
    implicitHeight: Math.max(extent, Theme.type.labelLineHeight + 2 * Theme.space.s2)
    implicitWidth: row.implicitWidth + 2 * inset

    Accessible.role: Accessible.PageTabList
    Accessible.name: label

    onActiveFocusChanged: if (!activeFocus) _keyboardNav = false

    function _indexOf(v) {
        for (let i = 0; i < segments.length; ++i)
            if (segments[i].value === v)
                return i
        return -1
    }
    function _enabled(i) {
        return i >= 0 && i < segments.length && segments[i].enabled !== false
    }
    function _step(from, delta) {
        let i = from
        for (let n = 0; n <= segments.length; ++n) {
            i += delta
            if (i < 0 || i >= segments.length)
                return from
            if (_enabled(i))
                return i
        }
        return from
    }
    function _move(to) {
        _keyboardNav = true
        focusIndex = to
        if (!manualActivation && to !== selectedIndex && _enabled(to))
            activated(segments[to].value)
    }
    Keys.onLeftPressed: _move(_step(focusIndex, -1))
    Keys.onRightPressed: _move(_step(focusIndex, 1))
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) {
            _move(_step(-1, 1)); event.accepted = true
        } else if (event.key === Qt.Key_End) {
            _move(_step(segments.length, -1)); event.accepted = true
        } else if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                   && _enabled(focusIndex)) {
            _keyboardNav = true
            if (focusIndex !== selectedIndex)
                activated(segments[focusIndex].value)
            event.accepted = true
        }
    }

    background: Rectangle {
        radius: Theme.radius.md
        color: Theme.colors.paneAlt
        border.width: 1
        border.color: Theme.colors.line
    }

    contentItem: Item {
        Item {
            id: tile
            visible: root.selectedIndex >= 0 && root._tileWidth > 0
            x: row.x + root._tileX
            y: root.inset
            width: root._tileWidth
            height: root.height - 2 * root.inset
            Behavior on x { NumberAnimation { duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve } }
            Behavior on width { NumberAnimation { duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve } }
            MeridianShadow {
                anchors.fill: parent
                layers: Theme.shadows.control
                radius: Theme.radius.md - root.inset
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.radius.md - root.inset
                color: Theme.colors.pane
                border.width: 1
                border.color: Theme.colors.lineStrong
            }
        }

        // Segments hug their labels; in less space they share it and
        // ellipsize (minimum width 0); `expand` gives equal shares.
        RowLayout {
            id: row
            x: root.inset
            y: root.inset
            width: root.width - 2 * root.inset
            height: root.height - 2 * root.inset
            spacing: 0

            Repeater {
                id: repeater
                model: root.segments
                delegate: T.AbstractButton {
                    id: segment
                    objectName: "segment" + index
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.selectedIndex
                    readonly property bool usable: modelData.enabled !== false
                    readonly property bool iconOnlySegment: (modelData.label ?? "").length === 0
                    readonly property color ink: !usable ? Theme.colors.inkFaint
                        : selected || hovered ? Theme.colors.ink : Theme.colors.inkMuted

                    focusPolicy: Qt.NoFocus
                    hoverEnabled: true
                    Layout.fillHeight: true
                    // fillWidth lets a segment shrink below its label; without
                    // `expand` the maximum keeps it at its natural width.
                    Layout.fillWidth: true
                    Layout.preferredWidth: root.expand ? 1 : implicitWidth
                    Layout.maximumWidth: root.expand ? Number.POSITIVE_INFINITY : implicitWidth
                    Layout.minimumWidth: iconOnlySegment ? root.extent : 0
                    leftPadding: iconOnlySegment ? 0 : Theme.space.s5
                    rightPadding: leftPadding
                    // Rounded up: layouts snap widths to whole pixels, and a
                    // label a fraction too narrow would elide.
                    implicitWidth: iconOnlySegment ? root.extent
                        : Math.ceil((glyph.visible ? glyph.width + (caption.visible ? Theme.space.s2 : 0) : 0)
                                    + caption.implicitWidth + leftPadding + rightPadding)
                    text: modelData.label ?? ""
                    Accessible.role: Accessible.PageTab
                    Accessible.name: text.length > 0 ? text : (modelData.tooltip ?? "")
                    Accessible.selected: selected
                    onClicked: {
                        if (!usable)
                            return
                        root.forceActiveFocus(Qt.MouseFocusReason)
                        root._keyboardNav = false
                        root.focusIndex = index
                        if (!selected)
                            root.activated(modelData.value)
                    }

                    contentItem: Item {
                        implicitHeight: Theme.type.labelLineHeight
                        Row {
                            id: content
                            anchors.centerIn: parent
                            spacing: glyph.visible && caption.visible ? Theme.space.s2 : 0
                            MeridianIcon {
                                id: glyph
                                visible: (segment.modelData.icon ?? "").length > 0
                                name: segment.modelData.icon ?? ""
                                iconSize: MeridianIcon.Small
                                anchors.verticalCenter: parent.verticalCenter
                                color: segment.ink
                            }
                            MeridianText {
                                id: caption
                                visible: !segment.iconOnlySegment
                                role: MeridianText.Label
                                text: segment.text
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, segment.width - segment.leftPadding
                                                - segment.rightPadding - (glyph.visible ? glyph.width + Theme.space.s2 : 0))
                                color: segment.ink
                                Behavior on color { ColorAnimation { duration: Motion.select } }
                            }
                        }
                    }

                    Binding {
                        when: segment.selected
                        target: root
                        property: "_tileX"
                        value: segment.x
                        restoreMode: Binding.RestoreNone
                    }
                    Binding {
                        when: segment.selected
                        target: root
                        property: "_tileWidth"
                        value: segment.width
                        restoreMode: Binding.RestoreNone
                    }

                    MeridianFocusRing {
                        target: segment
                        shown: root.activeFocus && root.focusIndex === segment.index
                               && (root.visualFocus || root._keyboardNav)
                        targetRadius: Theme.radius.md - root.inset
                    }
                }
            }
        }
    }
}
