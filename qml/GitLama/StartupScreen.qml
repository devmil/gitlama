import QtQuick
import Meridian

// The loading and failed-start screen: the mark at the centre (where the
// macOS launch cover drew it) with progress below, or the failure with Retry.
Rectangle {
    id: screen

    property bool failed: false
    signal retry()

    color: Theme.colors.ground

    Image {
        id: mark
        visible: !screen.failed
        anchors.centerIn: parent
        width: GitLamaLayout.launchMarkSize
        height: GitLamaLayout.launchMarkSize
        source: "qrc:/GitLama/brand/tile-256.png"
        sourceSize: Qt.size(256, 256)
        smooth: true
        mipmap: true
        Accessible.ignored: true
    }

    Column {
        visible: !screen.failed
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.space.s8
        anchors.rightMargin: Theme.space.s8
        y: screen.height / 2 + GitLamaLayout.launchMarkSize / 2 + Theme.space.s7
        spacing: Theme.space.s4
        Accessible.role: Accessible.StaticText
        Accessible.name: L10n.t("startupLoading")

        MeridianSpinner { anchors.horizontalCenter: parent.horizontalCenter }
        MeridianText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: L10n.t("startupLoading")
            color: Theme.colors.inkMuted
        }
    }

    MeridianBanner {
        visible: screen.failed
        anchors.centerIn: parent
        width: Math.min(Metrics.dialogWidth, screen.width - 2 * Theme.space.s8)
        tone: MeridianBanner.Error
        message: L10n.t("startupFailed")
        MeridianButton {
            text: L10n.t("retry")
            variant: MeridianButton.Primary
            onClicked: screen.retry()
        }
    }

    CaptionBand {}
}
