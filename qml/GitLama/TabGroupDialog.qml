pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Sets a tab group's name, colour and icon at once (the Dart
// TabGroupDialog), with the group as the tab bar will show it.
MeridianDialog {
    id: dialog

    property var group: null
    property var tabLabels: []
    property var color: ({ series: 0 })
    property string icon: ""
    readonly property string groupName: nameField.text.trim().replace(/\s+/g, " ")
    readonly property color tint: AppearanceColors.color(AppearanceColors.keyOf(color))

    function show(value, labels) {
        group = value
        tabLabels = labels ?? []
        nameField.text = value.name ?? ""
        color = AppearanceColors.choice(value.color) ?? { series: 0 }
        icon = AppearanceColors.icons.indexOf(value.icon ?? "") >= 0 ? value.icon : ""
        open()
        nameField.forceActiveFocus()
    }
    function save() {
        if (!group)
            return
        Store.workspace.editTabGroup(group.id, groupName, AppearanceColors.keyOf(color), icon)
        close()
    }

    widthClass: MeridianDialog.Form
    title: L10n.t("tabGroupEditTitle")
    description: L10n.t("tabGroupEditDescription")
    onSubmitted: save()

    Column {
        width: parent ? parent.width : 0
        spacing: 0

        // The group as the tab bar will show it.
        Rectangle {
            objectName: "tab-group-preview"
            width: parent.width
            height: Metrics.tabStripHeight
            radius: Theme.radius.md
            color: Theme.colors.ground
            border.color: Theme.colors.line
            Accessible.role: Accessible.Graphic
            Accessible.name: L10n.t("tabGroupEditPreview")
            MeridianTabStrip {
                x: Theme.space.s3
                width: parent.width - 2 * Theme.space.s3
                height: parent.height
                enabled: false
                tabs: dialog.tabLabels.slice(0, GitLamaLayout.tabGroupPreviewTabs).map((label, index) => ({
                    id: index, label: label, group: dialog.group ? dialog.group.id : 0, renamable: false }))
                groups: dialog.group ? [{
                    id: dialog.group.id,
                    color: dialog.tint,
                    name: dialog.groupName,
                    icon: dialog.icon.length > 0 ? dialog.icon : null,
                    collapsed: false,
                    label: L10n.t("tabGroupUnnamed", [AppearanceColors.label(AppearanceColors.keyOf(dialog.color))]),
                }] : []
                activeTab: 0
            }
        }
        Item { width: 1; height: Theme.space.s6 }
        MeridianText { role: MeridianText.Label; text: L10n.t("tabGroupEditName") }
        Item { width: 1; height: Theme.space.s2 }
        MeridianTextField {
            id: nameField
            objectName: "tab-group-name"
            width: parent.width
            placeholderText: L10n.t("tabGroupNamePlaceholder")
            Accessible.name: L10n.t("tabGroupEditName")
            onAccepted: dialog.save()
        }
        Item { width: 1; height: Theme.space.s6 }
        MeridianText { role: MeridianText.Label; text: L10n.t("tabGroupColor") }
        Item { width: 1; height: Theme.space.s2 }
        MeridianColorChoiceRow {
            width: parent.width
            value: dialog.color
            customLabel: L10n.t("repositoryColorCustom")
            customValueLabel: hex => L10n.t("repositoryColorCustomValue", [hex])
            seriesLabels: AppearanceColors.seriesLabels
            pickerLabels: AppearanceColors.pickerLabels()
            onChosen: choice => { if (choice) dialog.color = choice }
        }
        Item { width: 1; height: Theme.space.s6 }
        MeridianText { role: MeridianText.Label; text: L10n.t("tabGroupIcon") }
        Item { width: 1; height: Theme.space.s2 }
        Flow {
            width: parent.width
            spacing: Theme.space.s2
            MeridianIconButton {
                objectName: "tab-group-icon-none"
                text: L10n.t("repositoryIconNone")
                iconName: "ban"
                controlSize: MeridianButton.Small
                active: dialog.icon.length === 0
                onClicked: dialog.icon = ""
            }
            Repeater {
                model: AppearanceColors.icons
                delegate: MeridianIconButton {
                    required property string modelData
                    objectName: "tab-group-icon-" + modelData
                    text: AppearanceColors.iconLabel(modelData)
                    iconName: modelData
                    iconColorOverride: dialog.tint
                    controlSize: MeridianButton.Small
                    active: dialog.icon === modelData
                    onClicked: dialog.icon = modelData
                }
            }
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            objectName: "tab-group-save"
            text: L10n.t("tabGroupEditSave")
            variant: MeridianButton.Primary
            onClicked: dialog.save()
        }
    ]
}
