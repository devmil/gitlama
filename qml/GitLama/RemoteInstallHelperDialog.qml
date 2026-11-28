import QtQuick
import Meridian

// Asks before copying this version's helper to a host:
// where it goes, its size and digest, and whether later versions may install theirs without
// asking. Answers the `remoteInstallHelper` prompt with {automatic} or null.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var request: ({})
    property bool automatic: false
    property var answerTo: null

    function ask(id, payload, answer) {
        promptId = id
        request = payload
        automatic = payload.automatic === true
        answerTo = answer
        open()
    }
    function finish(value) {
        if (promptId < 0)
            return
        const id = promptId
        promptId = -1
        answerTo(id, value)
    }
    function confirm() {
        finish({ automatic: automatic })
        close()
    }

    widthClass: MeridianDialog.Confirm
    title: L10n.tn("remoteInstallHelperTitle", { host: request.label ?? "" })
    onSubmitted: confirm()
    onClosed: finish(null)

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s2

        MeridianText {
            width: parent.width
            wrapMode: Text.Wrap
            text: L10n.tn("remoteInstallHelperDetail", { alias: dialog.request.alias ?? "" })
        }
        Item { width: 1; height: Theme.space.s2 }
        MeridianText { role: MeridianText.Caption; color: Theme.colors.inkMuted; text: L10n.t("remoteHelperLocationLabel") }
        MeridianSelectableText {
            objectName: "remote-install-location"
            width: parent.width
            role: MeridianText.CodeSm
            wrapMode: Text.WrapAnywhere
            text: dialog.request.location ?? ""
        }
        Item { width: 1; height: Theme.space.s1 }
        MeridianText {
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: L10n.tn("remoteInstallHelperSize", { size: Labels.byteSize(dialog.request.bytes ?? 0) })
        }
        MeridianSelectableText {
            width: parent.width
            role: MeridianText.CodeSm
            wrapMode: Text.WrapAnywhere
            text: L10n.tn("remoteInstallHelperDigest", { digest: dialog.request.sha256 ?? "" })
        }
        Item { width: 1; height: Theme.space.s2 }
        MeridianCheckbox {
            objectName: "remote-install-automatic"
            text: L10n.t("remoteAutoInstallHelper")
            checked: dialog.automatic
            onToggled: dialog.automatic = checked
        }
        MeridianText {
            width: parent.width
            role: MeridianText.Caption
            wrapMode: Text.Wrap
            color: Theme.colors.inkMuted
            text: L10n.t("remoteAutoInstallHelperDetail")
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.close() },
        MeridianButton {
            objectName: "remote-install-confirm"
            text: L10n.t("remoteInstallHelperConfirm")
            variant: MeridianButton.Primary
            onClicked: dialog.confirm()
        }
    ]
}
