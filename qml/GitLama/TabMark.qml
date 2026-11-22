import QtQuick
import Meridian

// The leading mark of a repository tab, created by the tab strip inside a
// Loader that carries `tab`: the repository's icon, and for a repository
// with several open worktrees the fork mark and their count.
Row {
    id: mark

    readonly property var tab: parent ? parent.tab : null
    spacing: Theme.space.s2
    visible: tab !== null && (tab.mark || tab.worktreeCount > 1)

    RepositoryIcon {
        anchors.verticalCenter: parent.verticalCenter
        mark: mark.tab ? (mark.tab.mark ?? null) : null
    }
    MeridianIcon {
        visible: mark.tab !== null && mark.tab.worktreeCount > 1
        anchors.verticalCenter: parent.verticalCenter
        name: "git-fork"
        iconSize: MeridianIcon.Small
        color: Theme.colors.inkMuted
    }
    MeridianCount {
        visible: mark.tab !== null && mark.tab.worktreeCount > 1
        anchors.verticalCenter: parent.verticalCenter
        label: mark.tab ? String(mark.tab.worktreeCount) : ""
        tone: MeridianCount.Quiet
    }
}
