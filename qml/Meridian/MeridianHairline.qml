import QtQuick

// A 1px `line` divider (Flutter: MeridianHairline). Horizontal by default;
// set `vertical` for a column rule.
Rectangle {
    property bool vertical: false
    implicitWidth: vertical ? Metrics.hairline : 0
    implicitHeight: vertical ? 0 : Metrics.hairline
    color: Theme.colors.line
    Accessible.ignored: true
}
