import QtQuick
import Meridian

// The Git commands an action runs (GitCommandDetails), selectable in a
// well so they can be copied.
Rectangle {
    id: root

    property var commands: []

    implicitHeight: commandText.implicitHeight + 2 * Theme.space.s3
    radius: Theme.radius.sm
    color: Theme.colors.paneAlt
    border.color: Theme.colors.line

    MeridianSelectableText {
        id: commandText
        x: Theme.space.s3
        y: Theme.space.s3
        width: root.width - 2 * Theme.space.s3
        role: MeridianText.CodeSm
        text: root.commands.join("\n")
        wrapMode: Text.WrapAnywhere
    }
}
