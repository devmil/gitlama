import QtQuick

// The window: the workspace while repositories are open, the welcome screen
// otherwise.
Item {
    Loader {
        anchors.fill: parent
        sourceComponent: Store.hasTabs ? workspaceComponent : welcomeComponent
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
