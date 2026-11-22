import QtQuick

// Read-only text a person can select and copy (Flutter:
// MeridianSelectableText): wraps, keeps the role's font and line height.
TextEdit {
    id: root

    property int role: MeridianText.Body
    property bool tabular: false
    property bool selectable: true
    readonly property real firstLineHeight: roleLineHeight

    readonly property font roleFont: {
        const t = Theme.type
        switch (role) {
        case MeridianText.Caption: return t.caption
        case MeridianText.Code: return t.code
        case MeridianText.CodeSm: return t.codeSm
        case MeridianText.Label: return t.label
        case MeridianText.BodyStrong: return t.bodyStrong
        default: return t.body
        }
    }
    readonly property real roleLineHeight: {
        const t = Theme.type
        switch (role) {
        case MeridianText.Caption: return t.captionLineHeight
        case MeridianText.Code: return t.codeLineHeight
        case MeridianText.CodeSm: return t.codeSmLineHeight
        case MeridianText.Label: return t.labelLineHeight
        case MeridianText.BodyStrong: return t.bodyStrongLineHeight
        default: return t.bodyLineHeight
        }
    }

    font: tabular ? Qt.font({ family: roleFont.family, pixelSize: roleFont.pixelSize, weight: roleFont.weight,
                              letterSpacing: roleFont.letterSpacing, features: { "tnum": 1 } })
                  : roleFont
    color: Theme.colors.ink
    selectionColor: Theme.colors.accentSoft
    selectedTextColor: Theme.colors.ink
    readOnly: true
    selectByMouse: selectable
    activeFocusOnPress: selectable
    activeFocusOnTab: false
    wrapMode: TextEdit.Wrap
    textFormat: TextEdit.PlainText
    persistentSelection: false
    // Line boxes on the token grid.
    topPadding: Math.max(0, (roleLineHeight - fontMetrics.height) / 2)
    bottomPadding: topPadding
    onActiveFocusChanged: if (!activeFocus) deselect()

    FontMetrics {
        id: fontMetrics
        font: root.font
    }
}
