pragma Singleton
import QtQuick

// The window's bridge objects, set once by Main before the content loads, so
// every component reads the same state and sends the same commands.
QtObject {
    /// The AppState bridge: startup, appearance, platform, prompts, notices.
    property var app: null
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
    readonly property var clone: workspace && workspace.clone ? workspace.clone : ({})
    readonly property bool hasTabs: workspace !== null && workspace.tabs.length > 0

    /// Development screenshots: a named step (dark, light, ...) the window runs.
    signal screenshotStepRequested(string name, string argument)
    function screenshotStep(name, argument) {
        if (name === "dark" || name === "light")
            screenshotTheme = name
        else if (name === "size") {
            const parts = argument.split("x")
            screenshotSize = Qt.size(Number(parts[0]), Number(parts[1]))
        } else if (name === "open" && workspace)
            workspace.openPath(argument)
        screenshotStepRequested(name, argument)
    }
    /// Overrides the theme for a development screenshot.
    property string screenshotTheme: ""
    /// Resizes the window for a development screenshot.
    property size screenshotSize: Qt.size(0, 0)
}
