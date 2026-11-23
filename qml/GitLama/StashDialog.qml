pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The stash dialog: a message and what to stash
// for a new stash, a new name for a rename, the target branch of a
// stash-and-switch, a warning before dropping.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var payload: ({})
    readonly property string kind: payload.kind ?? "push"
    readonly property bool push: kind === "push"
    readonly property bool rename: kind === "rename"
    readonly property bool auto: kind === "autoStashCheckout"
    readonly property var tracked: payload.tracked ?? []
    property bool selecting: false
    property bool includeUntracked: false
    property bool keepIndex: false
    property var selected: []
    // Development screenshots: `stashSelect:<index>` picks files to stash.
    Connections {
        target: Store
        function onScreenshotStepRequested(name, argument) {
            if (name === "stashSelect" && dialog.opened) {
                dialog.selecting = true
                if (argument.length > 0)
                    dialog.toggle(Number(argument))
            }
        }
    }
    function toggle(index) {
        const next = selected.filter(item => item !== index)
        if (next.length === selected.length)
            next.push(index)
        selected = next
    }
    readonly property string targetBranch: (payload.branches ?? []).indexOf(branchField.text.trim()) >= 0 ? branchField.text.trim() : ""
    readonly property bool valid: (!rename || message.text.trim().length > 0) && (!auto || targetBranch.length > 0)
        && (!(push && selecting) || selected.length > 0)
    readonly property string titleText: Commands.dialogTitle(Commands.label(({ push: "createStash", apply: "applyStash",
        pop: "popStash", drop: "dropStash", rename: "renameStash", autoStashCheckout: "autoStashCheckout" })[kind] ?? "createStash"))
    signal answered(int id, var request)

    function ask(id, value) {
        promptId = id
        payload = value
        message.text = value.initialMessage ?? ""
        branchField.text = value.initialTargetBranch ?? ""
        selecting = false
        includeUntracked = false
        keepIndex = false
        selected = []
        open()
        if (push || rename)
            message.forceActiveFocus()
    }
    function submit() {
        if (!valid)
            return
        close()
        const chosen = push && selecting
        answered(promptId, {
            message: (push || rename) ? message.text.trim() : "",
            paths: chosen ? selected.slice().sort((a, b) => a - b).map(index => tracked[index]) : [],
            includeUntracked: push && !chosen && includeUntracked,
            keepIndex: push && keepIndex,
            targetBranch: auto ? targetBranch : "",
        })
        promptId = -1
    }

    widthClass: MeridianDialog.Form
    title: titleText
    description: push ? L10n.t("stashPushIntro") : ""
    submitDisabled: !valid
    onSubmitted: submit()
    onRejected: { answered(promptId, null); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6

        MeridianSelectableText {
            visible: !!dialog.payload.selector
            width: parent.width
            text: dialog.payload.selector ? L10n.tn("stashSelected", { selector: dialog.payload.selector }) : ""
        }
        Column {
            visible: dialog.push || dialog.rename
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: dialog.rename ? L10n.t("stashNewName") : L10n.t("stashMessage") }
            MeridianTextField {
                id: message
                width: parent.width
                maximumLength: 256
                placeholderText: dialog.push ? L10n.t("stashMessagePlaceholder") : ""
                Accessible.name: dialog.rename ? L10n.t("stashNewName") : L10n.t("stashMessage")
            }
        }
        Column {
            visible: dialog.push
            width: parent.width
            MeridianRadio {
                objectName: "stash-scope-all"
                text: L10n.tn("stashScopeAll", { count: dialog.tracked.length + (dialog.includeUntracked ? (dialog.payload.untracked ?? 0) : 0) })
                checked: !dialog.selecting
                onClicked: dialog.selecting = false
            }
            MeridianRadio {
                objectName: "stash-scope-selected"
                text: L10n.t("stashScopeSelected")
                enabled: dialog.tracked.length > 0
                checked: dialog.selecting
                onClicked: dialog.selecting = true
            }
        }
        // The files to stash: the count and
        // Select all or none over rows of status and path.
        ListWell {
            visible: dialog.push && dialog.selecting
            width: parent.width
            model: dialog.tracked
            header: Item {
                width: ListView.view ? ListView.view.width : 0
                height: selectAll.height + Theme.space.s3
                MeridianText {
                    x: Theme.space.s6
                    anchors.verticalCenter: selectAll.verticalCenter
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: L10n.tn("stashSelectionCount", { selected: dialog.selected.length, count: dialog.tracked.length })
                }
                MeridianButton {
                    id: selectAll
                    objectName: "stash-select-all"
                    readonly property bool all: dialog.selected.length === dialog.tracked.length
                    y: Theme.space.s3
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space.s3
                    variant: MeridianButton.Quiet
                    controlSize: MeridianButton.Small
                    text: all ? L10n.t("stashSelectNone") : L10n.t("stashSelectAll")
                    onClicked: dialog.selected = all ? [] : dialog.tracked.map((_, index) => index)
                }
            }
            delegate: MeridianListRow {
                id: fileEntry
                required property string modelData
                required property int index
                objectName: "stash-file-" + index
                width: ListView.view.width
                text: modelData
                leading: Component {
                    Row {
                        spacing: Theme.space.s3
                        MeridianCheckbox {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: dialog.selected.indexOf(fileEntry.index) >= 0
                            onToggled: dialog.toggle(fileEntry.index)
                            Accessible.name: fileEntry.modelData
                        }
                        StatusGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            status: (dialog.payload.trackedStatus ?? [])[fileEntry.index] ?? "M"
                        }
                    }
                }
                onClicked: dialog.toggle(index)
            }
        }
        MeridianText {
            visible: dialog.push && dialog.selecting && (dialog.payload.untracked ?? 0) > 0
            width: parent.width
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: L10n.tn("stashSelectedUntrackedNote", { count: dialog.payload.untracked ?? 0 })
            wrapMode: Text.Wrap
        }
        Column {
            visible: dialog.push
            width: parent.width
            spacing: Theme.space.s4
            MeridianCheckbox {
                objectName: "stash-include-untracked"
                visible: !dialog.selecting
                width: parent.width
                text: L10n.t("stashIncludeUntracked")
                description: L10n.t("stashIncludeUntrackedHelp")
                checked: dialog.includeUntracked
                onToggled: dialog.includeUntracked = checked
            }
            MeridianCheckbox {
                objectName: "stash-keep-index"
                width: parent.width
                text: L10n.t("stashKeepIndex")
                description: L10n.t("stashKeepIndexHelp")
                checked: dialog.keepIndex
                onToggled: dialog.keepIndex = checked
            }
        }
        ReferenceField {
            id: branchField
            visible: dialog.auto
            width: parent.width
            label: L10n.t("stashTargetBranch")
            names: dialog.payload.branches ?? []
        }
        MeridianBanner {
            visible: dialog.kind === "drop"
            width: parent.width
            tone: MeridianBanner.Warning
            message: L10n.t("stashDropWarning")
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.reject() },
        MeridianButton {
            text: dialog.titleText
            variant: dialog.kind === "drop" ? MeridianButton.Danger : MeridianButton.Primary
            disabledReason: dialog.push && dialog.selecting && dialog.selected.length === 0 ? L10n.t("stashSelectFilesReason") : ""
            enabled: dialog.valid
            onClicked: dialog.submit()
        }
    ]
}
