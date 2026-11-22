import QtQuick
import QtQuick.Templates as T

// A sidebar row on `ground` (Flutter: MeridianNavRow): a folder, a label, a
// view. `current` marks where the person is; while the sidebar holds keyboard
// focus (`sidebarFocused`) the current row is solid `accent`. Arrow right and
// left expand and collapse an `expandable` row. `dropState` paints drag
// feedback (mail dragged onto a folder); the app owns the drag target.
T.ItemDelegate {
    id: control

    enum Drop { None, Accept, Reject }

    property string iconName
    property color iconColor: "transparent"
    property int count: 0
    /// Unread counts are `accent`; other counts are quiet.
    property bool countEmphasized: false
    property int depth: 0
    property bool expandable: false
    property bool expanded: false
    property bool current: false
    /// Marked like `current` but without the strong label (a chosen item
    /// rather than where the person is).
    property bool selected: false
    readonly property bool marked: current || selected
    property bool sidebarFocused: false
    property int dropState: MeridianNavRow.None
    /// Text at the trailing edge instead of a count (a PID, "now").
    property string trailingText
    /// A leading item instead of the icon (an avatar, a process icon).
    property alias leadingContent: leadingSlot.data
    readonly property bool hasLeading: leadingSlot.children.length > 0

    signal toggleExpanded()
    signal contextMenuRequested(real x, real y)

    readonly property bool solid: marked && sidebarFocused
    readonly property color fillColor: dropState === MeridianNavRow.Accept ? Theme.colors.accentSoft
        : solid ? Theme.colors.accent
        : marked ? Theme.colors.accentSoft
        : down ? Theme.pressed(Theme.colors.groundHover)
        : hovered ? Theme.colors.groundHover
        : Theme.clear(Theme.colors.groundHover)
    readonly property color inkColor: !enabled || dropState === MeridianNavRow.Reject ? Theme.colors.inkFaint
        : dropState === MeridianNavRow.Accept ? Theme.colors.accentInk
        : solid ? Theme.colors.inkOnAccent
        : Theme.colors.ink
    readonly property color mutedInk: solid ? Theme.colors.inkOnAccentMuted : Theme.colors.inkMuted

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    highlighted: marked
    implicitHeight: Math.max(Theme.size.row, Theme.type.bodyLineHeight + 2 * Theme.space.s1)
    implicitWidth: Metrics.sidebarMinWidth
    leftPadding: Theme.space.s4 + depth * Metrics.treeIndent
    rightPadding: Theme.space.s4
    topPadding: 0
    bottomPadding: 0

    Accessible.role: Accessible.ListItem
    Accessible.name: count > 0 ? text + ", " + count : text
    Accessible.selected: marked

    Keys.onRightPressed: event => {
        if (expandable && !expanded) { toggleExpanded(); event.accepted = true } else event.accepted = false
    }
    Keys.onLeftPressed: event => {
        if (expandable && expanded) { toggleExpanded(); event.accepted = true } else event.accepted = false
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (point) => control.contextMenuRequested(point.position.x, point.position.y)
    }

    contentItem: Item {
        MeridianIconButton {
            id: chevron
            visible: control.expandable
            x: -width - Theme.space.s1
            anchors.verticalCenter: parent.verticalCenter
            extent: Metrics.chevronSize + 4
            implicitWidth: Theme.touch ? Theme.size.minTarget : extent
            implicitHeight: implicitWidth
            iconName: "chevron-right"
            text: control.text
            turns: control.expanded ? 0.25 : 0
            focusPolicy: Qt.NoFocus
            surfaceColor: control.fillColor
            onClicked: control.toggleExpanded()
        }
        Item {
            id: leadingSlot
            visible: control.hasLeading
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
        MeridianIcon {
            id: glyph
            visible: control.iconName.length > 0 && !control.hasLeading
            anchors.verticalCenter: parent.verticalCenter
            name: control.iconName
            color: control.iconColor.a > 0 && !control.solid ? control.iconColor : control.mutedInk
        }
        MeridianText {
            anchors.verticalCenter: parent.verticalCenter
            x: control.hasLeading ? leadingSlot.width + Theme.space.s4 : glyph.visible ? glyph.width + Theme.space.s4 : 0
            width: parent.width - x - (countText.visible ? countText.width + Theme.space.s4 : 0)
            elide: Text.ElideRight
            role: control.current ? MeridianText.BodyStrong : MeridianText.Body
            text: control.text
            color: control.inkColor
        }
        MeridianText {
            id: countText
            visible: control.count > 0 || control.trailingText.length > 0
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width - width
            role: control.trailingText.length > 0 ? MeridianText.CodeSm
                : control.countEmphasized ? MeridianText.Label : MeridianText.Caption
            text: control.trailingText.length > 0 ? control.trailingText : control.count
            color: control.countEmphasized && !control.solid ? Theme.colors.accentInk : control.mutedInk
            tabular: true
        }
    }

    background: Rectangle {
        radius: Theme.radius.sm
        color: control.fillColor
        border.width: control.dropState === MeridianNavRow.Accept ? 1 : 0
        border.color: Theme.colors.accent
        Behavior on color { ColorAnimation { duration: control.marked ? Motion.select : Motion.hoverFor(control.hovered) } }
        MeridianFocusRing {
            target: control
            shown: control.visualFocus
            targetRadius: Theme.radius.sm
        }
    }
}
