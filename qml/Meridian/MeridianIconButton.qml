import QtQuick
import QtQuick.Templates as T

// A single-icon command for toolbars, island headers and row hover actions
// (Flutter: MeridianIconButton). `text` is required: it is the accessible
// name and the tooltip. Use it only where the icon is unambiguous (search,
// close, more, pin); anything else is a MeridianButton with a label.
T.AbstractButton {
    id: control

    property string iconName
    property int controlSize: MeridianButton.Regular
    /// A toggle that is on: `accent-soft` fill, `accent-ink` icon.
    property bool active: false
    property bool onGround: false
    /// The fill the button sits on (a hovered or selected row), so its hover
    /// darkens that fill instead of vanishing into it.
    property color surfaceColor: "transparent"
    /// Rotation of the icon in turns (a disclosure chevron).
    property real turns: 0
    /// Nudge the icon 2px towards this direction on activation (-1, 0, 1).
    property int nudgeDirection: 0
    /// Overrides the icon colour (a row's `secondary` ink, `accent-ink`).
    property color iconColorOverride: "transparent"
    /// The hover label; `text` by default.
    property string tooltip
    /// Why the command is unavailable; the tooltip while disabled.
    property string disabledReason
    property bool showTooltip: true

    readonly property bool onAccent: Qt.colorEqual(surfaceColor, Theme.colors.accent)
    property real _hoverWeight: hovered && enabled ? 1 : 0
    Behavior on _hoverWeight { NumberAnimation { duration: Motion.hoverFor(control.hovered || control.down) } }
    property real _activeWeight: active && enabled ? 1 : 0
    Behavior on _activeWeight { NumberAnimation { duration: Motion.select } }
    property real extent: controlSize === MeridianButton.Small ? Theme.size.controlSmall : Theme.size.control
    readonly property color hoverFill: Theme.hoverFillOn(surfaceColor, onGround)
    readonly property color iconColor: {
        const c = Theme.colors
        if (!enabled)
            return c.inkFaint
        if (iconColorOverride.a > 0)
            return iconColorOverride
        if (onAccent)
            return hovered ? c.inkOnAccent : c.inkOnAccentMuted
        if (active)
            return c.accentInk
        return hovered || down ? c.ink : c.inkMuted
    }

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    implicitWidth: Math.max(extent, Theme.size.minTarget)
    implicitHeight: Math.max(extent, Theme.size.minTarget)
    padding: 0

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.checkable: false
    Accessible.description: !enabled && disabledReason.length > 0 ? disabledReason : ""

    MeridianTooltip {
        shown: control.showTooltip && control.hovered
        text: !control.enabled && control.disabledReason.length > 0 ? control.disabledReason
            : control.tooltip.length > 0 ? control.tooltip : control.text
    }

    scale: down ? Motion.pressScale : 1
    Behavior on scale {
        NumberAnimation {
            duration: control.down ? Motion.press : Motion.snappy.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: control.down ? Motion.exitCurve : Motion.snappy.curve
        }
    }

    onClicked: if (nudgeDirection !== 0) nudge.restart()

    contentItem: Item {
        MeridianIcon {
            id: glyph
            anchors.centerIn: parent
            name: control.iconName
            iconSize: control.controlSize === MeridianButton.Small ? MeridianIcon.Small : MeridianIcon.Regular
            color: control.iconColor
            rotation: control.turns * 360
            Behavior on rotation {
                NumberAnimation { duration: Motion.quick; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
            }
            // An override follows the data it shows (a row's ink) and swaps
            // at once; only the interaction states fade.
            Behavior on color {
                enabled: control.iconColorOverride.a === 0
                ColorAnimation { duration: Motion.select }
            }
            transform: Translate { id: shift }
        }
        SequentialAnimation {
            id: nudge
            NumberAnimation {
                target: shift; property: "x"
                to: control.nudgeDirection * Motion.nudgeDistance
                duration: Motion.nudge
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard
            }
            NumberAnimation {
                target: shift; property: "x"; to: 0
                duration: Motion.snappy.duration
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve
            }
        }
    }

    background: Item {
        Rectangle {
            anchors.centerIn: parent
            width: control.extent
            height: control.extent
            radius: Theme.radius.md
            // The interaction states animate as weights, so a surface that
            // changes with data (a heat-tinted row) moves the fill at once
            // instead of restarting a fade, and redrawing, on every change.
            color: !control.enabled ? Theme.clear(control.hoverFill)
                 : control.down ? Theme.pressed(control.hoverFill)
                 : Theme.blend(Theme.blend(Theme.clear(control.hoverFill), control.hoverFill, control._hoverWeight),
                               Theme.colors.accentSoft, control._activeWeight)
            MeridianFocusRing {
                target: control
                shown: control.visualFocus
                width: parent.width + 2 * _outset
                height: parent.height + 2 * _outset
                targetRadius: Theme.radius.md
            }
        }
    }
}
