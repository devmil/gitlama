pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The body of a remote tab that could not open: a dropped
// connection offers Reconnect; a changed host identity explains and opens the host for a
// decision; a repository that no longer matches the one the tab opened, on a host that still
// does, can be trusted and opened again.
Item {
    id: page

    required property var tab
    readonly property string profileId: tab.remoteProfile ?? ""
    readonly property var host: Labels.remoteHost(profileId)
    readonly property string name: Labels.remoteHostName(profileId)
    readonly property bool usable: host !== null
    readonly property bool identityChanged: tab.failure === "remoteIdentityChanged"
    // A connected host vouched for its account and store, so only the repository changed.
    readonly property bool repositoryChanged: identityChanged && usable && host.phase !== "identityChanged"

    objectName: "remote-tab-failure"

    RemoteReconnect { id: reconnect; profileId: page.profileId }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.space.s6, Metrics.dialogConfirmWidth)
        spacing: Theme.space.s3

        MeridianIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: page.identityChanged ? "shield-alert" : "wifi-off"
            iconSize: MeridianIcon.Toolbar
        }
        Item { width: 1; height: Theme.space.s1 }
        MeridianText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: MeridianText.BodyStrong
            text: page.repositoryChanged ? L10n.tn("remoteTabRepositoryChangedTitle", { host: page.name })
                : page.identityChanged ? L10n.tn("remoteTabIdentityChangedTitle", { host: page.name })
                : L10n.tn("remoteTabDisconnectedTitle", { host: page.name })
        }
        MeridianText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.colors.inkMuted
            text: page.repositoryChanged ? L10n.t("remoteTabRepositoryChangedDetail")
                : page.identityChanged ? L10n.t("remoteTabIdentityChangedDetail")
                : page.usable ? L10n.t("remoteTabDisconnectedDetail") : L10n.t("remoteTabHostDeletedDetail")
        }
        MeridianText {
            visible: (page.tab.path ?? "").length > 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WrapAnywhere
            role: MeridianText.CodeSm
            color: Theme.colors.inkMuted
            text: page.tab.path ?? ""
        }
        Item { visible: page.usable; width: 1; height: Theme.space.s2 }
        MeridianButton {
            objectName: "remote-trust-repository"
            visible: page.repositoryChanged
            anchors.horizontalCenter: parent.horizontalCenter
            text: L10n.t("remoteTabTrustRepository")
            iconName: "rotate-cw"
            variant: MeridianButton.Primary
            onClicked: Store.remote.trustRepository(page.tab.tabId ?? page.tab.id)
        }
        MeridianButton {
            objectName: "remote-review-identity"
            visible: page.usable && page.identityChanged && !page.repositoryChanged
            anchors.horizontalCenter: parent.horizontalCenter
            text: L10n.t("remoteReviewHost")
            iconName: "server"
            variant: MeridianButton.Primary
            onClicked: Store.actions.showRemoteHosts(page.profileId)
        }
        // A dropped connection: automatic reconnection and Reconnect.
        Column {
            visible: page.usable && !page.identityChanged
            width: parent.width
            spacing: Theme.space.s2
            MeridianText {
                objectName: "remote-reconnect-status"
                visible: reconnect.status !== null
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: reconnect.status ? reconnect.status.title : ""
            }
            MeridianText {
                visible: reconnect.status !== null && reconnect.status.reason.length > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: reconnect.status ? reconnect.status.reason : ""
            }
            Item { visible: reconnect.status !== null; width: 1; height: Theme.space.s2 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space.s3
                MeridianButton {
                    objectName: "remote-install-helper"
                    visible: reconnect.install
                    text: L10n.t("remoteInstallHelper")
                    iconName: "download"
                    variant: MeridianButton.Primary
                    onClicked: reconnect.installHelper()
                }
                MeridianButton {
                    objectName: "remote-reconnect"
                    text: reconnect.reconnectLabel
                    iconName: "refresh"
                    variant: reconnect.install ? MeridianButton.Quiet : MeridianButton.Primary
                    loading: reconnect.connecting
                    enabled: !reconnect.connecting
                    onClicked: reconnect.reconnectNow()
                }
                MeridianButton {
                    objectName: "remote-reconnect-stop"
                    visible: reconnect.automatic && !reconnect.connecting
                    text: L10n.t("remoteReconnectStop")
                    variant: MeridianButton.Quiet
                    onClicked: reconnect.stop()
                }
            }
        }
    }
}
