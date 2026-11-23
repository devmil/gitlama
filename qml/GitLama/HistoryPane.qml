pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The History pane: the query toolbar, notices and
// the commit graph. Rows come from Rust (HistoryModel) for every commit of
// the history; rows not loaded yet show as skeletons until their page
// arrives. Only the visible rows are built.
Item {
    id: pane

    readonly property var paneState: Store.history ? (Store.history.state ?? ({})) : ({})
    readonly property var active: Store.workspace ? Store.workspace.active : null
    readonly property string selectedObjectId: active && active.selectedIdentity ? active.selectedIdentity : ""
    /// The row of the single selected commit, whose selection bar glides between rows (NM-31);
    /// -1 with several selected (their rows keep their own fills).
    readonly property int glideIndex: {
        void paneState
        if ((paneState.selectedIds ?? []).length > 1 || selectedObjectId.length === 0)
            return -1
        return Store.historyRows.indexOf(selectedObjectId)
    }
    readonly property string dateFormat: Store.appearance.dateFormat ?? "iso"
    signal command(string id, var options)

    // History's metadata columns.
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

    /// The commit menu: the selection's
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
        syncMotion()
    }

    // ---------------------------------------------------------------- graph motion

    HistoryMotion { id: graphMotion }

    readonly property string _repository: Store.workspace ? String(Store.workspace.activeTabId) : ""
    property string _lighting: ""
    property string _wip: ""
    property string _initialLanes: ""
    property int _handledSync: -1
    property int _handledCommit: -1
    property string _pendingLanding: ""
    // The commit flash, the search match reached (NM-33) and a transfer's arriving rows (NH-2).
    property string flashObjectId: ""
    property int flashSequence: 0
    property string attentionObjectId: ""
    property int attentionSequence: 0
    property int _searchIndexSeen: -1
    property int _searchMatchesSeen: -1
    property var syncEntranceIds: []
    property int syncEntranceSequence: 0

    function _visibleRows() {
        return Math.max(1, Math.ceil(list.height / Theme.size.row))
    }

    /// Tells the graph's motion what changed: the lit ancestry (NH-3), the working-tree row
    /// appearing or going (NM-36), the first load of a repository (NH-7), a transfer's new
    /// rows (NH-2) and a commit made here (NH-1).
    function syncMotion() {
        const state = paneState
        if (state.hasPage !== true || _repository.length === 0)
            return
        const repository = _repository
        const lighting = repository + "|" + (state.lightingActive === true) + "|" + (state.currentObjectId ?? "")
        if (_lighting.length > 0 && _lighting !== lighting && _lighting.startsWith(repository + "|")) {
            const current = state.currentObjectId ?? ""
            graphMotion.lightingChanged(current.length > 0 ? Store.historyRows.indexOf(current) : -1,
                                        state.lightingActive === true)
        }
        _lighting = lighting
        const wip = repository + "|" + ((state.worktreeRows ?? 0) > 0)
        if (_wip.length > 0 && _wip !== wip && _wip.startsWith(repository + "|")) {
            if ((state.worktreeRows ?? 0) > 0) {
                // The working-tree row opens at the top and its ring draws.
                graphMotion.insertRow(0)
                graphMotion.drawLanes(0, 1, 0)
            } else {
                graphMotion.removeRow(0)
            }
        }
        _wip = wip
        if (_initialLanes !== repository) {
            _initialLanes = repository
            if (Store.markMotionSeen("history-open-lanes|" + repository))
                Qt.callLater(() => graphMotion.drawLanes(0, Math.min(pane._visibleRows(), Store.historyRows.count()),
                                                         Motion.select))
        }
        const sync = state.sync ?? ({})
        if (_handledSync < 0)
            _handledSync = sync.sequence ?? 0
        if ((sync.sequence ?? 0) > _handledSync && state.requestId !== sync.previousHistoryRequest) {
            _handledSync = sync.sequence
            if (Store.markMotionSeen("history-sync-rows|" + repository + "|" + sync.sequence)) {
                const first = Math.floor(list.contentY / Theme.size.row)
                const last = first + _visibleRows()
                const indices = (sync.newRows ?? []).map(id => Store.historyRows.indexOf(id))
                    .filter(index => index >= first && index < last).sort((a, b) => a - b)
                syncEntranceSequence = sync.sequence
                syncEntranceIds = indices.slice(0, Motion.staggerMax).map(index => Store.historyRows.objectIdAt(index))
                if (indices.length > 0)
                    graphMotion.drawLanes(indices[0], indices.length, GitLamaLayout.pullLanesDelay)
            }
        }
        const matches = state.searchMatches ?? 0
        const searchIndex = state.searchIndex ?? -1
        if (matches === _searchMatchesSeen && searchIndex !== _searchIndexSeen && searchIndex >= 0
                && _searchIndexSeen >= 0 && (state.currentObjectId ?? "").length > 0) {
            attentionObjectId = state.currentObjectId
            attentionSequence += 1
        }
        _searchMatchesSeen = matches
        _searchIndexSeen = searchIndex
        const committed = state.lastCommit
        if (committed && committed.sequence > _handledCommit) {
            _handledCommit = committed.sequence
            flashObjectId = committed.objectId
            flashSequence = committed.sequence
            _pendingLanding = committed.amend ? ""
                : Store.markMotionSeen("gitlama-commit-land|" + repository + "|" + committed.sequence) ? committed.objectId : ""
        }
        if (_pendingLanding.length > 0 && Store.historyRows.indexOf(_pendingLanding) >= 0) {
            const landed = _pendingLanding
            _pendingLanding = ""
            graphMotion.landCommit(landed)
            if (list.contentY < Theme.size.row)
                graphMotion.insertRow(1)
        }
    }

    // The search scopes and whether the typed query is the one searched.
    property bool searchHash: true
    property bool searchMessage: true
    property bool searchAuthor: true
    property bool searchPath: false
    readonly property bool queryApplied: {
        const applied = paneState.searchText
        const text = query.text.trim()
        if (applied === null || applied === undefined)
            return text.length === 0
        const scopes = paneState.searchScopes ?? ({})
        return applied === text && scopes.hash === searchHash && scopes.message === searchMessage
            && scopes.author === searchAuthor && scopes.path === searchPath
    }
    property bool showReflog: false
    property var reflog: null
    /// The upstream banner the person dismissed: "<ref>:<behind>".
    property string dismissedStale: ""
    readonly property var staleUpstream: {
        void Store.workspace.active
        return Store.history ? Store.history.staleUpstream() : null
    }
    readonly property string staleKey: staleUpstream ? staleUpstream.reference + ":" + staleUpstream.behind : ""
    readonly property var branchFilter: active ? (active.branchFilter ?? []) : []
    readonly property bool otherRefs: Store.appearance.historyOtherRefs === true

    function applyQuery() {
        Store.history.applyQuery(query.text, searchHash, searchMessage, searchAuthor, searchPath)
    }
    /// Enter searches a new query and steps through the matches of the
    /// searched one.
    function activateSearch(backwards) {
        if (!queryApplied || (paneState.searchMatches ?? 0) === 0) {
            applyQuery()
            return
        }
        Store.history.navigateSearch(backwards)
    }
    function clearSearch() {
        query.text = ""
        applyQuery()
        query.searchField.forceActiveFocus()
    }
    function focusSearch() { query.searchField.forceActiveFocus() }
    function searchFor(text) {
        query.text = text
        activateSearch(false)
    }
    function openBranchFilter() { branchFilterEditor.show(Store.history.branchFilterChoices(), branchFilter) }
    function setOtherRefs(value) { Store.app.updateAppearance({ historyOtherRefs: value }) }
    function toggleReflog() {
        showReflog = !showReflog
        if (showReflog) {
            reflog = null
            Store.history.loadReflog()
        }
    }
    Connections {
        target: Store.history
        function onReflogLoaded(value) { pane.reflog = value }
    }
    // Another repository drops the reflog and the dismissed banner.
    onActiveChanged: {
        showReflog = false
        reflog = null
    }

    // The query toolbar.
    Rectangle {
        id: toolbar
        objectName: "history-query-toolbar"
        width: parent.width
        height: Theme.size.control + 2 * Theme.space.s2
        color: Theme.colors.pane

        Flickable {
            id: toolbarScroll
            anchors.fill: parent
            anchors.leftMargin: Theme.space.s5
            anchors.rightMargin: Theme.space.s5
            contentWidth: Math.max(width, GitLamaLayout.historyQueryToolbarMinWidth)
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Item {
                width: toolbarScroll.contentWidth
                height: toolbarScroll.height
                MeridianText {
                    anchors.verticalCenter: parent.verticalCenter
                    role: MeridianText.BodyStrong
                    text: L10n.t("workspaceHistory")
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    MeridianButton {
                        id: branchFilterButton
                        objectName: "history-branch-filter"
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.branchFilter.length === 0 ? L10n.t("historyBranchFilter")
                            : L10n.tn("historyBranchFilterCount", { count: pane.branchFilter.length })
                        tooltip: L10n.t("historyBranchFilterTooltip")
                        iconName: "git-branch"
                        trailingIconName: "chevron-down"
                        variant: pane.branchFilter.length === 0 ? MeridianButton.Quiet : MeridianButton.Secondary
                        controlSize: MeridianButton.Small
                        onClicked: pane.openBranchFilter()
                        BranchFilterEditor {
                            id: branchFilterEditor
                            x: Math.min(0, branchFilterButton.width - width)
                            onChanged: filter => Store.sidebar.setBranchFilter(filter)
                        }
                    }
                    MeridianIconButton {
                        id: viewOptions
                        objectName: "history-view-options"
                        anchors.verticalCenter: parent.verticalCenter
                        text: L10n.t("historyViewOptions")
                        iconName: "eye"
                        controlSize: MeridianButton.Small
                        onClicked: {
                            viewMenu.items = [{ title: L10n.t("historyShowOtherRefs"), value: "otherRefs", checked: pane.otherRefs }]
                            viewMenu.show(viewOptions, 0, viewOptions.height)
                        }
                        CommandMenu {
                            id: viewMenu
                            onSelected: value => {
                                if (value === "otherRefs")
                                    pane.setOtherRefs(!pane.otherRefs)
                            }
                        }
                    }
                    Item { width: Theme.space.s3; height: 1 }
                    MeridianFindBar {
                        id: query
                        objectName: "history-query"
                        anchors.verticalCenter: parent.verticalCenter
                        placeholder: L10n.t("historySearchHint")
                        previousLabel: L10n.t("diffPreviousMatch")
                        nextLabel: L10n.t("diffNextMatch")
                        clearLabel: L10n.t("searchClear")
                        searchingLabel: L10n.t("findSearching")
                        noMatchesLabel: pane.queryApplied ? L10n.t("findNoMatches") : ""
                        positionText: (current, total) => L10n.tn("findMatchPosition", { current: current, total: total })
                        countText: total => L10n.tn("findMatchCount", { count: total })
                        matchCount: pane.paneState.searchMatches ?? 0
                        currentMatch: pane.paneState.searchIndex ?? -1
                        searching: pane.paneState.searchPending === true
                        // Clearing (typing, Clear, Escape) shows every commit
                        // again and keeps typing in the field.
                        onEdited: value => { if (value.length === 0) pane.clearSearch() }
                        onNext: pane.activateSearch(false)
                        onPrevious: pane.activateSearch(true)
                        Keys.onEscapePressed: pane.clearSearch()
                        trailing: [
                            MeridianIconButton {
                                id: scopesButton
                                objectName: "history-search-scopes"
                                text: L10n.t("historySearchScopes")
                                iconName: "list-filter-plus"
                                controlSize: MeridianButton.Small
                                onClicked: {
                                    scopesMenu.items = [
                                        { title: L10n.t("historySearchHash"), value: "hash", checked: pane.searchHash },
                                        { title: L10n.t("historySearchMessage"), value: "message", checked: pane.searchMessage },
                                        { title: L10n.t("historySearchAuthor"), value: "author", checked: pane.searchAuthor },
                                        { title: L10n.t("historySearchPath"), value: "path", checked: pane.searchPath },
                                    ]
                                    scopesMenu.show(scopesButton, 0, scopesButton.height)
                                }
                                CommandMenu {
                                    id: scopesMenu
                                    onSelected: value => {
                                        if (value === "hash") pane.searchHash = !pane.searchHash
                                        else if (value === "message") pane.searchMessage = !pane.searchMessage
                                        else if (value === "author") pane.searchAuthor = !pane.searchAuthor
                                        else if (value === "path") pane.searchPath = !pane.searchPath
                                    }
                                }
                            },
                            MeridianIconButton {
                                objectName: "history-apply-filter"
                                text: L10n.t("historyApplyFilter")
                                iconName: "inspect"
                                controlSize: MeridianButton.Small
                                onClicked: pane.applyQuery()
                            }
                        ]
                    }
                    MeridianIconButton {
                        objectName: "history-collapse-selected"
                        anchors.verticalCenter: parent.verticalCenter
                        text: L10n.t("historyCollapseSelected")
                        iconName: "git-merge"
                        controlSize: MeridianButton.Small
                        enabled: pane.paneState.canCollapse === true
                        onClicked: Store.history.toggleCollapse((pane.paneState.selectedIds ?? [])[0] ?? "")
                    }
                    MeridianButton {
                        objectName: "history-reflog-toggle"
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.showReflog ? L10n.t("historyGraph") : L10n.t("historyReflog")
                        variant: MeridianButton.Quiet
                        iconName: pane.showReflog ? "branch" : "history"
                        controlSize: MeridianButton.Small
                        onClicked: pane.toggleReflog()
                    }
                }
            }
        }
        MeridianHairline {
            anchors.bottom: parent.bottom
            width: parent.width
        }
    }

    // Power tools dock under the query bar.
    Loader {
        id: powerTools
        anchors.top: toolbar.bottom
        width: parent.width
        height: active ? item.implicitHeight : 0
        active: Store.shell !== null && Store.shell.panel === "powerTools"
        sourceComponent: Column {
            width: pane.width
            WorkflowHeader {
                width: parent.width
                title: L10n.t("powerToolsTitle")
                exitLabel: L10n.t("close")
                onExit: Store.shell.closePanel("powerTools")
            }
            Rectangle {
                width: parent.width
                height: Math.min(GitLamaLayout.powerToolsDockedMaxHeight, pane.Window.height * GitLamaLayout.powerToolsDockedHeightFraction)
                color: Theme.colors.paneAlt
                PowerTools {
                    anchors.fill: parent
                    docked: true
                    onCloseRequested: Store.shell.closePanel("powerTools")
                }
            }
            MeridianHairline { width: parent.width }
        }
    }

    // The upstream banner and History's one notice, above the graph.
    Column {
        id: notices
        anchors.top: powerTools.bottom
        width: parent.width

        Item {
            visible: pane.staleUpstream !== null && pane.staleKey !== pane.dismissedStale
            width: parent.width
            height: visible ? staleBanner.implicitHeight + 2 * Theme.space.s2 : 0
            MeridianBanner {
                id: staleBanner
                objectName: "history-stale-upstream"
                x: Theme.space.s2
                y: Theme.space.s2
                width: parent.width - 2 * Theme.space.s2
                tone: MeridianBanner.Info
                message: pane.staleUpstream ? L10n.tn("historyNewUpstreamCommits", { count: pane.staleUpstream.behind, ref: pane.staleUpstream.reference }) : ""
                MeridianButton {
                    text: L10n.t("workspaceRefresh")
                    controlSize: MeridianButton.Small
                    onClicked: {
                        Store.history.reload()
                        pane.dismissedStale = pane.staleKey
                    }
                }
                MeridianButton {
                    text: L10n.t("operationsDismiss")
                    variant: MeridianButton.Quiet
                    controlSize: MeridianButton.Small
                    onClicked: pane.dismissedStale = pane.staleKey
                }
            }
        }
        Item {
            readonly property var notice: {
                const state = pane.paneState
                if (pane.showReflog)
                    return null
                if (state.searchPending)
                    return { message: L10n.tn("historyPendingFilter", { filter: state.searchText ?? "" }), progress: true }
                if (state.searchFailure || state.queryFailure)
                    return { message: L10n.t("historyFilterFailed") }
                if ((state.branchFilterCount ?? 0) > 0 && (state.total ?? 0) === 0)
                    return { message: L10n.t("historyBranchFilterNoCommits"), action: "showAll" }
                if (state.targetNotShown)
                    return state.otherRefs ? { message: L10n.t("historyTargetNotShown") }
                                           : { message: L10n.t("historyTargetOutsideRefScope"), action: "otherRefs" }
                if (state.selectedFilteredOut)
                    return { message: L10n.t("historySelectionFilteredOut") }
                if (state.queryActive)
                    return { message: L10n.tn("historyAcceptedFilter", { filter: state.acceptedQuery ?? "" }) }
                if ((state.collapsedCommits ?? 0) > 0)
                    return { message: L10n.tn("historyCollapsedCount", { count: state.collapsedCommits }) }
                return null
            }
            visible: notice !== null
            width: parent.width
            height: visible ? noticeBanner.implicitHeight + 2 * Theme.space.s1 : 0
            MeridianBanner {
                id: noticeBanner
                objectName: "history-notice"
                x: Theme.space.s2
                y: Theme.space.s1
                width: parent.width - 2 * Theme.space.s2
                tone: MeridianBanner.Info
                message: parent.notice ? parent.notice.message : ""
                Accessible.role: Accessible.AlertMessage
                MeridianSpinner {
                    visible: noticeBanner.parent.notice !== null && noticeBanner.parent.notice.progress === true
                }
                MeridianButton {
                    objectName: "history-branch-filter-show-all"
                    visible: noticeBanner.parent.notice !== null && noticeBanner.parent.notice.action === "showAll"
                    text: L10n.t("historyBranchFilterShowAll")
                    controlSize: MeridianButton.Small
                    onClicked: Store.sidebar.setBranchFilter([])
                }
                MeridianButton {
                    objectName: "history-show-other-refs"
                    visible: noticeBanner.parent.notice !== null && noticeBanner.parent.notice.action === "otherRefs"
                    text: L10n.t("historyShowOtherRefs")
                    controlSize: MeridianButton.Small
                    onClicked: {
                        pane.setOtherRefs(true)
                        const target = pane.paneState.targetObjectId
                        if (target)
                            Store.history.showCommit(target)
                    }
                }
            }
        }
    }

    Item {
        id: body
        anchors.top: notices.bottom
        anchors.bottom: parent.bottom
        width: parent.width

        MeridianEmptyState {
            anchors.fill: parent
            visible: pane.paneState.phase === "failed"
            compact: true
            iconName: "circle-alert"
            title: L10n.t("workspaceUnavailableRepository")
            MeridianButton {
                text: L10n.t("historyRetryLoad")
                iconName: "rotate-ccw"
                controlSize: MeridianButton.Small
                onClicked: Store.history.reload()
            }
        }
        // A repository without commits (no page), or a page that shows no
        // rows.
        MeridianEmptyState {
            anchors.fill: parent
            visible: pane.paneState.phase !== "failed" && pane.paneState.phase !== "loading" && pane.paneState.empty === true
                && pane.paneState.hasPage === true
            compact: true
            iconName: "history"
            title: L10n.t("workspaceEmptyHistory")
        }
        MeridianEmptyState {
            anchors.fill: parent
            visible: pane.paneState.phase !== "failed" && pane.paneState.phase !== "loading" && pane.paneState.hasPage !== true
            headline: true
            title: L10n.t("historyNoCommitsYet")
            MeridianButton {
                text: L10n.t("historyOpenChanges")
                onClicked: Store.actions.runCommand("showChanges", ({}))
            }
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
            MeridianSelectionGlide {
                view: list
                itemExtent: Theme.size.row
                selectedIndex: pane.glideIndex
            }

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
                glided: pane.glideIndex >= 0
                motion: graphMotion
                flashTrigger: objectId === pane.flashObjectId ? pane.flashSequence : 0
                attentionTrigger: objectId === pane.attentionObjectId ? pane.attentionSequence : 0
                entranceOrder: pane.syncEntranceIds.indexOf(objectId)
                entranceKey: entranceOrder >= 0 ? "history-sync-row|" + objectId + "|" + pane.syncEntranceSequence : ""
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

        // The reflog in place of the graph.
        Rectangle {
            visible: pane.showReflog
            anchors.fill: parent
            color: Theme.colors.pane
            MeridianEmptyState {
                visible: pane.reflog === null || pane.reflog.entries.length === 0
                anchors.fill: parent
                compact: true
                progress: pane.reflog === null
                iconName: pane.reflog === null ? "" : "history"
                title: pane.reflog === null ? L10n.t("loading") : L10n.t("historyReflogEmpty")
            }
            Column {
                visible: pane.reflog !== null && pane.reflog.entries.length > 0
                anchors.fill: parent
                Item {
                    visible: pane.reflog !== null && pane.reflog.retainedAfterFailure === true
                    width: parent.width
                    height: visible ? retainedBanner.implicitHeight + 2 * Theme.space.s1 : 0
                    MeridianBanner {
                        id: retainedBanner
                        x: Theme.space.s2
                        y: Theme.space.s1
                        width: parent.width - 2 * Theme.space.s2
                        tone: MeridianBanner.Info
                        message: L10n.t("historyReflogRetainedFailure")
                    }
                }
                ListView {
                    id: reflogList
                    objectName: "history-reflog"
                    width: parent.width
                    height: parent.height - y
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: pane.reflog ? pane.reflog.entries : []
                    MeridianWheelScroll { flickable: reflogList }
                    C.ScrollBar.vertical: MeridianScrollBar {}
                    delegate: MeridianListRow {
                        id: reflogRow
                        required property var modelData
                        width: reflogList.width
                        height: Theme.size.row
                        text: modelData.summary
                        iconName: "history"
                        trailing: Component {
                            MeridianText {
                                role: MeridianText.Caption
                                text: reflogRow.modelData.short
                            }
                        }
                        onClicked: {
                            pane.showReflog = false
                            Store.history.reveal(modelData.commit)
                        }
                    }
                }
            }
        }

        MeridianSpinner {
            visible: pane.paneState.phase === "preview" || pane.paneState.phase === "loading"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.space.s4
        }
    }
}
