pragma ComponentBehavior: Bound
import QtQuick

// The registry's keyboard shortcuts as window shortcuts (the Flutter
// shell's CallbackShortcuts). A command runs through the same policy as its
// menu item. Pane-scoped commands listen while their pane is shown; the
// sidebar and the commit editor bind their own keys. Text fields keep the
// printable keys they type.
Item {
    id: root

    readonly property var active: Store.workspace ? Store.workspace.active : null
    readonly property string pane: active ? active.pane : ""
    // Bound where they act: sidebar rows, the commit editor, the resolver.
    readonly property var ownedElsewhere: ["commitCreate"]

    function scopeActive(scopes) {
        for (const scope of scopes) {
            if (scope === "global")
                return true
            if (scope === "changes" && pane === "changes")
                return true
            if ((scope === "history" || scope === "diff") && (pane === "history" || pane === "changes"))
                return true
        }
        return false
    }

    Repeater {
        model: Commands.registry.filter(command => command.shortcut && root.ownedElsewhere.indexOf(command.id) < 0)
        delegate: Item {
            id: binding
            required property var modelData
            Shortcut {
                sequences: [Commands.sequence(binding.modelData.id)]
                enabled: Commands.sequence(binding.modelData.id).length > 0 && root.scopeActive(binding.modelData.scopes)
                context: Qt.WindowShortcut
                onActivated: Store.actions.runCommand(binding.modelData.id, ({}))
            }
        }
    }
}
