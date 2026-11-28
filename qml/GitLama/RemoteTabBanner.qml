import QtQuick
import Meridian

// The persistent notice of an open remote tab whose connection is gone: its content stays visible as the last received state. It never takes focus.
MeridianBanner {
    id: banner

    required property var tab
    readonly property var host: Labels.remoteHost(tab.remoteProfile ?? "")
    readonly property string name: Labels.remoteHostName(tab.remoteProfile ?? "")

    objectName: "remote-stale-banner"
    tone: MeridianBanner.Warning
    iconName: "wifi-off"
    title: status.status ? status.status.title : ""
    message: status.status ? status.status.detail : L10n.tn("remoteStaleBanner", { host: name })

    RemoteReconnect { id: status; profileId: banner.tab.remoteProfile ?? "" }

    MeridianButton {
        objectName: "remote-install-helper"
        visible: banner.host !== null && status.install
        text: L10n.t("remoteInstallHelper")
        controlSize: MeridianButton.Small
        onClicked: status.installHelper()
    }
    MeridianButton {
        objectName: "remote-reconnect"
        visible: banner.host !== null
        text: status.reconnectLabel
        controlSize: MeridianButton.Small
        variant: status.install ? MeridianButton.Quiet : MeridianButton.Secondary
        loading: status.connecting
        enabled: !status.connecting
        onClicked: status.reconnectNow()
    }
    MeridianButton {
        objectName: "remote-reconnect-stop"
        visible: banner.host !== null && status.automatic && !status.connecting
        text: L10n.t("remoteReconnectStop")
        controlSize: MeridianButton.Small
        variant: MeridianButton.Quiet
        onClicked: status.stop()
    }
}
