pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The commit editor (the Dart CommitEditor in a GitLamaComposer): subject
// with its length counter, description, Amend, the staged count and the
// options menu, then Commit & Push and Commit. A failed commit shows why,
// with retries without hooks or unsigned. The draft is kept per worktree.
Rectangle {
    id: editor

    readonly property var commitState: Store.commit ? (Store.commit.state ?? ({})) : ({})
    readonly property var changes: Store.changes ? (Store.changes.state ?? ({})) : ({})
    readonly property var active: Store.workspace ? Store.workspace.active : null
    readonly property bool busy: commitState.busy === true
    readonly property int stagedCount: changes.stagedTotal ?? 0
    property bool amend: false
    property bool skipHooks: false
    property bool signOff: false
    property bool attempted: false
    readonly property string subjectText: subjectField.text
    readonly property bool empty: subjectText.trim().length === 0
    readonly property bool trailingSpace: subjectText.length > 0 && subjectText.replace(/\s+$/, "") !== subjectText
    readonly property string subjectError: empty && attempted ? L10n.t("commitEmptySubject")
        : trailingSpace ? L10n.t("commitTrailingWhitespace") : ""
    readonly property string commitReason: {
        const reason = Commands.reason(amend ? "commitAmend" : "commitCreate", Store.actions ? Store.actions.availability : ({}))
        if (reason === "contextRequired" && !amend)
            return L10n.t("commitNothingStaged")
        if (reason.length > 0)
            return Commands.reasonText(reason)
        return !amend && stagedCount === 0 ? L10n.t("commitNothingStaged") : ""
    }
    readonly property bool canCommit: !busy && !empty && commitReason.length === 0
    readonly property var failure: commitState.failure ?? null

    signal command(string id, var options)

    color: Theme.colors.paneAlt
    implicitHeight: content.implicitHeight + 2 * Theme.space.s5

    Rectangle { width: parent.width; height: Metrics.hairline; color: Theme.colors.line }

    // The draft follows the active worktree.
    Connections {
        target: Store.commit
        function onDraftChanged() { editor.loadDraft() }
        function onCommitted(push) {
            subjectField.text = ""
            descriptionField.text = ""
            editor.amend = false
            editor.attempted = false
            if (push)
                editor.command("push", ({}))
        }
    }
    function loadDraft() {
        const draft = Store.commit ? Store.commit.draft : null
        _loading = true
        subjectField.text = draft ? (draft.subject ?? "") : ""
        descriptionField.text = draft ? (draft.description ?? "") : ""
        _loading = false
        amend = false
        attempted = false
    }
    property bool _loading: false
    property alias subject: subjectField
    Component.onCompleted: loadDraft()
    Timer {
        id: draftTimer
        interval: 300
        onTriggered: Store.commit.updateDraft(subjectField.text, descriptionField.text)
    }
    function draftEdited() {
        if (!_loading)
            draftTimer.restart()
    }

    function submit(push, retry) {
        if (busy)
            return
        if (commitReason.length > 0) {
            Notifications.show(commitReason, false)
            return
        }
        if (empty) {
            attempted = true
            return
        }
        draftTimer.stop()
        Store.commit.commit({
            subject: subjectField.text,
            description: descriptionField.text,
            coauthors: [],
            author: "",
            amend: amend,
            skipHooks: skipHooks || retry === "skipHooks",
            signOff: signOff,
        }, push, retry ?? "")
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        anchors.topMargin: Metrics.hairline
        contentWidth: width
        contentHeight: content.implicitHeight + 2 * Theme.space.s5
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        MeridianWheelScroll { flickable: scroller }

        Column {
            id: content
            x: Theme.space.s5
            y: Theme.space.s5
            width: scroller.width - 2 * Theme.space.s5
            spacing: Theme.space.s4

            // A failed commit and its output.
            Column {
                visible: editor.failure !== null || editor.commitState.outcomeUnknown === true
                width: parent.width
                spacing: Theme.space.s3
                MeridianBanner {
                    objectName: "commit-failure-panel"
                    width: parent.width
                    tone: MeridianBanner.Error
                    title: editor.commitState.outcomeUnknown === true ? ""
                        : !editor.failure ? ""
                        : (editor.failure.kind === "hook" ? L10n.t("commitHookFailure")
                           : editor.failure.kind === "signing" ? L10n.t("commitSigningFailure") : L10n.t("commitOtherFailure"))
                          + (editor.failure.exitCode !== null && editor.failure.exitCode !== undefined
                             ? " · " + L10n.tn("commitFailureExitCode", { code: editor.failure.exitCode }) : "")
                    message: editor.commitState.outcomeUnknown === true ? L10n.t("remoteOutcomeUnknownCommit") : L10n.t("commitFailed")
                    MeridianButton {
                        visible: editor.failure !== null
                        text: L10n.t("commitRetry")
                        controlSize: MeridianButton.Small
                        enabled: !editor.busy
                        onClicked: editor.submit(editor.failure.push === true, "")
                    }
                    MeridianButton {
                        visible: editor.failure !== null && editor.failure.kind === "hook"
                        text: L10n.t("commitSkipHooks")
                        controlSize: MeridianButton.Small
                        variant: MeridianButton.DangerQuiet
                        enabled: !editor.busy
                        onClicked: editor.submit(editor.failure.push === true, "skipHooks")
                    }
                    MeridianButton {
                        visible: editor.failure !== null && editor.failure.kind === "signing"
                        text: L10n.t("commitSigningDisabled")
                        controlSize: MeridianButton.Small
                        variant: MeridianButton.DangerQuiet
                        enabled: !editor.busy
                        onClicked: editor.submit(editor.failure.push === true, "unsigned")
                    }
                }
                Rectangle {
                    visible: editor.failure !== null && (editor.failure.output ?? "").length > 0
                    width: parent.width
                    height: Math.min(GitLamaLayout.commitFailureOutputMaxHeight, output.implicitHeight + 2 * Theme.space.s3)
                    radius: Theme.radius.sm
                    color: Theme.colors.paneAlt
                    border.color: Theme.colors.line
                    clip: true
                    MeridianSelectableText {
                        id: output
                        x: Theme.space.s3
                        y: Theme.space.s3
                        width: parent.width - 2 * Theme.space.s3
                        role: MeridianText.CodeSm
                        text: editor.failure ? (editor.failure.output ?? "") : ""
                        wrapMode: Text.Wrap
                    }
                }
            }

            MeridianTextField {
                id: subjectField
                objectName: "commit-subject-field"
                width: parent.width
                height: GitLamaLayout.composerSubjectHeight
                font: Theme.type.bodyStrong
                placeholderText: L10n.t("commitSubject")
                Accessible.name: L10n.t("commitSubject")
                enabled: !editor.busy
                error: editor.subjectError.length > 0
                onTextChanged: editor.draftEdited()
                onAccepted: descriptionField.forceActiveFocus()
                trailingContent: [
                    MeridianText {
                        objectName: "commit-subject-counter"
                        readonly property int length: [...subjectField.text].length
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        role: MeridianText.Caption
                        tabular: true
                        text: length + "/" + GitLamaLayout.subjectGuide
                        color: length > GitLamaLayout.subjectLimit ? Theme.colors.danger
                            : length > GitLamaLayout.subjectGuide ? Theme.colors.warning : Theme.colors.inkMuted
                        Behavior on color { ColorAnimation { duration: Motion.select } }
                    },
                    MeridianIcon {
                        visible: editor.subjectError.length > 0
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        name: "circle-x"
                        color: Theme.colors.danger
                        HoverHandler { id: errorHover }
                        MeridianTooltip { shown: errorHover.hovered; text: editor.subjectError }
                    }
                ]
            }
            MeridianTextArea {
                id: descriptionField
                objectName: "commit-description-field"
                width: parent.width
                minimumLines: GitLamaLayout.composerDescriptionMinLines
                maximumLines: GitLamaLayout.composerDescriptionMaxLines
                placeholderText: L10n.t("commitDescription")
                Accessible.name: L10n.t("commitDescription")
                enabled: !editor.busy
                onTextChanged: editor.draftEdited()
            }

            // Amend, the staged count and the options.
            Item {
                width: parent.width
                height: Math.max(amendBox.implicitHeight, optionsButton.height)
                MeridianCheckbox {
                    id: amendBox
                    objectName: "commit-amend"
                    anchors.verticalCenter: parent.verticalCenter
                    text: L10n.t("commitAmend")
                    checked: editor.amend
                    enabled: !editor.busy
                    onToggled: {
                        editor.amend = checked
                        if (checked && subjectField.text.length === 0 && descriptionField.text.length === 0) {
                            Store.commit.loadTools()
                            editor._fillAmend = true
                        }
                    }
                }
                MeridianText {
                    x: amendBox.width + Theme.space.s4
                    anchors.verticalCenter: parent.verticalCenter
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: L10n.tn("changesStagedFilesCount", { count: editor.stagedCount })
                }
                MeridianIconButton {
                    id: optionsButton
                    objectName: "commit-options-menu"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: L10n.t("commitOptions")
                    iconName: "more"
                    enabled: !editor.busy
                    onClicked: {
                        Store.commit.loadTools()
                        optionsMenu.items = [
                            { title: L10n.t("commitTemplate"), value: "template", enabled: !!editor.commitState.template },
                            { title: L10n.t("commitSkipHooks"), value: "skipHooks", checked: editor.skipHooks },
                            { title: L10n.t("commitSignOff"), value: "signOff", checked: editor.signOff },
                        ]
                        optionsMenu.show(optionsButton, 0, optionsButton.height)
                    }
                }
                CommandMenu {
                    id: optionsMenu
                    onSelected: value => {
                        if (value === "template" && editor.commitState.template) {
                            const template = editor.commitState.template
                            const lines = template.split("\n")
                            subjectField.text = lines[0] ?? ""
                            descriptionField.text = lines.slice(1).join("\n").trim()
                        } else if (value === "skipHooks") {
                            editor.skipHooks = !editor.skipHooks
                        } else if (value === "signOff") {
                            editor.signOff = !editor.signOff
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: Theme.space.s4
                MeridianButton {
                    objectName: "commit-push-menu"
                    width: (parent.width - parent.spacing) / 2
                    text: L10n.t("commitAndPush")
                    controlSize: MeridianButton.Small
                    variant: MeridianButton.Secondary
                    enabled: editor.canCommit && Commands.reason("push", Store.actions ? Store.actions.availability : ({})) === ""
                    disabledReason: editor.canCommit ? "" : editor.commitReason.length > 0 ? editor.commitReason : L10n.t("commitEmptySubject")
                    onClicked: editor.submit(true)
                }
                MeridianButton {
                    readonly property string branch: editor.active && editor.active.branch ? editor.active.branch : ""
                    readonly property string shortBranch: [...branch].length > 12 ? [...branch].slice(0, 11).join("") + "…" : branch
                    width: (parent.width - parent.spacing) / 2
                    text: editor.amend && editor.active && editor.active.headObjectId
                          ? L10n.tn("commitAmendHash", { hash: editor.active.headObjectId.substring(0, 8) })
                          : shortBranch.length === 0 ? L10n.t("commitAction") : L10n.tn("commitToBranch", { branch: shortBranch })
                    controlSize: MeridianButton.Small
                    variant: MeridianButton.Primary
                    loading: editor.busy
                    success: editor.commitState.succeeded === true
                    enabled: editor.canCommit
                    disabledReason: editor.commitReason
                    onClicked: editor.submit(false)
                }
            }
        }
    }

    // Amend fills the editor with the commit being amended.
    property bool _fillAmend: false
    onCommitStateChanged: {
        if (!_fillAmend || !commitState.recent || !active)
            return
        const message = commitState.recent.find(entry => entry.objectId === active.headObjectId)
        if (!message)
            return
        _fillAmend = false
        subjectField.text = message.subject
        descriptionField.text = message.description
    }

    // Ctrl/Cmd+Enter commits from either field.
    Shortcut {
        sequences: [Commands.sequence("commitCreate")]
        enabled: subjectField.activeFocus || descriptionField.textArea.activeFocus
        onActivated: editor.submit(false)
    }
}
