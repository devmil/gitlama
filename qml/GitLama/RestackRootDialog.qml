pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The branch whose stack to restack (the Dart RestackRootDialog): a
// search field over the branches; choosing one answers.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var branches: []
    property string query: ""
    readonly property var shown: branches.filter(b => (b.name + " " + b.target).toLowerCase().indexOf(query) >= 0)
    signal answered(int id, var branch)

    function ask(id, payload) {
        promptId = id
        branches = payload.branches ?? []
        search.text = ""
        query = ""
        open()
        search.forceActiveFocus()
    }
    function choose(branch) {
        close()
        answered(promptId, branch)
        promptId = -1
    }

    widthClass: MeridianDialog.Form
    title: L10n.t("restackChooseRoot")
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        height: GitLamaLayout.rebaseTargetListHeight
        spacing: Theme.space.s5
        MeridianTextField {
            id: search
            width: parent.width
            variant: MeridianTextField.Search
            placeholderText: L10n.t("referencePickerSearch")
            Accessible.name: L10n.t("referencePickerSearch")
            onTextEdited: dialog.query = text.toLowerCase()
            onAccepted: if (dialog.shown.length > 0) dialog.choose(dialog.shown[0])
        }
        ListView {
            id: list
            width: parent.width
            height: parent.height - search.height - parent.spacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: dialog.shown
            MeridianWheelScroll { flickable: list }
            delegate: MeridianListRow {
                required property var modelData
                width: ListView.view.width
                iconName: "branch"
                text: modelData.name
                subtitle: modelData.target.substring(0, 8)
                onClicked: dialog.choose(modelData)
            }
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() }
    ]
}
