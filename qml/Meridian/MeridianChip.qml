import QtQuick
import QtQuick.Templates as T

// A compact label: a filter, a tag, a recipient, an attachment (Flutter:
// MeridianChip). `selected` makes it a filter toggle (`accent-soft` with a
// check). `removable` adds its own remove button (`removeLabel` is its
// accessible name, e.g. "Remove Anna") that emits `removeRequested`.
T.AbstractButton {
    id: control

    enum Tone { Neutral, Accent, Success, Warning, Danger, Attention }

    property int tone: MeridianChip.Neutral
    property string iconName
    /// A `series` colour for a category; the text always goes with it.
    property color dotColor: "transparent"
    property bool selected: false
    /// Pressable (a filter or an attachment). Plain tags are not.
    property bool interactive: false
    property bool removable: false
    property string removeLabel
    property real maxWidth: 240

    signal removeRequested()

    readonly property bool tinted: tone !== MeridianChip.Neutral || selected
    readonly property color restFill: {
        const c = Theme.colors
        if (selected) return c.accentSoft
        switch (tone) {
        case MeridianChip.Accent: return c.accentSoft
        case MeridianChip.Success: return c.successBg
        case MeridianChip.Warning: return c.warningBg
        case MeridianChip.Danger: return c.dangerBg
        case MeridianChip.Attention: return c.attentionBg
        default: return Theme.clear(c.paneHover)
        }
    }
    readonly property color inkColor: {
        const c = Theme.colors
        if (!enabled) return c.inkFaint
        if (selected) return c.accentInk
        switch (tone) {
        case MeridianChip.Accent: return c.accentInk
        case MeridianChip.Success: return c.success
        case MeridianChip.Warning: return c.warning
        case MeridianChip.Danger: return c.danger
        case MeridianChip.Attention: return c.attention
        default: return c.ink
        }
    }
    readonly property bool hoverable: enabled && (interactive || removable) && !selected
    readonly property color fillColor: {
        if (!hoverable || !hovered)
            return restFill
        const base = tinted ? Theme.pressed(restFill) : Theme.colors.paneHover
        return down ? Theme.pressed(base) : base
    }

    hoverEnabled: true
    focusPolicy: interactive ? Qt.StrongFocus : Qt.NoFocus
    implicitHeight: Math.max(Theme.touch ? Metrics.chipHeightTouch : Metrics.chipHeight,
                             Theme.type.labelLineHeight + 2 * Theme.space.s1)
    implicitWidth: Math.min(maxWidth, Math.ceil(implicitContentWidth + leftPadding + rightPadding))
    leftPadding: Theme.space.s4
    rightPadding: removable ? Theme.space.s1 : Theme.space.s4
    topPadding: 0
    bottomPadding: 0

    Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: text
    Accessible.checked: selected

    scale: down && interactive ? Motion.pressScale : 1
    Behavior on scale {
        NumberAnimation {
            duration: control.down ? Motion.press : Motion.snappy.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: control.down ? Motion.exitCurve : Motion.snappy.curve
        }
    }

    contentItem: Item {
        readonly property real dotWidth: dot.visible ? dot.width + Theme.space.s2 : 0
        readonly property real glyphWidth: glyph.visible ? glyph.width + Theme.space.s2 : 0
        readonly property real removeWidth: remove.visible ? Theme.space.s2 + remove.width : 0
        implicitWidth: dotWidth + glyphWidth + label.implicitWidth + removeWidth
        implicitHeight: Theme.type.labelLineHeight

        Rectangle {
            id: dot
            visible: control.dotColor.a > 0
            width: Metrics.statusDot
            height: width
            radius: width / 2
            color: control.dotColor
            anchors.verticalCenter: parent.verticalCenter
        }
        MeridianIcon {
            id: glyph
            x: parent.dotWidth
            visible: control.selected || control.iconName.length > 0
            name: control.selected ? "check" : control.iconName
            iconSize: MeridianIcon.Small
            color: control.inkColor
            anchors.verticalCenter: parent.verticalCenter
        }
        MeridianText {
            id: label
            x: parent.dotWidth + parent.glyphWidth
            role: MeridianText.Label
            text: control.text
            color: control.inkColor
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(implicitWidth, parent.width - x - parent.removeWidth))
        }
        MeridianIconButton {
            id: remove
            objectName: "chipRemoveButton"
            x: parent.width - width
            visible: control.removable
            iconName: "x"
            text: control.removeLabel
            controlSize: MeridianButton.Small
            surfaceColor: control.fillColor
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Theme.touch ? Theme.size.minTarget : Metrics.chipHeight - 4
            implicitHeight: implicitWidth
            extent: Metrics.chipHeight - 4
            onClicked: control.removeRequested()
        }
    }

    background: Rectangle {
        radius: Theme.radius.sm
        color: control.fillColor
        border.width: control.tinted ? 0 : 1
        border.color: control.enabled ? Theme.colors.lineStrong : Theme.colors.line
        Behavior on color { ColorAnimation { duration: Motion.hoverFor(control.hovered) } }
        MeridianFocusRing {
            target: control
            shown: control.visualFocus
            targetRadius: Theme.radius.sm
        }
    }
}
