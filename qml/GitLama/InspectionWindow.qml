pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Meridian

// An inspection window (the Dart inspection_window_app): one location of a
// repository in an inspector of its own, beside the main window. Its title
// names the repository's folder and what it shows.
Window {
    id: window

    required property int windowId
    required property var bridge
    required property var diffModel
    required property var blameModel
    /// The repository's path; Show in main window needs its tab.
    required property string repository

    readonly property var location: bridge && bridge.state ? (bridge.state.location ?? null) : null
    readonly property string folder: repository.split(/[\\/]/).filter(part => part.length > 0).pop() ?? repository

    width: GitLamaLayout.inspectionWindowWidth
    height: GitLamaLayout.inspectionWindowHeight
    minimumWidth: GitLamaLayout.windowMinimumWidth
    minimumHeight: GitLamaLayout.windowMinimumHeight
    color: Theme.colors.ground
    title: location === null ? folder + " — " + L10n.t("appTitle") : folder + " — " + view.locationLabel(location)

    onClosing: {
        Store.inspectionWindows.close(window.windowId)
        window.destroy()
    }

    MeridianIsland {
        anchors.fill: parent
        anchors.margins: Theme.space.s3
        InspectorView {
            id: view
            anchors.fill: parent
            inWindow: true
            windowId: window.windowId
            windowRepository: window.repository
            bridge: window.bridge
            diffModel: window.diffModel
            blameModel: window.blameModel
        }
    }
}
