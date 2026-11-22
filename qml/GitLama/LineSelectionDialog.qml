pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// "Select changed lines" (the Dart WorkingDiffSelectionDialog): the file's
// working diff with a checkbox on every hunk and change line; the picked
// lines are staged (or unstaged), discarded or made into a patch. Its state
// is `Store.lineSelection`, its rows `Store.lineRows`.
MeridianDialog {
    id: dialog

    readonly property var selectionState: Store.lineSelection ? (Store.lineSelection.state ?? ({})) : ({})
    readonly property bool staged: selectionState.side === "staged"
    readonly property bool ready: selectionState.hasPage === true && selectionState.failed !== true
    readonly property bool picked: ready && selectionState.empty === false

    /// Opens the dialog for the Changes file `key` on `side`.
    function show(side, key) {
        Store.lineSelection.begin(side, key)
        open()
    }

    widthClass: MeridianDialog.Workflow
    title: L10n.t("inspectChanges")
    description: L10n.t("inspectChangesHelp")
    submitDisabled: !picked
    onSubmitted: { Store.lineSelection.stage(); close() }
    onClosed: Store.lineSelection.end()

    // The outline is drawn over the rows, whose fills reach the edges.
    Item {
        width: parent ? parent.width : 0
        height: GitLamaLayout.previewDialogBodyHeight

        Rectangle {
            id: well
            anchors.fill: parent
            radius: Theme.radius.lg
            color: Theme.colors.pane
            clip: true

            Rectangle {
                id: countBar
                width: parent.width
                height: countRow.implicitHeight + 2 * Theme.space.s2
                color: Theme.colors.paneAlt
                Item {
                    id: countRow
                    x: Theme.space.s5
                    y: Theme.space.s2
                    width: parent.width - x - Theme.space.s3
                    implicitHeight: Math.max(countText.implicitHeight, allButton.implicitHeight)
                    MeridianText {
                        id: countText
                        objectName: "line-selection-count"
                        anchors.verticalCenter: parent.verticalCenter
                        role: MeridianText.Caption
                        color: Theme.colors.inkMuted
                        text: dialog.selectionState.more === true
                            ? L10n.tn("lineSelectionCountAtLeast", { count: dialog.selectionState.count ?? 0 })
                            : L10n.tn("lineSelectionCount", { count: dialog.selectionState.count ?? 0 })
                    }
                    MeridianButton {
                        id: allButton
                        objectName: "line-selection-all"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        variant: MeridianButton.Quiet
                        controlSize: MeridianButton.Small
                        text: dialog.selectionState.allChecked === true ? L10n.t("stashSelectNone") : L10n.t("stashSelectAll")
                        enabled: dialog.ready
                        onClicked: Store.lineSelection.toggleAll()
                    }
                }
            }
            MeridianHairline { y: countBar.height; width: parent.width; color: Theme.colors.line }

            MeridianEmptyState {
                visible: dialog.selectionState.failed === true || (dialog.selectionState.hasPage !== true && dialog.selectionState.loading === true)
                anchors.fill: list
                compact: true
                iconName: dialog.selectionState.failed === true ? "circle-alert" : ""
                progress: dialog.selectionState.failed !== true
                title: dialog.selectionState.failed === true ? L10n.t("workingDiffFailed") : L10n.t("loading")
            }

            ListView {
                id: list
                objectName: "line-selection-list"
                visible: dialog.ready
                y: countBar.height + Metrics.hairline
                width: parent.width
                height: parent.height - y
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Store.lineRows
                MeridianWheelScroll { flickable: list }
                C.ScrollBar.vertical: MeridianScrollBar {}
                footer: Item {
                    visible: dialog.selectionState.hasMore === true
                    width: list.width
                    height: visible ? moreButton.implicitHeight + 2 * Theme.space.s3 : 0
                    MeridianButton {
                        id: moreButton
                        anchors.centerIn: parent
                        text: L10n.t("stagingLoadMore")
                        variant: MeridianButton.Quiet
                        controlSize: MeridianButton.Small
                        enabled: dialog.selectionState.loading !== true
                        onClicked: Store.lineSelection.loadMore()
                    }
                }
                delegate: LineSelectionRow {
                    width: list.width
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.lg
            color: "transparent"
            border.color: Theme.colors.line
        }
    }

    actions: [
        MeridianButton {
            text: L10n.t("cancel")
            variant: MeridianButton.Quiet
            onClicked: dialog.reject()
        },
        MeridianButton {
            visible: dialog.selectionState.canDiscard === true
            text: L10n.t("discardLines")
            variant: MeridianButton.DangerQuiet
            enabled: dialog.picked
            onClicked: { Store.lineSelection.discard(); dialog.close() }
        },
        MeridianButton {
            text: L10n.t("patchCreate")
            enabled: dialog.picked
            onClicked: {
                const source = Store.lineSelection.patchSource()
                dialog.close()
                if (source)
                    Store.actions.showPatchDialog(source, "create")
            }
        },
        MeridianButton {
            text: dialog.staged ? L10n.t("unstageLines") : L10n.t("stageLines")
            variant: MeridianButton.Primary
            enabled: dialog.picked
            onClicked: { Store.lineSelection.stage(); dialog.close() }
        }
    ]
}
