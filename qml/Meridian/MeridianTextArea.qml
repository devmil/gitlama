import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls.Basic as C

// Multi-line text input (Flutter: MeridianTextField with several lines):
// the Default field's `control-edge` edge, focus edge and halo, `space-3`
// padding. It grows with its text between `minimumLines` and
// `maximumLines` and scrolls inside beyond that; set an explicit height to
// fill a space instead. Pair it with a label and set `Accessible.name`.
Item {
    id: root

    property alias text: area.text
    property alias placeholderText: area.placeholderText
    property alias readOnly: area.readOnly
    property alias textArea: area
    property bool error: false
    property bool monospace: false
    property int minimumLines: 2
    property int maximumLines: 5
    readonly property real lineHeight: monospace ? Theme.type.codeLineHeight : Theme.type.bodyLineHeight
    readonly property real chrome: 2 * Theme.space.s3 + 2

    signal editingFinished()

    implicitWidth: Metrics.textFieldMinWidth
    implicitHeight: chrome + lineHeight * Math.max(minimumLines, Math.min(maximumLines, area.lineCount))
    activeFocusOnTab: false

    function forceActiveFocus() { area.forceActiveFocus() }

    Rectangle {
        id: well
        anchors.fill: parent
        radius: Theme.radius.md
        color: root.enabled ? Theme.colors.pane : Theme.colors.paneAlt
        border.width: 1
        border.color: root.error ? Theme.colors.danger : area.activeFocus ? Theme.colors.focus
            : hover.hovered ? Theme.colors.inkFaint : Theme.colors.controlEdge
        Behavior on border.color { ColorAnimation { duration: Motion.quick } }
    }
    Rectangle {
        // The 1px focus halo.
        anchors.fill: parent
        anchors.margins: -1
        radius: Theme.radius.md + 1
        color: "transparent"
        border.width: 1
        border.color: root.error ? Theme.colors.danger : Theme.colors.focus
        opacity: area.activeFocus ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fade(Motion.quick) } }
    }
    HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 1
        clip: true
        contentWidth: width
        contentHeight: area.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        C.ScrollBar.vertical: MeridianScrollBar {}
        MeridianWheelScroll { flickable: flick }

        T.TextArea {
            id: area
            width: flick.width
            implicitHeight: Math.max(flick.height, contentHeight + topPadding + bottomPadding)
            leftPadding: Theme.space.s4
            rightPadding: Theme.space.s4
            topPadding: Theme.space.s3
            bottomPadding: Theme.space.s3
            wrapMode: TextEdit.Wrap
            font: root.monospace ? Theme.type.code : Theme.type.body
            color: enabled ? Theme.colors.ink : Theme.colors.inkFaint
            placeholderTextColor: Theme.colors.inkFaint
            selectionColor: Theme.colors.accentSoft
            selectedTextColor: Theme.colors.ink
            selectByMouse: true
            activeFocusOnTab: true
            Accessible.role: Accessible.EditableText
            Accessible.name: root.Accessible.name
            onEditingFinished: root.editingFinished()
            // Keeps the cursor in view while typing.
            onCursorRectangleChanged: {
                if (cursorRectangle.y < flick.contentY)
                    flick.contentY = cursorRectangle.y
                else if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height)
                    flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height + bottomPadding
            }

            Text {
                visible: area.text.length === 0 && area.preeditText.length === 0
                x: area.leftPadding
                y: area.topPadding
                width: area.width - area.leftPadding - area.rightPadding
                wrapMode: Text.Wrap
                font: area.font
                color: area.placeholderTextColor
                text: area.placeholderText
                Accessible.ignored: true
            }
        }
    }
}
