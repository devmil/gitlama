pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Meridian

// The window buttons the desktop configured (GTK's decoration layout), for
// the trailing end of the top toolbar row. Buttons a layout puts on the
// start edge are shown here too. Renders nothing without a drawn caption.
Row {
    id: controls

    /// Which buttons: "leading", "trailing" or "all".
    property string side: "all"
    readonly property var buttons: !Store.drawsCaption ? []
        : side === "leading" ? Store.captionLayout.leading
        : side === "trailing" ? Store.captionLayout.trailing
        : Store.captionLayout.leading.concat(Store.captionLayout.trailing)

    visible: buttons.length > 0
    spacing: 0

    Repeater {
        model: controls.buttons
        MeridianIconButton {
            id: button
            required property string modelData
            text: modelData === "minimize" ? L10n.t("windowMinimize")
                 : modelData === "maximize" ? L10n.t("windowMaximize")
                 : L10n.t("windowClose")
            iconName: modelData === "minimize" ? "minus" : modelData === "maximize" ? "square" : "x"
            onGround: true
            focusPolicy: Qt.NoFocus
            onClicked: {
                const window = controls.Window.window
                if (modelData === "minimize")
                    window.showMinimized()
                else if (modelData === "maximize")
                    window.visibility === Window.Maximized ? window.showNormal() : window.showMaximized()
                else
                    window.close()
            }
        }
    }
}
