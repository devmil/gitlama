import QtQuick

// One diff line's text. Read-only and never focused or selected by its own pointer: DiffView
// selects across lines (it sets each line's part with `select`) and offers Copy in its own
// menu and on Ctrl+C, so the line needs no text menu of its own.
TextEdit {
    readOnly: true
    selectByMouse: false
    selectByKeyboard: false
    activeFocusOnPress: false
    activeFocusOnTab: false
    persistentSelection: true
}
