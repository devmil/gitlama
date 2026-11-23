pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// A repository tab's context menu: open its folder, copy its path, rename,
// icon, groups and close.
CommandMenu {
    id: menu

    required property var tabs
    property var tab: null
    signal renameRequested(var tabId)

    function showFor(tabId, item, x, y) {
        tab = tabs.tabById(tabId)
        if (!tab)
            return
        items = _items()
        show(item, x, y)
    }

    function _items() {
        const tab = menu.tab
        const remote = tab.remote === true
        const otherGroups = Store.workspace.groups.filter(group => group.id !== tab.groupId)
        const entry = Object.values(tabs.entries).find(candidate => candidate.some(member => member.id === tab.id)) ?? [tab]
        const label = tabs.label(tab)
        const result = [
            { title: L10n.t("openInFileBrowser", [Labels.fileBrowserName()]), value: "openFolder", icon: "folder-open",
              enabled: !!tab.path && !remote },
            { title: L10n.t("repositoryCopyPath"), value: "copyPath", icon: "copy", enabled: !!tab.path },
            { separator: true },
            { title: L10n.t("repositoryTabRename"), value: "rename", icon: "pencil", enabled: !!tab.path && tab.phase === "open" },
        ]
        if (tab.hasCustomName)
            result.push({ title: L10n.t("repositoryTabResetName"), value: "resetName", icon: "rotate-ccw" })
        result.push({ title: L10n.t("repositoryTabChangeIcon"), value: "changeIcon", icon: "image", enabled: !!tab.path })
        result.push({ title: L10n.t("repositoryTabRemoveIcon"), value: "removeIcon", icon: "eraser", enabled: tab.hasMark === true })
        result.push({ separator: true })
        if (otherGroups.length === 0) {
            result.push({ title: L10n.t("tabGroupAddToNew"), value: "newGroup", icon: "folder-plus" })
        } else {
            result.push({ title: L10n.t("tabGroupAddTo"), icon: "folder-plus", children: [
                { title: L10n.t("tabGroupNew"), value: "newGroup", icon: "plus" },
                { separator: true },
            ].concat(otherGroups.map(group => ({
                title: group.name.length > 0 ? group.name : L10n.t("tabGroupUnnamed", [AppearanceColors.label(group.color)]),
                value: "join:" + group.id,
            }))) })
        }
        if (tab.groupId !== null && tab.groupId !== undefined)
            result.push({ title: L10n.t("tabGroupRemoveTab"), value: "leaveGroup", icon: "circle-minus" })
        result.push({ separator: true })
        result.push({ title: L10n.t("workspaceCloseTab", [entry.length > 1 ? tabs.worktreeLabel(tab) : label]), value: "close", icon: "close" })
        if (entry.length > 1)
            result.push({ title: L10n.t("worktreeCloseAll", [entry.length]), value: "closeAll", icon: "close" })
        return result
    }

    onSelected: (value) => {
        const tab = menu.tab
        if (!tab)
            return
        const entry = Object.values(tabs.entries).find(candidate => candidate.some(member => member.id === tab.id)) ?? [tab]
        if (value === "openFolder") {
            Store.actions.openFolder(tab.path)
        } else if (value === "copyPath") {
            Store.actions.copyText(tab.path, L10n.t("repositoryPathCopied"))
        } else if (value === "rename") {
            if (entry.length > 1 && Store.workspace.activeTabId !== tab.id)
                Store.workspace.activateTab(tab.id)
            menu.renameRequested(tab.id)
        } else if (value === "resetName") {
            Store.workspace.renameTab(tab.id, "")
        } else if (value === "changeIcon") {
            Store.actions.showRepositoryIconDialog(tab)
        } else if (value === "removeIcon") {
            Store.workspace.removeTabIcon(tab.id)
        } else if (value === "newGroup") {
            Store.workspace.createTabGroup(tab.id)
        } else if (String(value).startsWith("join:")) {
            Store.workspace.addTabToGroup(tab.id, Number(String(value).slice(5)))
        } else if (value === "leaveGroup") {
            Store.workspace.removeTabFromGroup(tab.id)
        } else if (value === "close") {
            Store.workspace.closeTab(tab.id)
        } else if (value === "closeAll") {
            Store.workspace.closeTabs(entry.map(member => member.id))
        }
    }
}
