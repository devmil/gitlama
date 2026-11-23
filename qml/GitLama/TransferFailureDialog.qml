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
        const actions = [{ id: "retry", label: L10n.t("repositoryLockRemoveAndRetry"), danger: true, removesLocks: true }]
        // Git can trip over its own lock while pruning.
        if (pruningFetch) actions.push({ id: "retryWithoutPrune", label: L10n.t("failureFetchWithoutPrune") })
        actions.push({ id: "retry", label: L10n.t("repositoryLockRetry"), primary: true })
        return { title: L10n.t("repositoryLockTitle"), message: L10n.t("transferFailureLocked"),
                 explanation: L10n.t("repositoryLockExplanation"), actions: actions, showsLocks: true }
    }

    // The repository's lock files.
    readonly property bool showsLocks: guide.showsLocks === true
    property var inspection: null
    property bool checking: false
    property bool inspectionFailed: false
    property bool removing: false
    property string removalError: ""
    readonly property var locks: inspection ? inspection.locks : []
    readonly property bool canRemoveLocks: inspection !== null && inspection.canRemove === true
    readonly property var shownActions: guide.actions.filter(action => !action.removesLocks || (canRemoveLocks && locks.length > 0))
    function inspectLocks() {
        checking = true
        inspectionFailed = false
        removalError = ""
        Store.workflows.inspectLocks()
    }
    function ageLabel(seconds) {
        if (seconds === null || seconds === undefined)
            return L10n.t("repositoryLockAgeUnknown")
        if (seconds >= 86400) return L10n.tn("repositoryLockAgeDays", { count: Math.floor(seconds / 86400) })
        if (seconds >= 3600) return L10n.tn("repositoryLockAgeHours", { count: Math.floor(seconds / 3600) })
        if (seconds >= 60) return L10n.tn("repositoryLockAgeMinutes", { count: Math.floor(seconds / 60) })
        return L10n.tn("repositoryLockAgeSeconds", { count: seconds })
    }
    Connections {
        target: Store.workflows
        function onLocksInspected(value) {
            dialog.checking = false
            dialog.inspection = value
            dialog.inspectionFailed = value === null
        }
        function onLocksRemoved(outcome) {
            dialog.removing = false
            if (outcome.failure) {
                dialog.removalError = L10n.t(outcome.failure)
                return
            }
            dialog.choose("retry")
        }
    }

    function ask(id, value) {
        promptId = id
        report = value
        inspection = null
        removalError = ""
        removing = false
        open()
        if (showsLocks)
            inspectLocks()
    }
    function run(action) {
        if (!action.removesLocks) {
            choose(action.id)
            return
        }
        removing = true
        removalError = ""
        Store.workflows.removeLocks(locks.map(lock => lock.token))
    }
    function choose(action) {
        close()
        answered(promptId, { remedy: action, references: spellings })
        promptId = -1
    }

    title: guide.title
    description: guide.message
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s4

        MeridianText {
            objectName: "transfer-failure-explanation"
            visible: (dialog.guide.explanation ?? "").length > 0
            width: parent.width
            text: dialog.guide.explanation ?? ""
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
        }
        Column {
            objectName: "repository-lock-list"
            visible: dialog.showsLocks
            width: parent.width
            spacing: Theme.space.s3
            Item {
                width: parent.width
                height: checkAgain.height
                MeridianText {
                    anchors.verticalCenter: parent.verticalCenter
                    role: MeridianText.Label
                    text: L10n.t("repositoryLockListTitle")
                }
                MeridianButton {
                    id: checkAgain
                    objectName: "repository-lock-check-again"
                    anchors.right: parent.right
                    text: L10n.t("repositoryLockCheckAgain")
                    iconName: "refresh-cw"
                    variant: MeridianButton.Quiet
                    controlSize: MeridianButton.Small
                    enabled: !dialog.checking && !dialog.removing
                    onClicked: dialog.inspectLocks()
                }
            }
            Row {
                visible: dialog.checking && dialog.inspection === null
                spacing: Theme.space.s3
                MeridianSpinner { anchors.verticalCenter: parent.verticalCenter }
                MeridianText {
                    anchors.verticalCenter: parent.verticalCenter
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: L10n.t("repositoryLockChecking")
                }
            }
            MeridianText {
                visible: dialog.inspectionFailed && !dialog.checking
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: L10n.t("repositoryLockInspectFailed")
            }
            MeridianPropertyList {
                visible: dialog.locks.length > 0
                width: parent.width
                properties: dialog.locks.map(lock => ({ label: dialog.ageLabel(lock.ageSeconds), value: lock.path, monospace: true }))
            }
            MeridianText {
                visible: dialog.inspection !== null && dialog.inspection.truncated === true
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: L10n.t("repositoryLockTruncated")
            }
        }
        MeridianBanner {
            objectName: "repository-lock-advice"
            readonly property string advice: dialog.inspection ? (dialog.inspection.advice ?? "") : ""
            visible: dialog.showsLocks && advice.length > 0
            width: parent.width
            tone: dialog.locks.length === 0 ? MeridianBanner.Success : MeridianBanner.Info
            message: advice === "none" ? L10n.t("repositoryLockNone")
                : advice === "recent" ? L10n.t("repositoryLockRecent")
                : advice === "stale" ? L10n.t("repositoryLockStale") : ""
        }
        MeridianBanner {
            visible: dialog.showsLocks && dialog.locks.length > 0
            width: parent.width
            tone: MeridianBanner.Warning
            message: dialog.canRemoveLocks ? L10n.t("repositoryLockRemoveWarning") : L10n.t("repositoryLockRemoteOnly")
        }
        MeridianBanner {
            objectName: "repository-lock-removal-error"
            visible: dialog.removalError.length > 0
            width: parent.width
            tone: MeridianBanner.Error
            message: dialog.removalError
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        Repeater {
            model: dialog.shownActions
            delegate: MeridianButton {
                required property var modelData
                objectName: "transfer-failure-" + (modelData.removesLocks ? "removeLocksAndRetry" : modelData.id)
                text: modelData.label
                variant: modelData.danger ? MeridianButton.Danger
                    : modelData.primary ? MeridianButton.Primary : MeridianButton.Secondary
                enabled: !dialog.removing
                loading: dialog.removing && modelData.removesLocks === true
                onClicked: dialog.run(modelData)
            }
        }
    ]
}
