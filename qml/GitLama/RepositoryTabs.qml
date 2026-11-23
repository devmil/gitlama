pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The repository tabs in the title bar (RepositoryTabs + GitLamaRepoTabs):
// Meridian's tab strip over the workspace's tabs and groups, the window's
// drag area beside it and the button that opens another repository. A
// repository with several open worktrees is one entry; the worktree row
// unfolds under the strip while the active repository has several open.
Column {
    id: root

    readonly property var workspace: Store.workspace
    readonly property var tabs: workspace ? workspace.tabs : []
    readonly property var groups: workspace ? workspace.groups : []
    readonly property var activeTabId: workspace ? workspace.activeTabId : -1

    /// The strip id of each repository with several open worktrees: a tab's
    /// id it held, kept while the entry stands.
    property var _entryIds: ({})
    /// The worktree each such repository showed last.
    property var _lastActive: ({})
    /// The strip's entries by strip id: [tab, ...].
    property var entries: ({})
    property var stripTabs: []
    property var worktrees: []

    onTabsChanged: _rebuild()
    onActiveTabIdChanged: _rebuild()
    // A host's name, colour or icon shows in its tabs.
    readonly property var remoteHosts: Store.remote ? Store.remote.hosts : null
    onRemoteHostsChanged: _rebuild()
    Component.onCompleted: _rebuild()

    function tabById(id) {
        return tabs.find(tab => tab.id === id) ?? null
    }

    /// A tab's name: the one the user gave its repository, or its folder's.
    function label(tab) {
        if (tab.phase === "choosing")
            return L10n.t("openRepository")
        if (tab.customName)
            return tab.customName
        return tab.label.length === 0 ? L10n.t("repositoryIconNameRepository") : tab.label
    }

    /// The name of a repository with several open worktrees: its main
    /// worktree's, or the folder that holds its Git directory.
    function repositoryLabel(worktrees) {
        const main = worktrees.find(tab => tab.mainWorktree)
        if (main)
            return label(main)
        const common = worktrees[0].repositoryPath
        if (!common)
            return label(worktrees[0])
        const parts = common.split(/[\/\\]/).filter(part => part.length > 0)
        const folder = parts.length > 1 && parts[parts.length - 1] === ".git" ? parts[parts.length - 2] : (parts[parts.length - 1] ?? "")
        const name = folder.endsWith(".git") ? folder.slice(0, -4) : folder
        return name.length === 0 ? label(worktrees[0]) : name
    }

    /// A worktree row tab's name: the one the user gave it, or what it has
    /// checked out.
    function worktreeLabel(tab) {
        if (tab.customName)
            return tab.customName
        if (tab.branch)
            return tab.branch
        if (tab.headObjectId)
            return L10n.t("compassDetachedAt", [String(tab.headObjectId).slice(0, 8)])
        return label(tab)
    }

    /// The tab entries: the tabs of one repository's worktrees stand side by
    /// side and form one entry.
    function tabEntries() {
        const result = []
        for (const tab of tabs) {
            const last = result.length > 0 ? result[result.length - 1] : null
            if (tab.repositoryKey && last && last[last.length - 1].repositoryKey === tab.repositoryKey)
                last.push(tab)
            else
                result.push([tab])
        }
        return result
    }

    function _representative(entry) {
        const last = _lastActive[entry[0].repositoryKey]
        return entry.find(tab => tab.id === activeTabId) ?? entry.find(tab => tab.id === last)
            ?? entry.find(tab => tab.mainWorktree) ?? entry[0]
    }

    function _rebuild() {
        const result = {}
        const order = []
        const repositories = {}
        const entryIds = Object.assign({}, _entryIds)
        const lastActive = Object.assign({}, _lastActive)
        for (const entry of tabEntries()) {
            const repository = entry[0].repositoryKey
            if (entry.length < 2 || !repository) {
                result[entry[0].id] = entry
                order.push(entry[0].id)
                continue
            }
            repositories[repository] = true
            const members = entry.map(tab => tab.id)
            let id = entryIds[repository]
            if (id === undefined || (members.indexOf(id) < 0 && tabs.some(tab => tab.id === id)))
                id = entry[0].id
            entryIds[repository] = id
            result[id] = entry
            order.push(id)
            if (members.indexOf(activeTabId) >= 0)
                lastActive[repository] = activeTabId
        }
        for (const key in entryIds)
            if (!repositories[key])
                delete entryIds[key]
        for (const key in lastActive)
            if (!repositories[key])
                delete lastActive[key]
        _entryIds = entryIds
        _lastActive = lastActive
        entries = result
        stripTabs = order.map(id => result[id].length > 1 ? _repositoryTab(id, result[id]) : _tab(result[id][0]))
        const active = tabById(activeTabId)
        const entryOfActive = Object.values(result).find(entry => entry.some(tab => tab.id === activeTabId)) ?? []
        worktrees = active && entryOfActive.length > 1 ? entryOfActive : []
    }

    function _syncTooltip(tab) {
        return tab.hasStatus ? L10n.t("syncAheadBehind", [tab.ahead, tab.behind]) : ""
    }

    /// How a remote tab shows its host: {name, disconnected, color, icon}; null for a local
    /// tab.
    function _host(tab) {
        if (!tab.remoteProfile || tab.phase === "choosing")
            return null
        const profile = Labels.remoteHost(tab.remoteProfile)
        const color = profile && profile.color ? AppearanceColors.color(profile.color) : null
        const icon = profile && AppearanceColors.icons.indexOf(profile.icon ?? "") >= 0 ? profile.icon : null
        return { name: Labels.remoteHostName(tab.remoteProfile), disconnected: tab.remoteStale === true, color: color, icon: icon }
    }

    function _tab(tab, overrides) {
        overrides = overrides ?? ({})
        const name = overrides.label ?? label(tab)
        const host = _host(tab)
        const marked = host !== null && (host.color !== null || host.icon !== null)
        // A marked host is told by its icon; its name would crowd the label.
        const shown = host === null || marked || overrides.label !== undefined ? name
            : L10n.tn("remoteTabLabel", { repository: name, host: host.name })
        const hostNote = host === null ? "" : host.disconnected ? L10n.tn("remoteHostBadgeDisconnected", { host: host.name })
            : L10n.tn("remoteHostBadge", { host: host.name })
        const tooltip = [overrides.tooltip ?? (hostNote.length > 0 ? name + " · " + hostNote : shown), _syncTooltip(tab)]
            .filter(part => part.length > 0).join(" · ")
        const hostIcon = host !== null && tab.phase === "open"
        return {
            id: overrides.id ?? tab.id,
            label: shown,
            group: overrides.noGroup ? null : (tab.groupId ?? null),
            tooltip: tooltip,
            semanticLabel: hostNote.length > 0 ? name + ", " + hostNote : "",
            dirty: overrides.dirty ?? (tab.hasStatus && tab.changes > 0),
            // The label carries the host; renaming edits only local names.
            renamable: overrides.renamable ?? (host === null && tab.phase === "open"),
            renamePlaceholder: tab.label,
            spinner: tab.phase === "opening",
            iconName: tab.phase === "failed" ? "circle-alert"
                : hostIcon ? (host.disconnected ? "wifi-off" : host.icon ?? "server") : (overrides.iconName ?? ""),
            iconColor: tab.phase === "failed" ? Theme.colors.danger
                : hostIcon ? (host.color ?? Theme.colors.inkMuted) : (overrides.iconColor ?? Theme.colors.inkMuted),
            mark: hostIcon ? null : tab.phase === "open" || tab.phase === "failed" ? (overrides.mark ?? tab.mark) : null,
            worktreeCount: overrides.worktreeCount ?? 0,
            tabId: tab.id,
        }
    }

    /// A repository with several open worktrees: one entry, named for the
    /// repository and marked with how many worktrees its row holds.
    function _repositoryTab(id, worktrees) {
        const representative = _representative(worktrees)
        const name = repositoryLabel(worktrees)
        const main = worktrees.find(tab => tab.mainWorktree)
        return _tab(representative, {
            id: id,
            label: name,
            tooltip: L10n.t("worktreeTabsTooltip", [name, worktrees.length]),
            mark: main ? main.mark : null,
            worktreeCount: worktrees.length,
            dirty: worktrees.some(tab => tab.hasStatus && tab.changes > 0),
            renamable: false,
        })
    }

    function _group(group) {
        return {
            id: group.id,
            color: AppearanceColors.color(group.color),
            name: group.name,
            icon: group.icon ?? null,
            collapsed: group.collapsed,
            label: L10n.t("tabGroupUnnamed", [AppearanceColors.label(group.color)]),
        }
    }

    function _entryIdOf(tabId) {
        for (const key in entries)
            if (entries[key].some(tab => tab.id === tabId))
                return Number(key)
        return null
    }

    /// The tab `index` among the strip's other entries stands for, as an
    /// index among the tabs outside `moved`.
    function _tabIndexFor(others, index, moved) {
        const remaining = tabs.filter(tab => moved.indexOf(tab.id) < 0).map(tab => tab.id)
        if (index >= others.length)
            return remaining.length
        return remaining.indexOf(entries[others[index]][0].id)
    }

    function _moveEntry(id, index, group) {
        const entry = entries[id]
        if (!entry)
            return
        const leader = entry[0].id
        const ordered = stripTabs.map(tab => tab.id).filter(other => other !== id)
        workspace.moveTab(leader, _tabIndexFor(ordered, index, [leader]), group === null || group === undefined ? -1 : group)
    }

    function _moveGroup(groupId, index) {
        const members = tabs.filter(tab => tab.groupId === groupId).map(tab => tab.id)
        const others = stripTabs.filter(tab => tab.group !== groupId).map(tab => tab.id)
        workspace.moveTabGroup(groupId, _tabIndexFor(others, index, members))
    }

    // ---------------------------------------------------------------- strip

    Item {
        id: stripRow
        width: root.width
        height: Metrics.tabStripHeight

        MeridianTabStrip {
            id: strip
            objectName: "repository-tab-strip"
            x: Theme.space.s3
            height: parent.height
            width: Math.min(implicitWidth, parent.width - 2 * Theme.space.s3 - Theme.size.controlSmall)
            tabs: root.stripTabs
            groups: root.groups.map(group => root._group(group))
            activeTab: root._entryIdOf(root.activeTabId)
            renamable: true
            groupsMovable: true
            nameMaxLength: 256
            leadingDelegate: TabMark {}
            closeLabel: L10n.t("workspaceCloseTab", ["%1"])
            collapseGroupLabel: L10n.t("tabGroupCollapse", ["%1"])
            expandGroupLabel: L10n.t("tabGroupExpand", ["%1"])
            groupLabel: (name, count) => L10n.t("tabGroupSemantics", [name, count])
            renameTabLabel: L10n.t("repositoryTabRenameLabel")
            renameGroupLabel: L10n.t("tabGroupRenameLabel")
            groupNamePlaceholder: L10n.t("tabGroupNamePlaceholder")
            moveLeftLabel: L10n.t("repositoryTabMoveLeft")
            moveRightLabel: L10n.t("repositoryTabMoveRight")
            dirtyLabel: L10n.t("repositoryTabUnsaved")

            onActivated: (id) => {
                const entry = root.entries[id]
                if (entry)
                    root.workspace.activateTab(entry.length > 1 ? root._representative(entry).id : id)
            }
            onCloseRequested: (id) => {
                const entry = root.entries[id]
                if (!entry)
                    return
                if (entry.length < 2)
                    root.workspace.closeTab(id)
                else
                    root.workspace.closeTabs(entry.map(tab => tab.id))
            }
            onMoveRequested: (id, index, group) => root._moveEntry(id, index, group)
            onGroupMoveRequested: (group, index) => root._moveGroup(group, index)
            onContextMenuRequested: (id, x, y) => {
                const entry = root.entries[id]
                if (entry)
                    tabMenu.showFor(entry.length > 1 ? root._representative(entry).id : id, strip, x, y)
            }
            onRenamed: (id, name) => root.workspace.renameTab(id, name)
            onGroupToggled: (group) => {
                const found = root.groups.find(candidate => candidate.id === group)
                if (found)
                    root.workspace.setTabGroupCollapsed(group, !found.collapsed)
            }
            onGroupContextMenuRequested: (group, x, y) => groupMenu.showFor(group, strip, x, y)
            onGroupRenamed: (group, name) => root.workspace.renameTabGroup(group, name)
        }

        WindowDragArea {
            objectName: "repository-titlebar-tab-gap"
            x: strip.x + strip.width
            width: openButton.x - x
            height: parent.height
        }

        MeridianIconButton {
            id: openButton
            objectName: "repository-open-tab"
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s3
            anchors.verticalCenter: parent.verticalCenter
            text: L10n.t("workspaceOpenAnother")
            iconName: "plus"
            controlSize: MeridianButton.Small
            onGround: true
            onClicked: root.workspace.addRepositoryChooser()
        }
    }

    Connections {
        target: root.workspace
        function onGroupCreated(group) {
            strip.renameGroup(group)
        }
    }

    // The row unfolds under the strip while the active repository has
    // several worktrees open, and folds away with the last but one.
    MeridianReveal {
        width: root.width
        shown: root.worktrees.length > 1
        WorktreeRow {
            implicitWidth: root.width
            worktrees: root.worktrees
            tabs: root
        }
    }

    TabContextMenu {
        id: tabMenu
        tabs: root
        onRenameRequested: (tabId) => {
            if (root.worktrees.some(tab => tab.id === tabId))
                Qt.callLater(() => root.renameWorktree(tabId))
            else
                strip.renameTab(root._entryIdOf(tabId))
        }
    }

    GroupContextMenu {
        id: groupMenu
        tabs: root
        onRenameRequested: (group) => strip.renameGroup(group)
    }

    function showTabMenu(tabId, item, x, y) {
        tabMenu.showFor(tabId, item, x, y)
    }

    signal renameWorktreeRequested(var tabId)
    function renameWorktree(tabId) {
        renameWorktreeRequested(tabId)
    }
}
