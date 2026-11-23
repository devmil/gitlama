pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Git's status accelerators of the active repository (the Dart
// StatusAccelerationSettings): whether the untracked cache and the file
// system monitor are on, and a way to turn on what is missing — the same
// settings the slow-status offer enables.
MeridianSettingsGroup {
    id: group

    readonly property var view: Store.settings && Store.settings.acceleration ? (Store.settings.acceleration.settings ?? null) : null
    readonly property var acceleration: view ? (view.acceleration ?? null) : null
    function onOff(on) { return L10n.t(on ? "settingsOn" : "settingsOff") }

    objectName: "settings-status-acceleration"
    title: L10n.t("settingsStatusAcceleration")

    MeridianText {
        width: parent.width
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        text: L10n.t("settingsStatusAccelerationHint")
    }
    MeridianText {
        visible: group.view !== null && group.view.remote === true
        width: parent.width
        wrapMode: Text.Wrap
        text: L10n.t("settingsStatusAccelerationRemote")
    }
    MeridianText {
        visible: group.view !== null && group.view.remote !== true && group.view.loading !== true && group.view.readFailed === true
        width: parent.width
        role: MeridianText.Caption
        color: Theme.colors.danger
        wrapMode: Text.Wrap
        text: L10n.t("settingsStatusAccelerationReadFailed")
    }
    MeridianSettingsRow {
        visible: group.acceleration !== null
        width: parent.width
        label: L10n.t("settingsUntrackedCache")
        MeridianText {
            objectName: "settings-untracked-cache"
            text: group.acceleration ? group.onOff(group.acceleration.untrackedCache) : ""
        }
    }
    MeridianSettingsRow {
        visible: group.acceleration !== null
        width: parent.width
        label: L10n.t("settingsFsmonitor")
        MeridianText {
            objectName: "settings-fsmonitor"
            text: !group.acceleration ? ""
                : group.acceleration.fsmonitor || group.acceleration.fsmonitorAvailable ? group.onOff(group.acceleration.fsmonitor)
                : L10n.t("settingsFsmonitorUnavailable")
        }
    }
    MeridianText {
        visible: group.acceleration !== null && group.acceleration.lastScanMillis !== null && group.acceleration.lastScanMillis !== undefined
        width: parent.width
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        wrapMode: Text.Wrap
        text: !visible ? "" : group.acceleration.lastScanMillis < 1000 ? L10n.t("settingsStatusAccelerationLastScanFast")
            : L10n.tn("settingsStatusAccelerationLastScan", { seconds: Math.round(group.acceleration.lastScanMillis / 1000) })
    }
    MeridianButton {
        objectName: "settings-status-acceleration-enable"
        visible: group.acceleration !== null && group.acceleration.canImprove === true
        variant: MeridianButton.Secondary
        text: L10n.t("settingsStatusAccelerationEnable")
        enabled: group.view !== null && group.view.enabling !== true
        onClicked: Store.settings.statusAcceleration("enableFromSettings")
    }
    MeridianText {
        visible: group.acceleration !== null && group.acceleration.canImprove !== true
        width: parent.width
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        text: L10n.t("settingsStatusAccelerationAllOn")
    }
    MeridianText {
        visible: group.view !== null && group.view.enableFailed === true
        width: parent.width
        role: MeridianText.Caption
        color: Theme.colors.danger
        wrapMode: Text.Wrap
        text: L10n.t("statusAccelerationFailed")
        Accessible.role: Accessible.AlertMessage
        Accessible.name: text
    }
}
