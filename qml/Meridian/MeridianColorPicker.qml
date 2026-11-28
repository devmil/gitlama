pragma ComponentBehavior: Bound
import QtQuick

// Picks a colour by eye or by number (Flutter: MeridianColorPicker): rows
// of offered colours (`groups`), a hue and saturation wheel, the colour
// before and after with its hex value, and sliders for hue, saturation and
// brightness or for red, green and blue.
//
// `color` is content, not a theme token. `edited(color)` follows every drag
// and keystroke; `editFinished(color)` reports the colour when a drag ends,
// a swatch is chosen, a hex value is submitted or a slider steps. The wheel
// turns the hue with Left and Right and changes the saturation with Up and
// Down (Shift for bigger steps). Wide (the wheel beside the controls) at
// `colorPickerWide` and up unless touch, stacked otherwise.
Item {
    id: picker

    property color color: "#ff0000"
    /// The colour before this edit, shown above `color`; a tap restores
    /// it. Unset shows only `color`.
    property var original: undefined
    /// "hsv" or "rgb": the channels the sliders edit.
    property string model: "hsv"
    /// [{title, colors: [...], labels: [...]}] offered as swatches.
    property var groups: []

    property string wheelLabel: "Hue and saturation"
    property string hueLabel: "Hue"
    property string saturationLabel: "Saturation"
    property string brightnessLabel: "Brightness"
    property string redLabel: "Red"
    property string greenLabel: "Green"
    property string blueLabel: "Blue"
    property string hsvLabel: "HSB"
    property string rgbLabel: "RGB"
    property string channelsLabel: "Colour model"
    property string hexLabel: "Hex"
    property string invalidHexLabel: "Enter six hex digits, such as #18304F"
    property string originalLabel: "Original colour"
    property string currentLabel: "New colour"
    property var swatchLabel: hex => "Colour " + hex
    property var degreesText: value => value + "°"
    property var percentText: value => value + "%"

    signal edited(color value)
    signal editFinished(color value)

    // The edited colour as hue (0..360), saturation and value (0..1); a grey
    // keeps the hue the wheel was turned to.
    property real hue: 0
    property real saturation: 1
    property real brightness: 1
    readonly property color shown: Qt.hsva(hue / 360, saturation, brightness, 1)
    readonly property bool wide: !Theme.touch && width >= Metrics.colorPickerWide
    property string hexError

    function hexOf(value) {
        const c = Qt.color(value)
        const part = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return ("#" + part(c.r) + part(c.g) + part(c.b)).toUpperCase()
    }
    function parseHex(text) {
        let value = text.trim().replace(/^#/, "")
        if (/^[0-9a-fA-F]{3}$/.test(value))
            value = value.split("").map(d => d + d).join("")
        return /^[0-9a-fA-F]{6}$/.test(value) ? Qt.color("#" + value) : null
    }
    function take(value) {
        const c = Qt.color(value)
        // Black keeps the hue and saturation, a grey the hue.
        if (c.hsvValue <= 0) {
            brightness = 0
            return
        }
        if (c.hsvHue >= 0)
            hue = c.hsvHue * 360
        saturation = c.hsvSaturation
        brightness = c.hsvValue
    }
    function change(h, s, v) {
        hue = ((h % 360) + 360) % 360
        saturation = Math.max(0, Math.min(1, s))
        brightness = Math.max(0, Math.min(1, v))
        hexField.text = hexOf(shown)
        hexError = ""
        edited(shown)
    }
    function choose(value) {
        take(value)
        hexField.text = hexOf(shown)
        hexError = ""
        edited(shown)
        editFinished(shown)
    }
    function setRgb(r, g, b) {
        take(Qt.rgba(r / 255, g / 255, b / 255, 1))
        hexField.text = hexOf(shown)
        edited(shown)
    }
    function stepWheel(degrees, amount) {
        change(hue + degrees, saturation + amount, brightness)
    }

    Component.onCompleted: { take(color); hexField.text = hexOf(shown) }
    onColorChanged: {
        if (hexOf(color) !== hexOf(shown)) {
            take(color)
            hexField.text = hexOf(shown)
        }
    }

    implicitWidth: Metrics.colorWellPopover - 2 * Theme.space.s6
    implicitHeight: layout.implicitHeight

    Column {
        id: layout
        width: parent.width
        spacing: Theme.space.s5

        // Offered colours.
        Repeater {
            model: picker.groups.filter(group => (group.colors ?? []).length > 0)
            delegate: Column {
                id: groupColumn
                required property var modelData
                width: layout.width
                spacing: Theme.space.s2
                MeridianText {
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: groupColumn.modelData.title ?? ""
                    Accessible.role: Accessible.Heading
                }
                Flow {
                    width: parent.width
                    spacing: Theme.space.s2
                    Repeater {
                        model: groupColumn.modelData.colors
                        delegate: MeridianColorSwatch {
                            required property var modelData
                            required property int index
                            color: modelData
                            text: (groupColumn.modelData.labels ?? [])[index] ?? picker.swatchLabel(picker.hexOf(modelData))
                            selected: picker.hexOf(modelData) === picker.hexOf(picker.shown)
                            enabled: picker.enabled
                            onClicked: picker.choose(modelData)
                        }
                    }
                }
            }
        }

        Flow {
            width: parent.width
            spacing: picker.wide ? Theme.space.s8 : Theme.space.s5
            flow: Flow.LeftToRight

            // The wheel: hues around, saturated at the rim, white at the
            // centre, at full brightness; its thumb shows the colour.
            Item {
                id: hueWheel
                readonly property real size: Math.min(Theme.touch ? Metrics.colorWheelTouch : Metrics.colorWheel, layout.width)
                readonly property real thumb: Theme.touch ? Metrics.colorWheelThumbTouch : Metrics.colorWheelThumb
                width: picker.wide ? size : layout.width
                height: size
                activeFocusOnTab: picker.enabled
                Accessible.role: Accessible.Slider
                Accessible.name: picker.wheelLabel
                Accessible.description: picker.hueLabel + " " + picker.degreesText(Math.round(picker.hue)) + ", "
                    + picker.saturationLabel + " " + picker.percentText(Math.round(picker.saturation * 100))
                Keys.onPressed: event => {
                    const shift = event.modifiers & Qt.ShiftModifier
                    const degrees = shift ? 10 : 1
                    const amount = shift ? 0.1 : 0.01
                    if (event.key === Qt.Key_Right) picker.stepWheel(degrees, 0)
                    else if (event.key === Qt.Key_Left) picker.stepWheel(-degrees, 0)
                    else if (event.key === Qt.Key_Up) picker.stepWheel(0, amount)
                    else if (event.key === Qt.Key_Down) picker.stepWheel(0, -amount)
                    else return
                    event.accepted = true
                }
                Keys.onReleased: event => {
                    if ([Qt.Key_Right, Qt.Key_Left, Qt.Key_Up, Qt.Key_Down].indexOf(event.key) >= 0 && !event.isAutoRepeat)
                        picker.editFinished(picker.shown)
                }
                Item {
                    id: disc
                    x: (parent.width - width) / 2
                    width: hueWheel.size
                    height: hueWheel.size
                    opacity: picker.enabled ? 1 : 0.4
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            const context = getContext("2d")
                            context.reset()
                            const r = width / 2
                            for (let h = 0; h < 360; h += 1) {
                                context.beginPath()
                                context.moveTo(r, r)
                                context.arc(r, r, r, (h - 0.6) * Math.PI / 180, (h + 0.6) * Math.PI / 180, false)
                                context.closePath()
                                context.fillStyle = String(Qt.hsva(h / 360, 1, 1, 1))
                                context.fill()
                            }
                            const white = context.createRadialGradient(r, r, 0, r, r, r)
                            white.addColorStop(0, "rgba(255,255,255,1)")
                            white.addColorStop(1, "rgba(255,255,255,0)")
                            context.beginPath()
                            context.arc(r, r, r, 0, 2 * Math.PI, false)
                            context.fillStyle = white
                            context.fill()
                            context.beginPath()
                            context.arc(r, r, r - 0.5, 0, 2 * Math.PI, false)
                            context.lineWidth = Metrics.hairline
                            context.strokeStyle = String(Theme.colors.lineStrong)
                            context.stroke()
                        }
                        onWidthChanged: requestPaint()
                    }
                    Rectangle {
                        readonly property real angle: picker.hue * Math.PI / 180
                        readonly property real reach: picker.saturation * disc.width / 2
                        x: disc.width / 2 + Math.cos(angle) * reach - width / 2
                        y: disc.height / 2 + Math.sin(angle) * reach - height / 2
                        width: hueWheel.thumb
                        height: hueWheel.thumb
                        radius: width / 2
                        color: Qt.hsva(picker.hue / 360, picker.saturation, picker.brightness, 1)
                        border.width: Metrics.colorWheelThumbRing
                        border.color: Theme.colors.pane
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -Metrics.hairline
                            radius: width / 2
                            color: "transparent"
                            border.width: Metrics.hairline
                            border.color: Theme.colors.ink
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: picker.enabled
                        cursorShape: Qt.CrossCursor
                        preventStealing: true
                        function at(mouse) {
                            const dx = mouse.x - width / 2
                            const dy = mouse.y - height / 2
                            let angle = Math.atan2(dy, dx) * 180 / Math.PI
                            if (angle < 0)
                                angle += 360
                            picker.change(angle, Math.sqrt(dx * dx + dy * dy) / (width / 2), picker.brightness)
                        }
                        onPressed: mouse => { hueWheel.forceActiveFocus(); at(mouse) }
                        onPositionChanged: mouse => at(mouse)
                        onReleased: picker.editFinished(picker.shown)
                    }
                    MeridianFocusRing { target: parent; shown: hueWheel.activeFocus; targetRadius: width / 2 }
                }
            }

            Column {
                width: picker.wide ? layout.width - hueWheel.width - Theme.space.s8 : layout.width
                spacing: Theme.space.s4

                Row {
                    width: parent.width
                    spacing: Theme.space.s4
                    // The colour before the edit (a tap restores it) above the new one.
                    Rectangle {
                        id: preview
                        width: Metrics.colorPreview
                        height: Theme.size.control
                        radius: Theme.radius.md
                        color: "transparent"
                        clip: true
                        Column {
                            anchors.fill: parent
                            Rectangle {
                                visible: picker.original !== undefined && picker.original !== null
                                width: parent.width
                                height: visible ? parent.height / 2 : 0
                                color: visible ? picker.original : "transparent"
                                Accessible.role: Accessible.Button
                                Accessible.name: picker.originalLabel
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: picker.enabled
                                    onClicked: picker.choose(picker.original)
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: parent.height - (picker.original !== undefined && picker.original !== null ? parent.height / 2 : 0)
                                color: picker.shown
                                Accessible.role: Accessible.Graphic
                                Accessible.name: picker.currentLabel
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: Metrics.hairline
                            border.color: Theme.colors.lineStrong
                        }
                    }
                    Column {
                        width: parent.width - preview.width - parent.spacing
                        MeridianTextField {
                            id: hexField
                            objectName: "meridian-color-hex"
                            width: parent.width
                            monospace: true
                            enabled: picker.enabled
                            error: picker.hexError.length > 0
                            maximumLength: 7
                            validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                            Accessible.name: picker.hexLabel
                            onTextEdited: {
                                const parsed = picker.parseHex(text)
                                if (!parsed)
                                    return
                                picker.hexError = ""
                                picker.take(parsed)
                                picker.edited(picker.shown)
                            }
                            onAccepted: {
                                const parsed = picker.parseHex(text)
                                if (!parsed) {
                                    picker.hexError = picker.invalidHexLabel
                                    return
                                }
                                picker.take(parsed)
                                text = picker.hexOf(picker.shown)
                                picker.edited(picker.shown)
                                picker.editFinished(picker.shown)
                            }
                            // Leaving the field tidies a valid value.
                            onActiveFocusChanged: if (!activeFocus && picker.parseHex(text)) text = picker.hexOf(picker.parseHex(text))
                        }
                        MeridianText {
                            visible: picker.hexError.length > 0
                            width: parent.width
                            role: MeridianText.Caption
                            color: Theme.colors.danger
                            wrapMode: Text.Wrap
                            text: picker.hexError
                        }
                    }
                }
                MeridianSegmented {
                    width: parent.width
                    expand: true
                    label: picker.channelsLabel
                    segments: [{ value: "hsv", label: picker.hsvLabel }, { value: "rgb", label: picker.rgbLabel }]
                    value: picker.model
                    onActivated: value => picker.model = value
                }
                Repeater {
                    model: picker.model === "hsv" ? ["h", "s", "v"] : ["r", "g", "b"]
                    delegate: Column {
                        id: channel
                        required property string modelData
                        width: parent.width
                        readonly property int red: Math.round(picker.shown.r * 255)
                        readonly property int green: Math.round(picker.shown.g * 255)
                        readonly property int blue: Math.round(picker.shown.b * 255)
                        readonly property string name: ({ h: picker.hueLabel, s: picker.saturationLabel, v: picker.brightnessLabel,
                                                          r: picker.redLabel, g: picker.greenLabel, b: picker.blueLabel })[modelData]
                        readonly property real maximum: modelData === "h" ? 360 : modelData === "s" || modelData === "v" ? 100 : 255
                        readonly property real current: ({ h: picker.hue, s: Math.round(picker.saturation * 100), v: Math.round(picker.brightness * 100),
                                                           r: red, g: green, b: blue })[modelData]
                        readonly property string valueText: modelData === "h" ? picker.degreesText(Math.round(picker.hue))
                            : modelData === "s" || modelData === "v" ? picker.percentText(current) : String(current)
                        Item {
                            width: parent.width
                            height: nameText.implicitHeight
                            MeridianText { id: nameText; role: MeridianText.Caption; color: Theme.colors.inkMuted; text: channel.name }
                            MeridianText { anchors.right: parent.right; role: MeridianText.Label; text: channel.valueText }
                        }
                        MeridianSlider {
                            objectName: "meridian-color-" + channel.modelData
                            width: parent.width
                            label: channel.name
                            from: 0
                            to: channel.maximum
                            stepSize: 1
                            value: channel.current
                            enabled: picker.enabled
                            valueLabel: v => channel.valueText
                            trackColors: {
                                const r = channel.red / 255, g = channel.green / 255, b = channel.blue / 255
                                switch (channel.modelData) {
                                case "h": return [0, 60, 120, 180, 240, 300, 360].map(h => Qt.hsva((h % 360) / 360, 1, 1, 1))
                                case "s": return [Qt.hsva(picker.hue / 360, 0, picker.brightness, 1), Qt.hsva(picker.hue / 360, 1, picker.brightness, 1)]
                                case "v": return [Qt.hsva(picker.hue / 360, picker.saturation, 0, 1), Qt.hsva(picker.hue / 360, picker.saturation, 1, 1)]
                                case "r": return [Qt.rgba(0, g, b, 1), Qt.rgba(1, g, b, 1)]
                                case "g": return [Qt.rgba(r, 0, b, 1), Qt.rgba(r, 1, b, 1)]
                                default: return [Qt.rgba(r, g, 0, 1), Qt.rgba(r, g, 1, 1)]
                                }
                            }
                            onMoved: {
                                switch (channel.modelData) {
                                case "h": picker.change(value, picker.saturation, picker.brightness); break
                                case "s": picker.change(picker.hue, value / 100, picker.brightness); break
                                case "v": picker.change(picker.hue, picker.saturation, value / 100); break
                                case "r": picker.setRgb(value, channel.green, channel.blue); break
                                case "g": picker.setRgb(channel.red, value, channel.blue); break
                                default: picker.setRgb(channel.red, channel.green, value)
                                }
                            }
                            onPressedChanged: if (!pressed) picker.editFinished(picker.shown)
                        }
                    }
                }
            }
        }
    }
}
