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

    /// An entry added while the Logbook is open enters from the top (NM-61): its key and
    /// stagger order; while `entranceActive` is false the key is only remembered.
    property string entranceKey: ""
    property int entranceOrder: 0
    property bool entranceActive: true
    property real _enter: 1
    property string _enteredKey: ""
    onEntranceKeyChanged: _enterOnce()
    function _enterOnce() {
        if (entranceKey === _enteredKey)
            return
        _enteredKey = entranceKey
        if (entranceKey.length === 0 || !MeridianMotionMemory.markSeen(entranceKey) || !entranceActive || Motion.reduced)
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
            target: row
            property: "_enter"
            to: 1
            duration: Motion.select
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.standard
        }
    }
    opacity: _enter
    transform: Translate { y: -Motion.riseContent * (1 - row._enter) }

    // A failure shakes the row once (NM-63).
    // A plain value set on creation: a binding would already hold the new state here.
    property string _previous: ""
    property int _failures: 0
    readonly property real shakeX: shaker.offset
    /// A run that just succeeded draws its check (NM-62) instead of showing it.
    property bool drawCompletion: false
    Component.onCompleted: {
        _previous = state_
        _enterOnce()
    }
    Timer {
        id: completionTimer
        interval: GitLamaLayout.landRingClose
        onTriggered: row.drawCompletion = false
    }
    onState_Changed: {
        drawCompletion = _previous === "running" && state_ === "succeeded" && !Motion.reduced
        if (drawCompletion)
            completionTimer.restart()
        if (_previous !== "failed" && state_ === "failed" && !Motion.reduced)
            failurePop.restart()
        if (shakeOnFailure && _previous !== "failed" && state_ === "failed")
            _failures += 1
        _previous = state_
    }
    MeridianShake {
        id: shaker
        visible: false
        trigger: row._failures
        strength: MeridianShake.Field
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
            // The spinner crossfades into the outcome's mark (NM-62); a failure pops in (NM-63).
            MeridianSwap {
                id: markSwap
                anchors.centerIn: parent
                swapKey: row.state_
                style: MeridianSwap.Fade
                Item {
                    implicitWidth: GitLamaLayout.logbookMarkIconSize
                    implicitHeight: GitLamaLayout.logbookMarkIconSize
                    MeridianSpinner {
                        visible: row.iconName.length === 0
                        anchors.centerIn: parent
                        size: GitLamaLayout.logbookMarkIconSize
                        color: row.tone
                        immediate: true
                    }
                    MeridianStrokeIcon {
                        visible: row.drawCompletion
                        anchors.centerIn: parent
                        name: "check"
                        extent: GitLamaLayout.logbookMarkIconSize
                        color: row.tone
                        drawn: row.drawCompletion
                        duration: GitLamaLayout.landRingClose
                    }
                    MeridianIcon {
                        id: markIcon
                        visible: row.iconName.length > 0 && !row.drawCompletion
                        anchors.centerIn: parent
                        name: row.iconName
                        extent: GitLamaLayout.logbookMarkIconSize
                        color: row.tone
                    }
                }
            }
            NumberAnimation {
                id: failurePop
                target: markIcon
                property: "scale"
                from: 0.8
                to: 1
                duration: Motion.pop.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.pop.curve
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
