import QtQuick
import Meridian

// One side of the sync badge: an arrow and a count that rolls digit by digit and pops when
// it grows (`popOnIncrease`).
Row {
    id: part

    property string iconName
    property int count: 0
    property bool popOnIncrease: false
    property color color: Theme.colors.ink

    MeridianIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: part.iconName
        extent: GitLamaLayout.syncIconSize
        color: part.color
    }
    MeridianRollingNumber {
        anchors.verticalCenter: parent.verticalCenter
        value: part.count
        popOnIncrease: part.popOnIncrease
        role: MeridianText.Caption
        color: part.color
    }
}
