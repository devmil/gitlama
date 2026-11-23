pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Confirms a reference change: what it does, from where to where, the
// warnings Git's state raises, and the Git commands it runs.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var payload: ({})
    readonly property var request: payload.request ?? ({})
    readonly property bool destructive: ["deleteBranch", "deleteTag", "removeRemote", "reset"].indexOf(request.kind) >= 0
        && (request.kind !== "reset" || request.resetMode === "hard")
    signal answered(int id, bool confirmed)

    function titleFor(kind) {
        const command = ({ createBranch: "createBranch", renameBranch: "renameBranch", deleteBranch: "deleteBranch",
            checkoutBranch: "checkoutBranch", checkoutCommit: "checkoutCommit", setUpstream: "editBranch",
            unsetUpstream: "editBranch", createTag: "createTag", deleteTag: "deleteTag", addRemote: "addRemote",
            editRemote: "editRemote", renameRemote: "renameRemote", removeRemote: "removeRemote", reset: "resetBranch" })[kind]
        // The confirmation titles name the mutation (the Dart
        // refMutationConfirmationTitle), not always the registry command.
        return Commands.dialogTitle(command === "editBranch" ? L10n.t("commandEditBranch")
            : command === "renameBranch" ? L10n.t("commandRenameBranch") : Commands.label(command))
    }
    function message(request) {
        const name = request.name ?? ""
        switch (request.kind) {
        case "createBranch": return request.checkout ? L10n.tn("refConfirmCreateAndCheckoutBranch", { name: name }) : L10n.tn("refConfirmCreateBranch", { name: name })
        case "renameBranch": return L10n.tn("refConfirmRenameBranch", { name: name, newName: request.secondName ?? "" })
        case "deleteBranch": return request.deleteUpstream
            ? L10n.tn("refConfirmDeleteBranchAndUpstream", { name: name, upstream: request.deleteUpstream.label })
            : L10n.tn("refConfirmDeleteBranch", { name: name })
        case "checkoutBranch": return L10n.tn("refConfirmCheckoutBranch", { name: name })
        case "checkoutCommit": return L10n.tn("refConfirmCheckoutCommit", { target: request.target ?? "" })
        case "setUpstream": return L10n.tn("refConfirmSetUpstream", { name: name, upstream: request.secondName ?? "" })
        case "unsetUpstream": return L10n.tn("refConfirmUnsetUpstream", { name: name })
        case "createTag": return L10n.tn("refConfirmCreateTag", { name: name })
        case "deleteTag": return (request.remoteNames ?? []).length === 0
            ? L10n.tn("refConfirmDeleteTagLocal", { name: name })
            : L10n.tn("refConfirmDeleteTagRemotes", { name: name, remotes: request.remoteNames.join(", ") })
        case "addRemote": return L10n.tn("refConfirmAddRemote", { name: name })
        case "editRemote": return L10n.tn("refConfirmEditRemote", { name: name })
        case "renameRemote": return L10n.tn("refConfirmRenameRemote", { name: name, newName: request.secondName ?? "" })
        case "removeRemote": return L10n.tn("refConfirmRemoveRemote", { name: name })
        case "reset": return request.resetMode === "hard" ? L10n.t("refConfirmResetHard")
            : request.resetMode === "mixed" ? L10n.t("refConfirmResetMixed") : L10n.t("refConfirmResetSoft")
        default: return ""
        }
    }
    function warningText(warning) {
        return L10n.t(({ dirtyCheckout: "refMutationWarningDirty", detachedHead: "refMutationWarningDetached",
                         publishedBranch: "refMutationWarningPublished", checkedOutElsewhere: "refMutationWarningOtherWorktree",
                         destructiveReset: "refMutationWarningDestructiveReset" })[warning])
    }
    readonly property var commands: {
        const list = ["git " + (payload.arguments ?? []).join(" ")]
        if (payload.localTagObjectId)
            for (const remote of request.remoteNames ?? [])
                list.push("git push --force-with-lease=refs/tags/" + request.name + ":" + payload.localTagObjectId + " " + remote + " :refs/tags/" + request.name)
        if (request.deleteUpstream)
            list.push("git push --force-with-lease=refs/heads/" + request.deleteUpstream.branch + " " + request.deleteUpstream.remote + " :refs/heads/" + request.deleteUpstream.branch)
        return list
    }

    function ask(id, value) {
        promptId = id
        payload = value
        open()
    }

    title: titleFor(request.kind)
    onSubmitted: { close(); answered(promptId, true); promptId = -1 }
    onRejected: { answered(promptId, false); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s4
        MeridianText { width: parent.width; text: dialog.message(dialog.request); wrapMode: Text.Wrap }
        Row {
            visible: !!dialog.request.name && (!!dialog.request.secondName || !!dialog.request.target)
            spacing: Theme.space.s3
            MeridianText { role: MeridianText.CodeSm; text: dialog.request.target ?? dialog.request.name ?? ""; color: Theme.colors.inkMuted }
            MeridianIcon { name: "arrow-right"; iconSize: MeridianIcon.Small; color: Theme.colors.inkMuted; anchors.verticalCenter: parent.verticalCenter }
            MeridianText { role: MeridianText.CodeSm; text: dialog.request.secondName ?? dialog.request.name ?? "" }
        }
        MeridianText {
            visible: (dialog.request.remoteNames ?? []).length > 0 || !!dialog.request.deleteUpstream
            width: parent.width
            text: L10n.t("deleteRefOnRemoteWarning")
            wrapMode: Text.Wrap
        }
        Repeater {
            model: dialog.payload.warnings ?? []
            delegate: MeridianBanner {
                required property string modelData
                width: parent ? parent.width : 0
                tone: MeridianBanner.Warning
                message: dialog.warningText(modelData)
            }
        }
        Rectangle {
            width: parent.width
            height: commandText.implicitHeight + 2 * Theme.space.s3
            radius: Theme.radius.sm
            color: Theme.colors.paneAlt
            border.color: Theme.colors.line
            MeridianSelectableText {
                id: commandText
                x: Theme.space.s3
                y: Theme.space.s3
                width: parent.width - 2 * Theme.space.s3
                role: MeridianText.CodeSm
                text: dialog.commands.join("\n")
                wrapMode: Text.WrapAnywhere
            }
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            text: dialog.request.kind === "deleteBranch" || dialog.request.kind === "deleteTag" ? L10n.t("delete") : dialog.titleFor(dialog.request.kind)
            variant: dialog.destructive ? MeridianButton.Danger : MeridianButton.Primary
            onClicked: dialog.submitted()
        }
    ]
}
