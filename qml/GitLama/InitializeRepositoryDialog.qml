import QtQuick
import QtQuick.Layouts
import Meridian

// Asks where a new repository goes and whether it is bare. Hosts are offered
// when there are any; a host that does not allow changes cannot be chosen
// and says why.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property bool bare: false
    /// "" is this computer; hosts use their profile IDs.
    property string location: ""
    readonly property bool local: location === ""
    readonly property string blocked: ""
    property bool _answered: false

    signal chosen(int id, var choice)

    function ask(id, initiallyBare) {
        promptId = id
        bare = initiallyBare
        location = ""
        _answered = false
        open()
    }

    function finish(choice) {
        if (_answered)
            return
        _answered = true
        chosen(promptId, choice)
    }

    widthClass: MeridianDialog.Form
    title: L10n.t("initializeRepository")
    description: local ? L10n.t("initializeDestinationHint") : L10n.t("initializeRemoteDestinationHint")
    submitDisabled: blocked.length > 0
    onSubmitted: {
        finish({ profileId: local ? null : location, bare: bare })
        close()
    }
    onRejected: finish(null)
    onClosed: finish(null)

    ColumnLayout {
        width: parent.width
        spacing: Theme.space.s6
        MeridianCheckbox {
            objectName: "initialize-bare"
            Layout.fillWidth: true
            text: L10n.t("initializeBareOption")
            description: L10n.t("initializeBareHelp")
            checked: dialog.bare
            onToggled: dialog.bare = checked
        }
    }

    actions: [
        MeridianButton {
            text: L10n.t("cancel")
            variant: MeridianButton.Quiet
            onActivated: dialog.close()
        },
        MeridianButton {
            objectName: "initialize-continue"
            text: L10n.t("chooseCloneDestination")
            variant: MeridianButton.Primary
            enabled: dialog.blocked.length === 0
            disabledReason: dialog.blocked
            onActivated: dialog.submit()
        }
    ]
}
