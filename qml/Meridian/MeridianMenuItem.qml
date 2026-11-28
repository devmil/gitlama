import QtQuick
import QtQuick.Templates as T

// One command in a MeridianMenu. `text` names the object for real ("Move
// Quarterly report to archive"). Optional `iconName` or `dotColor` (a
// label's colour), `shortcut` and `hint` at the right, `checkable`/`checked`,
// `danger` for destructive commands (last, after a separator).
T.MenuItem {
    id: control

    property string iconName
    property color dotColor: "transparent"
    property string shortcut
    property string hint
    property bool danger: false

    // A menu that opened under a resting pointer shows no hover highlight
    // until the pointer moves; keyboard highlights show at once.
    readonly property bool pointerWaiting: hovered && !!(menu as MeridianMenu) && !(menu as MeridianMenu).pointerArmed
    readonly property bool highlightedRow: highlighted && enabled && !pointerWaiting
    readonly property color inkColor: !enabled ? Theme.colors.inkFaint
        : highlightedRow ? (danger ? Theme.colors.inkOnDanger : Theme.colors.inkOnAccent)
        : danger ? Theme.colors.danger : Theme.colors.ink
    readonly property color mutedInk: highlightedRow ? (danger ? Theme.colors.inkOnDanger : Theme.colors.inkOnAccentMuted)
        : Theme.colors.inkMuted

    icon.name: iconName
    hoverEnabled: true
    HoverHandler {
        enabled: !!(control.menu as MeridianMenu) && !(control.menu as MeridianMenu).pointerArmed
        onPointChanged: if (hovered) (control.menu as MeridianMenu).notePointer(point.scenePosition)
    }
    implicitWidth: Math.max(Metrics.menuMinWidth, Math.ceil(implicitContentWidth + leftPadding + rightPadding))
    implicitHeight: visible ? Math.max(Theme.size.row, Theme.type.bodyLineHeight + 2 * Theme.space.s1) : 0
    leftPadding: Theme.space.s4
    rightPadding: Theme.space.s4
    topPadding: 0
    bottomPadding: 0

    Accessible.role: Accessible.MenuItem
    Accessible.name: text

    indicator: Item {}
    arrow: MeridianIcon {
        x: control.width - control.rightPadding - width
        anchors.verticalCenter: parent.verticalCenter
        visible: control.subMenu !== null
        name: "chevron-right"
        iconSize: MeridianIcon.Small
        color: control.mutedInk
    }

    contentItem: Item {
        readonly property real slot: Theme.size.icon + Theme.space.s4
        readonly property real trailing: (hintText.visible ? hintText.implicitWidth + Theme.space.s5 : 0)
            + (keys.visible ? keys.implicitWidth + Theme.space.s5 : 0)
            + (control.subMenu ? Theme.size.iconSmall + Theme.space.s4 : 0)
        implicitWidth: slot + label.implicitWidth + trailing
        implicitHeight: Theme.type.bodyLineHeight

        MeridianIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: control.checked || control.iconName.length > 0
            name: control.checked ? "check" : control.iconName
            color: control.checked ? control.inkColor : control.mutedInk
        }
        Rectangle {
            visible: !control.checked && control.iconName.length === 0 && control.dotColor.a > 0
            anchors.verticalCenter: parent.verticalCenter
            x: (Theme.size.icon - width) / 2
            width: Metrics.statusDot + 2
            height: width
            radius: width / 2
            color: control.dotColor
        }
        MeridianText {
            id: label
            x: parent.slot
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - x - parent.trailing)
            text: control.text
            color: control.inkColor
        }
        MeridianText {
            id: hintText
            visible: control.hint.length > 0
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width - width - (keys.visible ? keys.implicitWidth + Theme.space.s5 : 0)
               - (control.subMenu ? Theme.size.iconSmall + Theme.space.s4 : 0)
            role: MeridianText.Caption
            text: control.hint
            color: control.mutedInk
        }
        MeridianText {
            id: keys
            visible: control.shortcut.length > 0
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width - width - (control.subMenu ? Theme.size.iconSmall + Theme.space.s4 : 0)
            role: MeridianText.Caption
            text: control.shortcut
            color: control.mutedInk
        }
    }

    background: Rectangle {
        x: Theme.space.s2
        width: control.width - 2 * Theme.space.s2
        radius: Theme.radius.sm
        // The highlight moves to the hovered or keyboard row at once.
        color: control.highlightedRow ? (control.danger ? Theme.colors.danger : Theme.colors.accent)
                                      : "transparent"
    }
}
