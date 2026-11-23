pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Every reference a field offers, searchable and grouped (the Dart
// _ReferencePickerDialog): branches, remotes, tags and commits under their
// titles. Up, Down and Enter pick one.
MeridianDialog {
    id: dialog

    property var choices: []
    property string query: ""
    property int highlighted: 0
    signal chosen(string value)

    readonly property var rows: choices.filter(choice => (choice.value + " " + choice.description).toLowerCase()
        .indexOf(query.toLowerCase()) >= 0)
    function groupTitle(icon) {
        return ({ branch: L10n.t("workspaceBranches"), cloud: L10n.t("workspaceRemotes"), tag: L10n.t("workspaceTags"),
                  "git-commit-horizontal": L10n.t("workspaceHistory") })[icon] ?? ""
    }
    function ask(label, all) {
        title = label
        choices = all
        query = ""
        highlighted = 0
        search.text = ""
        open()
        search.forceActiveFocus()
    }
    function choose(index) {
        const row = rows[index]
        if (!row)
            return
        close()
        chosen(row.value)
    }

    objectName: "reference-picker"
    widthClass: MeridianDialog.Form
    onSubmitted: choose(highlighted)

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s5
        MeridianTextField {
            id: search
            width: parent.width
            variant: MeridianTextField.Search
            placeholderText: L10n.t("referencePickerSearch")
            clearLabel: L10n.t("searchClear")
            Accessible.name: L10n.t("referencePickerSearch")
            onTextEdited: {
                dialog.query = text
                dialog.highlighted = 0
            }
            Keys.onDownPressed: dialog.highlighted = Math.min(Math.max(0, dialog.rows.length - 1), dialog.highlighted + 1)
            Keys.onUpPressed: dialog.highlighted = Math.max(0, dialog.highlighted - 1)
        }
        MeridianEmptyState {
            visible: dialog.rows.length === 0
            width: parent.width
            height: Theme.size.row * 3
            compact: true
            title: L10n.t("referencePickerEmpty")
        }
        ListWell {
            visible: dialog.rows.length > 0
            width: parent.width
            model: dialog.rows
            delegate: Column {
                id: entry
                required property var modelData
                required property int index
                readonly property string group: dialog.groupTitle(modelData.icon)
                readonly property bool startsGroup: group.length > 0
                    && (index === 0 || dialog.rows[index - 1].icon !== modelData.icon)
                width: ListView.view.width
                MeridianText {
                    visible: entry.startsGroup
                    leftPadding: Theme.space.s5
                    topPadding: Theme.space.s3
                    bottomPadding: Theme.space.s1
                    role: MeridianText.Overline
                    color: Theme.colors.inkMuted
                    text: entry.group
                }
                MeridianListRow {
                    width: parent.width
                    text: entry.modelData.value
                    meta: entry.modelData.description.length > 12 && /^[0-9a-f]+$/.test(entry.modelData.description)
                        ? entry.modelData.description.substring(0, 8) : entry.modelData.description
                    iconName: entry.modelData.icon
                    selected: entry.index === dialog.highlighted
                    onClicked: dialog.choose(entry.index)
                }
            }
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.close() }
    ]
}
