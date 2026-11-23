pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The window while repositories are open: toolbar, repository tabs, the
// active repository's body and the status bar, with floating panels.
Rectangle {
    id: shell

    color: Theme.colors.ground

    readonly property var active: Store.workspace.active
    /// The one floating panel shown: operations, snapshots, extensions,
    /// integrations, powerTools, or "".
    property string panel: ""
    /// Panels still built (one plays its exit while another enters).
    property var mounted: ({})
    readonly property bool operationsVisible: panel === "operations"
    property bool activityVisible: false
    readonly property var activityIsland: activity.item
    /// The operation the toolbar's Compass shows, with its progress.
    readonly property var operationSummary: {
        const center = Store.operations ? (Store.operations.center ?? ({})) : ({})
        const entries = center.entries ?? []
        const foreground = entries.find(entry => entry.origin === "user" && entry.state === "running") ?? null
        const running = foreground ?? entries.find(entry => entry.state === "running") ?? null
        const action = name => L10n.t("operation" + name.charAt(0).toUpperCase() + name.slice(1))
        let detail = ""
        if (foreground && foreground.progress) {
            const progress = Labels.operationProgress(foreground.progress)
            detail = progress.length > 0 ? L10n.tn("operationRunningDetail", { operation: action(foreground.action), detail: progress }) : ""
        }
        return {
            foreground: foreground ? { label: action(foreground.action), detail: detail } : null,
            running: running !== null,
            progress: running && running.progress ? running.progress.percent / 100 : -1,
            failedCount: center.failed ?? 0,
            runningCount: center.running ?? 0,
        }
    }

    function togglePanel(name) {
        if (panel === name) {
            panel = ""
            return
        }
        const next = Object.assign({}, mounted)
        next[name] = true
        mounted = next
        panel = name
    }
    function closePanel(name) {
        if (panel === name)
            panel = ""
    }
    function unmountPanel(name) {
        if (panel === name)
            return
        const next = Object.assign({}, mounted)
        delete next[name]
        mounted = next
    }
    function toggleOperations() { togglePanel("operations") }
    Component.onCompleted: Store.shell = shell

    function command(id, options) {
        Store.actions.runCommand(id, options ?? ({}))
    }

    /// The Compass grows into the active repository's details.
    function showRepositoryDetails() {
        if (!repositoryDetails.opened && Store.workspace.details)
            repositoryDetails.open()
    }
    RepositoryDetailsPanel {
        id: repositoryDetails
        anchorItem: toolbar.compassItem
    }

    Column {
        anchors.fill: parent

        WorkspaceToolbar {
            id: toolbar
            objectName: "repository-toolbar"
            width: parent.width
            height: Theme.size.toolbar
            operations: shell.operationSummary
            operationsVisible: shell.operationsVisible
            activityVisible: shell.activityVisible
            detailsOpen: repositoryDetails.visible
            onCommand: (id, options) => shell.command(id, options)
        }

        RepositoryTabs {
            id: tabs
            width: parent.width
        }

        Item {
            id: body
            width: parent.width
            height: shell.height - toolbar.height - tabs.height - statusBar.height - (activity.visible ? activity.height + Theme.space.s3 : 0)
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

        // The active repository's recent commands, under the workspace.
        Loader {
            id: activity
            active: shell.activityVisible
            visible: active
            x: Theme.space.s3
            width: parent.width - 2 * Theme.space.s3
            height: active ? GitLamaLayout.activityHeight : 0
            sourceComponent: ActivityIsland {}
        }
        Item { visible: activity.visible; width: 1; height: Theme.space.s3 }

        WorkspaceStatusBar {
            id: statusBar
            width: parent.width
            height: Metrics.statusBarHeight
        }
    }

    // The logbook, below the toolbar at the trailing edge.
    Loader {
        id: logbook
        active: shell.mounted.operations === true
        x: shell.width - width - Theme.space.s3
        y: toolbar.height + tabs.height + Theme.space.s2
        z: 10
        sourceComponent: LogbookPanel {
            shown: shell.panel === "operations"
            onCloseRequested: shell.closePanel("operations")
            onHidden: shell.unmountPanel("operations")
            onShowDetails: key => shell.activityVisible = true
        }
    }
    // Named snapshots, in the same place.
    Loader {
        active: shell.mounted.snapshots === true
        x: shell.width - width - Theme.space.s3
        y: toolbar.height + tabs.height + Theme.space.s2
        z: 10
        sourceComponent: SnapshotsPanel {
            shown: shell.panel === "snapshots"
            availableHeight: shell.height - y - Metrics.statusBarHeight - Theme.space.s4
            onCloseRequested: shell.closePanel("snapshots")
            onHidden: shell.unmountPanel("snapshots")
        }
    }
}
