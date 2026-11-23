import QtQuick
import QtQuick.Window

// Keeps the main window's frame across launches in the appearance settings.
// The window stays hidden until `restore` gives it the saved frame (a frame no
// screen shows keeps its size and is centred), then every move, resize and
// maximize is saved after a short pause, and once more by `save` on close.
// Wayland compositors place windows themselves, so there only the size and
// the maximized state take effect.
QtObject {
    id: geometry

    required property Window window
    /// Saves fields into the appearance settings: `function(patch)`.
    required property var update

    property bool restored: false

    function restore(appearance) {
        if (restored)
            return
        restored = true
        const width = appearance.windowWidth
        const height = appearance.windowHeight
        const x = appearance.windowX
        const y = appearance.windowY
        const complete = [x, y, width, height].every(value => typeof value === "number")
        if (complete) {
            window.width = Math.max(width, window.minimumWidth)
            window.height = Math.max(height, window.minimumHeight)
            if (_onScreen(x, y, window.width, window.height)) {
                window.x = x
                window.y = y
            } else {
                _centre()
            }
        } else {
            _centre()
        }
        if (appearance.windowMaximized === true)
            window.showMaximized()
        else
            window.show()
    }

    /// Shows the window as it is, for a start without settings.
    function reveal() {
        if (restored)
            return
        restored = true
        window.show()
    }

    /// Saves the frame now.
    function save() {
        pause.stop()
        if (!restored)
            return
        if (window.visibility === Window.Maximized) {
            geometry.update({ windowMaximized: true })
            return
        }
        if (window.visibility !== Window.Windowed)
            return
        const clamp = (value, low) => Math.round(Math.min(Math.max(value, low), GitLamaLayout.windowMaximumExtent))
        geometry.update({
            windowX: Math.round(window.x),
            windowY: Math.round(window.y),
            windowWidth: clamp(window.width, GitLamaLayout.windowMinimumWidth),
            windowHeight: clamp(window.height, GitLamaLayout.windowMinimumHeight),
            windowMaximized: false
        })
    }

    function _onScreen(x, y, width, height) {
        const screens = Application.screens
        for (let index = 0; index < screens.length; ++index) {
            const screen = screens[index]
            const overlapWidth = Math.min(x + width, screen.virtualX + screen.width) - Math.max(x, screen.virtualX)
            const overlapHeight = Math.min(y + height, screen.virtualY + screen.height) - Math.max(y, screen.virtualY)
            if (overlapWidth >= GitLamaLayout.windowVisibleOverlap && overlapHeight >= GitLamaLayout.windowVisibleOverlap)
                return true
        }
        return false
    }

    function _centre() {
        const screen = window.screen
        if (!screen)
            return
        window.x = screen.virtualX + Math.max(0, (screen.width - window.width) / 2)
        window.y = screen.virtualY + Math.max(0, (screen.height - window.height) / 2)
    }

    function _changed() {
        if (restored)
            pause.restart()
    }

    readonly property Timer pause: Timer {
        interval: GitLamaLayout.windowGeometrySaveDelay
        onTriggered: geometry.save()
    }

    readonly property Connections watch: Connections {
        target: geometry.window
        function onXChanged() { geometry._changed() }
        function onYChanged() { geometry._changed() }
        function onWidthChanged() { geometry._changed() }
        function onHeightChanged() { geometry._changed() }
        function onVisibilityChanged() { geometry._changed() }
    }
}
