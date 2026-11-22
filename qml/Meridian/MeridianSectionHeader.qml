pragma ComponentBehavior: Bound
import QtQuick

// The header strip of an island or section (Flutter: MeridianSectionHeader):
// an optional icon or leading item, the title (`body-strong`, announced as a
// heading), a quiet count, a caption, an optional middle that takes the
// remaining width, and small actions at the end, `space-1` apart. A hairline
// divides it from the content unless `divider` is off.
Item {
    id: root

    enum Size { Regular, Small }

    property string title
    property string iconName
    /// Replaces `iconName` (a status glyph, an avatar).
    property Component leading
    /// A quiet count after the title; -1 shows none.
    property int count: -1
    /// The count's accessible name ("12 files").
    property string countLabel
    /// Metadata after the title (a size, a path, "3 of 12").
    property string caption
    /// Content between the title and the actions that takes the rest.
    property Component middle
    property bool divider: true
    /// The strip's fill; transparent by default.
    property color color: "transparent"
    property int size: MeridianSectionHeader.Regular
    default property alias actions: actionRow.data

    implicitHeight: Math.max(Theme.size.islandHeader, Theme.size.minTarget) + (divider ? Metrics.hairline : 0)
    implicitWidth: 240

    Rectangle {
        anchors.fill: parent
        color: root.color
    }

    Item {
        id: strip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(Theme.size.islandHeader, Theme.size.minTarget)
        anchors.leftMargin: Theme.space.s5
        anchors.rightMargin: Theme.space.s3

        Loader {
            id: leadingItem
            active: root.leading !== null || root.iconName.length > 0
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: root.leading ?? iconComponent
        }
        Component {
            id: iconComponent
            MeridianIcon {
                name: root.iconName
                iconSize: MeridianIcon.Small
                color: Theme.colors.inkMuted
            }
        }

        Row {
            id: heading
            readonly property real start: leadingItem.active ? leadingItem.width + Theme.space.s3 : 0
            readonly property real available: (middleItem.active ? strip.width / 2 : strip.width - actionRow.width - Theme.space.s1) - start
            x: start
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            MeridianText {
                id: titleText
                visible: root.title.length > 0
                width: Math.min(implicitWidth, Math.max(0, heading.available - countItem.width - captionGap.width - Math.min(captionText.implicitWidth, heading.available / 3)))
                role: root.size === MeridianSectionHeader.Small ? MeridianText.Label : MeridianText.BodyStrong
                color: Theme.colors.ink
                text: root.title
                Accessible.role: Accessible.Heading
                Accessible.name: root.title
            }
            Item { width: titleText.visible && countItem.visible ? Theme.space.s2 : 0; height: 1 }
            MeridianCount {
                id: countItem
                visible: root.count >= 0
                anchors.verticalCenter: parent.verticalCenter
                label: String(root.count)
                tone: MeridianCount.Quiet
                semanticLabel: root.countLabel
            }
            Item { id: captionGap; width: captionText.visible ? Theme.space.s4 : 0; height: 1 }
            MeridianText {
                id: captionText
                visible: root.caption.length > 0
                width: Math.min(implicitWidth, Math.max(0, heading.available - titleText.width - countItem.width - captionGap.width))
                role: MeridianText.Caption
                tabular: true
                color: Theme.colors.inkMuted
                text: root.caption
            }
        }

        Loader {
            id: middleItem
            active: root.middle !== null
            sourceComponent: root.middle
            anchors.verticalCenter: parent.verticalCenter
            x: heading.x + heading.width + (heading.width > 0 ? Theme.space.s4 : 0)
            width: Math.max(0, actionRow.x - x - Theme.space.s1)
        }

        Row {
            id: actionRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s1
        }
    }

    MeridianHairline {
        visible: root.divider
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }
}
