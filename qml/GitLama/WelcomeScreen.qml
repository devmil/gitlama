pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Meridian

// The window without open repositories: the open, clone and create actions,
// the recent repositories and what failed. The workflows run in the core;
// this shows their state and forwards the user's choices.
Rectangle {
    id: screen

    readonly property var entry: Store.workspace ? (Store.workspace.entry ?? ({})) : ({})
    readonly property bool busy: entry.busy === true
    readonly property var recents: Store.workspace ? Store.workspace.recents : []
    readonly property bool ready: false

    color: Theme.colors.ground

    // Title row: the window caption with the Settings button.
    Item {
        id: titleRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Metrics.tabStripHeight

        WindowDragArea { anchors.fill: parent }
        MeridianText {
            anchors.left: parent.left
            anchors.leftMargin: (Store.isMac ? Metrics.macOSTrafficLightInset : 0) + Theme.space.s4
            anchors.right: settingsButton.left
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.BodyStrong
            color: Theme.colors.ink
            text: L10n.t("appTitle")
        }
        MeridianIconButton {
            id: settingsButton
            objectName: "welcome-settings"
            anchors.right: controls.left
            anchors.rightMargin: Theme.space.s3
            anchors.verticalCenter: parent.verticalCenter
            text: L10n.t("settingsTitle")
            iconName: "settings"
            onGround: true
            onClicked: Store.actions.showSettings()
        }
        WindowControls {
            id: controls
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s3
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Flickable {
        id: scroller
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleRow.bottom
        anchors.bottom: statusBar.top
        contentWidth: width
        contentHeight: Math.max(height, column.implicitHeight + 2 * Theme.space.s8)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        MeridianWheelScroll { flickable: scroller }

        ColumnLayout {
            id: column
            width: Math.min(GitLamaLayout.contentMaxWidth, scroller.width - 2 * Theme.space.s8)
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(Theme.space.s8, (scroller.contentHeight - implicitHeight) / 2)
            spacing: 0

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: GitLamaLayout.welcomeMarkSize
                Layout.preferredHeight: GitLamaLayout.welcomeMarkSize
                source: "qrc:/GitLama/brand/tile-64.png"
                sourceSize: Qt.size(128, 128)
                smooth: true
                mipmap: true
                Accessible.ignored: true
            }
            Item { Layout.preferredHeight: Theme.space.s6 }
            MeridianText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                role: MeridianText.Display
                color: Theme.colors.ink
                wrapMode: Text.Wrap
                text: screen.ready ? L10n.t("repositoryReady") : L10n.t("welcomeTitle")
            }
            Item { Layout.preferredHeight: Theme.space.s4 }
            MeridianText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                text: screen.ready ? L10n.t("repositoryReadyDetail") : L10n.t("welcomeDetail")
            }
            Item { Layout.preferredHeight: Theme.space.s8 }
            Flow {
                id: actionsFlow
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: Theme.space.s4
                // Centre each line of the wrap so the wrap is centred.
                leftPadding: Math.max(0, (width - implicitLineWidth) / 2)
                readonly property real implicitLineWidth: {
                    let total = 0
                    for (let i = 0; i < children.length; ++i)
                        if (children[i].visible)
                            total += children[i].implicitWidth + (total > 0 ? spacing : 0)
                    return Math.min(total, width)
                }
                MeridianButton {
                    text: L10n.t("welcomeOpen")
                    iconName: "folder-open"
                    variant: MeridianButton.Primary
                    loading: screen.busy
                    enabled: !screen.busy
                    onActivated: Store.workspace.openRepository()
                }
                MeridianButton {
                    objectName: "welcome-open-remote"
                    visible: Store.remoteEnabled
                    text: L10n.t("openRemoteRepository")
                    iconName: "server"
                    enabled: !screen.busy
                    onActivated: Store.actions.openRemoteRepository()
                }
                MeridianButton {
                    text: L10n.t("welcomeClone")
                    iconName: "fetch"
                    loading: Store.clone.running === true
                    enabled: !screen.busy
                    onActivated: Store.actions.cloneRepository()
                }
                MeridianButton {
                    text: L10n.t("welcomeCreate")
                    iconName: "plus"
                    loading: screen.busy
                    enabled: !screen.busy
                    onActivated: Store.workspace.initializeRepository(false)
                }
                MeridianButton {
                    text: L10n.t("initializeBareRepository")
                    variant: MeridianButton.Quiet
                    loading: screen.busy
                    enabled: !screen.busy
                    onActivated: Store.workspace.initializeRepository(true)
                }
            }
            // A running clone: its progress and Cancel.
            Item { visible: Store.clone.running === true; Layout.preferredHeight: Theme.space.s4 }
            MeridianProgressBar {
                visible: Store.clone.running === true
                Layout.fillWidth: true
                value: Store.clone.progress ?? -1
            }
            MeridianButton {
                visible: Store.clone.running === true
                text: L10n.t("cancelClone")
                variant: MeridianButton.Quiet
                onClicked: Store.workspace.cancelClone()
            }
            // Why the last clone failed, and what to try.
            Item { visible: !!screen.entry.cloneFailure; Layout.preferredHeight: Theme.space.s4 }
            MeridianBanner {
                visible: !!screen.entry.cloneFailure
                Layout.fillWidth: true
                tone: MeridianBanner.Error
                message: Labels.cloneFailureMessage(screen.entry.cloneFailure ?? "")
            }
            MeridianButton {
                visible: screen.entry.cloneFailure === "authentication"
                text: L10n.t("retryAuthentication")
                variant: MeridianButton.Quiet
                enabled: !screen.busy
                onClicked: Store.workspace.retryCloneWithCredentials()
            }
            MeridianButton {
                visible: screen.entry.cloneFailure === "hostKey"
                text: L10n.t("inspectHostKey")
                variant: MeridianButton.Quiet
                enabled: !screen.busy
                onClicked: Store.workspace.inspectCloneHostKey()
            }
            Item {
                visible: screen.entry.failure !== undefined && screen.entry.failure !== null
                Layout.preferredHeight: Theme.space.s4
            }
            MeridianBanner {
                visible: screen.entry.failure !== undefined && screen.entry.failure !== null
                Layout.fillWidth: true
                tone: MeridianBanner.Error
                message: Labels.repositoryFailureMessage(screen.entry.failure)
            }
            Item { Layout.preferredHeight: Theme.space.s8 }
            MeridianIsland {
                id: recentIsland
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.size.islandHeader + Metrics.hairline
                    + (screen.recents.length === 0 ? noRecents.implicitHeight + 2 * Theme.space.s5
                                                   : recentList.implicitHeight + Theme.space.s3)
                title: L10n.t("recentRepositories")

                MeridianText {
                    id: noRecents
                    visible: screen.recents.length === 0
                    x: Theme.space.s5
                    y: Theme.space.s5
                    width: parent.width - 2 * Theme.space.s5
                    text: L10n.t("noRecentRepositories")
                    color: Theme.colors.ink
                }
                RecentRepositoryList {
                    id: recentList
                    visible: screen.recents.length > 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: Theme.space.s3
                    recents: screen.recents
                    busy: screen.busy
                    onOpen: (recent) => Store.actions.openRecent(recent)
                }
            }
        }
    }

    MeridianStatusBar {
        id: statusBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Metrics.statusBarHeight
        StatusNotificationText { width: statusBar.width - 2 * Theme.space.s3 }
    }
}
