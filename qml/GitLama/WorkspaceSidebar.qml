pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import QtQuick.Controls.Basic as C
import Meridian

// The workspace sidebar (the Dart WorkspaceSidebar): the panes, then the
// active repository's references in sections. The rows come from Rust,
// already filtered and flattened; only the visible ones are built.
//
// The reference filter is hidden until asked for with its button or by
// typing while the sidebar has focus, and goes away once cleared.
FocusScope {
    id: sidebar

    readonly property var active: Store.workspace ? Store.workspace.active : null
    readonly property var header: Store.sidebar ? (Store.sidebar.header ?? ({})) : ({})
    readonly property bool hasRepository: header.hasRepository === true
    readonly property string pane: active ? active.pane : ""
    property bool filterOpen: false
    /// The filter field, created with the list's header.
    property MeridianTextField filterField: null
    signal command(string id, var options)

    function openFilter(initial) {
        if (initial !== undefined)
            filterField.text = initial
        filterOpen = true
        Store.sidebar.setFilter(true, filterField.text)
        Qt.callLater(() => filterField.forceActiveFocus())
    }

    function closeFilter() {
        if (!filterOpen && filterField.text.length === 0)
            return
        filterOpen = false
        filterField.text = ""
        Store.sidebar.setFilter(false, "")
    }

    // A different repository starts without a filter.
    onActiveChanged: {
        const identity = active ? active.tabId : -1
        if (identity !== _shownTab) {
            _shownTab = identity
            if (filterOpen)
                closeFilter()
        }
    }
    property int _shownTab: -1

    // Typing a character while a row has focus starts filtering with it.
    Keys.onPressed: event => {
        if (!hasRepository || !filterField || filterField.activeFocus)
            return
        const text = event.text
        if (text.length !== 1 || text.trim().length === 0 || text.charCodeAt(0) < 0x20 || text.charCodeAt(0) === 0x7f)
            return
        if (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))
            return
        openFilter(filterOpen ? filterField.text + text : text)
        event.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.colors.ground
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: Theme.space.s2
        anchors.bottomMargin: Theme.space.s2
        leftMargin: Theme.space.s3
        rightMargin: Theme.space.s3
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Store.sidebarRows
        reuseItems: true
        cacheBuffer: 400
        keyNavigationEnabled: false

        MeridianWheelScroll { flickable: list }
        C.ScrollBar.vertical: MeridianScrollBar { viewHovered: sidebar.hovered }

        header: Column {
            width: list.width - list.leftMargin - list.rightMargin

            SidebarGroupLabel {
                width: parent.width
                label: L10n.t("commandGroupCommands")
            }
            MeridianListRow {
                width: parent.width
                text: L10n.t("workspaceChanges")
                iconName: "changes"
                selected: sidebar.pane === "changes"
                enabled: sidebar.hasRepository
                onClicked: Store.sidebar.selectPane("changes")
            }
            MeridianListRow {
                width: parent.width
                text: L10n.t("workspaceHistory")
                iconName: "history"
                selected: sidebar.pane === "history"
                enabled: sidebar.hasRepository
                onClicked: Store.sidebar.selectPane("history")
            }
            SidebarGroupLabel {
                width: parent.width
                label: L10n.t("commandGroupRepository")
                MeridianIconButton {
                    objectName: "sidebar-filter-show"
                    visible: !sidebar.filterOpen && sidebar.hasRepository
                    text: L10n.t("sidebarFilterShow")
                    iconName: "search"
                    controlSize: MeridianButton.Small
                    onGround: true
                    onClicked: sidebar.openFilter()
                }
            }
            Item {
                visible: sidebar.filterOpen
                width: parent.width
                height: visible ? filterField.implicitHeight + Theme.space.s1 : 0
                MeridianTextField {
                    id: filterField
                    objectName: "sidebar-filter"
                    x: Theme.space.s2
                    y: Theme.space.s1
                    width: parent.width - 2 * Theme.space.s2
                    variant: MeridianTextField.Search
                    controlSize: MeridianButton.Small
                    placeholderText: L10n.t("sidebarFilterPlaceholder")
                    Accessible.name: L10n.t("sidebarFilterShow")
                    inputMethodHints: Qt.ImhNoPredictiveText
                    Component.onCompleted: sidebar.filterField = filterField
                    onTextEdited: Store.sidebar.setFilter(true, text)
                    Keys.onEscapePressed: sidebar.closeFilter()
                    // An empty filter goes away once focus leaves it.
                    onActiveFocusChanged: {
                        if (!activeFocus && sidebar.filterOpen && text.trim().length === 0)
                            sidebar.closeFilter()
                    }
                    MeridianIconButton {
                        objectName: "sidebar-filter-clear"
                        text: L10n.t("sidebarFilterClear")
                        iconName: "x"
                        controlSize: MeridianButton.Small
                        onClicked: sidebar.closeFilter()
                    }
                }
            }
            MeridianText {
                visible: sidebar.header.noMatches === true
                x: Theme.space.s4
                width: parent.width - 2 * Theme.space.s4
                topPadding: Theme.space.s2
                bottomPadding: Theme.space.s2
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: L10n.t("sidebarFilterNoMatches")
                wrapMode: Text.WordWrap
            }
        }

        delegate: DelegateChooser {
            role: "kind"
            DelegateChoice {
                roleValue: "section"
                SidebarSectionRow {
                    required property var model
                    width: list.width - list.leftMargin - list.rightMargin
                    row: model ?? ({})
                    hasRepository: sidebar.hasRepository
                    onToggled: {
                        if (!row.expanded && row.section === "addWorktree")
                            Store.sidebar.reloadWorktrees()
                        Store.sidebar.setExpanded(row.section, !row.expanded)
                    }
                    onCommand: id => sidebar.command(id, ({}))
                }
            }
            // Why the last worktree deletion failed.
            DelegateChoice {
                roleValue: "banner"
                Item {
                    required property var model
                    width: list.width - list.leftMargin - list.rightMargin
                    implicitHeight: banner.implicitHeight + 2 * Theme.space.s3
                    MeridianBanner {
                        id: banner
                        x: Theme.space.s3
                        y: Theme.space.s3
                        width: parent.width - 2 * Theme.space.s3
                        tone: MeridianBanner.Error
                        message: L10n.t(parent.model.name ?? "")
                    }
                }
            }
            DelegateChoice {
                roleValue: "ref"
                SidebarRefRow {
                    required property var model
                    width: list.width - list.leftMargin - list.rightMargin
                    row: model ?? ({})
                    onToggled: Store.sidebar.setExpanded(row.key, !row.expanded)
                    onCommand: (id, options) => sidebar.command(id, options)
                }
            }
        }
    }

    HoverHandler { id: sidebarHover }
    readonly property bool hovered: sidebarHover.hovered
}
