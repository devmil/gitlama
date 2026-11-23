pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// What a stash change will do: the files it
// touches, untracked and staged handling, its target branch and the Git
// commands.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var preview: ({})
    readonly property string kind: preview.kind ?? "push"
    signal answered(int id, bool confirmed)

    function ask(id, value) {
        promptId = id
        preview = value
        open()
    }

    title: L10n.t("stashPreviewTitle")
    description: ({ push: L10n.t("stashPushSummary"), apply: L10n.t("stashApplySummary"), pop: L10n.t("stashPopSummary"),
                    drop: L10n.t("stashDropSummary"), rename: L10n.t("stashRenameSummary") })[kind] ?? L10n.t("stashCheckoutSummary")
    onSubmitted: { close(); answered(promptId, true); promptId = -1 }
    onRejected: { answered(promptId, false); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6
        MeridianPropertyList {
            width: parent.width
            visible: properties.length > 0
            properties: {
                const list = []
                if ((dialog.preview.affectedPaths ?? 0) > 0)
                    list.push({ label: L10n.t("stashPreviewFiles"), value: L10n.tn("stashPreviewFileCount", { count: dialog.preview.affectedPaths }), selectable: false })
                if (dialog.preview.includesUntracked)
                    list.push({ label: L10n.t("stashPreviewNewFiles"), value: L10n.t("stashPreviewIncluded"), selectable: false })
                if (dialog.preview.keepsIndex)
                    list.push({ label: L10n.t("stashPreviewStaged"), value: L10n.t("stashPreviewStillStaged"), selectable: false })
                if (dialog.preview.targetBranch)
                    list.push({ label: L10n.t("stashTargetBranch"), value: dialog.preview.targetBranch, monospace: true })
                return list
            }
        }
        MeridianBanner {
            visible: dialog.preview.destructive === true
            width: parent.width
            tone: MeridianBanner.Warning
            message: L10n.t("stashDropWarning")
        }
        MeridianText {
            visible: ["apply", "pop", "autoStashCheckout"].indexOf(dialog.kind) >= 0
            width: parent.width
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: L10n.t("stashRecoveryRetained")
            wrapMode: Text.Wrap
        }
        GitCommands { width: parent.width; commands: dialog.preview.commands ?? [] }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            text: Commands.dialogTitle(Commands.label(({ push: "createStash", apply: "applyStash", pop: "popStash", drop: "dropStash",
                rename: "renameStash", autoStashCheckout: "autoStashCheckout" })[dialog.kind] ?? "checkoutCommit"))
            variant: dialog.preview.destructive === true ? MeridianButton.Danger : MeridianButton.Primary
            onClicked: dialog.submitted()
        }
    ]
}
