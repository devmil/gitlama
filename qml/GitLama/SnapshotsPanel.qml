pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// Named snapshots of the working state (the Dart NamedSnapshotsPanel): a
// form that captures one, then the saved snapshots with their counts and a
// menu to inspect, restore, branch from or delete each. The workflow and
// its state live in Rust (Store.workflows.snapshots).
MeridianPanel {
    id: panel

    property real availableHeight: GitLamaLayout.snapshotsBodyHeight
    readonly property var panelState: Store.workflows ? (Store.workflows.snapshots ?? ({})) : ({})
    readonly property var entries: panelState.entries ?? []
    readonly property bool busy: panelState.busy === true
    property bool includeUntracked: true
    property bool keepIndex: false
    property int seenClose: -1

    title: L10n.t("namedSnapshotsTitle")
    closeLabel: L10n.t("close")
    width: GitLamaLayout.snapshotsPanelWidth
    leftPadding: 0
    rightPadding: 0
    bottomPadding: 0

    function act(action, entry) { Store.workflows.snapshot(action, { id: entry ? entry.id : "" }) }
    function create() {
        if (busy || nameField.text.trim().length === 0)
            return
        Store.workflows.snapshot("create", { name: nameField.text, includeUntracked: includeUntracked, keepIndex: keepIndex })
        nameField.text = ""
    }

    Component.onCompleted: { seenClose = panelState.closeSequence ?? 0; Store.workflows.snapshot("load", ({})) }
    // A restore that met conflicts closes the panel; Changes shows them.
    onPanelStateChanged: {
        if (seenClose >= 0 && (panelState.closeSequence ?? 0) !== seenClose) {
            seenClose = panelState.closeSequence ?? 0
            panel.closeRequested()
        }
    }

    Column {
        width: panel.bodyWidth
        height: Math.min(GitLamaLayout.snapshotsBodyHeight, panel.availableHeight - panel.headerHeight)

        Item {
            width: parent.width
            height: form.height + 2 * Theme.space.s5
            Rectangle {
                id: form
                x: Theme.space.s5
                y: Theme.space.s5
                width: parent.width - 2 * Theme.space.s5
                height: formColumn.implicitHeight + 2 * Theme.space.s5
                radius: Theme.radius.lg
                color: Theme.colors.paneAlt
                Column {
                    id: formColumn
                    x: Theme.space.s5
                    y: Theme.space.s5
                    width: parent.width - 2 * Theme.space.s5
                    spacing: Theme.space.s5
                    Column {
                        width: parent.width
                        spacing: Theme.space.s2
                        MeridianText { role: MeridianText.Label; text: L10n.t("namedSnapshotName") }
                        MeridianTextField {
                            id: nameField
                            width: parent.width
                            maximumLength: 128
                            enabled: !panel.busy
                            Accessible.name: L10n.t("namedSnapshotName")
                            onAccepted: panel.create()
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: Theme.space.s7
                        MeridianCheckbox {
                            text: L10n.t("stashIncludeUntracked")
                            checked: panel.includeUntracked
                            enabled: !panel.busy
                            onToggled: panel.includeUntracked = checked
                        }
                        MeridianCheckbox {
                            text: L10n.t("stashKeepIndex")
                            checked: panel.keepIndex
                            enabled: !panel.busy
                            onToggled: panel.keepIndex = checked
                        }
                    }
                    Item {
                        width: parent.width
                        height: createButton.implicitHeight
                        MeridianButton {
                            id: createButton
                            anchors.right: parent.right
                            text: L10n.t("namedSnapshotCreate")
                            variant: MeridianButton.Primary
                            controlSize: MeridianButton.Small
                            enabled: !panel.busy && nameField.text.trim().length > 0
                            onClicked: panel.create()
                        }
                    }
                }
            }
        }
        Item {
            visible: !!panel.panelState.failure
            width: parent.width
            height: visible ? failureBanner.implicitHeight + 2 * Theme.space.s5 : 0
            MeridianBanner {
                id: failureBanner
                x: Theme.space.s5
                y: Theme.space.s5
                width: parent.width - 2 * Theme.space.s5
                tone: MeridianBanner.Error
                message: panel.panelState.failure ? L10n.t(panel.panelState.failure) : ""
            }
        }
        MeridianProgressBar {
            visible: panel.busy
            width: parent.width
        }

        Item {
            width: parent.width
            height: parent.height - y
            MeridianEmptyState {
                visible: panel.entries.length === 0
                anchors.fill: parent
                compact: true
                progress: panel.panelState.loading === true
                iconName: panel.panelState.loading === true ? "" : "stash"
                title: panel.panelState.loading === true ? L10n.t("loading") : L10n.t("namedSnapshotsEmpty")
                message: panel.panelState.loading === true ? "" : L10n.t("namedSnapshotsEmptyHelp")
            }
            ListView {
                id: list
                visible: panel.entries.length > 0
                anchors.fill: parent
                leftMargin: Theme.space.s2
                rightMargin: Theme.space.s2
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: panel.entries
                MeridianWheelScroll { flickable: list }
                C.ScrollBar.vertical: MeridianScrollBar {}
                footer: Item {
                    width: list.width - list.leftMargin - list.rightMargin
                    height: panel.panelState.nextOffset !== null && panel.panelState.nextOffset !== undefined ? moreButton.implicitHeight + Theme.space.s4 : 0
                    MeridianButton {
                        id: moreButton
                        visible: parent.height > 0
                        anchors.centerIn: parent
                        text: L10n.t("loadMore")
                        variant: MeridianButton.Quiet
                        controlSize: MeridianButton.Small
                        enabled: panel.panelState.loading !== true
                        onClicked: Store.workflows.snapshot("more", ({}))
                    }
                }
                delegate: MeridianListRow {
                    id: row
                    required property var modelData
                    width: list.width - list.leftMargin - list.rightMargin
                    selected: panel.panelState.selected === modelData.id
                    text: modelData.name
                    subtitle: Labels.historyDate(modelData.created / 1000, "local")
                    iconName: modelData.ready ? "stash" : "triangle-alert"
                    onClicked: panel.act("select", row.modelData)
                    titleTrailing: Component {
                        RefChip { visible: !!row.modelData.baseRef; name: row.modelData.baseRef ?? ""; kind: "local" }
                    }
                    trailing: Component {
                        Row {
                            spacing: Theme.space.s2
                            Repeater {
                                model: [[row.modelData.staged, "changesStaged"], [row.modelData.unstaged, "changesUnstaged"],
                                        [row.modelData.untracked, "namedSnapshotFactNewFiles"]]
                                delegate: MeridianCount {
                                    id: countChip
                                    required property var modelData
                                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                    label: String(modelData[0])
                                    MeridianTooltip { shown: countHover.hovered; text: L10n.t(countChip.modelData[1]) }
                                    HoverHandler { id: countHover }
                                }
                            }
                            Item { width: Theme.space.s1; height: 1 }
                            MeridianIconButton {
                                id: menuButton
                                anchors.verticalCenter: parent.verticalCenter
                                text: L10n.t("historyFileActions")
                                iconName: "more"
                                controlSize: MeridianButton.Small
                                enabled: !panel.busy
                                onClicked: {
                                    entryMenu.entry = row.modelData
                                    const remote = Store.platform.remoteEnabled === true && Store.workspace.details && Store.workspace.details.remote
                                    entryMenu.items = [
                                        { title: L10n.t("namedSnapshotInspect"), value: "inspect" },
                                        { title: L10n.t("namedSnapshotRestore"), value: "restore", enabled: row.modelData.ready && !remote },
                                        { title: L10n.t("namedSnapshotBranch"), value: "branch", enabled: row.modelData.ready && !remote },
                                        { separator: true },
                                        { title: L10n.t("delete"), value: "delete", danger: true, enabled: !remote },
                                    ]
                                    entryMenu.show(menuButton, 0, menuButton.height)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    CommandMenu {
        id: entryMenu
        property var entry: null
        onSelected: value => {
            if (value === "inspect")
                inspectDialog.show(entry)
            else
                panel.act(value, entry)
        }
    }

    // A snapshot's facts.
    MeridianDialog {
        id: inspectDialog
        property var entry: ({})
        function show(value) { entry = value; open() }
        title: entry.name ?? ""
        closeLabel: L10n.t("close")
        MeridianPropertyList {
            objectName: "named-snapshot-facts"
            width: parent ? parent.width : 0
            readonly property var number: value => Number(value ?? 0).toLocaleString(Qt.locale(L10n.locale), "f", 0)
            properties: [
                { label: L10n.t("namedSnapshotFactBranch"), value: inspectDialog.entry.baseRef ?? L10n.t("namedSnapshotNoBranch") },
                { label: L10n.t("namedSnapshotFactBase"), value: (inspectDialog.entry.baseOid ?? "").substring(0, 8), monospace: true },
                { label: L10n.t("changesStaged"), value: number(inspectDialog.entry.staged), selectable: false },
                { label: L10n.t("changesUnstaged"), value: number(inspectDialog.entry.unstaged), selectable: false },
                { label: L10n.t("namedSnapshotFactNewFiles"), value: number(inspectDialog.entry.untracked), selectable: false },
                { label: L10n.t("namedSnapshotFactId"), value: (inspectDialog.entry.objectId ?? "").substring(0, 8), monospace: true },
            ]
        }
    }
}
