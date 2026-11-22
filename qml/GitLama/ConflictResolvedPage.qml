pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Once no file is conflicted (the Dart resolver's resolved page): the merge
// message of a paused merge and every resolved file, each of which can be
// put back. The page scrolls as one.
Flickable {
    id: page

    property var conflictState: ({})
    readonly property bool busy: conflictState.busy === true
    readonly property var resolved: conflictState.resolved ?? []
    readonly property bool merge: conflictState.operation === "merge"
    readonly property real inset: Math.max(Theme.space.s8, (width - GitLamaLayout.mergeMessageMaxWidth) / 2)

    clip: true
    contentHeight: column.implicitHeight + 2 * Theme.space.s9
    boundsBehavior: Flickable.StopAtBounds
    MeridianWheelScroll { flickable: page }

    function outcomeText(outcome) {
        switch (outcome) {
        case "deleted": return L10n.t("conflictOutcomeDeleted")
        case "current": return L10n.tn("conflictOutcomeCurrent", { label: conflictState.currentLabel ?? "" })
        case "incoming": return L10n.tn("conflictOutcomeIncoming", { label: conflictState.incomingLabel ?? "" })
        case "merged": return L10n.t("conflictOutcomeMerged")
        case "external": return L10n.t("conflictOutcomeExternal")
        default: return ""
        }
    }

    Column {
        id: column
        x: page.inset
        y: Theme.space.s9
        width: page.width - 2 * page.inset
        spacing: 0

        MeridianIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "circle-check"
            extent: GitLamaLayout.resolvedStateIconSize
            color: Theme.colors.success
        }
        Item { width: 1; height: Theme.space.s5 }
        MeridianText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            role: MeridianText.Title
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: L10n.t(page.conflictState.operation === "standalone" ? "conflictStandaloneResolved" : "conflictAllResolved")
        }
        Item { visible: page.merge; width: 1; height: Theme.space.s8 }
        MeridianText {
            visible: page.merge
            width: parent.width
            role: MeridianText.Label
            text: L10n.t("commitSubject")
        }
        MeridianTextField {
            id: subject
            visible: page.merge
            width: parent.width
            Accessible.name: L10n.t("commitSubject")
            text: page.conflictState.mergeSubject ?? ""
            onTextEdited: Store.conflicts.setMergeMessage(text, description.text)
        }
        Item { visible: page.merge; width: 1; height: Theme.space.s5 }
        MeridianText {
            visible: page.merge
            width: parent.width
            role: MeridianText.Label
            text: L10n.t("commitDescription")
        }
        MeridianTextArea {
            id: description
            visible: page.merge
            width: parent.width
            minimumLines: 3
            maximumLines: 5
            Accessible.name: L10n.t("commitDescription")
            text: page.conflictState.mergeDescription ?? ""
            textArea.onTextChanged: if (textArea.activeFocus) Store.conflicts.setMergeMessage(subject.text, text)
        }

        Item { visible: page.resolved.length > 0; width: 1; height: Theme.space.s8 }
        Item {
            visible: page.resolved.length > 0
            width: parent.width
            height: Math.max(undoAll.height, resolvedTitle.height)
            MeridianText {
                id: resolvedTitle
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - count.width - undoAll.width - 2 * Theme.space.s3)
                role: MeridianText.BodyStrong
                text: L10n.t("conflictResolvedFiles")
            }
            MeridianCount {
                id: count
                x: resolvedTitle.width + Theme.space.s3
                anchors.verticalCenter: parent.verticalCenter
                label: String(page.resolved.length)
            }
            MeridianButton {
                id: undoAll
                visible: page.resolved.length > 1
                x: parent.width - width
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t("conflictUndoAll")
                iconName: "undo"
                variant: MeridianButton.Quiet
                controlSize: MeridianButton.Small
                enabled: !page.busy
                onClicked: Store.conflicts.forEach(page.resolved.map(file => file.key), "")
            }
        }
        Item { visible: page.resolved.length > 0; width: 1; height: Theme.space.s2 }
        MeridianText {
            visible: page.resolved.length > 0
            width: parent.width
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: L10n.t("conflictResolvedHint")
        }
        Item { visible: page.resolved.length > 0; width: 1; height: Theme.space.s3 }
        Rectangle {
            visible: page.resolved.length > 0
            width: parent.width
            height: files.height + 2 * Theme.space.s3
            radius: Theme.radius.lg
            color: Theme.colors.paneAlt
            Column {
                id: files
                x: Theme.space.s3
                y: Theme.space.s3
                width: parent.width - 2 * Theme.space.s3
                Repeater {
                    model: page.resolved
                    delegate: MeridianListRow {
                        id: fileRow
                        required property var modelData
                        readonly property string outcome: page.outcomeText(modelData.outcome)
                        readonly property int slash: modelData.path.lastIndexOf("/")
                        width: files.width
                        text: modelData.path.substring(slash + 1)
                        subtitle: [outcome, slash >= 0 ? modelData.path.substring(0, slash) : ""].filter(part => part.length > 0).join(" · ")
                        semanticValue: [modelData.path, outcome].filter(part => part.length > 0).join(", ")
                        leading: Component {
                            MeridianIcon {
                                name: fileRow.modelData.outcome === "deleted" ? "trash-2" : "check"
                                color: fileRow.modelData.outcome === "deleted" ? Theme.colors.danger : Theme.colors.success
                            }
                        }
                        trailing: Component {
                            MeridianIconButton {
                                iconName: "undo"
                                text: L10n.t("conflictUndoResolution")
                                controlSize: MeridianButton.Small
                                enabled: !page.busy
                                onClicked: Store.conflicts.undo(fileRow.modelData.key)
                            }
                        }
                    }
                }
            }
        }
    }
}
