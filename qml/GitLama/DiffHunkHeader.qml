import QtQuick
import Meridian

// A hunk's header (the Dart _HunkCell): its range, then the code it is in,
// Show more lines, and on a working diff the hunk's Discard and Stage (or
// Unstage) buttons. The diff's row and the header pinned above a scrolled
// diff both draw it.
Item {
    id: header

    /// The DiffView it belongs to (seen dynamically: the view contains it).
    required property var diff
    property string stableId
    property string range
    property string text

    readonly property bool actions: diff.hunkActions && stableId.length > 0

    implicitHeight: GitLamaLayout.hunkHeaderHeight

    Row {
        x: Theme.space.s5
        width: parent.width - x - Theme.space.s3
        height: parent.height
        spacing: Theme.space.s4

        MeridianText {
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.CodeSm
            text: header.range
            color: Theme.colors.inkMuted
        }
        MeridianText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - x - trailing.width - parent.spacing)
            role: MeridianText.CodeSm
            text: header.text
            elide: Text.ElideRight
        }
        Row {
            id: trailing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s2

            MeridianIconButton {
                visible: header.diff.canShowMoreContext
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t("diffShowMoreLines")
                iconName: "chevrons-down-up"
                controlSize: MeridianButton.Small
                onClicked: header.diff.showMoreContext()
            }
            MeridianButton {
                objectName: "discard-hunk"
                visible: header.actions && header.diff.canDiscardHunks
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t("discardHunk")
                iconName: "undo"
                variant: MeridianButton.DangerQuiet
                controlSize: MeridianButton.Small
                enabled: header.diff.hunkActionsEnabled
                onClicked: header.diff.discardHunk(header.stableId)
            }
            MeridianButton {
                objectName: "stage-hunk"
                visible: header.actions
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t(header.diff.hunkStagedSide ? "unstageHunk" : "stageHunk")
                iconName: header.diff.hunkStagedSide ? "unstage-all" : "stage-all"
                controlSize: MeridianButton.Small
                enabled: header.diff.hunkActionsEnabled && header.diff.hunkStageDisabledReason.length === 0
                disabledReason: header.diff.hunkStageDisabledReason
                onClicked: header.diff.stageHunk(header.stableId)
            }
        }
    }
}
