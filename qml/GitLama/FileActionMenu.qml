pragma ComponentBehavior: Bound
import QtQuick

// The menu of a file or folder: the shared
// catalogue (file_actions.rs) says which actions it lists, in which groups
// and with which titles; the host performs them through `run`.
CommandMenu {
    id: menu

    /// Runs (action, selection): an action name of the catalogue, and
    /// whether it applies to the multiple selection.
    property var run: null
    /// The menu's items as last built (development screenshots read them).
    property var shownItems: []

    /// A catalogue title: {key, args} (args may be titles) or {text}.
    function titleText(title) {
        if (!title)
            return ""
        if (title.text !== undefined)
            return title.text
        const values = {}
        for (const name in (title.args ?? {})) {
            const value = title.args[name]
            values[name] = value !== null && typeof value === "object" ? titleText(value) : value
        }
        return L10n.tn(title.key, values)
    }

    /// Builds the menu of `subject` ({source, path, change, tree, mode,
    /// exists, changedFolder, staged, discardable, untracked}) for `host`
    /// ({capabilities, reasons: {action: text}, inspectionReason, busy,
    /// allowStagingWhileBusy}) and opens it at `x`, `y` of `item`.
    /// `selection` is {count, staged, clean} or null.
    function showFor(subject, selection, host, item, x, y) {
        const entries = Store.workflows.fileMenu(subject, selection ?? null, host)
        const items = entries.map(entry => {
            if (entry.separator)
                return { separator: true }
            if (entry.header !== undefined)
                return { header: titleText(entry.header) }
            const title = titleText(entry.title)
            return {
                title: entry.unavailable ? title + " — " + entry.unavailable : title,
                icon: entry.icon,
                enabled: entry.enabled,
                danger: entry.danger,
                hint: entry.reason ?? "",
                value: { action: entry.action, selection: entry.selection },
            }
        })
        shownItems = items
        menu.items = items
        menu.show(item, x, y)
    }

    onSelected: value => {
        if (menu.run && value)
            menu.run(value.action, value.selection === true)
    }
}
