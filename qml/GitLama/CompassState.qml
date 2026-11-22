import QtQuick
import Meridian

// The Compass's repository state: conflicts, changed files and sync.
Row {
    id: root

    property int ahead: 0
    property int behind: 0
    property int dirty: 0
    property int conflicts: 0
    property bool showConflictCount: false
    property bool dirtyPopIn: false

    MeridianReveal {
        anchors.verticalCenter: parent.verticalCenter
        axis: MeridianReveal.Horizontal
        shown: root.showConflictCount
        Row {
            MeridianCount {
                label: L10n.t("compassConflicts", [root.conflicts])
                tone: MeridianCount.Attention
            }
            Item { width: Theme.space.s4; height: 1 }
        }
    }
    Row {
        visible: root.dirty > 0
        anchors.verticalCenter: parent.verticalCenter
        DirtyCount {
            dirty: root.dirty
            popIn: root.dirtyPopIn
            anchors.verticalCenter: parent.verticalCenter
        }
        Item { width: Theme.space.s4; height: 1 }
    }
    SyncBadge {
        anchors.verticalCenter: parent.verticalCenter
        ahead: root.ahead
        behind: root.behind
        showZero: true
    }
}
