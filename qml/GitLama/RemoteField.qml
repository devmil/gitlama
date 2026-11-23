import QtQuick
import Meridian

// A labelled text field of the remote workspace dialogs (the Dart MeridianTextField with
// label, error and message): the label above, the field, then an error in danger ink or a
// help message below it.
Column {
    id: field

    property string label
    property alias text: input.text
    property alias placeholderText: input.placeholderText
    property alias monospace: input.monospace
    property alias input: input
    property alias trailingContent: input.trailingContent
    /// The error to show; "" for none.
    property string error
    /// Help shown when there is no error.
    property string message
    signal edited()
    signal submitted()

    spacing: Theme.space.s2

    MeridianText { role: MeridianText.Label; text: field.label }
    MeridianTextField {
        id: input
        width: parent.width
        enabled: field.enabled
        error: field.error.length > 0
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        Accessible.name: field.label
        Accessible.description: field.error.length > 0 ? field.error : field.message
        onTextEdited: field.edited()
        onAccepted: field.submitted()
    }
    MeridianText {
        visible: text.length > 0
        width: parent.width
        role: MeridianText.Caption
        wrapMode: Text.Wrap
        color: field.error.length > 0 ? Theme.colors.danger : Theme.colors.inkMuted
        text: field.error.length > 0 ? field.error : field.message
    }
}
