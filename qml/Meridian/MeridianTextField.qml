import QtQuick
import QtQuick.Templates as T

// Single-line text input (Flutter: MeridianTextField). Keep the label
// outside the field: pair it with a MeridianText label or a settings row,
// and set `Accessible.name`. Never a floating label.
//
// `Default` has a `control-edge` edge; focus paints a `focus` edge plus a 1px
// halo. `Search` is a filled `pane-alt` well with no edge until focused, for
// filters in headers and toolbars. `Plain` has no edge, well or ring (it
// types inside a surface that is already a field, like a recipient field).
T.TextField {
    id: control

    enum Variant {
        Default,
        Search,
        Plain
    }

    property int variant: MeridianTextField.Default
    property int controlSize: MeridianButton.Regular
    property string iconName: variant === MeridianTextField.Search ? "search" : ""
    /// Adds a clear button while the field holds text (its accessible name).
    property string clearLabel
    property string trailingText
    property bool error: false
    property bool monospace: false
    /// Increment to shake the field once (a rejected submit).
    property int rejectCount: 0
    /// Items after the clear button (a search-options menu button).
    property alias trailingContent: trailingSlot.data

    readonly property real extent: controlSize === MeridianButton.Small ? Theme.size.controlSmall : Theme.size.control
    readonly property bool plain: variant === MeridianTextField.Plain
    readonly property bool search: variant === MeridianTextField.Search
    readonly property real leadingWidth: iconName.length > 0 ? Theme.size.iconSmall + Theme.space.s3 : 0
    readonly property real trailingWidth: (clearButton.visible ? clearButton.width + Theme.space.s1 : 0) + (trailingLabel.visible ? trailingLabel.implicitWidth + Theme.space.s3 : 0)
        + (trailingSlot.width > 0 ? trailingSlot.width + Theme.space.s1 : 0)

    hoverEnabled: true
    implicitWidth: Math.max(Metrics.textFieldMinWidth, contentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(extent, Theme.type.bodyLineHeight + 2)
    leftPadding: (plain ? 0 : Theme.space.s4) + leadingWidth
    rightPadding: (plain ? 0 : Theme.space.s4) + trailingWidth
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    font: monospace ? Theme.type.code : Theme.type.body
    color: enabled ? Theme.colors.ink : Theme.colors.inkFaint
    placeholderTextColor: Theme.colors.inkFaint
    selectionColor: Theme.colors.accentSoft
    selectedTextColor: Theme.colors.ink
    selectByMouse: true
    persistentSelection: false

    Accessible.role: Accessible.EditableText
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            textMenu.openAtCursor()
            event.accepted = true
        }
    }
    Accessible.description: error ? Accessible.description : ""

    onRejectCountChanged: if (rejectCount > 0)
        shake.restart()

    transform: Translate {
        id: offset
    }
    SequentialAnimation {
        id: shake
        loops: Motion.shakeCycles
        NumberAnimation {
            target: offset
            property: "x"
            to: -Motion.shakeFieldDistance
            duration: Motion.shakeField / (4 * Motion.shakeCycles)
        }
        NumberAnimation {
            target: offset
            property: "x"
            to: Motion.shakeFieldDistance
            duration: Motion.shakeField / (2 * Motion.shakeCycles)
        }
        NumberAnimation {
            target: offset
            property: "x"
            to: 0
            duration: Motion.shakeField / (4 * Motion.shakeCycles)
        }
    }

    background: Item {
        implicitHeight: control.extent
        // The template draws no placeholder; it sits where the text starts
        // and elides before the trailing controls.
        Text {
            z: 1
            visible: control.text.length === 0 && control.preeditText.length === 0
            x: control.leftPadding
            width: Math.max(0, parent.width - control.leftPadding - control.rightPadding)
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            font: control.font
            color: control.placeholderTextColor
            text: control.placeholderText
            Accessible.ignored: true
        }
        Rectangle {
            id: well
            anchors.fill: parent
            visible: !control.plain
            radius: Theme.radius.md
            color: control.search && !control.activeFocus ? Theme.colors.paneAlt : Theme.colors.pane
            border.width: 1
            border.color: control.error ? Theme.colors.danger : control.activeFocus ? Theme.colors.focus : control.search ? Theme.clear(Theme.colors.controlEdge) : control.hovered ? Theme.colors.inkFaint : Theme.colors.controlEdge
            Behavior on color {
                ColorAnimation {
                    duration: Motion.quick
                }
            }
            Behavior on border.color {
                ColorAnimation {
                    duration: Motion.quick
                }
            }
        }
        Rectangle {
            // The 1px focus halo.
            visible: !control.plain
            anchors.fill: parent
            anchors.margins: -1
            radius: Theme.radius.md + 1
            color: "transparent"
            border.width: 1
            border.color: control.error ? Theme.colors.danger : Theme.colors.focus
            opacity: control.activeFocus ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fade(Motion.quick)
                }
            }
        }
        MeridianIcon {
            visible: control.iconName.length > 0
            x: (control.plain ? 0 : Theme.space.s4)
            anchors.verticalCenter: parent.verticalCenter
            name: control.iconName
            iconSize: MeridianIcon.Small
            color: Theme.colors.inkMuted
        }
    }

    // Above the editable text, so its buttons receive the pointer.
    Row {
        z: 1
        anchors.right: parent.right
        anchors.rightMargin: control.plain ? 0 : Theme.space.s2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s1
        MeridianText {
            id: trailingLabel
            visible: control.trailingText.length > 0
            role: MeridianText.Caption
            text: control.trailingText
            color: Theme.colors.inkMuted
            anchors.verticalCenter: parent.verticalCenter
            font.features: {
                "tnum": 1
            }
        }
        MeridianIconButton {
            id: clearButton
            objectName: "textFieldClearButton"
            visible: control.clearLabel.length > 0 && control.length > 0 && control.enabled
            iconName: "x"
            text: control.clearLabel
            controlSize: MeridianButton.Small
            surfaceColor: control.search && !control.activeFocus ? Theme.colors.paneAlt : Theme.colors.pane
            focusPolicy: Qt.NoFocus
            anchors.verticalCenter: parent.verticalCenter
            onClicked: {
                control.clear();
                control.forceActiveFocus();
            }
        }
        Row {
            id: trailingSlot
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s1
        }
    }

    MeridianTextMenu {
        id: textMenu
    }
}
