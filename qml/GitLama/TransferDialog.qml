pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The transfer dialog: the remote, the
// branch or tag, and the options of a fetch, pull or push.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var payload: ({})
    readonly property string kind: payload.kind ?? "fetch"
    readonly property var remotes: payload.remotes ?? []
    property string remote: ""
    property string strategy: "fastForwardOnly"
    property bool allowDirty: false
    property bool stashBeforePull: false
    property bool force: false
    property bool setUpstream: true
    property bool prune: true
    readonly property bool tagKind: kind === "pushTag" || kind === "deleteTag"
    readonly property string branchText: branchField.text.trim()
    readonly property var remoteBranches: {
        const entry = (payload.remoteBranches ?? []).find(item => item.remote === remote)
        return entry ? entry.branches.filter(name => kind !== "deleteBranch" || name !== "HEAD") : []
    }
    readonly property bool branchHasUpstream: {
        const name = branchText
        if (payload.currentBranch === name && payload.currentUpstream)
            return true
        const branch = (payload.branches ?? []).find(item => item.name === name)
        return branch ? branch.hasUpstream === true : false
    }
    readonly property bool canSubmit: remote.length > 0
        && (kind === "fetch" || branchText.length > 0)
        && (kind !== "deleteBranch" || remoteBranches.indexOf(branchText) >= 0)
    readonly property bool needsAcknowledgement: kind === "pull" && payload.dirty === true && !allowDirty && !stashBeforePull
    readonly property string titleText: Commands.dialogTitle(L10n.t(({
        fetch: "commandFetch", pull: "commandPull", push: "commandPush", pushTag: "commandPushTag",
        deleteTag: "commandDeleteTag", deleteBranch: "commandDeleteRemoteBranch" })[kind]))

    signal answered(int id, var request)

    function ask(id, value) {
        promptId = id
        payload = value
        remote = value.initialRemote && (value.remotes ?? []).indexOf(value.initialRemote) >= 0
            ? value.initialRemote : ((value.remotes ?? [])[0] ?? "")
        strategy = value.initialPullStrategy ?? "fastForwardOnly"
        force = value.initialForce === true
        allowDirty = false
        stashBeforePull = false
        setUpstream = true
        prune = true
        branchField.text = value.branch ?? ""
        open()
    }
    function submit() {
        if (!canSubmit || needsAcknowledgement)
            return
        close()
        answered(promptId, {
            kind: kind,
            remote: remote,
            branch: kind === "fetch" ? "" : branchText,
            pullStrategy: strategy,
            allowDirty: allowDirty,
            stashBeforePull: stashBeforePull,
            forceWithLease: kind === "push" && force,
            setUpstream: kind === "push" && setUpstream && !branchHasUpstream,
            prune: prune,
        })
        promptId = -1
    }

    widthClass: MeridianDialog.Form
    title: titleText
    description: ({ fetch: L10n.t("transferFetchDescription"), pull: L10n.t("transferPullDescription"),
                    push: L10n.t("transferPushDescription"), pushTag: L10n.t("transferPushTagDescription"),
                    deleteBranch: L10n.t("transferDeleteBranchDescription") })[kind] ?? ""
    submitDisabled: !canSubmit || needsAcknowledgement
    onSubmitted: submit()
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6

        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("transferRemote") }
            MeridianSelect {
                objectName: "transfer-remote"
                fixedWidth: parent.width
                label: L10n.t("transferRemote")
                values: dialog.remotes
                value: dialog.remote
                valueLabel: value => value.length === 0 ? L10n.t("transferRemote") : value
                enabled: dialog.remotes.length > 0
                onActivated: value => dialog.remote = value
            }
        }
        ReferenceField {
            id: branchField
            visible: dialog.kind !== "fetch"
            width: parent.width
            selectionIcon: dialog.tagKind ? "tag" : "branch"
            label: dialog.tagKind ? L10n.t("transferTag") : L10n.t("transferBranch")
            names: dialog.tagKind ? (dialog.payload.tags ?? [])
                : dialog.kind === "pull" || dialog.kind === "deleteBranch" ? dialog.remoteBranches
                : (dialog.payload.branches ?? []).map(branch => branch.name)
            helperText: dialog.kind === "pushTag" ? L10n.t("transferTagHelp") : ""
        }
        Column {
            visible: dialog.kind === "pull"
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("transferPullStrategy") }
            MeridianSelect {
                objectName: "transfer-pull-strategy"
                fixedWidth: parent.width
                label: L10n.t("transferPullStrategy")
                values: ["fastForwardOnly", "fastForwardIfPossible", "rebase"]
                value: dialog.strategy
                valueLabel: value => ({ fastForwardOnly: L10n.t("transferFfOnly"),
                                        fastForwardIfPossible: L10n.t("transferFfPossible"),
                                        rebase: L10n.t("transferRebase") })[value]
                onActivated: value => dialog.strategy = value
            }
        }
        MeridianCheckbox {
            objectName: "transfer-prune"
            visible: dialog.kind === "fetch"
            width: parent.width
            text: L10n.t("transferPrune")
            description: L10n.t("transferPruneHelp")
            checked: dialog.prune
            onToggled: dialog.prune = checked
        }
        MeridianBanner {
            visible: dialog.kind === "pull" && dialog.payload.dirty === true
            width: parent.width
            tone: MeridianBanner.Info
            message: L10n.t("transferLocalChangesHelp")
        }
        MeridianCheckbox {
            objectName: "transfer-stash-before-pull"
            visible: dialog.kind === "pull" && dialog.payload.dirty === true
            width: parent.width
            text: L10n.t("transferStashBeforePull")
            description: L10n.t("transferStashBeforePullHelp")
            checked: dialog.stashBeforePull
            onToggled: { dialog.stashBeforePull = checked; if (checked) dialog.allowDirty = false }
        }
        MeridianCheckbox {
            objectName: "transfer-allow-dirty"
            visible: dialog.kind === "pull" && dialog.payload.dirty === true
            width: parent.width
            text: L10n.t("transferAllowDirty")
            description: L10n.t("transferAllowDirtyHelp")
            checked: dialog.allowDirty
            onToggled: { dialog.allowDirty = checked; if (checked) dialog.stashBeforePull = false }
        }
        MeridianCheckbox {
            objectName: "transfer-set-upstream"
            visible: dialog.kind === "push" && !dialog.branchHasUpstream
            width: parent.width
            text: L10n.t("transferSetUpstream")
            description: L10n.t("transferSetUpstreamHelp")
            checked: dialog.setUpstream
            onToggled: dialog.setUpstream = checked
        }
        MeridianCheckbox {
            objectName: "transfer-force"
            visible: dialog.kind === "push"
            width: parent.width
            text: L10n.t("transferForceOption")
            description: L10n.t("transferForceHelp")
            checked: dialog.force
            onToggled: dialog.force = checked
        }
    }

    actions: [
        MeridianButton {
            text: L10n.t("cancel")
            variant: MeridianButton.Quiet
            onClicked: dialog.reject()
        },
        MeridianButton {
            variant: dialog.kind === "deleteBranch" || dialog.kind === "deleteTag" ? MeridianButton.Danger : MeridianButton.Primary
            text: dialog.kind === "fetch" ? L10n.t("operationFetch")
                : dialog.kind === "pull" ? (dialog.stashBeforePull ? L10n.t("transferStashPullAction") : L10n.t("operationPull"))
                : dialog.kind === "push" ? L10n.t("operationPush") : dialog.titleText
            disabledReason: dialog.needsAcknowledgement ? L10n.t("transferFailureDirty") : ""
            enabled: dialog.canSubmit && !dialog.needsAcknowledgement
            onClicked: dialog.submit()
        }
    ]
}
