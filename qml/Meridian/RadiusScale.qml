import QtQuick

// The brand's radius steps over the core scale. `radius-pill` never changes.
QtObject {
    /// The brand's own steps ({ xs, sm, md, lg, xl }), if any.
    property var brandSteps: ({})

    readonly property real xs: brandSteps.xs ?? Tokens.radius.xs
    readonly property real sm: brandSteps.sm ?? Tokens.radius.sm
    readonly property real md: brandSteps.md ?? Tokens.radius.md
    readonly property real lg: brandSteps.lg ?? Tokens.radius.lg
    readonly property real xl: brandSteps.xl ?? Tokens.radius.xl
    readonly property real pill: Tokens.radius.pill
}
