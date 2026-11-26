pragma Singleton
import QtQuick

// The window's bridge objects, set once by Main before the content loads, so
// every component reads the same state and sends the same commands.
QtObject {
    /// The AppState bridge: startup, appearance, platform, prompts, notices.
    property var app: null
    /// A commit command that arrived before the commit editor existed ("commitCreate" or
    /// "commitAmend"); the editor runs it when it is created.
    property string pendingCommitAction: ""
    /// Moments that play once per session (MeridianMotionMemory): key -> true.
    property var motionSeen: ({})
    /// Marks `key` seen; false when it was already.
    function markMotionSeen(key) {
        if (motionSeen[key] === true)
            return false
        motionSeen[key] = true
        return true
    }
    /// The WorkspaceState bridge: tabs, groups, entry actions, recents.
    property var workspace: null
    /// The SidebarState bridge: header state and sidebar slots.
    property var sidebar: null
    /// The sidebar's rows (a RowModel).
    property var sidebarRows: null
    /// The HistoryState bridge: the History pane's state and slots.
    property var history: null
    /// History's rows (a HistoryModel).
    property var historyRows: null
    /// The InspectorState bridge: the detail inspector and its slots.
    property var inspector: null
    /// The inspector's diff rows (a DiffModel).
    property var inspectorDiff: null
    /// The ChangesState bridge: the Changes pane's state and slots.
    property var changes: null
    /// The Changes file lists (RowModels) and the working diff (a DiffModel).
    property var unstagedRows: null
    property var stagedRows: null
    property var workingDiff: null
    /// The CommitState bridge: the commit editor's draft and commit.
    property var commit: null
    /// The WorkflowsState bridge: starts repository workflows.
    property var workflows: null
    /// The SettingsState bridge: the settings dialog's Git page, refused
    /// writes and licenses.
    property var settings: null
    /// The ConflictsState bridge and the shown file's comparison rows.
    property var conflicts: null
    property var conflictRows: null
    /// The inspector's blame lines.
    property var inspectorBlame: null
    /// Opens inspection windows (InspectionWindows).
    property var inspectionWindows: null
    /// Development screenshots: the window to capture instead of the main one.
    property var screenshotWindow: null
    /// The OperationsState bridge (logbook, activity).
    property var operations: null
    property var patches: null
    /// Hosting: accounts, the active repository's binding and resources.
    property var hosting: null
    /// Remote workspaces: hosts, connections, pending remote writes (RemoteState).
    property var remote: null
    /// The accounts page (development screenshots drive its form).
    property var hostingSettings: null
    property var lineSelection: null
    property var lineRows: null
    /// The workspace shell, which owns the floating panels.
    property var shell: null
    /// The History pane (development screenshots open its menus).
    property var historyPane: null
    /// The Changes lists by side (development screenshots open their menus).
    property var changesSections: ({})
    /// The inspector view (development screenshots open its file menus).
    property var inspectorView: null
    property var workingDiffPane: null
    /// The commit editor of the Changes pane (commit and amend commands).
    property var commitEditor: null
    /// The History inspector fills the workspace (Maximize).
    property bool inspectorMaximized: false
    /// Native window hooks (PlatformHooks).
    property var hooks: null
    /// The window's dialogs and workflows (Actions.qml).
    property var actions: null

    readonly property var platform: app ? app.platform : ({})
    readonly property var appearance: app && app.appearance ? app.appearance : ({})
    readonly property string os: platform && platform.os ? platform.os : Qt.platform.os
    readonly property bool isMac: os === "macos" || os === "osx"
    readonly property bool isLinux: os === "linux"
    readonly property bool isWindows: os === "windows"
    /// Linux windows are frameless: GitLama draws the caption in its toolbar.
    readonly property bool drawsCaption: isLinux
    /// The buttons GTK's decoration layout asks for: {leading: [...], trailing: [...]}.
    property var captionLayout: ({ leading: [], trailing: ["close"] })
    /// Whether this window offers remote workspaces.
    readonly property bool remoteEnabled: platform && platform.remoteEnabled === true
    /// The running clone: {running, progress, ...}.
    readonly property var clone: workspace && workspace.entry && workspace.entry.clone ? workspace.entry.clone : ({})
    readonly property bool hasTabs: workspace !== null && workspace.tabs.length > 0

    /// Development screenshots: a named step (dark, light, ...) the window runs.
    signal screenshotStepRequested(string name, string argument)
    function screenshotStep(name, argument) {
        if (name === "dark" || name === "light")
            screenshotTheme = name
        else if (name === "size") {
            const parts = argument.split("x")
            screenshotSize = Qt.size(Number(parts[0]), Number(parts[1]))
        } else if (name === "diffFind" && inspectorView) {
            inspectorView.find(argument)
        } else if (name === "appearance") {
            app.updateAppearance(JSON.parse(argument))
        } else if (name === "inspectorScope") {
            inspector.setAllFiles(argument === "all")
        } else if (name === "inspectorExpand") {
            inspector.expandDirectory(argument)
        } else if (name === "changesTree") {
            // changesTree:<side>=<on|off>
            const parts = argument.split("=")
            if (changesSections[parts[0]])
                changesSections[parts[0]].setTree(parts[1] !== "off")
        } else if (name === "toggleFolder") {
            // toggleFolder:<side>=<folder path>
            const parts = argument.split("=")
            changes.toggleFolder(parts[0], parts[1])
        } else if (name === "fileMenu") {
            // fileMenu:<side>=<row>[=<action>]
            const parts = argument.split("=")
            const section = changesSections[parts[0]]
            if (section)
                section.runFileAction(Number(parts[1]), parts[2] ?? "")
        } else if (name === "inspectorFileMenu" && inspectorView) {
            // inspectorFileMenu:<file>[=<action>]
            const parts = argument.split("=")
            inspectorView.runFileAction(Number(parts[0]), parts[1] ?? "")
        } else if (name === "hostingForm" && hostingSettings) {
            // hostingForm:<preset>: opens the add-account form for a preset.
            hostingSettings.addExpanded = true
            hostingSettings.selectPreset(argument.length > 0 ? argument : "github")
        } else if (name === "hostingGuide" && hostingSettings) {
            hostingSettings.showGuide()
        } else if (name === "drop" && workspace) {
            // drop:<path>|<path>…: as if the paths were dropped on the window.
            workspace.openDropped(argument.split("|"))
        } else if (name === "historySearch" && historyPane) {
            // historySearch:<text>: types and searches the query.
            historyPane.searchFor(argument)
        } else if (name === "historyBranchFilter" && historyPane) {
            historyPane.openBranchFilter()
        } else if (name === "historyReflog" && historyPane) {
            historyPane.toggleReflog()
        } else if (name === "commitMenu" && historyPane && historyRows) {
            // Development: builds row N's commit menu and reports its shape.
            historyPane.showCommitMenu(historyRows.objectIdAt(Number(argument)), "", historyPane, 10, 10)
            console.log("commit menu:", JSON.stringify(historyPane.commitMenuItems.map(item => item.separator ? "-" : item.title + (item.children ? "[" + item.children.length + "]" : "") + (item.enabled === false ? "(off)" : ""))))
        } else if (name === "selectRow" && history && historyRows) {
            const objectId = historyRows.objectIdAt(Number(argument))
            if (objectId.length > 0)
                history.select(objectId)
        } else if (name === "unstaged" && changes && unstagedRows) {
            const row = unstagedRows.get(Number(argument))
            if (row) {
                changes.select("unstaged", [row.key])
                history.select(row.path)
            }
        } else if (name === "diffDrag" && workingDiffPane) {
            // diffDrag:<x1>,<y1>,<x2>,<y2>[,<clicks>]: presses on the working diff and drags,
            // then logs the selected text.
            const v = argument.split(",").map(Number)
            const diff = workingDiffPane.diffView
            for (let click = 0; click < (v[4] || 1); ++click) {
                diff._press({ x: v[0], y: v[1], modifiers: 0 })
                if (click + 1 < (v[4] || 1))
                    diff._release({ x: v[0], y: v[1], modifiers: 0 })
            }
            diff._extend(v[2], v[3])
            diff._release({ x: v[2], y: v[3], modifiers: 0 })
            console.log("diff selection:", JSON.stringify(diff.selectedText()))
        } else if (name === "wheel" && hooks) {
            // wheel:<x>,<y>,<dy>[,<phase>[,<dx>[,shift]]]: a wheel notch (phase 0), a touchpad
            // gesture (1 begin, 2 update, 3 end) or, with a negative phase, a pointer move at a
            // window point.
            const v = argument.split(",")
            const n = v.map(Number)
            hooks.devWheel(n[0], n[1], n[4] || 0, n[2], n[3] || 0, v[5] === "shift" ? Qt.ShiftModifier : 0)
        } else if (name === "stageSelected" && changes) {
            changes.stageSelection(argument)
        } else if (name === "remoteAdd" && remote) {
            // remoteAdd:<label>=<alias>: saves a host profile.
            const parts = argument.split("=")
            remote.saveProfile(0, "", parts[0], parts[1] ?? parts[0], "", "server")
        } else if (name === "remoteOpen" && remote) {
            // remoteOpen:<alias>=<path>: opens a repository on a saved host.
            const parts = argument.split("=")
            remote.openOnHost(parts[0], parts.slice(1).join("="))
        } else if (name === "remoteHosts" && actions) {
            actions.showRemoteHosts("")
        } else if (name === "remoteOperations" && actions) {
            actions.showRemoteOperations()
        } else if (name === "remoteAccess" && remote) {
            // remoteAccess:<alias>=changes|read: what GitLama may do on the host.
            const parts = argument.split("=")
            const host = (remote.hosts ?? []).find(item => item.alias === parts[0])
            if (host)
                remote.setAccess(host.id, parts[1] === "changes")
        } else if (name === "remoteDisconnect" && remote) {
            // remoteDisconnect:<alias>: closes the host's connection.
            const host = (remote.hosts ?? []).find(item => item.alias === argument)
            if (host)
                remote.disconnect(host.id)
        } else if (name === "command" && actions) {
            actions.runCommand(argument, ({}))
        } else if (name === "commit" && commit) {
            commit.commit({ subject: argument, description: "", coauthors: [], author: "", amend: false,
                            skipHooks: false, signOff: false }, false, "")
        } else if (name === "file" && inspector) {
            inspector.selectFile(argument)
        } else if (name === "open" && workspace)
            workspace.openPath(argument)
        else if (name === "newTab" && workspace)
            workspace.addRepositoryChooser()
        else if (name === "tab" && workspace) {
            const tab = (workspace.tabs ?? [])[Number(argument)]
            if (tab)
                workspace.activateTab(tab.id)
        }
        screenshotStepRequested(name, argument)
    }
    /// Overrides the theme for a development screenshot.
    property string screenshotTheme: ""
    /// Resizes the window for a development screenshot.
    property size screenshotSize: Qt.size(0, 0)
}
