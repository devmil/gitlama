import QtQuick

// A tab group chip's context menu.
CommandMenu {
    id: menu

    required property var tabs
    property var group: null
    signal renameRequested(var groupId)

    function showFor(groupId, item, x, y) {
        group = Store.workspace.groups.find(candidate => candidate.id === groupId) ?? null
        if (!group)
            return
        items = [
            { title: L10n.t("tabGroupRename"), value: "rename", icon: "pencil" },
            { title: L10n.t("tabGroupEdit"), value: "edit", icon: "palette" },
            { separator: true },
            { title: group.collapsed ? L10n.t("tabGroupExpandAction") : L10n.t("tabGroupCollapseAction"),
              value: "toggle", icon: group.collapsed ? "chevrons-up-down" : "chevrons-down-up" },
            { title: L10n.t("tabGroupUngroup"), value: "ungroup", icon: "unlink" },
            { separator: true },
            { title: L10n.t("tabGroupClose"), value: "close", icon: "close" },
        ]
        show(item, x, y)
    }

    onSelected: (value) => {
        const group = menu.group
        if (!group)
            return
        switch (value) {
        case "rename": menu.renameRequested(group.id); break
        case "edit": Store.actions.showTabGroupDialog(group, Store.workspace.tabs.filter(tab => tab.groupId === group.id).map(tab => menu.tabs.label(tab))); break
        case "toggle": Store.workspace.setTabGroupCollapsed(group.id, !group.collapsed); break
        case "ungroup": Store.workspace.ungroupTabs(group.id); break
        case "close": Store.workspace.closeTabGroup(group.id); break
        }
    }
}
