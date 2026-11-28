pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The record of remote changes: every remote write, newest
// first, with its host, family and state. An unresolved one can be checked again on its
// connected host; a resolved one can be dismissed. GitLama never repeats a write.
MeridianDialog {
    id: dialog

    /// Hosts whose writes are being looked up again.
    property var checking: ({})
    readonly property var operations: Store.remote ? (Store.remote.operations ?? []) : []
    readonly property var helper: Store.remote ? (Store.remote.helper ?? ({})) : ({})
    readonly property bool uncertain: operations.some(operation => Labels.remoteOperationNeedsReview(operation))

    function familyIcon(family) {
        return ({ stage: "layers", commit: "check", refs: "branch", stash: "stash", transfer: "push", discard: "trash",
                  history: "git-merge", rebase: "squash", restack: "git-fork", bisect: "search", conflict: "circle-alert",
                  sequencer: "skip-forward", snapshot: "save", snapshotRestore: "recovery", restore: "rotate-ccw",
                  indexLock: "key", patch: "file-diff", extension: "puzzle" })[family] ?? "circle-alert"
    }
    function check(profileId) {
        const next = Object.assign({}, checking)
        next[profileId] = true
        checking = next
        Store.remote.reconcile(profileId)
        settle.restart()
    }
    onOperationsChanged: checking = ({})
    Timer { id: settle; interval: GitLamaLayout.remoteCheckSettle; onTriggered: dialog.checking = ({}) }

    widthClass: MeridianDialog.Workflow
    title: L10n.t("remoteOperationsTitle")
    description: L10n.t("remoteOperationsDescription")

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6

        MeridianBanner {
            visible: dialog.helper.ledgerUsable === false
            width: parent.width
            tone: MeridianBanner.Error
            message: L10n.t("remoteOperationsLedgerUnavailable")
        }
        MeridianBanner {
            objectName: "remote-operations-uncertain"
            visible: dialog.uncertain
            width: parent.width
            tone: MeridianBanner.Warning
            message: L10n.t("remoteOperationsUncertain")
        }
        MeridianText {
            visible: dialog.operations.length === 0
            width: parent.width
            color: Theme.colors.inkMuted
            text: L10n.t("remoteOperationsEmpty")
        }
        ListWell {
            objectName: "remote-operations-list"
            visible: dialog.operations.length > 0
            width: parent.width
            model: dialog.operations
            delegate: MeridianListRow {
                id: row
                required property var modelData
                readonly property var host: Labels.remoteHost(modelData.profileId)
                readonly property bool connected: host !== null && host.ready === true
                readonly property string stateLabel: Labels.remoteOperationState(modelData)
                readonly property string family: Labels.remoteFamily(modelData.family)
                objectName: "remote-operation-" + modelData.id
                width: ListView.view.width
                text: modelData.summary.length > 0 ? modelData.summary : family
                subtitle: L10n.tn("remoteOperationSubtitle", { host: modelData.host ?? L10n.t("remoteHostUnknown"), family: family, state: stateLabel })
                twoLine: true
                semanticValue: stateLabel
                leading: Component { MeridianIcon { name: dialog.familyIcon(row.modelData.family) } }
                trailing: Component {
                    Item {
                        implicitWidth: row.modelData.pending ? checkButton.implicitWidth : dismissButton.implicitWidth
                        implicitHeight: Theme.size.controlSmall
                        MeridianButton {
                            id: checkButton
                            objectName: "remote-operation-check-" + row.modelData.id
                            visible: row.modelData.pending
                            text: L10n.t("remoteOperationCheckAgain")
                            controlSize: MeridianButton.Small
                            loading: dialog.checking[row.modelData.profileId] === true
                            enabled: row.connected && dialog.checking[row.modelData.profileId] !== true
                            disabledReason: row.connected ? "" : L10n.t("remoteOperationCheckDisconnected")
                            onClicked: dialog.check(row.modelData.profileId)
                        }
                        MeridianButton {
                            id: dismissButton
                            objectName: "remote-operation-dismiss-" + row.modelData.id
                            visible: !row.modelData.pending
                            text: L10n.t("remoteOperationDismiss")
                            controlSize: MeridianButton.Small
                            variant: MeridianButton.Quiet
                            onClicked: Store.remote.dismissOperation(row.modelData.id)
                        }
                    }
                }
            }
        }
    }
    actions: [
        MeridianButton { text: L10n.t("close"); variant: MeridianButton.Quiet; onClicked: dialog.close() }
    ]
}
