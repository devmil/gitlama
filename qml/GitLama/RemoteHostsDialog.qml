pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The host profiles: the hosts with their connection state, and
// the selected host's status, failure and helper installation, identity change, access,
// automatic helper installation and Connect/Disconnect/Edit/Delete. With `choosing` the
// primary action continues with the selected, connected host: a prompt then receives its ID.
MeridianDialog {
    id: dialog

    property bool choosing: false
    property int promptId: -1
    property string selected: ""
    /// Hosts whose changed identity the user set aside for now.
    property var deferred: ({})
    /// Whether this build can install a helper on the selected host (checked on demand).
    property var installable: ({})
    property var answerTo: null

    readonly property var hosts: Store.remote ? (Store.remote.hosts ?? []) : []
    readonly property var profile: {
        for (let index = 0; index < hosts.length; index += 1) {
            if (hosts[index].id === selected)
                return hosts[index]
        }
        return null
    }
    readonly property bool canChoose: profile !== null && profile.verified !== null && profile.ready

    /// Opens the dialog, optionally with `profileId` selected; a prompt `id` gets the answer.
    function show(profileId, choosingHost, id, answer) {
        choosing = choosingHost === true
        promptId = id === undefined ? -1 : id
        answerTo = answer ?? null
        deferred = ({})
        installable = ({})
        selected = ""
        for (let index = 0; index < hosts.length; index += 1) {
            if (hosts[index].id === profileId)
                selected = profileId
        }
        if (selected.length === 0 && hosts.length > 0)
            selected = hosts[0].id
        open()
    }
    function finish(value) {
        if (promptId >= 0 && answerTo) {
            const id = promptId
            promptId = -1
            answerTo(id, value)
        }
    }
    function choose() {
        if (!canChoose)
            return
        finish(profile.id)
        close()
    }
    function setAccess(allow) {
        if (!profile || profile.writesAllowed === allow)
            return
        Store.remote.setAccess(profile.id, allow)
    }

    widthClass: MeridianDialog.Workflow
    title: choosing ? L10n.t("openRemoteRepository") : L10n.t("remoteHosts")
    description: L10n.t("remoteHostsIntro")
    submitDisabled: !choosing || !canChoose
    onSubmitted: if (choosing) choose()
    onClosed: finish(null)

    onProfileChanged: {
        if (profile && profile.failure && Labels.remoteInstallResolves(profile.failure.code)
                && installable[profile.id] === undefined)
            Store.remote.checkInstallable(profile.id)
    }
    Connections {
        target: Store.remote
        function onInstallableChecked(profileId, value) {
            const next = Object.assign({}, dialog.installable)
            next[profileId] = value
            dialog.installable = next
        }
    }

    RemoteHostEditor { id: editor; onSaved: profileId => dialog.selected = profileId }
    MeridianConfirm {
        id: deleteConfirm
        property string profileId
        destructive: true
        confirmLabel: L10n.t("remoteDeleteHost")
        cancelLabel: L10n.t("cancel")
        description: L10n.t("remoteDeleteHostDetail")
        onConfirmed: {
            Store.remote.deleteProfile(profileId)
            dialog.selected = ""
        }
    }

    Column {
        width: parent ? parent.width : 0
        spacing: 0

        MeridianText {
            objectName: "remote-hosts-empty"
            visible: dialog.hosts.length === 0
            width: parent.width
            wrapMode: Text.Wrap
            color: Theme.colors.inkMuted
            text: L10n.t("remoteHostsEmpty")
        }
        ListView {
            id: list
            visible: dialog.hosts.length > 0
            width: parent.width
            height: Math.min(contentHeight, GitLamaLayout.remoteHostListMaxHeight)
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: dialog.hosts
            delegate: MeridianListRow {
                id: row
                required property var modelData
                objectName: "remote-host-" + modelData.id
                width: ListView.view.width
                text: modelData.label
                subtitle: modelData.verified
                    ? L10n.tn("remoteHostRowVerified", { alias: modelData.alias, account: modelData.verified.accountName })
                    : L10n.tn("remoteHostRowUnverified", { alias: modelData.alias })
                twoLine: true
                selected: modelData.id === dialog.selected
                semanticValue: Labels.remotePhase(modelData.phase)
                leading: Component {
                    MeridianIcon {
                        name: AppearanceColors.icons.indexOf(row.modelData.icon ?? "") >= 0 ? row.modelData.icon : "server"
                        color: row.modelData.color ? AppearanceColors.color(row.modelData.color) : Theme.colors.inkMuted
                    }
                }
                trailing: Component {
                    MeridianStatusDot {
                        tone: Labels.remotePhaseTone(row.modelData.phase)
                        label: Labels.remotePhase(row.modelData.phase)
                    }
                }
                onClicked: dialog.selected = modelData.id
            }
        }

        // The selected host.
        Column {
            id: details
            objectName: "remote-host-details"
            visible: dialog.profile !== null
            width: parent.width
            topPadding: Theme.space.s5
            spacing: Theme.space.s4

            readonly property var host: dialog.profile ?? ({})
            readonly property bool busy: Labels.remoteBusy(host.phase ?? "")
            readonly property bool identityChanged: host.phase === "identityChanged" && !!host.observed
                && dialog.deferred[host.id] !== true
            readonly property bool showFailure: !!host.failure && !identityChanged && host.phase !== "identityChanged"
                && (host.phase === "failed" || host.phase === "disconnected")

            Column {
                width: parent.width
                spacing: Theme.space.s2
                Row {
                    spacing: Theme.space.s3
                    MeridianSpinner {
                        visible: details.busy
                        immediate: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    MeridianText {
                        objectName: "remote-host-phase"
                        role: MeridianText.BodyStrong
                        text: Labels.remotePhase(details.host.phase ?? "idle")
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }
                MeridianText {
                    visible: !!details.host.verified
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: details.host.verified ? L10n.tn("remoteHostAccount", { account: details.host.verified.accountName }) : ""
                }
            }

            MeridianBanner {
                objectName: "remote-host-failure"
                visible: details.showFailure
                width: parent.width
                tone: MeridianBanner.Error
                message: Labels.remoteFailure(details.host.failure)
            }
            // Installing the helper resolves the failure: install, or place it by hand.
            Column {
                visible: details.showFailure && details.host.failure
                    && (Labels.remoteInstallResolves(details.host.failure.code) || details.host.failure.code === "installUnavailable")
                width: parent.width
                spacing: Theme.space.s3
                readonly property bool canInstall: details.host.failure !== undefined && details.host.failure !== null
                    && Labels.remoteInstallResolves(details.host.failure.code) && dialog.installable[details.host.id] === true
                MeridianText {
                    visible: parent.canInstall
                    width: parent.width
                    role: MeridianText.Caption
                    wrapMode: Text.Wrap
                    color: Theme.colors.inkMuted
                    text: L10n.t("remoteInstallHelperHelp")
                }
                MeridianButton {
                    objectName: "remote-install-helper"
                    visible: parent.canInstall
                    text: L10n.t("remoteInstallHelper")
                    iconName: "download"
                    variant: MeridianButton.Primary
                    onClicked: Store.remote.installHelper(details.host.id)
                }
                RemoteHelperLocation { visible: !parent.canInstall; width: parent.width }
            }

            MeridianBanner {
                objectName: "remote-identity-changed"
                visible: details.identityChanged
                width: parent.width
                tone: MeridianBanner.Warning
                title: L10n.t("remoteIdentityChangedTitle")
                message: details.host.observed
                    ? L10n.tn("remoteIdentityChangedDetail", {
                        observed: details.host.observed.accountName,
                        verified: details.host.verified ? details.host.verified.accountName : L10n.t("remoteHostUnknownAccount") })
                    : ""
                MeridianButton {
                    objectName: "remote-trust-identity"
                    text: L10n.t("remoteTrustIdentity")
                    controlSize: MeridianButton.Small
                    variant: MeridianButton.Primary
                    onClicked: Store.remote.rebind(details.host.id)
                }
                MeridianButton {
                    text: L10n.t("cancel")
                    controlSize: MeridianButton.Small
                    variant: MeridianButton.Quiet
                    onClicked: {
                        const next = Object.assign({}, dialog.deferred)
                        next[details.host.id] = true
                        dialog.deferred = next
                    }
                }
            }

            // What GitLama may do on the host.
            Column {
                objectName: "remote-access"
                width: parent.width
                spacing: Theme.space.s2
                MeridianSegmented {
                    objectName: "remote-allow-writes"
                    label: L10n.t("remoteAccess")
                    segments: [{ value: false, label: L10n.t("remoteAccessReadOnly"), icon: "eye" },
                               { value: true, label: L10n.t("remoteAccessChanges"), icon: "pencil" }]
                    value: details.host.writesAllowed === true
                    enabled: !details.busy
                    onActivated: value => dialog.setAccess(value)
                }
                MeridianText {
                    objectName: "remote-access-detail"
                    width: parent.width
                    role: MeridianText.Caption
                    wrapMode: Text.Wrap
                    color: Theme.colors.inkMuted
                    text: details.host.writesAllowed ? L10n.t("remoteAccessChangesDetail") : L10n.t("remoteAccessReadOnlyDetail")
                }
                MeridianText {
                    visible: !details.host.verified && details.host.writesAllowed === true
                    width: parent.width
                    role: MeridianText.Caption
                    wrapMode: Text.Wrap
                    color: Theme.colors.inkMuted
                    text: L10n.t("remoteAccessFirstConnection")
                }
                // Changes allowed while connected apply when the host reconnects.
                MeridianText {
                    visible: details.host.ready === true && details.host.writeBlock === "reconnect"
                    width: parent.width
                    role: MeridianText.Caption
                    wrapMode: Text.Wrap
                    color: Theme.colors.inkMuted
                    text: L10n.t("remoteAccessNextConnection")
                }
            }

            MeridianSwitch {
                objectName: "remote-auto-install"
                width: parent.width
                text: L10n.t("remoteAutoInstallHelper")
                description: L10n.t("remoteAutoInstallHelperDetail")
                checked: details.host.autoInstallHelper === true
                onToggled: Store.remote.setAutoInstall(details.host.id, checked)
            }

            Flow {
                width: parent.width
                spacing: Theme.space.s3
                MeridianButton {
                    objectName: "remote-cancel-connect"
                    visible: details.busy
                    text: L10n.t("remoteCancelConnect")
                    iconName: "ban"
                    onClicked: Store.remote.cancel(details.host.id)
                }
                MeridianButton {
                    objectName: "remote-disconnect"
                    visible: !details.busy && details.host.ready === true
                    text: L10n.t("remoteDisconnect")
                    iconName: "unlink"
                    onClicked: Store.remote.disconnect(details.host.id)
                }
                MeridianButton {
                    objectName: "remote-connect"
                    visible: !details.busy && details.host.ready !== true
                    text: L10n.t("remoteConnect")
                    iconName: "link"
                    variant: dialog.choosing ? MeridianButton.Secondary : MeridianButton.Primary
                    onClicked: {
                        const next = Object.assign({}, dialog.deferred)
                        delete next[details.host.id]
                        dialog.deferred = next
                        Store.remote.connectHost(details.host.id)
                    }
                }
                MeridianButton {
                    objectName: "remote-edit-host"
                    text: L10n.t("remoteEditHost")
                    iconName: "pencil"
                    variant: MeridianButton.Quiet
                    enabled: !details.busy
                    onClicked: editor.edit(details.host)
                }
                MeridianButton {
                    objectName: "remote-delete-host"
                    text: L10n.t("remoteDeleteHost")
                    iconName: "trash"
                    variant: MeridianButton.DangerQuiet
                    onClicked: {
                        deleteConfirm.profileId = details.host.id
                        deleteConfirm.title = L10n.tn("remoteDeleteHostTitle", { host: details.host.label })
                        deleteConfirm.open()
                    }
                }
            }
        }
    }

    actions: [
        MeridianButton {
            objectName: "remote-add-host"
            text: L10n.t("remoteAddHost")
            iconName: "plus"
            enabled: dialog.hosts.length < 64
            disabledReason: L10n.t("remoteFailureCapacity")
            onClicked: editor.add("")
        },
        MeridianButton {
            objectName: "remote-choose-folder"
            visible: dialog.choosing
            text: L10n.t("remoteChooseFolder")
            variant: MeridianButton.Primary
            enabled: dialog.canChoose
            disabledReason: L10n.t("remoteChooseFolderDisabled")
            onClicked: dialog.choose()
        }
    ]
}
