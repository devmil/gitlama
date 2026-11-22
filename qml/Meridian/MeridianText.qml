import QtQuick

// Text in one of Meridian's type roles. Hierarchy comes from weight and ink,
// not size: most UI text is Body, BodyStrong, Label or Caption.
Text {
    id: root

    enum Role { Display, Title, Heading, Body, BodyStrong, Label, Caption, Overline, Code, CodeSm, Reading }

    property int role: MeridianText.Body
    /// Tabular figures (times, counts, sizes) so digits line up.
    /// Set this, not `font.features`, which would replace the role's font.
    property bool tabular: false

    readonly property font roleFont: {
        const t = Theme.type
        switch (role) {
        case MeridianText.Display: return t.display
        case MeridianText.Title: return t.title
        case MeridianText.Heading: return t.heading
        case MeridianText.BodyStrong: return t.bodyStrong
        case MeridianText.Label: return t.label
        case MeridianText.Caption: return t.caption
        case MeridianText.Overline: return t.overline
        case MeridianText.Code: return t.code
        case MeridianText.CodeSm: return t.codeSm
        case MeridianText.Reading: return t.reading
        default: return t.body
        }
    }

    readonly property real roleLineHeight: {
        const t = Theme.type
        switch (role) {
        case MeridianText.Display: return t.displayLineHeight
        case MeridianText.Title: return t.titleLineHeight
        case MeridianText.Heading: return t.headingLineHeight
        case MeridianText.BodyStrong: return t.bodyStrongLineHeight
        case MeridianText.Label: return t.labelLineHeight
        case MeridianText.Caption: return t.captionLineHeight
        case MeridianText.Overline: return t.overlineLineHeight
        case MeridianText.Code: return t.codeLineHeight
        case MeridianText.CodeSm: return t.codeSmLineHeight
        case MeridianText.Reading: return t.readingLineHeight
        default: return t.bodyLineHeight
        }
    }

    /// Overrides on top of the role. Never assign `font.*` on a
    /// MeridianText: that replaces the role font with the default one.
    property int fontWeight: -1
    property real fontPixelSize: -1
    property bool strikeout: false

    readonly property bool _plainRole: !tabular && fontWeight < 0 && fontPixelSize <= 0 && !strikeout
    font: _plainRole ? roleFont
        : Qt.font({ family: roleFont.family,
                    pixelSize: fontPixelSize > 0 ? fontPixelSize : roleFont.pixelSize,
                    weight: fontWeight >= 0 ? fontWeight : roleFont.weight,
                    letterSpacing: roleFont.letterSpacing, capitalization: roleFont.capitalization,
                    strikeout: strikeout,
                    features: tabular ? { "tnum": 1 } : {} })
    color: Theme.colors.ink
    // Fixed line boxes keep rows on the token grid; a larger line count still
    // grows the item.
    lineHeightMode: Text.FixedHeight
    lineHeight: roleLineHeight
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
