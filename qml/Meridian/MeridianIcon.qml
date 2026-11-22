import QtQuick
import QtQuick.Shapes

// A single-ink Lucide icon from Meridian's set. Decorative: pair it with a
// label, or give the control that holds it an accessible name.
Item {
    id: root

    enum Size { Small, Regular, Toolbar }

    /// Lucide name, e.g. "circle-check".
    property string name
    property int iconSize: MeridianIcon.Regular
    /// An explicit extent in logical pixels; overrides `iconSize` when > 0.
    property real extent: 0
    property color color: Theme.colors.ink
    /// Lucide's stroke is 2 on the 24px grid. It scales with the icon.
    property real strokeWidth: 2

    readonly property real dimension: extent > 0 ? extent
        : iconSize === MeridianIcon.Small ? Theme.size.iconSmall
        : iconSize === MeridianIcon.Toolbar ? Theme.size.iconToolbar
        : Theme.size.icon
    /// The Lucide name `name` resolves to through the app's aliases.
    readonly property string resolvedName: Theme.iconAliases[name] ?? name
    readonly property string pathData: IconData.paths[resolvedName] ?? ""
    readonly property bool known: pathData.length > 0

    implicitWidth: dimension
    implicitHeight: dimension
    Accessible.ignored: true

    Shape {
        width: 24
        height: 24
        scale: root.dimension / 24
        transformOrigin: Item.TopLeft
        visible: root.known
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.pathData }
        }
    }
}
