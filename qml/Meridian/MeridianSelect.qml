pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T

// A trigger that looks like a secondary button showing the current value
// and opens a menu of the choices with the current one checked (Flutter:
// MeridianSelect). The trigger fits its longest choice, so it keeps its size
// when the value changes; its chevron turns half a turn while open.
//
// `values` holds the choices; `valueLabel(value)` names one (defaults to
// String(value)). `activated(value)` reports a pick.
T.AbstractButton {
    id: control

    property var values: []
    property var value
    property var valueLabel: function (v) { return String(v) }
    /// Accessible name ("Polling interval").
    property string label
    property bool showLabel: false
    property real fixedWidth: -1
    property real minWidth: Metrics.selectMinWidth
    property int controlSize: MeridianButton.Regular
    property bool animateValue: false

    signal activated(var value)

    readonly property bool small: controlSize === MeridianButton.Small
    readonly property string currentLabel: valueLabel(value)
    readonly property real extent: Math.ceil(Math.max(small ? Theme.size.controlSmall : Theme.size.control,
                                                       Theme.type.bodyLineHeight + 2 * (small ? Theme.space.s1 : Theme.space.s2)))
    readonly property real fitted: {
        let longest = 0
        const choices = values.slice()
        choices.push(value)
        for (let i = 0; i < choices.length; ++i)
            longest = Math.max(longest, metrics.advanceWidth(valueLabel(choices[i])))
        return Math.ceil(Theme.space.s4 + longest + Theme.space.s4 + Theme.size.iconSmall + Theme.space.s3 + 2)
    }

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    implicitWidth: fixedWidth >= 0 ? fixedWidth : Math.max(minWidth, fitted)
    implicitHeight: (showLabel ? Theme.type.labelLineHeight + Theme.space.s2 : 0) + extent
    padding: 0

    Accessible.role: Accessible.ComboBox
    Accessible.name: label
    Accessible.description: currentLabel

    FontMetrics {
        id: metrics
        font: Theme.type.body
    }

    onClicked: menu.open()

    Keys.onSpacePressed: event => { menu.open(); event.accepted = true }
    Keys.onReturnPressed: event => { menu.open(); event.accepted = true }

    contentItem: Item {
        MeridianText {
            visible: control.showLabel
            role: MeridianText.Label
            text: control.label
            color: control.enabled ? Theme.colors.ink : Theme.colors.inkFaint
        }
        Item {
            id: trigger
            y: control.showLabel ? Theme.type.labelLineHeight + Theme.space.s2 : 0
            width: parent.width
            height: control.extent

            MeridianShadow {
                anchors.fill: parent
                visible: control.enabled
                layers: Theme.shadows.control
                radius: Theme.radius.md
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.radius.md
                color: !control.enabled ? Theme.colors.paneAlt
                     : control.down ? Theme.pressed(Theme.colors.paneHover)
                     : control.hovered ? Theme.colors.paneHover : Theme.colors.pane
                border.width: 1
                border.color: control.enabled ? Theme.colors.lineStrong : Theme.colors.line
                Behavior on color { ColorAnimation { duration: Motion.hoverFor(control.hovered || control.down) } }
            }
            MeridianSwapText {
                x: Theme.space.s4
                anchors.verticalCenter: parent.verticalCenter
                width: chevron.x - x - Theme.space.s4
                style: control.animateValue ? MeridianSwapText.Rise : MeridianSwapText.Fade
                text: control.currentLabel
                color: control.enabled ? Theme.colors.ink : Theme.colors.inkFaint
            }
            MeridianIcon {
                id: chevron
                anchors.right: parent.right
                anchors.rightMargin: Theme.space.s3
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-down"
                iconSize: MeridianIcon.Small
                color: control.enabled ? Theme.colors.inkMuted : Theme.colors.inkFaint
                rotation: menu.visible ? 180 : 0
                Behavior on rotation {
                    NumberAnimation { duration: Motion.quick; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
                }
            }
            MeridianFocusRing {
                target: trigger
                shown: control.visualFocus
                targetRadius: Theme.radius.md
            }
        }
    }

    MeridianMenu {
        id: menu
        y: control.height
        width: Math.max(implicitWidth, control.width)
        Instantiator {
            model: control.values
            delegate: MeridianMenuItem {
                required property var modelData
                text: control.valueLabel(modelData)
                checkable: true
                checked: modelData === control.value
                onTriggered: control.activated(modelData)
            }
            onObjectAdded: (index, object) => menu.insertItem(index, object)
            onObjectRemoved: (index, object) => menu.removeItem(object)
        }
    }
}
