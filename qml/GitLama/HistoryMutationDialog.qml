pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Asks for a merge, cherry-pick or revert (the Dart
// HistoryMutationInputDialog): the branch and merge mode of a merge, the
// published-history acknowledgement of a cherry-pick, and a revert's
// "apply only" alternative.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var payload: ({})
    readonly property string kind: payload.kind ?? "merge"
    readonly property bool merge: kind === "merge"
    readonly property bool revert: kind === "revert"
    readonly property var branches: payload.branches ?? []
    readonly property var branch: branches.find(b => b.name === branchField.text.trim()) ?? null
    property string mergeMode: "fastForwardIfPossible"
    property bool acknowledged: false
    readonly property var targets: merge ? (branch ? [branch.target] : []) : (payload.selectedTargets ?? [])
    readonly property bool needsAcknowledgement: payload.publishedHistory === true && kind === "cherryPick"
    readonly property string blocked: revert && payload.activeOperation === true ? L10n.t("historyMutationFailureActive")
        : revert && payload.conflictedWorktree === true ? L10n.t("historyRevertResolveConflicts") : ""
    readonly property bool valid: targets.length > 0 && (!needsAcknowledgement || acknowledged) && blocked.length === 0
    readonly property string kindLabel: Commands.dialogTitle(Commands.label(
        ({ merge: "mergeBranch", cherryPick: "cherryPickSelected", revert: "revertSelected" })[kind]))
    signal answered(int id, var request)

    function ask(id, value) {
        promptId = id
        payload = value
        mergeMode = "fastForwardIfPossible"
        acknowledged = false
        const initial = (value.branches ?? []).find(b => b.target === value.initialTarget || b.name === value.initialSourceName)
            ?? (value.branches ?? [])[0]
        branchField.text = initial ? initial.name : ""
        open()
        if (merge)
            branchField.forceActiveFocus()
    }
    /// Development screenshots choose the merged branch.
    function chooseSource(name) { branchField.text = name }
    function finish(noCommit) {
        if (!valid || (noCommit && targets.length !== 1))
            return
        close()
        answered(promptId, {
            targets: targets,
            sourceName: merge && branch ? branch.name : "",
            mergeMode: mergeMode,
            acknowledgePublishedHistory: acknowledged,
            noCommit: noCommit,
        })
        promptId = -1
    }

    widthClass: MeridianDialog.Form
    submitDisabled: !valid
    title: revert && targets.length === 1 ? L10n.t("historyRevertCommit") : kindLabel
    description: merge ? L10n.t("historyMergeSummary")
        : targets.length === 0 ? L10n.t("historyMutationSelectCommits")
        : kind === "cherryPick" ? L10n.tn("historyCherryPickIntro", { count: targets.length })
        : L10n.tn("historyRevertIntro", { count: targets.length })
    onSubmitted: finish(false)
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6
        ReferenceField {
            id: branchField
            visible: dialog.merge
            width: parent.width
            label: L10n.t("historyMutationSourceBranch")
            names: dialog.branches.map(b => b.name)
        }
        MeridianSelect {
            visible: dialog.merge
            fixedWidth: parent.width
            showLabel: true
            label: L10n.t("historyMutationMergeMode")
            values: ["fastForwardIfPossible", "fastForwardOnly", "noFastForward"]
            value: dialog.mergeMode
            valueLabel: v => L10n.t({ fastForwardIfPossible: "historyMutationFastForwardPossible",
                                      fastForwardOnly: "historyMutationFastForwardOnly",
                                      noFastForward: "historyMutationNoFastForward" }[v])
            onActivated: v => dialog.mergeMode = v
        }
        MeridianBanner {
            visible: dialog.blocked.length > 0
            width: parent.width
            tone: MeridianBanner.Warning
            message: dialog.blocked
        }
        MeridianText {
            visible: dialog.revert && dialog.targets.length > 0
            width: parent.width
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: L10n.t(dialog.targets.length === 1 ? "historyRevertApplyHint" : "historyRevertApplySingleRequired")
        }
        MeridianCheckbox {
            visible: dialog.needsAcknowledgement
            width: parent.width
            text: L10n.t("historyMutationPublishedWarning")
            checked: dialog.acknowledged
            onToggled: dialog.acknowledged = checked
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            visible: dialog.revert
            text: L10n.t("historyRevertApplyOnly")
            enabled: dialog.valid && dialog.targets.length === 1
            disabledReason: dialog.targets.length > 1 ? L10n.t("historyRevertApplySingleRequired") : ""
            onClicked: dialog.finish(true)
        },
        MeridianButton {
            text: dialog.revert ? L10n.t("historyRevertCommitNow") : dialog.kindLabel
            variant: MeridianButton.Primary
            enabled: dialog.valid
            onClicked: dialog.finish(false)
        }
    ]
}
