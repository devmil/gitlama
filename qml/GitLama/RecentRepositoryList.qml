pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The recent repositories under a filter field: rows whose name or location
// contains every typed word. Enter opens the first one shown.
Item {
    id: list

    property var recents: []
    property bool busy: false
    signal open(var recent)

    readonly property string query: filter.text.trim()
    readonly property var shown: recents.filter(recent => Labels.recentMatches(query, Labels.recentSearchText(recent)))

    implicitHeight: filterRow.height + Theme.space.s3 + (shown.length === 0 ? noMatch.implicitHeight : rows.implicitHeight) + Theme.space.s3

    Item {
        id: filterRow
        width: parent.width
        height: filter.implicitHeight
        MeridianTextField {
            id: filter
            objectName: "recent-repositories-filter"
            x: Theme.space.s4
            width: parent.width - 2 * Theme.space.s4
            variant: MeridianTextField.Search
            placeholderText: L10n.t("recentRepositoriesFilter")
            clearLabel: L10n.t("searchClear")
            inputMethodHints: Qt.ImhNoPredictiveText
            Accessible.name: L10n.t("recentRepositoriesFilter")
            onAccepted: {
                if (list.shown.length > 0 && !list.busy)
                    list.open(list.shown[0])
            }
        }
    }

    MeridianText {
        id: noMatch
        visible: list.shown.length === 0
        y: filterRow.height + Theme.space.s3
        x: Theme.space.s4
        width: parent.width - 2 * Theme.space.s4
        color: Theme.colors.inkMuted
        text: L10n.t("recentRepositoriesNoMatch")
    }

    Column {
        id: rows
        y: filterRow.height + Theme.space.s3
        visible: list.shown.length > 0
        width: parent.width
        Repeater {
            model: list.shown
            MeridianListRow {
                required property var modelData
                width: rows.width
                iconName: modelData.remote ? "server" : "folder-closed"
                text: modelData.remote ? Labels.remoteRecentName(modelData) : modelData.name
                subtitle: modelData.remote ? Labels.remoteRecentSubtitle(modelData) : modelData.path
                match: list.query
                enabled: !list.busy
                onClicked: list.open(modelData)
            }
        }
    }
}
