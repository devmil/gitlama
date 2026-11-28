pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// GitLama's About: the mark, the name, the maker
// and the version, centred like a title page, the source code and licenses,
// then the Lama family with GitLama picked out.
MeridianDialog {
    id: dialog

    signal openLicenses()

    readonly property string sourceUrl: "https://github.com/devmil/gitlama"

    objectName: "brand-about"
    widthClass: MeridianDialog.Confirm
    closeLabel: L10n.t("close")

    Column {
        width: parent ? parent.width : 0
        spacing: 0
        Accessible.role: Accessible.Grouping
        Accessible.name: L10n.t("aboutApp")

        Item { width: 1; height: Theme.space.s5 }
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: GitLamaLayout.aboutMarkSize
            height: GitLamaLayout.aboutMarkSize
            source: "qrc:/GitLama/brand/tile-256.png"
            smooth: true
            mipmap: true
        }
        Item { width: 1; height: Theme.space.s7 }
        MeridianText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            role: MeridianText.Display
            text: L10n.t("appTitle")
            Accessible.role: Accessible.Heading
        }
        Item { width: 1; height: Theme.space.s3 }
        MeridianText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            color: Theme.colors.inkMuted
            text: L10n.t("brandMaker")
        }
        Item { width: 1; height: Theme.space.s4; visible: version.visible }
        MeridianSelectableText {
            id: version
            objectName: "brand-about-version"
            visible: (Store.platform.version ?? "").length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: L10n.tn("aboutVersion", { version: Store.platform.version ?? "", build: String(Store.platform.build ?? "") })
        }
        Item { width: 1; height: Theme.space.s5 }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.space.s3
            MeridianButton {
                objectName: "brand-about-source"
                text: L10n.t("aboutSourceCode")
                iconName: "external-link"
                variant: MeridianButton.Quiet
                controlSize: MeridianButton.Small
                onClicked: {
                    if (!Qt.openUrlExternally(dialog.sourceUrl))
                        Notifications.show(L10n.t("aboutSourceCodeOpenFailed"), true)
                }
            }
            MeridianButton {
                objectName: "brand-about-licenses"
                text: L10n.t("licensesTitle")
                iconName: "file-text"
                variant: MeridianButton.Quiet
                controlSize: MeridianButton.Small
                onClicked: dialog.openLicenses()
            }
        }
        Item { width: 1; height: Theme.space.s9 }
        MeridianHairline { width: parent.width }
        Item { width: 1; height: Theme.space.s7 }
        MeridianText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            role: MeridianText.Overline
            color: Theme.colors.inkMuted
            text: L10n.t("lamaFamily")
        }
        Item { width: 1; height: Theme.space.s5 }
        Flow {
            id: family
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, familyWidth)
            spacing: Theme.space.s3
            property real familyWidth: 0
            Repeater {
                model: L10n.t("lamaFamilyNames").split("·").map(name => name.trim()).filter(name => name.length > 0)
                delegate: MeridianChip {
                    required property string modelData
                    text: modelData
                    tone: modelData === L10n.t("appTitle") ? MeridianChip.Accent : MeridianChip.Neutral
                    Component.onCompleted: family.familyWidth += implicitWidth + (family.familyWidth > 0 ? family.spacing : 0)
                }
            }
        }
        Item { width: 1; height: Theme.space.s3 }
    }
}
