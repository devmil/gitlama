pragma Singleton
import QtQuick

// UI feedback shared by the whole window (the Flutter
// StatusNotificationScope): the status bar message, which expires after
// 8 seconds, and a failure dialog for each failed action the user started.
QtObject {
    id: root

    /// The status bar message; empty when there is none.
    property string message
    property bool error: false
    /// Asks the window to show the failure dialog for `text`.
    signal failureRequested(string text, var details)

    function show(text, isError, details) {
        message = text
        error = isError === true
        expiry.restart()
        if (error)
            failureRequested(text, details ?? ({}))
    }

    property Timer expiry: Timer {
        interval: 8000
        onTriggered: {
            root.message = ""
            root.error = false
        }
    }
}
