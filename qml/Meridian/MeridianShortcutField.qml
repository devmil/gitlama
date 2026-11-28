pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T

// Records a key combination (Flutter: MeridianShortcutField). Controlled:
// the consumer owns `recording`, validation and storage. Activating asks to
// record (`recordRequested`); while `recording` the next real key-down with
// its modifiers is reported as `recorded(key, modifiers)` (Qt key codes, no
// typed text kept). Escape, Tab and losing focus cancel
// (`cancelRecording`). Bound `keys` show as keycaps with a clear button.
Item {
    id: root

    property string label
    property string emptyLabel
    property string recordingLabel
    property string preparingLabel
    property string clearLabel
    property var keys: []
    property bool recording: false
    property bool preparing: false
    property bool showLabel: true
    property bool clearable: true
    /// Why the field cannot record; read to assistive technology.
    property string disabledReason
    /// A conflict or failure line below the field, announced when it appears.
    property string conflictText

    signal recordRequested()
    signal recorded(int key, int modifiers)
    signal cancelRecording()
    signal cleared()

    readonly property bool active: enabled && !preparing
    readonly property string valueText: preparing ? preparingLabel
                                        : recording ? recordingLabel
                                        : keys.length === 0 ? emptyLabel : keys.join(" + ")
    property bool _cancelRequested: false

    implicitWidth: 240
    implicitHeight: column.implicitHeight

    function _cancel() {
        if (!recording || _cancelRequested)
            return
        _cancelRequested = true
        cancelRecording()
    }

    onRecordingChanged: {
        if (recording && active) {
            _cancelRequested = false
            field.forceActiveFocus()
        }
    }
    onActiveChanged: if (recording && !active) Qt.callLater(_cancel)

    Column {
        id: column
        width: root.width
        spacing: Theme.space.s3

        MeridianText {
            visible: root.showLabel
            width: parent.width
            role: MeridianText.BodyStrong
            text: root.label
        }
        Item {
            width: parent.width
            height: field.height
            T.AbstractButton {
                id: field
                width: parent.width - (clear.visible ? clear.width + Theme.space.s2 : 0)
                implicitHeight: Math.max(Theme.size.control, content.implicitHeight + 2 * Theme.space.s3)
                enabled: root.active
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true
                Accessible.role: Accessible.Button
                Accessible.name: root.label
                Accessible.description: root.disabledReason.length > 0 && !root.active ? root.disabledReason : root.valueText

                onClicked: root.recording ? root._cancel() : root.recordRequested()
                onActiveFocusChanged: if (!activeFocus && root.recording) root._cancel()

                Keys.onPressed: event => {
                    if (!root.recording) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            root.recordRequested()
                            event.accepted = true
                        }
                        return
                    }
                    event.accepted = true
                    if (root._cancelRequested || event.isAutoRepeat)
                        return
                    switch (event.key) {
                    case Qt.Key_Control: case Qt.Key_Shift: case Qt.Key_Alt: case Qt.Key_Meta:
                    case Qt.Key_AltGr: case Qt.Key_Super_L: case Qt.Key_Super_R: case Qt.Key_Hyper_L:
                    case Qt.Key_Hyper_R: case Qt.Key_CapsLock: case Qt.Key_unknown:
                        return
                    }
                    const command = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
                    if (!command && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
                        root._cancel()
                        event.accepted = false
                        return
                    }
                    if (!command && !(event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Escape) {
                        root._cancel()
                        return
                    }
                    root.recorded(event.key, event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier))
                }

                background: Rectangle {
                    radius: Theme.radius.md
                    color: field.hovered && field.enabled && !root.recording ? Theme.colors.paneHover : Theme.colors.pane
                    border.width: 1
                    border.color: root.recording && root.active ? Theme.colors.focus
                                  : root.active ? Theme.colors.controlEdge : Theme.colors.line
                    Behavior on color { ColorAnimation { duration: Motion.hoverFor(field.hovered) } }
                    MeridianFocusRing {
                        target: parent
                        shown: field.visualFocus && !root.recording
                        targetRadius: Theme.radius.md
                    }
                }
                contentItem: Item {
                    implicitHeight: content.implicitHeight
                    Item {
                        id: content
                        x: Theme.space.s4
                        width: parent.width - 2 * Theme.space.s4
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: caps.visible ? caps.implicitHeight : valueLabel.implicitHeight
                        height: implicitHeight
                        Flow {
                            id: caps
                            visible: !root.recording && !root.preparing && root.keys.length > 0
                            width: parent.width
                            spacing: Theme.space.s2
                            Repeater {
                                model: caps.visible ? root.keys : []
                                delegate: MeridianKbd {
                                    required property string modelData
                                    keys: [modelData]
                                }
                            }
                        }
                        MeridianText {
                            id: valueLabel
                            visible: !caps.visible
                            width: parent.width
                            text: root.valueText
                            color: root.active ? Theme.colors.inkMuted : Theme.colors.inkFaint
                        }
                    }
                }
            }
            MeridianIconButton {
                id: clear
                visible: root.clearable && root.keys.length > 0
                x: parent.width - width
                anchors.verticalCenter: field.verticalCenter
                iconName: "x"
                text: root.clearLabel
                enabled: root.enabled && !root.preparing
                onClicked: root.cleared()
            }
        }
        MeridianText {
            visible: root.conflictText.length > 0
            width: parent.width
            role: MeridianText.Caption
            color: Theme.colors.danger
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: root.conflictText
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }
    }
}
