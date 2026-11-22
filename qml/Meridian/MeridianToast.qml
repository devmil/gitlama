import QtQuick

// One transient result ("Archived 3 messages"), with an optional action
// (Undo). Shown and replaced by MeridianToastHost; one toast at a time.
// Errors that need a decision are banners or dialogs, never toasts.
FocusScope {
    id: root

    enum Tone { Neutral, Success, Warning, Error }

    property string message
    property int tone: MeridianToast.Neutral
    property string actionLabel
    /// Remaining fraction of the countdown, for the time rule.
    property real remaining: 1
    readonly property bool paused: hover.hovered || root.activeFocus

    signal actionTriggered()

    readonly property string iconName: ["", "circle-check", "triangle-alert", "circle-x"][tone]
    readonly property color toneInk: [Theme.colors.ink, Theme.colors.success, Theme.colors.warning,
        Theme.colors.danger][tone]
    readonly property bool stacked: action.visible
        && messageText.implicitWidth + action.implicitWidth + 3 * Theme.space.s6 + glyphSpace > Metrics.toastWidth
    readonly property real glyphSpace: glyph.visible ? glyph.width + Theme.space.s4 : 0

    implicitWidth: Math.min(Metrics.toastWidth, messageText.implicitWidth + glyphSpace + 2 * Theme.space.s6
                            + (action.visible && !stacked ? action.implicitWidth + Theme.space.s4 : 0))
    implicitHeight: surface.implicitHeight

    Accessible.role: Accessible.AlertMessage
    Accessible.name: message

    HoverHandler { id: hover }

    MeridianSurface {
        id: surface
        anchors.fill: parent
        implicitHeight: messageText.height + (root.stacked ? Theme.space.s3 + action.height : 0) + 2 * Theme.space.s5

        MeridianIcon {
            id: glyph
            visible: root.iconName.length > 0
            x: Theme.space.s6
            y: Theme.space.s5 + (Theme.type.bodyLineHeight - height) / 2
            name: root.iconName
            color: root.toneInk
        }
        MeridianText {
            id: messageText
            x: Theme.space.s6 + root.glyphSpace
            y: Theme.space.s5
            width: surface.width - x - Theme.space.s6
                   - (action.visible && !root.stacked ? action.width + Theme.space.s4 : 0)
            text: root.message
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        MeridianButton {
            id: action
            objectName: "toastAction"
            visible: root.actionLabel.length > 0
            text: root.actionLabel
            variant: MeridianButton.Quiet
            controlSize: MeridianButton.Small
            surfaceColor: Theme.colors.raised
            x: root.stacked ? messageText.x - Theme.space.s4 : surface.width - Theme.space.s5 - width
            y: root.stacked ? messageText.y + messageText.height + Theme.space.s3 : (surface.height - height) / 2
            onActivated: root.actionTriggered()
        }
        Rectangle {
            // The shrinking time rule of an action toast; it pauses on hover.
            visible: root.actionLabel.length > 0
            x: Theme.radius.xl
            y: surface.height - height - 1
            height: 2
            radius: 1
            width: (surface.width - 2 * Theme.radius.xl) * root.remaining
            color: Theme.colors.line
        }
    }
}
