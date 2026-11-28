pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// A new tab that has no repository yet: the
// mark, Open a repository, why the last open failed, and the recent
// repositories, each opening in this tab.
Item {
    id: chooser

    /// The tab this chooser fills.
    required property var tab
    readonly property var recents: Store.workspace ? Store.workspace.recents : []
    /// An open from this chooser is running; the tab's next state ends it.
    property bool busy: false
    onTabChanged: busy = false

    function open(recentIndex) {
        if (busy)
            return
        busy = true
        Store.workspace.openFromChooser(tab.tabId ?? tab.id, recentIndex)
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        contentHeight: column.implicitHeight + 2 * Theme.space.s9
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        MeridianWheelScroll { flickable: scroller }
        C.ScrollBar.vertical: MeridianScrollBar {}

        Column {
            id: column
            objectName: "repository-chooser"
            x: Math.max(Theme.space.s9, (scroller.width - width) / 2)
            y: Theme.space.s9
            width: Math.min(GitLamaLayout.contentMaxWidth, scroller.width - 2 * Theme.space.s9)
            spacing: 0

            Image {
                objectName: "repository-chooser-mark"
                source: "qrc:/GitLama/brand/tile-256.png"
                width: Theme.size.control * 4
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                Accessible.ignored: true
            }
            Item { width: 1; height: Theme.space.s2 }
            MeridianText { role: MeridianText.Caption; text: L10n.t("brandMaker") }
            Item { width: 1; height: Theme.space.s6 }
            MeridianText {
                role: MeridianText.Title
                text: L10n.t("brandWelcome")
                color: Theme.colors.ink
            }
            Item { width: 1; height: Theme.space.s8 }
            MeridianButton {
                objectName: "repository-chooser-browse"
                text: L10n.t("openRepository")
                iconName: "folder-open"
                variant: MeridianButton.Primary
                enabled: !chooser.busy
                onClicked: chooser.open(-1)
            }
            Item { visible: Store.remoteEnabled; width: 1; height: Theme.space.s4 }
            MeridianButton {
                objectName: "repository-chooser-remote"
                visible: Store.remoteEnabled
                text: L10n.t("openRemoteRepository")
                iconName: "server"
                enabled: !chooser.busy
                onClicked: Store.actions.openRemoteRepository(chooser.tab.tabId ?? chooser.tab.id)
            }
            Item { width: 1; height: (chooser.tab.failure ?? null) !== null ? Theme.space.s6 : 0 }
            MeridianBanner {
                visible: (chooser.tab.failure ?? null) !== null
                width: parent.width
                tone: MeridianBanner.Error
                message: Labels.repositoryFailureMessage(chooser.tab.failure ?? "")
            }
            Item { width: 1; height: Theme.space.s9 }
            MeridianText {
                role: MeridianText.BodyStrong
                text: L10n.t("recentRepositories")
                color: Theme.colors.ink
            }
            Item { width: 1; height: Theme.space.s4 }
            MeridianText {
                visible: chooser.recents.length === 0
                text: L10n.t("noRecentRepositories")
            }
            RecentRepositoryList {
                visible: chooser.recents.length > 0
                width: parent.width
                recents: chooser.recents
                busy: chooser.busy
                onOpen: recent => {
                    if (recent.remote)
                        Store.actions.openRecent(recent, chooser.tab.tabId ?? chooser.tab.id)
                    else
                        chooser.open(recent.index)
                }
            }
        }
    }
}
