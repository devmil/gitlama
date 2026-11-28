import QtQuick
import Meridian

// The body of a repository tab on this computer that could not open (a folder that is gone,
// no longer a repository or not readable): says so instead of loading forever, and offers to
// close the tab or open another repository.
Item {
    id: page

    required property var tab
    signal command(string id)

    objectName: "local-tab-failure"

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.space.s6, Metrics.dialogConfirmWidth)
        spacing: Theme.space.s3

        MeridianIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "circle-alert"
            iconSize: MeridianIcon.Toolbar
            color: Theme.colors.inkMuted
        }
        MeridianText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: MeridianText.BodyStrong
            text: L10n.t("workspaceUnavailableRepository")
        }
        MeridianText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.colors.inkMuted
            text: Labels.repositoryFailureMessage(page.tab.failure ?? "")
        }
        Item { width: 1; height: Theme.space.s1 }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.space.s2
            MeridianButton {
                objectName: "local-tab-failure-close"
                text: L10n.tn("workspaceCloseTab", { name: page.tab.label ?? "" })
                iconName: "x"
                onClicked: Store.workspace.closeTab(page.tab.tabId)
            }
            MeridianButton {
                objectName: "local-tab-failure-open"
                text: L10n.t("workspaceOpenAnother")
                iconName: "folder-open"
                variant: MeridianButton.Primary
                onClicked: page.command("openRepository")
            }
        }
    }
}
