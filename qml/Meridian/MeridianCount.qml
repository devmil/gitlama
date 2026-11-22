import QtQuick

// A count pill (Flutter: MeridianCount): unread, matches, queued. Tabular
// `caption`-sized figures on `line`, or `accent`, `attention`, `danger`;
// `Quiet` drops the pill. A changing label rolls to its new value.
Item {
    id: root

    enum Tone { Neutral, Accent, Attention, Danger, Quiet }

    property string label
    property int tone: MeridianCount.Neutral
    property string semanticLabel
    /// A rising number rolls up; a falling one down.
    property int _previous: 0

    readonly property bool quiet: tone === MeridianCount.Quiet
    readonly property color fillColor: {
        const c = Theme.colors
        switch (tone) {
        case MeridianCount.Accent: return c.accent
        case MeridianCount.Attention: return c.attention
        case MeridianCount.Danger: return c.danger
        case MeridianCount.Quiet: return "transparent"
        default: return c.line
        }
    }
    readonly property color inkColor: {
        const c = Theme.colors
        switch (tone) {
        case MeridianCount.Accent: return c.inkOnAccent
        case MeridianCount.Attention: return c.inkOnAttention
        case MeridianCount.Danger: return c.inkOnDanger
        case MeridianCount.Quiet: return c.inkMuted
        default: return c.ink
        }
    }

    implicitWidth: Math.max(quiet ? 0 : Metrics.countMinWidth, text.contentWidth + (quiet ? 0 : 2 * Metrics.countPaddingX))
    implicitHeight: Metrics.countHeight
    Accessible.role: Accessible.StaticText
    Accessible.name: semanticLabel.length > 0 ? semanticLabel : label

    onLabelChanged: {
        const next = parseInt(label)
        if (!isNaN(next)) {
            text.direction = next >= _previous ? 1 : -1
            _previous = next
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.fillColor
    }
    MeridianSwapText {
        id: text
        anchors.centerIn: parent
        width: contentWidth
        height: root.height
        style: MeridianSwapText.Roll
        text: root.label
        role: MeridianText.Caption
        tabular: true
        color: root.inkColor
        Accessible.ignored: true
    }
}
