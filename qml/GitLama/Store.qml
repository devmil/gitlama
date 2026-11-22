pragma Singleton
import QtQuick

// The window's bridge objects, set once by Main before the content loads, so
// every component reads the same state and sends the same commands.
QtObject {
    /// The AppState bridge: startup, appearance, platform.
    property var app: null
    /// Native window hooks (PlatformHooks).
    property var hooks: null

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

    /// Development screenshots: a named step (dark, light, ...) the window runs.
    signal screenshotStepRequested(string name, string argument)
    function screenshotStep(name, argument) {
        if (name === "dark" || name === "light")
            screenshotTheme = name
        screenshotStepRequested(name, argument)
    }
    /// Overrides the theme for a development screenshot.
    property string screenshotTheme: ""
}
