pragma Singleton
import QtQuick
import Meridian

// The colours a repository mark or tab group takes: a palette colour (the
// theme's categorical series, following light and dark) or a custom
// `rgb-rrggbb`, which stays the same in both.
QtObject {
    readonly property var palette: ["blue", "teal", "amber", "orange", "rose", "violet", "cyan", "olive"]

    function color(key, fallback) {
        const index = palette.indexOf(key)
        if (index >= 0) {
            const c = Theme.colors
            return [c.series1, c.series2, c.series3, c.series4, c.series5, c.series6, c.series7, c.series8][index]
        }
        const custom = /^rgb-([0-9a-f]{6})$/.exec(key ?? "")
        if (custom)
            return "#" + custom[1]
        return fallback ?? Theme.colors.inkMuted
    }

    /// The icons a repository mark or tab group can take.
    readonly property var icons: ["folder-git-2", "code-xml", "square-terminal", "box", "blocks", "puzzle", "layers", "book-open",
        "palette", "image", "smartphone", "monitor", "server", "cloud", "zap", "star", "flag", "bug", "wand-sparkles",
        "graduation-cap", "shield-check", "chart-line", "house", "users"]
    readonly property var iconNames: ({ "folder-git-2": "Repository", "code-xml": "Code", "square-terminal": "Terminal",
        "box": "Package", "blocks": "Components", "puzzle": "Plugin", "layers": "Layers", "book-open": "Documentation",
        "palette": "Design", "image": "Media", "smartphone": "Mobile", "monitor": "Desktop", "server": "Server", "cloud": "Cloud",
        "zap": "Lightning", "star": "Star", "flag": "Flag", "bug": "Bug", "wand-sparkles": "Magic", "graduation-cap": "Learning",
        "shield-check": "Security", "chart-line": "Analytics", "house": "Home", "users": "Team" })

    /// The icon's name, for tooltips and accessibility.
    function iconLabel(icon) {
        const name = iconNames[icon]
        return name ? L10n.t("repositoryIconName" + name) : L10n.t("repositoryIconSymbol")
    }

    /// A stored colour key as a MeridianColorChoiceRow value, and back.
    function choice(key) {
        const index = palette.indexOf(key)
        if (index >= 0)
            return { series: index }
        const custom = /^rgb-([0-9a-f]{6})$/.exec(key ?? "")
        return custom ? { custom: "#" + custom[1].toUpperCase() } : null
    }
    function keyOf(choice) {
        if (!choice)
            return ""
        return choice.series !== undefined ? palette[choice.series] : "rgb-" + choice.custom.replace("#", "").toLowerCase()
    }

    readonly property var seriesLabels: palette.map(key => label(key))
    /// The colour picker's strings in the app's language.
    function pickerLabels() {
        return {
            wheel: L10n.t("colorPickerWheel"), hue: L10n.t("colorPickerHue"), saturation: L10n.t("colorPickerSaturation"),
            brightness: L10n.t("colorPickerBrightness"), red: L10n.t("colorPickerRed"), green: L10n.t("colorPickerGreen"),
            blue: L10n.t("colorPickerBlue"), hsv: L10n.t("colorPickerHsb"), rgb: L10n.t("colorPickerRgb"),
            channels: L10n.t("colorPickerModel"), hex: L10n.t("colorPickerHex"), invalidHex: L10n.t("colorPickerInvalidHex"),
            original: L10n.t("colorPickerOriginal"), current: L10n.t("colorPickerNew"),
            swatch: hex => L10n.t("colorPickerSwatch", [hex]),
            degrees: value => L10n.t("colorPickerDegrees", [value]),
            percent: value => L10n.t("colorPickerPercent", [value]),
        }
    }

    /// The colour's name, for menus and accessibility labels.
    function label(key) {
        switch (key) {
        case "blue": return L10n.t("repositoryColorBlue")
        case "teal": return L10n.t("repositoryColorTeal")
        case "amber": return L10n.t("repositoryColorAmber")
        case "orange": return L10n.t("repositoryColorOrange")
        case "rose": return L10n.t("repositoryColorRose")
        case "violet": return L10n.t("repositoryColorViolet")
        case "cyan": return L10n.t("repositoryColorCyan")
        case "olive": return L10n.t("repositoryColorOlive")
        }
        const custom = /^rgb-([0-9a-f]{6})$/.exec(key ?? "")
        return custom ? L10n.t("repositoryColorCustomValue", ["#" + custom[1].toUpperCase()]) : ""
    }
}
