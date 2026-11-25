import QtQuick

// One diff line's text. Read-only and never focused or selected by its own pointer: DiffView
// draws the cross-line selection highlight behind it and offers Copy in its own menu and on
// Ctrl+C, so the line needs no native TextEdit selection or text menu of its own.
TextEdit {
    readOnly: true
    selectByMouse: false
    selectByKeyboard: false
    activeFocusOnPress: false
    activeFocusOnTab: false
}
