import QtQuick

// The engine's root: creates the main window and exits with an error when
// the window's QML cannot load, so a broken build fails instead of running
// without a window.
QtObject {
    id: boot

    required property var app
    required property var hooks
    required property var workspace
    property var window: null

    Component.onCompleted: {
        const component = Qt.createComponent("Main.qml")
        if (component.status !== Component.Ready) {
            console.error(component.errorString())
            Qt.exit(3)
            return
        }
        window = component.createObject(null, { app: boot.app, hooks: boot.hooks, workspace: boot.workspace })
        if (window === null) {
            console.error("the main window could not be created")
            Qt.exit(3)
        }
    }
}
