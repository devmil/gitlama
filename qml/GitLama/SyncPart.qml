import QtQuick
import Meridian

// One side of the sync badge: an arrow and a rolling count that pops when
// it grows (`popOnIncrease`).
Row {
    id: part

    property string iconName
    property int count: 0
    property bool popOnIncrease: false
    property color color: Theme.colors.ink
    property int _previous: count

    onCountChanged: {
        number.direction = count >= _previous ? 1 : -1
        number.text = String(count)
        if (popOnIncrease && count > _previous && !Motion.reduced)
            pop.restart()
        _previous = count
    }
    Component.onCompleted: number.text = String(count)

    MeridianIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: part.iconName
        extent: GitLamaLayout.syncIconSize
        color: part.color
    }
    MeridianSwapText {
        id: number
        anchors.verticalCenter: parent.verticalCenter
        width: contentWidth
        style: MeridianSwapText.Roll
        role: MeridianText.Caption
        tabular: true
        color: part.color
        transformOrigin: Item.Center
    }
    SequentialAnimation {
        id: pop
        NumberAnimation { target: number; property: "scale"; to: Motion.popScale; duration: Motion.pop.duration / 2; easing.type: Easing.OutQuad }
        NumberAnimation { target: number; property: "scale"; to: 1; duration: Motion.pop.duration / 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.pop.curve }
    }
}
