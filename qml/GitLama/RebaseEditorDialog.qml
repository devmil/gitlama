pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The interactive rebase plan (the Dart RebaseEditorDialog): every commit,
// oldest first, with its action. Rows reorder by their grip, by the arrow
// buttons or Ctrl+↑/↓; P R E S F D pick an action; dragging a row's merge
// handle onto another squashes it there. A squash or fixup indents under a
// drawn connector, a dropped subject is struck through, a reword asks for
// its new message.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var plan: ({})
    property bool autosquash: false
    property bool acknowledged: false
    property string selectedId: ""
    /// Bumped on every edit so bindings over the model re-evaluate.
    property int revision: 0
    readonly property int publishedCount: plan.publishedCount ?? 0
    readonly property bool valid: {
        void revision
        if (instructions.count === 0)
            return false
        const first = instructions.get(0).action
        if (first === "squash" || first === "fixup")
            return false
        for (let i = 0; i < instructions.count; ++i) {
            const item = instructions.get(i)
            if (item.action === "reword" && item.message.length === 0)
                return false
        }
        return publishedCount === 0 || acknowledged
    }
    readonly property var actionNames: ["pick", "reword", "edit", "squash", "fixup", "drop"]
    signal answered(int id, var edit)

    function actionLabel(action) {
        return L10n.t("rebaseAction" + action.charAt(0).toUpperCase() + action.slice(1))
    }
    function ask(id, payload) {
        promptId = id
        plan = payload
        autosquash = false
        acknowledged = false
        instructions.clear()
        for (const item of payload.instructions ?? [])
            instructions.append({ instructionId: item.id, action: item.action, oid: item.oid, subject: item.subject,
                                  published: item.published, message: item.message ?? "" })
        selectedId = instructions.count > 0 ? instructions.get(0).instructionId : ""
        revision++
        open()
    }
    function indexOf(instructionId) {
        for (let i = 0; i < instructions.count; ++i)
            if (instructions.get(i).instructionId === instructionId)
                return i
        return -1
    }
    function move(from, to) {
        if (to < 0 || to >= instructions.count || from === to)
            return
        instructions.move(from, to, 1)
        revision++
    }
    function setAction(index, action) {
        instructions.setProperty(index, "action", action)
        if (action !== "reword")
            instructions.setProperty(index, "message", "")
        revision++
    }
    /// Moves `draggedId` under `targetId` as a squash into it.
    // A drag source is untyped; the dragged row carries its instruction.
    function draggedInstruction(source) {
        return source.instructionId
    }

    function squashOnto(draggedId, targetId) {
        const from = indexOf(draggedId)
        if (from < 0 || draggedId === targetId)
            return
        const target = indexOf(targetId)
        const destination = from < target ? target : target + 1
        instructions.move(from, destination, 1)
        instructions.setProperty(destination, "action", "squash")
        instructions.setProperty(destination, "message", "")
        revision++
    }
    function runCommand(action) {
        const index = indexOf(selectedId)
        if (index >= 0)
            setAction(index, action)
    }
    function submit() {
        if (!valid)
            return
        const edited = []
        for (let i = 0; i < instructions.count; ++i) {
            const item = instructions.get(i)
            edited.push({ id: item.instructionId, action: item.action, message: item.message })
        }
        close()
        answered(promptId, { instructions: edited, acknowledgePublishedHistory: acknowledged, applyAutosquash: autosquash })
        promptId = -1
    }

    widthClass: MeridianDialog.Workflow
    title: L10n.t("rebaseEditorTitle")
    description: L10n.tn("rebaseEditorSummary", { branch: plan.currentBranch ?? "", onto: plan.onto ?? "" })
    submitDisabled: !valid
    onSubmitted: submit()
    onRejected: { answered(promptId, null); promptId = -1 }

    ListModel { id: instructions }

    // The app's rebase shortcuts act on the selected row.
    Shortcut { sequence: Commands.sequence("rebaseSquash"); enabled: dialog.opened && sequence.length > 0; onActivated: dialog.runCommand("squash") }
    Shortcut { sequence: Commands.sequence("rebaseFixup"); enabled: dialog.opened && sequence.length > 0; onActivated: dialog.runCommand("fixup") }
    Shortcut { sequence: Commands.sequence("rebaseReword"); enabled: dialog.opened && sequence.length > 0; onActivated: dialog.runCommand("reword") }
    Shortcut { sequence: Commands.sequence("rebaseDrop"); enabled: dialog.opened && sequence.length > 0; onActivated: dialog.runCommand("drop") }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6

        MeridianBanner {
            visible: (dialog.plan.conflicts ?? 0) > 0
            width: parent.width
            tone: MeridianBanner.Warning
            message: L10n.tn("rebaseConflictsExpected", { count: dialog.plan.conflicts ?? 0 })
        }
        Column {
            width: parent.width
            spacing: Theme.space.s3
            MeridianText {
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: L10n.tn("rebaseInstructionCount", { count: instructions.count })
            }
            ListView {
                id: list
                width: parent.width
                height: Math.min(contentHeight, GitLamaLayout.rebaseInstructionListMaxHeight)
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                model: instructions
                MeridianWheelScroll { flickable: list }
                C.ScrollBar.vertical: MeridianScrollBar {}
                moveDisplaced: Transition {
                    NumberAnimation { property: "y"; duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve }
                }
                move: Transition {
                    NumberAnimation { property: "y"; duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve }
                }
                delegate: Item {
                    id: row
                    required property int index
                    required property string instructionId
                    required property string action
                    required property string oid
                    required property string subject
                    required property bool published
                    required property string message
                    readonly property bool joined: action === "squash" || action === "fixup"
                    readonly property bool dropped: action === "drop"
                    width: ListView.view.width
                    height: card.height + Theme.space.s2
                    z: grip.drag.active ? 2 : 1

                    function keyAction(event) {
                        const modifier = (event.modifiers & Qt.ControlModifier) || (event.modifiers & Qt.MetaModifier)
                        if (modifier && event.key === Qt.Key_Up) {
                            dialog.move(row.index, row.index - 1)
                            return true
                        }
                        if (modifier && event.key === Qt.Key_Down) {
                            dialog.move(row.index, row.index + 1)
                            return true
                        }
                        if (modifier || (event.modifiers & Qt.AltModifier))
                            return false
                        const action = ({ p: "pick", r: "reword", e: "edit", s: "squash", f: "fixup", d: "drop" })[event.text.toLowerCase()]
                        if (action === undefined)
                            return false
                        dialog.setAction(row.index, action)
                        return true
                    }

                    // Dropping another row's merge handle here squashes it
                    // into this commit.
                    DropArea {
                        id: squashTarget
                        anchors.fill: card
                        keys: ["gitlama/rebase-instruction"]
                        onEntered: drag => drag.accepted = drag.source !== null && dialog.draggedInstruction(drag.source) !== row.instructionId
                        onDropped: drop => dialog.squashOnto(dialog.draggedInstruction(drop.source), row.instructionId)
                    }

                    Rectangle {
                        id: card
                        width: parent.width
                        height: content.height
                        radius: Theme.radius.lg
                        color: squashTarget.containsDrag ? Theme.colors.accentSoft : Theme.colors.paneAlt
                        Behavior on color { ColorAnimation { duration: Motion.quick } }
                        FocusScope {
                            id: rowFocus
                            anchors.fill: parent
                            activeFocusOnTab: true
                            onActiveFocusChanged: if (activeFocus) dialog.selectedId = row.instructionId
                            Keys.onPressed: event => event.accepted = row.keyAction(event)
                        }
                        MeridianFocusRing { target: card; shown: rowFocus.activeFocus; targetRadius: Theme.radius.lg }

                        // The connector from the commit above into a squash.
                        Canvas {
                            id: connector
                            property real progress: row.joined ? 1 : 0
                            Behavior on progress { NumberAnimation { duration: GitLamaLayout.laneDrawRow; easing.type: Easing.OutCubic } }
                            width: GitLamaLayout.rebaseIndent
                            height: parent.height
                            visible: progress > 0
                            onProgressChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                ctx.strokeStyle = Theme.colors.accent
                                ctx.lineWidth = Metrics.hairline
                                const h = height
                                const w = width
                                // Draw the path up to `progress` of its length.
                                const steps = 24
                                const end = Math.round(steps * progress)
                                ctx.beginPath()
                                ctx.moveTo(0.5, 0)
                                for (let i = 1; i <= end; ++i) {
                                    const t = i / steps
                                    if (t <= 0.5) {
                                        ctx.lineTo(0.5, h * t)
                                    } else {
                                        const u = (t - 0.5) * 2
                                        // Quadratic from (0, h/2) via (0, .75h) to (w, .75h).
                                        const x = 2 * (1 - u) * u * 0 + u * u * w
                                        const y = (1 - u) * (1 - u) * h * 0.5 + 2 * (1 - u) * u * h * 0.75 + u * u * h * 0.75
                                        ctx.lineTo(Math.max(0.5, x), y)
                                    }
                                }
                                ctx.stroke()
                            }
                        }

                        Column {
                            id: content
                            property real indent: row.joined ? GitLamaLayout.rebaseIndent : Theme.space.s4
                            Behavior on indent { NumberAnimation { duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve } }
                            x: indent
                            width: card.width - indent - Theme.space.s4
                            bottomPadding: row.action === "reword" ? Theme.space.s4 : 0
                            Item {
                                width: parent.width
                                height: Theme.size.row
                                Item {
                                    id: grip
                                    readonly property alias drag: gripDrag
                                    width: Theme.size.controlSmall
                                    height: Theme.size.controlSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                    MeridianIcon { anchors.centerIn: parent; name: "grip-vertical"; iconSize: MeridianIcon.Small; color: Theme.colors.inkMuted }
                                    HoverHandler { id: gripHover; cursorShape: Qt.OpenHandCursor }
                                    MeridianTooltip { text: L10n.t("rebaseDragToReorder"); shown: gripHover.hovered && !gripDrag.active }
                                    // Reorders by the row's place under the pointer.
                                    DragHandler {
                                        id: gripDrag
                                        target: null
                                        yAxis.enabled: true
                                        xAxis.enabled: false
                                        cursorShape: Qt.ClosedHandCursor
                                        onCentroidChanged: {
                                            if (!active)
                                                return
                                            const point = grip.mapToItem(list.contentItem, centroid.position.x, centroid.position.y)
                                            const target = list.indexAt(10, point.y)
                                            if (target >= 0 && target !== row.index)
                                                dialog.move(row.index, target)
                                        }
                                    }
                                }
                                MeridianSelect {
                                    id: actionSelect
                                    x: grip.width + Theme.space.s2
                                    anchors.verticalCenter: parent.verticalCenter
                                    fixedWidth: GitLamaLayout.rebaseActionWidth
                                    animateValue: true
                                    label: L10n.t("rebaseEditorTitle")
                                    values: dialog.actionNames
                                    value: row.action
                                    valueLabel: v => dialog.actionLabel(v)
                                    onActivated: v => dialog.setAction(row.index, v)
                                }
                                MeridianText {
                                    id: oidText
                                    x: actionSelect.x + actionSelect.width + Theme.space.s4
                                    anchors.verticalCenter: parent.verticalCenter
                                    role: MeridianText.CodeSm
                                    color: Theme.colors.inkMuted
                                    text: row.oid.substring(0, 8)
                                }
                                Item {
                                    id: subjectBox
                                    x: oidText.x + oidText.width + Theme.space.s4
                                    width: tools.x - x - (badge.visible ? badge.width + 2 * Theme.space.s3 : 0)
                                    height: parent.height
                                    property real strike: row.dropped ? 1 : 0
                                    Behavior on strike { NumberAnimation { duration: Motion.quick } }
                                    MeridianText {
                                        id: subjectText
                                        width: Math.min(implicitWidth, parent.width)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.subject
                                        opacity: 1 - (1 - GitLamaLayout.opacityIgnoredRow) * subjectBox.strike
                                    }
                                    // The strike ends with the (elided) subject, not the row.
                                    Rectangle {
                                        visible: subjectBox.strike > 0
                                        anchors.verticalCenter: subjectText.verticalCenter
                                        width: subjectText.width * subjectBox.strike
                                        height: Metrics.hairline
                                        color: Theme.colors.inkMuted
                                    }
                                }
                                MeridianCount {
                                    id: badge
                                    visible: row.published
                                    x: tools.x - width - Theme.space.s3
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: L10n.t("rebasePublishedBadge")
                                }
                                Row {
                                    id: tools
                                    x: parent.width - width
                                    anchors.verticalCenter: parent.verticalCenter
                                    // Drag onto another row to squash into it.
                                    Item {
                                        id: squashHandle
                                        readonly property string instructionId: row.instructionId
                                        width: Theme.size.controlSmall
                                        height: Theme.size.controlSmall
                                        Drag.active: squashDrag.active
                                        Drag.keys: ["gitlama/rebase-instruction"]
                                        Drag.source: squashHandle
                                        Drag.hotSpot.x: width / 2
                                        Drag.hotSpot.y: height / 2
                                        MeridianIcon { anchors.centerIn: parent; name: "git-merge"; color: Theme.colors.inkMuted }
                                        HoverHandler { id: squashHover; cursorShape: Qt.OpenHandCursor }
                                        MeridianTooltip { text: L10n.t("rebaseDragToSquash"); shown: squashHover.hovered && !squashDrag.active }
                                        DragHandler {
                                            id: squashDrag
                                            target: squashHandle
                                            onActiveChanged: {
                                                if (active) {
                                                    squashHandle.parent = list
                                                    return
                                                }
                                                squashHandle.Drag.drop()
                                                squashHandle.parent = tools
                                                squashHandle.x = 0
                                                squashHandle.y = 0
                                            }
                                        }
                                        Rectangle {
                                            visible: squashDrag.active
                                            anchors.left: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: dragLabel.implicitWidth + 2 * Theme.space.s4
                                            height: dragLabel.implicitHeight + 2 * Theme.space.s4
                                            radius: Theme.radius.lg
                                            color: Theme.colors.raised
                                            MeridianShadow { anchors.fill: parent; layers: Theme.shadows.float; radius: parent.radius; z: -1 }
                                            MeridianText { id: dragLabel; anchors.centerIn: parent; text: L10n.t("rebaseDragToSquash") }
                                        }
                                    }
                                    MeridianIconButton {
                                        iconName: "arrow-up"
                                        text: L10n.t("rebaseMoveUp")
                                        controlSize: MeridianButton.Small
                                        enabled: row.index > 0
                                        onClicked: dialog.move(row.index, row.index - 1)
                                    }
                                    MeridianIconButton {
                                        iconName: "arrow-down"
                                        text: L10n.t("rebaseMoveDown")
                                        controlSize: MeridianButton.Small
                                        enabled: row.index < instructions.count - 1
                                        onClicked: dialog.move(row.index, row.index + 1)
                                    }
                                    MeridianIconButton {
                                        id: moreButton
                                        iconName: "more"
                                        text: L10n.t("toolbarMore")
                                        onClicked: {
                                            actionMenu.items = dialog.actionNames.map(name => ({ title: dialog.actionLabel(name), value: name,
                                                                                                 checked: name === row.action }))
                                            actionMenu.show(moreButton, 0, moreButton.height)
                                        }
                                        CommandMenu {
                                            id: actionMenu
                                            onSelected: value => dialog.setAction(row.index, value)
                                        }
                                    }
                                }
                            }
                            MeridianTextField {
                                visible: row.action === "reword"
                                width: parent.width
                                placeholderText: L10n.t("rebaseReplacementMessage")
                                Accessible.name: L10n.t("rebaseReplacementMessage")
                                text: row.message
                                onTextEdited: {
                                    instructions.setProperty(row.index, "message", text)
                                    dialog.revision++
                                }
                            }
                        }
                    }
                }
            }
        }
        Column {
            width: parent.width
            spacing: Theme.space.s4
            MeridianCheckbox {
                width: parent.width
                text: L10n.t("rebaseAutosquash")
                description: L10n.t("rebaseAutosquashHint")
                checked: dialog.autosquash
                onToggled: dialog.autosquash = checked
            }
            MeridianCheckbox {
                visible: dialog.publishedCount > 0
                width: parent.width
                text: L10n.t("rebasePublishedWarning")
                description: L10n.tn("rebasePublishedNote", { count: dialog.publishedCount })
                checked: dialog.acknowledged
                onToggled: dialog.acknowledged = checked
            }
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            text: L10n.t("rebaseStart")
            variant: MeridianButton.Primary
            enabled: dialog.valid
            onClicked: dialog.submit()
        }
    ]
}
