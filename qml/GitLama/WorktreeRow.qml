pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The open worktrees of the active tab's repository, under the strip: the
// fork mark in the colour of the entry's group, the worktrees as tabs, and
// the button that opens another worktree.
Item {
    id: row

    property var worktrees: []
    required property var tabs

    implicitHeight: Metrics.tabStripHeight
    readonly property var group: worktrees.length > 0 && worktrees[0].groupId !== null && worktrees[0].groupId !== undefined
        ? (Store.workspace.groups.find(group => group.id === worktrees[0].groupId) ?? null) : null
    readonly property string rowLabel: worktrees.length > 0 ? L10n.t("worktreeRowLabel", [row.tabs.repositoryLabel(worktrees)]) : ""

    Rectangle {
        anchors.fill: parent
        color: Theme.colors.ground
    }

    Item {
        id: fork
        x: Theme.space.s3
        width: Theme.size.iconSmall + 2 * Theme.space.s3
        height: parent.height
        Accessible.role: Accessible.StaticText
        Accessible.name: row.rowLabel
        MeridianIcon {
            anchors.centerIn: parent
            name: "git-fork"
            iconSize: MeridianIcon.Small
            color: row.group ? AppearanceColors.color(row.group.color) : Theme.colors.inkMuted
        }
        HoverHandler { id: forkHover }
        MeridianTooltip { shown: forkHover.hovered; text: row.rowLabel }
    }

    MeridianTabStrip {
        id: strip
        objectName: "repository-worktree-strip"
        x: fork.x + fork.width
        height: parent.height
        width: Math.min(implicitWidth, Math.max(0, openButton.x - x))
        renamable: true
        nameMaxLength: 256
        tabs: row.worktrees.map(tab => ({
            id: tab.id,
            label: row.tabs.worktreeLabel(tab),
            tooltip: [row.tabs.worktreeLabel(tab), tab.mainWorktree ? L10n.t("worktreeMainTab") : "", tab.path ?? ""]
                .filter(part => part.length > 0).join(" · "),
            dirty: tab.hasStatus && tab.changes > 0,
            renamable: tab.phase === "open",
            renamePlaceholder: tab.label,
            iconName: tab.mainWorktree ? "house" : "git-branch",
            iconColor: Theme.colors.inkMuted,
            spinner: tab.phase === "opening",
        }))
        activeTab: Store.workspace.activeTabId
        closeLabel: L10n.t("workspaceCloseTab", ["%1"])
        renameTabLabel: L10n.t("repositoryTabRenameLabel")
        moveLeftLabel: L10n.t("repositoryTabMoveLeft")
        moveRightLabel: L10n.t("repositoryTabMoveRight")
        dirtyLabel: L10n.t("repositoryTabUnsaved")
        onActivated: (id) => Store.workspace.activateTab(id)
        onCloseRequested: (id) => Store.workspace.closeTab(id)
        onMoveRequested: (id, index) => Store.workspace.moveWorktreeTab(id, index)
        onContextMenuRequested: (id, x, y) => row.tabs.showTabMenu(id, row, strip.x + x, strip.y + y)
        onRenamed: (id, name) => Store.workspace.renameTab(id, name)
    }

    Connections {
        target: row.tabs
        function onRenameWorktreeRequested(tabId) {
            strip.renameTab(tabId)
        }
    }

    WindowDragArea {
        x: strip.x + strip.width
        width: openButton.x - x
        height: parent.height
    }

    MeridianIconButton {
        id: openButton
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.s3
        anchors.verticalCenter: parent.verticalCenter
        text: L10n.t("worktreeOpen")
        iconName: "folder-git-2"
        controlSize: MeridianButton.Small
        onGround: true
        onClicked: worktreeMenu.showAt(openButton, 0, openButton.height)
    }

    WorktreeOpenMenu { id: worktreeMenu }
}
