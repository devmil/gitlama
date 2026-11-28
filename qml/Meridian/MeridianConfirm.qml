import QtQuick

// A yes/no question (Flutter: showMeridianConfirm). `confirmLabel` is the
// verb ("Delete 3 messages"); Cancel is always Cancel. A destructive
// confirmation has a danger verb and starts with focus on Cancel, so a hasty
// Enter or Space cancels. Escape always cancels.
MeridianDialog {
    id: dialog

    property string confirmLabel
    property string cancelLabel
    property bool destructive: false
    property string confirmIcon

    signal confirmed()
    signal cancelled()

    onSubmitted: confirmButton.clicked()
    onRejected: cancelled()
    onOpened: (destructive ? cancelButton : confirmButton).forceActiveFocus(Qt.TabFocusReason)

    actions: [
        MeridianButton {
            id: confirmButton
            objectName: "confirmButton"
            text: dialog.confirmLabel
            iconName: dialog.confirmIcon
            variant: dialog.destructive ? MeridianButton.Danger : MeridianButton.Primary
            onActivated: {
                dialog.close()
                dialog.confirmed()
            }
        },
        MeridianButton {
            id: cancelButton
            objectName: "cancelButton"
            text: dialog.cancelLabel
            onActivated: dialog.reject()
        }
    ]
}
