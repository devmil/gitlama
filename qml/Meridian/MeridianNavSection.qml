import QtQuick

// A sidebar section (Flutter: MeridianNavSection): an `overline` title in
// `ink-muted`, `space-4` above, with optional `actions` that show while the
// section is hovered or they hold focus, and an optional quiet count. Put
// the rows in the section; they stack below the title.
Item {
    id: root

    property string title
    property int count: -1
    /// Header actions (small icon buttons), revealed on hover.
    property alias actions: actionRow.data
    default property alias rows: rowColumn.data

    readonly property bool showActions: Theme.touch || header.hovered || actionRow.activeFocus

    implicitWidth: Metrics.sidebarMinWidth
    implicitHeight: Theme.space.s4 + headerItem.height + rowColumn.implicitHeight

    Item {
        id: headerItem
        y: Theme.space.s4
        width: parent.width
        height: Math.max(Metrics.navSectionHeight, Theme.size.minTarget)
        HoverHandler { id: header }

        MeridianText {
            x: Theme.touch ? Theme.space.s6 : Theme.space.s4
            anchors.verticalCenter: parent.verticalCenter
            width: actionRow.x - x - Theme.space.s2
            role: MeridianText.Overline
            text: root.title
            color: Theme.colors.inkMuted
            Accessible.role: Accessible.Heading
            Accessible.name: root.title
        }
        Row {
            id: actionRow
            anchors.right: countPill.visible ? countPill.left : parent.right
            anchors.rightMargin: countPill.visible ? Theme.space.s2 : (Theme.touch ? Theme.space.s6 : Theme.space.s4) - Theme.space.s2
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.showActions ? 1 : 0
            enabled: root.showActions
            Behavior on opacity { NumberAnimation { duration: Motion.hoverFor(root.showActions) } }
        }
        MeridianCount {
            id: countPill
            visible: root.count >= 0
            anchors.right: parent.right
            anchors.rightMargin: Theme.touch ? Theme.space.s6 : Theme.space.s4
            anchors.verticalCenter: parent.verticalCenter
            tone: MeridianCount.Quiet
            label: String(root.count)
        }
    }
    Column {
        id: rowColumn
        y: headerItem.y + headerItem.height
        width: parent.width
    }
}
