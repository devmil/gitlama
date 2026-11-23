pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The Changes pane's diff (the Dart WorkingTreeDetailPane): the selected
// file's working diff on the focused side. Lines select with a click
// (Shift extends, Ctrl/Cmd adds) and stage, unstage or discard from the
// toolbar or their context menu.
Rectangle {
    id: pane

    readonly property var paneState: Store.changes ? (Store.changes.state ?? ({})) : ({})
    readonly property var detail: paneState.detail ?? ({})
    readonly property bool staged: detail.side === "staged"
    readonly property var selectedRows: detail.selectedRows ?? []
    readonly property bool canDiscardLines: !staged && detail.untracked !== true
    // Staging is refused only for a repository on another computer that
    // does not allow it (the Dart remote stage reason).
    readonly property string stageDisabledReason: {
        const reason = Commands.reason("stageSelection")
        return reason.startsWith("remote") ? Commands.reasonText(reason) : ""
    }
    readonly property bool busy: paneState.busy === true

    color: Theme.colors.pane
    Component.onCompleted: Store.workingDiffPane = pane
    Component.onDestruction: if (Store.workingDiffPane === pane) Store.workingDiffPane = null

    readonly property bool diffFocused: diff.activeFocus || workingFind.searchField.activeFocus
    /// Focuses the diff's find field (Find); false without a diff.
    function focusFind() {
        if (!content.visible)
            return false
        workingFind.searchField.forceActiveFocus()
        workingFind.searchField.selectAll()
        return true
    }

    // Development screenshots: `diffRow:<index>` scrolls the diff to a row;
    // `stageHunk:<n>` stages (or unstages) the n-th hunk.
    Connections {
        target: Store
        function onScreenshotStepRequested(name, argument) {
            if (name === "diffRow") {
                diff.positionAt(Number(argument))
            } else if (name === "diffSelect" && Store.workingDiff) {
                // diffSelect:<first>-<last> selects those rows' lines.
                const range = argument.split("-").map(Number)
                Store.changes.setSelectedRows(Store.workingDiff.lineIds(range[0], range[1]))
            } else if (name === "diffCopy") {
                diff.runCopyMenuItem(argument === "patch" ? "copyPatch" : "copyLines")
            } else if (name === "stageHunk" && Store.workingDiff) {
                let at = -1
                for (let n = 0; n <= Number(argument); ++n)
                    at = Store.workingDiff.hunkFrom(at, true)
                const header = at < 0 ? null : Store.workingDiff.hunkHeaderFor(at)
                if (header)
                    Store.changes.stageHunk(header.stableId)
            }
        }
    }

    // The pane's header: the file's status.
    Item {
        id: header
        width: parent.width
        height: Theme.size.islandHeader
        MeridianText {
            x: Theme.space.s5
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.BodyStrong
            text: L10n.t("workspaceDetail")
        }
        StatusGlyph {
            visible: (pane.detail.status ?? "").length > 0
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s5
            anchors.verticalCenter: parent.verticalCenter
            status: pane.detail.status ?? ""
        }
        MeridianHairline { anchors.bottom: parent.bottom; width: parent.width }
    }
    MeridianProgressBar {
        id: progress
        visible: pane.detail.loading === true
        anchors.top: header.bottom
        width: parent.width
    }

    MeridianEmptyState {
        visible: !pane.detail.identity
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        compact: true
        iconName: "inspect"
        title: L10n.t("workspaceNoSelection")
    }
    MeridianEmptyState {
        visible: !!pane.detail.identity && !!pane.detail.failure
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        compact: true
        iconName: "circle-alert"
        title: L10n.t("workingDiffFailed")
    }
    MeridianEmptyState {
        visible: !!pane.detail.identity && !pane.detail.failure && pane.detail.hasDiff !== true && pane.detail.waiting === true
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        compact: true
        iconName: "hourglass"
        title: L10n.t("workingDiffWaitingForGit")
        message: L10n.t("workingDiffWaitingForGitDetail")
    }

    Item {
        id: content
        visible: !!pane.detail.identity && !pane.detail.failure && pane.detail.hasDiff === true
        anchors.top: progress.visible ? progress.bottom : header.bottom
        anchors.bottom: parent.bottom
        width: parent.width

        // The file.
        Item {
            id: fileLine
            width: parent.width
            height: Theme.size.row + 2 * Theme.space.s3
            MeridianIcon {
                id: fileIcon
                x: Theme.space.s4
                anchors.verticalCenter: parent.verticalCenter
                name: "file"
            }
            MeridianText {
                x: fileIcon.x + fileIcon.width + Theme.space.s3
                width: parent.width - x - Theme.space.s4
                anchors.verticalCenter: parent.verticalCenter
                text: pane.detail.identity ?? ""
                elide: Text.ElideMiddle
            }
            MeridianHairline { anchors.bottom: parent.bottom; width: parent.width }
        }
        // The diff's toolbar: line actions and layout.
        Item {
            id: toolbar
            objectName: "working-diff-toolbar-surface"
            anchors.top: fileLine.bottom
            width: parent.width
            height: Theme.size.control + 2 * Theme.space.s2
            Row {
                anchors.right: parent.right
                anchors.rightMargin: Theme.space.s4
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.s1
                MeridianIconButton {
                    text: L10n.t("diffPreviousHunk")
                    iconName: "arrow-up-to-line"
                    controlSize: MeridianButton.Small
                    onClicked: diff.nextHunk(false)
                }
                MeridianIconButton {
                    text: L10n.t("diffNextHunk")
                    iconName: "arrow-down-to-line"
                    controlSize: MeridianButton.Small
                    onClicked: diff.nextHunk(true)
                }
                DiffFind {
                    id: workingFind
                    anchors.verticalCenter: parent.verticalCenter
                    searcher: Store.changes
                    view: diff
                    diffKey: (pane.detail.identity ?? "") + ":" + (pane.detail.side ?? "")
                }
                DiffViewingActions {
                    anchors.verticalCenter: parent.verticalCenter
                    encoding: diff.encoding
                    onEncodingChosen: value => diff.encoding = value
                    setOptions: (context, whitespace, layout) =>
                        Store.changes.setDiffOptions(context, whitespace, layout, pane.detail.forceText === true)
                }
            }
            MeridianHairline { anchors.bottom: parent.bottom; width: parent.width }
        }
        MeridianEmptyState {
            visible: (pane.detail.rows ?? 0) === 0
            anchors.top: toolbar.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            compact: true
            iconName: "file-diff"
            title: L10n.t("workingDiffEmpty")
        }
        // An image change shows its images instead of the diff rows.
        ImageDiffView {
            id: workingImage
            visible: diff.visible && row !== null
            anchors.fill: diff
            source: Store.changes
            load: row => Store.changes.loadImageDiff(row.key)
            function refresh() {
                const next = Store.workingDiff ? Store.workingDiff.imageRow() : null
                if (JSON.stringify(next) !== JSON.stringify(row))
                    row = next
            }
            Connections {
                target: Store.workingDiff
                function onCountChanged() { workingImage.refresh() }
                function onDataChanged() { workingImage.refresh() }
                function onModelReset() { workingImage.refresh() }
            }
        }
        DiffView {
            id: diff
            opacity: workingImage.row === null ? 1 : 0
            enabled: workingImage.row === null
            visible: (pane.detail.rows ?? 0) > 0
            anchors.top: toolbar.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            model: Store.workingDiff
            hunkSource: Store.changes
            layout: pane.detail.options ? pane.detail.options.layout : "unified"
            wrap: Store.appearance.diffWrap === true
            showIndicators: Store.appearance.diffIndicators !== false
            showMinimap: Store.appearance.diffMinimap !== false
            canShowMoreContext: !!pane.detail.options && pane.detail.options.contextLines < 10000
            onShowMoreContext: Store.changes.showMoreContext()
            hunkActions: pane.detail.forceText !== true
            canShowAsText: pane.detail.forceText !== true
            onShowAsText: {
                const preferences = Store.appearance
                Store.changes.setDiffOptions(preferences.diffContextLines ?? 3, preferences.diffWhitespace ?? "preserve",
                                             preferences.diffLayout ?? "unified", true)
            }
            hunkStagedSide: pane.staged
            canDiscardHunks: pane.canDiscardLines
            hunkActionsEnabled: !pane.busy
            hunkStageDisabledReason: pane.stageDisabledReason
            onStageHunk: stableId => Store.changes.stageHunk(stableId)
            onDiscardHunk: stableId => Store.changes.discardHunk(stableId)
            lineSelection: true
            selectedRows: pane.selectedRows
            onRowsSelected: rows => Store.changes.setSelectedRows(rows)
            onLineMenuRequested: (x, y) => {
                // The destructive entry goes last (the Dart withDestructiveLast).
                lineMenu.items = [
                    { title: pane.staged ? L10n.t("diffSelectionUnstage") : L10n.t("diffSelectionStage"),
                      icon: pane.staged ? "minus" : "plus", enabled: !pane.busy, value: "stage" },
                ].concat(diff.copyMenuItems()).concat(pane.canDiscardLines ? [{ separator: true },
                    { title: L10n.t("diffSelectionDiscard"), icon: "trash", danger: true, enabled: !pane.busy, value: "discard" }] : [])
                lineMenu.show(diff, x, y)
            }
            patchSource: Store.changes
            // Stage or unstage, and discard, the selected lines: floating
            // over the first of them (the Dart _selectionActions).
            selectionActions: Component {
                Row {
                    spacing: Theme.space.s2
                    MeridianButton {
                        objectName: "diff-selection-stage"
                        text: pane.staged ? L10n.t("diffSelectionUnstage") : L10n.t("diffSelectionStage")
                        controlSize: MeridianButton.Small
                        enabled: !pane.busy && pane.stageDisabledReason.length === 0
                        disabledReason: pane.stageDisabledReason
                        onClicked: Store.changes.stageRows()
                    }
                    MeridianButton {
                        objectName: "diff-selection-discard"
                        visible: pane.canDiscardLines
                        text: L10n.t("diffSelectionDiscard")
                        controlSize: MeridianButton.Small
                        enabled: !pane.busy
                        onClicked: Store.changes.discardRows()
                    }
                }
            }
        }
        CommandMenu {
            id: lineMenu
            onSelected: value => {
                if (diff.runCopyMenuItem(value))
                    return
                if (value === "stage")
                    Store.changes.stageRows()
                else if (value === "discard")
                    Store.changes.discardRows()
            }
        }
    }
}
