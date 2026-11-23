pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// A labelled choice among stored setting values:
// segmented for two or three peers, a select otherwise.
MeridianSettingsRow {
    id: choice

    property var values: []
    property var value
    property var valueLabel: v => String(v)
    property bool segmented: false
    signal chosen(var value)

    readonly property var shownValue: values.indexOf(value) >= 0 ? value : values[0]

    MeridianSegmented {
        visible: choice.segmented
        label: choice.label
        segments: choice.values.map(v => ({ value: v, label: choice.valueLabel(v) }))
        value: choice.shownValue
        onActivated: v => choice.chosen(v)
    }
    MeridianSelect {
        visible: !choice.segmented
        label: choice.label
        values: choice.values
        value: choice.shownValue
        valueLabel: choice.valueLabel
        onActivated: v => choice.chosen(v)
    }
}
