pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// One sidebar reference row: a branch, group,
// remote, tag, stash, worktree or integration. Clicking selects it and
// shows its commit in History; a group opens or closes. Double-click and
// Enter run its primary command, F2 renames, Delete deletes, the context
// menu key and Shift+F10 open its menu. A branch dragged onto the current
// branch integrates into it.
FocusScope {
    id: root

    /// What a dragged branch carries to the row it is dropped on.
    component BranchDrag: Item {
        property string branchName
        property string branchTarget
    }

    required property var row
    /// `row`, never null while a delegate is torn down.
    readonly property var entry: row ?? ({})
    signal command(string id, var options)
    signal toggled()

    readonly property bool hasChildren: row.hasChildren === true
    readonly property bool expanded: row.expanded === true
    readonly property var commands: row.commands ?? []
    readonly property string commandName: row.commandName ?? row.name
    readonly property bool strong: false
    readonly property string fileBrowserName: Labels.fileBrowserName()

    implicitHeight: Theme.size.row

    function reasonOf(id) {
        return Commands.reason(id, Store.actions ? Store.actions.availability : ({}), {
            reference: row.filterReference ?? null,
            target: row.target ?? null,
            current: row.current === true,
            contextual: true,
        })
    }

    function run(id) {
        if (reasonOf(id).length > 0)
            return
        command(id, {
            initialName: id === "createBranch" || id === "createTag" ? null : commandName,
            initialTarget: row.target ?? null,
            initialReference: row.filterReference ?? null,
        })
    }

    function activate() {
        listRow.forceActiveFocus()
        const reveal = row.target ? (row.filterReference ?? row.revealReference ?? "") : ""
        Store.sidebar.selectReference(row.reference, reveal)
        const action = row.activate
        if (action && action.command !== undefined)
            command(action.command, {})
        else if (action && action.worktree !== undefined)
            Store.sidebar.openWorktree(action.worktree)
        else if (row.target)
            Store.sidebar.revealTarget(row.target)
        else if (hasChildren)
            toggled()
    }

    function worktreeActions() {
        if (row.worktree === null || row.worktree === undefined)
            return []
        const index = row.worktree
        const path = row.worktreePath ?? ""
        const actions = []
        if (row.current !== true)
            actions.push({ title: L10n.t("extensionOpen"), run: () => Store.sidebar.openWorktree(index) })
        actions.push({ title: L10n.tn("openInFileBrowser", { browser: fileBrowserName }), run: () => Store.actions.openFolder(path) })
        actions.push({
            title: L10n.t("extensionWorktreeDeleteAction"),
            enabled: row.worktreeProtected !== true,
            danger: true,
            run: () => Store.actions.deleteWorktree(index, row.name),
        })
        return actions
    }

    /// A pull request's actions: its page and, while open, checking it out.
    function pullRequestActions() {
        const pull = row.pullRequest
        if (!pull)
            return []
        const actions = [{ title: L10n.t("hostingOpenBrowser"), run: () => { if (Store.hosting.openable(pull.webUrl)) Qt.openUrlExternally(pull.webUrl) } }]
        if (pull.checkoutBranch)
            actions.push({ title: L10n.t("hostingCheckout"),
                           run: () => root.command("createBranch", { initialName: pull.checkoutBranch, initialTarget: pull.checkoutTarget }) })
        return actions
    }

    function showMenu(x, y) {
        if (row.hasMenu !== true)
            return
        listRow.forceActiveFocus()
        menu.items = ReferenceMenu.items({
            name: row.name,
            commandName: commandName,
            target: row.target ?? null,
            filterReference: row.filterReference ?? null,
            filterUpstream: row.filterUpstream ?? null,
            commands: commands,
            current: row.current === true,
        }, worktreeActions().concat(pullRequestActions()), (id, options) => root.command(id, options))
        menu.show(listRow, x, y)
    }

    function keyCommand(key) {
        const first = ids => ids.find(id => commands.indexOf(id) >= 0) ?? ""
        if (key === Qt.Key_F2)
            return first(["renameBranch", "renameRemote", "renameStash"])
        if (key === Qt.Key_Delete)
            return first(["deleteBranch", "deleteRemoteBranch", "deleteTag", "removeRemote", "dropStash"])
        return ""
    }

    function handleKey(event) {
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        if (hasChildren && (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                            || (enter && !row.primaryCommand))) {
            const open = event.key === Qt.Key_Right || (enter && !expanded)
            if (open !== expanded)
                toggled()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            showMenu(Theme.space.s4, height)
            event.accepted = true
            return
        }
        if (enter && row.primaryCommand) {
            run(row.primaryCommand)
            event.accepted = true
            return
        }
        if (enter || event.key === Qt.Key_Space) {
            activate()
            event.accepted = true
            return
        }
        const id = keyCommand(event.key)
        if (id.length > 0) {
            run(id)
            event.accepted = true
        }
    }

    CommandMenu {
        id: menu
        onSelected: value => {
            listRow.forceActiveFocus()
            if (typeof value === "function")
                value()
        }
    }

    MeridianListRow {
        id: listRow
        anchors.fill: parent
        text: root.entry.name
        selected: root.entry.selected === true
        emphasized: root.entry.current === true
        focus: true
        activeFocusOnTab: true
        Keys.onPressed: event => root.handleKey(event)
        semanticValue: root.entry.currentDescription ? L10n.t(root.entry.currentDescription)
            : root.entry.current === true && root.entry.filtered === true
                ? L10n.t("sidebarCurrentBranch") + ", " + L10n.t("historyBranchFilterShown")
            : root.entry.current === true ? L10n.t("sidebarCurrentBranch")
            : root.entry.filtered === true ? L10n.t("historyBranchFilterShown") : ""

        onClicked: root.activate()
        onDoubleClicked: {
            if (root.entry.primaryCommand)
                root.run(root.entry.primaryCommand)
        }
        onContextMenuRequested: (x, y) => root.showMenu(x, y)

        leading: Component {
            Row {
                id: leadingRow
                readonly property var item: root.entry ?? ({})
                spacing: Theme.space.s3
                leftPadding: leadingRow.item.depth * Metrics.treeIndent
                Item {
                    width: Metrics.chevronSize
                    height: Metrics.chevronSize
                    anchors.verticalCenter: parent.verticalCenter
                    MeridianIcon {
                        visible: root.hasChildren
                        anchors.centerIn: parent
                        name: root.expanded ? "chevron-down" : "chevron-right"
                        iconSize: MeridianIcon.Small
                        color: Theme.colors.inkMuted
                    }
                    TapHandler {
                        enabled: root.hasChildren
                        onTapped: {
                            listRow.forceActiveFocus()
                            root.toggled()
                        }
                    }
                }
                MeridianIcon {
                    id: glyph
                    anchors.verticalCenter: parent.verticalCenter
                    name: leadingRow.item.icon
                    iconSize: MeridianIcon.Small
                    color: leadingRow.item.current === true ? Theme.colors.accentInk : Theme.colors.inkMuted
                    HoverHandler { id: glyphHover }
                    MeridianTooltip {
                        shown: glyphHover.hovered && (leadingRow.item.currentDescription ?? "").length > 0
                        text: leadingRow.item.currentDescription ? L10n.t(leadingRow.item.currentDescription) : ""
                    }
                }
            }
        }

        trailing: Component {
            Row {
                id: trailingRow
                readonly property var item: root.entry ?? ({})
                spacing: Theme.space.s2
                Item {
                    visible: trailingRow.item.filtered === true || trailingRow.item.holdsFiltered === true
                    objectName: "sidebar-ref-filtered"
                    width: Metrics.chevronSize
                    height: Metrics.chevronSize
                    anchors.verticalCenter: parent.verticalCenter
                    MeridianIcon {
                        anchors.centerIn: parent
                        name: "list-filter"
                        iconSize: MeridianIcon.Small
                        color: trailingRow.item.filtered === true ? Theme.colors.accentInk : Theme.colors.inkMuted
                    }
                    HoverHandler { id: filterHover }
                    MeridianTooltip {
                        shown: filterHover.hovered
                        text: L10n.t("historyBranchFilterShown")
                    }
                }
                SyncBadge {
                    visible: trailingRow.item.ahead > 0 || trailingRow.item.behind > 0
                    anchors.verticalCenter: parent.verticalCenter
                    ahead: trailingRow.item.ahead
                    behind: trailingRow.item.behind
                    HoverHandler { id: syncHover }
                    MeridianTooltip {
                        shown: syncHover.hovered
                        text: L10n.tn("transferAheadBehind", { ahead: String(trailingRow.item.ahead), behind: String(trailingRow.item.behind) })
                    }
                }
                // A branch's CI state, or the bound integration's main
                // branch's.
                HostingStatus {
                    id: branchChecks
                    readonly property string checkState: trailingRow.item.hostingCheck ?? ""
                    visible: checkState.length > 0 && !(trailingRow.item.pullRequest)
                    anchors.verticalCenter: parent.verticalCenter
                    checks: checkState
                    HoverHandler { id: branchChecksHover }
                    MeridianTooltip {
                        shown: branchChecksHover.hovered
                        text: trailingRow.item.hostingCheckBranch
                            ? L10n.tn("hostingBranchChecks", { branch: trailingRow.item.hostingCheckBranch, checks: branchChecks.label(branchChecks.checkState) })
                            : branchChecks.label(branchChecks.checkState)
                    }
                }
                // A pull request's checks and conflicts.
                HostingStatus {
                    visible: trailingRow.item.pullRequest !== null && trailingRow.item.pullRequest !== undefined
                    anchors.verticalCenter: parent.verticalCenter
                    checks: trailingRow.item.pullRequest ? (trailingRow.item.pullRequest.checks ?? "") : ""
                    conflicting: trailingRow.item.pullRequest ? trailingRow.item.pullRequest.conflicting === true : false
                }
                MeridianText {
                    id: subtitleText
                    readonly property string shown: {
                        const value = trailingRow.item.subtitle ?? ""
                        return value.startsWith("@") ? L10n.t(value.slice(1)) : value
                    }
                    visible: shown.length > 0
                    width: Math.min(implicitWidth, GitLamaLayout.trackingLabelMaxWidth)
                    anchors.verticalCenter: parent.verticalCenter
                    role: MeridianText.Caption
                    text: shown
                    color: Theme.colors.inkMuted
                    elide: Text.ElideRight
                    HoverHandler { id: subtitleHover }
                    MeridianTooltip {
                        shown: subtitleHover.hovered
                        text: trailingRow.item.pullRequest
                            ? L10n.tn("hostingPullRequestBranches", { source: trailingRow.item.pullRequest.source, target: trailingRow.item.pullRequest.target })
                            : subtitleText.shown
                    }
                }
            }
        }

        HoverHandler { id: rowHover }
        MeridianTooltip {
            shown: rowHover.hovered
            text: root.entry.reference
        }
    }

    // A branch dragged onto the current branch integrates into it.
    BranchDrag {
        id: dragProxy
        visible: false
        Drag.active: drag.active
        Drag.keys: ["gitlama-branch"]
        Drag.hotSpot.x: 0
        Drag.hotSpot.y: 0
        branchName: root.commandName
        branchTarget: root.entry.target ?? ""
    }
    DragHandler {
        id: drag
        enabled: root.entry.draggable === true
        target: null
        dragThreshold: GitLamaLayout.dragThreshold
        onActiveChanged: {
            if (active) {
                dragProxy.x = centroid.position.x
                dragProxy.y = centroid.position.y
            } else {
                dragProxy.Drag.drop()
            }
        }
        onCentroidChanged: {
            if (active) {
                dragProxy.x = centroid.position.x
                dragProxy.y = centroid.position.y
            }
        }
    }
    Rectangle {
        visible: drag.active
        parent: root.Window.contentItem
        x: drag.centroid.scenePosition.x + Theme.space.s3
        y: drag.centroid.scenePosition.y + Theme.space.s3
        width: dragLabel.implicitWidth + 2 * Theme.space.s4
        height: dragLabel.implicitHeight + 2 * Theme.space.s4
        radius: Theme.radius.lg
        color: Theme.colors.raised
        z: 1000
        MeridianText {
            id: dragLabel
            anchors.centerIn: parent
            text: root.entry.name
        }
    }
    opacity: drag.active ? 0.45 : 1

    DropArea {
        id: drop
        anchors.fill: parent
        enabled: root.entry.dropTarget === true
        keys: ["gitlama-branch"]
        onEntered: drag => {
            const source = drag.source as BranchDrag
            drag.accepted = source && source.branchTarget !== (root.entry.target ?? "")
                && Commands.reason("integrateBranch", Store.actions ? Store.actions.availability : ({}),
                                   { target: source.branchTarget }).length === 0
        }
        onDropped: drag => {
            const source = drag.source as BranchDrag
            if (!source)
                return
            root.command("integrateBranch", { initialName: source.branchName, initialTarget: source.branchTarget })
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: drop.containsDrag
        color: "transparent"
        border.color: Theme.colors.accent
        border.width: 1
    }
}
