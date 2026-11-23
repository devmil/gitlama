import QtQuick

// An invisible copy of a text laid out like the Text it shadows, for geometry Text does not
// expose (`positionToRectangle`): where a changed word lands on a wrapped diff line. It takes
// no input, focus or selection, so it needs no text menu.
TextEdit {
    opacity: 0
    enabled: false
    readOnly: true
    activeFocusOnPress: false
    selectByMouse: false
    Accessible.ignored: true
}
