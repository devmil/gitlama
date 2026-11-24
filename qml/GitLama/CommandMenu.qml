pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// A menu built from data, shown with the platform's own menu UI. `items` are
// {title, value, icon, shortcut, enabled, checked, danger, reason} entries,
// {separator: true}, {header: title} or {title, children: [...]}.
// Selecting an available item emits `selected(value)`.
MeridianMenu {
    id: menu

    property var items: []
    signal selected(var value)

    // On Linux/Wayland Qt's Popup.Native falls back to an xdg_popup window that
    // drops the (x, y) offset and snaps to parentItem's (0, 0); Popup.Item renders
    // the same Meridian menu at the exact pointer coordinates. macOS/Windows keep
    // native menus.
    nativeMenu: Qt.platform.os !== "linux"

    /// Rebuilds the menu from `items` and opens it at `x`, `y` of `parentItem`.
    function show(parentItem, x, y) {
        build()
        if (parentItem)
            menu.parent = parentItem
        menu.popup(parentItem, x ?? 0, y ?? 0)
    }

    function build() {
        _fill(menu, items)
    }

    // Created items are untyped; their triggered signal is reached dynamically.
    function _connectTriggered(item, value) {
        item.triggered.connect(() => menu.selected(value))
    }

    function _fill(target, entries) {
        while (target.count > 0)
            target.takeItem(0).destroy()
        while (target.menuAt(0) !== null)
            target.takeMenu(0).destroy()
        for (const entry of entries) {
            if (entry.separator) {
                target.addItem(separatorComponent.createObject(null))
            } else if (entry.header !== undefined) {
                target.addItem(headerComponent.createObject(null, { text: entry.header }))
            } else if (entry.children) {
                const submenu = submenuComponent.createObject(null, { title: entry.title })
                _fill(submenu, entry.children)
                target.addMenu(submenu)
            } else {
                const item = itemComponent.createObject(null, {
                    text: entry.title,
                    iconName: entry.icon ?? "",
                    shortcut: entry.shortcut ?? "",
                    hint: entry.hint ?? "",
                    danger: entry.danger === true,
                    checkable: entry.checked !== undefined,
                    checked: entry.checked === true,
                    enabled: entry.enabled !== false,
                })
                const value = entry.value
                menu._connectTriggered(item, value)
                target.addItem(item)
            }
        }
    }

    Component { id: itemComponent; MeridianMenuItem {} }
    Component { id: separatorComponent; MeridianMenuSeparator {} }
    Component { id: headerComponent; MeridianMenuHeader {} }
    Component { id: submenuComponent; MeridianMenu { nativeMenu: Qt.platform.os !== "linux" } }
}
