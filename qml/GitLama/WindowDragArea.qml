import QtQuick
import QtQuick.Window

// Turns empty background into window caption: dragging moves the window and
// double-clicking toggles maximize. Controls above it keep their gestures.
// Without a GitLama-drawn caption (macOS, Windows) it does nothing.
Item {
    id: area

    readonly property bool active: Store.drawsCaption || Store.isMac

    TapHandler {
        enabled: area.active
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.DragThreshold
        onDoubleTapped: {
            const window = area.Window.window
            if (window.visibility === Window.Maximized)
                window.showNormal()
            else
                window.showMaximized()
        }
    }
    DragHandler {
        enabled: area.active
        target: null
        acceptedButtons: Qt.LeftButton
        onActiveChanged: if (active) area.Window.window.startSystemMove()
    }
}
