import QtQuick
import QtQuick.Templates as T

// A labelled command (Flutter: MeridianButton).
//
// The label is the verb and its object in sentence case ("Move 3 messages to
// archive"). The width follows the label; never fix it, German runs up to 40%
// longer. `primary` at most once per island; `danger` only inside a
// confirming dialog (use `DangerQuiet` in rows and headers).
T.Button {
    id: control

    enum Variant { Primary, Secondary, Quiet, Danger, DangerQuiet }
    enum ControlSize { Regular, Small }

    property int variant: MeridianButton.Secondary
    property int controlSize: MeridianButton.Regular
    /// Lucide name of the leading icon.
    property string iconName
    property string trailingIconName
    /// Keeps the label and swaps the icon for a spinner after 150ms.
    property bool loading: false
    /// Edge-triggered confirmation: the leading icon becomes a check for
    /// `motion-hold`, then `successFinished` is emitted once.
    property bool success: false
    property bool iconOnly: false
    /// The fill the button sits on, for the quiet hover (defaults to `pane`).
    property color surfaceColor: "transparent"
    property bool onGround: false
    /// Why the command is unavailable; announced and used as the tooltip.
    property string disabledReason
    /// A hover label, shown for icon-only buttons by default.
    property string tooltip

    signal successFinished()
    /// The command. Unlike `clicked`, it does not fire while `loading`: focus
    /// stays on the button and nothing runs. Connect commands here.
    signal activated()

    readonly property bool small: controlSize === MeridianButton.Small
    readonly property bool primary: variant === MeridianButton.Primary
    // The confirmation looks active only for its hold: a `success` left set
    // afterwards does not keep a disabled button looking enabled.
    readonly property bool active: enabled || loading || _holding
    readonly property real extent: small ? Theme.size.controlSmall : Theme.size.control
    readonly property color restFill: {
        const c = Theme.colors
        switch (variant) {
        case MeridianButton.Primary: return c.accent
        case MeridianButton.Danger: return c.danger
        case MeridianButton.Secondary: return c.pane
        case MeridianButton.DangerQuiet: return Theme.clear(c.dangerBg)
        default: return Theme.clear(c.paneHover)
        }
    }
    readonly property color hoverFill: {
        const c = Theme.colors
        switch (variant) {
        case MeridianButton.Primary: return Theme.brighten(c.accent, c.inkOnAccent)
        case MeridianButton.Danger: return Theme.brighten(c.danger, c.inkOnDanger)
        case MeridianButton.Secondary: return c.paneHover
        case MeridianButton.DangerQuiet: return c.dangerBg
        default: return Theme.hoverFillOn(surfaceColor, onGround)
        }
    }
    readonly property color edgeColor: {
        const c = Theme.colors
        if (!active) {
            return variant === MeridianButton.Secondary || variant === MeridianButton.Danger
                ? c.line : Theme.clear(c.line)
        }
        switch (variant) {
        case MeridianButton.Primary: return c.accent
        case MeridianButton.Danger: return c.danger
        case MeridianButton.Secondary: return c.lineStrong
        default: return Theme.clear(c.lineStrong)
        }
    }
    readonly property color inkColor: {
        const c = Theme.colors
        if (!active)
            return primary ? c.inkMuted : c.inkFaint
        switch (variant) {
        case MeridianButton.Primary: return c.inkOnAccent
        case MeridianButton.Danger: return c.inkOnDanger
        case MeridianButton.DangerQuiet: return c.danger
        default: return c.ink
        }
    }
    readonly property color fillColor: {
        if (loading || _holding)
            return restFill
        if (!enabled)
            return primary ? Theme.colors.accentSoft : Theme.clear(Theme.colors.paneHover)
        if (down)
            return Theme.pressed(hoverFill)
        return hovered ? hoverFill : restFill
    }

    property bool _holding: false

    onSuccessChanged: {
        if (success) {
            _holding = true
            successHold.restart()
        } else {
            _holding = false
            successHold.stop()
        }
    }
    onLoadingChanged: if (loading) { successHold.stop(); _holding = false }

    Timer {
        id: successHold
        interval: Motion.hold
        onTriggered: {
            control._holding = false
            control.successFinished()
        }
    }

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    implicitHeight: Math.max(extent, iconOnly ? 0 : Theme.type.labelLineHeight + 2 * Theme.space.s2)
    implicitWidth: iconOnly ? extent : Math.ceil(implicitContentWidth + leftPadding + rightPadding)
    leftPadding: iconOnly ? 0 : (small ? Theme.space.s4 : Theme.space.s5)
    rightPadding: leftPadding
    topPadding: 0
    bottomPadding: 0
    spacing: Theme.space.s3

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.description: !enabled && disabledReason.length > 0 ? disabledReason : ""

    MeridianTooltip {
        shown: control.hovered
        text: !control.enabled && control.disabledReason.length > 0 ? control.disabledReason
            : control.tooltip.length > 0 ? control.tooltip : control.iconOnly ? control.text : ""
    }

    scale: down && active ? Motion.pressScale : 1
    Behavior on scale {
        NumberAnimation {
            duration: control.down ? Motion.press : Motion.snappy.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: control.down ? Motion.exitCurve : Motion.snappy.curve
        }
    }

    contentItem: Item {
        readonly property real slotWidth: slot.occupied ? Theme.size.iconSmall : 0
        readonly property real slotGap: control.iconOnly || !slot.occupied ? 0 : control.spacing
        readonly property real trailingWidth: trailing.visible ? control.spacing + trailing.width : 0
        implicitWidth: control.iconOnly ? slotWidth : slotWidth + slotGap + label.implicitWidth + trailingWidth
        implicitHeight: Math.max(Theme.size.iconSmall, Theme.type.labelLineHeight)

        Item {
            id: slot
            objectName: "buttonIconSlot"
            readonly property bool occupied: control.iconName.length > 0 || control.loading || control._holding
            width: parent.slotWidth
            height: Theme.size.iconSmall
            x: control.iconOnly ? (parent.width - width) / 2
                                : Math.max(0, (parent.width - parent.implicitWidth) / 2)
            anchors.verticalCenter: parent.verticalCenter
            MeridianIcon {
                anchors.centerIn: parent
                name: control._holding ? "check" : control.iconName
                iconSize: MeridianIcon.Small
                color: control.inkColor
                visible: !spinner.shown
            }
            MeridianSpinner {
                id: spinner
                anchors.centerIn: parent
                size: Theme.size.iconSmall
                running: control.loading
                color: control.inkColor
            }
        }

        MeridianText {
            id: label
            visible: !control.iconOnly
            role: MeridianText.Label
            text: control.text
            color: control.inkColor
            anchors.verticalCenter: parent.verticalCenter
            x: slot.x + slot.width + parent.slotGap
            width: Math.max(0, Math.min(implicitWidth, parent.width - x - parent.trailingWidth))
        }

        MeridianIcon {
            id: trailing
            visible: !control.iconOnly && control.trailingIconName.length > 0
            name: control.trailingIconName
            iconSize: MeridianIcon.Small
            color: control.inkColor
            anchors.verticalCenter: parent.verticalCenter
            x: label.x + label.width + control.spacing
        }
    }

    background: Item {
        implicitHeight: control.extent
        MeridianShadow {
            anchors.fill: parent
            visible: control.active && control.variant === MeridianButton.Secondary
            layers: Theme.shadows.control
            radius: Theme.radius.md
        }
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.md
            color: control.fillColor
            border.width: 1
            border.color: control.edgeColor
            Behavior on color {
                ColorAnimation { duration: Motion.hoverFor(control.hovered || control.down) }
            }
        }
        MeridianFocusRing {
            target: control
            shown: control.visualFocus
            targetRadius: Theme.radius.md
        }
    }

    onClicked: if (!loading) activated()
    Keys.onReturnPressed: event => { if (!control.loading) control.clicked(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!control.loading) control.clicked(); event.accepted = true }
}
