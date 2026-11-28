import QtQuick

// Density-resolved extents (MeridianDensity in the Flutter library). Theme
// owns the instance apps read as Theme.size.
QtObject {
    property int density: 1
    readonly property bool touch: density === 3

    readonly property real row: [Tokens.size.rowCompact, Tokens.size.row,
        Tokens.size.rowComfortable, Tokens.size.rowTouch][density] ?? Tokens.size.row
    readonly property real control: touch ? Tokens.size.controlTouch : Tokens.size.control
    readonly property real controlSmall: touch ? Tokens.size.control : Tokens.size.controlSm
    readonly property real minTarget: touch ? Tokens.size.targetTouch : 0
    readonly property real icon: touch ? 20 : Tokens.size.icon
    readonly property real iconSmall: touch ? 18 : 14
    readonly property real iconToolbar: touch ? 22 : 18
    readonly property real toolbar: Tokens.size.toolbar
    readonly property real islandHeader: touch ? 48 : Tokens.size.islandHeader
    readonly property real sidebar: Tokens.size.sidebar
}
