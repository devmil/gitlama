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
                // Keyboard focus stays out while an operation holds the tab.
                enabled: busyLoader.active === false
                onCommand: (id, options) => shell.command(id, options)
            }
            // The active tab's blocking operation holds the repository area;
            // the area keeps its place so its scroll positions survive.
            Loader {
                id: busyLoader
                readonly property var busy: Store.workflows ? Store.workflows.busy : null
                anchors.fill: parent
                active: busy !== null && busy !== undefined
                sourceComponent: MeridianBusyOverlay {
                    message: busyLoader.busy ? L10n.tn(busyLoader.busy.key, busyLoader.busy.args ?? ({})) : ""
                    MeridianButton {
                        visible: busyLoader.busy !== null && busyLoader.busy.cancellable === true
                        text: busyLoader.busy && busyLoader.busy.canceling ? L10n.t("historyMutationCanceling") : L10n.t("cancel")
                        variant: MeridianButton.Quiet
                        enabled: busyLoader.busy !== null && busyLoader.busy.canceling !== true
                        onClicked: Store.workflows.cancelBusy()
                    }
                }
            }
        }

        WorkspaceStatusBar {
            id: statusBar
            width: parent.width
            height: Metrics.statusBarHeight
        }
    }
}
