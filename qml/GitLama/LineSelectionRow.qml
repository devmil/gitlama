pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// One row of a diff in which lines are picked (the Dart
// DiffLineSelectionRow): styled like the diff view (code type, line-number
// gutters, added and removed fills) with a leading checkbox on change lines
// and hunk headers. A tap anywhere on a pickable row toggles it.
Item {
    id: row

    required property string rowId
    required property string kind
    required property string text
    required property var oldLine
    required property var newLine
    required property bool pickable
    /// true, false, or null for a partly picked hunk.
    required property var checked

    readonly property bool hunk: kind === "hunk"
    readonly property bool line: kind === "addition" || kind === "deletion" || kind === "context"
    readonly property bool added: kind === "addition"
    readonly property bool removed: kind === "deletion"
    readonly property var hunkParts: {
        const match = /^(@@[^@]*@@)(.*)$/.exec(text)
        return match ? [match[1], match[2].trim()] : [text, ""]
    }
    readonly property real checkSlotWidth: Theme.space.s4 + Metrics.checkboxSize + Theme.space.s2

    implicitHeight: hunk ? GitLamaLayout.hunkHeaderHeight
        : line ? Tokens.size.rowCompact
        : label.implicitHeight + 2 * (kind === "file" ? Theme.space.s3 : Theme.space.s2)

    function toggle() {
        if (pickable && (hunk || line))
            Store.lineSelection.toggle(rowId, checked !== true)
    }

    Rectangle {
        anchors.fill: parent
        color: row.hunk ? Theme.colors.paneAlt : row.added ? Theme.colors.successBg : row.removed ? GitColors.deletedBg : "transparent"
        Rectangle { visible: row.hunk; width: parent.width; height: Metrics.hairline; color: Theme.colors.line }
        Rectangle { visible: row.hunk; y: parent.height - height; width: parent.width; height: Metrics.hairline; color: Theme.colors.line }
    }

    TapHandler {
        enabled: row.pickable && (row.hunk || row.line)
        onTapped: row.toggle()
    }
    HoverHandler {
        enabled: row.pickable && (row.hunk || row.line)
        cursorShape: Qt.PointingHandCursor
    }

    MeridianCheckbox {
        visible: row.pickable && (row.hunk || row.line)
        x: Theme.space.s4
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Metrics.checkboxSize
        focusPolicy: Qt.NoFocus
        checkState: row.checked === true ? Qt.Checked : row.checked === false ? Qt.Unchecked : Qt.PartiallyChecked
        tristate: true
        // The row decides the next state.
        nextCheckState: function() { return checkState }
        onClicked: row.toggle()
        Accessible.name: row.hunk ? L10n.tn("lineSelectionSection", { header: row.text })
            : row.added ? L10n.tn("lineSelectionAdded", { line: row.newLine ?? 0, text: row.text })
            : L10n.tn("lineSelectionRemoved", { line: row.oldLine ?? 0, text: row.text })
    }

    // A hunk header: its range, then the enclosing section.
    Row {
        visible: row.hunk
        x: row.checkSlotWidth + Theme.space.s3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s4
        MeridianText { role: MeridianText.CodeSm; color: Theme.colors.inkMuted; text: row.hunkParts[0] }
        MeridianText {
            width: row.width - row.checkSlotWidth - Theme.space.s3 - x - Theme.space.s4
            role: MeridianText.CodeSm
            elide: Text.ElideRight
            text: row.hunkParts[1]
        }
    }

    // A change or context line: gutters, sign, text.
    Row {
        visible: row.line
        x: row.checkSlotWidth
        anchors.verticalCenter: parent.verticalCenter
        MeridianText {
            width: GitLamaLayout.diffGutterWidth
            rightPadding: Theme.space.s4
            horizontalAlignment: Text.AlignRight
            role: MeridianText.CodeSm
            color: Theme.colors.inkMuted
            text: row.oldLine === null || row.oldLine === undefined ? "" : String(row.oldLine)
        }
        MeridianText {
            width: GitLamaLayout.diffGutterWidth
            rightPadding: Theme.space.s4
            horizontalAlignment: Text.AlignRight
            role: MeridianText.CodeSm
            color: Theme.colors.inkMuted
            text: row.newLine === null || row.newLine === undefined ? "" : String(row.newLine)
        }
        MeridianText {
            width: GitLamaLayout.diffSignWidth
            horizontalAlignment: Text.AlignHCenter
            role: MeridianText.CodeSm
            color: row.added ? Theme.colors.success : GitColors.deleted
            text: row.added ? "+" : row.removed ? "−" : ""
        }
        MeridianText {
            width: row.width - row.checkSlotWidth - 2 * GitLamaLayout.diffGutterWidth - GitLamaLayout.diffSignWidth - Theme.space.s4
            role: MeridianText.Code
            elide: Text.ElideRight
            text: row.text
        }
    }

    // A file header or a note (no newline, binary, ...).
    MeridianText {
        id: label
        visible: !row.hunk && !row.line
        x: row.kind === "file" ? Theme.space.s4
            : row.checkSlotWidth + 2 * GitLamaLayout.diffGutterWidth + GitLamaLayout.diffSignWidth
        anchors.verticalCenter: parent.verticalCenter
        width: row.width - x - Theme.space.s4
        role: row.kind === "file" ? MeridianText.CodeSm : MeridianText.Caption
        color: row.kind === "file" ? Theme.colors.ink : Theme.colors.inkMuted
        elide: Text.ElideRight
        text: {
            switch (row.kind) {
            case "noNewline": return L10n.t("diffNoNewline")
            case "binary": return L10n.t("diffBinaryFallback")
            case "image": return L10n.t("diffImageFallback")
            case "submodule": return L10n.t("diffSubmoduleFallback")
            case "modeOnly": return L10n.tn("diffModeOnlyFallback", { modes: row.text })
            case "tooLarge": return L10n.t("diffTooLargeFallback")
            default: return row.text
            }
        }
    }
}
