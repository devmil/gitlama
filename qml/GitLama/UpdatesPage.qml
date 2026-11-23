pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The Updates settings page: the installed
// version, the release channel and the update check. macOS hands checks to
// Sparkle; Linux and Windows compare with the public release index and
// point to the downloads page. The state is Store.settings.updates.
MeridianSettingsGroup {
    id: page

    readonly property var updates: Store.settings ? (Store.settings.updates ?? ({})) : ({})
    readonly property var installed: updates.installed ?? null
    readonly property var status: updates.status ?? null
    readonly property string failure: updates.failure ?? ""
    readonly property string statusText: {
        if (updates.checking === true)
            return L10n.t("updatesChecking")
        if (failure.length > 0)
            return L10n.t(failure)
        if (status === null)
            return ""
        if (status.kind === "upToDate")
            return L10n.tn("updatesUpToDate", { version: installed ? installed.version : "", build: installed ? installed.build : 0 })
        if (status.kind === "noRelease")
            return L10n.t("updatesNoRelease")
        return L10n.tn("updatesAvailable", { version: status.version, build: status.build })
    }

    MeridianSettingsRow {
        visible: page.installed !== null
        width: parent.width
        label: L10n.t("updatesInstalledVersion")
        MeridianText {
            objectName: "settings-updates-installed"
            color: Theme.colors.ink
            text: page.installed ? L10n.tn("updatesVersionAndBuild", { version: page.installed.version, build: page.installed.build }) : ""
        }
    }
    MeridianSettingsRow {
        width: parent.width
        label: L10n.t("updatesChannel")
        MeridianSegmented {
            objectName: "settings-updates-channel"
            label: L10n.t("updatesChannel")
            segments: [{ value: "stable", label: L10n.t("updatesChannelStable") },
                       { value: "beta", label: L10n.t("updatesChannelBeta") }]
            value: page.updates.channel ?? "stable"
            onActivated: value => Store.settings.updateAction("channel", value)
        }
    }
    MeridianText {
        width: parent.width
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        wrapMode: Text.Wrap
        text: L10n.t("updatesChannelHint")
    }
    MeridianButton {
        objectName: "settings-updates-check"
        variant: MeridianButton.Secondary
        text: L10n.t("updatesCheck")
        enabled: page.updates.checking !== true
        onClicked: Store.settings.updateAction("check", "")
    }
    MeridianText {
        width: parent.width
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        wrapMode: Text.Wrap
        text: page.updates.installsUpdates === true ? L10n.t("updatesAutomaticHint") : L10n.t("updatesManualHint")
    }
    MeridianText {
        objectName: "settings-updates-status"
        width: parent.width
        role: MeridianText.Caption
        color: page.failure.length > 0 ? Theme.colors.danger : Theme.colors.ink
        wrapMode: Text.Wrap
        text: page.statusText
        Accessible.role: Accessible.AlertMessage
        Accessible.name: text
    }
    MeridianButton {
        objectName: "settings-updates-open-downloads"
        visible: page.failure.length === 0 && page.status !== null && page.status.kind === "available"
        text: L10n.t("updatesOpenDownloads")
        onClicked: {
            if (!Qt.openUrlExternally(page.updates.downloadsUrl))
                Notifications.show(L10n.t("updatesFailureOpen"), true)
        }
    }
}
