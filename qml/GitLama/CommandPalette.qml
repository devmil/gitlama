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
    /// The configured custom commands, listed after the matching commands.
    readonly property var customCommands: ((Store.settings && Store.settings.tools ? Store.settings.tools.configured : null) ?? [])
        .filter(tool => tool.kind === "custom")
    /// Why custom commands cannot run here (a remote host's tab), or "".
    readonly property string customReason: reasonOf("showIntegrations")
    readonly property var results: {
        const term = query.trim().toLowerCase()
        return Commands.registry
            .filter(command => term.length === 0 || Commands.label(command.id).toLowerCase().indexOf(term) >= 0)
            .map(command => ({ id: command.id, custom: false, group: "commands" }))
            .concat(customCommands.map(tool => ({ id: tool.id, custom: true, group: "custom" })))
    }
    signal run(string id)

    /// Increments with each opening: the rows enter once per opening (NH-6).
    property int openings: 0
    // NH-6: opened from the toolbar, the surface grows out of the palette button's rect and
    // pill radius on `spring-snappy` while its content fades in after `paletteContentDelay`;
    // closed without running a command it shrinks back over `motion-dialog`. Opened from the
    // keyboard (or under reduce motion) it uses the dialog entrance.
    property rect originRect: Qt.rect(0, 0, 0, 0)
    readonly property bool morphing: originRect.width > 0 && !Motion.reduced
    /// 0 at the button, 1 at the palette's own place.
    property real morph: 1
    property real contentOpacity: 1
    property bool _ran: false
    readonly property real _scaleX: morphing ? 1 + (originRect.width / Math.max(1, width) - 1) * (1 - morph) : 1
    readonly property real _scaleY: morphing ? 1 + (originRect.height / Math.max(1, height) - 1) * (1 - morph) : 1
    readonly property real _shiftX: morphing ? (originRect.x + originRect.width / 2 - (x + width / 2)) * (1 - morph) : 0
    readonly property real _shiftY: morphing ? (originRect.y + originRect.height / 2 - (y + height / 2)) * (1 - morph) : 0
    readonly property real _radius: morphing
        ? (originRect.height / 2 * (1 - morph) + Theme.radius.lg * morph) / Math.max(0.01, Math.min(_scaleX, _scaleY))
        : Theme.radius.lg

    function show(origin) {
        originRect = origin ? Qt.rect(origin.x, origin.y, origin.width, origin.height) : Qt.rect(0, 0, 0, 0)
        _ran = false
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
        if (!command)
            return
        if (command.custom) {
            if (customReason.length > 0 || !Store.workflows)
                return
            _ran = true
            close()
            Store.workflows.runIntegration(command.id)
            return
        }
        if (reasonOf(command.id).length > 0)
            return
        _ran = true
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
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: commandPalette.morphing ? 0 : Motion.fade(Motion.dialog) }
            NumberAnimation { property: "scale"; from: commandPalette.morphing ? 1 : Motion.dialogEnterScale; to: 1; duration: commandPalette.morphing ? 0 : Motion.dialog; easing.type: Easing.OutCubic }
            NumberAnimation {
                target: commandPalette; property: "morph"; from: commandPalette.morphing ? 0 : 1; to: 1
                duration: !commandPalette.morphing ? 0 : Motion.snappy.duration
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve
            }
            SequentialAnimation {
                PropertyAction { target: commandPalette; property: "contentOpacity"; value: commandPalette.morphing ? 0 : 1 }
                PauseAnimation { duration: commandPalette.morphing ? GitLamaLayout.paletteContentDelay : 0 }
                NumberAnimation {
                    target: commandPalette; property: "contentOpacity"; to: 1
                    duration: commandPalette.morphing ? Motion.quick : 0
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard
                }
            }
        }
    }
    exit: Transition {
        ParallelAnimation {
            // Shrinks back into the button unless a command ran; then it fades.
            NumberAnimation {
                target: commandPalette; property: "morph"; to: commandPalette.morphing && !commandPalette._ran ? 0 : 1
                duration: commandPalette.morphing && !commandPalette._ran ? Motion.dialog : 0
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve
            }
            NumberAnimation {
                target: commandPalette; property: "contentOpacity"; to: 0
                duration: commandPalette.morphing && !commandPalette._ran ? Motion.exit : 0
            }
            NumberAnimation {
                property: "opacity"; from: 1; to: 0
                duration: commandPalette.morphing && !commandPalette._ran ? Motion.dialog : Motion.fade(Motion.exit)
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve
            }
        }
    }

    background: MeridianSurface {
        radius: commandPalette._radius
        transform: [
            Scale { origin.x: commandPalette.width / 2; origin.y: commandPalette.height / 2; xScale: commandPalette._scaleX; yScale: commandPalette._scaleY },
            Translate { x: commandPalette._shiftX; y: commandPalette._shiftY }
        ]
    }

    contentItem: Item {
        opacity: commandPalette.contentOpacity
        transform: [
            Scale { origin.x: commandPalette.width / 2; origin.y: commandPalette.height / 2; xScale: commandPalette._scaleX; yScale: commandPalette._scaleY },
            Translate { x: commandPalette._shiftX; y: commandPalette._shiftY }
        ]
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
            section.property: "group"
            section.delegate: Item {
                id: groupHeader
                required property string section
                width: list.width - list.leftMargin - list.rightMargin
                height: groupLabel.implicitHeight + Theme.space.s4 + Theme.space.s2
                MeridianText {
                    id: groupLabel
                    x: Theme.space.s4
                    y: Theme.space.s4
                    role: MeridianText.Overline
                    color: Theme.colors.inkMuted
                    text: (groupHeader.section === "custom" ? L10n.t("integrationCustom")
                                                             : L10n.t("commandGroupCommands")).toUpperCase()
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
                readonly property bool custom: modelData.custom === true
                readonly property string reason: custom ? commandPalette.customReason : commandPalette.reasonOf(modelData.id)
                width: list.width - list.leftMargin - list.rightMargin
                text: custom ? modelData.id : Commands.label(modelData.id)
                match: commandPalette.query
                selected: index === commandPalette.selectedIndex
                islandFocused: true
                enabled: reason.length === 0
                subtitle: reason.length > 0 ? Commands.reasonText(reason) : custom ? L10n.t("integrationCustom") : ""
                focusPolicy: Qt.NoFocus
                leading: Component {
                    MeridianIcon { name: row.custom ? "command" : Commands.icon(row.modelData.id) }
                }
                trailing: custom || Commands.shortcutLabel(modelData.id).length === 0 ? null : keycap
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
