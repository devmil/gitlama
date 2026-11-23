import QtQuick
import Meridian

// Credentials for one transfer (showGitCredentialDialog): user name and a
// password or token. They are used once and never stored.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property string target
    property bool allowToken: true
    readonly property string secretLabel: !allowToken ? L10n.t("clonePasswordOrToken")
        : useToken ? L10n.t("transferToken") : L10n.t("transferPassword")
    property bool useToken: false
    signal answered(int id, var credentials)

    function ask(id, value) {
        promptId = id
        target = value.target ?? ""
        allowToken = value.allowToken !== false
        useToken = false
        username.text = ""
        secret.text = ""
        open()
        username.forceActiveFocus()
    }
    function submit() {
        if (secret.text.length === 0)
            return
        close()
        answered(promptId, { username: username.text, secret: secret.text, token: useToken })
        promptId = -1
    }

    title: L10n.t("transferCredentialsTitle")
    description: L10n.t("transferCredentialsTransient") + (target.length > 0 ? "\n" + target : "")
    submitDisabled: secret.text.length === 0
    onSubmitted: submit()
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s4
        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("transferUsername") }
            MeridianTextField { id: username; width: parent.width; Accessible.name: L10n.t("transferUsername") }
        }
        Column {
            width: parent.width
            spacing: Theme.space.s2
            // Without a token choice the one field takes either (the Dart clone credential).
            MeridianText { role: MeridianText.Label; text: dialog.secretLabel }
            MeridianTextField {
                id: secret
                width: parent.width
                echoMode: TextInput.Password
                Accessible.name: dialog.secretLabel
                onAccepted: dialog.submit()
            }
        }
        MeridianCheckbox {
            visible: dialog.allowToken
            text: L10n.t("transferUseToken")
            checked: dialog.useToken
            onToggled: dialog.useToken = checked
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton { text: L10n.t("retryAuthentication"); variant: MeridianButton.Primary; enabled: secret.text.length > 0; onClicked: dialog.submit() }
    ]
}
