pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Meridian

// The settings: appearance, Git, custom commands, diff view,
// shortcuts, accessibility, diagnostics and licenses. Every change applies
// at once; a refused write shows in the footer.
MeridianSettingsDialog {
    id: dialog

    readonly property var appearance: Store.appearance
    readonly property var page: Store.settings ? (Store.settings.page ?? ({})) : ({})
    readonly property string failure: Store.settings ? Store.settings.failure : ""
    readonly property var repository: page.repository ?? null
    property string recordingCommand: ""
    signal licensesRequested()

    title: L10n.t("settingsTitle")
    closeLabel: L10n.t("close")

    readonly property var categories: [
        ["appearance", "palette", "settingsAppearance", "settingsAppearanceDetail"],
        ["git", "branch", "settingsGit", "settingsGitDetail"],
        ["integrations", "cloud", "settingsIntegrations", "settingsIntegrationsDetail"],
        ["repositoryBinding", "link", "settingsRepositoryBinding", "settingsRepositoryBindingDetail"],
        ["remoteHosts", "server", "settingsRemoteHosts", "settingsRemoteHostsDetail"],
        ["customCommands", "command", "settingsCustomCommands", "settingsCustomCommandsDetail"],
        ["diffView", "side-by-side", "settingsDiffView", "settingsDiffViewDetail"],
        ["diffRenderer", "file-diff", "settingsDiffRenderer", "settingsDiffRendererDetail"],
        ["shortcuts", "shortcuts", "settingsShortcuts", "settingsShortcutsDetail"],
        ["accessibility", "accessibility", "settingsAccessibility", "settingsAccessibilityDetail"],
        ["updates", "download", "settingsUpdates", "settingsUpdatesDetail"],
        ["diagnostics", "activity", "diagnosticsTitle", "diagnosticsDescription"],
        ["licenses", "info", "licensesTitle", "settingsLicensesDetail"],
    ]
    pages: categories.map(c => ({ label: L10n.t(c[2]), icon: c[1], description: L10n.t(c[3]) }))

    function show(category) {
        const index = categories.findIndex(c => c[0] === category)
        customCommands.focusForm = category === "customCommands"
        currentPage = Math.max(0, index)
        if (category === "customCommands")
            customCommands.start()
        if (Store.settings)
            Store.settings.statusAcceleration("read")
        diffRendererPage.reset()
        recordingCommand = ""
        if (Store.settings)
            Store.settings.showFailure("")
        open()
    }
    // Each visit to Custom commands looks for installed tools again.
    property int _shownPage: -1
    onCurrentPageChanged: {
        if (currentPage === _shownPage)
            return
        _shownPage = currentPage
        if (categories[currentPage] && categories[currentPage][0] === "customCommands" && opened)
            customCommands.start()
    }
    onClosed: _shownPage = -1
    function updateAppearance(patch) {
        Store.app.updateAppearance(patch)
        Store.settings.showFailure("")
    }
    function onOff(v) { return L10n.t(v === "on" ? "settingsOn" : "settingsOff") }

    /// The canonical binding (`Ctrl+Shift+P`) of a recorded key, or "" for
    /// a key no shortcut can use.
    function bindingOf(key, modifiers) {
        let name = ""
        if (key >= Qt.Key_A && key <= Qt.Key_Z)
            name = String.fromCharCode(key)
        else if (key >= Qt.Key_0 && key <= Qt.Key_9)
            name = String.fromCharCode(key)
        else if (key >= Qt.Key_F1 && key <= Qt.Key_F24)
            name = "F" + (key - Qt.Key_F1 + 1)
        else {
            switch (key) {
            case Qt.Key_Return: case Qt.Key_Enter: name = "Enter"; break
            case Qt.Key_Space: name = "Space"; break
            case Qt.Key_Tab: name = "Tab"; break
            case Qt.Key_Up: name = "Up"; break
            case Qt.Key_Down: name = "Down"; break
            case Qt.Key_Left: name = "Left"; break
            case Qt.Key_Right: name = "Right"; break
            case Qt.Key_Insert: name = "Insert"; break
            case Qt.Key_Question: name = "?"; break
            case Qt.Key_Comma: name = ","; break
            case Qt.Key_Slash: name = "/"; break
            case Qt.Key_BracketLeft: name = "["; break
            case Qt.Key_BracketRight: name = "]"; break
            default: return ""
            }
        }
        // On macOS Qt reports Command as Control and Control as Meta.
        const control = Store.isMac ? (modifiers & Qt.MetaModifier) : (modifiers & Qt.ControlModifier)
        const command = Store.isMac ? (modifiers & Qt.ControlModifier) : (modifiers & Qt.MetaModifier)
        const parts = []
        if (control) parts.push("Ctrl")
        if (command) parts.push("Cmd")
        if (modifiers & Qt.AltModifier) parts.push("Alt")
        if ((modifiers & Qt.ShiftModifier) && name !== "?") parts.push("Shift")
        parts.push(name)
        return parts.join("+")
    }

    footerShown: failure.length > 0
    footerContent: [
        MeridianText {
            visible: dialog.failure.length > 0
            width: parent ? parent.width : 0
            role: MeridianText.Caption
            color: Theme.colors.danger
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: dialog.failure.length > 0 ? L10n.t(dialog.failure) : ""
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }
    ]

    // Appearance ---------------------------------------------------------------
    MeridianSettingsGroup {
        SettingsChoice {
            width: parent.width
            segmented: true
            label: L10n.t("settingsTheme")
            values: ["system", "light", "dark"]
            value: dialog.appearance.theme
            valueLabel: v => L10n.t(v === "light" ? "settingsThemeLight" : v === "dark" ? "settingsThemeDark" : "settingsFollowSystem")
            onChosen: v => dialog.updateAppearance({ theme: v })
        }
        SettingsChoice {
            width: parent.width
            segmented: true
            label: L10n.t("settingsDensity")
            values: ["compact", "regular", "comfortable"]
            value: dialog.appearance.density
            valueLabel: v => L10n.t(v === "compact" ? "settingsDensityCompact" : v === "comfortable" ? "settingsDensityComfortable" : "settingsDensityRegular")
            onChosen: v => dialog.updateAppearance({ density: v })
        }
        SettingsChoice {
            width: parent.width
            label: L10n.t("settingsDateFormat")
            values: ["relative", "local", "iso"]
            value: dialog.appearance.dateFormat
            valueLabel: v => L10n.t(v === "local" ? "settingsDateLocal" : v === "iso" ? "settingsDateIso" : "settingsDateRelative")
            onChosen: v => dialog.updateAppearance({ dateFormat: v })
        }
        SettingsChoice {
            width: parent.width
            label: L10n.t("settingsAvatars")
            help: L10n.t("avatarGravatarHint")
            values: ["initials", "gravatar"]
            value: dialog.appearance.gravatarEnabled ? "gravatar" : "initials"
            valueLabel: v => L10n.t(v === "gravatar" ? "settingsAvatarsGravatar" : "settingsAvatarsInitials")
            onChosen: v => dialog.updateAppearance({ gravatarEnabled: v === "gravatar" })
        }
        SettingsChoice {
            width: parent.width
            segmented: true
            label: L10n.t("settingsInspectionOpenIn")
            help: L10n.t("settingsInspectionOpenInDetail")
            values: ["pane", "window"]
            value: dialog.appearance.inspectionOpenIn
            valueLabel: v => L10n.t(v === "window" ? "settingsInspectionOpenInWindow" : "settingsInspectionOpenInPane")
            onChosen: v => dialog.updateAppearance({ inspectionOpenIn: v })
        }
        SettingsChoice {
            width: parent.width
            segmented: true
            label: L10n.t("settingsHistoryOtherRefs")
            help: L10n.t("settingsHistoryOtherRefsDetail")
            values: ["on", "off"]
            value: dialog.appearance.historyOtherRefs ? "on" : "off"
            valueLabel: dialog.onOff
            onChosen: v => dialog.updateAppearance({ historyOtherRefs: v === "on" })
        }
    }

    // Git ----------------------------------------------------------------------
    MeridianSettingsGroup {
        SettingsChoice {
            width: parent.width
            segmented: true
            label: L10n.t("settingsAutoFetch")
            values: ["on", "off"]
            value: dialog.page.autoFetch && dialog.page.autoFetch.enabled ? "on" : "off"
            valueLabel: dialog.onOff
            onChosen: v => Store.settings.updateAutoFetch({ enabled: v === "on" })
        }
        SettingsChoice {
            width: parent.width
            label: L10n.t("settingsAutoFetchInterval")
            help: L10n.t("settingsAutoFetchHint")
            values: dialog.page.intervals ?? []
            value: dialog.page.autoFetch ? dialog.page.autoFetch.intervalMinutes : 10
            valueLabel: v => L10n.tn("settingsAutoFetchMinutes", { count: v })
            onChosen: v => Store.settings.updateAutoFetch({ intervalMinutes: v })
        }
        MeridianText {
            visible: dialog.repository !== null
            width: parent.width
            text: dialog.repository ? L10n.tn("settingsActiveRepository", { name: dialog.repository.label }) : ""
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        SettingsChoice {
            visible: dialog.repository !== null
            width: parent.width
            label: L10n.t("settingsRepositoryAutoFetch")
            values: ["default", "on", "off"]
            value: dialog.repository ? dialog.repository.autoFetch : "default"
            valueLabel: v => v === "default" ? L10n.t("settingsFollowApplication") : dialog.onOff(v)
            onChosen: v => Store.settings.setRepositoryAutoFetch(v)
        }
        MeridianButton {
            id: resetRepository
            visible: dialog.repository !== null
            variant: MeridianButton.Secondary
            text: L10n.t("settingsResetRepositoryAction")
            onClicked: resetConfirm.open()
        }
        MeridianConfirm {
            id: resetConfirm
            title: L10n.t("settingsResetRepositoryTitle")
            description: dialog.repository ? L10n.tn("settingsResetRepositoryConfirmation", { name: dialog.repository.label }) : ""
            confirmLabel: L10n.t("settingsResetRepositoryAction")
            cancelLabel: L10n.t("cancel")
            destructive: true
            onConfirmed: Store.settings.resetRepository()
            onClosed: resetRepository.forceActiveFocus()
        }
        StatusAccelerationSettings {
            visible: dialog.repository !== null
            width: parent.width
        }
        MeridianText {
            visible: dialog.repository === null
            width: parent.width
            text: L10n.t("settingsNoActiveRepository")
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
    }

    // Hosting accounts ---------------------------------------------------------
    MeridianSettingsGroup {
        HostingSettings {
            width: parent.width
            section: "accounts"
        }
    }

    // Repository binding -------------------------------------------------------
    MeridianSettingsGroup {
        HostingSettings {
            width: parent.width
            section: "binding"
            onOpenAccounts: dialog.currentPage = dialog.categories.findIndex(c => c[0] === "integrations")
        }
    }

    // Remote hosts -------------------------------------------------------------
    MeridianSettingsGroup {
        RemoteHostsSettings {
            width: parent.width
        }
    }

    // Custom commands ----------------------------------------------------------
    MeridianSettingsGroup {
        CustomCommandsPage {
            id: customCommands
            width: parent.width
        }
    }

    // Diff view ----------------------------------------------------------------
    MeridianSettingsGroup {
        SettingsChoice {
            width: parent.width
            segmented: true
            label: L10n.t("settingsDiffLayout")
            values: ["unified", "sideBySide"]
            value: dialog.appearance.diffLayout
            valueLabel: v => L10n.t(v === "sideBySide" ? "settingsDiffSideBySide" : "settingsDiffUnified")
            onChosen: v => dialog.updateAppearance({ diffLayout: v })
        }
        SettingsChoice {
            width: parent.width
            segmented: true
            label: L10n.t("settingsDiffWrap")
            values: ["wrap", "scroll"]
            value: dialog.appearance.diffWrap ? "wrap" : "scroll"
            valueLabel: v => L10n.t(v === "wrap" ? "settingsDiffWrapOn" : "settingsDiffWrapOff")
            onChosen: v => dialog.updateAppearance({ diffWrap: v === "wrap" })
        }
        SettingsChoice {
            width: parent.width
            label: L10n.t("settingsDiffWhitespace")
            values: ["preserve", "ignoreAll", "ignoreAmount", "ignoreEndOfLine"]
            value: dialog.appearance.diffWhitespace
            valueLabel: v => L10n.t({ preserve: "settingsDiffWhitespacePreserve", ignoreAll: "settingsDiffWhitespaceIgnoreAll",
                                      ignoreAmount: "settingsDiffWhitespaceIgnoreAmount",
                                      ignoreEndOfLine: "settingsDiffWhitespaceIgnoreEndOfLine" }[v])
            onChosen: v => dialog.updateAppearance({ diffWhitespace: v })
        }
        SettingsChoice {
            width: parent.width
            label: L10n.t("diffContextLines")
            values: {
                const choices = (dialog.page.contextChoices ?? [0, 3, 6, 10]).slice()
                const current = dialog.appearance.diffContextLines ?? 3
                if (choices.indexOf(current) < 0)
                    choices.push(current)
                return choices.sort((a, b) => a - b)
            }
            value: dialog.appearance.diffContextLines
            valueLabel: v => L10n.tn("diffContextValue", { count: v })
            onChosen: v => dialog.updateAppearance({ diffContextLines: v })
        }
        SettingsChoice {
            width: parent.width
            segmented: true
            label: L10n.t("settingsDiffIndicators")
            values: ["on", "off"]
            value: dialog.appearance.diffIndicators ? "on" : "off"
            valueLabel: dialog.onOff
            onChosen: v => dialog.updateAppearance({ diffIndicators: v === "on" })
        }
        SettingsChoice {
            width: parent.width
            segmented: true
            label: L10n.t("settingsDiffMinimap")
            values: ["on", "off"]
            value: dialog.appearance.diffMinimap ? "on" : "off"
            valueLabel: dialog.onOff
            onChosen: v => dialog.updateAppearance({ diffMinimap: v === "on" })
        }
    }

    // Diff renderer --------------------------------------------------------------
    MeridianSettingsGroup {
        DiffRendererPage {
            id: diffRendererPage
            width: parent.width
        }
    }

    // Shortcuts ----------------------------------------------------------------
    MeridianSettingsGroup {
        MeridianButton {
            variant: MeridianButton.Secondary
            text: L10n.t("settingsShortcutReset")
            onClicked: Store.settings.resetShortcuts()
        }
        Repeater {
            model: Commands.registry
            delegate: Item {
                id: shortcutRow
                required property var modelData
                readonly property string commandId: modelData.id
                readonly property var shortcut: Commands.shortcuts[commandId]
                width: parent ? parent.width : 0
                height: Math.max(rowLabel.height, field.height)
                MeridianText {
                    id: rowLabel
                    width: parent.width - field.width - Theme.space.s5
                    anchors.verticalCenter: parent.verticalCenter
                    text: Commands.label(shortcutRow.commandId)
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
                MeridianShortcutField {
                    id: field
                    x: parent.width - width
                    width: GitLamaLayout.shortcutFieldWidth
                    showLabel: false
                    label: Commands.label(shortcutRow.commandId)
                    emptyLabel: L10n.t("settingsShortcutUnbound")
                    recordingLabel: L10n.t("settingsShortcutRecording")
                    preparingLabel: L10n.t("settingsShortcutRecording")
                    clearLabel: L10n.t("settingsShortcutClear")
                    keys: shortcutRow.shortcut && shortcutRow.shortcut.canonical
                          ? Commands.platformShortcutKeys(shortcutRow.shortcut.canonical) : []
                    recording: dialog.recordingCommand === shortcutRow.commandId
                    onRecordRequested: dialog.recordingCommand = shortcutRow.commandId
                    onCancelRecording: if (dialog.recordingCommand === shortcutRow.commandId) dialog.recordingCommand = ""
                    onRecorded: (key, modifiers) => {
                        dialog.recordingCommand = ""
                        const binding = dialog.bindingOf(key, modifiers)
                        if (binding.length === 0)
                            Store.settings.showFailure("settingsShortcutInvalid")
                        else
                            Store.settings.setShortcut(shortcutRow.commandId, binding)
                    }
                    onCleared: Store.settings.setShortcut(shortcutRow.commandId, "")
                }
            }
        }
    }

    // Accessibility ------------------------------------------------------------
    MeridianSettingsGroup {
        SettingsChoice {
            width: parent.width
            label: L10n.t("settingsMotion")
            values: ["followSystem", "reduce", "full"]
            value: dialog.appearance.reduceMotion
            valueLabel: v => L10n.t(v === "reduce" ? "settingsMotionReduce" : v === "full" ? "settingsMotionFull" : "settingsFollowSystem")
            onChosen: v => dialog.updateAppearance({ reduceMotion: v })
        }
    }

    // Updates ------------------------------------------------------------------
    UpdatesPage {}

    // Diagnostics --------------------------------------------------------------
    // devmil_logging's DiagnosticControls: one column, space-4 apart.
    Column {
        id: diagnostics
        spacing: Theme.space.s4
        property bool detailed: false
        property string preview: ""
        property string status: ""
        function refresh() { detailed = Store.settings ? Store.settings.diagnosticsDetailed() : false }
        onVisibleChanged: if (visible) refresh()

        MeridianText {
            width: parent.width
            text: L10n.t("diagnosticsTitle")
        }
        MeridianText {
            width: parent.width
            text: L10n.t("diagnosticsDescription")
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        Flow {
            width: parent.width
            spacing: Theme.space.s4
            MeridianButton {
                text: L10n.t(diagnostics.detailed ? "diagnosticsDisable" : "diagnosticsEnable")
                onClicked: {
                    Store.settings.setDiagnosticsDetailed(!diagnostics.detailed)
                    diagnostics.refresh()
                }
            }
            MeridianButton {
                text: L10n.t("diagnosticsClear")
                onClicked: {
                    Store.settings.clearDiagnostics()
                    diagnostics.preview = ""
                    diagnostics.status = ""
                }
            }
            MeridianButton {
                text: L10n.t("diagnosticsPreview")
                onClicked: {
                    diagnostics.preview = Store.settings.diagnosticsPreview(Store.platform.version ?? "unknown")
                    diagnostics.status = ""
                }
            }
        }
        MeridianSurface {
            visible: diagnostics.preview.length > 0
            width: parent.width
            height: Theme.size.toolbar * 6
            color: Theme.colors.paneAlt
            radius: Theme.radius.md
            Flickable {
                id: previewScroll
                anchors.fill: parent
                anchors.margins: Theme.space.s3
                clip: true
                contentHeight: previewText.height
                boundsBehavior: Flickable.StopAtBounds
                MeridianWheelScroll { flickable: previewScroll }
                MeridianSelectableText {
                    id: previewText
                    width: previewScroll.width
                    role: MeridianText.CodeSm
                    text: diagnostics.preview
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
        Flow {
            visible: diagnostics.preview.length > 0
            width: parent.width
            spacing: Theme.space.s4
            MeridianButton {
                text: L10n.t("diagnosticsSave")
                onClicked: saveDialog.open()
            }
            // The platform's share sheet: macOS and Windows, as the text stays in memory.
            MeridianButton {
                id: shareButton
                visible: Store.hooks !== null && Store.hooks.canShare()
                text: L10n.t("diagnosticsShare")
                onClicked: {
                    const origin = shareButton.mapToItem(null, 0, 0)
                    const shown = Store.hooks.shareText(diagnostics.preview, L10n.t("diagnosticsTitle"),
                                                        origin.x, origin.y, shareButton.width, shareButton.height)
                    diagnostics.status = shown ? "" : L10n.t("diagnosticsFailed")
                }
            }
            MeridianButton {
                text: L10n.t("diagnosticsCancel")
                onClicked: { diagnostics.preview = ""; diagnostics.status = "" }
            }
        }
        MeridianText {
            visible: diagnostics.status.length > 0
            width: parent.width
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: diagnostics.status
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }
        FileDialog {
            id: saveDialog
            fileMode: FileDialog.SaveFile
            onVisibleChanged: if (visible) selectedFile = currentFolder + "/gitlama-diagnostics.txt"
            nameFilters: ["Text (*.txt)"]
            onAccepted: diagnostics.status = L10n.t(Store.settings.saveDiagnostics(selectedFile.toString(), diagnostics.preview)
                                                     ? "diagnosticsSaved" : "diagnosticsFailed")
        }
    }

    // Licenses -----------------------------------------------------------------
    MeridianSettingsGroup {
        MeridianButton {
            variant: MeridianButton.Secondary
            text: L10n.t("settingsOpenLicenses")
            onClicked: {
                dialog.close()
                dialog.licensesRequested()
            }
        }
    }
}
