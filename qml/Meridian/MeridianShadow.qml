pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Paints a Meridian shadow token (`Theme.shadows.pane`, `.float`, `.control`)
// behind a rounded rectangle of the same size. Hard rings (no blur) are drawn
// as crisp outlines; blurred layers use RectangularShadow, a signed-distance
// shadow that needs no offscreen pass.
Item {
    id: root

    property var layers: Theme.shadows.pane
    property real radius: Theme.radius.lg

    Repeater {
        model: root.layers
        delegate: Item {
            id: shadowLayer
            required property var modelData
            anchors.fill: parent

            Rectangle {
                visible: shadowLayer.modelData.blur === 0 && shadowLayer.modelData.spread > 0
                x: shadowLayer.modelData.x - shadowLayer.modelData.spread
                y: shadowLayer.modelData.y - shadowLayer.modelData.spread
                width: root.width + 2 * shadowLayer.modelData.spread
                height: root.height + 2 * shadowLayer.modelData.spread
                radius: root.radius + shadowLayer.modelData.spread
                color: "transparent"
                border.width: shadowLayer.modelData.spread
                border.color: shadowLayer.modelData.color
            }

            Rectangle {
                // A hard offset lip (e.g. shadow-control: 0 1px 0).
                visible: shadowLayer.modelData.blur === 0 && shadowLayer.modelData.spread === 0
                x: shadowLayer.modelData.x
                y: shadowLayer.modelData.y
                width: root.width
                height: root.height
                radius: root.radius
                color: shadowLayer.modelData.color
            }

            RectangularShadow {
                visible: shadowLayer.modelData.blur > 0
                anchors.fill: parent
                offset.x: shadowLayer.modelData.x
                offset.y: shadowLayer.modelData.y
                blur: shadowLayer.modelData.blur
                spread: shadowLayer.modelData.spread
                radius: root.radius
                color: shadowLayer.modelData.color
            }
        }
    }
}
