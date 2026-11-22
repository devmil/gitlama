import QtQuick
import Meridian

// The worktree row's open menu: the repository's worktrees that are not
// open, and Add worktree.
CommandMenu {
    id: menu

    function showAt(item, x, y) {
        // The inventory comes from the extensions family (ported with the
        // extensions panel); until it is loaded only Add is offered.
        items = [
            { title: L10n.t("worktreeAllOpen"), value: "", enabled: false },
            { separator: true },
            { title: L10n.t("commandAddWorktree"), value: "add", icon: "plus" },
        ]
        show(item, x, y)
    }

    onSelected: (value) => {
        if (value === "add")
            Store.actions.runCommand("addWorktree", {})
    }
}
