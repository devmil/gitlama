import QtQuick

// What an empty, loading or failed list or screen says (Flutter:
// MeridianEmptyState). `title` says what is true ("No messages match
// “invoice”"), `message` one sentence on what to do, and one action goes in
// `action`. No mascots, no emoji, no exclamation marks.
//
// `progress` is the loading state of the same place: a spinner replaces the
// icon after 150ms and the title says what is loading. The parts enter one
// after the other, once.
Item {
    id: root

    property string title
    property string message
    property string iconName
    /// First-run and welcome screens: the `display` style.
    property bool headline: false
    /// The in-pane size for small islands and detail panes.
    property bool compact: false
    property bool progress: false
    /// 0..1 adds a determinate bar under the title; negative hides it.
    property real progressValue: -1
    default property alias action: actionSlot.data

    implicitWidth: Math.min(360, column.implicitWidth)
    implicitHeight: column.implicitHeight + 2 * (compact ? Theme.space.s6 : Theme.space.s9)

    Column {
        id: column
        anchors.centerIn: parent
        width: Math.min(360, root.width - 2 * Theme.space.s6)
        spacing: root.compact ? Theme.space.s3 : Theme.space.s4

        Item {
            id: art
            property int stage: 0
            width: parent.width
            height: visible ? 24 : 0
            visible: root.iconName.length > 0 || root.progress
            opacity: 0
            MeridianIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.progress
                name: root.iconName
                extent: 24
                color: Theme.colors.inkMuted
            }
            MeridianSpinner {
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.progress
                size: 24
                color: Theme.colors.inkMuted
            }
        }
        MeridianText {
            id: titleText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            role: root.headline ? MeridianText.Display : root.compact ? MeridianText.Body : MeridianText.Heading
            text: root.title
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            opacity: 0
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
        MeridianProgressBar {
            width: parent.width * 0.6
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.progress && root.progressValue >= 0
            value: root.progressValue
            track: true
            persistent: true
        }
        MeridianText {
            id: messageText
            width: parent.width
            visible: text.length > 0
            horizontalAlignment: Text.AlignHCenter
            role: root.compact ? MeridianText.Caption : MeridianText.Body
            color: Theme.colors.inkMuted
            text: root.message
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            opacity: 0
        }
        Item {
            id: actionHolder
            width: parent.width
            height: actionSlot.childrenRect.height
            visible: actionSlot.children.length > 0
            opacity: 0
            Item {
                id: actionSlot
                width: childrenRect.width
                height: childrenRect.height
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // One staggered entrance, then rest (MM-67). Reduce motion fades all
    // parts together; a zero duration lands on full opacity.
    ParallelAnimation {
        id: entrance
        running: true
        SequentialAnimation {
            PauseAnimation { duration: Motion.staggerDelay(0) }
            NumberAnimation { target: art; property: "opacity"; to: 1; duration: Motion.fade(Motion.layout) }
        }
        SequentialAnimation {
            PauseAnimation { duration: Motion.staggerDelay(1) }
            NumberAnimation { target: titleText; property: "opacity"; to: 1; duration: Motion.fade(Motion.layout) }
        }
        SequentialAnimation {
            PauseAnimation { duration: Motion.staggerDelay(2) }
            NumberAnimation { target: messageText; property: "opacity"; to: 1; duration: Motion.fade(Motion.layout) }
        }
        SequentialAnimation {
            PauseAnimation { duration: Motion.staggerDelay(3) }
            NumberAnimation { target: actionHolder; property: "opacity"; to: 1; duration: Motion.fade(Motion.layout) }
        }
    }
}
