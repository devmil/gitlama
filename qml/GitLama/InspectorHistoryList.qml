pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The history lens's commits (the Dart InspectorHistoryList): the path's
// (or the selected lines') commits, newest first; selecting one shows its
// change, a double click inspects that commit, and older pages load on
// demand.
Item {
    id: root

    property var bridge: Store.inspector

    property var paneState: ({})
    readonly property var location: paneState.location ?? null
    readonly property var history: paneState.history ?? null
    readonly property var entries: history ? (history.entries ?? []) : []
    readonly property var lines: location ? location.lines : null

    MeridianSectionHeader {
        id: listHeader
        width: parent.width
        title: L10n.t("inspectorLensHistory")
        count: root.history ? root.entries.length : -1
        MeridianChip {
            visible: root.lines !== null && root.lines !== undefined
            text: root.lines ? L10n.tn("inspectorLines", { first: root.lines[0], last: root.lines[1] }) : ""
            removable: true
            removeLabel: L10n.t("inspectorClearLines")
            onRemoveRequested: root.bridge.up()
        }
    }
    MeridianEmptyState {
        visible: root.history === null || root.entries.length === 0
        anchors.top: listHeader.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        compact: true
        progress: root.history === null
        title: root.history === null ? L10n.t("loading") : L10n.t("inspectorNoHistory")
    }
    ListView {
        id: list
        objectName: "inspector-history"
        Accessible.role: Accessible.List
        Accessible.name: root.location && root.location.path ? L10n.tn("inspectorHistoryOf", { path: root.location.path }) : ""
        visible: root.entries.length > 0
        anchors.top: listHeader.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        leftMargin: Theme.space.s2
        rightMargin: Theme.space.s2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.entries
        MeridianWheelScroll { flickable: list }
        C.ScrollBar.vertical: MeridianScrollBar {}
        onAtYEndChanged: if (atYEnd && root.history && root.history.hasMore && !root.history.loadingMore && !root.history.moreFailed) root.bridge.loadMoreHistory()
        footer: MeridianListRow {
            visible: root.history !== null && root.history.hasMore === true && root.lines === null
            height: visible ? implicitHeight : 0
            width: list.width - list.leftMargin - list.rightMargin
            text: root.history && root.history.moreFailed ? L10n.t("retry") : L10n.t("inspectorLoadOlder")
            iconName: root.history && root.history.moreFailed ? "rotate-ccw" : "history"
            onClicked: root.bridge.loadMoreHistory()
        }
        delegate: MeridianListRow {
            id: entryRow
            required property var modelData
            width: list.width - list.leftMargin - list.rightMargin
            twoLine: true
            iconName: "history"
            text: modelData.summary
            subtitle: [modelData.author, Qt.formatDate(new Date(modelData.authorTime * 1000), Qt.locale().dateFormat(Locale.ShortFormat)),
                       modelData.oldPath ? L10n.tn("historyRenamedFrom", { path: modelData.oldPath }) : ""].filter(part => part.length > 0).join(" · ")
            selected: root.location !== null && root.location.historyCommit === modelData.commit
            trailing: Component {
                MeridianText {
                    role: MeridianText.CodeSm
                    color: Theme.colors.inkMuted
                    text: Labels.shortObjectId(entryRow.modelData.commit)
                }
            }
            onClicked: root.bridge.selectHistoryEntry(modelData.commit)
            TapHandler { onDoubleTapped: root.bridge.showCommit(entryRow.modelData.commit) }
        }
    }
}
