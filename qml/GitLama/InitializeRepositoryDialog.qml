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
    readonly property var hosts: Store.remote && Store.remoteEnabled ? (Store.remote.hosts ?? []) : []
    readonly property var host: local ? null : hosts.find(item => item.id === location) ?? null
    /// Why repositories cannot be created on the chosen host before connecting to it.
    readonly property string blocked: local ? "" : host === null ? L10n.t("remoteRecentHostMissing")
        : host.initializeBlock ? L10n.t(host.initializeBlock) : ""
    // A host removed while the dialog is open is no longer a choice.
    onHostsChanged: if (!local && !hosts.some(item => item.id === location)) location = ""
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
        MeridianSelect {
            objectName: "initialize-location"
            visible: dialog.hosts.length > 0
            Layout.fillWidth: true
            fixedWidth: parent.width
            label: L10n.t("initializeLocation")
            showLabel: true
            values: [""].concat(dialog.hosts.map(item => item.id))
            value: dialog.location
            valueLabel: value => value === "" ? L10n.t("initializeLocationThisComputer")
                : (dialog.hosts.find(item => item.id === value) ?? ({ label: "" })).label
            onActivated: value => dialog.location = value
        }
        MeridianBanner {
            objectName: "initialize-blocked"
            visible: dialog.blocked.length > 0
            Layout.fillWidth: true
            tone: MeridianBanner.Info
            message: dialog.blocked
        }
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
