pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// What a failed transfer means and how to resolve it (the failure
// catalog): a pull's saved changes, a case collision of tracking refs, a
// remote that moved ahead, or a lock another Git process held.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var report: ({})
    signal answered(int id, var remedy)

    readonly property bool recovery: !!report.stash && report.stash.reapplyCompleted !== true
    readonly property bool pruningFetch: report.kind === "fetch" && report.prune === true
    readonly property var spellings: report.reference ? [report.reference].concat(report.related ?? []) : []
    readonly property bool repairable: spellings.length > 0 && spellings.every(name => name.startsWith("refs/remotes/"))
    function short(reference) {
        for (const prefix of ["refs/remotes/", "refs/heads/", "refs/tags/"])
            if (reference.startsWith(prefix))
                return reference.substring(prefix.length)
        return reference
    }
    readonly property var guide: {
        if (recovery) {
            const stash = report.stash
            const key = !stash.pullCompleted ? (stash.reapplyCompleted ? "transferPullFailedStashRestored" : "transferPullFailedStashSaved")
                : stash.reapplyCompleted ? "transferPullStashRestored"
                : stash.conflicted ? "transferPullStashConflict" : "transferPullStashSaved"
            return { title: L10n.t("transferPullRecoveryTitle"), message: L10n.tn(key, { reason: L10n.t("transferFailed") }),
                     explanation: L10n.t("transferPullRecoveryHelp"), actions: [] }
        }
        if (report.diagnosis === "refCaseCollision") {
            const actions = []
            if (pruningFetch) actions.push({ id: "retryWithoutPrune", label: L10n.t("failureFetchWithoutPrune") })
            if (repairable) actions.push({ id: "repairTrackingRefs", label: L10n.t("failureCaseCollisionRepairAction"), primary: true })
            return { title: L10n.t("failureCaseCollisionTitle"),
                     message: L10n.tn("failureCaseCollisionMessage", { names: spellings.map(short).join(", ") }),
                     explanation: repairable ? L10n.t("failureCaseCollisionRepair") : L10n.t("failureCaseCollisionServer"),
                     actions: actions }
        }
        if (report.diagnosis === "remoteAhead")
            return { title: L10n.t("failureRemoteAheadTitle"), message: L10n.t("failureRemoteAheadMessage"), explanation: "",
                     actions: [{ id: "fetchRemote", label: L10n.t("operationFetch"), primary: true }] }
        const actions = []
        if (pruningFetch) actions.push({ id: "retryWithoutPrune", label: L10n.t("failureFetchWithoutPrune") })
        actions.push({ id: "retry", label: L10n.t("repositoryLockRetry"), primary: true })
        return { title: L10n.t("repositoryLockTitle"), message: L10n.t("transferFailureLocked"),
                 explanation: L10n.t("repositoryLockExplanation"), actions: actions }
    }

    function ask(id, value) {
        promptId = id
        report = value
        open()
    }
    function choose(action) {
        close()
        answered(promptId, { remedy: action, references: spellings })
        promptId = -1
    }

    title: guide.title
    description: guide.message
    onRejected: { answered(promptId, null); promptId = -1 }

    MeridianText {
        visible: (dialog.guide.explanation ?? "").length > 0
        width: parent ? parent.width : 0
        text: dialog.guide.explanation ?? ""
        color: Theme.colors.inkMuted
        wrapMode: Text.Wrap
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        Repeater {
            model: dialog.guide.actions
            delegate: MeridianButton {
                required property var modelData
                text: modelData.label
                variant: modelData.primary ? MeridianButton.Primary : MeridianButton.Secondary
                onClicked: dialog.choose(modelData.id)
            }
        }
    ]
}
