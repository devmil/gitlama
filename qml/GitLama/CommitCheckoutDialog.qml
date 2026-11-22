import QtQuick
import Meridian

// Checking out a commit (detached HEAD). A dirty tree must stash first:
// keep the changes in a stash, or stash and reapply them after.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var review: ({})
    readonly property bool dirty: review.dirty === true
    signal answered(int id, var choice)

    function ask(id, value) {
        promptId = id
        review = value
        open()
    }
    function choose(choice) {
        close()
        answered(promptId, choice)
        promptId = -1
    }

    title: Commands.dialogTitle(L10n.t("commandCheckoutCommit"))
    description: L10n.tn("refConfirmCheckoutCommit", { target: (review.target ?? "").substring(0, 10) })
    onSubmitted: if (!dialog.dirty) choose("checkout")
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s4
        MeridianBanner {
            visible: dialog.dirty
            width: parent.width
            tone: MeridianBanner.Warning
            message: L10n.t("commitCheckoutDirtyHelp")
        }
        MeridianText {
            visible: dialog.dirty
            width: parent.width
            text: L10n.t("commitCheckoutStashHelp")
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
        }
        MeridianText {
            visible: dialog.dirty
            width: parent.width
            text: L10n.t("commitCheckoutReapplyHelp")
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
        }
        GitCommands { width: parent.width; commands: ["git " + (dialog.review.arguments ?? []).join(" ")] }
    }
    actions: [
        MeridianButton { text: L10n.t("commitCheckoutDismiss"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            visible: dialog.dirty && !!dialog.review.stash
            text: L10n.t("commitCheckoutStash")
            onClicked: dialog.choose("stash")
        },
        MeridianButton {
            visible: dialog.dirty && !!dialog.review.stashAndReapply
            text: L10n.t("commitCheckoutStashAndReapply")
            variant: MeridianButton.Primary
            onClicked: dialog.choose("stashAndReapply")
        },
        MeridianButton {
            visible: !dialog.dirty
            text: L10n.t("commitCheckoutAction")
            variant: MeridianButton.Primary
            onClicked: dialog.choose("checkout")
        }
    ]
}
