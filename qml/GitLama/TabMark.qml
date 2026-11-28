import QtQuick
import Meridian

// The leading mark of a repository tab, created by the tab strip inside a
// Loader that carries `tab`: the repository's icon, and for a repository
// with several open worktrees the fork mark and their count.
Row {
    id: tabMark

    readonly property var host: parent
    readonly property var tab: host ? host.tab ?? null : null
    spacing: Theme.space.s2
    visible: tab !== null && (tab.mark || tab.worktreeCount > 1)

    RepositoryIcon {
        anchors.verticalCenter: parent.verticalCenter
        mark: tabMark.tab ? (tabMark.tab.mark ?? null) : null
    }
    MeridianIcon {
        visible: tabMark.tab !== null && tabMark.tab.worktreeCount > 1
        anchors.verticalCenter: parent.verticalCenter
        name: "git-fork"
        iconSize: MeridianIcon.Small
        color: Theme.colors.inkMuted
    }
    MeridianCount {
        visible: tabMark.tab !== null && tabMark.tab.worktreeCount > 1
        anchors.verticalCenter: parent.verticalCenter
        label: tabMark.tab ? String(tabMark.tab.worktreeCount) : ""
        tone: MeridianCount.Quiet
    }
}
