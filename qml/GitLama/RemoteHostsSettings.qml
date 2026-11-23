pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Settings › Remote hosts: the helper version this build
// needs, then every host with its state, access, automatic helper installation and Install
// helper, Manage connection, Edit and Delete; Add host below.
Column {
    id: page

    readonly property var hosts: Store.remote ? (Store.remote.hosts ?? []) : []
    readonly property var helper: Store.remote ? (Store.remote.helper ?? ({})) : ({})
    property string failure: ""

    spacing: 0

    Connections {
        target: Store.remote
        function onSaveFailed(result) {
            page.failure = L10n.t(result.key) + "\n" + L10n.tn("remoteProfileSaveCode", { code: result.code })
        }
    }
    RemoteHostEditor { id: editor }
    MeridianConfirm {
        id: deleteConfirm
        property string profileId
        destructive: true
        confirmLabel: L10n.t("remoteDeleteHost")
        cancelLabel: L10n.t("cancel")
        description: L10n.t("remoteDeleteHostDetail")
        onConfirmed: Store.remote.deleteProfile(profileId)
    }

    MeridianSettingsRow {
        width: parent.width
        label: L10n.t("remoteHelperVersion")
        help: L10n.t("remoteHelperVersionDetail")
        MeridianText {
            objectName: "settings-remote-helper-version"
            text: page.helper.version !== null && page.helper.version !== undefined
                ? String(page.helper.version) : L10n.t("remoteHelperVersionUnknown")
        }
    }
    Item { width: 1; height: Theme.space.s6 }
    MeridianBanner {
        visible: page.failure.length > 0
        width: parent.width
        tone: MeridianBanner.Error
        message: page.failure
    }
    Item { visible: page.failure.length > 0; width: 1; height: Theme.space.s5 }
    MeridianText {
        objectName: "settings-remote-hosts-empty"
        visible: page.hosts.length === 0
        width: parent.width
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        wrapMode: Text.Wrap
        text: L10n.t("remoteHostsEmpty")
    }
    Repeater {
        model: page.hosts
        delegate: Column {
            id: card
            required property var modelData
            objectName: "settings-remote-host-" + modelData.id
            width: page.width
            spacing: Theme.space.s4
            readonly property bool installing: modelData.connecting === true

            MeridianListRow {
                width: parent.width
                text: card.modelData.label
                subtitle: card.modelData.verified
                    ? L10n.tn("remoteHostRowVerified", { alias: card.modelData.alias, account: card.modelData.verified.accountName })
                    : L10n.tn("remoteHostRowUnverified", { alias: card.modelData.alias })
                twoLine: true
                semanticValue: Labels.remotePhase(card.modelData.phase)
                leading: Component {
                    MeridianIcon {
                        name: AppearanceColors.icons.indexOf(card.modelData.icon ?? "") >= 0 ? card.modelData.icon : "server"
                        color: card.modelData.color ? AppearanceColors.color(card.modelData.color) : Theme.colors.inkMuted
                    }
                }
                trailing: Component {
                    MeridianStatusDot {
                        tone: Labels.remotePhaseTone(card.modelData.phase)
                        label: Labels.remotePhase(card.modelData.phase)
                    }
                }
            }
            MeridianSegmented {
                objectName: "settings-remote-access-" + card.modelData.id
                label: L10n.t("remoteAccess")
                segments: [{ value: false, label: L10n.t("remoteAccessReadOnly"), icon: "eye" },
                           { value: true, label: L10n.t("remoteAccessChanges"), icon: "pencil" }]
                value: card.modelData.writesAllowed === true
                onActivated: value => {
                    page.failure = ""
                    if (value !== card.modelData.writesAllowed)
                        Store.remote.setAccess(card.modelData.id, value)
                }
            }
            MeridianSwitch {
                objectName: "settings-remote-auto-install-" + card.modelData.id
                width: parent.width
                text: L10n.t("remoteAutoInstallHelper")
                description: L10n.t("remoteAutoInstallHelperDetail")
                checked: card.modelData.autoInstallHelper === true
                onToggled: {
                    page.failure = ""
                    Store.remote.setAutoInstall(card.modelData.id, checked)
                }
            }
            MeridianText {
                visible: card.modelData.needsHelper === true && !card.installing
                width: parent.width
                role: MeridianText.Caption
                wrapMode: Text.Wrap
                color: Theme.colors.danger
                text: card.modelData.failure ? Labels.remoteFailure(card.modelData.failure) : L10n.t("remoteFailureHelperNotInstalled")
            }
            Flow {
                width: parent.width
                spacing: Theme.space.s3
                MeridianButton {
                    objectName: "settings-remote-install-" + card.modelData.id
                    visible: card.modelData.needsHelper === true
                    text: L10n.t("remoteInstallHelper")
                    iconName: "download"
                    variant: MeridianButton.Primary
                    loading: card.installing
                    enabled: !card.installing
                    onClicked: Store.remote.installHelper(card.modelData.id)
                }
                MeridianButton {
                    objectName: "settings-remote-manage-" + card.modelData.id
                    text: L10n.t("remoteManageConnection")
                    iconName: "link"
                    onClicked: Store.actions.showRemoteHosts(card.modelData.id)
                }
                MeridianButton {
                    objectName: "settings-remote-edit-" + card.modelData.id
                    text: L10n.t("remoteEditHost")
                    iconName: "pencil"
                    variant: MeridianButton.Quiet
                    enabled: !card.installing
                    onClicked: editor.edit(card.modelData)
                }
                MeridianButton {
                    objectName: "settings-remote-delete-" + card.modelData.id
                    text: L10n.t("remoteDeleteHost")
                    iconName: "trash"
                    variant: MeridianButton.DangerQuiet
                    onClicked: {
                        deleteConfirm.profileId = card.modelData.id
                        deleteConfirm.title = L10n.tn("remoteDeleteHostTitle", { host: card.modelData.label })
                        deleteConfirm.open()
                    }
                }
            }
            Item { width: 1; height: Theme.space.s7 - Theme.space.s4 }
        }
    }
    Item { width: 1; height: Theme.space.s4 }
    MeridianButton {
        objectName: "settings-remote-add-host"
        text: L10n.t("remoteAddHost")
        iconName: "plus"
        enabled: page.hosts.length < 64
        disabledReason: L10n.t("remoteFailureCapacity")
        onClicked: editor.add("")
    }
}
