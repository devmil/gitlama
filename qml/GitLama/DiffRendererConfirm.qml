pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// What a diff renderer does before it runs or is saved (the Dart
// DiffRendererPreviewContent in a confirmation): one sentence, the program
// and its limits, and both exact command lines behind "Command details".
MeridianConfirm {
    id: confirm

    property int promptId: -1
    property var preview: ({})
    readonly property bool run: preview.run === true
    signal answered(int id, bool value)

    function ask(id, value) {
        promptId = id
        preview = value
        open()
    }

    widthClass: MeridianDialog.Form
    title: run ? L10n.t("diffRendererPreviewTitle") : L10n.t("diffRendererValidatedTitle")
    confirmLabel: run ? L10n.t("diffRendererRun") : L10n.t("diffRendererSave")
    cancelLabel: L10n.t("cancel")
    onConfirmed: { confirm.answered(promptId, true); promptId = -1 }
    onCancelled: { confirm.answered(promptId, false); promptId = -1 }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6
        readonly property var outputFormat: ({ label: L10n.t("diffRendererOutputFormat"), value: confirm.preview.mediaType ?? "", monospace: true })
        MeridianText {
            width: parent.width
            role: MeridianText.Body
            color: Theme.colors.ink
            wrapMode: Text.Wrap
            text: confirm.run ? L10n.t("diffRendererRunSummary") : L10n.t("diffRendererValidatedSummary")
        }
        MeridianPropertyList {
            objectName: "diff-renderer-facts"
            width: parent.width
            properties: {
                const list = []
                if ((confirm.preview.title ?? "").length > 0)
                    list.push({ label: L10n.t("diffRendererName"), value: confirm.preview.title })
                list.push({ label: L10n.t("diffRendererProgram"), value: confirm.preview.executable ?? "", monospace: true })
                if (confirm.run) {
                    list.push({ label: L10n.t("diffRendererInputSize"), value: Labels.byteSize(confirm.preview.inputBytes ?? 0) })
                    list.push({ label: L10n.t("diffRendererOutputLimit"), value: Labels.byteSize(confirm.preview.outputLimitBytes ?? 0) })
                    list.push({ label: L10n.t("diffRendererTimeLimit"), value: L10n.tn("secondsCount", { count: confirm.preview.timeoutSeconds ?? 0 }) })
                } else {
                    list.push(parent.outputFormat)
                }
                return list
            }
        }
        MeridianDisclosure {
            objectName: "diff-renderer-commands"
            width: parent.width
            title: L10n.t("commandDetails")
            onToggled: value => expanded = value
            MeridianPropertyList {
                width: parent ? parent.width : 0
                properties: [
                    { label: L10n.t("diffRendererCapabilityCommand"), value: confirm.preview.capabilityCommand ?? "", monospace: true },
                    { label: L10n.t("diffRendererRenderCommand"), value: confirm.preview.renderCommand ?? "", monospace: true },
                    { label: L10n.t("diffRendererProtocol"), value: confirm.preview.protocol ?? "", monospace: true },
                ].concat(confirm.run ? [{ label: L10n.t("diffRendererOutputFormat"), value: confirm.preview.mediaType ?? "", monospace: true }] : [])
            }
        }
    }
}
