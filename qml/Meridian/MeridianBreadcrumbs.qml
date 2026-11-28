pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T

// A path of crumbs (Flutter: MeridianBreadcrumbs): the first and the last
// crumb always show; when the trail is too wide, the crumbs after the first
// fold into "…" from the left, and the last one gives way with an ellipsis.
//
// `crumbs` are {label, mono, emphasis, icon, prefix, enabled, semanticLabel}:
// `icon` and `prefix` (small monospace text, a short hash) lead the label;
// an `enabled` crumb activates. Activating "…" emits `overflowRequested`
// with the hidden crumbs' indices.
Item {
    id: root

    property var crumbs: []
    property string overflowLabel
    property string semanticLabel

    signal activated(int index)
    signal contextMenuRequested(int index, real x, real y)
    signal overflowRequested(var hidden, real x, real y)

    readonly property int count: crumbs.length
    /// Each crumb's natural width, published by its delegate.
    property var _widths: []
    function _publishWidth(index, width) {
        if (_widths[index] === width)
            return
        const next = _widths.slice(0, count)
        next[index] = width
        _widths = next
    }
    readonly property real separatorWidth: Theme.size.iconSmall + 2 * Theme.space.s1
    /// How many crumbs after the first are folded into "…".
    readonly property int folded: {
        if (count < 3)
            return 0
        const widths = []
        for (let i = 0; i < count; ++i)
            widths.push(_widths[i] ?? 0)
        const total = f => {
            let sum = 0
            for (let i = 0; i < count; ++i)
                if (i === 0 || i === count - 1 || i > f)
                    sum += widths[i]
            const shown = count - f + (f > 0 ? 1 : 0)
            return sum + (shown - 1) * separatorWidth + (f > 0 ? ellipsis.implicitWidth : 0)
        }
        for (let f = 0; f <= count - 2; ++f)
            if (total(f) <= width)
                return f
        return count - 2
    }

    implicitHeight: Theme.size.controlSmall
    clip: true

    Accessible.role: Accessible.Pane
    Accessible.name: semanticLabel

    component Crumb: T.AbstractButton {
        id: crumb
        property var data_: ({})
        property bool interactive: false
        property real maximumWidth: -1
        readonly property bool lit: interactive && (hovered || down)
        readonly property color ink: data_.emphasis === true || lit ? Theme.colors.ink : Theme.colors.inkMuted

        implicitWidth: leftPadding + rightPadding + content.implicitWidth
        implicitHeight: Theme.size.controlSmall
        width: maximumWidth >= 0 ? Math.min(implicitWidth, maximumWidth) : implicitWidth
        height: implicitHeight
        leftPadding: Theme.space.s2
        rightPadding: Theme.space.s2
        hoverEnabled: interactive
        focusPolicy: interactive ? Qt.StrongFocus : Qt.NoFocus
        enabled: true

        Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
        Accessible.name: data_.semanticLabel ?? data_.label ?? ""

        background: Rectangle {
            radius: Theme.radius.sm
            color: crumb.lit ? Theme.colors.paneHover : Theme.clear(Theme.colors.paneHover)
            Behavior on color { ColorAnimation { duration: Motion.hoverFor(crumb.lit) } }
            MeridianFocusRing { target: crumb; shown: crumb.visualFocus; targetRadius: Theme.radius.sm }
        }
        contentItem: Item {
            id: content
            // The natural width: leading parts and the whole label.
            implicitWidth: label.lead + label.implicitWidth
            implicitHeight: row.implicitHeight
            Row {
                id: row
                width: Math.min(implicitWidth, parent.width)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.s2
                MeridianIcon {
                    id: glyph
                    visible: (crumb.data_.icon ?? "").length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    name: crumb.data_.icon ?? ""
                    iconSize: MeridianIcon.Small
                    color: crumb.ink
                }
                MeridianText {
                    id: prefix
                    visible: (crumb.data_.prefix ?? "").length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    role: MeridianText.CodeSm
                    text: crumb.data_.prefix ?? ""
                    color: Theme.colors.inkMuted
                }
                MeridianText {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real lead: (glyph.visible ? glyph.width + row.spacing : 0)
                        + (prefix.visible ? prefix.implicitWidth + row.spacing : 0)
                    width: Math.max(0, Math.min(implicitWidth, content.width - lead))
                    role: crumb.data_.mono === true ? MeridianText.CodeSm
                        : crumb.data_.emphasis === true ? MeridianText.BodyStrong : MeridianText.Body
                    text: crumb.data_.label ?? ""
                    color: crumb.ink
                    elide: Text.ElideRight
                }
            }
        }
    }

    Row {
        id: trail
        height: parent.height
        spacing: 0

        Repeater {
            model: root.count
            delegate: Row {
                id: slot
                required property int index
                readonly property bool hiddenCrumb: index >= 1 && index <= root.folded && index < root.count - 1
                /// The crumb's natural width, without separators.
                readonly property real crumbWidth: crumbItem.implicitWidth
                onCrumbWidthChanged: root._publishWidth(index, crumbWidth)
                Component.onCompleted: root._publishWidth(index, crumbWidth)
                visible: !hiddenCrumb
                height: trail.height
                spacing: 0

                Item {
                    visible: slot.index > 0
                    width: root.separatorWidth
                    height: parent.height
                    MeridianIcon {
                        anchors.centerIn: parent
                        name: "chevron-right"
                        iconSize: MeridianIcon.Small
                        color: Theme.colors.inkFaint
                    }
                }
                Crumb {
                    id: crumbItem
                    anchors.verticalCenter: parent.verticalCenter
                    data_: root.crumbs[slot.index] ?? ({})
                    interactive: data_.enabled === true
                    // The last crumb gives way when the trail is still too wide.
                    maximumWidth: slot.index === root.count - 1
                        ? Math.max(0, root.width - slot.x - (slot.index > 0 ? root.separatorWidth : 0)) : -1
                    onClicked: root.activated(slot.index)
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: point => root.contextMenuRequested(slot.index, point.position.x, point.position.y)
                    }
                }
                // "…" stands after the first crumb while crumbs are folded.
                Row {
                    visible: slot.index === 0 && root.folded > 0
                    height: parent.height
                    Item {
                        width: root.separatorWidth
                        height: parent.height
                        MeridianIcon {
                            anchors.centerIn: parent
                            name: "chevron-right"
                            iconSize: MeridianIcon.Small
                            color: Theme.colors.inkFaint
                        }
                    }
                    Crumb {
                        anchors.verticalCenter: parent.verticalCenter
                        data_: ({ label: "…", semanticLabel: root.overflowLabel, enabled: true })
                        interactive: true
                        onClicked: {
                            const hidden = []
                            for (let i = 1; i <= root.folded; ++i)
                                hidden.push(i)
                            root.overflowRequested(hidden, x, y + height)
                        }
                    }
                }
            }
        }
    }

    // Measures "…" for the fold.
    Crumb {
        id: ellipsis
        visible: false
        data_: ({ label: "…" })
    }
}
