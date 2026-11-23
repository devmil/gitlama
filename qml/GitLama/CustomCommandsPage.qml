pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Meridian

// The Custom commands settings page: tools found on this computer, the configured tools, and a form
// whose tool the core validates before it is stored. Every run previews its
// command first. The state is Store.settings.tools.
Column {
    id: page

    /// Opened from "Add integration": the form's name field takes focus.
    property bool focusForm: false
    readonly property var tools: Store.settings ? (Store.settings.tools ?? ({})) : ({})
    readonly property bool busy: tools.busy === true
    readonly property var kinds: ["editor", "terminal", "fileManager", "browser", "diffTool", "mergeTool", "custom"]
    property string kind: "custom"
    property bool explicitShell: false
    property bool wait: true
    property bool confirmation: true
    property int seenSaved: -1

    function act(action, options) { Store.settings.tool(action, options ?? ({})) }
    function save() {
        act("save", {
            id: nameField.text, kind: kind, executable: executableField.text, arguments: argumentsField.text,
            explicitShell: explicitShell, wait: wait, confirmation: confirmation, timeout: timeoutField.text,
        })
    }
    function start() {
        act("open")
        if (focusForm)
            Qt.callLater(() => nameField.forceActiveFocus())
    }
    onToolsChanged: {
        // A stored tool clears the form.
        const saved = tools.saved ?? 0
        if (seenSaved >= 0 && saved !== seenSaved) {
            nameField.text = ""
            executableField.text = ""
            argumentsField.text = ""
        }
        seenSaved = saved
    }

    spacing: Theme.space.s6

    MeridianText {
        visible: page.tools.repository !== true
        width: parent.width
        wrapMode: Text.Wrap
        text: L10n.t("commandRepositoryRequired")
    }
    MeridianProgressBar {
        visible: page.tools.repository === true && page.busy
        width: parent.width
    }
    MeridianBanner {
        visible: page.tools.repository === true && !!page.tools.failure
        width: parent.width
        tone: MeridianBanner.Error
        message: page.tools.failure ? L10n.t(page.tools.failure) : ""
    }

    Column {
        visible: page.tools.repository === true
        width: parent.width
        spacing: Theme.space.s8

        // Discovered tools.
        Column {
            width: parent.width
            spacing: Theme.space.s4
            MeridianText { role: MeridianText.BodyStrong; color: Theme.colors.ink; text: L10n.t("integrationDiscovered"); Accessible.role: Accessible.Heading }
            MeridianText {
                visible: (page.tools.discovered ?? []).length === 0
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: L10n.t("integrationDiscoveredEmpty")
            }
            ListWell {
                objectName: "integration-discovered"
                visible: (page.tools.discovered ?? []).length > 0
                width: parent.width
                height: visible ? implicitHeight : 0
                model: page.tools.discovered ?? []
                delegate: MeridianListRow {
                    id: discoveredRow
                    required property var modelData
                    required property int index
                    width: ListView.view ? ListView.view.width : 0
                    text: Labels.integrationKind(modelData.kind)
                    subtitle: modelData.id
                    trailing: Component {
                        MeridianButton {
                            text: L10n.t("integrationRun")
                            variant: MeridianButton.Quiet
                            controlSize: MeridianButton.Small
                            enabled: !page.busy
                            onClicked: page.act("runDiscovered", { index: discoveredRow.index })
                        }
                    }
                }
            }
        }

        // Configured tools.
        Column {
            width: parent.width
            spacing: Theme.space.s4
            MeridianText { role: MeridianText.BodyStrong; color: Theme.colors.ink; text: L10n.t("integrationConfigured"); Accessible.role: Accessible.Heading }
            MeridianText {
                visible: (page.tools.configured ?? []).length === 0
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: L10n.t("integrationConfiguredEmpty")
            }
            ListWell {
                objectName: "integration-configured"
                visible: (page.tools.configured ?? []).length > 0
                width: parent.width
                height: visible ? implicitHeight : 0
                model: page.tools.configured ?? []
                delegate: MeridianListRow {
                    id: configuredRow
                    required property var modelData
                    width: ListView.view ? ListView.view.width : 0
                    text: modelData.id
                    subtitle: Labels.integrationKind(modelData.kind)
                    trailing: Component {
                        Row {
                            spacing: Theme.space.s2
                            MeridianButton {
                                objectName: "integration-run-" + configuredRow.modelData.id
                                text: L10n.t("integrationRun")
                                variant: MeridianButton.Quiet
                                controlSize: MeridianButton.Small
                                enabled: !page.busy
                                onClicked: page.act("run", { id: configuredRow.modelData.id })
                            }
                            MeridianButton {
                                text: L10n.t("delete")
                                variant: MeridianButton.DangerQuiet
                                controlSize: MeridianButton.Small
                                enabled: !page.busy
                                onClicked: page.act("remove", { id: configuredRow.modelData.id })
                            }
                        }
                    }
                }
            }
        }

        // A new tool.
        Column {
            width: parent.width
            spacing: Theme.space.s4
            MeridianText { role: MeridianText.BodyStrong; color: Theme.colors.ink; text: L10n.t("integrationConfigure"); Accessible.role: Accessible.Heading }
            Column {
                width: parent.width
                spacing: Theme.space.s6
                MeridianSelect {
                    width: parent.width
                    label: L10n.t("integrationKind")
                    showLabel: true
                    values: page.kinds
                    value: page.kind
                    valueLabel: kind => Labels.integrationKind(kind)
                    enabled: !page.busy
                    onActivated: value => {
                        page.kind = value
                        if (value === "custom")
                            page.wait = true
                    }
                }
                Column {
                    width: parent.width
                    spacing: Theme.space.s2
                    MeridianText { role: MeridianText.Label; text: L10n.t("integrationName") }
                    MeridianTextField {
                        id: nameField
                        objectName: "integration-id"
                        width: parent.width
                        enabled: !page.busy
                        Accessible.name: L10n.t("integrationName")
                    }
                    MeridianText {
                        width: parent.width
                        role: MeridianText.Caption
                        color: Theme.colors.inkMuted
                        wrapMode: Text.Wrap
                        text: L10n.t("integrationNameHelp")
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
                            id: executableField
                            objectName: "integration-executable"
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
                        width: parent.width
                        minimumLines: 2
                        maximumLines: 5
                        enabled: !page.busy
                    }
                    MeridianText {
                        width: parent.width
                        role: MeridianText.Caption
                        color: Theme.colors.inkMuted
                        wrapMode: Text.Wrap
                        text: L10n.t("integrationArgumentsHelp")
                    }
                }
                Column {
                    width: parent.width
                    spacing: Theme.space.s4
                    MeridianCheckbox {
                        width: parent.width
                        text: L10n.t("integrationExplicitShell")
                        description: L10n.t("integrationExplicitShellHelp")
                        checked: page.explicitShell
                        enabled: !page.busy
                        onToggled: page.explicitShell = checked
                    }
                    MeridianCheckbox {
                        width: parent.width
                        text: L10n.t("integrationConfirm")
                        checked: page.confirmation
                        enabled: !page.busy
                        onToggled: page.confirmation = checked
                    }
                    MeridianCheckbox {
                        width: parent.width
                        text: L10n.t("integrationWait")
                        description: L10n.t("integrationWaitHelp")
                        checked: page.wait
                        enabled: page.kind !== "custom" && !page.busy
                        onToggled: page.wait = checked
                    }
                }
                Column {
                    width: GitLamaLayout.shortFieldWidth
                    spacing: Theme.space.s2
                    MeridianText { role: MeridianText.Label; text: L10n.t("integrationTimeout") }
                    MeridianTextField {
                        id: timeoutField
                        width: parent.width
                        text: "30"
                        enabled: !page.busy
                        inputMethodHints: Qt.ImhDigitsOnly
                        Accessible.name: L10n.t("integrationTimeout")
                    }
                }
                Item {
                    width: parent.width
                    height: saveButton.implicitHeight
                    MeridianButton {
                        id: saveButton
                        objectName: "integration-save"
                        anchors.right: parent.right
                        text: L10n.t("integrationValidateSave")
                        variant: MeridianButton.Primary
                        enabled: !page.busy
                        onClicked: page.save()
                    }
                }
            }
        }
    }

    FileDialog {
        id: programPicker
        fileMode: FileDialog.OpenFile
        onAccepted: {
            const text = selectedFile.toString()
            executableField.text = text.startsWith("file://") ? decodeURIComponent(text.slice(Qt.platform.os === "windows" ? 8 : 7)) : text
        }
    }
}
