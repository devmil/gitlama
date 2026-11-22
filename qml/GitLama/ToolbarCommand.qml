import QtQuick
import Meridian

// One repository command in the window bar: the registry's icon and name,
// a shortened caption keeping the full name as tooltip, and the reason it
// is unavailable.
MeridianToolbarButton {
    id: button

    required property string commandId
    property bool compact: false
    /// A shortened caption; the command's name by default.
    property string label
    property string icon
    /// Why the command cannot run now; "" when it can.
    property string reason
    signal run()

    objectName: "toolbar-action-" + commandId
    text: label.length > 0 ? label : Commands.label(commandId)
    tooltip: label.length > 0 ? Commands.dialogTitle(Commands.label(commandId)) : ""
    iconName: icon.length > 0 ? icon : Commands.icon(commandId)
    showLabel: !compact
    enabled: reason.length === 0
    disabledReason: Commands.reasonText(reason)
    onClicked: run()
}
