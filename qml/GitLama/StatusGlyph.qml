import QtQuick
import Meridian

// The one-letter file status (GitLamaStatusGlyph): M and T in warning, A in
// success, D in deleted, R and C renamed, U attention, ? outlined. A partly
// staged file shows its fill on the upper half only.
Rectangle {
    id: glyph

    property string status
    property bool partial: false

    readonly property var look: {
        switch (status) {
        case "M": case "T": return [Theme.colors.warningBg, Theme.colors.warning, "", "statusGlyphModified"]
        case "A": return [Theme.colors.successBg, Theme.colors.success, "", "statusGlyphAdded"]
        case "D": return [GitColors.deletedBg, GitColors.deleted, "", "statusGlyphDeleted"]
        case "R": return [Theme.colors.accentSoft, GitColors.renamed, "", "statusGlyphRenamed"]
        case "C": return [Theme.colors.accentSoft, GitColors.renamed, "", "statusGlyphCopied"]
        case "U": return [Theme.colors.attentionBg, Theme.colors.attention, "", "statusGlyphConflict"]
        case "?": return [Theme.colors.paneAlt, Theme.colors.inkMuted, Theme.colors.lineStrong, "statusGlyphUntracked"]
        default: return ["transparent", Theme.colors.inkFaint, Theme.colors.line, "statusGlyphIgnored"]
        }
    }

    width: GitLamaLayout.glyphSize
    height: GitLamaLayout.glyphSize
    radius: Theme.radius.xs
    color: partial ? "transparent" : look[0]
    border.width: look[2] !== "" ? 1 : 0
    border.color: look[2] !== "" ? look[2] : "transparent"
    clip: true
    visible: status.length > 0

    Accessible.role: Accessible.StaticText
    Accessible.name: L10n.t(look[3])

    Rectangle {
        visible: glyph.partial
        anchors.fill: parent
        radius: glyph.radius
        color: glyph.look[0]
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height / 2
            color: Theme.colors.paneAlt
        }
    }
    MeridianText {
        anchors.centerIn: parent
        role: MeridianText.Code
        fontPixelSize: 10
        fontWeight: Font.Bold
        text: glyph.status === "T" ? "M" : glyph.status === "·" ? "!" : glyph.status
        color: glyph.look[1]
    }
}
