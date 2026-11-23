pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The active repository's body: the sidebar (a
// rail when the window is narrow) beside the workspace islands.
Item {
    id: body

    readonly property var active: Store.workspace ? Store.workspace.active : null
    readonly property var appearance: Store.appearance
    readonly property bool compactSidebar: width < GitLamaLayout.compactBreakpoint + Theme.space.s5
    readonly property real sidebarWidth: Math.max(Metrics.sidebarMinWidth,
        Math.min(Metrics.sidebarMaxWidth, appearance.sidebarWidth ?? Theme.size.sidebar))
    /// The width while the splitter is dragged; saved when the drag ends.
    property real draggedSidebarWidth: -1
    /// The detail island's height while its splitter is dragged.
    property real draggedDetailHeight: -1
    /// The detail island's chosen height for this window (not saved); -1
    /// splits evenly.
    property real detailHeight: -1
    readonly property real shownSidebarWidth: draggedSidebarWidth >= 0 ? draggedSidebarWidth : sidebarWidth

    signal command(string id, var options)

    function setSidebarWidth(width) {
        const clamped = Math.round(Math.max(Metrics.sidebarMinWidth, Math.min(Metrics.sidebarMaxWidth, width)))
        Store.app.updateAppearance({ sidebarWidth: clamped })
    }

    SidebarRail {
        id: rail
        visible: body.compactSidebar
        width: Metrics.sidebarRailWidth
        height: parent.height - Theme.space.s3
        pane: body.active ? body.active.pane : ""
        onSelectPane: pane => Store.sidebar.selectPane(pane)
    }

    WorkspaceSidebar {
        id: sidebar
        objectName: "workspace-sidebar"
        visible: !body.compactSidebar
        width: body.shownSidebarWidth
        height: parent.height - Theme.space.s3
        onCommand: (id, options) => body.command(id, options)
    }

    MeridianResizeHandle {
        id: splitter
        objectName: "sidebar-pane-splitter"
        visible: !body.compactSidebar
        x: sidebar.width
        height: sidebar.height
        semanticLabel: L10n.t("workspaceResizeSidebar")
        keyboardStep: GitLamaLayout.paneResizeStep
        activeFocusOnTab: false
        onDragStarted: body.draggedSidebarWidth = body.sidebarWidth
        onDragged: delta => {
            const base = body.draggedSidebarWidth >= 0 ? body.draggedSidebarWidth : body.sidebarWidth
            body.draggedSidebarWidth = Math.max(Metrics.sidebarMinWidth, Math.min(Metrics.sidebarMaxWidth, base + delta))
            if (!dragging) {
                body.setSidebarWidth(body.draggedSidebarWidth)
                body.draggedSidebarWidth = -1
            }
        }
        onDragFinished: {
            if (body.draggedSidebarWidth >= 0)
                body.setSidebarWidth(body.draggedSidebarWidth)
            body.draggedSidebarWidth = -1
        }
    }

    Item {
        id: workspace
        x: body.compactSidebar ? rail.width : splitter.x + splitter.width
        width: body.width - x - Theme.space.s3
        height: parent.height - Theme.space.s3

        readonly property bool history: body.active !== null && body.active.pane === "history"
        // The graph stays mounted while the inspector is maximized, so its
        // scroll position and selection survive.
        readonly property bool maximized: history && Store.inspectorMaximized
        readonly property real detailHeight: Math.max(180, Math.min(height - GitLamaLayout.primaryIslandMinHeight - Theme.space.s3,
            body.draggedDetailHeight >= 0 ? body.draggedDetailHeight
                : body.detailHeight >= 0 ? body.detailHeight : (height - Theme.space.s3) / 2))

        readonly property bool conflictFlow: !workspace.history && body.active !== null && body.active.hasStatus === true
            && Store.changes !== null && (Store.changes.state ?? ({})).conflictFlow === true

        // Changes: the files island beside the diff.
        ChangesPane {
            visible: !workspace.history && body.active !== null && body.active.hasStatus === true && !workspace.conflictFlow
            anchors.fill: parent
            onCommand: (id, options) => body.command(id, options)
        }
        // A paused operation at conflicts: the resolver replaces Changes.
        Loader {
            id: resolverLoader
            active: workspace.conflictFlow
            anchors.fill: parent
            sourceComponent: ConflictResolver {
                onCommand: (id, options) => body.command(id, options)
            }
        }

        // History keeps the full width above; details and the diff below.
        MeridianIsland {
            id: primary
            visible: (workspace.history && !workspace.maximized) || body.active === null || !body.active.hasStatus
            width: parent.width
            height: workspace.history ? Math.max(0, parent.height - workspace.detailHeight - Theme.space.s3) : parent.height
            HistoryPane {
                anchors.fill: parent
                visible: workspace.history
                onCommand: (id, options) => body.command(id, options)
            }
            MeridianEmptyState {
                visible: !workspace.history && (body.active === null || !body.active.hasStatus)
                anchors.fill: parent
                compact: true
                progress: true
                title: L10n.t("workspaceLoadingRepository")
            }
        }
        MeridianResizeHandle {
            objectName: "detail-pane-splitter"
            visible: workspace.history && !workspace.maximized
            y: primary.height
            width: parent.width
            orientation: Qt.Vertical
            semanticLabel: L10n.t("workspaceResizeDetail")
            keyboardStep: GitLamaLayout.paneResizeStep
            activeFocusOnTab: false
            onDragStarted: body.draggedDetailHeight = workspace.detailHeight
            onDragged: delta => {
                const base = body.draggedDetailHeight >= 0 ? body.draggedDetailHeight : workspace.detailHeight
                body.draggedDetailHeight = base - delta
                if (!dragging) {
                    body.detailHeight = body.draggedDetailHeight
                    body.draggedDetailHeight = -1
                }
            }
            onDragFinished: {
                if (body.draggedDetailHeight >= 0)
                    body.detailHeight = workspace.detailHeight
                body.draggedDetailHeight = -1
            }
        }
        MeridianIsland {
            objectName: "detail-pane"
            visible: workspace.history
            y: parent.height - height
            width: parent.width
            height: workspace.maximized ? parent.height : workspace.detailHeight
            InspectorView {
                anchors.fill: parent
            }
        }
    }
}
