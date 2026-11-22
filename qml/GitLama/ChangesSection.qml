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
    readonly property int shown: model ? model.size : 0
    readonly property int total: unstaged ? (paneState.unstagedTotal ?? 0) : (paneState.stagedTotal ?? 0)
    readonly property int selectedCount: unstaged ? (paneState.selectedUnstaged ?? 0) : (paneState.selectedStaged ?? 0)
    readonly property bool filtering: paneState.filtering === true
    readonly property bool busy: paneState.busy === true
    /// The row the Shift range starts from.
    property int anchor: -1

    function keysOf(predicate) {
        const keys = []
        for (let i = 0; i < model.count(); ++i) {
            const row = model.get(i)
            if (predicate(row, i))
                keys.push(row.key)
        }
        return keys
    }
    function selectedKeys() { return keysOf(row => row.selected) }
    function selectRow(index, modifiers) {
        const row = model.get(index)
        if (!row)
            return
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
        capabilities: ["stage", "unstage", "createPatch", "openExternally", "revealInFileBrowser", "copyPath", "discard", "clean",
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
            const keys = rows.map(row => row.key)
            const path = target.path
            switch (action) {
            case "stage":
            case "unstage":
                Store.changes.stageFiles(owner.side, keys); return
            case "createPatch": {
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
                Store.workflows.ignorePath(path, false, rows.some(row => row.untracked !== true)); return
            case "blame":
                Store.inspector.inspectWorkingFile(path, "blame", false); return
            case "fileHistory":
                Store.inspector.inspectWorkingFile(path, "history", false); return
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
            path: model.path ?? ""
            status: model.status ?? ""
            partial: model.partial === true
            selected: model.selected === true
            opacity: pending ? 0.5 : 1
            activeFocusOnTab: false
            onClicked: {
                list.forceActiveFocus()
                owner.selectRow(fileRow.index, fileRow.modifiers)
            }
            onDoubleClicked: Store.changes.stageFiles(owner.side, [fileRow.key])
            onContextMenuRequested: (x, y) => owner.showFileMenu(fileRow.index, fileRow, x, y)
            // Stages or unstages this one file.
            MeridianIconButton {
                visible: rowHover.hovered
                anchors.right: parent.right
                anchors.rightMargin: Theme.space.s3
                anchors.verticalCenter: parent.verticalCenter
                text: owner.unstaged ? L10n.t("stageFile") : L10n.t("unstageFile")
                iconName: owner.unstaged ? "plus" : "minus"
                controlSize: MeridianButton.Small
                enabled: !owner.busy || owner.paneState.canQueue === true
                onClicked: Store.changes.stageFiles(owner.side, [fileRow.key])
            }
            HoverHandler { id: rowHover }
        }

        MeridianText {
            visible: owner.shown === 0 && owner.total > 0
            anchors.centerIn: parent
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: L10n.t("changesFilterNoMatches")
        }
    }
}
