import QtQuick
import Meridian

// A step's number in a plan list (the Dart GitLamaStepNumber): `code-sm`,
// `ink-muted`, right-aligned in at least a glyph's width.
MeridianText {
    property int number
    width: Math.max(GitLamaLayout.glyphSize, implicitWidth)
    horizontalAlignment: Text.AlignRight
    role: MeridianText.CodeSm
    color: Theme.colors.inkMuted
    text: String(number)
}
