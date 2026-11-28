import QtQuick

// The window: the workspace while repositories are open, the welcome screen
// otherwise. The workspace is built in the background the first time a
// repository opens (building it at once froze the window for most of a
// second); the welcome screen stays until it is ready.
Item {
    Loader {
        id: workspaceLoader
        anchors.fill: parent
        active: Store.hasTabs
        asynchronous: true
        visible: status === Loader.Ready
        sourceComponent: workspaceComponent
    }
    Loader {
        anchors.fill: parent
        active: !Store.hasTabs || workspaceLoader.status !== Loader.Ready
        sourceComponent: welcomeComponent
    }
    Component {
        id: welcomeComponent
        WelcomeScreen {}
    }
    Component {
        id: workspaceComponent
        WorkspaceShell {}
    }
}
