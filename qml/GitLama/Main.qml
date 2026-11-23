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
    required property var hosting
    required property var remote
    required property var lineSelection
    required property var lineRows
    required property var inspectorBlame
    required property var inspectionWindows

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

    width: GitLamaLayout.windowDefaultWidth
    height: GitLamaLayout.windowDefaultHeight
    minimumWidth: GitLamaLayout.windowMinimumWidth
    minimumHeight: GitLamaLayout.windowMinimumHeight
    // Shown by `frame` with the saved geometry.
    visible: false
    title: L10n.t("appTitle")
    color: Theme.colors.ground
    // Linux draws its own caption in the toolbar; macOS keeps the native
    // frame with a unified toolbar.
    flags: Store.drawsCaption ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window

    Binding { target: Theme; property: "brand"; value: "gitlama" }
    Binding { target: Theme; property: "iconAliases"; value: GitLamaIcons.aliases }
    Binding {
        target: Theme
        property: "textMenuLabels"
        value: ({ cut: L10n.t("textMenuCut"), copy: L10n.t("textMenuCopy"), paste: L10n.t("textMenuPaste"), selectAll: L10n.t("textMenuSelectAll") })
    }
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
        Store.hosting = hosting
        Store.remote = remote
        Store.lineSelection = lineSelection
        Store.lineRows = lineRows
        Store.inspectorBlame = inspectorBlame
        Store.inspectionWindows = inspectionWindows
        Store.actions = actions
        systemReducedMotion = hooks.reduceMotion()
        Theme.textScale = hooks.textScale()
        Store.captionLayout = _parseCaptionLayout(hooks.captionLayout())
        _restoreFrame()
        const request = hooks.screenshotRequest()
        if (request.length > 0)
            screenshot.start(request)
    }

    // Development: saves the window (after optional steps) and quits.
    Timer {
        id: screenshot
        property string path
        property var steps: []
        /// The wait after each step; `pace:<ms>` changes it, to capture motion mid-way.
        property int pace: GitLamaLayout.screenshotStepWait
        interval: GitLamaLayout.screenshotSettle
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
                if (name === "pace") {
                    pace = Number(argument)
                    interval = 1
                    restart()
                    return
                }
                Store.screenshotStep(name, argument)
                interval = pace
                restart()
                return
            }
            if (path === "-")
                return
            // `shotWindow` captures the newest inspection window instead.
            const target = Store.screenshotWindow ?? appWindow
            target.contentItem.grabToImage(result => {
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

    onClosing: {
        // Inspection windows close with the main window.
        if (Store.actions)
            Store.actions.closeInspectionWindows()
        frame.save()
        app.flushSettings()
    }

    WindowGeometry {
        id: frame
        window: appWindow
        update: patch => appWindow.app.updateAppearance(patch)
        // Native window setup (macOS toolbar) needs the shown window.
        onRestoredChanged: Qt.callLater(() => appWindow.hooks.configureWindow())
    }
    // The saved frame arrives with the settings; a failed start shows the window as it is.
    function _restoreFrame() {
        if (appWindow.appearance.windowMaximized !== undefined)
            frame.restore(appWindow.appearance)
        else if (appWindow.app.startup === "failed")
            frame.reveal()
    }
    onAppearanceChanged: _restoreFrame()
    Connections {
        target: appWindow.app
        function onStartupChanged() { appWindow._restoreFrame() }
    }
    Timer {
        running: !frame.restored
        interval: GitLamaLayout.windowRestoreTimeout
        onTriggered: frame.reveal()
    }

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

    // Folders dropped on the window open as repositories; the prompt covers the window meanwhile.
    DropArea {
        id: repositoryDrop
        anchors.fill: parent
        enabled: appWindow.app.startup === "ready"
        keys: ["text/uri-list"]
        onEntered: drag => drag.accept(Qt.CopyAction)
        onDropped: drop => {
            const paths = drop.urls.map(url => url.toString())
                .filter(url => url.startsWith("file://"))
                .map(url => decodeURIComponent(url.slice(Qt.platform.os === "windows" ? 8 : 7)))
            appWindow.workspace.openDropped(paths.concat(drop.urls.length > paths.length ? new Array(drop.urls.length - paths.length).fill("") : []))
            drop.accept(Qt.CopyAction)
        }
    }
    Rectangle {
        objectName: "repository-drop-overlay"
        anchors.fill: parent
        visible: opacity > 0
        opacity: repositoryDrop.containsDrag ? 1 : 0
        color: Theme.colors.ground
        Behavior on opacity { NumberAnimation { duration: Motion.overlay } }
        MeridianDropZone {
            anchors.centerIn: parent
            width: Math.min(GitLamaLayout.dropPromptWidth, parent.width - 2 * Theme.space.s6)
            scale: repositoryDrop.containsDrag ? 1 : Motion.overlayEnterScale
            Behavior on scale { NumberAnimation { duration: Motion.overlay; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.enter } }
            dropState: repositoryDrop.containsDrag ? MeridianDropZone.Active : MeridianDropZone.Idle
            message: L10n.t("repositoryDropPrompt")
            iconName: "folder-open"
            browsable: false
        }
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
