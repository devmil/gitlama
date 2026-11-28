import QtQuick
import QtQuick.Shapes

// Draws an SVG path progressively (Flutter: MeridianStroke): the first `progress` share of
// its length, contour after contour, with round caps and joins like Lucide. Check marks,
// strike-throughs, connectors, rings. `pathData` is in the item's own coordinates, or on a
// `viewSize` grid scaled uniformly to the item's width (an icon's 24 × 24).
Item {
    id: root

    property string pathData: ""
    /// 0 draws nothing, 1 the whole path.
    property real progress: 1
    property color color: Theme.colors.ink
    /// In the path's units: on a `viewSize` grid it scales with the item.
    property real strokeWidth: 2
    /// The grid `pathData` is drawn on; 0 uses the item's coordinates.
    property real viewSize: 0

    readonly property real _scale: viewSize > 0 ? width / viewSize : 1

    Shape {
        width: root.viewSize > 0 ? root.viewSize : root.width
        height: root.viewSize > 0 ? root.viewSize : root.height
        scale: root._scale
        transformOrigin: Item.TopLeft
        visible: root.progress > 0 && root.pathData.length > 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            trim.start: 0
            trim.end: Math.max(0, Math.min(1, root.progress))
            PathSvg { path: root.pathData }
        }
    }
}
