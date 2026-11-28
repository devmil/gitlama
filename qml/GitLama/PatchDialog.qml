pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Meridian

// The patch dialog: Create writes a patch to a
// chosen folder after a preview of its scope, format, name and size; Apply
// checks a patch file against the repository and applies it. A finished
// step says what happened, shows the written file and offers to start
// again. Its state is `Store.patches`.
MeridianDialog {
    id: dialog

    readonly property var patchState: Store.patches ? (Store.patches.state ?? ({})) : ({})
    readonly property bool create: patchState.mode !== "apply"
    readonly property bool busy: patchState.busy === true
    readonly property var exportPreview: patchState.export ?? null
    readonly property var applyPreview: patchState.apply ?? null
    readonly property var completion: patchState.completion ?? null
    /// Why patches cannot be applied here; Apply then explains it instead.
    property string applyUnavailableReason: ""
    readonly property bool canSubmit: create
        ? exportPreview !== null && exportPreview.writable === true && !busy
        : applyPreview !== null && !busy && applyUnavailableReason.length === 0

    /// Opens the dialog for `source` ({kind, ...}, see patch_state.rs) in
    /// `mode` (create or apply).
    /// What the patch is made from ({kind, ...}).
    property var source: ({})
    function show(source, mode) {
        dialog.source = source
        Store.patches.begin(source, mode ?? "create")
        open()
    }
    function submit() {
        if (!canSubmit)
            return
        if (create)
            Store.patches.write()
        else
            Store.patches.apply()
    }
    function localPath(url) {
        const text = url.toString()
        return text.startsWith("file://") ? decodeURIComponent(text.slice(Qt.platform.os === "windows" ? 8 : 7)) : text
    }

    widthClass: MeridianDialog.Form
    title: L10n.t("patchTitle")
    description: create ? L10n.t("patchCreateDescription") : L10n.t("patchApplyDescription")
    submitDisabled: !canSubmit
    onSubmitted: submit()
    onClosed: Store.patches.end()

    FolderDialog {
        id: destinationPicker
        onAccepted: Store.patches.chooseDestination(dialog.localPath(selectedFolder))
    }
    FileDialog {
        id: patchPicker
        fileMode: FileDialog.OpenFile
        nameFilters: ["*.patch *.diff"]
        onAccepted: Store.patches.chooseFile(dialog.localPath(selectedFile))
    }

    Column {
        objectName: "patch-dialog-content"
        width: parent ? parent.width : 0
        spacing: Theme.space.s6

        // The mode switch hugs its two choices at the leading edge.
        MeridianSegmented {
            label: L10n.t("patchTitle")
            segments: [{ value: "create", label: L10n.t("patchCreate") }, { value: "apply", label: L10n.t("patchApply") }]
            value: dialog.create ? "create" : "apply"
            onActivated: value => Store.patches.setMode(value)
        }

        // What a finished write or apply did, then the way to start again.
        Column {
            visible: dialog.completion !== null
            objectName: "patch-completion"
            width: parent.width
            spacing: Theme.space.s6
            MeridianBanner {
                width: parent.width
                tone: dialog.completion === null ? MeridianBanner.Success
                    : dialog.completion.tone === "error" ? MeridianBanner.Error
                    : dialog.completion.tone === "warning" ? MeridianBanner.Warning : MeridianBanner.Success
                message: dialog.completion === null ? "" : L10n.t(dialog.completion.key)
                MeridianButton {
                    visible: dialog.completion !== null && !!dialog.completion.path
                    text: L10n.t("patchShowInFolder")
                    variant: MeridianButton.Secondary
                    controlSize: MeridianButton.Small
                    iconName: "folder-open"
                    onClicked: Store.workflows.revealPath(dialog.completion.path)
                }
            }
            MeridianPropertyList {
                visible: dialog.completion !== null && !!dialog.completion.path
                width: parent.width
                properties: [{ label: L10n.t("patchSavedTo"), value: dialog.completion && dialog.completion.path ? dialog.completion.path : "", monospace: true }]
            }
            MeridianButton {
                text: dialog.create ? L10n.t("patchChooseDestination") : L10n.t("patchChooseFile")
                variant: MeridianButton.Secondary
                iconName: "folder-open"
                enabled: !dialog.busy
                onClicked: dialog.create ? destinationPicker.open() : patchPicker.open()
            }
        }

        // Create.
        Column {
            visible: dialog.completion === null && dialog.create
            width: parent.width
            spacing: Theme.space.s6
            MeridianText {
                visible: dialog.exportPreview === null
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                text: L10n.t("patchDestinationUnset")
            }
            MeridianPropertyList {
                visible: dialog.exportPreview !== null
                objectName: "patch-export-facts"
                width: parent.width
                properties: {
                    const preview = dialog.exportPreview
                    if (preview === null)
                        return []
                    const facts = [
                        { label: L10n.t("patchScope"), value: L10n.t(preview.scope), selectable: false },
                        { label: L10n.t("patchFormat"), value: L10n.t(preview.format), selectable: false },
                        { label: L10n.t("patchFilename"), value: preview.filename, monospace: true },
                    ]
                    if (dialog.patchState.destination)
                        facts.push({ label: L10n.t("patchDestination"), value: dialog.patchState.destination, monospace: true })
                    facts.push({ label: L10n.t("patchSize"), value: Labels.byteSize(preview.bytes), selectable: false })
                    return facts
                }
            }
            MeridianBanner {
                visible: dialog.exportPreview !== null && dialog.exportPreview.requiresOverwrite === true
                width: parent.width
                tone: MeridianBanner.Warning
                message: L10n.t("patchOverwriteWarning")
            }
            MeridianButton {
                objectName: "patch-overwrite"
                visible: dialog.exportPreview !== null && dialog.exportPreview.requiresOverwrite === true
                text: L10n.t("patchOverwrite")
                variant: MeridianButton.Secondary
                enabled: !dialog.busy
                onClicked: Store.patches.overwrite()
            }
            MeridianButton {
                visible: !(dialog.exportPreview !== null && dialog.exportPreview.requiresOverwrite === true)
                text: L10n.t("patchChooseDestination")
                variant: MeridianButton.Secondary
                iconName: "folder-open"
                enabled: !dialog.busy
                onClicked: destinationPicker.open()
            }
        }

        // Apply.
        MeridianBanner {
            visible: dialog.completion === null && !dialog.create && dialog.applyUnavailableReason.length > 0
            objectName: "patch-apply-unavailable"
            width: parent.width
            tone: MeridianBanner.Info
            message: dialog.applyUnavailableReason
        }
        Column {
            visible: dialog.completion === null && !dialog.create && dialog.applyUnavailableReason.length === 0
            width: parent.width
            spacing: Theme.space.s6
            MeridianPropertyList {
                visible: !!dialog.patchState.patchPath
                objectName: "patch-apply-facts"
                width: parent.width
                properties: {
                    if (!dialog.patchState.patchPath)
                        return []
                    const facts = [
                        { label: L10n.t("patchFile"), value: dialog.patchState.patchPath, monospace: true },
                        { label: L10n.t("patchTarget"), value: dialog.source.kind === "history" ? (dialog.patchState.repositoryLabel ?? "")
                                                          : L10n.t("patchCurrentRepository") },
                    ]
                    if (dialog.applyPreview !== null) {
                        facts.push({ label: L10n.t("patchCheck"), value: L10n.t("patchCheckPassed"), selectable: false })
                        facts.push({ label: L10n.t("patchBinary"), value: L10n.t(dialog.applyPreview.binary ? "patchYes" : "patchNo"), selectable: false })
                    }
                    return facts
                }
            }
            MeridianText {
                visible: !dialog.patchState.patchPath
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                text: L10n.t("patchFileUnset")
            }
            MeridianButton {
                text: L10n.t("patchChooseFile")
                variant: MeridianButton.Secondary
                iconName: "folder-open"
                enabled: !dialog.busy
                onClicked: patchPicker.open()
            }
            ListWell {
                objectName: "patch-apply-files"
                visible: dialog.applyPreview !== null && (dialog.applyPreview.paths ?? []).length > 0
                width: parent.width
                implicitHeight: Math.min(view.contentHeight, maxHeight)
                model: dialog.applyPreview ? dialog.applyPreview.paths : []
                header: Item {
                    width: parent ? parent.width : 0
                    height: countText.implicitHeight + Theme.space.s4
                    MeridianText {
                        id: countText
                        x: Theme.space.s6
                        y: Theme.space.s4
                        role: MeridianText.Caption
                        color: Theme.colors.inkMuted
                        text: L10n.tn("patchFileCount", { count: dialog.applyPreview ? dialog.applyPreview.paths.length : 0 })
                    }
                }
                delegate: FileRow {
                    required property string modelData
                    width: ListView.view ? ListView.view.width : 0
                    path: modelData
                    activeFocusOnTab: false
                    leading: Component {
                        MeridianIcon { name: "file"; iconSize: MeridianIcon.Small; color: Theme.colors.inkMuted }
                    }
                }
            }
            GitCommands {
                visible: dialog.applyPreview !== null
                width: parent.width
                commands: dialog.applyPreview ? [dialog.applyPreview.command] : []
            }
        }

        MeridianProgressBar {
            visible: dialog.busy
            width: parent.width
        }
        MeridianBanner {
            visible: dialog.patchState.failed === true && dialog.completion === null
            width: parent.width
            tone: MeridianBanner.Error
            message: dialog.create ? L10n.t("patchExportFailed") : L10n.t("patchApplyFailed")
        }
    }
    actions: [
        MeridianButton {
            text: L10n.t("close")
            variant: MeridianButton.Quiet
            enabled: !dialog.busy
            onClicked: dialog.reject()
        },
        MeridianButton {
            text: dialog.create ? L10n.t("patchWrite") : L10n.t("patchApply")
            variant: MeridianButton.Primary
            enabled: dialog.canSubmit
            onClicked: dialog.submit()
        }
    ]
}
