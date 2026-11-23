pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The branch, tag and remote dialog:
// the fields the change of `kind` needs.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var payload: ({})
    readonly property var references: payload.references ?? ({})
    readonly property string kind: payload.kind ?? "createBranch"
    readonly property var remoteNames: (references.remotes ?? []).map(remote => remote.name)
    readonly property bool remoteKind: kind === "editRemote" || kind === "renameRemote"
    readonly property bool fixedName: remoteKind && (payload.initialName ?? "").length > 0
    readonly property bool needsName: kind !== "reset"
    readonly property bool needsSecondName: kind === "renameBranch" || kind === "renameRemote"
    readonly property bool needsTarget: kind === "createBranch" || kind === "createTag" || kind === "reset"
    readonly property bool needsUrl: kind === "addRemote" || kind === "editRemote"
    property bool checkout: true
    property bool force: false
    property bool deleteUpstream: false
    property string resetMode: "mixed"
    property var tagRemotes: []
    readonly property string nameText: nameField.text.trim()
    readonly property string secondText: secondField.text.trim()
    readonly property var upstream: {
        if (kind !== "deleteBranch")
            return null
        const branch = (references.branches ?? []).find(item => item.name === nameText)
        if (!branch || !branch.upstream)
            return null
        const short = branch.upstream.replace(/^refs\/remotes\//, "")
        const owner = remoteNames.filter(remote => short.startsWith(remote + "/")).sort((a, b) => b.length - a.length)[0]
        if (!owner)
            return null
        const name = short.substring(owner.length + 1)
        const fetched = (references.remotes.find(remote => remote.name === owner).branches ?? []).indexOf(name) >= 0
        return fetched ? { remote: owner, branch: name, label: owner + "/" + name } : null
    }
    readonly property bool valid: (!needsName || nameText.length > 0)
        && (!needsSecondName || (secondText.length > 0
            && (kind !== "renameRemote" || (secondText !== nameText && remoteNames.indexOf(secondText) < 0))))
        && (!needsTarget || targetField.text.trim().length > 0)
        && (!needsUrl || urlField.text.trim().length > 0)
    readonly property string commandId: ({
        createBranch: "createBranch", renameBranch: "renameBranch", deleteBranch: "deleteBranch",
        checkoutBranch: "checkoutBranch", checkoutCommit: "checkoutCommit", setUpstream: "renameBranch",
        unsetUpstream: "renameBranch", createTag: "createTag", deleteTag: "deleteTag", addRemote: "addRemote",
        editRemote: "editRemote", renameRemote: "renameRemote", removeRemote: "removeRemote", reset: "resetBranch" })[kind]
    readonly property string titleText: Commands.dialogTitle(Commands.label(commandId))
    signal answered(int id, var request)

    property bool currentUrlHidden: false
    /// The references and loaded commits the target offers.
    property var choices: []
    /// Branch names without their remote, for new names.
    readonly property var branchNameSuggestions: (references.branches ?? []).map(branch => branch.name)
        .concat([].concat(...(references.remotes ?? []).map(remote => remote.branches)))
    function ask(id, value) {
        promptId = id
        payload = value
        const previous = value.previous
        nameField.text = previous ? (previous.name ?? "") : (value.initialName ?? "")
        secondField.text = previous ? (previous.secondName ?? "") : ""
        targetField.text = previous ? (previous.target ?? "") : (value.initialTarget ?? "")
        const remote = (value.references.remotes ?? []).find(item => item.name === value.initialName)
        // A URL with credentials shows redacted: it is never offered for editing.
        currentUrlHidden = !!remote && value.kind === "editRemote" && String(remote.url ?? "").indexOf("[REDACTED]") >= 0
        urlField.text = previous ? (previous.url ?? "") : (remote && value.kind === "editRemote" && !currentUrlHidden ? remote.url : "")
        messageField.text = previous ? (previous.message ?? "") : ""
        choices = Store.history ? Store.history.referenceChoices() : []
        checkout = previous ? previous.checkout === true : true
        force = previous ? previous.force === true : false
        deleteUpstream = false
        resetMode = previous && previous.resetMode ? previous.resetMode : "mixed"
        tagRemotes = previous ? (previous.remoteNames ?? []) : []
        open()
        if (fixedName)
            (needsSecondName ? secondField : urlField).forceActiveFocus()
        else if (needsName)
            nameField.forceActiveFocus()
    }
    /// Development screenshots type a name.
    function fill(name) { nameField.text = name }
    function submit() {
        if (!valid)
            return
        close()
        answered(promptId, {
            kind: kind,
            name: needsName ? nameText : "",
            secondName: needsSecondName ? secondText : "",
            target: needsTarget ? targetField.text.trim() : "",
            url: needsUrl ? urlField.text.trim() : "",
            force: force,
            remoteNames: kind === "deleteTag" ? tagRemotes : [],
            deleteUpstream: deleteUpstream && upstream ? upstream : null,
            checkout: kind === "createBranch" && checkout,
            resetMode: kind === "reset" ? resetMode : null,
            message: kind === "createTag" ? messageField.text : "",
        })
        promptId = -1
    }

    widthClass: MeridianDialog.Form
    title: titleText
    submitDisabled: !valid
    onSubmitted: submit()
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6

        ReferenceField {
            id: nameField
            visible: dialog.needsName
            width: parent.width
            label: L10n.t("refMutationName")
            selectionIcon: dialog.remoteKind || dialog.needsUrl || dialog.kind === "removeRemote" ? "cloud"
                : dialog.kind === "deleteTag" || dialog.kind === "createTag" ? "tag" : "branch"
            names: dialog.kind === "createBranch" ? dialog.branchNameSuggestions
                : dialog.kind === "createTag" ? []
                : dialog.remoteKind || dialog.kind === "removeRemote" ? dialog.remoteNames
                : dialog.kind === "deleteTag" ? (dialog.references.tags ?? []).map(tag => tag.name)
                : (dialog.references.branches ?? []).map(branch => branch.name)
            normalize: dialog.kind === "createBranch" || dialog.kind === "createTag"
            suggestSegments: dialog.kind === "createBranch"
            suggestions: (dialog.remoteKind || !dialog.needsUrl) && dialog.kind !== "createTag"
            enabled: !dialog.fixedName
        }
        ReferenceField {
            id: secondField
            visible: dialog.needsSecondName
            width: parent.width
            label: L10n.t("refMutationNewName")
            names: dialog.kind === "renameRemote" ? [] : dialog.branchNameSuggestions
            normalize: true
            suggestSegments: dialog.kind === "renameBranch"
        }
        Column {
            visible: dialog.needsUrl
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("refMutationRemoteUrl") }
            MeridianTextField { id: urlField; width: parent.width; Accessible.name: L10n.t("refMutationRemoteUrl") }
            MeridianText {
                visible: dialog.currentUrlHidden
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                text: L10n.t("refMutationRemoteUrlHidden")
            }
        }
        ReferenceField {
            id: targetField
            visible: dialog.needsTarget
            width: parent.width
            label: dialog.kind === "createBranch" ? L10n.t("refMutationStartingPoint") : L10n.t("extensionWorktreeReference")
            names: ["HEAD"].concat((dialog.references.branches ?? []).map(branch => branch.name))
                .concat([].concat(...(dialog.references.remotes ?? []).map(remote => remote.branches.map(branch => remote.name + "/" + branch))))
                .concat((dialog.references.tags ?? []).map(tag => tag.name))
            choices: dialog.choices
            helperText: L10n.t("referencePickerHistoryHint")
        }
        MeridianCheckbox {
            objectName: "create-branch-checkout"
            visible: dialog.kind === "createBranch"
            text: L10n.t("refMutationCheckoutNewBranch")
            checked: dialog.checkout
            onToggled: dialog.checkout = checked
        }
        Column {
            visible: dialog.kind === "createTag"
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("refMutationTagMessage") }
            MeridianTextArea {
                id: messageField
                width: parent.width
                minimumLines: 3
                maximumLines: 3
                Accessible.name: L10n.t("refMutationTagMessage")
            }
        }
        MeridianCheckbox {
            visible: dialog.kind === "deleteBranch"
            text: L10n.t("refMutationForceDelete")
            checked: dialog.force
            onToggled: dialog.force = checked
        }
        MeridianCheckbox {
            objectName: "delete-branch-upstream"
            visible: dialog.upstream !== null
            width: parent.width
            text: dialog.upstream ? L10n.tn("refMutationDeleteUpstream", { upstream: dialog.upstream.label }) : ""
            description: L10n.t("refMutationDeleteUpstreamHelp")
            checked: dialog.deleteUpstream
            onToggled: dialog.deleteUpstream = checked
        }
        Column {
            objectName: "delete-tag-remotes"
            visible: dialog.kind === "deleteTag" && (dialog.references.remotes ?? []).length > 0
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("deleteTagRemotePrompt") }
            Repeater {
                model: dialog.references.remotes ?? []
                delegate: MeridianCheckbox {
                    required property var modelData
                    text: modelData.name
                    description: modelData.url
                    checked: dialog.tagRemotes.indexOf(modelData.name) >= 0
                    onToggled: {
                        const next = dialog.tagRemotes.filter(name => name !== modelData.name)
                        if (checked)
                            next.push(modelData.name)
                        dialog.tagRemotes = next
                    }
                }
            }
            MeridianText {
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: L10n.t("deleteTagRemoteAvailabilityHint")
                wrapMode: Text.Wrap
            }
        }
        Column {
            visible: dialog.kind === "reset"
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("refMutationResetMode") }
            MeridianSelect {
                fixedWidth: parent.width
                label: L10n.t("refMutationResetMode")
                values: ["soft", "mixed", "hard"]
                value: dialog.resetMode
                valueLabel: value => ({ soft: L10n.t("refMutationResetSoft"), mixed: L10n.t("refMutationResetMixed"),
                                        hard: L10n.t("refMutationResetHard") })[value]
                onActivated: value => dialog.resetMode = value
            }
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton { text: dialog.titleText; variant: MeridianButton.Primary; enabled: dialog.valid; onClicked: dialog.submit() }
    ]
}
