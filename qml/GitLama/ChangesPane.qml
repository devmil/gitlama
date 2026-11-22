pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The Changes pane (the Dart ChangesPane): beside the diff, an island with
// the staging banners, the file filter, the unstaged and staged lists
// (split by a draggable ratio) and the commit editor.
Item {
    id: pane

    readonly property var paneState: Store.changes ? (Store.changes.state ?? ({})) : ({})
    readonly property var appearance: Store.appearance
    /// The unstaged list's share of the lists' height.
    property real splitRatio: Math.max(GitLamaLayout.changesSplitRatioMin,
        Math.min(GitLamaLayout.changesSplitRatioMax, (appearance.changesSplitRatio ?? 500) / 1000))
    property real draggedRatio: -1
    readonly property real ratio: draggedRatio >= 0 ? draggedRatio : splitRatio
    /// The width of the files island (appearance.diffWidth in Flutter).
    property real draggedWidth: -1
    readonly property real maximumFilesWidth: Math.max(GitLamaLayout.codePaneMinWidth,
        width - GitLamaLayout.changesDiffMinWidth - Theme.space.s3)
    readonly property real filesWidth: Math.max(Math.min(GitLamaLayout.changesFilePaneMinWidth, maximumFilesWidth),
        Math.min(maximumFilesWidth, draggedWidth >= 0 ? draggedWidth : (appearance.diffWidth ?? 420)))

    signal command(string id, var options)

    MeridianIsland {
        id: files
        width: pane.filesWidth
        height: parent.height

        Item {
            anchors.fill: parent

            Column {
                id: banners
                width: parent.width
                RepositoryConditions {
                    width: parent.width
                    onCommand: id => pane.command(id, ({}))
                    onSkip: Store.conflicts.sequence("skip")
                }
                MeridianBanner {
                    visible: (pane.paneState.stopped ?? 0) > 0
                    width: parent.width
                    tone: MeridianBanner.Warning
                    message: L10n.tn("stagingQueueStopped", { count: pane.paneState.stopped ?? 0 })
                    dismissible: true
                    dismissLabel: L10n.t("close")
                    onDismissed: Store.changes.dismissStopped()
                }
                MeridianBanner {
                    objectName: "staging-progress"
                    visible: !!pane.paneState.phase
                    width: parent.width
                    tone: MeridianBanner.Info
                    message: ({ waiting: L10n.t("stagingWaiting"), preparing: L10n.t("stagingPreparing"),
                                updating: L10n.t("stagingUpdating"), refreshing: L10n.t("stagingRefreshing") })[pane.paneState.phase ?? "waiting"]
                        + " " + L10n.tn("stagingQueueCount", { count: pane.paneState.pending ?? 0 })
                }
            }

            // The file filter.
            Item {
                id: filterBar
                anchors.top: banners.bottom
                width: parent.width
                height: Theme.size.islandHeader
                MeridianTextField {
                    objectName: "changes-filter"
                    x: Theme.space.s4
                    width: parent.width - 2 * Theme.space.s4
                    anchors.verticalCenter: parent.verticalCenter
                    variant: MeridianTextField.Search
                    controlSize: MeridianButton.Small
                    placeholderText: L10n.t("changesFilterPlaceholder")
                    clearLabel: L10n.t("changesFilterClear")
                    Accessible.name: L10n.t("changesFilterLabel")
                    trailingText: text.trim().length > 0
                        ? L10n.tn("changesFilterCount", {
                              shown: (pane.paneState.unstagedShown ?? 0) + (pane.paneState.stagedShown ?? 0),
                              total: (pane.paneState.unstagedTotal ?? 0) + (pane.paneState.stagedTotal ?? 0) })
                        : ""
                    onTextChanged: Store.changes.setFilter(text)
                    Keys.onEscapePressed: text = ""
                }
                MeridianHairline { anchors.bottom: parent.bottom; width: parent.width }
            }

            Item {
                id: lists
                anchors.top: filterBar.bottom
                anchors.bottom: editorSplitter.top
                width: parent.width

                ChangesSection {
                    id: unstagedSection
                    width: parent.width
                    height: Math.round((lists.height - Theme.space.s3) * pane.ratio)
                    side: "unstaged"
                    title: L10n.t("changesUnstaged")
                    model: Store.unstagedRows
                    paneState: pane.paneState
                }
                MeridianResizeHandle {
                    objectName: "changes-pane-splitter"
                    y: unstagedSection.height
                    width: parent.width
                    orientation: Qt.Vertical
                    semanticLabel: L10n.t("changesResizePanes")
                    keyboardStep: GitLamaLayout.paneResizeStep
                    activeFocusOnTab: false
                    onDragStarted: pane.draggedRatio = pane.ratio
                    onDragged: delta => {
                        const base = pane.draggedRatio >= 0 ? pane.draggedRatio : pane.ratio
                        pane.draggedRatio = Math.max(GitLamaLayout.changesSplitRatioMin,
                            Math.min(GitLamaLayout.changesSplitRatioMax, base + delta / Math.max(1, lists.height - Theme.space.s3)))
                        if (!dragging) {
                            Store.app.updateAppearance({ changesSplitRatio: Math.round(pane.draggedRatio * 1000) })
                            pane.draggedRatio = -1
                        }
                    }
                    onDragFinished: {
                        if (pane.draggedRatio >= 0)
                            Store.app.updateAppearance({ changesSplitRatio: Math.round(pane.draggedRatio * 1000) })
                        pane.draggedRatio = -1
                    }
                }
                ChangesSection {
                    id: stagedSection
                    y: unstagedSection.height + Theme.space.s3
                    width: parent.width
                    height: lists.height - y
                    side: "staged"
                    title: L10n.t("changesStaged")
                    model: Store.stagedRows
                    paneState: pane.paneState
                }
            }

            MeridianResizeHandle {
                id: editorSplitter
                objectName: "changes-commit-splitter"
                anchors.bottom: editor.top
                width: parent.width
                orientation: Qt.Vertical
                semanticLabel: L10n.t("changesResizeCommit")
                activeFocusOnTab: false
                onDragged: delta => editor.chosenHeight = Math.max(140, Math.min(parent.height - 120 - Theme.space.s3, editor.height - delta))
                onReset: editor.chosenHeight = -1
            }
            CommitEditor {
                id: editor
                objectName: "changes-commit-editor"
                anchors.bottom: parent.bottom
                width: parent.width
                /// The height the splitter chose; -1 fits the content.
                property real chosenHeight: -1
                height: Math.max(140, Math.min(parent.height - 120 - Theme.space.s3,
                                               chosenHeight >= 0 ? chosenHeight : implicitHeight))
                onCommand: (id, options) => pane.command(id, options)
            }
        }
    }

    MeridianResizeHandle {
        id: filesSplitter
        x: files.width
        height: parent.height
        semanticLabel: L10n.t("workspaceResizeDetail")
        keyboardStep: GitLamaLayout.paneResizeStep
        activeFocusOnTab: false
        onDragStarted: pane.draggedWidth = pane.filesWidth
        onDragged: delta => {
            pane.draggedWidth = Math.max(GitLamaLayout.changesFilePaneMinWidth,
                Math.min(pane.maximumFilesWidth, (pane.draggedWidth >= 0 ? pane.draggedWidth : pane.filesWidth) + delta))
            if (!dragging) {
                Store.app.updateAppearance({ diffWidth: Math.round(pane.draggedWidth) })
                pane.draggedWidth = -1
            }
        }
        onDragFinished: {
            if (pane.draggedWidth >= 0)
                Store.app.updateAppearance({ diffWidth: Math.round(pane.draggedWidth) })
            pane.draggedWidth = -1
        }
    }

    MeridianIsland {
        x: filesSplitter.x + filesSplitter.width
        width: pane.width - x
        height: parent.height
        WorkingDiffPane {
            anchors.fill: parent
        }
    }
}
