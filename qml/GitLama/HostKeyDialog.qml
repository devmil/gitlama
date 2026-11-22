import QtQuick
import Meridian

// Trust a server's SSH host key (confirmHostKey): the server, key type and
// fingerprint to compare with what its administrator published.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var challenge: ({})
    signal answered(int id, bool trust)

    function ask(id, value) {
        promptId = id
        challenge = value
        open()
    }

    title: L10n.t("hostKeyTitle")
    description: L10n.t("hostKeyDescription")
    onSubmitted: { close(); answered(promptId, true); promptId = -1 }
    onRejected: { answered(promptId, false); promptId = -1 }

    MeridianPropertyList {
        width: parent ? parent.width : 0
        properties: [
            { label: L10n.t("hostKeyServer"), value: (dialog.challenge.host ?? "") + ((dialog.challenge.port ?? 22) !== 22 ? ":" + dialog.challenge.port : "") },
            { label: L10n.t("hostKeyType"), value: dialog.challenge.algorithm ?? "" },
            { label: L10n.t("hostKeyFingerprint"), value: dialog.challenge.fingerprint ?? "", monospace: true },
        ]
    }
    actions: [
        MeridianButton { text: L10n.t("rejectHostKey"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton { text: L10n.t("trustHostKey"); variant: MeridianButton.Primary; onClicked: dialog.submitted() }
    ]
}
