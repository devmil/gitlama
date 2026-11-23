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
    readonly property bool busy: paneState.busy === true

    color: Theme.colors.pane

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
                x: Theme.space.s4
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.s2
                MeridianButton {
                    visible: pane.selectedRows.length > 0
                    text: pane.staged ? L10n.t("diffSelectionUnstage") : L10n.t("diffSelectionStage")
                    iconName: pane.staged ? "minus" : "plus"
                    controlSize: MeridianButton.Small
                    variant: MeridianButton.Secondary
                    enabled: !pane.busy
                    onClicked: Store.changes.stageRows()
                }
                MeridianButton {
                    visible: pane.selectedRows.length > 0 && pane.canDiscardLines
                    text: L10n.t("diffSelectionDiscard")
                    iconName: "trash"
                    controlSize: MeridianButton.Small
                    variant: MeridianButton.Danger
                    enabled: !pane.busy
                    onClicked: Store.changes.discardRows()
                }
            }
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
        DiffView {
            id: diff
            visible: (pane.detail.rows ?? 0) > 0
            anchors.top: toolbar.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            model: Store.workingDiff
            layout: pane.detail.options ? pane.detail.options.layout : "unified"
            wrap: Store.appearance.diffWrap === true
            showIndicators: Store.appearance.diffIndicators !== false
            showMinimap: Store.appearance.diffMinimap !== false
            canShowMoreContext: !!pane.detail.options && pane.detail.options.contextLines < 10000
            onShowMoreContext: Store.changes.showMoreContext()
            lineSelection: true
            selectedRows: pane.selectedRows
            onRowsSelected: rows => Store.changes.setSelectedRows(rows)
            onLineMenuRequested: (x, y) => {
                lineMenu.items = [
                    { title: pane.staged ? L10n.t("diffSelectionUnstage") : L10n.t("diffSelectionStage"),
                      icon: pane.staged ? "minus" : "plus", enabled: !pane.busy, value: "stage" },
                ].concat(pane.canDiscardLines ? [{ separator: true },
                    { title: L10n.t("diffSelectionDiscard"), icon: "trash", danger: true, enabled: !pane.busy, value: "discard" }] : [])
                lineMenu.show(diff, x, y)
            }
        }
        CommandMenu {
            id: lineMenu
            onSelected: value => value === "stage" ? Store.changes.stageRows() : Store.changes.discardRows()
        }
    }
}
