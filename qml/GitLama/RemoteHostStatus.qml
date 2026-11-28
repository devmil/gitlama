import QtQuick
import Meridian

// The status bar's host of the active remote tab: its name, what
// GitLama may do there, and a native menu that switches between Read only and Allow changes,
// reconnects or disconnects, installs the helper and opens the host's settings.
MeridianButton {
    id: status

    required property string profileId
    required property bool disconnected
    readonly property var host: Labels.remoteHost(profileId)
    readonly property string name: Labels.remoteHostName(profileId)
    readonly property bool changes: host !== null && host.writesAllowed === true
    readonly property string badge: disconnected ? L10n.tn("remoteHostBadgeDisconnected", { host: name })
        : L10n.tn("remoteHostBadge", { host: name })

    objectName: "remote-host-status"
    variant: MeridianButton.Quiet
    controlSize: MeridianButton.Small
    leftPadding: 0
    rightPadding: 0
    text: badge
    tooltip: host !== null ? L10n.tn("remoteHostStatusTooltip", { host: name }) : ""
    // Without a known host the badge only names it: no hover, focus or menu.
    hoverEnabled: host !== null
    focusPolicy: host !== null ? Qt.TabFocus : Qt.NoFocus
    Accessible.role: host !== null ? Accessible.ButtonMenu : Accessible.StaticText
    Accessible.description: host !== null ? (changes ? L10n.t("remoteAccessStatusChanges") : L10n.t("remoteAccessStatusReadOnly")) : ""
    onClicked: if (host !== null) menu.show(status, 0, status.height)

    contentItem: Row {
        id: row
        leftPadding: Theme.space.s2
        rightPadding: Theme.space.s2
        spacing: Theme.space.s2
        MeridianIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: status.disconnected ? "wifi-off" : "server"
            iconSize: MeridianIcon.Small
            color: Theme.colors.inkMuted
        }
        MeridianText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, GitLamaLayout.remoteHostBadgeMaxWidth)
            elide: Text.ElideRight
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: status.badge
        }
        Item { visible: status.host !== null; width: Theme.space.s1; height: 1 }
        MeridianIcon {
            visible: status.host !== null
            anchors.verticalCenter: parent.verticalCenter
            name: status.changes ? "pencil" : "eye"
            iconSize: MeridianIcon.Small
            color: Theme.colors.inkMuted
        }
        MeridianText {
            objectName: "remote-host-access"
            visible: status.host !== null
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: status.changes ? L10n.t("remoteAccessStatusChanges") : L10n.t("remoteAccessStatusReadOnly")
        }
        MeridianIcon {
            visible: status.host !== null
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down"
            iconSize: MeridianIcon.Small
            color: Theme.colors.inkMuted
        }
    }

    CommandMenu {
        id: menu
        items: status.host === null ? [] : [
            { value: "readOnly", title: L10n.t("remoteAccessReadOnly"), icon: "eye", checked: !status.changes },
            { value: "allowChanges", title: L10n.t("remoteAccessChanges"), icon: "pencil", checked: status.changes },
            { separator: true },
            status.host.ready
                ? { value: "disconnect", title: L10n.t("remoteDisconnect"), icon: "unlink" }
                : { value: "reconnect", title: L10n.t("remoteReconnect"), icon: "refresh", enabled: status.host.connecting !== true },
            status.host.needsHelper === true
                ? { value: "installHelper", title: L10n.t("remoteInstallHelper"), icon: "download", enabled: status.host.connecting !== true }
                : null,
            { separator: true },
            { value: "settings", title: L10n.t("remoteHostSettings"), icon: "settings" }
        ].filter(item => item !== null)
        onSelected: id => {
            switch (id) {
            case "readOnly": Store.remote.setAccess(status.profileId, false); break
            case "allowChanges": Store.remote.setAccess(status.profileId, true); break
            case "disconnect": Store.remote.disconnect(status.profileId); break
            case "reconnect": Store.remote.reconnect(status.profileId); break
            case "installHelper": Store.remote.installHelper(status.profileId); break
            case "settings": Store.actions.showRemoteHosts(status.profileId); break
            }
        }
    }
}
