pragma Singleton
import QtQuick

// The resolved Meridian theme for one application window tree.
//
// An app sets `brand`, `mode`, `density` and `reducedMotion` once (usually
// from its preferences and the platform adapter) and every primitive reads
// colours, type, radii, spacing and sizes from here. Never hard-code a value a
// token or metric already names.
QtObject {
    id: theme

    enum Mode { System, Light, Dark }
    enum Density { Compact, Regular, Comfortable, Touch }

    /// A brand id from Tokens.brandIds, e.g. "crossproton".
    property string brand: "gitlama"
    property int mode: Theme.System
    /// The platform's colour scheme. Bound to the style hints by default;
    /// apps and tests may override it.
    property bool systemDark: Application.styleHints.colorScheme === Qt.ColorScheme.Dark
    /// -1 follows the brand's default density.
    property int density: -1
    /// The app's reduce-motion preference OR'd with the platform setting.
    /// Qt has no portable reduce-motion signal; the app's platform adapter
    /// supplies it.
    property bool reducedMotion: false
    /// Multiplies type sizes: the platform's text scale (GTK's
    /// text-scaling-factor on Linux). Layout sizes stay put.
    property real textScale: 1

    readonly property var brandInfo: Tokens.brands[brand] ?? Tokens.brands[Tokens.brandIds[0]]
    readonly property bool dark: mode === Theme.Dark || (mode === Theme.System && systemDark)
    readonly property int resolvedDensity: density >= 0 ? density : _densityFor(brandInfo.density)
    readonly property bool touch: resolvedDensity === Theme.Touch

    readonly property ColorScheme colors: ColorScheme {
        palette: (Tokens.palettes[theme.brandInfo.id] ?? {})[theme.dark ? "dark" : "light"] ?? ({})
    }

    readonly property TypeScale type: TypeScale {
        touch: theme.touch
        scale: theme.textScale
        sansFamily: theme.brandInfo.sans
        monoFamily: theme.brandInfo.mono
        readingFamily: theme.brandInfo.reading
    }

    readonly property RadiusScale radius: RadiusScale {
        brandSteps: theme.brandInfo.radius ?? ({})
    }

    readonly property SpaceScale space: SpaceScale {}

    /// Density-resolved extents (MeridianDensity in the Flutter library).
    readonly property SizeScale size: SizeScale {
        density: theme.resolvedDensity
    }

    /// Shadow layers ({x, y, blur, spread, color}) for MeridianShadow.
    readonly property ShadowSet shadows: ShadowSet {
        dark: theme.dark
    }

    /// `color` with zero alpha, so a fill can fade in without passing through
    /// translucent black.
    function clear(color) {
        return Qt.rgba(color.r, color.g, color.b, 0)
    }

    /// `over` at `alpha` composited onto `base` (Flutter's Color.alphaBlend).
    function blend(base, over, alpha) {
        const a = over.a * alpha
        const outA = a + base.a * (1 - a)
        if (outA <= 0)
            return Qt.rgba(0, 0, 0, 0)
        return Qt.rgba((over.r * a + base.r * base.a * (1 - a)) / outA,
                       (over.g * a + base.g * base.a * (1 - a)) / outA,
                       (over.b * a + base.b * base.a * (1 - a)) / outA,
                       outA)
    }

    /// Meridian's pressed state: 4% `ink` over `base`.
    function pressed(base) {
        return blend(base, colors.ink, Metrics.opacityPressedOverlay)
    }

    /// A solid fill brightened by its own ink (primary and danger hover).
    function brighten(fill, onFill) {
        return blend(fill, onFill, Metrics.opacityPrimaryHoverOverlay)
    }

    /// The hover fill of a quiet control on `surface` (`pane` by default).
    function hoverFillOn(surface, onGround) {
        if (typeof surface === "string")
            surface = Qt.lighter(surface, 1.0)
        if (surface === undefined || surface === null || surface.a === 0)
            return onGround ? colors.groundHover : colors.paneHover
        if (Qt.colorEqual(surface, colors.pane))
            return colors.paneHover
        if (Qt.colorEqual(surface, colors.ground))
            return colors.groundHover
        if (Qt.colorEqual(surface, colors.accent))
            return brighten(colors.accent, colors.inkOnAccent)
        return pressed(blend(onGround ? colors.ground : colors.pane, surface, 1))
    }

    function _densityFor(name) {
        switch (name) {
        case "compact": return Theme.Compact
        case "comfortable": return Theme.Comfortable
        case "touch": return Theme.Touch
        default: return Theme.Regular
        }
    }
}
