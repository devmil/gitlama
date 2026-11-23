pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// Picks the branches the history graph shows,
// as a tree of local branches and each remote's. Clicking a branch adds or
// removes it and applies at once; double-click, Enter or the row's focus
// action shows only that branch and closes. A local branch brings the
// branch it tracks. Typing narrows the tree to matching branches and opens
// every folder; Up and Down move, Space toggles and Enter or Space opens
// and closes a folder.
MeridianPopover {
    id: editor

    /// {reference, label, name, remote, current, upstream} per branch.
    property var choices: []
    /// The filter: sorted full reference names; empty shows everything.
    property var filter: []
    property var tree: []
    property var openFolders: ({})
    property var rows: []
    property int cursor: 0
    readonly property var current: choices.find(choice => choice.current) ?? null
    readonly property string needle: search.text.trim().toLowerCase()

    signal changed(var filter)

    width: GitLamaLayout.branchFilterWidth
    padding: 0

    function show(choices, filter) {
        editor.choices = choices
        editor.filter = filter ?? []
        search.text = ""
        tree = buildTree()
        const folders = {}
        for (const node of tree)
            if (!node.choice)
                folders[node.path] = true
        const reveal = nodes => {
            for (const node of nodes) {
                if (node.choice)
                    continue
                if (node.branches.some(choice => choice.current || BranchFilters.contains(editor.filter, choice.reference)))
                    folders[node.path] = true
                reveal(node.children)
            }
        }
        reveal(tree)
        openFolders = folders
        rows = flatten()
        cursor = 0
        open()
        search.forceActiveFocus()
    }

    function branchNode(choice, name) {
        return { path: choice.reference, name: name, choice: choice, children: [], branches: [choice] }
    }
    function folderNode(path, name, children) {
        let branches = []
        for (const child of children)
            branches = branches.concat(child.branches)
        return { path: path, name: name, choice: null, children: children, branches: branches }
    }
    /// Folders of `items` ([name, choice]) below `path`, in the order their
    /// first branch comes.
    function folders(items, path) {
        const order = []
        const groups = {}
        for (const item of items) {
            const segment = item[0].split("/")[0]
            if (!groups[segment]) {
                groups[segment] = []
                order.push(segment)
            }
            groups[segment].push(item)
        }
        return order.map(segment => {
            const group = groups[segment]
            if (group.length === 1 && group[0][0] === segment)
                return branchNode(group[0][1], segment)
            return folderNode(path + segment + "/", segment,
                folders(group.filter(item => item[0].length > segment.length)
                             .map(item => [item[0].substring(segment.length + 1), item[1]]), path + segment + "/"))
        })
    }
    function shortName(reference) {
        for (const prefix of ["refs/heads/", "refs/remotes/"])
            if (reference.startsWith(prefix))
                return reference.substring(prefix.length)
        return reference
    }
    /// References the repository no longer lists stay on top while filtered,
    /// so they can be removed; then local branches and each remote's.
    function buildTree() {
        const known = new Set(choices.map(choice => choice.reference))
        const local = []
        const remotes = {}
        const remoteOrder = []
        for (const choice of choices) {
            if (choice.remote) {
                if (!remotes[choice.remote]) {
                    remotes[choice.remote] = []
                    remoteOrder.push(choice.remote)
                }
                remotes[choice.remote].push([choice.name, choice])
            } else {
                local.push([choice.name, choice])
            }
        }
        const result = []
        for (const reference of filter)
            if (!known.has(reference))
                result.push(branchNode({ reference: reference, label: shortName(reference), name: shortName(reference) }, shortName(reference)))
        if (local.length > 0)
            result.push(folderNode("refs/heads/", L10n.t("workspaceBranches"), folders(local, "refs/heads/")))
        for (const remote of remoteOrder)
            result.push(folderNode("refs/remotes/" + remote + "/", remote, folders(remotes[remote], "refs/remotes/" + remote + "/")))
        return result
    }
    /// The visible rows; while searching, only matching branches and the
    /// folders holding them, all open.
    function flatten() {
        const searching = needle.length > 0
        const result = []
        const visit = (nodes, depth) => {
            let any = false
            for (const node of nodes) {
                if (node.choice) {
                    if (searching && node.choice.label.toLowerCase().indexOf(needle) < 0)
                        continue
                    result.push({ node: node, depth: depth, open: false })
                    any = true
                    continue
                }
                const open = searching || openFolders[node.path] === true
                const at = result.length
                result.push({ node: node, depth: depth, open: open })
                if (!open)
                    any = true
                else if (visit(node.children, depth + 1) || !searching)
                    any = true
                else
                    result.splice(at, 1)
            }
            return any
        }
        visit(tree, 0)
        return result
    }
    function apply(next) {
        if (JSON.stringify(next) === JSON.stringify(filter))
            return
        filter = next
        editor.changed(next)
    }
    function toggle(index) {
        cursor = index
        const node = rows[index].node
        if (node.choice) {
            apply(BranchFilters.toggled(filter, node.choice.reference, node.choice.upstream ?? null))
        } else if (needle.length === 0) {
            const next = Object.assign({}, openFolders)
            if (next[node.path])
                delete next[node.path]
            else
                next[node.path] = true
            openFolders = next
            rows = flatten()
        }
    }
    function focusOn(choice) {
        apply(BranchFilters.focus(choice.reference, choice.upstream ?? null))
        close()
    }
    function move(delta) {
        if (rows.length === 0)
            return
        cursor = Math.max(0, Math.min(rows.length - 1, cursor + delta))
        list.positionViewAtIndex(cursor, ListView.Contain)
    }

    contentItem: Column {
        Item {
            width: parent.width
            height: search.implicitHeight + 2 * Theme.space.s3
            MeridianTextField {
                id: search
                objectName: "branch-filter-search"
                x: Theme.space.s3
                y: Theme.space.s3
                width: parent.width - 2 * Theme.space.s3
                variant: MeridianTextField.Search
                controlSize: MeridianButton.Small
                placeholderText: L10n.t("historyBranchFilterSearch")
                clearLabel: L10n.t("searchClear")
                inputMethodHints: Qt.ImhNoPredictiveText
                Accessible.name: L10n.t("historyBranchFilterSearch")
                onTextChanged: {
                    editor.rows = editor.flatten()
                    // On the first matching branch, so Enter shows it rather
                    // than folding the folder above it.
                    editor.cursor = Math.max(0, editor.rows.findIndex(row => row.node.choice !== null))
                    list.contentY = 0
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Down) {
                        editor.move(1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        editor.move(-1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Space && editor.rows.length > 0) {
                        editor.toggle(editor.cursor)
                        event.accepted = true
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && editor.rows.length > 0) {
                        const node = editor.rows[editor.cursor].node
                        if (node.choice)
                            editor.focusOn(node.choice)
                        else
                            editor.toggle(editor.cursor)
                        event.accepted = true
                    }
                }
            }
        }
        MeridianText {
            visible: editor.rows.length === 0
            width: parent.width
            topPadding: Theme.space.s4
            bottomPadding: Theme.space.s4
            horizontalAlignment: Text.AlignHCenter
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: L10n.t("historyBranchFilterNoMatches")
        }
        ListView {
            id: list
            objectName: "branch-filter-list"
            visible: editor.rows.length > 0
            width: parent.width
            height: Math.min(editor.rows.length * Theme.size.row, GitLamaLayout.branchFilterListMaxHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: editor.rows
            MeridianWheelScroll { flickable: list }
            C.ScrollBar.vertical: MeridianScrollBar {}
            delegate: MeridianListRow {
                id: row
                required property var modelData
                required property int index
                readonly property var node: modelData.node
                readonly property bool folder: node.choice === null
                readonly property int shownCount: folder ? node.branches.filter(choice => BranchFilters.contains(editor.filter, choice.reference)).length : 0
                readonly property bool shown: !folder && BranchFilters.contains(editor.filter, node.choice.reference)
                width: list.width
                height: Theme.size.row
                text: node.name
                match: folder || editor.needle.length === 0 ? "" : editor.needle
                selected: index === editor.cursor
                emphasized: !folder && node.choice.current === true
                semanticValue: folder ? (shownCount > 0 ? L10n.tn("historyBranchFilterSummary", { count: shownCount }) : "")
                    : shown ? L10n.t("historyBranchFilterShown") : ""
                leading: Component {
                    Row {
                        leftPadding: row.modelData.depth * Metrics.treeIndent
                        spacing: Theme.space.s3
                        Item {
                            width: Metrics.chevronSize
                            height: Metrics.chevronSize
                            anchors.verticalCenter: parent.verticalCenter
                            MeridianIcon {
                                visible: row.folder
                                anchors.centerIn: parent
                                name: row.modelData.open ? "chevron-down" : "chevron-right"
                                iconSize: MeridianIcon.Small
                                color: row.solid ? Theme.colors.inkOnAccent : Theme.colors.inkMuted
                            }
                        }
                        Item {
                            width: Theme.size.icon
                            height: Theme.size.icon
                            anchors.verticalCenter: parent.verticalCenter
                            MeridianIcon {
                                visible: row.folder || row.shown
                                anchors.centerIn: parent
                                name: row.folder ? "folder-closed" : "check"
                                iconSize: row.folder ? MeridianIcon.Small : MeridianIcon.Regular
                                color: row.solid ? Theme.colors.inkOnAccent : row.folder ? Theme.colors.inkMuted : Theme.colors.accent
                            }
                        }
                    }
                }
                trailing: Component {
                    MeridianCount {
                        visible: row.folder && row.shownCount > 0
                        label: String(row.shownCount)
                    }
                }
                MeridianIconButton {
                    visible: !row.folder
                    text: L10n.t("historyBranchFilterFocus")
                    iconName: "focus"
                    controlSize: MeridianButton.Small
                    onClicked: editor.focusOn(row.node.choice)
                }
                onClicked: editor.toggle(index)
                onDoubleClicked: if (!folder) editor.focusOn(node.choice)
            }
        }
        MeridianHairline { width: parent.width }
        Column {
            x: Theme.space.s3
            width: parent.width - 2 * Theme.space.s3
            topPadding: Theme.space.s3
            bottomPadding: Theme.space.s3
            MeridianText {
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                text: L10n.t("historyBranchFilterHelp")
            }
            Item { width: 1; height: Theme.space.s2 }
            MeridianText {
                objectName: "branch-filter-summary"
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                elide: Text.ElideRight
                text: L10n.tn("historyBranchFilterSummary", { count: editor.filter.length })
            }
            Item { width: 1; height: Theme.space.s3 }
            // Wraps instead of overflowing with long translations.
            Flow {
                width: parent.width
                spacing: Theme.space.s2
                layoutDirection: Qt.RightToLeft
                MeridianButton {
                    objectName: "branch-filter-show-all"
                    text: L10n.t("historyBranchFilterShowAll")
                    controlSize: MeridianButton.Small
                    enabled: editor.filter.length > 0
                    onClicked: {
                        editor.apply([])
                        editor.close()
                    }
                }
                MeridianButton {
                    objectName: "branch-filter-current"
                    visible: editor.current !== null
                    text: L10n.t("historyBranchFilterCurrent")
                    variant: MeridianButton.Quiet
                    controlSize: MeridianButton.Small
                    onClicked: editor.focusOn(editor.current)
                }
            }
        }
    }
}
