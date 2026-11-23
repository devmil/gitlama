pragma ComponentBehavior: Bound
import QtQuick
import Meridian
import GitLamaNative

// One History graph row: its lanes and node, the
// references as chips, the subject, then author, hash and date at the end.
// Clicking selects (Ctrl/Cmd adds), double-clicking checks the commit out.
Item {
    id: entry

    required property int index
    required property string objectId
    required property bool loading
    required property bool lit
    required property bool incomingLit
    required property var graph
    required property int occupiedLane
    required property string subject
    required property bool worktree
    required property string author
    required property string avatarHash
    required property real authorTime
    required property var chips
    required property var overflow
    required property bool detached
    required property bool current
    required property bool selected
    required property bool compared
    required property bool searchMatch

    property real metadataLeft: width
    property real authorWidth: 132
    property real hashWidth: 72
    property real dateWidth: 84
    property bool lightingActive: false
    property bool queryActive: false
    property string dateFormat: "iso"
    property bool selectedHere: false
    property bool copied: false

    readonly property real graphClipRight: Math.max(0, metadataLeft - Theme.space.s5)
    readonly property real contentStart: Math.min(
        Math.ceil(GitLamaLayout.graphLaneOrigin + occupiedLane * GitLamaLayout.laneWidth + GitLamaLayout.graphNodeInkRadius + Theme.space.s4),
        graphClipRight)
    readonly property real contentAvailable: Math.max(0, Math.min(width, metadataLeft - contentStart - 12))
    readonly property bool wip: graph && (graph.shape === 5 || graph.shape === 6)

    // What a screen reader says.
    Accessible.role: Accessible.ListItem
    Accessible.selected: selected
    Accessible.name: loading ? "" : [
        L10n.tn("historyRowSemantics", {
            subject: subject,
            author: author,
            objectId: wip ? "" : objectId,
            date: authorTime > 0 ? Qt.formatDateTime(new Date(authorTime * 1000), Qt.ISODate) : "",
            lane: (graph ? graph.lane : 0) + 1,
            references: (chips ?? []).map(chip => chip.label).join(", "),
            overflow: overflow ? overflow.count : 0,
        })].concat(current ? [L10n.t("historyHeadReference")] : []).join(", ")
    readonly property real textOpacity: !lightingActive || lit ? 1 : GitLamaLayout.opacityUnlitText
    readonly property bool shownSelected: selected || selectedHere
    readonly property var laneColors: [Theme.colors.series1, Theme.colors.series2, Theme.colors.series3, Theme.colors.series4,
        Theme.colors.series5, Theme.colors.series6, Theme.colors.series7, Theme.colors.series8]

    signal activated(string objectId, bool toggle)
    signal doubleActivated(string objectId)
    signal contextMenuRequested(string objectId, real x, real y)
    signal copyRequested(string value)

    // Rows outside a search fade (NM-32).
    opacity: queryActive && !searchMatch && !loading ? GitLamaLayout.opacityUnlit : 1
    Behavior on opacity { NumberAnimation { duration: entry.opacity < 1 ? GitLamaLayout.laneDim : Motion.hoverOut } }

    Rectangle {
        id: fill
        anchors.fill: parent
        radius: Theme.radius.sm
        color: entry.compared && !entry.shownSelected ? Theme.colors.accentSoft
            : entry.shownSelected ? Theme.colors.accentSoft
            : hover.hovered && !entry.loading ? Theme.colors.paneHover
            : Theme.clear(Theme.colors.paneHover)
        Behavior on color { ColorAnimation { duration: entry.shownSelected ? Motion.select : Motion.hoverFor(hover.hovered) } }
    }

    // Rows still loading breathe as skeletons (NM-38).
    Item {
        visible: entry.loading
        anchors.fill: parent
        Rectangle {
            x: GitLamaLayout.graphLaneOrigin - GitLamaLayout.graphCommitRadius
            anchors.verticalCenter: parent.verticalCenter
            width: GitLamaLayout.graphCommitRadius * 2
            height: width
            radius: width / 2
            color: Theme.colors.lineStrong
            opacity: skeleton.value
        }
        Rectangle {
            x: GitLamaLayout.historySkeletonTextStart
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(GitLamaLayout.historySkeletonTextMaxWidth, entry.metadataLeft - GitLamaLayout.historySkeletonTextGap))
            height: GitLamaLayout.historySkeletonBarHeight
            radius: height / 2
            color: Theme.colors.lineStrong
            opacity: skeleton.value
        }
        Rectangle {
            x: entry.metadataLeft + Theme.space.s5
            anchors.verticalCenter: parent.verticalCenter
            width: GitLamaLayout.historyMetaSkeletonWidth
            height: GitLamaLayout.historySkeletonBarHeight
            radius: height / 2
            color: Theme.colors.lineStrong
            opacity: skeleton.value
        }
        QtObject {
            id: skeleton
            property real value: 0.6
            readonly property SequentialAnimation pulse: SequentialAnimation {
                running: entry.loading && !Theme.reducedMotion
                loops: Animation.Infinite
                NumberAnimation { target: skeleton; property: "value"; from: 0.6; to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { target: skeleton; property: "value"; from: 0.3; to: 0.6; duration: 700; easing.type: Easing.InOutSine }
            }
        }
    }

    GraphRow {
        visible: !entry.loading
        anchors.fill: parent
        row: entry.graph
        clipRight: entry.graphClipRight
        laneColors: entry.laneColors
        wipColor: Theme.colors.inkMuted
        conflictColor: Theme.colors.attention
        nodeBackground: entry.shownSelected || entry.compared ? fill.color : Theme.colors.pane
        strongInk: Theme.colors.inkOnAccent
        faintColor: Theme.colors.inkFaint
        addedColor: Theme.colors.successBg
        lightingActive: entry.lightingActive
        lit: entry.lit
        incomingLit: entry.incomingLit
    }

    // References and subject; text dims with the row's lanes (NH-3).
    Row {
        visible: !entry.loading
        x: entry.contentStart
        width: entry.contentAvailable
        height: parent.height
        spacing: Theme.space.s2
        clip: true
        opacity: entry.textOpacity

        RefChip {
            visible: entry.detached
            anchors.verticalCenter: parent.verticalCenter
            name: entry.objectId.substring(0, 10)
            kind: "head"
            detached: true
        }
        Repeater {
            model: entry.chips
            delegate: Row {
                id: chipRow
                required property var modelData
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                spacing: Theme.space.s1
                RefChip {
                    anchors.verticalCenter: parent.verticalCenter
                    name: chipRow.modelData.label
                    kind: chipRow.modelData.kind
                    upstream: chipRow.modelData.upstream ?? ""
                    lane: entry.graph ? entry.graph.lane : 0
                    ahead: chipRow.modelData.ahead
                    behind: chipRow.modelData.behind
                    checks: chipRow.modelData.checks ?? ""
                    TapHandler {
                        onTapped: entry.activated(entry.objectId, false)
                    }
                }
                // A branch's pull request follows its chip.
                Loader {
                    active: !!chipRow.modelData.pull
                    visible: active
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: PullRequestChip { pull: chipRow.modelData.pull }
                }
            }
        }
        MeridianCount {
            visible: entry.overflow !== null && entry.overflow !== undefined
            anchors.verticalCenter: parent.verticalCenter
            label: visible ? "+" + entry.overflow.count : ""
            HoverHandler { id: overflowHover }
            MeridianTooltip {
                shown: overflowHover.hovered
                text: entry.overflow ? entry.overflow.names : ""
            }
        }
        MeridianText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - x)
            text: entry.worktree && entry.graph
                  ? Labels.worktreeSubject(entry.graph.shape === 6, entry.graph.wipChanged, entry.graph.wipStaged)
                  : entry.subject
            font.italic: entry.wip
            color: entry.wip ? Theme.colors.inkMuted : Theme.colors.ink
            elide: Text.ElideRight
        }
    }

    // Author, hash and date.
    Row {
        visible: !entry.loading
        x: entry.metadataLeft + Theme.space.s5
        height: parent.height
        spacing: Theme.space.s5
        opacity: entry.textOpacity

        Item {
            width: entry.authorWidth
            height: parent.height
            AuthorAvatar {
                id: avatar
                visible: entry.author.length > 0
                anchors.verticalCenter: parent.verticalCenter
                author: entry.author
                avatarHash: entry.avatarHash
            }
            MeridianText {
                x: avatar.visible ? avatar.width + Theme.space.s3 : 0
                width: parent.width - x
                anchors.verticalCenter: parent.verticalCenter
                role: MeridianText.Caption
                text: entry.author.split("<")[0].trim()
                color: Theme.colors.inkMuted
                elide: Text.ElideRight
                HoverHandler { id: authorHover }
                TapHandler { onTapped: entry.copyRequested(entry.author) }
                MeridianTooltip { shown: authorHover.hovered; text: entry.author }
            }
        }
        MeridianSwapText {
            width: entry.hashWidth
            anchors.verticalCenter: parent.verticalCenter
            role: entry.copied ? MeridianText.Caption : MeridianText.CodeSm
            text: entry.copied ? L10n.t("historyHashCopied") : entry.objectId.substring(0, 10)
            color: Theme.colors.inkMuted
            HoverHandler { id: hashHover }
            TapHandler {
                onTapped: {
                    entry.copyRequested(entry.objectId)
                    entry.copied = true
                    copiedTimer.restart()
                }
            }
            MeridianTooltip { shown: hashHover.hovered; text: entry.objectId }
            Timer { id: copiedTimer; interval: GitLamaLayout.copiedHold; onTriggered: entry.copied = false }
        }
        MeridianText {
            width: entry.dateWidth
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            role: MeridianText.Caption
            tabular: true
            text: Labels.historyDate(entry.authorTime, entry.dateFormat)
            color: Theme.colors.inkMuted
            HoverHandler { id: dateHover }
            TapHandler {
                onTapped: {
                    if (entry.authorTime)
                        entry.copyRequested(new Date(entry.authorTime * 1000).toISOString())
                }
            }
            MeridianTooltip {
                shown: dateHover.hovered && entry.authorTime > 0
                text: entry.authorTime > 0 ? new Date(entry.authorTime * 1000).toISOString() : ""
            }
        }
    }

    HoverHandler { id: hover }
    TapHandler {
        id: tap
        enabled: !entry.loading
        acceptedButtons: Qt.LeftButton
        onTapped: {
            const toggle = (tap.point.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) !== 0
            entry.activated(entry.objectId, toggle)
        }
        onDoubleTapped: {
            if (!entry.wip)
                entry.doubleActivated(entry.objectId)
        }
    }
    TapHandler {
        enabled: !entry.loading
        acceptedButtons: Qt.RightButton
        onTapped: point => entry.contextMenuRequested(entry.objectId, point.position.x, point.position.y)
    }
}
