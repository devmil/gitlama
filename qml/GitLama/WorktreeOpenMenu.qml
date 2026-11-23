import QtQuick
import Meridian

// The worktree row's open menu (the Dart _showWorktreeMenu): the
// repository's worktrees that are not open, then Add worktree. It opens
// once the worktrees are listed; a failed listing says so instead.
CommandMenu {
    id: menu

    property Item anchorItem: null
    property real anchorX: 0
    property real anchorY: 0
    property bool waiting: false

    function showAt(item, x, y) {
        anchorItem = item
        anchorX = x
        anchorY = y
        waiting = true
        Store.workflows.worktreeMenu()
    }

    Connections {
        target: Store.workflows
        function onWorktreeMenuReady(rows) {
            if (!menu.waiting)
                return
            menu.waiting = false
            if (rows === null) {
                Notifications.show(L10n.t("worktreeListFailed"), true)
                return
            }
            const items = rows.length === 0
                ? [{ title: L10n.t("worktreeAllOpen"), value: "", enabled: false }]
                : rows.map((row, index) => ({ title: row.label, value: index, icon: row.icon }))
            menu.items = items.concat([{ separator: true },
                { title: L10n.t("commandAddWorktree"), value: "add", icon: "plus" }])
            menu.show(menu.anchorItem, menu.anchorX, menu.anchorY)
        }
    }

    onSelected: (value) => {
        if (value === "add")
            Store.actions.runCommand("addWorktree", {})
        else if (typeof value === "number")
            Store.workflows.openMenuWorktree(value)
    }
}
