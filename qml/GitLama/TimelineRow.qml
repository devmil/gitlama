pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// One row of a timeline: a state mark on a
// rail that runs through the rows, the verb and its target, the time and
// a metadata line; selected, its details reveal below on a state tint. A
// row that fails shakes once.
Item {
    id: row

    /// running, succeeded, warning, failed or cancelled.
    property string state_: "running"
    property string verb
    property string target
    property string metadata
    property string time
    property bool first: false
    property bool last: false
    property bool selected: false
    property bool shakeOnFailure: false
    /// The details, shown while selected.
    property Component details: null
    signal activated()

    readonly property color tone: ({ running: Theme.colors.accent, succeeded: Theme.colors.success, warning: Theme.colors.warning,
                                     failed: Theme.colors.danger, cancelled: Theme.colors.inkMuted })[state_] ?? Theme.colors.inkMuted
    readonly property string iconName: ({ succeeded: "check", warning: "triangle-alert", failed: "close", cancelled: "minus" })[state_] ?? ""

    implicitHeight: content.implicitHeight + 2 * Theme.space.s3
    Accessible.role: Accessible.ListItem
    Accessible.name: verb + (target.length > 0 ? " " + target : "") + ", " + metadata
    Accessible.selected: selected

    property string _previous: state_
    property real shakeX: 0
    onState_Changed: {
        if (shakeOnFailure && _previous !== "failed" && state_ === "failed" && !Motion.reduced)
            shake.restart()
        _previous = state_
    }
    SequentialAnimation {
        id: shake
        NumberAnimation { target: row; property: "shakeX"; to: 4; duration: Motion.shakeField / 6 }
        NumberAnimation { target: row; property: "shakeX"; to: -4; duration: Motion.shakeField / 3 }
        NumberAnimation { target: row; property: "shakeX"; to: 2; duration: Motion.shakeField / 4 }
        NumberAnimation { target: row; property: "shakeX"; to: 0; duration: Motion.shakeField / 4 }
    }

    // The selected and hovered fills sit under the rail.
    Rectangle {
        anchors.fill: parent
        color: row.selected ? Theme.colors.accentSoft : hover.hovered ? Theme.colors.paneHover : Theme.clear(Theme.colors.paneHover)
        Behavior on color { ColorAnimation { duration: Motion.hoverFor(hover.hovered) } }
    }
    Rectangle {
        id: rail
        x: Theme.space.s6 + (GitLamaLayout.logbookMarkSize - GitLamaLayout.logbookRailWidth) / 2
        y: row.first ? Theme.space.s3 + GitLamaLayout.logbookMarkSize / 2 : 0
        width: GitLamaLayout.logbookRailWidth
        height: parent.height - y - (row.last ? Theme.space.s3 + GitLamaLayout.logbookMarkSize / 2 : 0)
        color: row.state_ === "succeeded" ? Theme.colors.success : Theme.colors.line
        Behavior on color { ColorAnimation { duration: Motion.select } }
    }

    Item {
        id: content
        x: Theme.space.s6 + row.shakeX
        y: Theme.space.s3
        width: parent.width - 2 * Theme.space.s6
        implicitHeight: Math.max(mark.height, texts.implicitHeight)

        Rectangle {
            id: mark
            width: GitLamaLayout.logbookMarkSize
            height: width
            radius: width / 2
            color: Theme.colors.raised
            border.width: GitLamaLayout.logbookRailWidth
            border.color: row.state_ === "cancelled" ? Theme.colors.lineStrong : row.tone
            MeridianSpinner {
                visible: row.iconName.length === 0
                anchors.centerIn: parent
                size: GitLamaLayout.logbookMarkIconSize
                color: row.tone
                immediate: true
            }
            MeridianIcon {
                visible: row.iconName.length > 0
                anchors.centerIn: parent
                name: row.iconName
                extent: GitLamaLayout.logbookMarkIconSize
                color: row.tone
            }
        }
        Column {
            id: texts
            x: mark.width + Theme.space.s4
            width: parent.width - x
            Item {
                width: parent.width
                height: Math.max(heading.height, timeText.height)
                Row {
                    id: heading
                    width: parent.width - timeText.width - Theme.space.s3
                    height: verbText.height
                    spacing: Theme.space.s2
                    MeridianText {
                        id: verbText
                        width: Math.min(implicitWidth, heading.width)
                        role: MeridianText.BodyStrong
                        text: row.verb
                    }
                    MeridianText {
                        visible: row.target.length > 0
                        width: Math.max(0, heading.width - verbText.width - heading.spacing)
                        text: row.target
                    }
                }
                MeridianText {
                    id: timeText
                    x: parent.width - width
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: row.time
                }
            }
            MeridianText {
                visible: row.metadata.length > 0
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                maximumLineCount: 2
                text: row.metadata
            }
            MeridianReveal {
                width: parent.width
                shown: row.selected && row.details !== null
                Column {
                    width: texts.width
                    Item { width: 1; height: Theme.space.s3 }
                    Rectangle {
                        width: parent.width
                        height: detailLoader.height + 2 * Theme.space.s4
                        radius: Theme.radius.md
                        color: row.state_ === "warning" ? Theme.colors.warningBg : row.state_ === "failed" ? Theme.colors.dangerBg : Theme.colors.paneAlt
                        Loader {
                            id: detailLoader
                            x: Theme.space.s5
                            y: Theme.space.s4
                            width: parent.width - 2 * Theme.space.s5
                            active: row.selected && row.details !== null
                            sourceComponent: row.details
                        }
                    }
                }
            }
        }
    }
    HoverHandler { id: hover }
    TapHandler { onTapped: row.activated() }
}
