import QtQuick
import QtQuick.Templates as T

// A row in an island list (Flutter: MeridianListRow). The selection is an
// inset rounded bar: solid `accent` while the list's island has keyboard
// focus (`islandFocused`), `accent-soft` elsewhere. `hoverActions` (small
// MeridianIconButtons) replace `meta` on hover or keyboard focus; every hover
// action also belongs in the row's context menu.
//
// Keep it stateless for delegate reuse: bind every property to the model.
T.ItemDelegate {
    id: control

    property string subtitle
    property bool twoLine: false
    property string meta
    property string iconName
    property bool selected: false
    property bool islandFocused: false
    property bool emphasized: false
    property bool dimmed: false
    /// A filter or search query: its case-insensitive occurrences in the
    /// title are set in `accent`, bold and underlined (`on-accent` on a solid
    /// selection).
    property string match
    default property alias hoverActions: actionRow.data

    signal contextMenuRequested(real x, real y)

    readonly property bool solid: selected && islandFocused
    readonly property bool actionsShown: actionRow.children.length > 0
        && (hovered || activeFocus || actionRow.activeFocusInside)
    readonly property color fillColor: solid ? Theme.colors.accent
        : selected ? Theme.colors.accentSoft
        : down ? Theme.pressed(Theme.colors.paneHover)
        : hovered ? Theme.colors.paneHover
        : Theme.clear(Theme.colors.paneHover)
    readonly property color inkColor: !enabled ? Theme.colors.inkFaint : solid ? Theme.colors.inkOnAccent : Theme.colors.ink
    readonly property color mutedInk: !enabled ? Theme.colors.inkFaint : solid ? Theme.colors.inkOnAccentMuted : Theme.colors.inkMuted

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    highlighted: selected
    opacity: dimmed ? Metrics.opacityDimmedRow : 1
    implicitHeight: Math.max(Theme.size.row + (twoLine ? (Theme.touch ? 20 : 16) : 0),
                             (twoLine ? 2 : 1) * Theme.type.bodyLineHeight + 2 * Theme.space.s1)
    leftPadding: Theme.space.s4
    rightPadding: Theme.space.s4
    topPadding: 0
    bottomPadding: 0

    Accessible.role: Accessible.ListItem
    Accessible.name: subtitle.length > 0 ? text + ", " + subtitle : text
    Accessible.selected: selected

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (point) => control.contextMenuRequested(point.position.x, point.position.y)
    }

    contentItem: Item {
        readonly property real trailing: control.actionsShown ? actionRow.width + Theme.space.s4
            : metaText.visible ? metaText.implicitWidth + Theme.space.s4 : 0
        MeridianIcon {
            id: glyph
            visible: control.iconName.length > 0
            y: control.twoLine ? (Theme.type.bodyLineHeight - height) / 2 + Theme.space.s1 : (parent.height - height) / 2
            name: control.iconName
            color: control.mutedInk
        }
        MeridianText {
            id: title
            x: glyph.visible ? glyph.width + Theme.space.s4 : 0
            y: control.twoLine ? Theme.space.s1 : (parent.height - height) / 2
            width: control.twoLine || control.subtitle.length === 0
                   ? parent.width - x - parent.trailing
                   : Math.min(implicitWidth, parent.width - x - parent.trailing)
            role: control.emphasized ? MeridianText.BodyStrong : MeridianText.Body
            readonly property string query: control.match.trim()
            textFormat: query.length > 0 ? Text.StyledText : Text.PlainText
            text: query.length > 0
                  ? Theme.highlightMatches(control.text, query,
                        !control.enabled ? Theme.colors.inkFaint : control.solid ? Theme.colors.inkOnAccent : Theme.colors.accent)
                  : control.text
            color: control.inkColor
        }
        MeridianText {
            visible: control.subtitle.length > 0
            x: control.twoLine ? title.x : title.x + title.width + Theme.space.s4
            y: control.twoLine ? title.y + title.height : title.y
            width: control.twoLine ? title.width : Math.max(0, parent.width - x - parent.trailing)
            role: control.twoLine ? MeridianText.Caption : MeridianText.Body
            text: control.subtitle
            color: control.mutedInk
        }
        MeridianText {
            id: metaText
            visible: control.meta.length > 0 && !control.actionsShown
            anchors.verticalCenter: control.twoLine ? undefined : parent.verticalCenter
            y: control.twoLine ? title.y : 0
            x: parent.width - width
            role: MeridianText.Caption
            text: control.meta
            color: control.mutedInk
            tabular: true
        }
        Row {
            id: actionRow
            objectName: "listRowActions"
            readonly property bool activeFocusInside: {
                for (let i = 0; i < children.length; ++i)
                    if (children[i].activeFocus)
                        return true
                return false
            }
            x: parent.width - width
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s1
            opacity: control.actionsShown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: control.actionsShown ? Motion.hover : Motion.exit } }
        }
    }

    background: Rectangle {
        radius: Theme.radius.sm
        color: control.fillColor
        Behavior on color { ColorAnimation { duration: control.selected ? Motion.select : Motion.hoverFor(control.hovered) } }
        MeridianFocusRing {
            target: control
            shown: control.visualFocus
            targetRadius: Theme.radius.sm
        }
    }
}
