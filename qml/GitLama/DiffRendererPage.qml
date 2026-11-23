pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Meridian

// The Diff renderer settings page (the Dart DiffRendererSettingsCard): what
// a renderer may do, then its identifier, name, program and arguments; the
// core checks the program before it is stored. The state is
// Store.settings.renderer.
Column {
    id: page

    readonly property var renderer: Store.settings ? (Store.settings.renderer ?? ({})) : ({})
    readonly property var card: renderer.card ?? ({})
    readonly property bool busy: card.busy === true
    readonly property bool repository: Store.settings && Store.settings.tools ? Store.settings.tools.repository === true : false

    /// Fills the fields from the stored renderer.
    function reset() {
        idField.text = card.id ?? "plain-text"
        titleField.text = card.title ?? ""
        programField.text = card.executable ?? ""
        argumentsField.text = card.arguments ?? ""
    }

    spacing: Theme.space.s6

    MeridianText {
        width: parent.width
        wrapMode: Text.Wrap
        text: L10n.t("diffRendererContainmentHelp")
    }
    MeridianText {
        visible: !page.repository
        width: parent.width
        wrapMode: Text.Wrap
        text: L10n.t("commandRepositoryRequired")
    }
    Column {
        visible: page.repository
        width: parent.width
        spacing: Theme.space.s6

        MeridianProgressBar {
            visible: page.busy
            width: parent.width
        }
        MeridianBanner {
            visible: !!page.card.failure
            width: parent.width
            tone: MeridianBanner.Error
            message: page.card.failure ? L10n.t(page.card.failure) : ""
        }
        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("diffRendererId") }
            MeridianTextField {
                id: idField
                objectName: "diff-renderer-id"
                width: parent.width
                enabled: !page.busy
                Accessible.name: L10n.t("diffRendererId")
            }
        }
        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("diffRendererName") }
            MeridianTextField {
                id: titleField
                objectName: "diff-renderer-title"
                width: parent.width
                enabled: !page.busy
                Accessible.name: L10n.t("diffRendererName")
            }
        }
        // The program: a path field with a Choose button beside it.
        Row {
            width: parent.width
            spacing: Theme.space.s3
            Column {
                width: parent.width - chooseButton.width - parent.spacing
                spacing: Theme.space.s2
                MeridianText { role: MeridianText.Label; text: L10n.t("integrationExecutable") }
                MeridianTextField {
                    id: programField
                    objectName: "diff-renderer-executable"
                    width: parent.width
                    enabled: !page.busy
                    Accessible.name: L10n.t("integrationExecutable")
                }
            }
            MeridianButton {
                id: chooseButton
                anchors.bottom: parent.bottom
                text: L10n.t("integrationChooseExecutable")
                iconName: "folder-open"
                enabled: !page.busy
                onClicked: programPicker.open()
            }
        }
        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("integrationArguments") }
            MeridianTextArea {
                id: argumentsField
                objectName: "diff-renderer-arguments"
                width: parent.width
                minimumLines: 2
                maximumLines: 4
                enabled: !page.busy
            }
            MeridianText {
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                text: L10n.t("diffRendererArgumentsHelp")
            }
        }
        Row {
            anchors.right: parent.right
            spacing: Theme.space.s4
            MeridianButton {
                text: L10n.t("delete")
                variant: MeridianButton.DangerQuiet
                enabled: !page.busy && page.renderer.configured === true
                onClicked: {
                    Store.settings.diffRenderer("remove", ({}))
                    titleField.text = ""
                    programField.text = ""
                    argumentsField.text = ""
                }
            }
            MeridianButton {
                objectName: "diff-renderer-validate-save"
                text: L10n.t("diffRendererSave")
                variant: MeridianButton.Primary
                enabled: !page.busy
                onClicked: Store.settings.diffRenderer("save", {
                    id: idField.text, title: titleField.text, executable: programField.text, arguments: argumentsField.text,
                })
            }
        }
    }

    FileDialog {
        id: programPicker
        fileMode: FileDialog.OpenFile
        onAccepted: {
            const text = selectedFile.toString()
            programField.text = text.startsWith("file://") ? decodeURIComponent(text.slice(Qt.platform.os === "windows" ? 8 : 7)) : text
        }
    }
}
