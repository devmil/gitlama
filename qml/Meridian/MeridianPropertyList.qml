pragma ComponentBehavior: Bound
import QtQuick

// Label–value pairs (Flutter: MeridianPropertyList): a 120px `caption`
// label column in `ink-muted` and selectable values, `space-3` apart. Narrow
// lists and touch density stack the label over the value.
// `properties` is an array of { label, value, monospace, selectable }.
Column {
    id: root

    property var properties: []
    property real labelWidth: Metrics.propertyLabelColumn
    readonly property bool stacked: Theme.touch || width < labelWidth * Metrics.propertyStackFactor

    spacing: Theme.space.s3

    Repeater {
        model: root.properties
        delegate: Item {
            id: row
            required property var modelData
            width: root.width
            height: root.stacked ? label.height + Theme.space.s1 + value.height : Math.max(label.height, value.height)
            Accessible.role: Accessible.StaticText
            Accessible.name: modelData.label + ": " + modelData.value

            MeridianText {
                id: label
                width: root.stacked ? row.width : root.labelWidth
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: row.modelData.label
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                // Baseline-align the caption with the value's first line.
                y: root.stacked ? 0 : Math.max(0, (value.firstLineHeight - Theme.type.captionLineHeight) / 2)
                Accessible.ignored: true
            }
            MeridianSelectableText {
                id: value
                x: root.stacked ? 0 : root.labelWidth + Theme.space.s4
                y: root.stacked ? label.height + Theme.space.s1 : 0
                width: row.width - x
                role: row.modelData.monospace ? MeridianText.Code : MeridianText.Body
                tabular: row.modelData.monospace === true
                text: row.modelData.value
                selectable: row.modelData.selectable !== false
                Accessible.ignored: true
            }
        }
    }
}
