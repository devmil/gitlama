pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Meridian

// An inspection window: one location of a
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
    /// The host the repository is on; "" on this computer.
    readonly property string hostId: Store.inspectionWindows ? Store.inspectionWindows.hostOf(windowId) : ""
    readonly property var host: hostId.length > 0 ? Labels.remoteHost(hostId) : null
    /// A remote repository whose host the main window is not connected to.
    readonly property bool disconnected: hostId.length > 0 && (host === null || host.ready !== true)
    readonly property string name: hostId.length > 0 ? L10n.tn("remoteTabLabel", { repository: folder, host: Labels.remoteHostName(hostId) }) : folder

    width: GitLamaLayout.inspectionWindowWidth
    height: GitLamaLayout.inspectionWindowHeight
    minimumWidth: GitLamaLayout.windowMinimumWidth
    minimumHeight: GitLamaLayout.windowMinimumHeight
    color: Theme.colors.ground
    title: location === null ? name + " — " + L10n.t("appTitle") : name + " — " + view.locationLabel(location)

    onClosing: {
        Store.inspectionWindows.close(window.windowId)
        window.destroy()
    }

    // The platform's Close Window key (⌘W, Ctrl+W) closes this window like its close button.
    Shortcut {
        sequences: [StandardKey.Close]
        context: Qt.WindowShortcut
        onActivated: window.close()
    }

    MeridianIsland {
        anchors.fill: parent
        anchors.margins: Theme.space.s3
        // A host the main window is not connected to: connect there, then try again.
        MeridianEmptyState {
            objectName: "inspector-window-disconnected"
            anchors.fill: parent
            visible: window.disconnected
            compact: true
            iconName: "wifi-off"
            title: window.host !== null ? L10n.tn("remoteTabDisconnectedTitle", { host: window.host.label })
                : L10n.t("inspectorRemoteHostNotConnected")
            message: L10n.t("inspectorRemoteHostNotConnectedDetail")
            MeridianButton {
                objectName: "inspector-window-retry"
                text: L10n.t("retry")
                onClicked: Store.inspectionWindows.retry(window.windowId)
            }
        }
        InspectorView {
            id: view
            visible: !window.disconnected
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
