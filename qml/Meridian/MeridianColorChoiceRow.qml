pragma ComponentBehavior: Bound
import QtQuick

// The theme's categorical colours as swatches, optionally led by a "no
// colour" swatch and followed by a MeridianColorWell for any other colour
// (Flutter: MeridianColorChoiceRow): a label, a tab group, a calendar.
//
// `value` is {series: index} (a theme colour that follows light and dark),
// {custom: "#RRGGBB"} (the same in both) or null (no colour); `chosen`
// reports the next one. A custom colour stays in the well while a palette
// colour is chosen, so it can be chosen again.
Flow {
    id: row

    property var value: null
    property bool allowNone: false
    property string noneLabel: "No colour"
    property bool allowCustom: true
    property string customLabel: "Custom colour"
    property var customValueLabel: hex => "Custom colour " + hex
    /// Which categorical colours to offer, by index, in order.
    property var series: [0, 1, 2, 3, 4, 5, 6, 7]
    property var seriesLabels: ["Blue", "Teal", "Amber", "Orange", "Rose", "Violet", "Cyan", "Olive"]
    property var pickerLabels: ({})
    /// The last custom colour, kept while a palette colour is chosen.
    property string custom: value && value.custom ? value.custom : ""

    signal chosen(var choice)

    readonly property var seriesColors: [Theme.colors.series1, Theme.colors.series2, Theme.colors.series3, Theme.colors.series4,
        Theme.colors.series5, Theme.colors.series6, Theme.colors.series7, Theme.colors.series8]

    function resolve(choice) {
        if (!choice)
            return undefined
        return choice.series !== undefined ? seriesColors[choice.series] : Qt.color(choice.custom)
    }

    onValueChanged: if (value && value.custom) custom = value.custom
    spacing: Theme.space.s2

    MeridianColorSwatch {
        objectName: "meridian-color-none"
        visible: row.allowNone
        color: Theme.colors.inkMuted
        text: row.noneLabel
        selected: row.value === null || row.value === undefined
        enabled: row.enabled
        onClicked: row.chosen(null)
    }
    Repeater {
        model: row.series
        delegate: MeridianColorSwatch {
            required property int modelData
            objectName: "meridian-color-series-" + modelData
            color: row.seriesColors[modelData]
            text: row.seriesLabels[modelData] ?? ""
            selected: !!row.value && row.value.series === modelData
            enabled: row.enabled
            onClicked: row.chosen({ series: modelData })
        }
    }
    MeridianColorWell {
        objectName: "meridian-color-custom"
        visible: row.allowCustom
        hasColor: row.custom.length > 0
        color: row.custom.length > 0 ? row.custom : "transparent"
        text: row.custom.length > 0 ? row.customValueLabel(row.custom.toUpperCase()) : row.customLabel
        selected: !!row.value && row.value.custom !== undefined
        // The picker starts from the colour in use.
        initial: row.resolve(row.value)
        pickerLabels: row.pickerLabels
        enabled: row.enabled
        function hex(value) {
            const part = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
            return ("#" + part(value.r) + part(value.g) + part(value.b)).toUpperCase()
        }
        onEdited: value => {
            row.custom = hex(value)
            row.chosen({ custom: row.custom })
        }
    }
}
