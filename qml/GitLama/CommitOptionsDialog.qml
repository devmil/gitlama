pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The commit editor's options: co-authors,
// an author override, signing, sign-off, skipping hooks and spellcheck,
// then the message tools: the template, a fixup or squash message for the
// commit the staged change fixes, and recent messages. Options apply as
// they change; Enter closes the dialog.
MeridianDialog {
    id: dialog

    /// The CommitEditor whose options these are.
    required property var commitEditor
    readonly property bool busy: commitEditor.busy
    readonly property var recent: commitEditor.commitState.recent ?? []

    widthClass: MeridianDialog.Form
    title: L10n.t("commitOptions")
    closeLabel: L10n.t("close")
    onSubmitted: close()
    onOpened: Store.commit.loadTools()

    Column {
        objectName: "commit-options-content"
        width: parent ? parent.width : 0
        spacing: Theme.space.s6

        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("commitCoauthors") }
            MeridianTextField {
                id: coauthorsField
                width: parent.width
                enabled: !dialog.busy
                text: dialog.commitEditor.coauthors
                onTextEdited: dialog.commitEditor.coauthors = text
                Accessible.name: L10n.t("commitCoauthors")
            }
        }
        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("commitAuthor") }
            MeridianTextField {
                width: parent.width
                enabled: !dialog.busy
                text: dialog.commitEditor.author
                onTextEdited: dialog.commitEditor.author = text
                Accessible.name: L10n.t("commitAuthor")
            }
        }
        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("commitSigning") }
            MeridianSelect {
                objectName: "commit-options-signing"
                fixedWidth: parent.width
                enabled: !dialog.busy
                label: L10n.t("commitSigning")
                values: ["useGitConfiguration", "require", "disable"]
                value: dialog.commitEditor.signing
                valueLabel: value => value === "require" ? L10n.t("commitSigningRequired")
                    : value === "disable" ? L10n.t("commitSigningDisabled") : L10n.t("commitSigningGit")
                onActivated: value => dialog.commitEditor.signing = value
            }
        }
        Column {
            width: parent.width
            spacing: Theme.space.s4
            MeridianCheckbox {
                text: L10n.t("commitSignOff")
                enabled: !dialog.busy
                checked: dialog.commitEditor.signOff
                onToggled: dialog.commitEditor.signOff = checked
            }
            MeridianCheckbox {
                text: L10n.t("commitSkipHooks")
                enabled: !dialog.busy
                checked: dialog.commitEditor.skipHooks
                onToggled: dialog.commitEditor.skipHooks = checked
            }
            // Qt Quick has no platform spellcheck service: the option stays off.
            MeridianCheckbox {
                text: L10n.t("commitSpellcheck")
                enabled: false
                checked: false
            }
        }
        Flow {
            objectName: "commit-options-message-tools"
            width: parent.width
            spacing: Theme.space.s3
            MeridianButton {
                text: L10n.t("commitTemplate")
                enabled: !dialog.busy && !!dialog.commitEditor.commitState.template
                onClicked: dialog.commitEditor.applyTemplate()
            }
            MeridianButton {
                id: fixupButton
                text: L10n.t("fixupSuggestionAction")
                trailingIconName: "chevron-down"
                enabled: !dialog.busy
                onClicked: {
                    fixupMenu.items = [
                        { title: L10n.t("fixupSuggestionFixup"), value: "fixup" },
                        { title: L10n.t("fixupSuggestionSquash"), value: "squash" }]
                    fixupMenu.show(fixupButton, 0, fixupButton.height)
                }
            }
            MeridianButton {
                id: recentButton
                text: L10n.t("commitRecent")
                trailingIconName: "chevron-down"
                enabled: !dialog.busy && dialog.recent.length > 0
                onClicked: {
                    recentMenu.items = dialog.recent.map((message, index) => ({ title: message.subject, value: index }))
                    recentMenu.show(recentButton, 0, recentButton.height)
                }
            }
        }
    }

    CommandMenu {
        id: fixupMenu
        onSelected: value => dialog.commitEditor.suggestFixup(value === "squash")
    }
    CommandMenu {
        id: recentMenu
        onSelected: value => {
            const message = dialog.recent[value]
            if (message)
                dialog.commitEditor.applyMessage(message.subject, message.description)
        }
    }
}
