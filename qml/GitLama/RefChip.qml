import QtQuick
import Meridian

// A compact Git reference label (GitLamaRefChip): the checked-out branch
// filled with `ink`, local branches `accent-soft`, tags notched in their
// own colours, remotes and the stash outlined. A branch and its aligned
// upstream share one chip.
Item {
    id: chip

    property string name
    /// head, local, remote, tag, stash or other.
    property string kind: "local"
    property string upstream
    property int lane: 0
    property bool onAccent: false
    property bool detached: false
    property int ahead: 0
    property int behind: 0

    readonly property bool selectedOverride: onAccent && (kind === "local" || kind === "remote" || kind === "tag")
    readonly property color fill: selectedOverride ? Theme.colors.inkOnAccentMuted
        : kind === "head" ? (onAccent ? Theme.colors.inkOnAccent : Theme.colors.ink)
        : kind === "local" ? Theme.colors.accentSoft
        : kind === "tag" ? GitColors.tagBg
        : "transparent"
    readonly property color ink: selectedOverride ? Theme.colors.accent
        : kind === "head" ? (onAccent ? Theme.colors.accent : Theme.colors.pane)
        : kind === "local" ? Theme.colors.accentInk
        : kind === "tag" ? GitColors.tagInk
        : onAccent ? Theme.colors.inkOnAccent : Theme.colors.inkMuted
    readonly property bool outlined: !onAccent && (kind === "remote" || kind === "stash")
    readonly property var laneColors: [Theme.colors.series1, Theme.colors.series2, Theme.colors.series3, Theme.colors.series4,
        Theme.colors.series5, Theme.colors.series6, Theme.colors.series7, Theme.colors.series8]
    readonly property real startPadding: kind === "tag" ? GitLamaLayout.tagPaddingStart : GitLamaLayout.refChipPaddingX

    readonly property bool hasIcon: kind === "remote" || kind === "stash" || detached
    readonly property bool hasDot: !detached && (kind === "head" || kind === "local" || kind === "tag")
    /// Everything but the name, which gives way when the chip is too wide.
    readonly property real fixedWidth: startPadding + GitLamaLayout.refChipPaddingX
        + (hasIcon ? GitLamaLayout.refIconSize + Theme.space.s2 : hasDot ? GitLamaLayout.refDotSize + Theme.space.s2 : 0)
        + (upstream.length > 0 ? Theme.space.s2 + upstreamRow.implicitWidth : 0)
        + (sync.visible ? Theme.space.s2 + sync.implicitWidth : 0)

    implicitWidth: Math.min(GitLamaLayout.refChipMaxWidth, fixedWidth + label.implicitWidth)
    implicitHeight: GitLamaLayout.refChipHeight

    Rectangle {
        id: plate
        anchors.fill: parent
        visible: chip.kind !== "tag"
        color: chip.fill
        radius: chip.kind === "stash" ? height / 2 : Theme.radius.sm
        border.width: chip.outlined ? 1 : 0
        border.color: Theme.colors.lineStrong
    }
    // A tag's notched plate.
    Canvas {
        anchors.fill: parent
        visible: chip.kind === "tag"
        property color color: chip.fill
        onColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const context = getContext("2d")
            context.reset()
            context.fillStyle = color
            context.beginPath()
            context.moveTo(GitLamaLayout.tagNotch, 0)
            context.lineTo(width, 0)
            context.lineTo(width, height)
            context.lineTo(GitLamaLayout.tagNotch, height)
            context.lineTo(0, height / 2)
            context.closePath()
            context.fill()
        }
    }

    Row {
        id: row
        x: chip.startPadding
        width: chip.width - chip.startPadding - GitLamaLayout.refChipPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s2

        MeridianIcon {
            visible: chip.hasIcon
            anchors.verticalCenter: parent.verticalCenter
            name: chip.detached ? "circle-dot" : chip.kind === "stash" ? "stash" : "cloud"
            iconSize: MeridianIcon.Small
            width: GitLamaLayout.refIconSize
            height: GitLamaLayout.refIconSize
            color: chip.ink
        }
        Rectangle {
            visible: chip.hasDot
            anchors.verticalCenter: parent.verticalCenter
            width: GitLamaLayout.refDotSize
            height: width
            radius: width / 2
            color: chip.kind === "head" ? chip.ink : chip.laneColors[chip.lane % chip.laneColors.length]
        }
        MeridianText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, chip.width - chip.fixedWidth)
            role: chip.kind === "head" ? MeridianText.Label : MeridianText.Caption
            fontWeight: chip.kind === "head" ? Font.DemiBold : -1
            text: chip.name
            color: chip.ink
            elide: Text.ElideMiddle
        }
        Row {
            id: upstreamRow
            visible: chip.upstream.length > 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s1
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Metrics.hairline
                height: GitLamaLayout.refPairDividerHeight
                color: Theme.colors.lineStrong
            }
            Item { width: Theme.space.s1; height: 1 }
            MeridianIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "cloud"
                iconSize: MeridianIcon.Small
                width: GitLamaLayout.refIconSize
                height: GitLamaLayout.refIconSize
                color: chip.kind === "head" ? Qt.alpha(chip.ink, GitLamaLayout.opacityHeadChipUpstream) : Theme.colors.inkMuted
            }
            MeridianText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, GitLamaLayout.refChipMaxWidth / 2)
                role: MeridianText.Caption
                text: chip.upstream
                color: chip.kind === "head" ? Qt.alpha(chip.ink, GitLamaLayout.opacityHeadChipUpstream) : Theme.colors.inkMuted
                elide: Text.ElideMiddle
            }
        }
        SyncBadge {
            id: sync
            visible: chip.upstream.length === 0 && (chip.ahead > 0 || chip.behind > 0)
            anchors.verticalCenter: parent.verticalCenter
            ahead: chip.ahead
            behind: chip.behind
            onAccent: chip.onAccent
        }
    }

    HoverHandler { id: hover }
    MeridianTooltip {
        shown: hover.hovered
        text: chip.upstream.length === 0 ? chip.name : chip.name + "\n" + chip.upstream
    }
}
