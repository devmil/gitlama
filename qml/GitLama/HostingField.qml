import QtQuick
import Meridian

// A labelled text field of the hosting settings (the Dart _HostingTextField).
Column {
    id: field

    property string label
    property alias text: input.text
    signal edited()

    spacing: Theme.space.s2

    MeridianText { role: MeridianText.Label; text: field.label }
    MeridianTextField {
        id: input
        width: parent.width
        enabled: field.enabled
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        Accessible.name: field.label
        onTextEdited: field.edited()
    }
}
