pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// What a merge, cherry-pick or revert will do (the Dart
// HistoryMutationPreviewDialog): the branches, local changes, predicted
// conflicts, set-aside changes and the Git commands.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var preview: ({})
    readonly property string kind: preview.kind ?? "merge"
    readonly property bool setAside: preview.localChanges === "setAside"
    readonly property var prediction: preview.prediction ?? null
    signal answered(int id, bool confirmed)

    function ask(id, value) {
        promptId = id
        preview = value
        open()
    }

    title: L10n.t(({ merge: "historyMergePreviewTitle", cherryPick: "historyCherryPickPreviewTitle" })[kind] ?? "historyRevertPreviewTitle")
    description: kind === "merge" ? L10n.t("historyMergeSummary")
        : kind === "cherryPick" ? L10n.tn("historyCherryPickIntro", { count: preview.targets ?? 1 })
        : preview.noCommit === true ? L10n.t("historyRevertApplyIntro")
        : L10n.tn("historyRevertIntro", { count: preview.targets ?? 1 })
    onSubmitted: { close(); answered(promptId, true); promptId = -1 }
    onRejected: { answered(promptId, false); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6
        MeridianPropertyList {
            width: parent.width
            properties: {
                const list = []
                const p = dialog.preview
                if (dialog.kind === "merge")
                    list.push({ label: L10n.t("historyMutationSourceBranch"),
                                value: p.source ?? Labels.shortObjectId(p.firstTarget ?? ""), monospace: true })
                list.push({ label: L10n.t("historyPreviewCurrentBranch"), value: p.currentBranch ?? "", monospace: true })
                if ((p.localChanges ?? "none") !== "none")
                    list.push({ label: L10n.t("historyPreviewLocalChanges"),
                                value: L10n.t(dialog.setAside ? "historyRevertLocalSetAside" : "historyRevertLocalInPlace"), selectable: false })
                const prediction = dialog.prediction
                if (prediction !== null)
                    list.push({ label: L10n.t("historyPreviewConflicts"), selectable: false,
                                value: prediction.failed ? L10n.t("conflictCheckUnavailable")
                                     : prediction.conflicts === 0 ? L10n.t("conflictCheckNone")
                                     : L10n.tn("conflictCheckFiles", { count: prediction.conflicts }) })
                return list
            }
        }
        MeridianBanner {
            visible: dialog.preview.alreadyContained === true
            width: parent.width
            tone: MeridianBanner.Info
            message: L10n.t("historyMutationAlreadyContained")
        }
        MeridianText {
            visible: dialog.preview.localChanges === "inPlace"
            width: parent.width
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: L10n.t("historyRevertLocalInPlaceDetail")
        }
        // Why the revert sets the local changes aside and which collide.
        Column {
            visible: dialog.setAside
            width: parent.width
            spacing: Theme.space.s3
            MeridianBanner {
                width: parent.width
                tone: MeridianBanner.Info
                message: L10n.t("historyRevertSetAsideExplain")
            }
            MeridianText {
                visible: (dialog.preview.overlapCount ?? 0) > 0
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                text: L10n.tn("historyRevertSetAsideFiles", { count: dialog.preview.overlapCount ?? 0 })
            }
            MeridianSelectableText {
                visible: (dialog.preview.overlapCount ?? 0) > 0
                width: parent.width
                role: MeridianText.CodeSm
                text: (dialog.preview.overlappingPaths ?? []).concat((dialog.preview.overlapMore ?? 0) > 0
                    ? [L10n.tn("historyRevertSetAsideMore", { count: dialog.preview.overlapMore })] : []).join("\n")
            }
            MeridianText {
                visible: dialog.preview.stagedChanges === true
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                text: L10n.t("historyRevertSetAsideStaged")
            }
        }
        MeridianText {
            visible: dialog.prediction !== null && !dialog.prediction.failed
            width: parent.width
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: dialog.prediction !== null && dialog.prediction.complete ? L10n.t("conflictCheckEstimate") : L10n.t("conflictCheckPartial")
        }
        GitCommands { width: parent.width; commands: dialog.preview.commands ?? [] }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            text: dialog.kind === "revert"
                ? (dialog.setAside ? L10n.t("historyRevertSetAsideAction")
                   : dialog.preview.noCommit === true ? L10n.t("historyRevertApplyOnly") : L10n.t("historyRevertCommitNow"))
                : Commands.dialogTitle(Commands.label(dialog.kind === "merge" ? "mergeBranch" : "cherryPickSelected"))
            variant: MeridianButton.Primary
            onClicked: dialog.submitted()
        }
    ]
}
