pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Renames a branch and chooses its upstream.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var payload: ({})
    readonly property var references: payload.references ?? ({})
    readonly property string initialUpstream: payload.upstream ?? ""
    readonly property string nameText: nameField.text.trim()
    readonly property string upstreamText: upstreamField.text.trim()
    readonly property var otherBranches: (references.branches ?? []).map(branch => branch.name)
        .filter(name => name !== payload.branch)
    readonly property var remoteBranches: [].concat(...(references.remotes ?? [])
        .map(remote => remote.branches.filter(branch => branch !== "HEAD").map(branch => remote.name + "/" + branch))).sort()
    readonly property bool exists: otherBranches.indexOf(nameText) >= 0
    // A gone upstream may stay as it is; a new one must be fetched.
    readonly property bool upstreamValid: upstreamText.length === 0 || upstreamText === initialUpstream
        || remoteBranches.indexOf(upstreamText) >= 0
    readonly property bool changed: nameText !== payload.branch || upstreamText !== initialUpstream
    readonly property bool canSave: nameText.length > 0 && !exists && upstreamValid && changed
    signal answered(int id, var edit)

    function ask(id, value) {
        promptId = id
        payload = value
        nameField.text = value.branch ?? ""
        upstreamField.text = value.upstream ?? ""
        open()
        nameField.searchField.forceActiveFocus()
    }
    function submit() {
        if (!canSave)
            return
        close()
        answered(promptId, { name: nameText, upstream: upstreamText.length > 0 ? upstreamText : null })
        promptId = -1
    }

    widthClass: MeridianDialog.Form
    title: Commands.dialogTitle(L10n.t("commandEditBranch"))
    description: L10n.t("editBranchDescription")
    submitDisabled: !canSave
    onSubmitted: submit()
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6
        ReferenceField {
            id: nameField
            objectName: "edit-branch-name"
            width: parent.width
            label: L10n.t("editBranchName")
            names: dialog.otherBranches
            normalize: true
            suggestSegments: true
            helperText: dialog.exists ? L10n.t("editBranchNameExists") : ""
        }
        ReferenceField {
            id: upstreamField
            objectName: "edit-branch-upstream"
            width: parent.width
            label: L10n.t("editBranchUpstream")
            selectionIcon: "cloud"
            names: dialog.remoteBranches
            helperText: dialog.upstreamValid ? L10n.t("editBranchNoUpstream") : L10n.t("editBranchUpstreamUnknown")
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton { text: L10n.t("editBranchSave"); variant: MeridianButton.Primary; enabled: dialog.canSave; onClicked: dialog.submit() }
    ]
}
