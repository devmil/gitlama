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
    /// A MeridianSelectionGlide paints this row's selection bar.
    property bool glided: false

    // ---------------------------------------------------------------- chips

    /// The chips shown: {key, chip, arrived, leaving}; leaving chips keep their old place.
    property var displayChips: []
    property string _chipsRow: ""
    property string _chipsSeen: ""
    onChipsChanged: _updateChips()
    onObjectIdChanged: _updateChips()
    onLoadingChanged: _updateChips()
    function _chipKey(chip) {
        return chip.kind + "|" + chip.label
    }
    function _updateChips() {
        const current = loading ? [] : (chips ?? [])
        if (current.length === 0 && displayChips.length === 0) {
            _chipsSeen = ""
            _chipsRow = objectId
            return
        }
        const seen = objectId + "\n" + JSON.stringify(current)
        if (seen === _chipsSeen)
            return
        _chipsSeen = seen
        const landing = motion !== null && motion.landingId === objectId
        const sameRow = (_chipsRow === objectId || landing) && !Motion.reduced
        const before = _chipsRow === objectId ? displayChips : []
        _chipsRow = objectId
        const shown = before.filter(item => !item.leaving).map(item => item.key)
        const next = current.map(chip => {
            const key = _chipKey(chip)
            return { key: key, chip: chip, arrived: sameRow && shown.indexOf(key) < 0, leaving: false }
        })
        if (sameRow) {
            const keys = next.map(item => item.key)
            before.forEach((item, index) => {
                if (keys.indexOf(item.key) < 0)
                    next.splice(Math.min(index, next.length), 0, { key: item.key, chip: item.chip, arrived: false, leaving: true })
            })
        }
        displayChips = next
    }
    function chipSettled(key) {
        // Later rebuilds show the chip at rest.
        for (const item of displayChips)
            if (item.key === key)
                item.arrived = false
    }
    function chipLeft(key) {
        displayChips = displayChips.filter(item => !(item.leaving && item.key === key))
            .map(item => ({ key: item.key, chip: item.chip, arrived: false, leaving: item.leaving }))
    }
    /// The graph's motion (HistoryMotion), or null.
    property var motion: null
    /// Each increase tints the row once: a commit made here (after `commitTintDelay`, once per
    /// commit) and a search match reached with next or previous (NM-33).
    property int flashTrigger: 0
    property int attentionTrigger: 0
    /// The row a transfer brought enters (NH-2): its key and stagger order, or "".
    property string entranceKey: ""
    property int entranceOrder: 0
    property real _enter: 1
    property string _enteredKey: ""
    Component.onCompleted: {
        _enterOnce()
        _updateChips()
    }
    onEntranceKeyChanged: _enterOnce()
    function _enterOnce() {
        if (entranceKey === _enteredKey)
            return
        _enteredKey = entranceKey
        if (entranceKey.length === 0 || !MeridianMotionMemory.markSeen(entranceKey) || Motion.reduced)
            return
        entrance.stop()
        _enter = 0
        entranceWait.duration = Motion.staggerDelay(entranceOrder)
        entrance.restart()
    }
    SequentialAnimation {
        id: entrance
        PauseAnimation { id: entranceWait }
        NumberAnimation {
            target: entry
            property: "_enter"
            to: 1
            duration: Motion.select
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.standard
        }
    }

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
    // Follows the lanes' lighting transition (NH-3).
    readonly property real textOpacity: GitLamaLayout.opacityUnlitText
        + (1 - GitLamaLayout.opacityUnlitText) * graphRow.rowLitness
    readonly property bool shownSelected: selected || selectedHere
    readonly property var laneColors: [Theme.colors.series1, Theme.colors.series2, Theme.colors.series3, Theme.colors.series4,
        Theme.colors.series5, Theme.colors.series6, Theme.colors.series7, Theme.colors.series8]

    signal activated(string objectId, bool toggle)
    signal doubleActivated(string objectId)
    signal contextMenuRequested(string objectId, real x, real y)
    signal copyRequested(string value)

    // Rows outside a search fade (NM-32).
    property real searchOpacity: queryActive && !searchMatch && !loading ? GitLamaLayout.opacityUnlit : 1
    Behavior on searchOpacity { NumberAnimation { duration: entry.searchOpacity < 1 ? GitLamaLayout.laneDim : Motion.hoverOut } }
    opacity: searchOpacity * _enter
    // A row inserted above slides this one from its old place (NH-1, NM-36); a row a
    // transfer brought rises into place.
    transform: [
        Translate { y: entry.motion ? -entry.motion.insertionShift(entry.index) * entry.height : 0 },
        Translate { y: Motion.riseContent * (1 - entry._enter) }
    ]

    Rectangle {
        id: fill
        anchors.fill: parent
        radius: Theme.radius.sm
        color: entry.compared && !entry.shownSelected ? Theme.colors.accentSoft
            : entry.shownSelected && entry.glided ? Theme.clear(Theme.colors.accentSoft)
            : entry.shownSelected ? Theme.colors.accentSoft
            : hover.hovered && !entry.loading ? Theme.colors.paneHover
            : Theme.clear(Theme.colors.paneHover)
        Behavior on color { ColorAnimation { duration: entry.shownSelected ? Motion.select : Motion.hoverFor(hover.hovered) } }
    }
    Loader {
        anchors.fill: parent
        active: entry.flashTrigger > 0
        sourceComponent: MeridianAttention {
            trigger: entry.flashTrigger
            memoryKey: "history-commit|" + entry.objectId
            delay: GitLamaLayout.commitTintDelay
        }
    }
    Loader {
        anchors.fill: parent
        active: entry.attentionTrigger > 0
        sourceComponent: MeridianAttention {
            trigger: entry.attentionTrigger
        }
    }

    // Rows still loading breathe as skeletons (NM-38).
    Loader {
        active: entry.loading
        visible: active
        anchors.fill: parent
        sourceComponent: Item {
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
                    running: entry.loading && !Theme.reducedMotion && Motion.loopsActive
                    loops: Animation.Infinite
                    NumberAnimation { target: skeleton; property: "value"; from: 0.6; to: 0.3; duration: Motion.skeletonPulse / 2; easing.type: Easing.InOutSine }
                    NumberAnimation { target: skeleton; property: "value"; from: 0.3; to: 0.6; duration: Motion.skeletonPulse / 2; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    GraphRow {
        id: graphRow
        visible: !entry.loading
        anchors.fill: parent
        opacity: entry.motion ? entry.motion.insertionOpacity(entry.index) : 1
        rowKey: entry.objectId
        row: entry.graph
        clipRight: entry.graphClipRight
        laneColors: entry.laneColors
        wipColor: Theme.colors.inkMuted
        conflictColor: Theme.colors.attention
        nodeBackground: entry.shownSelected && entry.glided ? Theme.colors.accentSoft
            : entry.shownSelected || entry.compared ? fill.color : Theme.colors.pane
        strongInk: Theme.colors.inkOnAccent
        faintColor: Theme.colors.inkFaint
        addedColor: Theme.colors.successBg
        lightingActive: entry.lightingActive
        lit: entry.lit
        incomingLit: entry.incomingLit
        // Lanes drawing in (NH-2, NH-7) and a new commit's node landing (NH-1).
        drawProgress: entry.motion ? entry.motion.drawProgress(entry.index) : 1
        landing: entry.motion !== null && entry.motion.landingId === entry.objectId
        ringClose: entry.motion ? entry.motion.ringClose : 0
        ringOpacity: entry.motion ? entry.motion.ringOpacity : 0
        core: entry.motion ? entry.motion.core : 0
        halo: entry.motion ? entry.motion.halo : 0
        // The lanes light or dim flowing down from the focused commit (NH-3).
        onLightingTransition: {
            lighting.stop()
            const timing = entry.motion ? entry.motion.lightingTiming(entry.index) : null
            if (timing === null) {
                graphRow.litBlend = 1
                return
            }
            graphRow.litBlend = 0
            lightingDelay.duration = timing.delay
            lightingFade.duration = timing.duration
            lighting.restart()
        }
        SequentialAnimation {
            id: lighting
            PauseAnimation { id: lightingDelay }
            NumberAnimation {
                id: lightingFade
                target: graphRow
                property: "litBlend"
                to: 1
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.standard
            }
        }
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

        Loader {
            active: entry.detached
            visible: active
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: RefChip {
                name: entry.objectId.substring(0, 10)
                kind: "head"
                detached: true
            }
        }
        // A chip that appears while the row shows pops in from `opacity-badge-leave-scale` on
        // `spring-pop`; one that goes fades and shrinks away (NM-35). A row shown fresh (scrolled
        // into view, recycled) shows its chips at rest, except the commit just made, whose
        // chips arrive with it.
        Repeater {
            model: entry.displayChips
            delegate: Item {
                id: chipSlot
                required property var modelData
                readonly property var chip: modelData.chip
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                implicitWidth: modelData.leaving ? leavingLoader.implicitWidth : chipRow.implicitWidth
                implicitHeight: chipRow.implicitHeight
                width: implicitWidth
                height: implicitHeight
                Row {
                    id: chipRow
                    visible: !chipSlot.modelData.leaving
                    spacing: Theme.space.s1
                    scale: chipSlot.popScale
                    RefChip {
                        anchors.verticalCenter: parent.verticalCenter
                        name: chipSlot.chip.label
                        kind: chipSlot.chip.kind
                        upstream: chipSlot.chip.upstream ?? ""
                        lane: entry.graph ? entry.graph.lane : 0
                        ahead: chipSlot.chip.ahead
                        behind: chipSlot.chip.behind
                        checks: chipSlot.chip.checks ?? ""
                        TapHandler {
                            onTapped: entry.activated(entry.objectId, false)
                        }
                    }
                    // A branch's pull request follows its chip.
                    Loader {
                        active: !!chipSlot.chip.pull
                        visible: active
                        anchors.verticalCenter: parent.verticalCenter
                        sourceComponent: PullRequestChip { pull: chipSlot.chip.pull }
                    }
                }
                property real popScale: 1
                NumberAnimation {
                    id: chipPop
                    target: chipSlot
                    property: "popScale"
                    from: Metrics.opacityBadgeLeaveScale
                    to: 1
                    duration: Motion.pop.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.pop.curve
                    onFinished: entry.chipSettled(chipSlot.modelData.key)
                }
                Component.onCompleted: if (modelData.arrived) chipPop.start()
                Loader {
                    id: leavingLoader
                    active: chipSlot.modelData.leaving
                    sourceComponent: MeridianRemovingRow {
                        axis: MeridianReveal.Horizontal
                        onRemoved: entry.chipLeft(chipSlot.modelData.key)
                        Row {
                            spacing: Theme.space.s1
                            RefChip {
                                anchors.verticalCenter: parent.verticalCenter
                                name: chipSlot.chip.label
                                kind: chipSlot.chip.kind
                                lane: entry.graph ? entry.graph.lane : 0
                                ahead: chipSlot.chip.ahead
                                behind: chipSlot.chip.behind
                            }
                        }
                    }
                }
            }
        }
        Loader {
            active: entry.overflow !== null && entry.overflow !== undefined
            visible: active
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: MeridianCount {
                label: entry.overflow ? "+" + entry.overflow.count : ""
                HoverHandler { id: overflowHover }
                MeridianTooltip {
                    shown: overflowHover.hovered
                    text: entry.overflow ? entry.overflow.names : ""
                }
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
        // A copied hash shows a drawn check and "Copied" for a moment (NM-34).
        Item {
            width: entry.hashWidth
            height: parent.height
            clip: true
            MeridianText {
                visible: !entry.copied
                anchors.verticalCenter: parent.verticalCenter
                role: MeridianText.CodeSm
                text: entry.objectId.substring(0, 10)
                color: Theme.colors.inkMuted
            }
            Loader {
                active: entry.copied
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: Row {
                    spacing: Theme.space.s1
                    MeridianStrokeIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        iconSize: MeridianIcon.Small
                        color: Theme.colors.inkMuted
                        drawn: entry.copied
                        duration: Metrics.successCheckDraw
                    }
                    MeridianText {
                        anchors.verticalCenter: parent.verticalCenter
                        role: MeridianText.Caption
                        text: L10n.t("historyHashCopied")
                        color: Theme.colors.inkMuted
                    }
                }
            }
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
                text: dateHover.hovered && entry.authorTime > 0 ? new Date(entry.authorTime * 1000).toISOString() : ""
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
