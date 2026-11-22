import QtQuick

// Settings rows of one page (Flutter: MeridianSettingsGroup), `space-6`
// apart, under an optional `overline` title.
Column {
    id: root
    property string title
    default property alias rows: rowColumn.data
    spacing: Theme.space.s5
    MeridianText {
        visible: root.title.length > 0
        width: root.width
        role: MeridianText.Overline
        text: root.title
        color: Theme.colors.inkMuted
    }
    Column {
        id: rowColumn
        width: root.width
        spacing: Theme.space.s6
    }
}
