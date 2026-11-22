import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The exact commands a workflow runs, one per line, behind a collapsed
// "Git command details" disclosure (or `title`) (the Dart
// GitCommandDetails). The commands are selectable and scroll within a
// bounded height.
MeridianDisclosure {
    id: root

    property var commands: []

    title: L10n.t("gitCommandDetails")

    Rectangle {
        width: parent ? parent.width : 0
        height: Math.min(GitLamaLayout.commandDetailsMaxHeight, commandText.implicitHeight + 2 * Theme.space.s4)
        radius: Theme.radius.md
        color: Theme.colors.paneAlt

        Flickable {
            id: scroller
            anchors.fill: parent
            anchors.leftMargin: Theme.space.s5
            anchors.rightMargin: Theme.space.s5
            anchors.topMargin: Theme.space.s4
            anchors.bottomMargin: Theme.space.s4
            clip: true
            contentHeight: commandText.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: MeridianScrollBar {}

            MeridianSelectableText {
                id: commandText
                width: scroller.width
                role: MeridianText.CodeSm
                text: root.commands.join("\n")
                wrapMode: Text.WrapAnywhere
            }
        }
    }
}
