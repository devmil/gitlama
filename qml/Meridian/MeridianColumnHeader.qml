import QtQuick

// A table column heading (Flutter: MeridianColumnHeader): `caption` in
// `ink-muted`, `ink` and semibold with an arrow while it sorts, `pane-hover`
// on hover when it can be pressed. `contextMenuRequested` reports a
// secondary click.
Item {
    id: root

    enum Sort { None, Ascending, Descending }

    property string text
    property int sort: MeridianColumnHeader.None
    property bool alignEnd: false
    property bool pressable: true
    property string sortedAscendingLabel: "sorted ascending"
    property string sortedDescendingLabel: "sorted descending"

    signal clicked()
    signal contextMenuRequested(real x, real y)

    readonly property bool sorted: sort !== MeridianColumnHeader.None
    readonly property bool hovered: hover.hovered

    implicitWidth: label.implicitWidth + (arrow.visible ? Theme.space.s2 + arrow.width : 0) + 2 * Theme.space.s4
    implicitHeight: Theme.size.control

    Accessible.role: Accessible.ColumnHeader
    Accessible.name: text
    Accessible.description: sort === MeridianColumnHeader.Ascending ? sortedAscendingLabel
        : sort === MeridianColumnHeader.Descending ? sortedDescendingLabel : ""

    HoverHandler {
        id: hover
        cursorShape: root.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        id: tap
        enabled: root.pressable
        onTapped: root.clicked()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: point => root.contextMenuRequested(point.position.x, point.position.y)
    }

    Rectangle {
        anchors.fill: parent
        readonly property color hoverFill: root.pressable ? Theme.colors.paneHover : Theme.clear(Theme.colors.paneHover)
        color: tap.pressed ? Theme.pressed(hoverFill) : hover.hovered ? hoverFill : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.hoverFor(hover.hovered || tap.pressed) } }
    }
    Row {
        id: content
        spacing: Theme.space.s2
        anchors.verticalCenter: parent.verticalCenter
        x: root.alignEnd ? root.width - Theme.space.s4 - width : Theme.space.s4
        MeridianText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(implicitWidth,
                root.width - 2 * Theme.space.s4 - (arrow.visible ? arrow.width + content.spacing : 0)))
            role: MeridianText.Caption
            fontWeight: root.sorted ? Font.DemiBold : -1
            color: root.sorted ? Theme.colors.ink : Theme.colors.inkMuted
            text: root.text
        }
        MeridianIcon {
            id: arrow
            visible: root.sorted
            anchors.verticalCenter: parent.verticalCenter
            name: root.sort === MeridianColumnHeader.Ascending ? "arrow-up" : "arrow-down"
            extent: Metrics.sortIconSize
            color: Theme.colors.ink
        }
    }
}
