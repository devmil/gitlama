import QtQuick

// One status bar text: `caption`, `ink-muted`, tabular figures, swapping
// with a 3px rise when it changes, with an optional small leading icon.
Item {
    id: root

    property string text
    property string iconName
    /// False swaps at once: for text that changes on every refresh.
    property bool animated: true
    /// Caps the width; the text ellipsizes.
    property real maxWidth: -1

    implicitWidth: Math.min(maxWidth >= 0 ? maxWidth : Number.MAX_VALUE,
                            (icon.visible ? icon.width + Theme.space.s2 : 0) + swap.contentWidth)
    implicitHeight: Theme.type.captionLineHeight
    Accessible.role: Accessible.StaticText
    Accessible.name: text

    MeridianIcon {
        id: icon
        visible: root.iconName.length > 0
        anchors.verticalCenter: parent.verticalCenter
        name: root.iconName
        iconSize: MeridianIcon.Small
        color: Theme.colors.inkMuted
    }
    MeridianSwapText {
        id: swap
        x: icon.visible ? icon.width + Theme.space.s2 : 0
        width: root.width - x
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        tabular: true
        rise: Metrics.statusBarRise
        animated: root.animated
        Accessible.ignored: true
    }
}
