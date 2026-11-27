pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// One list of the Changes pane: its header with
// the count, Discard (unstaged only), Stage or Unstage selected and Stage
// or Unstage all; then the files. Click selects, Ctrl/Cmd adds, Shift
// extends, double-click moves the file to the other list, Space moves the
// selection, Ctrl/Cmd+A selects every file.
Item {
    id: owner

    /// "unstaged" or "staged".
    required property string side
    required property string title
    /// A RowModel of {key, path, status, partial, conflicted, untracked, selected, pending}.
    required property var model
    property var paneState: ({})
    readonly property bool unstaged: side === "unstaged"
    /// The files shown (folder rows of a tree do not count).
    readonly property int shown: unstaged ? (paneState.unstagedShown ?? 0) : (paneState.stagedShown ?? 0)
    readonly property int total: unstaged ? (paneState.unstagedTotal ?? 0) : (paneState.stagedTotal ?? 0)
    readonly property int selectedCount: unstaged ? (paneState.selectedUnstaged ?? 0) : (paneState.selectedStaged ?? 0)
    readonly property bool selectedDiscardable: unstaged && paneState.selectedUnstagedDiscardable === true
    readonly property bool selectedCleanOnly: unstaged && paneState.selectedUnstagedCleanOnly === true
    readonly property bool selectedAllPending: unstaged
        ? (paneState.selectedUnstagedAllPending === true)
        : (paneState.selectedStagedAllPending === true)
    readonly property bool filtering: paneState.filtering === true
    readonly property bool busy: paneState.busy === true
    /// The row the Shift range starts from.
    property int anchor: -1

    /// The list shows folders (Store.app appearance changes*Mode).
    readonly property bool tree: (unstaged ? Store.appearance.changesUnstagedMode : Store.appearance.changesStagedMode) === "tree"
    function setTree(value) {
        Store.app.updateAppearance(unstaged ? { changesUnstagedMode: value ? "tree" : "list" } : { changesStagedMode: value ? "tree" : "list" })
    }

    // Dragging files to the other list: the drag
    // label follows the pointer over the window; dropping on the other
    // list stages or unstages them.
    /// Whether the current drag carries the whole selection or one key.
    property bool draggingSelection: false
    property string draggingKey: ""
    function startDrag(selection, key, count, item, position) {
        const window = owner.Window.contentItem
        dragProxy.parent = window
        dragProxy.selection = selection
        dragProxy.key = key
        dragProxy.count = count
        draggingSelection = selection
        draggingKey = key
        dragProxy.side = side
        moveDrag(item, position)
        dragProxy.visible = true
        dragProxy.Drag.active = true
    }
    /// The row dragged after a long press, or null.
    property Item longDragRow: null
    function startLongDrag(row, position) {
        longDragRow = row
        list.interactive = false
        if (row.actsOnSelection)
            startDrag(true, "", owner.selectedCount, row, position)
        else
            startDrag(false, row.key, 1, row, position)
    }
    function endLongDrag() {
        longDragRow = null
        list.interactive = true
        endDrag()
    }
    function moveDrag(item, position) {
        const at = item.mapToItem(dragProxy.parent, position.x, position.y)
        dragProxy.x = at.x + Theme.space.s3
        dragProxy.y = at.y + Theme.space.s3
    }
    function endDrag() {
        if (!dragProxy.Drag.active)
            return
        dragProxy.Drag.drop()
        dragProxy.Drag.active = false
        dragProxy.visible = false
        draggingSelection = false
        draggingKey = ""
    }
    // The label under the pointer, lifted (MeridianLift).
    Item {
        id: dragProxy
        objectName: "changes-drag-label"
        property bool selection: false
        property string key: ""
        property int count: 0
        property string side: ""
        visible: false
        z: 1000
        width: dragLift.implicitWidth
        height: dragLift.implicitHeight
        Drag.keys: ["gitlama/changes"]
        Drag.source: owner
        Drag.dragType: Drag.Internal
        MeridianLift {
            id: dragLift
            lifted: dragProxy.visible
            radius: Theme.radius.md
            Rectangle {
                implicitWidth: dragLabel.implicitWidth + 2 * Theme.space.s4
                implicitHeight: dragLabel.implicitHeight + 2 * Theme.space.s3
                radius: Theme.radius.md
                color: Theme.colors.raised
                MeridianText {
                    id: dragLabel
                    anchors.centerIn: parent
                    role: MeridianText.Label
                    text: dragProxy.side === "unstaged"
                        ? L10n.tn("changesDragStageCount", { count: dragProxy.count })
                        : L10n.tn("changesDragUnstageCount", { count: dragProxy.count })
                }
            }
        }
    }
    // Files dragged from the other list land here.
    DropArea {
        anchors.fill: parent
        keys: ["gitlama/changes"]
        onEntered: drag => drag.accepted = drag.source !== owner
        onDropped: drop => owner.receiveDrop(drop.source) && drop.accept()
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.md
            color: "transparent"
            border.width: 2 * Metrics.hairline
            border.color: Theme.colors.accent
            visible: parent.containsDrag
        }
    }
    function dragPayload() { return { selection: dragProxy.selection, key: dragProxy.key } }
    // The drag source is another ChangesSection, seen dynamically.
    function receiveDrop(source) {
        if (!source || source === owner || source.dragPayload === undefined)
            return false
        const payload = source.dragPayload()
        if (payload.selection)
            Store.changes.stageSelectedFiles(source.side)
        else if (payload.key.length > 0)
            Store.changes.stageFiles(source.side, [payload.key])
        return true
    }
    function selectRow(index, modifiers) {
        const row = model.get(index)
        if (!row)
            return
        // Selecting a folder selects its files; only its chevron folds it.
        if (row.directory) {
            Store.changes.selectFolder(side, row.path)
            anchor = index
            list.currentIndex = index
            return
        }
        if (modifiers & Qt.ShiftModifier && anchor >= 0) {
            Store.changes.selectRange(side, anchor, index)
        } else if (modifiers & (Qt.ControlModifier | Qt.MetaModifier)) {
            Store.changes.toggleSelect(side, row.key)
            anchor = index
        } else {
            Store.changes.select(side, [row.key])
            anchor = index
            Store.sidebar.selectPane("changes")
            Store.history.select(row.path)
        }
        list.currentIndex = index
    }

    /// The file actions this list performs.
    readonly property var fileActionHost: ({
        capabilities: ["stage", "unstage", "inspectChanges", "createPatch", "openExternally", "revealInFileBrowser", "copyPath", "discard", "clean",
            "addToGitignore", "blame", "fileHistory", "folderHistory"],
        reasons: ({}),
        inspectionReason: (paneState.headObjectId ?? null) === null ? L10n.t("fileActionNoCommit") : null,
        busy: busy,
        allowStagingWhileBusy: paneState.canQueue === true,
    })

    /// Opens the menu of row `index` at `x`, `y` of `item`: the selection's
    /// actions first when the row belongs to a multiple selection.
    function showFileMenu(index, item, x, y) {
        const row = model.get(index)
        if (!row)
            return
        fileMenu.target = row
        if (row.directory) {
            fileMenu.showFor({
                source: "changesFolder",
                path: row.path,
                exists: (row.descendantCount ?? 0) > 0,
                staged: !unstaged,
                discardable: row.discardable === true,
                untracked: row.untracked === true,
            }, null, fileActionHost, item, x, y)
            return
        }
        const multi = row.selected === true && owner.selectedCount >= 2
        fileMenu.showFor({
            source: unstaged ? "unstagedFile" : "stagedFile",
            path: row.path,
            exists: true,
            staged: !unstaged,
            discardable: row.discardable === true,
            untracked: row.untracked === true,
        }, multi ? {
            count: owner.selectedCount,
            staged: !unstaged,
            clean: owner.selectedDiscardable ? owner.selectedCleanOnly : null,
        } : null, fileActionHost, item, x, y)
    }

    // ---------------------------------------------------------------- motion

    // What the pane passes on from the Changes workflows (ChangesPane): each move names the
    // list its files leave, their keys and the one file that flies to the other list (NH-4).
    property int mutationSequence: 0
    property string mutationSource: ""
    property var movingKeys: []
    property string flightKey: ""
    /// The last commit in this repository: the staged rows leave as it does.
    property int commitSequence: 0
    property var _leavingSet: ({})
    property var _movingSet: ({})
    property bool _commitLeaving: false
    property int _seenCommit: -1
    property int _arrivals: 0
    /// Rows still fading out; the empty state waits for them.
    property int leavingRows: 0
    onMutationSequenceChanged: {
        const leaving = {}
        const moving = {}
        for (let i = 0; i < movingKeys.length; ++i) {
            const key = movingKeys[i]
            moving[key] = true
            if (mutationSource === side)
                leaving[key] = true
        }
        _leavingSet = leaving
        _movingSet = moving
        _arrivals = 0
    }
    onCommitSequenceChanged: {
        if (!unstaged && _seenCommit >= 0 && commitSequence > _seenCommit)
            _commitLeaving = true
        _seenCommit = commitSequence
    }
    /// Whether the row `key` the list just removed leaves visibly (fading and collapsing):
    /// a committed staged file, or a file moving to the other list.
    function leaves(key) {
        const leaving = _commitLeaving || _leavingSet[key] === true
        if (leaving)
            Qt.callLater(owner._settleLeaving)
        return leaving
    }
    function _settleLeaving() {
        _commitLeaving = false
        _leavingSet = ({})
    }
    /// Whether the row `key` the list just added came from the other list.
    function arrives(key) {
        return mutationSource.length > 0 && mutationSource !== side && _movingSet[key] === true
    }
    function nextArrival() {
        return _arrivals++
    }
    /// Records row `key`'s place and image before it moves to the other list.
    function captureEntry(key) {
        const item = list.itemAtIndex(model.indexOf(key))
        if (!item)
            return false
        // qmllint disable missing-property
        item.capture()
        // qmllint enable missing-property
        return true
    }
    /// Whether a file at `path` arriving here would land in view.
    function willShow(key, path) {
        if (model.indexOf(key) >= 0)
            return false
        let index = 0
        for (let i = 0; i < model.count(); ++i) {
            const row = model.get(i)
            if (row && (row.path ?? "") < path)
                index = i + 1
        }
        const top = index * Theme.size.row
        return top + Theme.size.row > list.contentY && top < list.contentY + list.height
    }
    /// The path of row `key`, or "".
    function pathOf(key) {
        const row = model.get(model.indexOf(key))
        return row ? (row.path ?? "") : ""
    }

    // A failed stage or unstage shakes its button: the selection's or the list's.
    property int _selectedFailures: 0
    property int _allFailures: 0
    function showActionFailure(all) {
        if (all)
            _allFailures += 1
        else
            _selectedFailures += 1
    }
    MeridianShake { id: selectedShake; trigger: owner._selectedFailures; width: 0; height: 0 }
    MeridianShake { id: allShake; trigger: owner._allFailures; width: 0; height: 0 }

    Component.onCompleted: {
        Store.changesSections[side] = owner
        _seenCommit = commitSequence
    }
    // Development screenshots: `dragFile:<index>` drags row `index` of the
    // unstaged list onto the staged one (`hold` keeps it over the target).
    Connections {
        target: Store
        function onScreenshotStepRequested(name, argument) {
            if (name !== "dragFile" || !owner.unstaged)
                return
            const parts = argument.split(":")
            const row = owner.model.get(Number(parts[0]))
            const other = Store.changesSections["staged"]
            if (!row || !other)
                return
            owner.startDrag(false, row.key, 1, owner, Qt.point(owner.width / 2, 20))
            owner.moveDrag(other, Qt.point(other.width / 2, other.height / 2))
            if (parts[1] !== "hold")
                Qt.callLater(owner.endDrag)
        }
    }
    /// Development screenshots: builds row `index`'s menu and runs `action` of it.
    function runFileAction(index, action) {
        showFileMenu(index, owner, 10, 10)
        fileMenu.close()
        console.log("file menu:", JSON.stringify(fileMenu.shownItems.map(item => item.separator ? "-" : item.header !== undefined ? "#" + item.header : item.title + (item.enabled === false ? "(off)" : ""))))
        if (action.length > 0)
            fileMenu.run(action, false)
    }
    FileActionMenu {
        id: fileMenu
        property var target: null
        run: (action, selection) => {
            const folder = target.directory === true
            const path = target.path
            switch (action) {
            case "stage":
            case "unstage":
                if (folder)
                    Store.changes.stageFolder(owner.side, path)
                else if (selection)
                    Store.changes.stageSelectedFiles(owner.side)
                else
                    Store.changes.stageFiles(owner.side, [target.key])
                return
            case "inspectChanges":
                Store.actions.showLineSelection(owner.side, target.key); return
            case "createPatch": {
                if (folder) {
                    Store.actions.showPatchDialog({ kind: "folder", side: owner.side, path: path }, "create")
                    return
                }
                if (selection) {
                    Store.actions.showPatchDialog({ kind: "selection" }, "create")
                    return
                }
                const paths = []
                for (const candidate of [target.source ?? "", target.path])
                    if (candidate.length > 0 && paths.indexOf(candidate) < 0)
                        paths.push(candidate)
                Store.actions.showPatchDialog({ kind: "files", side: owner.side, paths: paths }, "create")
                return
            }
            case "discard":
            case "clean":
                if (folder)
                    Store.changes.discardFolder(path)
                else if (selection)
                    Store.changes.discardSelectedFiles()
                else
                    Store.changes.discardFiles([target.key])
                return
            case "copyPath":
                Store.actions.copyText(path, L10n.t("filePathCopied")); return
            case "openExternally":
                Store.workflows.openTool("editor", path); return
            case "revealInFileBrowser":
                Store.workflows.openTool("fileManager", path); return
            case "addToGitignore":
                Store.workflows.ignorePath(path, folder, target.untracked !== true); return
            case "blame":
                Store.actions.inspectWorkingFile(path, "blame", false); return
            case "fileHistory":
                Store.actions.inspectWorkingFile(path, "history", false); return
            case "folderHistory":
                Store.actions.inspectWorkingFile(path, "history", true); return
            }
        }
    }

    clip: true

    // The header.
    Item {
        id: sectionHeader
        width: parent.width
        height: Theme.size.islandHeader
        readonly property bool wide: width >= 460

        Row {
            x: Theme.space.s5
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s2
            MeridianText {
                anchors.verticalCenter: parent.verticalCenter
                role: MeridianText.BodyStrong
                text: owner.title
                Accessible.role: Accessible.Heading
            }
            MeridianCount {
                anchors.verticalCenter: parent.verticalCenter
                label: String(owner.shown)
                tone: owner.filtering ? MeridianCount.Neutral : MeridianCount.Quiet
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s1

            // List or tree: a segmented control, one icon button when narrow.
            MeridianSegmented {
                visible: sectionHeader.width >= 350
                anchors.verticalCenter: parent.verticalCenter
                objectName: "changes-" + owner.side + "-mode"
                label: owner.title
                controlSize: MeridianButton.Small
                segments: [{ value: "list", icon: "list-view", tooltip: L10n.t("changesListView") },
                           { value: "tree", icon: "tree-view", tooltip: L10n.t("changesTreeView") }]
                value: owner.tree ? "tree" : "list"
                onActivated: value => owner.setTree(value === "tree")
            }
            MeridianIconButton {
                visible: sectionHeader.width < 350
                anchors.verticalCenter: parent.verticalCenter
                text: owner.tree ? L10n.t("changesListView") : L10n.t("changesTreeView")
                iconName: owner.tree ? "list-view" : "tree-view"
                controlSize: MeridianButton.Small
                onClicked: owner.setTree(!owner.tree)
            }
            Item { width: Theme.space.s4 - parent.spacing; height: 1 }

            MeridianIconButton {
                visible: owner.unstaged
                text: L10n.t("discardSelected")
                iconName: "trash"
                controlSize: MeridianButton.Small
                iconColorOverride: Theme.colors.danger
                enabled: !owner.busy && owner.selectedCount > 0
                    && (owner.paneState.disabled ?? []).indexOf("discardChanges") < 0
                onClicked: Store.changes.discardSelectedFiles()
            }
            MeridianIconButton {
                visible: owner.unstaged
                text: owner.filtering ? L10n.t("discardShown") : L10n.t("discardAll")
                iconName: "brush-cleaning"
                controlSize: MeridianButton.Small
                iconColorOverride: Theme.colors.danger
                enabled: !owner.busy && owner.shown > 0
                onClicked: Store.changes.discardAll()
            }
            Rectangle {
                visible: owner.unstaged
                width: Metrics.hairline
                height: Theme.size.controlSmall
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.colors.line
            }
            Item { visible: owner.unstaged; width: Theme.space.s3; height: 1 }
            MeridianIconButton {
                text: owner.unstaged ? L10n.t("stageSelected") : L10n.t("unstageSelected")
                iconName: owner.unstaged ? "arrow-down" : "arrow-up"
                transform: Translate { x: selectedShake.offset }
                controlSize: MeridianButton.Small
                enabled: (!owner.busy || owner.paneState.canQueue === true) && owner.selectedCount > 0
                onClicked: Store.changes.stageSelectedFiles(owner.side)
            }
            MeridianIconButton {
                visible: !sectionHeader.wide
                text: owner.unstaged ? (owner.filtering ? L10n.t("stageShown") : L10n.t("stageAll"))
                                     : (owner.filtering ? L10n.t("unstageShown") : L10n.t("unstageAll"))
                iconName: owner.unstaged ? "stage-all" : "unstage-all"
                transform: Translate { x: allShake.offset }
                controlSize: MeridianButton.Small
                enabled: !owner.busy && owner.shown > 0
                onClicked: Store.changes.stageAll(owner.side)
            }
            MeridianButton {
                visible: sectionHeader.wide
                readonly property string allLabel: owner.unstaged
                    ? (owner.filtering ? L10n.t("stageShown") : L10n.t("stageAll"))
                    : (owner.filtering ? L10n.t("unstageShown") : L10n.t("unstageAll"))
                text: owner.filtering ? (owner.unstaged ? L10n.t("stageShortShown") : L10n.t("unstageShortShown")) : allLabel
                tooltip: allLabel
                iconName: owner.unstaged ? "stage-all" : "unstage-all"
                transform: Translate { x: allShake.offset }
                controlSize: MeridianButton.Small
                variant: owner.unstaged ? MeridianButton.Secondary : MeridianButton.Quiet
                enabled: !owner.busy && owner.shown > 0
                onClicked: Store.changes.stageAll(owner.side)
            }
        }
    }

    ListView {
        id: list
        objectName: "changes-" + owner.side + "-list"
        anchors.top: sectionHeader.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        leftMargin: Theme.space.s2
        rightMargin: Theme.space.s2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: owner.model
        reuseItems: true
        keyNavigationEnabled: false
        activeFocusOnTab: true
        currentIndex: -1

        MeridianWheelScroll { flickable: list }
        C.ScrollBar.vertical: MeridianScrollBar {}

        onActiveFocusChanged: if (activeFocus) Store.changes.focus(owner.side)

        Keys.onPressed: event => {
            const count = owner.model.count()
            if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                const next = Math.max(0, Math.min(count - 1, list.currentIndex + (event.key === Qt.Key_Down ? 1 : -1)))
                owner.selectRow(next, event.modifiers & Qt.ShiftModifier)
                list.positionViewAtIndex(next, ListView.Contain)
                event.accepted = true
            } else if (event.key === Qt.Key_Space) {
                Store.changes.toggleFocused()
                event.accepted = true
            } else if (event.key === Qt.Key_A && (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                Store.changes.selectAll(owner.side)
                event.accepted = true
            } else if (event.key === Qt.Key_Delete && owner.unstaged) {
                Store.changes.discardSelection()
                event.accepted = true
            }
        }

        // A row that leaves (a committed file, a file moving away) fades and collapses; one that
        // comes from the other list enters, or lands from its flight (NH-4) with a tint.
        delegate: Item {
            id: slot
            // A pooled row is hidden until it is reused (it could stay drawn at its old place).
            ListView.onPooled: visible = false
            required property int index
            required property var model
            readonly property string key: model.key ?? ""
            /// The move this row arrived with, or 0.
            property int arrival: 0
            property int arrivalOrder: 0
            readonly property bool flown: arrival > 0 && key === owner.flightKey
            width: list.width - list.leftMargin - list.rightMargin
            height: leaving.implicitHeight

            function capture() {
                travel.capture()
            }

            ListView.onAdd: {
                if (owner.arrives(key)) {
                    arrivalOrder = owner.nextArrival()
                    arrival = owner.mutationSequence
                }
            }
            ListView.onRemove: {
                if (owner.leaves(key)) {
                    slot.ListView.delayRemove = true
                    owner.leavingRows += 1
                    leaving.start()
                }
            }
            ListView.onReused: {
                leaving.reset()
                visible = true
                arrival = 0
            }

            // Pressed anywhere: a long press drags the row's files (the grip drags at once).
            PointHandler {
                id: pointer
                onPointChanged: if (owner.longDragRow === fileRow) owner.moveDrag(fileRow, point.position)
                onActiveChanged: if (!active && owner.longDragRow === fileRow) owner.endLongDrag()
            }

            MeridianRemovingRow {
                id: leaving
                width: slot.width
                autoStart: false
                onRemoved: {
                    owner.leavingRows -= 1
                    slot.ListView.delayRemove = false
                }
                MeridianEntrance {
                    implicitWidth: slot.width
                    entranceKey: slot.arrival > 0 && !slot.flown
                        ? "stage-arrival|" + owner.side + "|" + slot.key + "|" + slot.arrival : ""
                    order: slot.arrivalOrder
                    MeridianTravel {
                        id: travel
                        implicitWidth: slot.width
                        travelKey: "changes-file|" + slot.key
                        radius: Theme.radius.sm
                FileRow {
                            id: fileRow
                            readonly property int index: slot.index
                            readonly property var model: slot.model
                            readonly property string key: slot.key
                            readonly property bool pending: model.pending === true
                            width: slot.width
                            path: model.label ?? model.path ?? ""
                            sourceHint: Labels.renameSource(model.source ?? "", model.path ?? "")
                            depth: model.depth ?? 0
                            folder: model.directory === true
                            folderIcon: true
                            expanded: model.expanded === true
                            showDirectory: !owner.tree
                            status: model.status ?? ""
                            partial: model.partial === true
                            selected: model.selected === true
                            opacity: pending ? 0.5
                                : (owner.draggingSelection ? model.selected === true : owner.draggingKey === key)
                                    ? GitLamaLayout.opacityDragSource : 1
                            onLongPressed: if (!folder && gripEnabled) owner.startLongDrag(fileRow, pointer.point.position)
                            readonly property bool gripEnabled: !pending && (!owner.busy || owner.paneState.canQueue === true)
                            activeFocusOnTab: false
                            onClicked: {
                                list.forceActiveFocus()
                                owner.selectRow(fileRow.index, fileRow.modifiers)
                            }
                            onDoubleClicked: if (!folder) Store.changes.stageFiles(owner.side, [fileRow.key])
                            onFolderToggled: Store.changes.toggleFolder(owner.side, model.path)
                            onContextMenuRequested: (x, y) => owner.showFileMenu(fileRow.index, fileRow, x, y)
                            // Whether an action on this row affects the multiple selection.
                            readonly property bool actsOnSelection: model.selected === true && owner.selectedCount > 1
                            readonly property bool discardShown: owner.unstaged
                                && (actsOnSelection ? owner.selectedDiscardable : model.discardable === true)
                            readonly property bool cleanOnly: actsOnSelection ? owner.selectedCleanOnly : model.untracked === true
                            readonly property bool actionPending: actsOnSelection ? owner.selectedAllPending : pending
                            trailing: folder ? null : rowActions
                            Component {
                                id: rowActions
                                Row {
                                    spacing: Theme.space.s1
                                    // Stage (or unstage) and discard on hover.
                                    MeridianIconButton {
                                        visible: rowHover.hovered || fileRow.activeFocus
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: fileRow.actsOnSelection
                                            ? (owner.unstaged ? L10n.t("stageSelected") : L10n.t("unstageSelected"))
                                            : (owner.unstaged ? L10n.t("stageFile") : L10n.t("unstageFile"))
                                        iconName: owner.unstaged ? "arrow-down" : "arrow-up"
                                        controlSize: MeridianButton.Small
                                        enabled: (!owner.busy || owner.paneState.canQueue === true)
                                            && !fileRow.actionPending
                                        onClicked: fileRow.actsOnSelection
                                            ? Store.changes.stageSelectedFiles(owner.side)
                                            : Store.changes.stageFiles(owner.side, [fileRow.key])
                                    }
                                    MeridianIconButton {
                                        visible: (rowHover.hovered || fileRow.activeFocus) && fileRow.discardShown
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: fileRow.cleanOnly
                                            ? (fileRow.actsOnSelection ? L10n.t("cleanSelected") : L10n.t("cleanFile"))
                                            : (fileRow.actsOnSelection ? L10n.t("discardSelected") : L10n.t("discardFile"))
                                        iconName: "undo"
                                        controlSize: MeridianButton.Small
                                        enabled: !owner.busy
                                        onClicked: fileRow.actsOnSelection
                                            ? Store.changes.discardSelectedFiles()
                                            : Store.changes.discardFiles([fileRow.key])
                                    }
                                    // Queued work spins; otherwise the grip drags the file to
                                    // the other list.
                                    MeridianSpinner {
                                        visible: fileRow.pending
                                        anchors.verticalCenter: parent.verticalCenter
                                        Accessible.name: L10n.t("stagingPendingFile")
                                    }
                                    Item {
                                        id: grip
                                        visible: !fileRow.pending
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.size.iconSmall + 2 * Theme.space.s2
                                        height: width
                                        MeridianIcon {
                                            anchors.centerIn: parent
                                            name: "grip-vertical"
                                            iconSize: MeridianIcon.Small
                                            color: Theme.colors.inkMuted
                                        }
                                        HoverHandler { id: gripHover; cursorShape: Qt.OpenHandCursor }
                                        MeridianTooltip {
                                            text: L10n.t("dragChangeToOtherList")
                                            shown: gripHover.hovered && !gripDrag.active
                                        }
                                        DragHandler {
                                            id: gripDrag
                                            target: null
                                            enabled: !owner.busy || owner.paneState.canQueue === true
                                            onActiveChanged: {
                                                if (active) {
                                                    if (fileRow.actsOnSelection)
                                                        owner.startDrag(true, "", owner.selectedCount, grip, centroid.position)
                                                    else
                                                        owner.startDrag(false, fileRow.key, 1, grip, centroid.position)
                                                } else {
                                                    owner.endDrag()
                                                }
                                            }
                                            onCentroidChanged: if (active) owner.moveDrag(grip, centroid.position)
                                        }
                                    }
                                }
                            }
                            HoverHandler { id: rowHover }
                        }
                    }
                }
            }
            MeridianAttention {
                anchors.fill: parent
                trigger: slot.flown ? slot.arrival : 0
                memoryKey: "stage-flight|" + slot.key
            }
        }

        MeridianEmptyState {
            visible: owner.shown === 0 && owner.leavingRows === 0
            anchors.fill: parent
            compact: true
            title: owner.filtering && owner.total > 0 ? L10n.t("changesFilterNoMatches") : L10n.t("stagingEmpty")
        }
    }
}
