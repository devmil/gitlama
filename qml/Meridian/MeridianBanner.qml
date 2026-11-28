import QtQuick

// A persistent inline message about the state of the island or screen it
// sits in (Flutter: MeridianBanner). Say what happened, then what to do.
// Transient results are toasts, not banners. At most two small actions:
// put MeridianButtons (controlSize: Small) in `actions`. They sit at the
// right, centred on the text; at touch density and below 480px they go under
// the text.
Item {
    id: root

    enum Tone { Info, Success, Warning, Attention, Error }

    property int tone: MeridianBanner.Info
    property string title
    property string message
    property string iconName: ["info", "circle-check", "triangle-alert", "circle-alert", "circle-x"][tone]
    property bool dismissible: false
    property string dismissLabel
    /// Reveals and collapses with `motion-layout`.
    property bool shown: true
    default property alias actions: actionRow.data

    signal dismissed()

    readonly property color fillColor: [Theme.colors.paneAlt, Theme.colors.successBg, Theme.colors.warningBg,
        Theme.colors.attentionBg, Theme.colors.dangerBg][tone]
    readonly property color toneInk: [Theme.colors.accentInk, Theme.colors.success, Theme.colors.warning,
        Theme.colors.attention, Theme.colors.danger][tone]
    readonly property bool stacked: Theme.touch || width < 480
    readonly property bool hasActions: actionRow.children.length > 0

    implicitWidth: 480
    implicitHeight: shown ? body.height : 0
    clip: true
    opacity: shown ? 1 : 0
    visible: height > 0 || opacity > 0
    Behavior on implicitHeight {
        NumberAnimation { duration: Motion.layout; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
    }
    Behavior on opacity { NumberAnimation { duration: Motion.fade(root.shown ? Motion.layout : Motion.exit) } }

    Rectangle {
        id: body
        readonly property real pad: Theme.space.s5
        width: parent.width
        height: Math.max(text.height, root.stacked ? 0 : actionRow.height, dismiss.height)
                + (root.stacked && root.hasActions ? Theme.space.s4 + actionRow.height : 0) + 2 * pad
        radius: Theme.radius.lg
        color: root.fillColor
        Behavior on color { ColorAnimation { duration: Motion.select } }

        MeridianIcon {
            id: glyph
            x: body.pad
            y: body.pad + Math.max(0, (Theme.type.bodyLineHeight - height) / 2)
            name: root.iconName
            color: root.toneInk
        }
        Column {
            id: text
            x: glyph.x + glyph.width + Theme.space.s4
            y: body.pad + (root.stacked ? 0 : Math.max(0, (actionRow.height - height) / 2))
            width: body.width - x - body.pad
                   - (dismiss.visible ? dismiss.width + Theme.space.s3 : 0)
                   - (!root.stacked && root.hasActions ? actionRow.width + Theme.space.s4 : 0)
            Accessible.role: Accessible.AlertMessage
            Accessible.name: root.title.length > 0 ? root.title + " " + root.message : root.message
            MeridianText {
                width: parent.width
                visible: root.title.length > 0
                role: MeridianText.BodyStrong
                text: root.title
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            MeridianText {
                width: parent.width
                text: root.message
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
        }
        Row {
            id: actionRow
            spacing: Theme.space.s3
            x: root.stacked ? text.x : text.x + text.width + Theme.space.s4
            y: root.stacked ? text.y + text.height + Theme.space.s4
                            : body.pad + Math.max(0, (text.height - height) / 2)
        }
        MeridianIconButton {
            id: dismiss
            visible: root.dismissible
            x: body.width - body.pad - width
            y: body.pad
            iconName: "x"
            text: root.dismissLabel
            controlSize: MeridianButton.Small
            surfaceColor: root.fillColor
            onClicked: root.dismissed()
        }
    }
}
