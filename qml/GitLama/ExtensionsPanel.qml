pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import QtQuick.Dialogs
import Meridian

// Worktrees, submodules and Git LFS of the active repository (the Dart
// RepositoryExtensionsPanel): each a disclosure with its rows and actions,
// the add-worktree dialog and LFS patterns. The inventory and its changes
// live in Rust (Store.workflows.extensions).
MeridianPanel {
    id: panel

    property real availableHeight: GitLamaLayout.extensionsBodyMaxHeight + headerHeight
    /// Opened for "Track LFS pattern": the LFS section opens with its field focused.
    property bool focusLfs: false
    readonly property var panelState: Store.workflows ? (Store.workflows.extensions ?? ({})) : ({})
    readonly property var inventory: panelState.inventory ?? null
    readonly property bool busy: panelState.busy === true

    title: L10n.t("repositoryExtensionsTitle")
    closeLabel: L10n.t("close")
    width: GitLamaLayout.extensionsPanelWidth
    leftPadding: 0
    rightPadding: 0
    bottomPadding: 0

    function act(action, options) { Store.workflows.extension(action, options ?? ({})) }
    function lfs(action) { act(action, { pattern: lfsPattern.text.trim() }) }

    actions: [
        MeridianIconButton {
            text: L10n.t("workspaceRefresh")
            iconName: "refresh"
            controlSize: MeridianButton.Small
            enabled: !panel.busy
            onClicked: panel.act("load")
        }
    ]

    // Another tab's repository has its own extensions.
    readonly property var tabId: Store.workspace.active ? Store.workspace.active.id : null
    onTabIdChanged: act("open")
    Component.onCompleted: act("open")
    onInventoryChanged: {
        if (focusLfs && inventory && inventory.lfsAvailable) {
            focusLfs = false
            Qt.callLater(() => {
                lfsPattern.forceActiveFocus()
                list.contentY = Math.max(0, Math.min(lfsSection.y - list.height * 0.45, list.contentHeight - list.height))
            })
        }
    }

    Column {
        width: panel.bodyWidth
        height: Math.min(implicitHeight, Math.min(GitLamaLayout.extensionsBodyMaxHeight, panel.availableHeight - panel.headerHeight))

        MeridianProgressBar {
            visible: panel.busy
            width: parent.width
        }
        Item {
            visible: !!panel.panelState.failure
            width: parent.width
            height: visible ? failureBanner.implicitHeight + 2 * Theme.space.s4 : 0
            MeridianBanner {
                id: failureBanner
                x: Theme.space.s4
                y: Theme.space.s4
                width: parent.width - 2 * Theme.space.s4
                tone: MeridianBanner.Error
                message: panel.panelState.failure ? L10n.t(panel.panelState.failure) : ""
            }
        }
        MeridianEmptyState {
            visible: panel.inventory === null
            width: parent.width
            height: visible ? GitLamaLayout.extensionsBodyMaxHeight / 2 : 0
            compact: true
            progress: true
            title: L10n.t("loading")
        }
        Flickable {
            id: list
            objectName: "extensions-list"
            visible: panel.inventory !== null
            width: parent.width
            height: Math.min(contentHeight, GitLamaLayout.extensionsBodyMaxHeight, panel.availableHeight - panel.headerHeight)
            contentHeight: sections.implicitHeight + Theme.space.s5
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            MeridianWheelScroll { flickable: list }
            C.ScrollBar.vertical: MeridianScrollBar {}

            Column {
                id: sections
                x: Theme.space.s5
                width: list.width - 2 * Theme.space.s5

                MeridianDisclosure {
                    objectName: "extensions-worktrees"
                    width: parent.width
                    title: L10n.t("extensionWorktrees")
                    expanded: !panel.focusLfs
                    onToggled: value => expanded = value
                    Column {
                        width: parent ? parent.width : 0
                        Repeater {
                            model: panel.inventory ? panel.inventory.worktrees : []
                            delegate: MeridianListRow {
                                id: worktreeRow
                                required property var modelData
                                required property int index
                                width: parent ? parent.width : 0
                                text: modelData.title
                                subtitle: modelData.path
                                trailing: Component {
                                    Row {
                                        spacing: Theme.space.s2
                                        MeridianCount {
                                            anchors.verticalCenter: parent.verticalCenter
                                            label: worktreeRow.modelData.locked ? L10n.t("extensionWorktreeLocked")
                                                : worktreeRow.modelData.current ? L10n.t("extensionWorktreeCurrent")
                                                : worktreeRow.modelData.head ?? L10n.t("detachedHead")
                                        }
                                        MeridianButton {
                                            text: L10n.t("extensionOpen")
                                            variant: MeridianButton.Quiet
                                            controlSize: MeridianButton.Small
                                            enabled: !worktreeRow.modelData.current && !panel.busy
                                            onClicked: panel.act("openWorktree", { index: worktreeRow.index })
                                        }
                                        MeridianButton {
                                            text: L10n.tn("openInFileBrowser", { browser: Labels.fileBrowserName() })
                                            variant: MeridianButton.Quiet
                                            controlSize: MeridianButton.Small
                                            enabled: !panel.busy
                                            onClicked: Store.workflows.openFolder(worktreeRow.modelData.path)
                                        }
                                        MeridianButton {
                                            text: L10n.t("delete")
                                            variant: MeridianButton.DangerQuiet
                                            controlSize: MeridianButton.Small
                                            enabled: worktreeRow.modelData.deletable && !panel.busy
                                            onClicked: panel.act("deleteWorktree", { index: worktreeRow.index })
                                        }
                                    }
                                }
                            }
                        }
                        Item { width: 1; height: Theme.space.s6 }
                        MeridianButton {
                            objectName: "extensions-create-worktree"
                            text: L10n.t("extensionWorktreeCreate")
                            iconName: "plus"
                            variant: MeridianButton.Primary
                            enabled: !panel.busy
                            onClicked: createWorktree.show()
                        }
                    }
                }

                MeridianDisclosure {
                    objectName: "extensions-submodules"
                    width: parent.width
                    title: L10n.t("extensionSubmodules")
                    onToggled: value => expanded = value
                    Column {
                        width: parent ? parent.width : 0
                        MeridianListRow {
                            visible: panel.inventory !== null && panel.inventory.submodules.length === 0
                            width: parent.width
                            text: L10n.t("extensionNone")
                        }
                        Repeater {
                            model: panel.inventory ? panel.inventory.submodules : []
                            delegate: MeridianListRow {
                                id: submoduleRow
                                required property var modelData
                                required property int index
                                width: parent ? parent.width : 0
                                text: modelData.path
                                trailing: Component {
                                    Row {
                                        spacing: Theme.space.s2
                                        MeridianCount {
                                            anchors.verticalCenter: parent.verticalCenter
                                            label: L10n.t(submoduleRow.modelData.state)
                                        }
                                        MeridianButton {
                                            text: submoduleRow.modelData.initialized ? L10n.t("extensionUpdate") : L10n.t("extensionInitialize")
                                            variant: MeridianButton.Quiet
                                            controlSize: MeridianButton.Small
                                            enabled: !panel.busy
                                            onClicked: panel.act("submodule", { index: submoduleRow.index })
                                        }
                                        MeridianButton {
                                            text: L10n.t("extensionOpen")
                                            variant: MeridianButton.Quiet
                                            controlSize: MeridianButton.Small
                                            enabled: submoduleRow.modelData.initialized && !panel.busy
                                            onClicked: panel.act("enterSubmodule", { index: submoduleRow.index })
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                MeridianDisclosure {
                    id: lfsSection
                    objectName: "extensions-lfs"
                    width: parent.width
                    title: L10n.t("extensionLfs")
                    expanded: panel.focusLfs
                    onToggled: value => expanded = value
                    Column {
                        width: parent ? parent.width : 0
                        Item {
                            width: parent.width
                            height: pullButton.implicitHeight
                            MeridianButton {
                                id: pullButton
                                anchors.right: parent.right
                                text: L10n.t("extensionLfsPull")
                                variant: MeridianButton.Quiet
                                enabled: panel.inventory !== null && panel.inventory.lfsAvailable && !panel.busy
                                onClicked: panel.act("lfsPull")
                            }
                        }
                        MeridianListRow {
                            visible: panel.inventory !== null && !panel.inventory.lfsAvailable
                            width: parent.width
                            text: L10n.t("extensionLfsUnavailable")
                        }
                        Row {
                            visible: panel.inventory !== null && panel.inventory.lfsAvailable
                            width: parent.width
                            spacing: Theme.space.s2
                            Column {
                                width: parent.width - trackButton.width - untrackButton.width - 2 * parent.spacing
                                spacing: Theme.space.s2
                                MeridianText { role: MeridianText.Label; text: L10n.t("extensionLfsPattern") }
                                MeridianTextField {
                                    id: lfsPattern
                                    objectName: "extension-lfs-pattern"
                                    width: parent.width
                                    enabled: !panel.busy
                                    Accessible.name: L10n.t("extensionLfsPattern")
                                    onAccepted: panel.lfs("lfsTrack")
                                }
                            }
                            MeridianButton {
                                id: trackButton
                                anchors.bottom: parent.bottom
                                text: L10n.t("extensionLfsTrack")
                                variant: MeridianButton.Quiet
                                enabled: !panel.busy
                                onClicked: panel.lfs("lfsTrack")
                            }
                            MeridianButton {
                                id: untrackButton
                                anchors.bottom: parent.bottom
                                text: L10n.t("extensionLfsUntrack")
                                variant: MeridianButton.Quiet
                                enabled: !panel.busy
                                onClicked: panel.lfs("lfsUntrack")
                            }
                        }
                        Repeater {
                            model: panel.inventory ? panel.inventory.lfs : []
                            delegate: MeridianListRow {
                                id: lfsRow
                                required property var modelData
                                required property int index
                                width: parent ? parent.width : 0
                                text: modelData.path
                                trailing: Component {
                                    Row {
                                        spacing: Theme.space.s2
                                        MeridianCount {
                                            anchors.verticalCenter: parent.verticalCenter
                                            label: L10n.t(lfsRow.modelData.state)
                                        }
                                        MeridianButton {
                                            text: L10n.t("extensionInspectPointer")
                                            variant: MeridianButton.Quiet
                                            controlSize: MeridianButton.Small
                                            enabled: !panel.busy
                                            onClicked: panel.act("inspectPointer", { index: lfsRow.index })
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

    // Adds a worktree: the commit or branch it checks out and its folder.
    MeridianDialog {
        id: createWorktree
        objectName: "extension-worktree-dialog"
        function show() {
            referenceField.text = "HEAD"
            pathField.text = ""
            open()
            pathField.forceActiveFocus()
        }
        function finish() {
            if (pathField.text.trim().length === 0)
                return
            panel.act("createWorktree", { path: pathField.text.trim(), reference: referenceField.text.trim() })
            close()
        }
        widthClass: MeridianDialog.Form
        title: L10n.t("extensionWorktreeCreate")
        description: L10n.t("extensionWorktreeCreateDescription")
        submitDisabled: pathField.text.trim().length === 0
        onSubmitted: finish()
        Column {
            width: parent ? parent.width : 0
            spacing: Theme.space.s6
            ReferenceField {
                id: referenceField
                width: parent.width
                label: L10n.t("extensionWorktreeReference")
                helperText: L10n.t("referencePickerHistoryHint")
                names: []
                choices: Store.history ? Store.history.referenceChoices() : []
            }
            // The folder button belongs to the path above it and starts at
            // the fields' leading edge.
            Column {
                width: parent.width
                spacing: Theme.space.s3
                Column {
                    width: parent.width
                    spacing: Theme.space.s2
                    MeridianText { role: MeridianText.Label; text: L10n.t("extensionWorktreePath") }
                    MeridianTextField {
                        id: pathField
                        objectName: "extension-worktree-path"
                        width: parent.width
                        Accessible.name: L10n.t("extensionWorktreePath")
                        onAccepted: createWorktree.finish()
                    }
                }
                MeridianButton {
                    objectName: "extension-worktree-choose-folder"
                    text: L10n.t("extensionWorktreeChooseFolder")
                    iconName: "folder-open"
                    variant: MeridianButton.Quiet
                    onClicked: folderPicker.open()
                }
            }
        }
        actions: [
            MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: createWorktree.close() },
            MeridianButton {
                text: L10n.t("extensionWorktreeCreate")
                variant: MeridianButton.Primary
                enabled: pathField.text.trim().length > 0
                onClicked: createWorktree.finish()
            }
        ]
    }
    FolderDialog {
        id: folderPicker
        onAccepted: {
            const text = selectedFolder.toString()
            pathField.text = text.startsWith("file://") ? decodeURIComponent(text.slice(Qt.platform.os === "windows" ? 8 : 7)) : text
        }
    }

    function showCreateWorktree() { createWorktree.show() }
}
