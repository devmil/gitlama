pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The History pane (the Dart HistoryPane): the query toolbar, notices and
// the commit graph. Rows come from Rust (HistoryModel) for every commit of
// the history; rows not loaded yet show as skeletons until their page
// arrives. Only the visible rows are built.
Item {
    id: pane

    readonly property var paneState: Store.history ? (Store.history.state ?? ({})) : ({})
    readonly property var active: Store.workspace ? Store.workspace.active : null
    readonly property string selectedObjectId: active && active.selectedIdentity ? active.selectedIdentity : ""
    readonly property string dateFormat: Store.appearance.dateFormat ?? "iso"
    signal command(string id, var options)

    // History's metadata columns (the Dart _measureHistoryMetadata).
    readonly property real authorWidth: Math.max(80, Math.min(132, list.width - 650))
    readonly property real hashWidth: Math.ceil(hashMetrics.advanceWidth)
    readonly property real dateWidth: _dateWidth(dateFormat, L10n.language)
    readonly property real reservation: 4 * Theme.space.s5 + authorWidth + hashWidth + dateWidth
    readonly property real metadataLeft: Math.max(180, list.width - 2 * listPadding - reservation)
    readonly property real listPadding: Theme.space.s2

    TextMetrics { id: hashMetrics; font: Theme.type.codeSm; text: "0000000000" }
    FontMetrics { id: dateMetrics; font: Theme.type.caption }

    function _dateWidth(format) {
        const samples = []
        if (format === "iso") {
            samples.push("2000-01-01")
        } else {
            for (let month = 0; month < 12; ++month)
                for (let day = 22; day <= 28; ++day)
                    samples.push(new Date(2000, month, day).toLocaleDateString(Qt.locale(L10n.locale), "MMM d, yyyy"))
            if (format !== "local")
                samples.push(L10n.t("historyDateNow"), L10n.tn("historyDateMinutes", { count: 59 }),
                             L10n.tn("historyDateHours", { count: 23 }), L10n.tn("historyDateDays", { count: 29 }))
        }
        // Every digit the widest digit, so no date is cut off.
        let widest = "0"
        let widestWidth = 0
        for (let digit = 0; digit <= 9; ++digit) {
            const digitWidth = dateMetrics.advanceWidth(String(digit))
            if (digitWidth > widestWidth) {
                widestWidth = digitWidth
                widest = String(digit)
            }
        }
        let width = 0
        for (const sample of samples) {
            width = Math.max(width, dateMetrics.advanceWidth(sample.replace(/[0-9]/g, widest)))
        }
        return Math.ceil(width)
    }

    property var commitMenuItems: []
    Component.onCompleted: Store.historyPane = pane
    CommandMenu {
        id: commitMenu
        onSelected: value => { if (typeof value === "function") value() }
    }

    /// The commit menu (the Dart _commitContextMenu): the selection's
    /// commands when several are selected, the commit's commands, copying,
    /// then a submenu per reference at the commit.
    function showCommitMenu(objectId, subject, item, x, y) {
        if (objectId === "wip" || objectId.startsWith("loading-"))
            return
        const selected = (pane.paneState.selectedIds ?? []).filter(id => id !== "wip")
        const inSelection = selected.length >= 2 && selected.indexOf(objectId) >= 0
        const availability = Store.actions ? Store.actions.availability : ({})
        const commandItem = (id, selection, title) => {
            const reason = Commands.reason(id, availability, selection ? ({ contextual: true }) : ({ target: objectId, contextual: true }))
            return {
                title: title ?? Commands.label(id),
                icon: Commands.icon(id),
                shortcut: Commands.shortcutLabel(id),
                danger: Commands.definition(id)?.destructive === true,
                enabled: reason.length === 0,
                value: () => pane.command(id, selection ? ({}) : ({ initialTarget: objectId })),
            }
        }
        const destructiveLast = items => {
            const safe = items.filter(item => item.separator || !item.danger)
            const dangerous = items.filter(item => !item.separator && item.danger)
            return dangerous.length > 0 ? safe.concat([{ separator: true }], dangerous) : safe
        }
        const items = []
        if (inSelection) {
            items.push({ title: L10n.tn("menuSelectedCommits", { count: selected.length }), children: destructiveLast([
                commandItem("historyCompare", true),
                commandItem("cherryPickSelected", true),
                commandItem("revertSelected", true),
                commandItem("createPatch", true, L10n.t("patchCreateFromSelection")),
            ]) })
            items.push({ separator: true })
        }
        for (const item of destructiveLast([
            commandItem("revertSelected", false, L10n.t("historyRevertCommit")),
            commandItem("cherryPickSelected", false),
            commandItem("createPatch", false, L10n.t("patchCreateFromCommit")),
            commandItem("checkoutCommit", false),
            commandItem("saveCommitArchive", false),
            commandItem("createBranch", false),
            commandItem("createTag", false),
            commandItem("resetBranch", false),
            { separator: true },
            { title: L10n.t("historyCopyObjectId"), icon: "copy", value: () => Store.actions.copyText(objectId, L10n.t("menuCommitHashCopied")) },
            { title: L10n.t("historyCopySubject"), icon: "copy", value: () => Store.actions.copyText(subject, L10n.t("menuCommitSubjectCopied")) },
        ]))
            items.push(item)
        const references = Store.history.referencesAt(objectId)
        if (references.length > 0)
            items.push({ separator: true })
        for (const reference of references)
            items.push({ title: reference.name, children: ReferenceMenu.items(reference.entry, [], (id, options) => pane.command(id, options)) })
        commitMenu.items = items
        commitMenuItems = items
        commitMenu.show(item, x, y)
    }

    function select(objectId, toggle) {
        list.forceActiveFocus()
        if (toggle)
            Store.history.toggle(objectId)
        else
            Store.history.select(objectId)
    }

    function moveSelection(delta, extend) {
        const current = selectedObjectId.length > 0 ? Store.historyRows.indexOf(selectedObjectId) : -1
        const next = Math.max(0, Math.min(Store.historyRows.count() - 1, current < 0 ? 0 : current + delta))
        const objectId = Store.historyRows.objectIdAt(next)
        if (objectId.length === 0)
            return
        if (extend)
            Store.history.selectRelative(objectId, true)
        else
            Store.history.select(objectId)
        list.positionViewAtIndex(next, ListView.Contain)
    }

    // A revealed commit scrolls into view.
    property real _revealSequence: -1
    onPaneStateChanged: {
        const sequence = paneState.revealSequence ?? 0
        if (sequence !== _revealSequence) {
            _revealSequence = sequence
            if (paneState.revealIndex !== null && paneState.revealIndex !== undefined)
                Qt.callLater(() => list.positionViewAtIndex(paneState.revealIndex, ListView.Contain))
        }
    }

    // The query toolbar.
    Rectangle {
        id: toolbar
        objectName: "history-query-toolbar"
        width: parent.width
        height: Theme.size.control + 2 * Theme.space.s2
        color: Theme.colors.pane

        MeridianText {
            x: Theme.space.s5
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.BodyStrong
            text: L10n.t("workspaceHistory")
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s5
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s2

            MeridianTextField {
                id: query
                objectName: "history-query"
                width: 240
                variant: MeridianTextField.Search
                controlSize: MeridianButton.Small
                placeholderText: L10n.t("historySearchHint")
                Accessible.name: L10n.t("historySearchHint")
                onAccepted: {
                    if (pane.paneState.searchText === text.trim() && (pane.paneState.searchMatches ?? 0) > 0)
                        Store.history.navigateSearch(false)
                    else
                        Store.history.applyQuery(text, true, true, true, false)
                }
                onTextEdited: {
                    if (text.length === 0)
                        Store.history.applyQuery("", true, true, true, false)
                }
                Keys.onEscapePressed: {
                    text = ""
                    Store.history.applyQuery("", true, true, true, false)
                }
            }
        }
        MeridianHairline {
            anchors.bottom: parent.bottom
            width: parent.width
        }
    }

    Item {
        id: body
        anchors.top: toolbar.bottom
        anchors.bottom: parent.bottom
        width: parent.width

        MeridianEmptyState {
            anchors.fill: parent
            visible: pane.paneState.phase === "failed"
            compact: true
            iconName: "circle-alert"
            title: L10n.t("workspaceUnavailableRepository")
        }
        MeridianEmptyState {
            anchors.fill: parent
            visible: pane.paneState.phase !== "failed" && pane.paneState.phase !== "loading" && pane.paneState.empty === true
            compact: true
            iconName: "history"
            title: L10n.t("workspaceEmptyHistory")
        }

        ListView {
            id: list
            objectName: "history-graph"
            anchors.fill: parent
            anchors.margins: pane.listPadding
            visible: pane.paneState.phase !== "failed" && pane.paneState.empty !== true
            clip: true
            focus: true
            activeFocusOnTab: true
            boundsBehavior: Flickable.StopAtBounds
            model: Store.historyRows
            reuseItems: true
            cacheBuffer: 240
            keyNavigationEnabled: false

            MeridianWheelScroll { flickable: list }
            C.ScrollBar.vertical: MeridianScrollBar { viewHovered: listHover.hovered }

            Keys.onPressed: event => {
                const extend = (event.modifiers & Qt.ShiftModifier) !== 0
                if (event.key === Qt.Key_Down) {
                    pane.moveSelection(1, extend)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    pane.moveSelection(-1, extend)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageDown) {
                    pane.moveSelection(Math.max(1, Math.floor(list.height / Theme.size.row) - 1), extend)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp) {
                    pane.moveSelection(-Math.max(1, Math.floor(list.height / Theme.size.row) - 1), extend)
                    event.accepted = true
                } else if (event.key === Qt.Key_Home) {
                    pane.moveSelection(-Store.historyRows.count(), extend)
                    event.accepted = true
                } else if (event.key === Qt.Key_End) {
                    pane.moveSelection(Store.historyRows.count(), extend)
                    event.accepted = true
                }
            }

            delegate: HistoryRow {
                id: historyRow
                width: list.width
                height: Theme.size.row
                metadataLeft: pane.metadataLeft
                authorWidth: pane.authorWidth
                hashWidth: pane.hashWidth
                dateWidth: pane.dateWidth
                lightingActive: pane.paneState.lightingActive === true
                queryActive: pane.paneState.queryActive === true
                dateFormat: pane.dateFormat
                selectedHere: objectId === pane.selectedObjectId
                onActivated: (objectId, toggle) => pane.select(objectId, toggle)
                onDoubleActivated: objectId => pane.command("checkoutCommit", { initialTarget: objectId })
                onCopyRequested: value => Store.actions.copyText(value, L10n.t("historyObjectIdCopied"))
                onContextMenuRequested: (objectId, x, y) => pane.showCommitMenu(objectId, historyRow.subject, historyRow, x, y)
            }

            footer: Item {
                width: list.width
                height: Theme.size.row
                visible: pane.paneState.phase === "complete"
                MeridianText {
                    anchors.centerIn: parent
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: L10n.tn("historyEndOfHistory", { count: (pane.paneState.total ?? 0) - (pane.paneState.worktreeRows ?? 0) })
                }
            }
        }
        HoverHandler { id: listHover }

        MeridianSpinner {
            visible: pane.paneState.phase === "preview" || pane.paneState.phase === "loading"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.space.s4
        }
    }
}
