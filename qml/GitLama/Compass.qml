pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The repository context in the window bar (GitLamaCompass): repository /
// branch, then the state (conflicts, changed files, sync) or a running
// operation; a progress rule along the bottom edge. It opens the
// repository's details.
Item {
    id: compass

    property string repository
    /// The checked-out branch, or the detached label.
    property string branch
    property bool detached: false
    property int ahead: 0
    property int behind: 0
    property int dirty: 0
    property int conflicts: 0
    /// A running operation's name ("Fetching…"), or "".
    property string operation
    /// The operation with its phase and completion; replaces the text in
    /// place.
    property string operationDetail
    /// 0..1, or -1 while it cannot tell.
    property real progress: -1
    property bool activeProgress: false
    property int syncSequence: 0
    property bool syncChanged: false
    property bool compact: false
    signal showDetails()

    /// Changes appeared while the Compass was on screen (NM-04).
    property bool _dirtyPopIn: false
    property bool _shown: false
    property bool _showConflictCount: conflicts > 0
    property int _previousDirty: dirty
    property int _previousConflicts: conflicts

    Component.onCompleted: _shown = true
    onDirtyChanged: {
        _dirtyPopIn = _shown && _previousDirty === 0 && dirty > 0
        _previousDirty = dirty
    }
    onConflictsChanged: {
        if (conflicts > 0) {
            conflictCollapse.stop()
            _showConflictCount = true
        } else if (_previousConflicts > 0) {
            conflictCollapse.restart()
        }
        _previousConflicts = conflicts
    }
    Timer {
        id: conflictCollapse
        interval: GitLamaLayout.conflictCountCollapseDelay
        onTriggered: if (compass.conflicts === 0) compass._showConflictCount = false
    }

    readonly property real minWidth: compact ? GitLamaLayout.compassCompactMinWidth : GitLamaLayout.compassMinWidth
    implicitHeight: GitLamaLayout.compassHeight
    implicitWidth: Math.min(GitLamaLayout.compassMaxWidth,
                            Math.max(minWidth, row.implicitWidth + Theme.space.s5 + Theme.space.s3))
    Behavior on implicitWidth {
        enabled: compass._shown
        NumberAnimation { duration: Motion.layout; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
    }

    Accessible.role: Accessible.Button
    Accessible.name: L10n.t("compassSemantics", [compass.repository, compass.branch.length > 0 ? compass.branch : L10n.t("detachedHead"),
                                                 compass.ahead, compass.behind, compass.dirty, compass.conflicts])
    Accessible.onPressAction: compass.showDetails()

    MeridianShadow {
        anchors.fill: parent
        layers: Theme.shadows.pane
        radius: height / 2
    }

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: height / 2
        color: Theme.colors.pane
        border.width: 1
        border.color: hover.hovered ? Theme.colors.lineStrong : Theme.clear(Theme.colors.lineStrong)
        Behavior on border.color { ColorAnimation { duration: Motion.hoverFor(hover.hovered) } }
        clip: true
        // Only the sweep needs the rounded clip of a layer. A permanent layer drew the text
        // through a texture, which a fractional position or scale left blurred.
        layer.enabled: glintBand.sweeping

        CompassGlint {
            id: glintBand
            anchors.fill: parent
            sequence: compass.syncSequence
            changed: compass.syncChanged
        }

        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.space.s5
            width: parent.width - Theme.space.s5 - Theme.space.s3
            spacing: 0

            Item {
                id: identity
                height: parent.height
                width: Math.max(0, row.width - stateSwap.width - Theme.space.s5)
                implicitWidth: (compass.compact ? 0 : repositoryText.implicitWidth + separator.implicitWidth)
                    + branchIcon.width + Theme.space.s2 + branchText.implicitWidth
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    MeridianText {
                        id: repositoryText
                        visible: !compass.compact
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, GitLamaLayout.compassRepositoryMaxWidth,
                                        Math.max(0, identity.width * 3 / 7))
                        role: MeridianText.BodyStrong
                        color: Theme.colors.ink
                        text: compass.repository
                    }
                    MeridianText {
                        id: separator
                        visible: !compass.compact
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.colors.inkFaint
                        text: "  /  "
                    }
                    MeridianIcon {
                        id: branchIcon
                        anchors.verticalCenter: parent.verticalCenter
                        name: compass.detached ? "circle-dot" : "branch"
                        iconSize: MeridianIcon.Small
                        color: Theme.colors.accentInk
                    }
                    Item { width: Theme.space.s2; height: 1 }
                    // A checkout swaps the branch name with a rise (NM-02).
                    MeridianSwapText {
                        id: branchText
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, Math.min(contentWidth, identity.width - x))
                        text: compass.branch.length > 0 ? compass.branch : L10n.t("detachedHead")
                        role: MeridianText.Body
                        fontWeight: 500
                        color: Theme.colors.accentInk
                    }
                }
            }
            Item { width: Theme.space.s5; height: 1 }
            // The state and a running operation swap with a rise (NM-01).
            MeridianSwap {
                id: stateSwap
                anchors.verticalCenter: parent.verticalCenter
                swapKey: compass.operation.length === 0 ? "state" : "op:" + compass.operation
                alignment: 1
                Item {
                    implicitWidth: compass.operation.length === 0 ? stateRow.implicitWidth : Math.min(operationText.implicitWidth, GitLamaLayout.compassBranchMaxWidth)
                    implicitHeight: GitLamaLayout.compassHeight
                    CompassState {
                        id: stateRow
                        visible: compass.operation.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        ahead: compass.ahead
                        behind: compass.behind
                        dirty: compass.dirty
                        conflicts: compass.conflicts
                        showConflictCount: compass._showConflictCount
                        dirtyPopIn: compass._dirtyPopIn
                    }
                    MeridianText {
                        id: operationText
                        visible: compass.operation.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        role: MeridianText.Label
                        color: Theme.colors.ink
                        text: compass.operationDetail.length > 0 ? compass.operationDetail : compass.operation
                    }
                }
            }
        }

        CompassRule {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            active: compass.operation.length > 0 || compass.activeProgress
            progress: compass.progress
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: compass.showDetails() }
    MeridianTooltip {
        shown: hover.hovered
        text: L10n.t("repositoryDetailsTitle")
    }
}
