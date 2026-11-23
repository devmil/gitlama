pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Why a file is unmerged: which sides have
// it, how they differ, mode differences, and each index entry's facts.
Flickable {
    id: root

    property var file: null
    readonly property var details: file ? (file.details ?? ({})) : ({})

    implicitHeight: Math.min(GitLamaLayout.conflictDetailsMaxHeight, column.implicitHeight + 2 * Theme.space.s4)
    contentHeight: column.implicitHeight + 2 * Theme.space.s4
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    MeridianWheelScroll { flickable: root }

    function capitalized(name) { return name.charAt(0).toUpperCase() + name.slice(1) }
    function entryText(entry, working) {
        if (!entry || !entry.present)
            return L10n.t("conflictEntryAbsent")
        const facts = L10n.tn("conflictEntryFacts", {
            type: L10n.t("conflictEntry" + root.capitalized(entry.type ?? "unknown")),
            mode: entry.mode ?? "—",
            bytes: entry.bytes === null || entry.bytes === undefined ? "—" : String(entry.bytes),
        })
        if (entry.endings === undefined)
            return facts
        const endings = entry.endings === "none" ? L10n.t("conflictNoLineBreaks")
            : entry.endings === "mixed" ? L10n.t("conflictMixedLineBreaks") : entry.endings
        return facts + "\n" + L10n.tn("conflictFormatFacts", {
            endings: endings,
            finalNewline: L10n.t(entry.finalNewline ? "conflictFinalNewlinePresent" : "conflictFinalNewlineAbsent"),
            bom: L10n.t(entry.bom ? "conflictBomPresent" : "conflictBomAbsent"),
        })
    }

    Column {
        id: column
        x: Theme.space.s4
        y: Theme.space.s4
        width: root.width - 2 * Theme.space.s4
        MeridianText {
            width: parent.width
            role: MeridianText.Label
            text: L10n.t("conflictPresence" + root.capitalized(root.details.presence ?? "unknown"))
        }
        MeridianText {
            width: parent.width
            role: MeridianText.Caption
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: L10n.t({ identical: "conflictContentIdentical", lineEndings: "conflictContentLineEndings",
                           finalNewline: "conflictContentFinalNewline", byteOrderMark: "conflictContentBom",
                           whitespace: "conflictContentWhitespace", content: "conflictContentDifferent",
                           unavailable: "conflictContentUnavailable", missingSide: "conflictContentMissingSide" }[root.details.difference ?? "content"])
        }
        MeridianText {
            visible: root.details.modeDiffers === true
            width: parent.width
            role: MeridianText.Caption
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: L10n.t("conflictModesDiffer")
        }
        MeridianText {
            visible: root.file !== null && root.file.kind === "text" && root.file.markerFree === true
            width: parent.width
            role: MeridianText.Caption
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: L10n.t("conflictNoMarkers")
        }
        MeridianDisclosure {
            width: parent.width
            title: L10n.t("conflictEntryDetailsTitle")
            Column {
                width: parent ? parent.width : 0
                spacing: Theme.space.s3
                MeridianPropertyList {
                    width: parent.width
                    properties: [
                        { label: L10n.t("conflictAncestor"), value: root.entryText(root.details.ancestor) },
                        { label: L10n.t("conflictCurrentEntry"), value: root.entryText(root.details.current) },
                        { label: L10n.t("conflictIncomingEntry"), value: root.entryText(root.details.incoming) },
                        { label: L10n.t("conflictWorkingEntry"), value: root.entryText(root.details.working) },
                    ]
                }
                MeridianText {
                    width: parent.width
                    role: MeridianText.Caption
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    text: L10n.t("conflictPathFacts")
                }
            }
        }
    }
}
