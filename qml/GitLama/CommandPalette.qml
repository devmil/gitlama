pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls.Basic as C
import Meridian

// The command palette: every command,
// filtered as the query is typed, with why one cannot run and its
// shortcut. Up and Down move, Enter runs, Escape closes.
T.Popup {
    id: commandPalette

    property string query: ""
    property int selectedIndex: 0
    readonly property var availability: Store.actions ? Store.actions.availability : ({})
    readonly property var results: {
        const term = query.trim().toLowerCase()
        return Commands.registry.filter(command => term.length === 0 || Commands.label(command.id).toLowerCase().indexOf(term) >= 0)
    }
    signal run(string id)

    /// Increments with each opening: the rows enter once per opening (NH-6).
    property int openings: 0
    function show() {
        openings += 1
        query = ""
        field.text = ""
        selectedIndex = 0
        open()
        field.forceActiveFocus()
    }
    function reasonOf(id) {
        return Commands.reason(id, availability)
    }
    function activate(index) {
        const command = results[index]
        if (!command || reasonOf(command.id).length > 0)
            return
        close()
        run(command.id)
    }
    function move(delta) {
        if (results.length === 0)
            return
        selectedIndex = (selectedIndex + delta + results.length) % results.length
        list.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    parent: T.Overlay.overlay
    modal: true
    focus: true
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutside
    anchors.centerIn: parent
    width: Math.min(GitLamaLayout.paletteWidth, (parent ? parent.width : 800) - 2 * Theme.space.s6)
    height: (parent ? parent.height : 600) * GitLamaLayout.paletteMaxHeightFraction
    padding: 0

    T.Overlay.modal: Rectangle { color: Theme.colors.scrim }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.fade(Motion.dialog) }
            NumberAnimation { property: "scale"; from: Motion.dialogEnterScale; to: 1; duration: Motion.dialog; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.fade(Motion.exit) }
    }

    background: MeridianSurface {
        radius: Theme.radius.lg
    }

    contentItem: Item {
        Keys.onUpPressed: commandPalette.move(-1)
        Keys.onDownPressed: commandPalette.move(1)
        Keys.onReturnPressed: commandPalette.activate(commandPalette.selectedIndex)
        Keys.onEnterPressed: commandPalette.activate(commandPalette.selectedIndex)

        Item {
            id: queryRow
            width: parent.width
            height: GitLamaLayout.paletteQueryHeight
            MeridianIcon {
                id: glyph
                x: Theme.space.s6
                anchors.verticalCenter: parent.verticalCenter
                name: "command"
                color: Theme.colors.inkMuted
            }
            MeridianTextField {
                id: field
                objectName: "command-palette-query"
                x: glyph.x + glyph.width + Theme.space.s4
                width: escapeKey.x - x - Theme.space.s4
                anchors.verticalCenter: parent.verticalCenter
                variant: MeridianTextField.Plain
                placeholderText: L10n.t("commandPaletteSearch")
                Accessible.name: L10n.t("commandPaletteSearch")
                onTextEdited: { commandPalette.query = text; commandPalette.selectedIndex = 0 }
                Keys.onUpPressed: commandPalette.move(-1)
                Keys.onDownPressed: commandPalette.move(1)
                onAccepted: commandPalette.activate(commandPalette.selectedIndex)
            }
            MeridianKbd {
                id: escapeKey
                x: parent.width - width - Theme.space.s6
                anchors.verticalCenter: parent.verticalCenter
                keys: ["esc"]
            }
        }
        MeridianHairline { id: topRule; anchors.top: queryRow.bottom; width: parent.width }

        MeridianEmptyState {
            visible: commandPalette.results.length === 0
            anchors.top: topRule.bottom
            anchors.bottom: footerBar.top
            width: parent.width
            compact: true
            title: L10n.tn("commandPaletteNoMatch", { query: commandPalette.query.trim() })
        }
        ListView {
            id: list
            visible: commandPalette.results.length > 0
            anchors.top: topRule.bottom
            anchors.bottom: footerBar.top
            width: parent.width
            topMargin: Theme.space.s2
            bottomMargin: Theme.space.s2
            leftMargin: Theme.space.s2
            rightMargin: Theme.space.s2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: commandPalette.results
            MeridianWheelScroll { flickable: list }
            C.ScrollBar.vertical: MeridianScrollBar {}
            header: Item {
                width: list.width - list.leftMargin - list.rightMargin
                height: groupLabel.implicitHeight + Theme.space.s4 + Theme.space.s2
                MeridianText {
                    id: groupLabel
                    x: Theme.space.s4
                    y: Theme.space.s4
                    role: MeridianText.Overline
                    color: Theme.colors.inkMuted
                    text: L10n.t("commandGroupCommands").toUpperCase()
                }
            }
            delegate: MeridianListRow {
                id: row
                required property var modelData
                required property int index
                // The first rows fade in after the surface, 18 ms apart (NH-6).
                readonly property string entranceKey: "command-palette|" + commandPalette.openings + "|" + modelData.id
                property string _enteredKey: ""
                property real _enter: 1
                opacity: _enter
                Component.onCompleted: _enterOnce()
                onEntranceKeyChanged: _enterOnce()
                function _enterOnce() {
                    if (entranceKey === _enteredKey)
                        return
                    _enteredKey = entranceKey
                    if (!MeridianMotionMemory.markSeen(entranceKey) || Motion.reduced || index > 5)
                        return
                    rowEntrance.stop()
                    _enter = 0
                    rowWait.duration = GitLamaLayout.paletteRowsDelay + Motion.staggerDelay(index)
                    rowEntrance.restart()
                }
                SequentialAnimation {
                    id: rowEntrance
                    PauseAnimation { id: rowWait }
                    NumberAnimation { target: row; property: "_enter"; to: 1; duration: Motion.quick; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
                }
                readonly property string reason: commandPalette.reasonOf(modelData.id)
                width: list.width - list.leftMargin - list.rightMargin
                text: Commands.label(modelData.id)
                match: commandPalette.query
                selected: index === commandPalette.selectedIndex
                islandFocused: true
                enabled: reason.length === 0
                subtitle: reason.length > 0 ? Commands.reasonText(reason) : ""
                focusPolicy: Qt.NoFocus
                leading: Component {
                    MeridianIcon { name: Commands.icon(row.modelData.id) }
                }
                trailing: Commands.shortcutLabel(modelData.id).length === 0 ? null : keycap
                Component {
                    id: keycap
                    MeridianKbd { keys: [Commands.shortcutLabel(row.modelData.id)]; onAccent: row.solid }
                }
                onClicked: commandPalette.activate(index)
                HoverHandler { onHoveredChanged: if (hovered) commandPalette.selectedIndex = row.index }
            }
        }

        Rectangle {
            id: footerBar
            anchors.bottom: parent.bottom
            width: parent.width
            height: hints.implicitHeight + 2 * Theme.space.s4
            color: Theme.colors.paneAlt
            radius: Theme.radius.lg
            Rectangle { width: parent.width; height: parent.radius; color: parent.color }
            MeridianHairline { width: parent.width }
            Flow {
                id: hints
                x: Theme.space.s6
                y: Theme.space.s4
                width: parent.width - 2 * Theme.space.s6
                spacing: Theme.space.s6
                Repeater {
                    model: [[["↑", "↓"], "galleryPaletteMove"], [["↵"], "galleryPaletteRun"],
                            [[Store.isMac ? "⌘" : "Ctrl", "↵"], "galleryPaletteBackground"], [["tab"], "galleryPaletteScope"]]
                    delegate: Row {
                        required property var modelData
                        spacing: Theme.space.s3
                        MeridianKbd { keys: parent.modelData[0] }
                        MeridianText { text: L10n.t(parent.modelData[1]); anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }
    }
}
