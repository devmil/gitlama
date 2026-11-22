import QtQuick

// A collapsible group (Flutter: MeridianDisclosure): a row-height header
// with a chevron that turns to point down, the `label`-styled title and an
// optional `trailing` item; the content reveals below, indented `space-6`.
Item {
    id: root

    property string title
    property bool expanded: false
    property alias trailing: trailingSlot.data
    default property alias content: body.data
    property bool onGround: false

    signal toggled(bool expanded)

    implicitWidth: 300
    implicitHeight: header.height + reveal.height
    clip: reveal.height < body.implicitHeight

    Accessible.role: Accessible.Grouping
    Accessible.name: title

    Item {
        id: header
        width: parent.width
        height: Theme.size.row
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.title
        Accessible.checked: root.expanded
        Keys.onSpacePressed: root.toggle()
        Keys.onReturnPressed: root.toggle()
        Keys.onRightPressed: if (!root.expanded) root.toggle()
        Keys.onLeftPressed: if (root.expanded) root.toggle()

        HoverHandler { id: hover }
        TapHandler { id: tap; onTapped: root.toggle() }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.sm
            readonly property color hoverFill: root.onGround ? Theme.colors.groundHover : Theme.colors.paneHover
            color: tap.pressed ? Theme.pressed(hoverFill) : hover.hovered ? hoverFill : Theme.clear(hoverFill)
            Behavior on color { ColorAnimation { duration: Motion.hoverFor(hover.hovered || tap.pressed) } }
            MeridianFocusRing { target: parent; shown: header.activeFocus; targetRadius: Theme.radius.sm }
        }
        MeridianIcon {
            id: chevron
            x: Theme.space.s2
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-right"
            extent: Metrics.chevronSize
            color: root.enabled ? Theme.colors.inkMuted : Theme.colors.inkFaint
            rotation: root.expanded ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Motion.quick; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard } }
        }
        MeridianText {
            x: chevron.x + chevron.width + Theme.space.s3
            width: trailingSlot.x - x - Theme.space.s2
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.Label
            text: root.title
            color: root.enabled ? Theme.colors.ink : Theme.colors.inkFaint
        }
        Item {
            id: trailingSlot
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s2
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    Item {
        id: reveal
        y: header.height
        width: parent.width
        height: root.expanded ? body.implicitHeight : 0
        clip: true
        opacity: root.expanded ? 1 : 0
        Behavior on height { NumberAnimation { duration: Motion.layout; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard } }
        Behavior on opacity { NumberAnimation { duration: Motion.fade(Motion.layout) } }
        Column {
            id: body
            x: Theme.space.s6
            width: parent.width - x
        }
    }

    function toggle() {
        expanded = !expanded
        toggled(expanded)
    }
}
