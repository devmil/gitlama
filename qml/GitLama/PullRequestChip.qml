pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// A branch's pull request beside its chip in History: its number, merged or open, and its checks and
// conflicts; muted when draft, merged or outdated. Tapping opens its page.
Rectangle {
    id: chip

    property var pull: ({})
    property bool onAccent: false
    readonly property bool merged: pull.state === "merged"
    readonly property bool muted: pull.draft === true || merged || pull.outdated === true
    readonly property color ink: onAccent ? Theme.colors.inkOnAccent : muted ? Theme.colors.inkMuted : Theme.colors.accentInk
    readonly property string tooltip: ["#" + pull.number + " " + pull.title]
        .concat(merged ? [L10n.t("hostingPullRequestMerged")] : [])
        .concat(pull.checks && pull.checks !== "unknown" ? [status.label(pull.checks)] : [])
        .concat(pull.mergeability === "mergeable" ? [L10n.t("hostingMergeable")]
                : pull.mergeability === "conflicting" ? [L10n.t("hostingMergeConflicting")]
                : pull.mergeability === "checking" ? [L10n.t("hostingMergeChecking")] : [])
        .concat(pull.outdated === true ? [L10n.t("hostingPullRequestOutdated")] : [])
        .join("\n")

    objectName: "history-pull-request-" + pull.number
    implicitWidth: content.implicitWidth + 2 * GitLamaLayout.refChipPaddingX
    implicitHeight: GitLamaLayout.refChipHeight
    radius: height / 2
    color: "transparent"
    border.width: 1
    border.color: onAccent ? Theme.colors.inkOnAccentMuted : Theme.colors.lineStrong
    Accessible.role: Accessible.Button
    Accessible.name: tooltip

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.space.s1
        MeridianIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: chip.merged ? "git-merge" : "git-pull-request"
            extent: GitLamaLayout.refIconSize
            color: chip.ink
        }
        MeridianText {
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.Caption
            color: chip.ink
            text: "#" + chip.pull.number
        }
        HostingStatus {
            id: status
            anchors.verticalCenter: parent.verticalCenter
            checks: chip.pull.checks ?? ""
            conflicting: chip.pull.mergeability === "conflicting"
            onAccent: chip.onAccent
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    MeridianTooltip { shown: hover.hovered; text: chip.tooltip }
    TapHandler {
        onTapped: {
            if (Store.hosting.openable(chip.pull.webUrl))
                Qt.openUrlExternally(chip.pull.webUrl)
        }
    }
}
