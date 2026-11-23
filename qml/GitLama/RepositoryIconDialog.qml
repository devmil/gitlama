pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Meridian

// The repository mark editor: an icon and a
// colour, or an image file, that marks a repository's tab, with a preview.
// The draft lives in Store.workspace.appearanceEdit (the image is read in
// Rust); Save stores it.
MeridianDialog {
    id: dialog

    readonly property var draft: Store.workspace ? (Store.workspace.appearanceEdit ?? null) : null
    property string icon: ""
    property var color: null
    property bool busy: false
    property bool saveFailed: false
    readonly property bool imageFailed: draft !== null && draft.imageFailed === true
    readonly property color tint: color ? AppearanceColors.color(AppearanceColors.keyOf(color)) : Theme.colors.inkMuted

    function show(tab) {
        icon = ""
        color = null
        busy = false
        saveFailed = false
        Store.workspace.editTabAppearance(tab.id)
        open()
    }
    property bool started: false
    onDraftChanged: {
        // The stored mark arrives once; later changes are the image.
        if (draft && !started) {
            started = true
            icon = draft.icon ?? ""
            color = AppearanceColors.choice(draft.color ?? "")
        }
    }
    function save() {
        if (busy || imageFailed)
            return
        busy = true
        Store.workspace.saveTabAppearance(icon, AppearanceColors.keyOf(color))
    }
    Connections {
        target: Store.workspace
        function onAppearanceSaved(ok) {
            if (!dialog.busy)
                return
            dialog.busy = false
            if (ok)
                dialog.close()
            else
                dialog.saveFailed = true
        }
    }

    widthClass: MeridianDialog.Form
    title: L10n.t("repositoryIconTitle")
    description: L10n.t("repositoryIconDescription")
    submitDisabled: busy || imageFailed
    onSubmitted: save()
    onClosed: { started = false; Store.workspace.endTabAppearance() }

    FileDialog {
        id: imagePicker
        fileMode: FileDialog.OpenFile
        nameFilters: ["*.png *.jpg *.jpeg *.gif *.webp *.bmp *.ico *.svg"]
        onAccepted: {
            const url = selectedFile.toString()
            dialog.saveFailed = false
            Store.workspace.setAppearanceImage(url.startsWith("file://") ? decodeURIComponent(url.slice(Qt.platform.os === "windows" ? 8 : 7)) : url)
        }
    }

    Column {
        width: parent ? parent.width : 0
        spacing: 0

        Row {
            objectName: "repository-icon-preview"
            spacing: Theme.space.s3
            RepositoryIcon {
                anchors.verticalCenter: parent.verticalCenter
                mark: dialog.draft && (dialog.draft.imageUrl || dialog.icon.length > 0 || dialog.color)
                    ? { image: dialog.draft.imageUrl ?? "", icon: dialog.icon, color: AppearanceColors.keyOf(dialog.color) } : null
            }
            MeridianText {
                anchors.verticalCenter: parent.verticalCenter
                role: MeridianText.BodyStrong
                elide: Text.ElideRight
                text: dialog.draft ? dialog.draft.name : ""
            }
        }
        Item { width: 1; height: Theme.space.s6 }
        MeridianText { role: MeridianText.Label; text: L10n.t("repositoryIconSymbol") }
        Item { width: 1; height: Theme.space.s2 }
        Flow {
            width: parent.width
            spacing: Theme.space.s2
            MeridianIconButton {
                objectName: "repository-icon-none"
                text: L10n.t("repositoryIconNone")
                iconName: "ban"
                controlSize: MeridianButton.Small
                active: dialog.icon.length === 0
                enabled: !dialog.busy
                onClicked: { dialog.icon = ""; dialog.saveFailed = false }
            }
            Repeater {
                model: AppearanceColors.icons
                delegate: MeridianIconButton {
                    required property string modelData
                    objectName: "repository-icon-" + modelData
                    text: AppearanceColors.iconLabel(modelData)
                    iconName: modelData
                    iconColorOverride: dialog.tint
                    controlSize: MeridianButton.Small
                    active: dialog.icon === modelData
                    enabled: !dialog.busy
                    onClicked: { dialog.icon = modelData; dialog.saveFailed = false }
                }
            }
        }
        Item { width: 1; height: Theme.space.s6 }
        MeridianText { role: MeridianText.Label; text: L10n.t("repositoryIconColor") }
        Item { width: 1; height: Theme.space.s2 }
        MeridianColorChoiceRow {
            width: parent.width
            value: dialog.color
            allowNone: true
            noneLabel: L10n.t("repositoryColorNone")
            customLabel: L10n.t("repositoryColorCustom")
            customValueLabel: hex => L10n.t("repositoryColorCustomValue", [hex])
            seriesLabels: AppearanceColors.seriesLabels
            pickerLabels: AppearanceColors.pickerLabels()
            enabled: !dialog.busy
            onChosen: choice => { dialog.color = choice; dialog.saveFailed = false }
        }
        Item { width: 1; height: Theme.space.s6 }
        MeridianText { role: MeridianText.Label; text: L10n.t("repositoryIconImage") }
        Item { width: 1; height: Theme.space.s2 }
        Row {
            spacing: Theme.space.s3
            MeridianButton {
                objectName: "repository-icon-choose-image"
                text: L10n.t("repositoryIconChooseImage")
                iconName: "image-plus"
                controlSize: MeridianButton.Small
                enabled: !dialog.busy
                onClicked: imagePicker.open()
            }
            MeridianButton {
                objectName: "repository-icon-remove-image"
                visible: dialog.draft !== null && !!dialog.draft.image
                text: L10n.t("repositoryIconRemoveImage")
                variant: MeridianButton.Quiet
                controlSize: MeridianButton.Small
                enabled: !dialog.busy
                onClicked: { Store.workspace.setAppearanceImage(""); dialog.saveFailed = false }
            }
        }
        Item { width: 1; height: Theme.space.s3 }
        MeridianText {
            width: parent.width
            role: MeridianText.Caption
            wrapMode: Text.Wrap
            color: dialog.imageFailed || dialog.saveFailed ? Theme.colors.danger : Theme.colors.inkMuted
            text: dialog.imageFailed ? L10n.t("repositoryIconImageUnreadable")
                : dialog.saveFailed ? L10n.t("repositoryIconSaveFailed") : L10n.t("repositoryIconImageHint")
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            objectName: "repository-icon-save"
            text: L10n.t("repositoryIconSave")
            variant: MeridianButton.Primary
            enabled: !dialog.busy && !dialog.imageFailed
            onClicked: dialog.save()
        }
    ]
}
