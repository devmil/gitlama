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
    /// Replaces `iconName`'s glyph at the start (Flutter: `leading`): a
    /// chevron, an indent, a status icon. It is centred on the first line.
    property Component leading: null
    /// After the title on its line (Flutter: `titleTrailing`): a status mark
    /// that belongs to the name.
    property Component titleTrailing: null
    /// At the end, after `meta` or the hover actions (Flutter: `trailing`):
    /// badges, counts, a short label.
    property Component trailing: null
    /// Read after the name by assistive technology (Flutter: `semanticValue`).
    property string semanticValue
    default property alias hoverActions: actionRow.data

    signal contextMenuRequested(real x, real y)

    readonly property bool solid: selected && islandFocused
    readonly property bool actionsShown: actionRow.children.length > 0
        && (hovered || activeFocus || actionRow.activeFocusInside)
    /// A MeridianSelectionGlide paints this row's selected fill.
    property bool selectionGlided: false
    readonly property color fillColor: selected && selectionGlided ? Theme.clear(solid ? Theme.colors.accent : Theme.colors.accentSoft)
        : solid ? Theme.colors.accent
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
    Accessible.description: semanticValue
    Accessible.selected: selected

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (point) => control.contextMenuRequested(point.position.x, point.position.y)
    }

    contentItem: Item {
        readonly property real firstLineY: control.twoLine ? Theme.space.s1 : 0
        readonly property real firstLineHeight: control.twoLine ? Theme.type.bodyLineHeight : height
        readonly property real start: leadingLoader.active ? leadingLoader.width + Theme.space.s4
            : glyph.visible ? glyph.width + Theme.space.s4 : 0
        readonly property real end: trailingLoader.active ? trailingLoader.width + Theme.space.s4 : 0
        readonly property real reserved: end + (control.actionsShown ? actionRow.width + Theme.space.s4
            : metaText.visible ? metaText.implicitWidth + Theme.space.s4 : 0)
        Loader {
            id: leadingLoader
            active: control.leading !== null
            sourceComponent: control.leading
            y: parent.firstLineY + (parent.firstLineHeight - height) / 2
        }
        MeridianIcon {
            id: glyph
            visible: !leadingLoader.active && control.iconName.length > 0
            y: parent.firstLineY + (parent.firstLineHeight - height) / 2
            name: control.iconName
            color: control.mutedInk
        }
        MeridianText {
            id: title
            x: parent.start
            y: control.twoLine ? Theme.space.s1 : (parent.height - height) / 2
            readonly property real available: parent.width - x - parent.reserved
                - (titleTrailingLoader.active ? titleTrailingLoader.width + Theme.space.s2 : 0)
            width: (control.twoLine || control.subtitle.length === 0) && !titleTrailingLoader.active
                   ? Math.max(0, available)
                   : Math.max(0, Math.min(implicitWidth, available))
            role: control.emphasized ? MeridianText.BodyStrong : MeridianText.Body
            readonly property string query: control.match.trim()
            textFormat: query.length > 0 ? Text.StyledText : Text.PlainText
            text: query.length > 0
                  ? Theme.highlightMatches(control.text, query,
                        !control.enabled ? Theme.colors.inkFaint : control.solid ? Theme.colors.inkOnAccent : Theme.colors.accent)
                  : control.text
            color: control.inkColor
        }
        Loader {
            id: titleTrailingLoader
            active: control.titleTrailing !== null
            sourceComponent: control.titleTrailing
            x: title.x + title.width + Theme.space.s2
            y: parent.firstLineY + (parent.firstLineHeight - height) / 2
        }
        MeridianText {
            readonly property real after: titleTrailingLoader.active
                ? titleTrailingLoader.x + titleTrailingLoader.width : title.x + title.width
            visible: control.subtitle.length > 0
            x: control.twoLine ? title.x : after + Theme.space.s4
            y: control.twoLine ? title.y + title.height : title.y
            width: control.twoLine ? parent.width - title.x - parent.reserved
                                   : Math.max(0, parent.width - x - parent.reserved)
            role: control.twoLine ? MeridianText.Caption : MeridianText.Body
            text: control.subtitle
            color: control.mutedInk
        }
        MeridianText {
            id: metaText
            visible: control.meta.length > 0 && !control.actionsShown
            anchors.verticalCenter: control.twoLine ? undefined : parent.verticalCenter
            y: control.twoLine ? title.y : 0
            x: parent.width - parent.end - width
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
            x: parent.width - parent.end - width
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s1
            opacity: control.actionsShown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: control.actionsShown ? Motion.hover : Motion.exit } }
        }
        Loader {
            id: trailingLoader
            objectName: "listRowTrailing"
            active: control.trailing !== null
            sourceComponent: control.trailing
            x: parent.width - width
            anchors.verticalCenter: control.twoLine ? undefined : parent.verticalCenter
            y: control.twoLine ? parent.firstLineY + (parent.firstLineHeight - height) / 2 : 0
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
