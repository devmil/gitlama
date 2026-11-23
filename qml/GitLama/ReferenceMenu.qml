pragma Singleton
import QtQuick

// The context menu of one branch, tag, stash or remote wherever it is shown: graph-filter actions first, then the
// entry's own actions and its commands, then copying its name. Destructive
// items come last, behind a separator. Values are functions to call.
QtObject {
    /// `entry`: {name, commandName, target, filterReference, filterUpstream,
    /// commands, current}; `actions`: extra [{title, enabled, danger, run}];
    /// `onCommand(id, options)` runs a command.
    function items(entry, actions, onCommand) {
        const name = entry.commandName || entry.name
        const reference = entry.filterReference ?? null
        const context = { reference: reference, target: entry.target ?? null, current: entry.current === true, contextual: true }
        const reasonOf = id => Commands.reason(id, Store.actions ? Store.actions.availability : ({}), context)
        const run = id => {
            if (reasonOf(id).length > 0)
                return
            onCommand(id, {
                initialName: id === "createBranch" || id === "createTag" ? null : name,
                initialTarget: entry.target ?? null,
                initialReference: reference,
            })
        }
        const safe = []
        const dangerous = []
        const filter = Store.workspace && Store.workspace.active ? (Store.workspace.active.branchFilter ?? []) : []
        if (reference !== null && BranchFilters.isFilterable(reference)) {
            for (const action of BranchFilters.menuActions(filter, reference, entry.filterUpstream ?? null)) {
                const next = action.filter
                safe.push({ title: action.title, icon: "list-filter", value: () => Store.sidebar.setBranchFilter(next) })
            }
        }
        if (safe.length > 0)
            safe.push({ separator: true })
        for (const action of actions ?? []) {
            const item = {
                title: action.title,
                enabled: action.enabled !== false,
                danger: action.danger === true,
                value: () => { if (action.enabled !== false) action.run() },
            }
            if (item.danger)
                dangerous.push(item)
            else
                safe.push(item)
        }
        for (const item of CommandMenus.commandItems(entry.commands ?? [], reasonOf)) {
            if (item.separator)
                continue
            const id = item.value
            const wrapped = Object.assign({}, item, { value: () => run(id) })
            if (item.danger)
                dangerous.push(wrapped)
            else
                safe.push(wrapped)
        }
        if (safe.length > 0 && safe[safe.length - 1].separator !== true)
            safe.push({ separator: true })
        safe.push({
            title: L10n.t("sidebarCopyName"),
            icon: "copy",
            value: () => Store.actions.copyText(name, L10n.t("menuNameCopied")),
        })
        if (dangerous.length > 0)
            return safe.concat([{ separator: true }], dangerous)
        return safe
    }
}
