pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The logbook: every operation of the
// application, newest work first, filtered by who started it; the selected
// entry's command and output with Retry, Cancel, Dismiss, Copy and Details.
MeridianPanel {
    id: panel

    property string origin: "all"
    property string selectedKey: ""
    /// Loaded details by entry key: {record, expired, failed}.
    property var details: ({})
    readonly property var center: Store.operations ? (Store.operations.center ?? ({})) : ({})
    readonly property var entries: (center.entries ?? []).filter(entry => origin === "all" || entry.origin === origin)
    readonly property var selectedEntry: entries.find(entry => entry.key === selectedKey) ?? entries[0] ?? null
    signal showDetails(string key)

    title: L10n.t("logbookTitle")
    closeLabel: L10n.t("close")
    transformOrigin: Item.TopRight
    leftPadding: 0
    rightPadding: 0
    bottomPadding: Theme.space.s4
    width: Math.min(GitLamaLayout.logbookWidth, (Window.window ? Window.window.width : GitLamaLayout.logbookWidth) - 2 * Theme.space.s3)
    height: Math.min(implicitHeight, (Window.window ? Window.window.height : 800) * 0.72)

    function actionLabel(action) {
        if (!action)
            return ""
        return L10n.t("operation" + action.charAt(0).toUpperCase() + action.slice(1))
    }
    function load(entry) {
        if (!entry || !entry.hasDetails || details[entry.key] !== undefined)
            return
        const next = Object.assign({}, details)
        next[entry.key] = { loading: true }
        details = next
        Store.operations.loadDetails(entry.key)
    }
    onSelectedEntryChanged: load(selectedEntry)

    // The rows shown, keyed so their delegates persist: an entry that goes (dismissed,
    // cleared) fades and collapses in place, bottom-up (MM-22); one that comes grows in and
    // enters (MM-24). Changing the filter swaps the rows at once.
    ListModel { id: rows }
    property var entryByKey: ({})
    /// Entries on their way out, by key.
    property var leavingEntries: ({})
    /// The keys seen so far, so a new entry grows in.
    property var _knownKeys: ({})
    property string _originShown: origin
    onEntriesChanged: _sync()
    Component.onCompleted: _sync()

    function _sync() {
        const animate = _originShown === origin && rows.count > 0 && !Motion.reduced
        _originShown = origin
        const byKey = {}
        for (const entry of entries)
            byKey[entry.key] = entry
        const target = entries.map(entry => ({ key: entry.key, leaving: false, fresh: animate && _knownKeys[entry.key] !== true }))
        const leaving = Object.assign({}, animate ? leavingEntries : {})
        if (animate) {
            for (let i = 0; i < rows.count; ++i) {
                const row = rows.get(i)
                if (byKey[row.key] !== undefined)
                    continue
                if (!row.leaving)
                    leaving[row.key] = entryByKey[row.key] ?? leavingEntries[row.key]
                if (leaving[row.key] === undefined)
                    continue
                target.splice(Math.min(i, target.length), 0, { key: row.key, leaving: true, fresh: false })
                // The entry that takes a dismissed selection's place takes the selection.
                if (row.key === selectedKey && entries.length > 0)
                    selectedKey = entries[Math.min(i, entries.length - 1)].key
            }
        }
        for (const key in leaving)
            if (byKey[key] !== undefined)
                delete leaving[key]
        for (const entry of entries)
            _knownKeys[entry.key] = true
        entryByKey = byKey
        leavingEntries = leaving
        _apply(target)
    }
    function _apply(target) {
        const wanted = {}
        for (const item of target)
            wanted[item.key] = true
        for (let i = rows.count - 1; i >= 0; --i)
            if (wanted[rows.get(i).key] !== true)
                rows.remove(i)
        for (let i = 0; i < target.length; ++i) {
            const item = target[i]
            if (i < rows.count && rows.get(i).key === item.key) {
                if (rows.get(i).leaving !== item.leaving)
                    rows.setProperty(i, "leaving", item.leaving)
                continue
            }
            let found = -1
            for (let j = i + 1; j < rows.count; ++j) {
                if (rows.get(j).key === item.key) {
                    found = j
                    break
                }
            }
            if (found >= 0) {
                rows.move(found, i, 1)
                rows.setProperty(i, "leaving", item.leaving)
            } else {
                rows.insert(i, item)
            }
        }
    }
    /// How many leaving rows sit below row `index`: removals run bottom-up.
    function leavingBelow(index) {
        let count = 0
        for (let i = index + 1; i < rows.count; ++i)
            if (rows.get(i).leaving)
                count += 1
        return count
    }
    function removeLeft(key) {
        for (let i = 0; i < rows.count; ++i) {
            if (rows.get(i).key === key && rows.get(i).leaving) {
                rows.remove(i)
                break
            }
        }
        const leaving = Object.assign({}, leavingEntries)
        delete leaving[key]
        leavingEntries = leaving
    }

    Connections {
        target: Store.operations
        function onDetailsLoaded(key, record, expired) {
            const next = Object.assign({}, panel.details)
            next[key] = { record: record, expired: expired }
            panel.details = next
        }
    }

    Column {
        width: parent ? parent.width : 0
        Item {
            width: parent.width
            height: filter.height + Theme.space.s4
            MeridianSegmented {
                id: filter
                x: Theme.space.s6
                width: dismissAll.x - x - Theme.space.s3
                controlSize: MeridianButton.Small
                expand: true
                label: L10n.t("operationsFilterAll")
                segments: [{ value: "all", label: L10n.t("operationsFilterAll") },
                           { value: "user", label: L10n.t("operationsFilterUser") },
                           { value: "background", label: L10n.t("operationsFilterBackground") }]
                value: panel.origin
                onActivated: value => panel.origin = value
            }
            MeridianIconButton {
                id: dismissAll
                x: parent.width - width - Theme.space.s5
                anchors.verticalCenter: filter.verticalCenter
                iconName: "brush-cleaning"
                text: L10n.t("operationsDismissAll")
                controlSize: MeridianButton.Small
                enabled: (panel.center.failed ?? 0) > 0 || (panel.center.warning ?? 0) > 0
                onClicked: Store.operations.dismissAll()
            }
        }
        MeridianText {
            visible: rows.count === 0
            x: Theme.space.s6
            width: parent.width - 2 * Theme.space.s6
            topPadding: Theme.space.s6
            bottomPadding: Theme.space.s6
            color: Theme.colors.inkMuted
            text: L10n.t("operationsEmpty")
        }
        ListView {
            id: list
            visible: rows.count > 0
            width: parent.width
            height: Math.min(contentHeight, (Window.window ? Window.window.height : 800) * 0.72 - panel.headerHeight - filter.height - 2 * Theme.space.s4)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: rows
            MeridianWheelScroll { flickable: list }
            C.ScrollBar.vertical: MeridianScrollBar {}
            delegate: Item {
                id: slot
                required property string key
                required property bool leaving
                required property bool fresh
                required property int index
                readonly property var entry: leaving ? panel.leavingEntries[key] : panel.entryByKey[key]
                width: ListView.view.width
                height: reveal.implicitHeight
                visible: entry !== undefined
                Timer {
                    id: leaveWait
                    onTriggered: reveal.shown = false
                }
                onLeavingChanged: _leave()
                Component.onCompleted: _leave()
                function _leave() {
                    if (!leaving || leaveWait.running || !reveal.shown)
                        return
                    leaveWait.interval = Math.max(1, Motion.stagger * Math.min(panel.leavingBelow(index), GitLamaLayout.logbookLeaveStaggerMax))
                    leaveWait.start()
                }
                MeridianReveal {
                    id: reveal
                    width: slot.width
                    appear: slot.fresh
                    onHidden: panel.removeLeft(slot.key)
                    TimelineRow {
                        id: entryRow
                        readonly property var modelData: slot.entry ?? ({})
                        readonly property int index: slot.index
                        width: slot.width
                        enabled: !slot.leaving
                        state_: ({ running: "running", succeeded: "succeeded", warning: "warning", attention: "warning",
                                   failed: "failed", canceled: "cancelled" })[modelData.state] ?? "running"
                        shakeOnFailure: true
                        entranceKey: "logbook-entry|" + modelData.key
                        entranceOrder: index
                        entranceActive: panel.visible
                        verb: modelData.count > 1 ? L10n.tn("logbookRepeatedFetch", { count: modelData.count }) : panel.actionLabel(modelData.action)
                        target: modelData.count > 1 ? "" : (modelData.repository ?? L10n.t("operationRepositoryApplication"))
                        metadata: [modelData.repository ?? L10n.t("operationRepositoryApplication"),
                                   modelData.elapsed !== null && modelData.elapsed !== undefined
                                       ? L10n.tn("logbookDurationSeconds", { seconds: (modelData.elapsed / 1000).toFixed(1) }) : "",
                                   Labels.operationProgress(modelData.progress)].filter(part => part.length > 0).join(" · ")
                        time: Qt.formatTime(new Date(modelData.started), Qt.locale().timeFormat(Locale.ShortFormat))
                        first: index === 0
                        last: index === rows.count - 1
                        selected: panel.selectedEntry !== null && panel.selectedEntry.key === modelData.key
                        onActivated: panel.selectedKey = modelData.key
                        details: Component {
                            Column {
                                id: detail
                                readonly property var loaded: panel.details[entryRow.modelData.key]
                                width: parent ? parent.width : 0
                                spacing: Theme.space.s3
                                MeridianText {
                                    visible: !entryRow.modelData.hasDetails || (detail.loaded !== undefined && !detail.loaded.loading && detail.loaded.record === null)
                                    width: parent.width
                                    role: MeridianText.Caption
                                    color: Theme.colors.inkMuted
                                    wrapMode: Text.Wrap
                                    text: detail.loaded && detail.loaded.expired ? L10n.t("operationsDetailsExpired") : L10n.t("operationsDetailsUnavailable")
                                }
                                MeridianSpinner { visible: detail.loaded !== undefined && detail.loaded.loading === true; immediate: true }
                                Flickable {
                                    id: output
                                    visible: detail.loaded !== undefined && detail.loaded.record !== null && detail.loaded.record !== undefined
                                    width: parent.width
                                    height: Math.min(GitLamaLayout.logbookOutputMaxHeight, outputText.implicitHeight)
                                    contentHeight: outputText.implicitHeight
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    MeridianWheelScroll { flickable: output }
                                    MeridianSelectableText {
                                        id: outputText
                                        width: output.width
                                        role: MeridianText.CodeSm
                                        color: Theme.colors.inkMuted
                                        wrapMode: Text.Wrap
                                        text: output.visible ? "$ " + detail.loaded.record.executable + " " + detail.loaded.record.arguments
                                            + "\n\n" + detail.loaded.record.output : ""
                                    }
                                }
                                Flow {
                                    width: parent.width
                                    spacing: Theme.space.s3
                                    MeridianButton {
                                        visible: entryRow.modelData.canRetry
                                        text: L10n.t("retry")
                                        variant: MeridianButton.Secondary
                                        controlSize: MeridianButton.Small
                                        onClicked: Store.operations.retry(entryRow.modelData.key)
                                    }
                                    MeridianButton {
                                        visible: entryRow.modelData.canCancel
                                        text: L10n.t("cancel")
                                        variant: MeridianButton.DangerQuiet
                                        controlSize: MeridianButton.Small
                                        onClicked: Store.operations.cancel(entryRow.modelData.key)
                                    }
                                    MeridianButton {
                                        visible: entryRow.modelData.state === "failed" || entryRow.modelData.state === "warning"
                                        text: L10n.t("operationsDismiss")
                                        variant: MeridianButton.Quiet
                                        controlSize: MeridianButton.Small
                                        onClicked: Store.operations.dismiss(entryRow.modelData.key)
                                    }
                                    MeridianButton {
                                        visible: output.visible
                                        text: L10n.t("activityCopy")
                                        variant: MeridianButton.Quiet
                                        controlSize: MeridianButton.Small
                                        onClicked: {
                                            const record = detail.loaded.record
                                            const command = record.executable + " " + record.arguments
                                            Store.actions.copyText(record.output.length > 0 ? command + "\n\n" + record.output : command, L10n.t("activityCopied"))
                                        }
                                    }
                                    MeridianButton {
                                        visible: output.visible
                                        text: L10n.t("operationsDetails")
                                        variant: MeridianButton.Quiet
                                        controlSize: MeridianButton.Small
                                        onClicked: panel.showDetails(entryRow.modelData.key)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
