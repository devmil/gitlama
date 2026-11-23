pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Which commit the staged change fixes, when the suggestion is not certain: the commits that last touched its files.
MeridianDialog {
    id: dialog

    property var suggestion: ({})
    readonly property var evidence: suggestion.evidence ?? []
    signal chosen(var evidence)

    function ask(value) {
        suggestion = value
        open()
    }

    objectName: "fixup-base-dialog"
    widthClass: MeridianDialog.Form
    title: L10n.t("fixupSuggestionPickTitle")
    description: suggestion.state === "ambiguous" ? L10n.t("fixupSuggestionAmbiguous") : L10n.t("fixupSuggestionPickHint")

    ListWell {
        width: parent ? parent.width : 0
        model: dialog.evidence
        delegate: MeridianListRow {
            required property var modelData
            width: ListView.view.width
            text: modelData.subject
            subtitle: modelData.path ?? modelData.commit.substring(0, 8)
            twoLine: true
            onClicked: {
                dialog.close()
                dialog.chosen(modelData)
            }
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.close() }
    ]
}
