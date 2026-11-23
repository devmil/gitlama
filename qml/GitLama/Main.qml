pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Meridian

// GitLama's main window: the startup screen until the services are ready,
// then the home screen (welcome or workspace).
Window {
    id: appWindow

    required property var app
    required property var hooks
    required property var workspace
    required property var sidebar
    required property var sidebarRows
    required property var history
    required property var historyRows
    required property var inspector
    required property var inspectorDiff
    required property var changes
    required property var unstagedRows
    required property var stagedRows
    required property var workingDiff
    required property var commit
    required property var workflows
    required property var settings
    required property var conflicts
    required property var conflictRows
    required property var operations
    required property var patches
    required property var lineSelection
    required property var lineRows
    required property var inspectorBlame

    // A command forwarded from the command line brings the window forward.
    Connections {
        target: appWindow.app
        function onActivationChanged() {
            if (appWindow.visibility === Window.Minimized)
                appWindow.showNormal()
            appWindow.raise()
            appWindow.requestActivate()
        }
    }

    readonly property var appearance: app.appearance ?? ({})

    width: 1280
    height: 800
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    title: L10n.t("appTitle")
    color: Theme.colors.ground
    // Linux draws its own caption in the toolbar; macOS keeps the native
    // frame with a unified toolbar.
    flags: Store.drawsCaption ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window

    Binding { target: Theme; property: "brand"; value: "gitlama" }
    Binding { target: Theme; property: "iconAliases"; value: GitLamaIcons.aliases }
    Binding {
        target: Theme
        property: "mode"
        value: Store.screenshotTheme === "dark" ? Theme.Dark
             : Store.screenshotTheme === "light" ? Theme.Light
             : appWindow.appearance.theme === "light" ? Theme.Light
             : appWindow.appearance.theme === "dark" ? Theme.Dark : Theme.System
    }
    Binding {
        target: Theme
        property: "density"
        value: appWindow.appearance.density === "compact" ? Theme.Compact
             : appWindow.appearance.density === "comfortable" ? Theme.Comfortable : Theme.Regular
    }
    Binding {
        target: Theme
        property: "reducedMotion"
        value: appWindow.appearance.reduceMotion === "reduce" ? true
             : appWindow.appearance.reduceMotion === "full" ? false : appWindow.systemReducedMotion
    }
    property bool systemReducedMotion: false
    Binding { target: L10n; property: "language"; value: Qt.locale().name.startsWith("de") ? "de" : "en" }

    Component.onCompleted: {
        Store.app = app
        Store.screenshotSizeChanged.connect(() => {
            appWindow.width = Store.screenshotSize.width
            appWindow.height = Store.screenshotSize.height
        })
        Store.hooks = hooks
        Store.workspace = workspace
        Store.sidebar = sidebar
        Store.sidebarRows = sidebarRows
        Store.history = history
        Store.historyRows = historyRows
        Store.inspector = inspector
        Store.inspectorDiff = inspectorDiff
        Store.changes = changes
        Store.unstagedRows = unstagedRows
        Store.stagedRows = stagedRows
        Store.workingDiff = workingDiff
        Store.commit = commit
        Store.workflows = workflows
        Store.settings = settings
        Store.conflicts = conflicts
        Store.conflictRows = conflictRows
        Store.operations = operations
        Store.patches = patches
        Store.lineSelection = lineSelection
        Store.lineRows = lineRows
        Store.inspectorBlame = inspectorBlame
        Store.actions = actions
        systemReducedMotion = hooks.reduceMotion()
        Theme.textScale = hooks.textScale()
        Store.captionLayout = _parseCaptionLayout(hooks.captionLayout())
        Qt.callLater(() => appWindow.hooks.configureWindow())
        const request = hooks.screenshotRequest()
        if (request.length > 0)
            screenshot.start(request)
    }

    // Development: saves the window (after optional steps) and quits.
    Timer {
        id: screenshot
        property string path
        property var steps: []
        interval: 2500
        function start(request) {
            const parts = request.split(";")
            path = parts[0]
            steps = parts.slice(1)
            restart()
        }
        onTriggered: {
            const step = steps.shift()
            if (step !== undefined) {
                const separator = step.indexOf(":")
                const name = separator < 0 ? step : step.slice(0, separator)
                const argument = separator < 0 ? "" : step.slice(separator + 1)
                Store.screenshotStep(name, argument)
                interval = 1200
                restart()
                return
            }
            if (path === "-")
                return
            appWindow.contentItem.grabToImage(result => {
                result.saveToFile(path)
                Qt.quit()
            })
        }
    }

    /// GTK's decoration layout ("menu:minimize,maximize,close"); entries GitLama
    /// does not draw are skipped, a missing value is a single trailing close.
    function _parseCaptionLayout(value) {
        if (value === undefined || value === null || value === "@none")
            return { leading: [], trailing: ["close"] }
        const known = ["minimize", "maximize", "close"]
        const sides = String(value).split(":")
        const buttons = side => side.split(",").map(name => name.trim()).filter(name => known.indexOf(name) >= 0)
        return { leading: buttons(sides[0]), trailing: sides.length > 1 ? buttons(sides[1]) : [] }
    }

    onClosing: app.flushSettings()

    MeridianGround { anchors.fill: parent }

    Loader {
        anchors.fill: parent
        sourceComponent: appWindow.app.startup === "ready" ? homeComponent : startupComponent
    }

    Component {
        id: startupComponent
        StartupScreen {
            failed: appWindow.app.startup === "failed"
            onRetry: appWindow.app.retry()
        }
    }

    Component {
        id: homeComponent
        HomeScreen {}
    }

    Actions {
        id: actions
        window: appWindow
    }

    // Commands' keyboard shortcuts, once a repository can take them.
    CommandShortcuts {
        enabled: Store.app && Store.app.startup === "ready"
    }

    LinuxResizeEdges {
        anchors.fill: parent
        visible: Store.drawsCaption && appWindow.visibility === Window.Windowed
    }
}
