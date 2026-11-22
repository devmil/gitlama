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
