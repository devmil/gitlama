pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The window bar of the workspace (WorkspaceToolbar): Fetch, Pull, Push,
// Branch and Stash on the left; the Compass and the command palette button
// in the middle; Refresh, Logbook, Activity, Settings, More and the window
// controls on the right.
Item {
    id: toolbar

    readonly property var active: Store.workspace ? Store.workspace.active : null
    readonly property bool hasRepository: active !== null && active !== undefined && active.hasSession === true
    readonly property bool compact: width <= GitLamaLayout.compactBreakpoint
    property var availability: ({})
    property bool refreshing: false
    property bool operationsVisible: false
    property bool activityVisible: false
    property bool paletteOpen: false
    property bool detailsOpen: false
    property int syncSequence: 0
    property bool syncChanged: false
    /// The operation center: {runningCount, failedCount, foreground: {label, detail, progress}, running}.
    property var operations: ({})
    readonly property Item compassItem: compass
    readonly property Item paletteButton: paletteToolbarButton

    signal command(string id, var options)

    implicitHeight: Theme.size.toolbar

    function reasonOf(id) {
        return Commands.reason(id, toolbar.availability)
    }

    WindowDragArea { anchors.fill: parent }

    Row {
        id: leading
        anchors.left: parent.left
        anchors.leftMargin: Theme.space.s5
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s1

        Item {
            visible: Store.isMac
            width: Metrics.macOSTrafficLightInset - Theme.space.s1
            height: Theme.size.toolbar
        }
        ToolbarCommand {
            visible: toolbar.hasRepository
            commandId: "fetch"
            compact: toolbar.compact
            nudge: MeridianNudge.Down
            reason: toolbar.reasonOf("fetch")
            onRun: toolbar.command("fetch", {})
        }
        ToolbarCommand {
            visible: toolbar.hasRepository
            commandId: "pull"
            compact: toolbar.compact
            nudge: MeridianNudge.Down
            badge: toolbar.active && toolbar.active.behind > 0 ? toolbar.active.behind : 0
            reason: toolbar.reasonOf("pull")
            onRun: toolbar.command("pull", {})
        }
        ToolbarCommand {
            id: push
            visible: toolbar.hasRepository
            commandId: "push"
            compact: toolbar.compact
            nudge: MeridianNudge.Up
            badge: toolbar.active && toolbar.active.ahead > 0 ? toolbar.active.ahead : 0
            reason: toolbar.reasonOf("push")
            menu: pushMenu
            menuLabel: L10n.t("pushOptions")
            onRun: toolbar.command("push", {})
        }
        ToolbarCommand {
            visible: toolbar.hasRepository && !toolbar.compact
            commandId: "createBranch"
            compact: toolbar.compact
            label: L10n.t("toolbarBranch")
            icon: "branch"
            reason: toolbar.reasonOf("createBranch")
            onRun: toolbar.command("createBranch", {})
        }
        ToolbarCommand {
            visible: toolbar.hasRepository && !toolbar.compact
            commandId: "createStash"
            compact: toolbar.compact
            nudge: MeridianNudge.Down
            reason: toolbar.reasonOf("createStash")
            onRun: toolbar.command("createStash", {})
        }
    }

    MeridianMenu {
        id: pushMenu
        nativeMenu: true
        MeridianMenuItem {
            text: L10n.t("commandPush")
            onTriggered: toolbar.command("push", { force: false })
        }
        MeridianMenuSeparator {}
        MeridianMenuItem {
            text: L10n.t("transferForceWithLease")
            danger: true
            onTriggered: toolbar.command("push", { force: true })
        }
    }

    // The Compass stays centred in the window: a slot as wide as the
    // Commands button balances it.
    Row {
        id: centre
        readonly property real slot: Theme.size.control + Theme.space.s2
        readonly property real available: trailing.x - (leading.x + leading.width) - 2 * Theme.space.s4
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(leading.x + leading.width + Theme.space.s4,
                    Math.min((toolbar.width - width) / 2, trailing.x - Theme.space.s4 - width))
        spacing: 0
        Item { width: centre.slot; height: 1 }
        Compass {
            id: compass
            objectName: "repository-toolbar-context"
            width: Math.max(0, Math.min(implicitWidth, centre.available - 2 * centre.slot))
            opacity: toolbar.detailsOpen ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.exit } }
            repository: toolbar.active ? toolbar.active.label : L10n.t("appTitle")
            branch: !toolbar.active ? ""
                  : toolbar.active.branch ? toolbar.active.branch
                  : toolbar.active.headObjectId ? L10n.t("compassDetachedAt", [String(toolbar.active.headObjectId).slice(0, 8)]) : ""
            detached: toolbar.active ? toolbar.active.detached === true : false
            ahead: toolbar.active ? toolbar.active.ahead : 0
            behind: toolbar.active ? toolbar.active.behind : 0
            dirty: toolbar.active ? toolbar.active.dirty : 0
            conflicts: toolbar.active ? toolbar.active.conflicts : 0
            operation: toolbar.operations.foreground ? toolbar.operations.foreground.label + "…" : ""
            operationDetail: toolbar.operations.foreground && toolbar.operations.foreground.detail
                             ? toolbar.operations.foreground.detail : ""
            activeProgress: toolbar.operations.running === true
            progress: toolbar.operations.progress ?? -1
            syncSequence: toolbar.syncSequence
            syncChanged: toolbar.syncChanged
            compact: toolbar.compact
            onShowDetails: toolbar.command("showRepositoryDetails", {})
        }
        Item { width: Theme.space.s2; height: 1 }
        MeridianIconButton {
            id: paletteToolbarButton
            objectName: "toolbar-command-palette"
            anchors.verticalCenter: parent.verticalCenter
            opacity: toolbar.paletteOpen ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.exit } }
            text: L10n.t("commandPaletteTitle")
            iconName: "command"
            onGround: true
            tooltip: Commands.shortcutLabel("showCommandPalette").length > 0
                     ? L10n.t("commandPaletteShortcutTooltip", [Commands.shortcutLabel("showCommandPalette")])
                     : L10n.t("commandPaletteTitle")
            onClicked: toolbar.command("showCommandPalette", {})
        }
    }

    Row {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.s5
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        MeridianIconButton {
            visible: !toolbar.compact
            anchors.verticalCenter: parent.verticalCenter
            text: L10n.t("workspaceRefresh")
            tooltip: L10n.t("workspaceRefreshLocalHint")
            iconName: "refresh"
            onGround: true
            nudge: MeridianNudge.Rotate
            spinning: toolbar.refreshing
            readonly property string reason: toolbar.reasonOf("refreshRepository")
            enabled: reason.length === 0
            disabledReason: Commands.reasonText(reason)
            onClicked: toolbar.command("refreshRepository", {})
        }
        // Running work, or failures in `attention`, as a badge (NM-12).
        MeridianIconButton {
            anchors.verticalCenter: parent.verticalCenter
            text: L10n.t("logbookTitle")
            iconName: "history"
            onGround: true
            active: toolbar.operationsVisible
            badge: (toolbar.operations.failedCount ?? 0) > 0 ? toolbar.operations.failedCount : (toolbar.operations.runningCount ?? 0)
            badgeTone: (toolbar.operations.failedCount ?? 0) > 0 ? MeridianCount.Attention : MeridianCount.Accent
            onClicked: toolbar.command("showOperations", {})
        }
        MeridianIconButton {
            visible: !toolbar.compact
            anchors.verticalCenter: parent.verticalCenter
            text: L10n.t("workspaceActivity")
            iconName: "list-view"
            onGround: true
            active: toolbar.activityVisible
            onClicked: toolbar.command("showActivity", {})
        }
        MeridianIconButton {
            visible: !toolbar.compact
            anchors.verticalCenter: parent.verticalCenter
            text: L10n.t("settingsTitle")
            iconName: "settings"
            onGround: true
            onClicked: toolbar.command("showSettings", {})
        }
        MeridianToolbarButton {
            id: overflow
            objectName: "toolbar-overflow"
            anchors.verticalCenter: parent.verticalCenter
            width: Metrics.toolbarButtonCompactWidth
            text: L10n.t("toolbarMore")
            iconName: "more"
            showLabel: false
            onClicked: overflowMenu.show(overflow, 0, overflow.height)
        }
        Item {
            visible: Store.isMac
            width: GitLamaLayout.titleBarDragWidth
            height: Theme.size.toolbar
        }
        // Linux draws no title bar; its window buttons follow the actions.
        Item {
            visible: Store.drawsCaption && windowControls.buttons.length > 0
            width: Theme.space.s4
            height: Theme.size.toolbar
        }
        WindowControls {
            id: windowControls
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    CommandMenu {
        id: overflowMenu
        items: CommandMenus.workspaceMenu(toolbar.availability)
        onSelected: (id) => toolbar.command(id, {})
    }
}
