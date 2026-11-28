import QtQuick
import Meridian

// The status bar under the workspace (StatusBar): the brand mark (About),
// the remote host, the branch, the status message and the working tree
// state.
MeridianStatusBar {
    id: bar

    readonly property var active: Store.workspace ? Store.workspace.active : null
    property Component host: null
    property Component trailingItem: null

    readonly property string fallback: !active ? L10n.t("workspaceStatusLoading")
        : active.phase === "choosing" ? L10n.t("openRepository")
        : active.phase === "open" ? L10n.t("workspaceStatusReady")
        : active.phase === "failed" ? L10n.t("workspaceStatusFailed")
        : L10n.t("workspaceStatusLoading")

    Item {
        width: bar.width - trailingRow.width - 2 * Theme.space.s3 - Theme.space.s5
        height: Metrics.statusBarHeight
        Row {
            id: leadingRow
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            BrandSignature {
                anchors.verticalCenter: parent.verticalCenter
                onActivated: Store.actions.showAbout()
            }
            Item { width: Theme.space.s3; height: 1 }
            Loader {
                active: bar.host !== null
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                width: active && item ? Math.min((item as Item).implicitWidth, GitLamaLayout.remoteHostBadgeMaxWidth) : 0
                sourceComponent: bar.host
            }
            Item { visible: bar.host !== null; width: Theme.space.s5; height: 1 }
            MeridianStatusBarText {
                id: branchItem
                visible: bar.active !== null && !!bar.active.branch && bar.active.hasStatus
                anchors.verticalCenter: parent.verticalCenter
                iconName: "branch"
                text: visible ? bar.active.branch : ""
                maxWidth: GitLamaLayout.statusBranchMaxWidth
            }
            Item { visible: branchItem.visible; width: Theme.space.s5; height: 1 }
        }
        StatusNotificationText {
            anchors.verticalCenter: parent.verticalCenter
            x: leadingRow.width
            width: parent.width - x
            fallback: bar.fallback
        }
    }

    trailing: Row {
        id: trailingRow
        spacing: Theme.space.s5
        MeridianText {
            visible: bar.active !== null && bar.active.hasStatus === true
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            tabular: true
            text: !visible ? ""
                : (bar.active.workingTree === "clean" ? L10n.t("workspaceWorkingTreeClean")
                   : bar.active.workingTree === "conflicted" ? L10n.t("workspaceWorkingTreeConflicted")
                   : L10n.t("workspaceWorkingTreeDirty")) + " · " + bar.active.dirty
        }
        Loader {
            active: bar.trailingItem !== null
            visible: active
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: bar.trailingItem
        }
    }
}
