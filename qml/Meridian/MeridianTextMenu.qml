pragma ComponentBehavior: Bound
import QtQuick

// The text editing menu of a field or selectable text (Flutter:
// MeridianTextMenuRequest with the native text menu builder): Cut, Copy,
// Paste and Select All, each only when it applies, in the platform's own
// menu. Put one inside a text control and set `target`; a secondary click
// opens it at the pointer, and `openAtCursor()` (the Menu key, Shift+F10)
// opens it at the cursor. It never takes focus, so the field keeps its
// selection. Labels come from `Theme.textMenuLabels` for localization.
Item {
    id: textMenu

    /// The TextInput or TextEdit (a T.TextField, T.TextArea or TextEdit).
    property Item target: parent
    /// The target seen dynamically: text controls share no common type.
    readonly property var field: target
    /// Read-only text offers Copy and Select All only.
    property bool readOnly: field ? field.readOnly === true : true
    readonly property bool opened: menu.opened

    /// The actions that apply now, in menu order.
    function actions() {
        const field = textMenu.field
        if (!field)
            return []
        const selected = field.selectedText.length > 0
        // A password field never copies or cuts.
        const secret = field.echoMode !== undefined && field.echoMode !== TextInput.Normal
        const result = []
        if (!textMenu.readOnly && selected && !secret)
            result.push("cut")
        if (selected && !secret)
            result.push("copy")
        if (!textMenu.readOnly && field.canPaste)
            result.push("paste")
        if (field.length > 0 && field.selectedText.length < field.length)
            result.push("selectAll")
        return result
    }

    function run(action) {
        const field = textMenu.field
        if (!field)
            return
        switch (action) {
        case "cut": field.cut(); break
        case "copy": field.copy(); break
        case "paste": field.paste(); break
        case "selectAll": field.selectAll(); break
        }
    }

    function open(x, y) {
        const available = actions()
        if (available.length === 0)
            return
        while (menu.count > 0)
            menu.takeItem(0).destroy()
        for (const action of available) {
            const item = itemComponent.createObject(null, { editAction: action, text: Theme.textMenuLabels[action] ?? action })
            menu.addItem(item)
        }
        menu.popup(textMenu.target, x, y)
    }

    /// Opens the menu at the cursor (keyboard invocation).
    function openAtCursor() {
        const field = textMenu.field
        if (!field)
            return
        const rectangle = field.cursorRectangle
        open(rectangle.x, rectangle.y + rectangle.height)
    }

    TapHandler {
        target: null
        parent: textMenu.target
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.WithinBounds
        onTapped: eventPoint => textMenu.open(eventPoint.position.x, eventPoint.position.y)
    }

    MeridianMenu {
        id: menu
        nativeMenu: true
    }

    Component {
        id: itemComponent
        MeridianMenuItem {
            required property string editAction
            onTriggered: textMenu.run(editAction)
        }
    }
}
