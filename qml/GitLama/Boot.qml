import QtQuick

// The engine's root: creates the main window and exits with an error when
// the window's QML cannot load, so a broken build fails instead of running
// without a window.
QtObject {
    id: boot

    required property var app
    required property var hooks
    required property var workspace
    required property var sidebar
    required property var sidebarRows
    required property var history
    required property var historyRows
    required property var inspector
    required property var inspectorDiff
    required property var changes
    required property var unstagedRows
    required property var stagedRows
    required property var workingDiff
    required property var commit
    property var window: null

    Component.onCompleted: {
        const component = Qt.createComponent("Main.qml")
        if (component.status !== Component.Ready) {
            console.error(component.errorString())
            Qt.exit(3)
            return
        }
        window = component.createObject(null, { app: boot.app, hooks: boot.hooks, workspace: boot.workspace,
                                                         sidebar: boot.sidebar, sidebarRows: boot.sidebarRows,
                                                         history: boot.history, historyRows: boot.historyRows,
                                                         inspector: boot.inspector, inspectorDiff: boot.inspectorDiff,
                                                         changes: boot.changes, unstagedRows: boot.unstagedRows,
                                                         stagedRows: boot.stagedRows, workingDiff: boot.workingDiff,
                                                         commit: boot.commit })
        if (window === null) {
            console.error("the main window could not be created")
            Qt.exit(3)
        }
    }
}
