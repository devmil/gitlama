import QtQuick
import QtQuick.Templates as T

// One colour in a palette (Flutter: MeridianColorSwatch): a `color` disc
// with a `line-strong` edge (so white reads on white); selected, it gains a
// check and a 2px `accent` ring 2px outside. Lay a palette out in a Flow
// with `space-2` gaps. `color` is content, not a theme token; `text` names
// it for the tooltip and assistive technology. 24px, 32px at touch density.
T.AbstractButton {
    id: control

    property color color: "transparent"
    property bool selected: false

    readonly property real disc: Theme.touch ? Metrics.swatchSizeTouch : Metrics.swatchSize
    readonly property real ring: Metrics.swatchRingWidth + Metrics.swatchRingGap

    implicitWidth: disc + 2 * ring
    implicitHeight: disc + 2 * ring
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.checked: selected

    contentItem: Item {
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: Metrics.swatchRingWidth
            border.color: control.selected ? Theme.colors.accent : Theme.clear(Theme.colors.accent)
            Behavior on border.color { ColorAnimation { duration: Motion.select } }
        }
        Rectangle {
            x: control.ring
            y: control.ring
            width: control.disc
            height: control.disc
            radius: width / 2
            color: control.color
            opacity: control.enabled ? 1 : 0.4
            border.width: Metrics.hairline
            border.color: !control.enabled ? Theme.colors.line
                : control.hovered || control.pressed ? Theme.colors.inkMuted : Theme.colors.lineStrong
            MeridianIcon {
                visible: control.selected
                anchors.centerIn: parent
                name: "check"
                iconSize: MeridianIcon.Small
                // The check contrasts with the content colour, not the theme.
                color: (0.2126 * control.color.r + 0.7152 * control.color.g + 0.0722 * control.color.b) > 0.55 ? "#1b1f24" : "#ffffff"
            }
        }
        MeridianFocusRing { target: parent; shown: control.visualFocus; targetRadius: width / 2 }
        MeridianTooltip { shown: control.hovered; text: control.text }
    }
}
