import QtQuick

// One setting (Flutter: MeridianSettingsRow): the label right-aligned in a
// 200px column, the controls beside it, `help` below them. Below 520px and at
// touch density the label stacks above the controls. Changes apply straight
// away: no Save button.
Item {
    id: root

    property string label
    property string help
    property real labelWidth: 200
    default property alias controls: controlColumn.data
    readonly property bool stacked: Theme.touch || width < 520

    implicitWidth: 560
    implicitHeight: stacked ? labelText.height + Theme.space.s2 + side.height
                            : Math.max(labelText.height, side.height)

    MeridianText {
        id: labelText
        width: root.stacked ? root.width : root.labelWidth
        y: root.stacked ? 0 : Math.max(0, (Math.min(controlColumn.height, Theme.size.control) - height) / 2)
        horizontalAlignment: root.stacked ? Text.AlignLeft : Text.AlignRight
        text: root.label
        color: Theme.colors.ink
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    Column {
        id: side
        x: root.stacked ? 0 : root.labelWidth + Theme.space.s5
        y: root.stacked ? labelText.height + Theme.space.s2 : 0
        width: root.width - x
        spacing: Theme.space.s2
        Column {
            id: controlColumn
            width: parent.width
            spacing: Theme.space.s3
        }
        MeridianText {
            width: Math.min(380, parent.width)
            visible: root.help.length > 0
            role: MeridianText.Caption
            text: root.help
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
    }
}
