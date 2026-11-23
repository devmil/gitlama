pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T

// A swatch that opens a MeridianColorPicker in a popover (Flutter:
// MeridianColorWell): "any other colour" beside a palette. It shows
// `color` inside a ring of hues, or the hues and a plus while there is no
// custom colour (`hasColor` false). The picker starts from `color` (or
// `initial`); every change is `edited`, the end of a drag, a chosen swatch
// or a submitted value `editFinished`. Escape or a click outside closes the
// popover and focus returns to the well. `text` names it.
T.AbstractButton {
    id: well

    property color color: "transparent"
    property bool hasColor: false
    property bool selected: false
    /// Where the picker starts while there is no colour.
    property var initial: undefined
    property var groups: []
    property string model: "hsv"
    /// Strings for the picker: {wheel, hue, ...} as MeridianColorPicker names them.
    property var pickerLabels: ({})

    signal edited(color value)
    signal editFinished(color value)

    readonly property real disc: Theme.touch ? Metrics.swatchSizeTouch : Metrics.swatchSize
    readonly property real ring: Metrics.swatchRingWidth + Metrics.swatchRingGap
    readonly property alias popover: pickerPopover

    implicitWidth: disc + 2 * ring
    implicitHeight: disc + 2 * ring
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.checked: selected

    onClicked: pickerPopover.open()

    contentItem: Item {
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: Metrics.swatchRingWidth
            border.color: well.selected ? Theme.colors.accent : Theme.clear(Theme.colors.accent)
            Behavior on border.color { ColorAnimation { duration: Motion.select } }
        }
        Item {
            x: well.ring
            y: well.ring
            width: well.disc
            height: well.disc
            opacity: well.enabled ? 1 : 0.4
            // The ring of hues.
            Canvas {
                anchors.fill: parent
                onPaint: {
                    const context = getContext("2d")
                    context.reset()
                    const r = width / 2
                    for (let h = 0; h < 360; h += 2) {
                        context.beginPath()
                        context.moveTo(r, r)
                        context.arc(r, r, r, (h - 1.2) * Math.PI / 180, (h + 1.2) * Math.PI / 180, false)
                        context.closePath()
                        context.fillStyle = String(Qt.hsva(h / 360, 1, 1, 1))
                        context.fill()
                    }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: Metrics.hairline
                border.color: !well.enabled ? Theme.colors.line
                    : well.hovered || well.pressed ? Theme.colors.inkMuted : Theme.colors.lineStrong
            }
            // The custom colour in the middle, or a plus.
            Rectangle {
                visible: well.hasColor
                anchors.centerIn: parent
                width: parent.width * Metrics.colorWellCore
                height: width
                radius: width / 2
                color: well.color
                border.width: Metrics.hairline
                border.color: Theme.colors.pane
            }
            Rectangle {
                visible: !well.hasColor
                anchors.centerIn: parent
                width: parent.width * Metrics.colorWellCore
                height: width
                radius: width / 2
                color: Theme.colors.pane
                MeridianIcon { anchors.centerIn: parent; name: "plus"; iconSize: MeridianIcon.Small; color: Theme.colors.ink }
            }
        }
        MeridianFocusRing { target: parent; shown: well.visualFocus; targetRadius: width / 2 }
        MeridianTooltip { shown: well.hovered && !pickerPopover.visible; text: well.text }
    }

    MeridianPopover {
        id: pickerPopover
        width: Metrics.colorWellPopover
        onClosed: well.forceActiveFocus()
        contentItem: MeridianColorPicker {
            id: picker
            color: well.hasColor ? well.color : well.initial !== undefined ? well.initial : Qt.hsva(0, 1, 1, 1)
            original: well.hasColor ? well.color : well.initial
            groups: well.groups
            model: well.model
            wheelLabel: well.pickerLabels.wheel ?? "Hue and saturation"
            hueLabel: well.pickerLabels.hue ?? "Hue"
            saturationLabel: well.pickerLabels.saturation ?? "Saturation"
            brightnessLabel: well.pickerLabels.brightness ?? "Brightness"
            redLabel: well.pickerLabels.red ?? "Red"
            greenLabel: well.pickerLabels.green ?? "Green"
            blueLabel: well.pickerLabels.blue ?? "Blue"
            hsvLabel: well.pickerLabels.hsv ?? "HSB"
            rgbLabel: well.pickerLabels.rgb ?? "RGB"
            channelsLabel: well.pickerLabels.channels ?? "Colour model"
            hexLabel: well.pickerLabels.hex ?? "Hex"
            invalidHexLabel: well.pickerLabels.invalidHex ?? "Enter six hex digits, such as #18304F"
            originalLabel: well.pickerLabels.original ?? "Original colour"
            currentLabel: well.pickerLabels.current ?? "New colour"
            swatchLabel: well.pickerLabels.swatch ?? (hex => "Colour " + hex)
            degreesText: well.pickerLabels.degrees ?? (value => value + "°")
            percentText: well.pickerLabels.percent ?? (value => value + "%")
            onEdited: value => well.edited(value)
            onEditFinished: value => well.editFinished(value)
        }
    }
}
