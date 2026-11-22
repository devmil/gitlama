import QtQuick
import Meridian

// The status bar slot that shows Notifications' message: one line, caption,
// `danger` for errors; a new message rises in. Messages never resize the slot.
MeridianSwapText {
    property string fallback
    readonly property bool showsMessage: Notifications.message.length > 0
    text: showsMessage ? Notifications.message : fallback
    role: MeridianText.Caption
    color: showsMessage && Notifications.error ? Theme.colors.danger : Theme.colors.inkMuted
    rise: Theme.space.s1
    Accessible.role: Accessible.StaticText
    Accessible.name: text

    HoverHandler { id: hover }
    MeridianTooltip {
        shown: hover.hovered && parent.text.length > 0
        text: parent.text
    }
}
