pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The window while repositories are open: toolbar, repository tabs, the
// active repository's body and the status bar, with floating panels.
Rectangle {
    id: shell

    color: Theme.colors.ground

    readonly property var active: Store.workspace.active

    function command(id, options) {
        Store.actions.runCommand(id, options ?? ({}))
    }

    Column {
        anchors.fill: parent

        WorkspaceToolbar {
            id: toolbar
            objectName: "repository-toolbar"
            width: parent.width
            height: Theme.size.toolbar
            onCommand: (id, options) => shell.command(id, options)
        }

        RepositoryTabs {
            id: tabs
            width: parent.width
        }

        Item {
            id: body
            width: parent.width
            height: shell.height - toolbar.height - tabs.height - statusBar.height
            WorkspaceBody {
                anchors.fill: parent
            }
        }

        WorkspaceStatusBar {
            id: statusBar
            width: parent.width
            height: Metrics.statusBarHeight
        }
    }
}
