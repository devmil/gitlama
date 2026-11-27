import QtQuick

// Test stand-in for the native GraphRow painter (graph_row.h).
Item {
    property var row: null
    property real clipRight: 0
    property var laneColors: []
    property color wipColor
    property color conflictColor
    property color nodeBackground
    property color strongInk
    property color faintColor
    property color addedColor
    property bool strong: false
    property bool lightingActive: false
    property bool lit: false
    property bool incomingLit: false
    property string rowKey
    property real litBlend: 0
    readonly property real rowLitness: 0
    property real drawProgress: 1
    property bool landing: false
    property real ringOpacity: 0
    property real ringClose: 0
    property real halo: 0
    property real core: 0
    signal changed()
    signal lightingTransition()
}
