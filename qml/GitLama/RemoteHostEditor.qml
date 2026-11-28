pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Adds or edits a host profile: a name and an SSH destination,
// and the icon and colour its tabs show. A new host starts with the server icon and a colour
// no other host uses. Saving through Store.remote answers with `profileSaved`.
MeridianDialog {
    id: dialog

    /// The edited host, or null for a new one.
    property var profile: null
    /// The SSH alias a new host starts with (as the command line named it).
    property string requestedAlias: ""
    property string icon: "server"
    property var color: null
    property bool attempted: false
    property bool saving: false
    property int request: 0
    property string failure: ""
    signal saved(string profileId)
    /// Ends without saving (for a prompt).
    signal declined()

    readonly property var hosts: Store.remote ? (Store.remote.hosts ?? []) : []
    readonly property bool labelValid: validLabel(labelField.text)
    readonly property bool aliasValid: validAlias(aliasField.text)
    readonly property bool aliasChanged: profile !== null && !!profile.verified && aliasField.text.length > 0
        && aliasField.text !== profile.alias
    property bool done: false

    /// At most 128 characters without control characters, not only blanks.
    function validLabel(text) {
        const characters = Array.from(text)
        return characters.length > 0 && characters.length <= 128 && text.trim().length > 0
            && characters.every(c => { const code = c.codePointAt(0); return code >= 0x20 && !(code >= 0x7f && code <= 0x9f) })
    }
    /// A host or user@host, at most 128 ASCII characters (the core checks again).
    function validAlias(text) {
        return text.length <= 128 && /^[A-Za-z0-9][A-Za-z0-9._-]*(@[A-Za-z0-9][A-Za-z0-9._-]*)?$/.test(text)
    }
    function add(alias) {
        profile = null
        requestedAlias = alias
        labelField.text = alias
        aliasField.text = alias
        icon = "server"
        // A colour no other host uses, so the new host's tabs stand out at once.
        const used = hosts.map(host => host.color)
        const free = AppearanceColors.palette.filter(key => used.indexOf(key) < 0)
        color = AppearanceColors.choice(free.length > 0 ? free[0] : AppearanceColors.palette[0])
        begin()
    }
    function edit(host) {
        profile = host
        requestedAlias = ""
        labelField.text = host.label
        aliasField.text = host.alias
        icon = AppearanceColors.icons.indexOf(host.icon ?? "") >= 0 ? host.icon : ""
        color = AppearanceColors.choice(host.color ?? "")
        begin()
    }
    function begin() {
        attempted = false
        saving = false
        failure = ""
        done = false
        open()
        labelField.input.forceActiveFocus()
    }
    function save() {
        if (saving)
            return
        if (!labelValid || !aliasValid) {
            attempted = true
            return
        }
        saving = true
        failure = ""
        request += 1
        Store.remote.saveProfile(request, profile ? profile.id : "", labelField.text, aliasField.text,
                                 AppearanceColors.keyOf(color), icon)
    }
    Connections {
        target: Store.remote
        function onProfileSaved(requestId, profileId, result) {
            if (!dialog.saving || requestId !== dialog.request)
                return
            dialog.saving = false
            if (profileId.length > 0) {
                dialog.done = true
                dialog.saved(profileId)
                dialog.close()
            } else {
                dialog.failure = L10n.t(result.key) + "\n" + L10n.tn("remoteProfileSaveCode", { code: result.code })
            }
        }
    }

    widthClass: MeridianDialog.Form
    title: profile === null ? L10n.t("remoteAddHostTitle") : L10n.t("remoteEditHostTitle")
    description: profile === null && requestedAlias.length > 0 ? L10n.tn("remoteAddHostRequested", { alias: requestedAlias }) : ""
    submitDisabled: saving
    onSubmitted: save()
    onClosed: if (!done) declined()

    Column {
        width: parent ? parent.width : 0
        spacing: 0

        RemoteField {
            id: labelField
            objectName: "remote-host-label"
            width: parent.width
            label: L10n.t("remoteHostLabel")
            placeholderText: L10n.t("remoteHostLabelPlaceholder")
            enabled: !dialog.saving
            error: (dialog.attempted || text.length > 0) && !dialog.labelValid ? L10n.t("remoteLabelInvalid") : ""
            onSubmitted: dialog.save()
        }
        Item { width: 1; height: Theme.space.s6 }
        RemoteField {
            id: aliasField
            objectName: "remote-host-alias"
            width: parent.width
            label: L10n.t("remoteHostAlias")
            placeholderText: L10n.t("remoteAliasExample")
            monospace: true
            enabled: !dialog.saving
            error: (dialog.attempted || text.length > 0) && !dialog.aliasValid ? L10n.t("remoteAliasInvalid") : ""
            message: L10n.t("remoteHostAliasHelp")
            onSubmitted: dialog.save()
        }
        Item { width: 1; height: Theme.space.s6 }

        // The icon and colour the host's tabs show, as the repository icon dialog lays them out.
        Column {
            objectName: "remote-host-appearance"
            width: parent.width
            spacing: Theme.space.s2
            readonly property color tint: dialog.color ? AppearanceColors.color(AppearanceColors.keyOf(dialog.color)) : Theme.colors.inkMuted
            MeridianText { role: MeridianText.Label; text: L10n.t("repositoryIconSymbol") }
            Flow {
                width: parent.width
                spacing: Theme.space.s2
                MeridianIconButton {
                    objectName: "remote-host-icon-none"
                    text: L10n.t("repositoryIconNone")
                    iconName: "ban"
                    controlSize: MeridianButton.Small
                    active: dialog.icon.length === 0
                    enabled: !dialog.saving
                    onClicked: dialog.icon = ""
                }
                Repeater {
                    model: AppearanceColors.icons
                    delegate: MeridianIconButton {
                        required property string modelData
                        objectName: "remote-host-icon-" + modelData
                        text: AppearanceColors.iconLabel(modelData)
                        iconName: modelData
                        iconColorOverride: parent.parent.tint
                        controlSize: MeridianButton.Small
                        active: dialog.icon === modelData
                        enabled: !dialog.saving
                        onClicked: dialog.icon = modelData
                    }
                }
            }
            Item { width: 1; height: Theme.space.s4 }
            MeridianText { role: MeridianText.Label; text: L10n.t("repositoryIconColor") }
            MeridianColorChoiceRow {
                width: parent.width
                value: dialog.color
                allowNone: true
                noneLabel: L10n.t("repositoryColorNone")
                customLabel: L10n.t("repositoryColorCustom")
                customValueLabel: hex => L10n.t("repositoryColorCustomValue", [hex])
                seriesLabels: AppearanceColors.seriesLabels
                pickerLabels: AppearanceColors.pickerLabels()
                enabled: !dialog.saving
                onChosen: choice => dialog.color = choice
            }
            Item { width: 1; height: Theme.space.s1 }
            MeridianText {
                width: parent.width
                role: MeridianText.Caption
                wrapMode: Text.Wrap
                color: Theme.colors.inkMuted
                text: L10n.t("remoteHostAppearanceHelp")
            }
        }
        Item { width: 1; height: Theme.space.s6 }
        MeridianText {
            width: parent.width
            role: MeridianText.Caption
            wrapMode: Text.Wrap
            color: Theme.colors.inkMuted
            text: L10n.t("remoteHostTrustHelp")
        }
        Item { visible: dialog.aliasChanged; width: 1; height: Theme.space.s6 }
        MeridianBanner {
            visible: dialog.aliasChanged
            width: parent.width
            tone: MeridianBanner.Warning
            message: L10n.t("remoteAliasChangeWarning")
        }
        Item { visible: dialog.failure.length > 0; width: 1; height: Theme.space.s6 }
        MeridianBanner {
            visible: dialog.failure.length > 0
            width: parent.width
            tone: MeridianBanner.Error
            message: dialog.failure
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.close() },
        MeridianButton {
            objectName: "remote-host-save"
            text: L10n.t("remoteSaveHost")
            variant: MeridianButton.Primary
            loading: dialog.saving
            enabled: !dialog.saving
            onClicked: dialog.save()
        }
    ]
}
