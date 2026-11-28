pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Hosting settings:
// `section` "accounts" lists the hosting accounts with their switches and
// actions, the add-account form and a running sign-in; "binding" links the
// active repository to an account, remote and provider repository. The
// state is Store.hosting.
Column {
    id: page

    property string section: "accounts"
    signal openAccounts()

    readonly property var accounts: Store.hosting ? (Store.hosting.accounts ?? ({})) : ({})
    readonly property var connections: accounts.connections ?? []
    readonly property var authorization: accounts.authorization ?? null
    readonly property var repositoryState: Store.hosting ? (Store.hosting.repository ?? ({})) : ({})
    readonly property var binding: repositoryState.binding ?? null
    readonly property string failure: Store.hosting ? (Store.hosting.failure ?? "") : ""
    readonly property bool busy: authorization !== null && authorization.state !== null
        && ["queued", "waitingForBrowser", "waitingForDevice", "exchanging"].indexOf(authorization.state) >= 0

    // The add-account form.
    property bool addExpanded: false
    property string preset: "github"
    property string authentication: "oauth"
    property var defaults: null
    property bool apiEdited: false
    property string formError: ""
    readonly property bool selfHosted: ["gitlabSelfManaged", "forgejo", "gitHubEnterprise"].indexOf(preset) >= 0
    readonly property var availableAuthentications: (defaults ? defaults.authentications : ["oauth"]).filter(method =>
        method === "oauth" || (method === "gitHubCli" && accounts.githubCli === true) || (method === "gitLabCli" && accounts.gitlabCli === true))
    readonly property var presets: ["github", "gitlab", "gitlabSelfManaged", "forgejo", "codeberg", "gitHubEnterprise"]
    /// The browser page of the sign-in last opened, so it opens once.
    property string openedRequest: ""

    function presetLabel(name) {
        return ({ github: "GitHub", gitlab: "GitLab", gitlabSelfManaged: "GitLab Self-Managed", forgejo: "Forgejo",
                  codeberg: "Codeberg", gitHubEnterprise: "GitHub Enterprise Server" })[name] ?? name
    }
    function authenticationLabel(name) {
        return L10n.t(name === "gitHubCli" ? "hostingGitHubCli" : name === "gitLabCli" ? "hostingGitLabCli" : "hostingOAuthApplication")
    }
    /// A failure code in words.
    function failureText(code) {
        if (!code)
            return ""
        if (code === "settings")
            return L10n.t("hostingSettingsFailure")
        if (code === "oauth:invalidConnection")
            return L10n.tn("hostingFailure", { reason: L10n.t("hostingOAuthClientRejected") })
        const name = code.startsWith("oauth:") ? code.slice(6) : code
        const words = { notFound: "hostingFailureNotFound", redirected: "hostingFailureRedirected", serverError: "hostingFailureServerError",
                        network: "hostingFailureNetwork", certificate: "hostingFailureCertificate", timedOut: "hostingFailureTimedOut" }[name]
        return L10n.tn("hostingFailure", { reason: words ? L10n.t(words) : name })
    }
    function loadDefaults() {
        const webBase = selfHosted ? webField.text.trim() : ""
        defaults = Store.hosting.presetDefaults(preset, webBase)
        if (!selfHosted) {
            webField.text = defaults ? defaults.webBaseUrl : ""
            apiField.text = defaults ? defaults.apiBaseUrl : ""
        } else if (!apiEdited) {
            apiField.text = defaults ? defaults.apiBaseUrl : ""
        }
        if (availableAuthentications.indexOf(authentication) < 0)
            authentication = "oauth"
    }
    function selectPreset(value) {
        preset = value
        authentication = "oauth"
        apiEdited = false
        formError = ""
        webField.text = ""
        apiField.text = ""
        loadDefaults()
    }
    /// Checks the form and signs the new account in.
    function submit() {
        const id = idField.text.trim()
        if (id.length === 0) {
            formError = L10n.t("hostingGuideEnterName")
            return
        }
        if (connections.some(connection => connection.id === id)) {
            formError = L10n.t("hostingGuideNameInUse")
            return
        }
        if (authentication === "oauth" && clientField.text.trim().length === 0) {
            formError = L10n.t("hostingGuideEnterClientId")
            return
        }
        loadDefaults()
        if (defaults === null || defaults.preset !== preset || apiField.text.trim().length === 0) {
            formError = L10n.t("hostingGuideEnterServer")
            return
        }
        formError = ""
        Store.hosting.addConnection({
            id: id, preset: preset, webBaseUrl: defaults.webBaseUrl, apiBaseUrl: apiField.text.trim(),
            oauthClientId: clientField.text.trim(), authentication: authentication, capabilities: defaults.capabilities,
        })
    }
    function resetForm() {
        addExpanded = false
        idField.text = ""
        webField.text = ""
        apiField.text = ""
        clientField.text = ""
        preset = "github"
        authentication = "oauth"
        apiEdited = false
        formError = ""
        loadDefaults()
    }
    function showGuide() { guide.show(preset, authentication, defaults ? defaults.webBaseUrl : "") }
    function openUrl(url) {
        if (url && Store.hosting.openable(url))
            Qt.openUrlExternally(url)
    }

    // A sign-in opens its browser page once; a new account's success
    // closes the form.
    onAuthorizationChanged: {
        if (authorization === null)
            return
        if (authorization.browserUrl && authorization.requestId !== openedRequest) {
            openedRequest = authorization.requestId
            openUrl(authorization.browserUrl)
        }
        if (authorization.state === "succeeded") {
            if (authorization.newConnection)
                resetForm()
            Store.hosting.endAuthorization()
        }
    }
    Component.onCompleted: {
        loadDefaults()
        if (section === "accounts")
            Store.hostingSettings = page
    }

    spacing: Theme.space.s5

    // Accounts ----------------------------------------------------------------
    Column {
        visible: page.section === "accounts"
        width: parent.width
        spacing: Theme.space.s5

        MeridianText { role: MeridianText.BodyStrong; text: L10n.t("hostingAccounts"); Accessible.role: Accessible.Heading }
        Rectangle {
            visible: page.connections.length === 0
            width: parent.width
            height: visible ? noAccounts.implicitHeight + 2 * Theme.space.s8 : 0
            radius: Theme.radius.lg
            color: Theme.colors.paneAlt
            Row {
                id: noAccounts
                x: Theme.space.s8
                y: Theme.space.s8
                spacing: Theme.space.s5
                MeridianIcon { name: "cloud-off" }
                MeridianText { text: L10n.t("hostingNoConnections") }
            }
        }
        Repeater {
            model: page.connections
            delegate: Rectangle {
                id: card
                required property var modelData
                width: page.width
                height: cardColumn.implicitHeight + 2 * Theme.space.s8
                radius: Theme.radius.lg
                color: Theme.colors.paneAlt
                Column {
                    id: cardColumn
                    x: Theme.space.s8
                    y: Theme.space.s8
                    width: parent.width - 2 * Theme.space.s8
                    MeridianListRow {
                        width: parent.width
                        text: card.modelData.id
                        subtitle: card.modelData.login.length === 0 ? page.presetLabel(card.modelData.preset)
                            : page.presetLabel(card.modelData.preset) + " · " + card.modelData.login
                        iconName: "cloud"
                        titleTrailing: Component {
                            MeridianCount {
                                label: card.modelData.enabled ? L10n.t("hostingStateEnabled") : L10n.t("hostingStateDisabled")
                                tone: card.modelData.enabled ? MeridianCount.Accent : MeridianCount.Quiet
                            }
                        }
                    }
                    Item { width: 1; height: Theme.space.s5 }
                    MeridianSwitch {
                        text: L10n.t("hostingEnabled")
                        checked: card.modelData.enabled
                        enabled: !page.busy
                        onToggled: Store.hosting.toggleConnection(card.modelData.id, checked, card.modelData.refreshEnabled)
                    }
                    MeridianSwitch {
                        text: L10n.t("hostingBackgroundRefresh")
                        checked: card.modelData.refreshEnabled
                        enabled: card.modelData.enabled && !page.busy
                        onToggled: Store.hosting.toggleConnection(card.modelData.id, card.modelData.enabled, checked)
                    }
                    Item { width: 1; height: Theme.space.s4 }
                    Flow {
                        width: parent.width
                        spacing: Theme.space.s4
                        layoutDirection: Qt.RightToLeft
                        MeridianButton {
                            text: L10n.t("hostingRemove")
                            iconName: "trash"
                            variant: MeridianButton.DangerQuiet
                            enabled: !page.busy
                            onClicked: {
                                removeConfirm.connectionId = card.modelData.id
                                removeConfirm.open()
                            }
                        }
                        MeridianButton {
                            text: L10n.t("hostingReauthorize")
                            variant: MeridianButton.Quiet
                            enabled: !page.busy
                            onClicked: Store.hosting.reauthorize(card.modelData.id)
                        }
                    }
                }
            }
        }
        Item { width: 1; height: Theme.space.s1 }
        Rectangle {
            width: parent.width
            height: addDisclosure.implicitHeight
            radius: Theme.radius.lg
            color: Theme.colors.paneAlt
            MeridianDisclosure {
                id: addDisclosure
                objectName: "hosting-add-connection"
                width: parent.width
                title: L10n.t("hostingAddConnection")
                expanded: page.addExpanded
                onToggled: value => page.addExpanded = value
                Column {
                    x: Theme.space.s6
                    width: (parent ? parent.width : 0) - 2 * Theme.space.s6
                    topPadding: Theme.space.s6
                    bottomPadding: Theme.space.s6
                    spacing: Theme.space.s8
                    Column {
                        width: parent.width
                        spacing: Theme.space.s4
                        MeridianSelect {
                            width: parent.width
                            label: L10n.t("hostingPreset")
                            showLabel: true
                            values: page.presets
                            value: page.preset
                            valueLabel: name => page.presetLabel(name)
                            enabled: !page.busy
                            onActivated: value => page.selectPreset(value)
                        }
                        MeridianButton {
                            objectName: "hosting-setup-guide"
                            text: L10n.t("hostingGuideAction")
                            iconName: "circle-help"
                            variant: MeridianButton.Quiet
                            onClicked: guide.show(page.preset, page.authentication, page.defaults ? page.defaults.webBaseUrl : "")
                        }
                    }
                    Column {
                        visible: page.availableAuthentications.length > 1
                        width: parent.width
                        spacing: Theme.space.s4
                        MeridianSelect {
                            width: parent.width
                            label: L10n.t("hostingAuthenticationMethod")
                            showLabel: true
                            values: page.availableAuthentications
                            value: page.authentication
                            valueLabel: name => page.authenticationLabel(name)
                            enabled: !page.busy
                            onActivated: value => page.authentication = value
                        }
                        MeridianText {
                            visible: page.authentication !== "oauth"
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: page.authentication === "gitHubCli" ? L10n.t("hostingGitHubCliHint") : L10n.t("hostingGitLabCliHint")
                        }
                    }
                    HostingField { id: idField; objectName: "hosting-connection-id"; width: parent.width; label: L10n.t("hostingConnectionId"); enabled: !page.busy }
                    HostingField {
                        id: webField
                        objectName: "hosting-web-url"
                        visible: page.selfHosted
                        width: parent.width
                        label: L10n.t("hostingWebUrl")
                        enabled: !page.busy
                        onEdited: page.loadDefaults()
                    }
                    HostingField {
                        id: apiField
                        objectName: "hosting-api-url"
                        visible: page.selfHosted
                        width: parent.width
                        label: L10n.t("hostingApiUrl")
                        enabled: !page.busy
                        onEdited: page.apiEdited = true
                    }
                    HostingField {
                        id: clientField
                        objectName: "hosting-oauth-client-id"
                        visible: page.authentication === "oauth"
                        width: parent.width
                        label: L10n.t("hostingOAuthClientId")
                        enabled: !page.busy
                    }
                    MeridianText {
                        visible: page.formError.length > 0 || page.failure.length > 0
                        width: parent.width
                        color: Theme.colors.danger
                        wrapMode: Text.Wrap
                        text: page.formError.length > 0 ? page.formError : page.failureText(page.failure)
                    }
                    Item {
                        width: parent.width
                        height: authorizeButton.implicitHeight
                        MeridianButton {
                            id: authorizeButton
                            anchors.right: parent.right
                            text: page.authentication === "gitHubCli" ? L10n.t("hostingConnectWithCli")
                                : page.authentication === "gitLabCli" ? L10n.t("hostingConnectWithGitLabCli")
                                : L10n.t("hostingSaveAuthorize")
                            variant: MeridianButton.Primary
                            enabled: !page.busy
                            onClicked: page.submit()
                        }
                    }
                }
            }
        }
        // A running sign-in: the device code and the browser page.
        Rectangle {
            visible: page.authorization !== null && page.authorization.state !== "succeeded"
            width: parent.width
            height: visible ? waitingColumn.implicitHeight + 2 * Theme.space.s8 : 0
            radius: Theme.radius.lg
            color: Theme.colors.paneAlt
            Column {
                id: waitingColumn
                x: Theme.space.s8
                y: Theme.space.s8
                width: parent.width - 2 * Theme.space.s8
                spacing: Theme.space.s4
                MeridianText {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: page.authorization && page.authorization.failure ? page.failureText("oauth:" + page.authorization.failure)
                        : L10n.t("hostingAuthorizationWaiting")
                    color: page.authorization && page.authorization.failure ? Theme.colors.danger : Theme.colors.ink
                }
                MeridianSelectableText {
                    visible: page.authorization !== null && !!page.authorization.userCode
                    text: page.authorization && page.authorization.userCode ? L10n.tn("hostingAuthorizationCode", { code: page.authorization.userCode }) : ""
                }
                Row {
                    spacing: Theme.space.s4
                    MeridianButton {
                        visible: page.authorization !== null && !!page.authorization.browserUrl
                        text: L10n.t("hostingOpenBrowser")
                        variant: MeridianButton.Quiet
                        onClicked: page.openUrl(page.authorization.browserUrl)
                    }
                    MeridianButton {
                        text: page.busy ? L10n.t("cancel") : L10n.t("close")
                        variant: MeridianButton.Quiet
                        onClicked: Store.hosting.endAuthorization()
                    }
                }
            }
        }
    }

    // Binding -----------------------------------------------------------------
    Column {
        visible: page.section === "binding"
        width: parent.width
        spacing: Theme.space.s5

        MeridianText { role: MeridianText.BodyStrong; text: L10n.t("hostingBinding"); Accessible.role: Accessible.Heading }
        Rectangle {
            width: parent.width
            height: bindingColumn.implicitHeight + 2 * Theme.space.s8
            radius: Theme.radius.lg
            color: Theme.colors.paneAlt
            Column {
                id: bindingColumn
                x: Theme.space.s8
                y: Theme.space.s8
                width: parent.width - 2 * Theme.space.s8
                spacing: Theme.space.s8
                readonly property bool repository: Store.workspace && Store.workspace.active !== null && Store.workspace.active !== undefined
                readonly property var remotes: Store.workspace && Store.workspace.active ? (Store.workspace.active.remotes ?? []) : []
                MeridianText {
                    visible: !bindingColumn.repository
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: L10n.t("commandRepositoryRequired")
                }
                Column {
                    visible: bindingColumn.repository && page.connections.length === 0
                    width: parent.width
                    spacing: Theme.space.s5
                    MeridianText { width: parent.width; wrapMode: Text.Wrap; text: L10n.t("hostingConnectBeforeBinding") }
                    MeridianButton {
                        text: L10n.t("hostingAddConnection")
                        iconName: "link"
                        onClicked: page.openAccounts()
                    }
                }
                Column {
                    visible: bindingColumn.repository && page.connections.length > 0
                    width: parent.width
                    spacing: Theme.space.s8
                    MeridianText {
                        visible: page.binding !== null && (page.binding.state === "unmatched" || page.binding.state === "ambiguous")
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: page.binding && page.binding.state === "ambiguous" ? L10n.t("hostingAmbiguousBinding") : L10n.t("hostingNoBinding")
                    }
                    MeridianSelect {
                        id: connectionSelect
                        objectName: "hosting-binding-connection"
                        width: parent.width
                        label: L10n.t("hostingConnection")
                        showLabel: true
                        values: page.connections.filter(connection => connection.enabled).map(connection => connection.id)
                        value: page.binding && page.binding.connectionId ? page.binding.connectionId : (values[0] ?? "")
                        onActivated: value => connectionSelect.value = value
                    }
                    MeridianSelect {
                        id: remoteSelect
                        objectName: "hosting-binding-remote"
                        width: parent.width
                        label: L10n.t("hostingRemote")
                        showLabel: true
                        values: bindingColumn.remotes
                        value: page.binding && page.binding.remote ? page.binding.remote : (values[0] ?? "")
                        onActivated: value => remoteSelect.value = value
                    }
                    HostingField {
                        id: providerField
                        objectName: "hosting-provider-repository"
                        width: parent.width
                        label: L10n.t("hostingProviderRepository")
                        text: page.binding && page.binding.providerRepository ? page.binding.providerRepository : ""
                    }
                    MeridianText {
                        visible: page.failure.length > 0
                        width: parent.width
                        color: Theme.colors.danger
                        wrapMode: Text.Wrap
                        text: page.failureText(page.failure)
                    }
                    Flow {
                        width: parent.width
                        spacing: Theme.space.s4
                        layoutDirection: Qt.RightToLeft
                        MeridianButton {
                            text: L10n.t("hostingSaveBinding")
                            variant: MeridianButton.Primary
                            enabled: connectionSelect.value.length > 0 && remoteSelect.value.length > 0 && providerField.text.trim().length > 0
                            onClicked: Store.hosting.saveBinding(remoteSelect.value, connectionSelect.value, providerField.text)
                        }
                        MeridianButton {
                            text: L10n.t("hostingAutomaticBinding")
                            variant: MeridianButton.Quiet
                            onClicked: Store.hosting.clearBinding()
                        }
                    }
                }
            }
        }
    }

    // Removing an account asks first.
    MeridianConfirm {
        id: removeConfirm
        property string connectionId
        title: L10n.t("hostingRemove")
        description: L10n.tn("hostingRemoveConfirm", { name: connectionId })
        confirmLabel: L10n.t("hostingRemove")
        cancelLabel: L10n.t("cancel")
        destructive: true
        onConfirmed: Store.hosting.removeConnection(connectionId)
    }
    HostingGuideDialog {
        id: guide
        presetLabel: name => page.presetLabel(name)
        onOpenUrl: url => page.openUrl(url)
    }
}
