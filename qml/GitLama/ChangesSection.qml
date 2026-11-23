pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// One list of the Changes pane (the Dart ChangesSection): its header with
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
    readonly property bool filtering: paneState.filtering === true
    readonly property bool busy: paneState.busy === true
    /// The row the Shift range starts from.
    property int anchor: -1

    /// The list shows folders (Store.app appearance changes*Mode).
    readonly property bool tree: (unstaged ? Store.appearance.changesUnstagedMode : Store.appearance.changesStagedMode) === "tree"
    function setTree(value) {
        Store.app.updateAppearance(unstaged ? { changesUnstagedMode: value ? "tree" : "list" } : { changesStagedMode: value ? "tree" : "list" })
    }
    function keysOf(predicate) {
        const keys = []
        for (let i = 0; i < model.count(); ++i) {
            const row = model.get(i)
            if (!row.directory && predicate(row, i))
                keys.push(row.key)
        }
        return keys
    }
    function selectedKeys() { return keysOf(row => row.selected) }
    function rowsOf(keys) {
        const rows = []
        for (let i = 0; i < model.count(); ++i) {
            const row = model.get(i)
            if (!row.directory && keys.indexOf(row.key) >= 0)
                rows.push(row)
        }
        return rows
    }

    // Dragging files to the other list (the Dart _ChangesDrag): the drag
    // label follows the pointer over the window; dropping on the other
    // list stages or unstages them.
    function startDrag(keys, item, position) {
        const window = owner.Window.contentItem
        dragProxy.parent = window
        dragProxy.keys = keys
        dragProxy.side = side
        moveDrag(item, position)
        dragProxy.visible = true
        dragProxy.Drag.active = true
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
    }
    Rectangle {
        id: dragProxy
        objectName: "changes-drag-label"
        property var keys: []
        property string side: ""
        visible: false
        z: 1000
        width: dragLabel.implicitWidth + 2 * Theme.space.s4
        height: dragLabel.implicitHeight + 2 * Theme.space.s3
        radius: Theme.radius.md
        color: Theme.colors.pane
        border.width: Metrics.hairline
        border.color: Theme.colors.line
        Drag.keys: ["gitlama/changes"]
        Drag.source: owner
        Drag.dragType: Drag.Internal
        MeridianShadow { anchors.fill: parent; layers: Theme.shadows.float; radius: parent.radius; z: -1 }
        MeridianText {
            id: dragLabel
            anchors.centerIn: parent
            role: MeridianText.Label
            text: dragProxy.side === "unstaged"
                ? L10n.tn("changesDragStageCount", { count: dragProxy.keys.length })
                : L10n.tn("changesDragUnstageCount", { count: dragProxy.keys.length })
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
    function dragKeys() { return dragProxy.keys }
    // The drag source is another ChangesSection, seen dynamically.
    function receiveDrop(source) {
        if (!source || source === owner || source.dragKeys === undefined)
            return false
        const keys = source.dragKeys()
        if (keys.length > 0)
            Store.changes.stageFiles(source.side, keys)
        return true
    }
    function selectRow(index, modifiers) {
        const row = model.get(index)
        if (!row)
            return
        // Selecting a folder selects its files; only its chevron folds it.
        if (row.directory) {
            Store.changes.select(side, row.keys ?? [])
            anchor = index
            return
        }
        if (modifiers & Qt.ShiftModifier && anchor >= 0) {
            const from = Math.min(anchor, index), to = Math.max(anchor, index)
            Store.changes.select(side, keysOf((_, at) => at >= from && at <= to))
        } else if (modifiers & (Qt.ControlModifier | Qt.MetaModifier)) {
            const keys = selectedKeys()
            const at = keys.indexOf(row.key)
            if (at >= 0)
                keys.splice(at, 1)
            else
                keys.push(row.key)
            Store.changes.select(side, keys)
            anchor = index
        } else {
            Store.changes.select(side, [row.key])
            anchor = index
            Store.sidebar.selectPane("changes")
            Store.history.select(row.path)
        }
        list.currentIndex = index
    }

    /// The file actions this list performs (the Dart _ChangesActionHost).
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
        if (row.directory) {
            fileMenu.targets = [row]
            fileMenu.target = row
            fileMenu.showFor({
                source: "changesFolder",
                path: row.path,
                exists: (row.keys ?? []).length > 0,
                staged: !unstaged,
                discardable: row.discardable === true,
                untracked: row.untracked === true,
            }, null, fileActionHost, item, x, y)
            return
        }
        const selection = row.selected ? keysOf(candidate => candidate.selected).map(key => {
            for (let i = 0; i < model.count(); ++i) {
                const candidate = model.get(i)
                if (candidate.key === key)
                    return candidate
            }
            return null
        }).filter(candidate => candidate !== null) : []
        const discardable = selection.every(candidate => candidate.discardable === true)
        fileMenu.targets = selection.length >= 2 ? selection : [row]
        fileMenu.target = row
        fileMenu.showFor({
            source: unstaged ? "unstagedFile" : "stagedFile",
            path: row.path,
            exists: true,
            staged: !unstaged,
            discardable: row.discardable === true,
            untracked: row.untracked === true,
        }, selection.length >= 2 ? {
            count: selection.length,
            staged: !unstaged,
            clean: discardable ? selection.every(candidate => candidate.untracked === true) : null,
        } : null, fileActionHost, item, x, y)
    }

    Component.onCompleted: Store.changesSections[side] = owner
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
            owner.startDrag([row.key], owner, Qt.point(owner.width / 2, 20))
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
        property var targets: []
        run: (action, selection) => {
            const rows = selection ? targets : [target]
            const folder = target.directory === true
            const keys = folder ? (target.keys ?? []) : rows.map(row => row.key)
            const path = target.path
            switch (action) {
            case "stage":
            case "unstage":
                Store.changes.stageFiles(owner.side, keys); return
            case "inspectChanges":
                Store.actions.showLineSelection(owner.side, target.key); return
            case "createPatch": {
                if (folder) {
                    Store.actions.showPatchDialog({ kind: "keys", side: owner.side, keys: keys }, "create")
                    return
                }
                const paths = []
                for (const row of rows) {
                    for (const candidate of [row.source ?? "", row.path])
                        if (candidate.length > 0 && paths.indexOf(candidate) < 0)
                            paths.push(candidate)
                }
                Store.actions.showPatchDialog({ kind: "files", side: owner.side, paths: paths }, "create")
                return
            }
            case "discard":
            case "clean":
                Store.changes.discardFiles(keys); return
            case "copyPath":
                Store.actions.copyText(path, L10n.t("filePathCopied")); return
            case "openExternally":
                Store.workflows.openTool("editor", path); return
            case "revealInFileBrowser":
                Store.workflows.openTool("fileManager", path); return
            case "addToGitignore":
                Store.workflows.ignorePath(path, folder, rows.some(row => row.untracked !== true)); return
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
                onClicked: Store.changes.discardFiles(owner.selectedKeys())
            }
            MeridianIconButton {
                visible: owner.unstaged
                text: owner.filtering ? L10n.t("discardShown") : L10n.t("discardAll")
                iconName: "brush-cleaning"
                controlSize: MeridianButton.Small
                iconColorOverride: Theme.colors.danger
                enabled: !owner.busy && owner.shown > 0
                onClicked: Store.changes.discardFiles(owner.keysOf(() => true))
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
                controlSize: MeridianButton.Small
                enabled: (!owner.busy || owner.paneState.canQueue === true) && owner.selectedCount > 0
                onClicked: Store.changes.stageFiles(owner.side, owner.selectedKeys())
            }
            MeridianIconButton {
                visible: !sectionHeader.wide
                text: owner.unstaged ? (owner.filtering ? L10n.t("stageShown") : L10n.t("stageAll"))
                                     : (owner.filtering ? L10n.t("unstageShown") : L10n.t("unstageAll"))
                iconName: owner.unstaged ? "stage-all" : "unstage-all"
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
                Store.changes.select(owner.side, owner.keysOf(() => true))
                event.accepted = true
            } else if (event.key === Qt.Key_Delete && owner.unstaged) {
                Store.changes.discardSelection()
                event.accepted = true
            }
        }

        delegate: FileRow {
            id: fileRow
            required property int index
            required property var model
            readonly property string key: model.key ?? ""
            readonly property bool pending: model.pending === true
            width: list.width - list.leftMargin - list.rightMargin
            path: model.label ?? model.path ?? ""
            depth: model.depth ?? 0
            folder: model.directory === true
            folderIcon: true
            expanded: model.expanded === true
            showDirectory: !owner.tree
            status: model.status ?? ""
            partial: model.partial === true
            selected: model.selected === true
            opacity: pending ? 0.5 : 1
            activeFocusOnTab: false
            onClicked: {
                list.forceActiveFocus()
                owner.selectRow(fileRow.index, fileRow.modifiers)
            }
            onDoubleClicked: if (!folder) Store.changes.stageFiles(owner.side, [fileRow.key])
            onFolderToggled: Store.changes.toggleFolder(owner.side, model.path)
            onContextMenuRequested: (x, y) => owner.showFileMenu(fileRow.index, fileRow, x, y)
            // The rows an action on this one affects: the selection when the
            // row belongs to a multiple selection.
            readonly property var actionRows: model.selected === true && owner.selectedCount > 1
                ? owner.rowsOf(owner.selectedKeys()) : [model]
            readonly property bool discardShown: owner.unstaged && actionRows.length > 0 && actionRows.every(entry => entry.discardable === true)
            readonly property bool cleanOnly: actionRows.every(entry => entry.untracked === true)
            trailing: folder ? null : rowActions
            Component {
                id: rowActions
                Row {
                    spacing: Theme.space.s1
                    // Stage (or unstage) and discard on hover (the Dart
                    // GitLamaFileRow actions).
                    MeridianIconButton {
                        visible: rowHover.hovered || fileRow.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        text: fileRow.actionRows.length > 1
                            ? (owner.unstaged ? L10n.t("stageSelected") : L10n.t("unstageSelected"))
                            : (owner.unstaged ? L10n.t("stageFile") : L10n.t("unstageFile"))
                        iconName: owner.unstaged ? "arrow-down" : "arrow-up"
                        controlSize: MeridianButton.Small
                        enabled: (!owner.busy || owner.paneState.canQueue === true)
                            && !fileRow.actionRows.every(entry => entry.pending === true)
                        onClicked: Store.changes.stageFiles(owner.side, fileRow.actionRows.map(entry => entry.key))
                    }
                    MeridianIconButton {
                        visible: (rowHover.hovered || fileRow.activeFocus) && fileRow.discardShown
                        anchors.verticalCenter: parent.verticalCenter
                        text: fileRow.cleanOnly
                            ? (fileRow.actionRows.length > 1 ? L10n.t("cleanSelected") : L10n.t("cleanFile"))
                            : (fileRow.actionRows.length > 1 ? L10n.t("discardSelected") : L10n.t("discardFile"))
                        iconName: "undo"
                        controlSize: MeridianButton.Small
                        enabled: !owner.busy
                        onClicked: Store.changes.discardFiles(fileRow.actionRows.map(entry => entry.key))
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
                                if (active)
                                    owner.startDrag(fileRow.actionRows.map(entry => entry.key), grip, centroid.position)
                                else
                                    owner.endDrag()
                            }
                            onCentroidChanged: if (active) owner.moveDrag(grip, centroid.position)
                        }
                    }
                }
            }
            HoverHandler { id: rowHover }
        }

        MeridianEmptyState {
            visible: owner.shown === 0
            anchors.fill: parent
            compact: true
            title: owner.filtering && owner.total > 0 ? L10n.t("changesFilterNoMatches") : L10n.t("stagingEmpty")
        }
    }
}
