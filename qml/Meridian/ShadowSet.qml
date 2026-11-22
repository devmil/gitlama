import QtQuick

// The shadow tokens of one theme, as layer lists for MeridianShadow.
QtObject {
    property bool dark: false
    readonly property var _theme: Tokens.shadows[dark ? "dark" : "light"]
    /// Every island: the shadow is its edge.
    readonly property var pane: _theme.pane
    /// Menus, popovers, toasts, dialogs, sheets.
    readonly property var float: _theme.float
    /// Secondary buttons, the select trigger, the selected segment: a 1px lip.
    readonly property var control: _theme.control
}
