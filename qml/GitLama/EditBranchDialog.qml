pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Renames a branch and chooses its upstream (the Dart EditBranchDialog).
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var payload: ({})
    property var upstream: null
    readonly property var references: payload.references ?? ({})
    readonly property string nameText: nameField.text.trim()
    readonly property bool exists: nameText !== payload.branch
        && (references.branches ?? []).some(branch => branch.name === nameText)
    readonly property var upstreams: [null].concat([].concat(...(references.remotes ?? [])
        .map(remote => remote.branches.filter(branch => branch !== "HEAD").map(branch => remote.name + "/" + branch))))
    signal answered(int id, var edit)

    function ask(id, value) {
        promptId = id
        payload = value
        nameField.text = value.branch ?? ""
        upstream = value.upstream ?? null
        open()
        nameField.forceActiveFocus()
    }
    function submit() {
        if (nameText.length === 0 || exists)
            return
        close()
        answered(promptId, { name: nameText, upstream: upstream })
        promptId = -1
    }

    widthClass: MeridianDialog.Form
    title: Commands.dialogTitle(L10n.t("commandEditBranch"))
    description: L10n.t("editBranchDescription")
    submitDisabled: nameText.length === 0 || exists
    onSubmitted: submit()
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6
        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("editBranchName") }
            MeridianTextField { id: nameField; width: parent.width; error: dialog.exists; Accessible.name: L10n.t("editBranchName") }
            MeridianText {
                visible: dialog.exists
                role: MeridianText.Caption
                color: Theme.colors.danger
                text: L10n.t("editBranchNameExists")
            }
        }
        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("editBranchUpstream") }
            MeridianSelect {
                fixedWidth: parent.width
                label: L10n.t("editBranchUpstream")
                values: dialog.upstream !== null && dialog.upstreams.indexOf(dialog.upstream) < 0
                    ? dialog.upstreams.concat([dialog.upstream]) : dialog.upstreams
                value: dialog.upstream
                valueLabel: value => value === null ? L10n.t("editBranchNoUpstream")
                    : value
                onActivated: value => dialog.upstream = value
            }
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton { text: L10n.t("editBranchSave"); variant: MeridianButton.Primary; enabled: dialog.nameText.length > 0 && !dialog.exists; onClicked: dialog.submit() }
    ]
}
