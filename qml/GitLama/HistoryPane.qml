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

    readonly property var state: Store.history ? (Store.history.state ?? ({})) : ({})
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
    onStateChanged: {
        const sequence = state.revealSequence ?? 0
        if (sequence !== _revealSequence) {
            _revealSequence = sequence
            if (state.revealIndex !== null && state.revealIndex !== undefined)
                Qt.callLater(() => list.positionViewAtIndex(state.revealIndex, ListView.Contain))
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
                    if (pane.state.searchText === text.trim() && (pane.state.searchMatches ?? 0) > 0)
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
            visible: pane.state.phase === "failed"
            compact: true
            iconName: "circle-alert"
            title: L10n.t("workspaceUnavailableRepository")
        }
        MeridianEmptyState {
            anchors.fill: parent
            visible: pane.state.phase !== "failed" && pane.state.phase !== "loading" && pane.state.empty === true
            compact: true
            iconName: "history"
            title: L10n.t("workspaceEmptyHistory")
        }

        ListView {
            id: list
            objectName: "history-graph"
            anchors.fill: parent
            anchors.margins: pane.listPadding
            visible: pane.state.phase !== "failed" && pane.state.empty !== true
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
                width: list.width
                height: Theme.size.row
                metadataLeft: pane.metadataLeft
                authorWidth: pane.authorWidth
                hashWidth: pane.hashWidth
                dateWidth: pane.dateWidth
                lightingActive: pane.state.lightingActive === true
                queryActive: pane.state.queryActive === true
                dateFormat: pane.dateFormat
                selectedHere: objectId === pane.selectedObjectId
                onActivated: (objectId, toggle) => pane.select(objectId, toggle)
                onDoubleActivated: objectId => pane.command("checkoutCommit", { initialTarget: objectId })
                onCopyRequested: value => Store.actions.copyText(value, L10n.t("historyObjectIdCopied"))
            }

            footer: Item {
                width: list.width
                height: Theme.size.row
                visible: pane.state.phase === "complete"
                MeridianText {
                    anchors.centerIn: parent
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: L10n.tn("historyEndOfHistory", { count: (pane.state.total ?? 0) - (pane.state.worktreeRows ?? 0) })
                }
            }
        }
        HoverHandler { id: listHover }

        MeridianSpinner {
            visible: pane.state.phase === "preview" || pane.state.phase === "loading"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.space.s4
        }
    }
}
