import QtQuick
import QtQuick.Effects
import Meridian

// A repository's mark in its tab: the custom image when it could be read,
// else the chosen icon in the chosen colour, else a colour dot.
Item {
    id: icon

    /// {image, icon, color} or null.
    property var mark: null
    property color fallbackColor: Theme.colors.inkMuted
    readonly property color tint: mark && mark.color ? AppearanceColors.color(mark.color, fallbackColor) : fallbackColor

    visible: mark !== null && mark !== undefined
    implicitWidth: Theme.size.iconSmall
    implicitHeight: Theme.size.iconSmall
    Accessible.ignored: true

    Image {
        id: image
        readonly property bool ready: !!icon.mark && !!icon.mark.image && status === Image.Ready
        visible: false
        anchors.fill: parent
        source: icon.mark && icon.mark.image ? icon.mark.image : ""
        sourceSize: Qt.size(64, 64)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
    Rectangle {
        id: rounding
        anchors.fill: parent
        radius: Theme.radius.xs
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        visible: image.ready
        anchors.fill: parent
        source: image
        maskEnabled: true
        maskSource: rounding
    }
    MeridianIcon {
        visible: !image.ready && !!icon.mark && !!icon.mark.icon
        anchors.centerIn: parent
        name: icon.mark && icon.mark.icon ? icon.mark.icon : ""
        iconSize: MeridianIcon.Small
        color: icon.tint
    }
    Rectangle {
        visible: !image.ready && !(icon.mark && icon.mark.icon)
        anchors.centerIn: parent
        width: parent.width / 2
        height: width
        radius: width / 2
        color: icon.tint
    }
}
