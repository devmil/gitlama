pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The active repository's body (the Dart WorkspaceBody): the sidebar (a
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

        MeridianIsland {
            anchors.fill: parent
            MeridianText {
                anchors.centerIn: parent
                color: Theme.colors.inkMuted
                text: body.active ? body.active.pane : ""
            }
        }
    }
}
