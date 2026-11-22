pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The conflict resolver (the Dart ConflictResolver): replaces Changes while
// an operation is paused at conflicts. A header with Continue, Skip, Abort
// and Exit; the steps of the way through; the conflicted files beside the
// shown file's comparison and result; and once none is left, the resolved
// files and the merge message.
FocusScope {
    id: resolver

    readonly property var conflictState: Store.conflicts ? (Store.conflicts.state ?? ({})) : ({})
    readonly property bool ready: conflictState.ready === true
    readonly property bool busy: conflictState.busy === true
    readonly property var files: conflictState.files ?? []
    readonly property var file: conflictState.file ?? null
    readonly property int selected: conflictState.selected ?? 0
    readonly property bool standalone: conflictState.operation === "standalone"
    /// Ticked files, by key, for resolving together.
    property var checked: []
    property string checkAnchor: ""
    property real fileListWidth: GitLamaLayout.conflictFileListWidth
    property bool _finishReported: false

    signal command(string id, var options)

    Component.onCompleted: {
        Store.conflicts.load()
        if (Store.actions)
            Store.actions.conflictResolver = resolver
    }
    Component.onDestruction: {
        if (Store.actions && Store.actions.conflictResolver === resolver)
            Store.actions.conflictResolver = null
    }
    onConflictStateChanged: {
        // A file that left the conflicts loses its tick.
        const keys = files.map(file => file.key)
        const kept = checked.filter(key => keys.indexOf(key) >= 0)
        if (kept.length !== checked.length)
            checked = kept
        if (conflictState.finished === true && !_finishReported) {
            _finishReported = true
            Store.conflicts.finish()
        }
    }

    function toggleChecked(key, on, shift) {
        const keys = files.map(file => file.key)
        const from = keys.indexOf(checkAnchor)
        const to = keys.indexOf(key)
        const range = shift && from >= 0 ? keys.slice(Math.min(from, to), Math.max(from, to) + 1) : [key]
        let next = checked.filter(item => range.indexOf(item) < 0)
        if (on)
            next = next.concat(range)
        checked = next
        checkAnchor = key
    }
    function sideLabel(side) {
        return side === "current" ? (conflictState.currentLabel ?? "") : (conflictState.incomingLabel ?? "")
    }
    function selectFile(index, lastRegion) {
        if (!busy && index >= 0 && index < files.length && index !== selected)
            Store.conflicts.select(index, lastRegion === true)
    }
    /// The next or previous conflict, across files.
    function stepConflict(delta) {
        const regions = file ? (file.regions ?? 0) : 0
        const focused = file ? (file.focusedRegion ?? 0) : 0
        if (file && file.kind === "text" && focused + delta >= 0 && focused + delta < regions) {
            comparison.showRegion(focused + delta)
            return
        }
        selectFile(selected + delta, delta < 0)
    }
    /// Commands from menus and shortcuts reach the shown resolver.
    function runCommand(id) {
        switch (id) {
        case "conflictNext": stepConflict(1); return true
        case "conflictPrevious": stepConflict(-1); return true
        case "conflictTakeCurrent": Store.conflicts.takeFocused("current"); return true
        case "conflictTakeIncoming": Store.conflicts.takeFocused("incoming"); return true
        case "conflictTakeBoth": Store.conflicts.takeFocused("both"); return true
        case "rebaseContinue": Store.conflicts.sequence("continue"); return true
        case "rebaseAbort": Store.conflicts.sequence("abort"); return true
        }
        return false
    }

    Shortcut { sequences: ["Ctrl+S"]; enabled: resolver.visible && resolver.ready; onActivated: Store.conflicts.save() }
    Shortcut { sequence: "Alt+Left"; enabled: resolver.visible; onActivated: resolver.selectFile(resolver.selected - 1) }
    Shortcut { sequence: "Alt+Right"; enabled: resolver.visible; onActivated: resolver.selectFile(resolver.selected + 1) }
    Shortcut { sequence: "Ctrl+Return"; enabled: resolver.visible; onActivated: Store.conflicts.sequence("continue") }

    // Loading or failed.
    MeridianIsland {
        visible: !resolver.ready || resolver.conflictState.loadFailed === true
        anchors.fill: parent
        Column {
            anchors.centerIn: parent
            spacing: Theme.space.s5
            MeridianText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: resolver.conflictState.loadFailed === true ? L10n.t("conflictLoadFailed") : L10n.t("conflictLoading")
                Accessible.role: Accessible.AlertMessage
                Accessible.name: text
            }
            MeridianButton {
                visible: resolver.conflictState.loadFailed === true
                anchors.horizontalCenter: parent.horizontalCenter
                text: L10n.t("workspaceRefresh")
                variant: MeridianButton.Secondary
                onClicked: Store.conflicts.load()
            }
        }
    }

    Column {
        id: content
        visible: resolver.ready && resolver.conflictState.loadFailed !== true
        anchors.fill: parent

        WorkflowHeader {
            id: header
            width: parent.width
            title: L10n.t("conflictResolverTitle")
            status: {
                const operation = L10n.t("conflictOperation" + (resolver.conflictState.operation ?? "standalone").charAt(0).toUpperCase()
                                         + (resolver.conflictState.operation ?? "standalone").slice(1))
                const steps = resolver.conflictState.steps
                return steps !== null && steps !== undefined && resolver.conflictState.step !== null && resolver.conflictState.step !== undefined
                    ? operation + " · " + L10n.tn("conflictStepProgress", { current: resolver.conflictState.step, total: steps }) : operation
            }
            exitLabel: L10n.t("workflowExit")
            onExit: Store.conflicts.finish()
            readonly property bool compact: resolver.Window.window ? resolver.Window.window.width < 1100 : false

            MeridianSpinner { visible: resolver.busy; anchors.verticalCenter: parent ? parent.verticalCenter : undefined; immediate: true }
            MeridianButton {
                visible: !header.compact && resolver.conflictState.canSkip === true
                text: L10n.t("conflictSkip")
                variant: MeridianButton.Quiet
                controlSize: MeridianButton.Small
                enabled: !resolver.busy
                onClicked: Store.conflicts.sequence("skip")
            }
            MeridianButton {
                visible: !header.compact && !resolver.standalone
                text: L10n.t("conflictAbort")
                variant: MeridianButton.DangerQuiet
                controlSize: MeridianButton.Small
                enabled: !resolver.busy
                onClicked: Store.conflicts.sequence("abort")
            }
            MeridianIconButton {
                id: moreButton
                visible: header.compact
                iconName: "more"
                text: L10n.t("toolbarMore")
                controlSize: MeridianButton.Small
                onClicked: {
                    const items = []
                    if (resolver.conflictState.canSkip === true)
                        items.push({ title: L10n.t("conflictSkip"), value: "skip", enabled: !resolver.busy })
                    if (!resolver.standalone)
                        items.push({ title: L10n.t("conflictAbort"), value: "abort", enabled: !resolver.busy })
                    sequenceMenu.items = items
                    sequenceMenu.show(moreButton, 0, moreButton.height)
                }
                CommandMenu { id: sequenceMenu; onSelected: value => Store.conflicts.sequence(value) }
            }
            MeridianIconButton {
                iconName: "external-link"
                text: L10n.t("conflictExternalTool")
                controlSize: MeridianButton.Small
                enabled: false
                disabledReason: L10n.t("conflictExternalUnavailable")
            }
            MeridianIconButton {
                iconName: "refresh"
                text: L10n.t("workspaceRefresh")
                controlSize: MeridianButton.Small
                enabled: !resolver.busy
                onClicked: Store.conflicts.load()
            }
            primary: [
                MeridianButton {
                    visible: !resolver.standalone
                    text: L10n.t("conflictContinue")
                    variant: MeridianButton.Primary
                    controlSize: MeridianButton.Small
                    enabled: !resolver.busy && resolver.conflictState.canContinue === true
                        && (resolver.conflictState.operation !== "merge" || (resolver.conflictState.mergeSubject ?? "").trim().length > 0)
                    onClicked: Store.conflicts.sequence("continue")
                }
            ]
        }
        MeridianHairline { width: parent.width }

        // The way through the conflicts and what to do now.
        Item {
            id: guide
            width: parent.width
            height: guideColumn.implicitHeight + 2 * Theme.space.s3
            readonly property int resolvedCount: (resolver.conflictState.resolved ?? []).length
            readonly property int total: resolvedCount + resolver.files.length
            readonly property var guideState: {
                const f = resolver.files.length === 0 ? null : resolver.file
                if (f === null)
                    return [resolver.standalone ? 4 : 3, L10n.t(resolver.standalone ? "conflictGuideDone" : "conflictGuideContinue")]
                if (f.side)
                    return [1, L10n.t(f.deletionChosen ? "conflictGuideReviewDeletion" : "conflictGuideReview")]
                if (f.currentPresent !== f.incomingPresent)
                    return [0, L10n.t("conflictGuideDecideDeletion")]
                if (f.kind !== "text")
                    return [0, L10n.t("conflictChooseVersion")]
                if ((f.markers ?? 0) > 0)
                    return [0, L10n.tn("conflictGuidePick", { count: f.markers })]
                return [1, L10n.t("conflictGuideReview")]
            }
            Column {
                id: guideColumn
                x: Theme.space.s5
                y: Theme.space.s3
                width: parent.width - 2 * Theme.space.s5
                spacing: Theme.space.s2
                MeridianSteps {
                    width: parent.width
                    semanticLabel: L10n.t("conflictGuideTitle")
                    doneLabel: L10n.t("stepStateDone")
                    currentLabel: L10n.t("stepStateCurrent")
                    upcomingLabel: L10n.t("stepStateUpcoming")
                    current: guide.guideState[0]
                    steps: [L10n.t("conflictStepPick"), L10n.t("conflictStepReview"), L10n.t("conflictStepResolve"),
                            L10n.t(resolver.standalone ? "conflictStepDone" : "conflictStepContinue")]
                }
                Item {
                    width: parent.width
                    height: hint.implicitHeight
                    MeridianText {
                        id: hint
                        width: parent.width - (count.visible ? count.width + Theme.space.s3 : 0)
                        role: MeridianText.Caption
                        text: guide.guideState[1]
                    }
                    MeridianText {
                        id: count
                        visible: guide.total > 1
                        x: parent.width - width
                        role: MeridianText.Caption
                        color: Theme.colors.inkMuted
                        text: L10n.tn("conflictGuideResolvedCount", { resolved: guide.resolvedCount, total: guide.total })
                    }
                }
            }
        }
        MeridianHairline { width: parent.width }

        Item {
            id: body
            width: parent.width
            height: content.height - header.height - guide.height - footer.height - 3 * Metrics.hairline

            MeridianIsland {
                visible: resolver.files.length === 0
                anchors.fill: parent
                Column {
                    anchors.fill: parent
                    RepositoryConditions {
                        width: parent.width
                        onCommand: id => resolver.command(id, ({}))
                        onSkip: Store.conflicts.sequence("skip")
                    }
                    ConflictResolvedPage {
                        width: parent.width
                        height: parent.height - y
                        conflictState: resolver.conflictState
                    }
                }
            }

            // The conflicted files.
            MeridianIsland {
                id: filesIsland
                visible: resolver.files.length > 0
                width: Math.max(GitLamaLayout.conflictFileListMinWidth,
                                Math.min(resolver.fileListWidth, body.width - GitLamaLayout.conflictEditorMinWidth - Theme.space.s3))
                height: parent.height
                Column {
                    id: filesColumn
                    anchors.fill: parent
                    RepositoryConditions {
                        id: conditions
                        width: parent.width
                        onCommand: id => resolver.command(id, ({}))
                        onSkip: Store.conflicts.sequence("skip")
                    }
                    MeridianSectionHeader {
                        id: filesHeader
                        width: parent.width
                        title: L10n.t("conflictFilesTitle")
                        count: resolver.files.length
                    }
                    Item {
                        id: selectAllRow
                        width: parent.width
                        height: selectAll.implicitHeight + Theme.space.s3 + Theme.space.s2
                        readonly property int count: resolver.files.filter(file => resolver.checked.indexOf(file.key) >= 0).length
                        MeridianCheckbox {
                            id: selectAll
                            x: Theme.space.s4 + Theme.space.s2
                            y: Theme.space.s3
                            tristate: true
                            checkState: selectAllRow.count === 0 ? Qt.Unchecked
                                : selectAllRow.count === resolver.files.length ? Qt.Checked : Qt.PartiallyChecked
                            nextCheckState: () => selectAllRow.count === resolver.files.length ? Qt.Unchecked : Qt.Checked
                            text: selectAllRow.count === 0 ? L10n.t("conflictSelectAll") : L10n.tn("conflictSelectedCount", { count: selectAllRow.count })
                            enabled: !resolver.busy
                            onClicked: {
                                resolver.checkAnchor = ""
                                resolver.checked = selectAllRow.count === resolver.files.length ? [] : resolver.files.map(file => file.key)
                            }
                        }
                    }
                    ListView {
                        id: fileList
                        width: parent.width
                        height: parent.height - y - bulk.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: resolver.files
                        MeridianWheelScroll { flickable: fileList }
                        C.ScrollBar.vertical: MeridianScrollBar {}
                        delegate: FileRow {
                            id: fileRow
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            path: modelData.path
                            status: "U"
                            selected: index === resolver.selected
                            onClicked: resolver.selectFile(index)
                            leading: Component {
                                MeridianCheckbox {
                                    checked: resolver.checked.indexOf(fileRow.modelData.key) >= 0
                                    enabled: !resolver.busy
                                    Accessible.name: fileRow.modelData.path
                                    onClicked: resolver.toggleChecked(fileRow.modelData.key, checked, false)
                                    TapHandler {
                                        acceptedModifiers: Qt.ShiftModifier
                                        onTapped: resolver.toggleChecked(fileRow.modelData.key, !parent.checked, true)
                                    }
                                }
                            }
                            trailing: Component {
                                Row {
                                    spacing: Theme.space.s2
                                    MeridianIcon {
                                        visible: fileRow.modelData.deletion !== null && fileRow.modelData.deletion !== undefined
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "trash-2"
                                        iconSize: MeridianIcon.Small
                                        color: Theme.colors.danger
                                    }
                                    MeridianIcon {
                                        visible: fileRow.modelData.remaining === null || fileRow.modelData.remaining === 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "circle-alert"
                                        iconSize: MeridianIcon.Small
                                        color: Theme.colors.attention
                                    }
                                    MeridianCount {
                                        visible: (fileRow.modelData.remaining ?? 0) > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: String(fileRow.modelData.remaining ?? 0)
                                        tone: MeridianCount.Attention
                                    }
                                }
                            }
                        }
                    }
                    // Resolves the ticked files with one whole side.
                    Column {
                        id: bulk
                        visible: selectAllRow.count > 0
                        width: parent.width
                        height: visible ? implicitHeight : 0
                        MeridianHairline { width: parent.width }
                        Column {
                            x: Theme.space.s3
                            width: parent.width - 2 * Theme.space.s3
                            topPadding: Theme.space.s3
                            bottomPadding: Theme.space.s3
                            spacing: Theme.space.s2
                            MeridianButton {
                                width: parent.width
                                text: L10n.tn("conflictBulkUseCurrent", { count: selectAllRow.count })
                                controlSize: MeridianButton.Small
                                enabled: !resolver.busy
                                onClicked: { Store.conflicts.forEach(resolver.checked, "current"); resolver.checked = [] }
                            }
                            MeridianButton {
                                width: parent.width
                                text: L10n.tn("conflictBulkUseIncoming", { count: selectAllRow.count })
                                controlSize: MeridianButton.Small
                                enabled: !resolver.busy
                                onClicked: { Store.conflicts.forEach(resolver.checked, "incoming"); resolver.checked = [] }
                            }
                        }
                    }
                }
            }
            MeridianResizeHandle {
                id: splitter
                visible: resolver.files.length > 0
                x: filesIsland.width
                width: Theme.space.s3
                height: parent.height
                semanticLabel: L10n.t("conflictResizeFiles")
                keyboardStep: GitLamaLayout.paneResizeStep
                activeFocusOnTab: false
                onDragged: delta => resolver.fileListWidth = Math.max(GitLamaLayout.conflictFileListMinWidth, filesIsland.width + delta)
                onReset: resolver.fileListWidth = GitLamaLayout.conflictFileListWidth
            }

            // The shown file: details, the whole-file banner, comparison and result.
            MeridianIsland {
                id: editorIsland
                visible: resolver.files.length > 0 && resolver.file !== null
                x: filesIsland.width + splitter.width
                width: parent.width - x
                height: parent.height
                Item {
                    anchors.fill: parent
                    ConflictFileDetails {
                        id: details
                        width: parent.width
                        height: implicitHeight
                        file: resolver.file
                    }
                    MeridianHairline { id: detailsRule; y: details.height; width: parent.width }
                    Item {
                        id: wholeFile
                        y: detailsRule.y + detailsRule.height
                        width: parent.width
                        height: wholeBanner.visible ? wholeBanner.height + 2 * Theme.space.s3 : 0
                        readonly property var f: resolver.file
                        readonly property bool chosen: f !== null && !!f.side
                        readonly property bool oneDeleted: f !== null && f.currentPresent !== f.incomingPresent
                        readonly property string deleted: f && f.currentPresent ? "incoming" : "current"
                        readonly property string kept: deleted === "current" ? "incoming" : "current"
                        MeridianBanner {
                            id: wholeBanner
                            visible: wholeFile.chosen || wholeFile.oneDeleted
                            x: Theme.space.s3
                            y: Theme.space.s3
                            width: parent.width - 2 * Theme.space.s3
                            tone: wholeFile.chosen ? (wholeFile.f.deletionChosen ? MeridianBanner.Warning : MeridianBanner.Info) : MeridianBanner.Attention
                            iconName: wholeFile.chosen && !wholeFile.f.deletionChosen ? "check" : "trash-2"
                            title: !wholeFile.f ? ""
                                : wholeFile.chosen ? (wholeFile.f.deletionChosen ? L10n.t("conflictDeletionChosenTitle")
                                    : L10n.tn("conflictWholeFileChosenTitle", { branch: resolver.sideLabel(wholeFile.f.side) }))
                                : L10n.t("conflictDeletionDecisionTitle")
                            message: !wholeFile.f ? ""
                                : wholeFile.chosen ? (wholeFile.f.deletionChosen ? L10n.tn("conflictDeletionChosenBody", { branch: resolver.sideLabel(wholeFile.f.side) })
                                    : L10n.t("conflictWholeFileChosenBody"))
                                : [L10n.t("conflictPresence" + (wholeFile.f.details.presence ?? "unknown").charAt(0).toUpperCase() + (wholeFile.f.details.presence ?? "unknown").slice(1)),
                                   L10n.t("conflictDeletionDecisionHint")].map(part => part.endsWith(".") ? part : part + ".").join(" ")
                            MeridianButton {
                                visible: wholeFile.chosen
                                text: L10n.t("conflictChooseDifferently")
                                variant: MeridianButton.Quiet
                                controlSize: MeridianButton.Small
                                enabled: !resolver.busy
                                onClicked: Store.conflicts.clearWholeSide()
                            }
                            MeridianButton {
                                visible: !wholeFile.chosen
                                text: L10n.t("conflictKeepDeletion")
                                iconName: "trash-2"
                                variant: MeridianButton.Secondary
                                controlSize: MeridianButton.Small
                                enabled: !resolver.busy
                                onClicked: Store.conflicts.chooseSide(wholeFile.deleted)
                            }
                            MeridianButton {
                                visible: !wholeFile.chosen
                                text: L10n.tn("conflictKeepFileFrom", { branch: resolver.sideLabel(wholeFile.kept) })
                                variant: MeridianButton.Secondary
                                controlSize: MeridianButton.Small
                                enabled: !resolver.busy
                                onClicked: Store.conflicts.chooseSide(wholeFile.kept)
                            }
                        }
                    }
                    // Comparison and result: side by side when wide, stacked otherwise.
                    Item {
                        id: editor
                        y: wholeFile.y + wholeFile.height
                        width: parent.width
                        height: parent.height - y
                        readonly property bool wide: width >= GitLamaLayout.conflictWideEditorMinWidth
                        readonly property bool textFile: resolver.file !== null && resolver.file.kind === "text"
                        ConflictComparison {
                            id: comparison
                            visible: editor.textFile
                            width: editor.wide ? (editor.width - Metrics.hairline) * 3 / 5 : editor.width
                            height: editor.wide ? editor.height : (editor.height - Metrics.hairline) * 3 / 5
                            file: resolver.file
                            conflictState: resolver.conflictState
                            onScrolled: sync.follow(true)
                        }
                        // A binary or huge file: one card per side.
                        Row {
                            visible: !editor.textFile && resolver.file !== null
                            width: comparison.width
                            height: comparison.height
                            padding: Theme.space.s5
                            spacing: Theme.space.s4
                            Repeater {
                                model: ["current", "incoming"]
                                delegate: Rectangle {
                                    id: card
                                    required property string modelData
                                    readonly property bool chosen: resolver.file !== null && resolver.file.side === modelData
                                    readonly property bool present: resolver.file !== null && (modelData === "current" ? resolver.file.currentPresent : resolver.file.incomingPresent)
                                    readonly property bool empty: resolver.file !== null && (modelData === "current" ? resolver.file.currentEmpty : resolver.file.incomingEmpty)
                                    width: (parent.width - 2 * Theme.space.s5 - Theme.space.s4) / 2
                                    height: cardColumn.implicitHeight + 2 * Theme.space.s5
                                    radius: Theme.radius.lg
                                    color: cardHover.hovered ? Theme.colors.paneHover : Theme.colors.paneAlt
                                    border.width: chosen ? 2 : 1
                                    border.color: chosen ? Theme.colors.accent : Theme.colors.line
                                    Accessible.role: Accessible.Button
                                    Accessible.name: (modelData === "current" ? L10n.t("conflictUseCurrentFile") : L10n.t("conflictUseIncomingFile"))
                                        + ", " + resolver.sideLabel(modelData)
                                    HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { enabled: !resolver.busy; onTapped: Store.conflicts.chooseSide(card.modelData) }
                                    Column {
                                        id: cardColumn
                                        x: Theme.space.s5
                                        y: Theme.space.s5
                                        width: parent.width - 2 * Theme.space.s5
                                        spacing: Theme.space.s2
                                        Item {
                                            width: parent.width
                                            height: chip.height
                                            RefChip {
                                                id: chip
                                                name: resolver.sideLabel(card.modelData)
                                                kind: card.modelData === "current" ? "local" : "remote"
                                            }
                                            MeridianIcon {
                                                visible: card.chosen
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: "check"
                                                iconSize: MeridianIcon.Small
                                                color: Theme.colors.accent
                                            }
                                        }
                                        Item { width: 1; height: Theme.space.s2 }
                                        MeridianText {
                                            width: parent.width
                                            wrapMode: Text.Wrap
                                            elide: Text.ElideNone
                                            text: !card.present ? L10n.t("conflictKeepDeletion") : card.empty ? L10n.t("conflictEmptySide")
                                                : L10n.t(card.modelData === "current" ? "conflictUseCurrentFile" : "conflictUseIncomingFile")
                                        }
                                        MeridianText {
                                            width: parent.width
                                            role: MeridianText.Caption
                                            color: Theme.colors.inkMuted
                                            text: L10n.t("conflictUnknownProvenance")
                                        }
                                    }
                                }
                            }
                        }
                        MeridianHairline {
                            vertical: editor.wide
                            x: editor.wide ? comparison.width : 0
                            y: editor.wide ? 0 : comparison.height
                            width: editor.wide ? Metrics.hairline : editor.width
                            height: editor.wide ? editor.height : Metrics.hairline
                        }
                        ConflictResultPane {
                            id: resultPane
                            x: editor.wide ? comparison.width + Metrics.hairline : 0
                            y: editor.wide ? 0 : comparison.height + Metrics.hairline
                            width: editor.width - x
                            height: editor.height - y
                            file: resolver.file
                            conflictState: resolver.conflictState
                            onScrolled: sync.follow(false)
                        }
                    }
                }
            }
        }
        MeridianHairline { width: parent.width }

        // Where the resolver stands among the files.
        Item {
            id: footer
            width: parent.width
            height: Math.max(footerRow.implicitHeight, progressText.implicitHeight) + 2 * Theme.space.s4
            MeridianText {
                id: progressText
                x: Theme.space.s5
                anchors.verticalCenter: parent.verticalCenter
                width: footerRow.x - x - Theme.space.s3
                text: resolver.files.length === 0 ? L10n.t(resolver.standalone ? "conflictStandaloneResolved" : "conflictAllResolved")
                    : L10n.tn("conflictFileProgress", { current: resolver.selected + 1, total: resolver.files.length })
            }
            Row {
                id: footerRow
                x: parent.width - width - Theme.space.s5
                anchors.verticalCenter: parent.verticalCenter
                MeridianIconButton {
                    iconName: "back"
                    text: L10n.t("conflictPreviousFile")
                    controlSize: MeridianButton.Small
                    enabled: !resolver.busy && resolver.selected > 0
                    onClicked: resolver.selectFile(resolver.selected - 1)
                }
                MeridianIconButton {
                    iconName: "chevron-right"
                    text: L10n.t("conflictNextFile")
                    controlSize: MeridianButton.Small
                    enabled: !resolver.busy && resolver.selected < resolver.files.length - 1
                    onClicked: resolver.selectFile(resolver.selected + 1)
                }
                MeridianIconButton {
                    id: undoButton
                    visible: (resolver.conflictState.resolved ?? []).length > 0
                    iconName: "undo"
                    text: L10n.t("conflictUndoResolution")
                    controlSize: MeridianButton.Small
                    enabled: !resolver.busy
                    onClicked: {
                        undoMenu.items = (resolver.conflictState.resolved ?? []).map(file => ({ title: file.path, value: file.key }))
                        undoMenu.show(undoButton, 0, undoButton.height)
                    }
                    CommandMenu { id: undoMenu; onSelected: value => Store.conflicts.undo(value) }
                }
            }
        }
    }

    // The panes follow each other: the region a pane shows sits level with
    // the same region in the other (piecewise linear between regions).
    QtObject {
        id: sync
        property bool following: false
        function anchors() {
            const f = resolver.file
            if (!f || f.side || !(f.blockRows ?? []).length)
                return null
            const extents = comparison.regionExtents()
            const marks = f.marks ?? []
            // Each region's lines in the result: one mark, or two for "both".
            const pairs = [[0, 0]]
            let mark = 0
            for (let region = 0; region < extents.length && mark < marks.length; ++region) {
                const blocks = f.blocks ?? []
                const both = blocks[region] && blocks[region].choice === "both"
                const first = marks[mark]
                const last = both && mark + 1 < marks.length ? marks[mark + 1] : first
                mark += both ? 2 : 1
                pairs.push([extents[region].top, resultPane.lineTop(first.first)])
                pairs.push([extents[region].bottom, resultPane.lineTop(last.last + 1)])
            }
            return pairs
        }
        function map(value, pairs, fromIndex) {
            const toIndex = 1 - fromIndex
            for (let i = 1; i < pairs.length; ++i) {
                if (value <= pairs[i][fromIndex]) {
                    const a = pairs[i - 1], b = pairs[i]
                    const span = b[fromIndex] - a[fromIndex]
                    return span <= 0 ? b[toIndex] : a[toIndex] + (value - a[fromIndex]) / span * (b[toIndex] - a[toIndex])
                }
            }
            const last = pairs[pairs.length - 1]
            return last[toIndex] + (value - last[fromIndex])
        }
        function follow(fromComparison) {
            if (following || !editor.textFile)
                return
            const pairs = anchors()
            const list = comparison.view
            const flick = resultPane.flick
            following = true
            if (pairs === null) {
                if (fromComparison)
                    flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), list.contentY)
                else
                    list.contentY = Math.min(Math.max(0, list.contentHeight - list.height), flick.contentY)
            } else if (fromComparison) {
                flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), map(list.contentY, pairs, 0)))
            } else {
                list.contentY = Math.max(0, Math.min(Math.max(0, list.contentHeight - list.height), map(flick.contentY, pairs, 1)))
            }
            following = false
            // The focused conflict follows the scroll offset.
            const extents = comparison.regionExtents()
            const lead = GitLamaLayout.conflictLeadRows * GitLamaLayout.conflictComparisonRowHeight
            const line = list.contentY + lead
            let region = extents.findIndex(extent => extent.bottom > line + 1)
            if (region < 0)
                region = extents.length - 1
            if (region >= 0 && resolver.file && region !== resolver.file.focusedRegion)
                Store.conflicts.focusRegion(region)
        }
    }
}
