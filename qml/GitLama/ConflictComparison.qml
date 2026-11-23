pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// Current and incoming next to each other: a header with the focused conflict, the resolved count and
// navigation, each side's whole-file choice, then the rows, each conflict
// under its toolbar. Clicking a side's lines takes them (or takes them
// back); the result follows.
Item {
    id: root

    property var file: null
    property var conflictState: ({})
    readonly property bool busy: conflictState.busy === true
    readonly property int focusedRegion: file ? (file.focusedRegion ?? 0) : 0
    readonly property var blocks: file ? (file.blocks ?? []) : []
    readonly property var blockRows: file ? (file.blockRows ?? []) : []
    readonly property int markers: file ? (file.markers ?? 0) : 0
    readonly property real rowHeight: GitLamaLayout.conflictComparisonRowHeight
    readonly property real toolbarHeight: GitLamaLayout.conflictRegionToolbarHeight
    readonly property alias view: list
    /// The region and side under the pointer; "both" lights both sides.
    property int hoveredRegion: -1
    property string hoveredSide: ""

    signal scrolled()

    /// Content offsets of each region, toolbar included: [{top, bottom}].
    function regionExtents() {
        const extents = []
        for (let i = 0; i < blockRows.length; ++i) {
            const first = blockRows[i][0]
            const count = blockRows[i][1]
            const top = rowTop(first)
            extents.push({ top: top, bottom: count === 0 ? top : rowTop(first + count) })
        }
        return extents
    }

    // ---------------------------------------------------------------- wrapping

    /// Long lines wrap (the shared diff choice) instead of scrolling sideways together.
    readonly property bool wrap: Store.appearance.diffWrap === true
    readonly property real wrapLineHeight: Theme.type.codeLineHeight
    /// Each row's line height, and each row's top in the list (toolbars included), measured
    /// for every row so scrolling to a region and following the result stay exact.
    property var _lineHeights: []
    property var _tops: []
    function lineHeightAt(index) {
        return wrap ? (_lineHeights[index] ?? rowHeight) : rowHeight
    }
    function rowTop(index) {
        if (index <= 0)
            return 0
        return _tops[Math.min(index, _tops.length - 1)] ?? 0
    }
    FontMetrics { id: codeMetrics; font: Theme.type.code }
    function _visualLines(text) {
        if (text.length === 0 || textWidth <= 0)
            return 1
        const column = Math.max(1, codeMetrics.averageCharacterWidth)
        const perLine = Math.max(1, Math.floor(textWidth / column))
        const columns = Math.round(codeMetrics.advanceWidth(text) / column)
        return Math.max(1, Math.ceil(columns / perLine))
    }
    function _measure() {
        const model = Store.conflictRows
        const count = model ? model.count() : 0
        const heights = []
        const tops = [0]
        const padding = Math.max(0, rowHeight - wrapLineHeight)
        let y = 0
        for (let i = 0; i < count; ++i) {
            const row = model.get(i)
            let height = rowHeight
            if (wrap && row) {
                const lines = Math.max(_visualLines(row.current ?? ""), _visualLines(row.incoming ?? ""))
                height = Math.max(rowHeight, lines * wrapLineHeight + padding)
            }
            heights.push(height)
            y += height + (row && row.first ? toolbarHeight : 0)
            tops.push(y)
        }
        _lineHeights = heights
        _tops = tops
    }
    onWrapChanged: Qt.callLater(root._measure)
    onTextWidthChanged: if (wrap) Qt.callLater(root._measure)
    Connections {
        target: Store.conflictRows
        function onCountChanged() {
            Qt.callLater(root._measure)
            colourLater.restart()
        }
    }

    // ---------------------------------------------------------------- syntax

    // Each side as the comparison shows it, one line per row that shows the side, coloured by
    // the file's grammar once it rests for `syntaxIdle`.
    property var _currentLineOf: []
    property var _incomingLineOf: []
    property var _currentRuns: ({})
    property var _incomingRuns: ({})
    property int _colourGeneration: 0
    property string _colouredKey: ""
    readonly property string _fileKey: file ? (file.key ?? "") + "|" + blocks.length : ""
    on_FileKeyChanged: {
        colourLater.restart()
        Qt.callLater(root._measure)
    }
    Timer {
        id: colourLater
        interval: GitLamaLayout.syntaxIdle
        onTriggered: root._colourSides()
    }
    function _colourSides() {
        const model = Store.conflictRows
        const count = model ? model.count() : 0
        const key = _fileKey + "|" + count
        if (key === _colouredKey)
            return
        _colouredKey = key
        const current = [], incoming = []
        const currentLineOf = [], incomingLineOf = []
        for (let i = 0; i < count; ++i) {
            const row = model.get(i)
            if (row && row.currentLine !== null && row.currentLine !== undefined) {
                current.push(row.current ?? "")
                currentLineOf.push(current.length)
            } else {
                currentLineOf.push(0)
            }
            if (row && row.incomingLine !== null && row.incomingLine !== undefined) {
                incoming.push(row.incoming ?? "")
                incomingLineOf.push(incoming.length)
            } else {
                incomingLineOf.push(0)
            }
        }
        _currentLineOf = currentLineOf
        _incomingLineOf = incomingLineOf
        _currentRuns = ({})
        _incomingRuns = ({})
        if (!file || file.kind !== "text" || count === 0)
            return
        _colourGeneration += 1
        const path = file.path ?? ""
        Store.conflicts.colourText("current", _colourGeneration, path, current.join("\n"))
        Store.conflicts.colourText("incoming", _colourGeneration, path, incoming.join("\n"))
    }
    Connections {
        target: Store.conflicts
        function onTextColoured(view, generation, firstLine, lines) {
            if (generation !== root._colourGeneration || (view !== "current" && view !== "incoming"))
                return
            const runs = Object.assign({}, view === "current" ? root._currentRuns : root._incomingRuns)
            for (let i = 0; i < lines.length; ++i)
                if (lines[i].length > 0)
                    runs[firstLine + i] = lines[i]
            if (view === "current")
                root._currentRuns = runs
            else
                root._incomingRuns = runs
        }
    }
    /// The styled text of row `index`'s side, or "".
    function styledAt(index, current, text) {
        const line = (current ? _currentLineOf : _incomingLineOf)[index] ?? 0
        if (line === 0)
            return ""
        return SyntaxStyle.styled(text, (current ? _currentRuns : _incomingRuns)[line])
    }

    function choiceLabel(choice) {
        return L10n.t({ current: "conflictTakeCurrent", incoming: "conflictTakeIncoming", both: "conflictTakeBoth" }[choice])
    }
    function removeLabel(choice) {
        return L10n.t({ current: "conflictRemoveCurrent", incoming: "conflictRemoveIncoming", both: "conflictRemoveBoth" }[choice])
    }

    // The header: the focused conflict, wrap, the resolved count, navigation.
    MeridianSectionHeader {
        id: header
        width: parent.width
        size: MeridianSectionHeader.Small
        divider: false
        color: Theme.colors.paneAlt
        title: root.blocks.length === 0 ? L10n.t("conflictComparisonTitle")
            : L10n.tn("conflictRegionNumber", { number: root.focusedRegion + 1 })
        MeridianIconButton {
            objectName: "conflict-wrap"
            iconName: "wrap"
            text: L10n.t("diffWrap")
            active: root.wrap
            controlSize: MeridianButton.Small
            onClicked: Store.app.updateAppearance({ diffWrap: !root.wrap })
        }
        // The resolved regions roll as they change (NM-75).
        MeridianRollingNumber {
            visible: root.blocks.length > 0
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            role: MeridianText.Label
            color: root.markers === 0 ? Theme.colors.accent : Theme.colors.danger
            value: Math.max(0, root.blocks.length - root.markers)
            format: count => count + "/" + root.blocks.length
        }
        MeridianIconButton {
            iconName: "chevron-up"
            text: L10n.t("conflictPreviousRegion")
            controlSize: MeridianButton.Small
            enabled: root.focusedRegion > 0
            onClicked: root.showRegion(root.focusedRegion - 1)
        }
        MeridianIconButton {
            iconName: "chevron-down"
            text: L10n.t("conflictNextRegion")
            controlSize: MeridianButton.Small
            enabled: root.focusedRegion < root.blocks.length - 1
            onClicked: root.showRegion(root.focusedRegion + 1)
        }
    }

    // Each side's whole-file choice.
    Row {
        id: sources
        y: header.height
        width: parent.width
        height: GitLamaLayout.conflictRegionToolbarHeight
        Repeater {
            model: ["current", "incoming"]
            delegate: Rectangle {
                id: sourceCell
                required property string modelData
                required property int index
                readonly property bool current: modelData === "current"
                readonly property bool deletes: root.file !== null && !(current ? root.file.currentPresent : root.file.incomingPresent)
                readonly property bool chosen: root.file !== null && root.file.side === modelData
                readonly property color sideColor: current ? GitColors.sideOurs : GitColors.sideTheirs
                readonly property string action: chosen ? L10n.t(deletes ? "conflictKeepingDeletion" : "conflictUsingThisFile")
                    : deletes ? L10n.t("conflictKeepDeletion") : L10n.t(current ? "conflictUseCurrentFile" : "conflictUseIncomingFile")
                width: (sources.width - Metrics.hairline) / 2 + (index === 0 ? Metrics.hairline : 0)
                height: sources.height
                color: chosen ? Theme.blend(Theme.colors.pane, sideColor, GitLamaLayout.opacityConflictChosen) : Theme.colors.pane
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width - (sourceCell.index === 0 ? Metrics.hairline : 0)
                    height: sourceCell.chosen ? GitLamaLayout.conflictChoiceRail : Metrics.hairline
                    color: sourceCell.chosen ? sourceCell.sideColor : Qt.alpha(sourceCell.sideColor, GitLamaLayout.opacityConflictDivider)
                }
                MeridianHairline { visible: sourceCell.index === 0; vertical: true; anchors.right: parent.right; height: parent.height }
                Rectangle {
                    id: rail
                    x: Theme.space.s4
                    anchors.verticalCenter: parent.verticalCenter
                    width: GitLamaLayout.conflictRail
                    height: Theme.size.icon
                    color: sourceCell.sideColor
                }
                MeridianText {
                    x: rail.x + rail.width + Theme.space.s4
                    anchors.verticalCenter: parent.verticalCenter
                    width: sourceAction.x - x - Theme.space.s4
                    role: MeridianText.Label
                    text: L10n.tn(sourceCell.current ? "conflictCurrent" : "conflictIncoming",
                                  { label: sourceCell.current ? (root.conflictState.currentLabel ?? "") : (root.conflictState.incomingLabel ?? "") })
                }
                Loader {
                    id: sourceAction
                    readonly property bool narrow: sourceCell.width < GitLamaLayout.conflictSourceActionMinWidth
                    x: parent.width - width - Theme.space.s4 - (sourceCell.index === 0 ? Metrics.hairline : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: narrow ? sourceIcon : sourceButton
                    Component {
                        id: sourceButton
                        MeridianButton {
                            text: sourceCell.action
                            iconName: sourceCell.chosen ? "check" : sourceCell.deletes ? "trash-2" : ""
                            variant: sourceCell.chosen ? MeridianButton.Secondary : MeridianButton.Quiet
                            controlSize: MeridianButton.Small
                            enabled: !root.busy
                            onClicked: Store.conflicts.chooseSide(sourceCell.modelData)
                        }
                    }
                    Component {
                        id: sourceIcon
                        MeridianIconButton {
                            text: sourceCell.action
                            iconName: sourceCell.chosen ? "check" : sourceCell.deletes ? "trash-2" : "check-check"
                            active: sourceCell.chosen
                            controlSize: MeridianButton.Small
                            enabled: !root.busy
                            onClicked: Store.conflicts.chooseSide(sourceCell.modelData)
                        }
                    }
                }
            }
        }
    }

    // Both sides' lines scroll sideways together.
    property real horizontalOffset: 0
    readonly property real cellFixedWidth: GitLamaLayout.conflictChoiceRail + Theme.space.s3 + Theme.space.s4
        + GitLamaLayout.conflictLineColumnWidth + Theme.space.s5
    property real widestLine: 0
    readonly property real textWidth: Math.max(0, (width - Metrics.hairline) / 2 - cellFixedWidth)
    readonly property real maxHorizontal: wrap ? 0 : Math.max(0, widestLine - textWidth)
    onMaxHorizontalChanged: horizontalOffset = Math.min(horizontalOffset, maxHorizontal)

    ListView {
        id: list
        y: sources.y + sources.height
        width: parent.width
        height: parent.height - y - (horizontalBar.visible ? horizontalBar.height : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Store.conflictRows
        cacheBuffer: 400
        reuseItems: true
        MeridianWheelScroll { flickable: list }
        C.ScrollBar.vertical: MeridianScrollBar {}
        onContentYChanged: root.scrolled()
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            acceptedModifiers: Qt.ShiftModifier
            onWheel: event => {
                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                root.horizontalOffset = Math.max(0, Math.min(root.maxHorizontal, root.horizontalOffset - delta / 2))
            }
        }

        delegate: Column {
            id: row
            // A pooled row is hidden until it is reused (it could stay drawn at its old place).
            ListView.onPooled: visible = false
            ListView.onReused: visible = true
            required property int index
            required property string current
            required property string incoming
            required property var currentLine
            required property var incomingLine
            required property int block
            required property bool different
            required property bool first
            required property bool chosenCurrent
            required property bool chosenIncoming
            readonly property bool inRegion: block >= 0
            width: ListView.view.width

            // A conflict's choices above its first row.
            Row {
                visible: row.first
                width: parent.width
                height: visible ? root.toolbarHeight : 0
                readonly property bool focusedRegion: row.block === root.focusedRegion
                readonly property var choice: row.block >= 0 && row.block < root.blocks.length ? root.blocks[row.block].choice : null
                id: toolbar
                Repeater {
                    model: 2
                    delegate: Rectangle {
                        id: half
                        required property int index
                        width: (row.width - Metrics.hairline) / 2 + (index === 0 ? Metrics.hairline : 0)
                        height: root.toolbarHeight
                        color: toolbar.focusedRegion ? Theme.colors.accentSoft : Theme.colors.paneAlt
                        Rectangle {
                            visible: half.index === 0
                            width: GitLamaLayout.conflictRail
                            height: parent.height
                            color: toolbar.focusedRegion ? Theme.colors.accent : Theme.colors.line
                        }
                        MeridianHairline { visible: half.index === 0; vertical: true; anchors.right: parent.right; height: parent.height }
                        Row {
                            x: Theme.space.s3 + (half.index === 0 ? GitLamaLayout.conflictRail : 0)
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: half.index === 0 ? ["current"] : ["incoming"]
                                delegate: MeridianButton {
                                    required property string modelData
                                    readonly property bool remove: modelData === toolbar.choice || (toolbar.choice === "both")
                                    text: remove ? root.removeLabel(modelData) : root.choiceLabel(modelData)
                                    iconName: remove ? "minus" : ""
                                    variant: modelData === toolbar.choice ? MeridianButton.Secondary : MeridianButton.Quiet
                                    controlSize: MeridianButton.Small
                                    enabled: !root.busy
                                    onClicked: Store.conflicts.takeRegion(row.block, modelData, remove)
                                    HoverHandler {
                                        onHoveredChanged: {
                                            if (hovered) { root.hoveredRegion = row.block; root.hoveredSide = parent.modelData }
                                            else if (root.hoveredRegion === row.block) { root.hoveredRegion = -1; root.hoveredSide = "" }
                                        }
                                    }
                                }
                            }
                        }
                        // The region's number on the current side, "Take both" on the incoming side.
                        MeridianText {
                            visible: half.index === 0
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.space.s4 + Metrics.hairline
                            anchors.verticalCenter: parent.verticalCenter
                            role: MeridianText.Label
                            color: toolbar.focusedRegion ? Theme.colors.ink : Theme.colors.inkMuted
                            text: L10n.tn("conflictRegionNumber", { number: row.block + 1 })
                        }
                        MeridianButton {
                            visible: half.index === 1
                            readonly property bool remove: toolbar.choice === "both"
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.space.s4
                            anchors.verticalCenter: parent.verticalCenter
                            text: remove ? root.removeLabel("both") : root.choiceLabel("both")
                            iconName: remove ? "minus" : ""
                            variant: toolbar.choice === "both" ? MeridianButton.Secondary : MeridianButton.Quiet
                            controlSize: MeridianButton.Small
                            enabled: !root.busy
                            onClicked: Store.conflicts.takeRegion(row.block, "both", remove)
                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered) { root.hoveredRegion = row.block; root.hoveredSide = "both" }
                                    else if (root.hoveredRegion === row.block) { root.hoveredRegion = -1; root.hoveredSide = "" }
                                }
                            }
                        }
                    }
                }
            }

            // The row: current, then incoming.
            readonly property real lineHeight: root.lineHeightAt(row.index)
            Row {
                width: parent.width
                height: row.lineHeight
                Repeater {
                    model: 2
                    delegate: Rectangle {
                        id: cell
                        required property int index
                        readonly property bool current: index === 0
                        readonly property string side: current ? "current" : "incoming"
                        readonly property string cellText: current ? row.current : row.incoming
                        readonly property var line: current ? row.currentLine : row.incomingLine
                        readonly property bool chosen: current ? row.chosenCurrent : row.chosenIncoming
                        readonly property color sideColor: current ? GitColors.sideOurs : GitColors.sideTheirs
                        readonly property bool hunkHovered: !root.busy && row.inRegion && (cellArea.containsMouse
                            || (root.hoveredRegion === row.block && (root.hoveredSide === side || root.hoveredSide === "both")))
                        property real railProgress: chosen || hunkHovered ? 1 : 0
                        Behavior on railProgress { NumberAnimation { duration: Motion.select } }
                        width: (row.width - Metrics.hairline) / 2 + (index === 0 ? Metrics.hairline : 0)
                        height: row.lineHeight
                        color: !row.inRegion ? (row.different ? Theme.colors.attentionBg : Theme.colors.pane)
                            : Theme.blend(Theme.colors.pane, sideColor, hunkHovered ? GitLamaLayout.opacityConflictHover
                                : chosen ? GitLamaLayout.opacityConflictChosen : GitLamaLayout.opacityConflictUnchosen)
                        Rectangle {
                            width: GitLamaLayout.conflictChoiceRail
                            height: parent.height
                            color: row.inRegion ? Qt.alpha(cell.sideColor, GitLamaLayout.opacityConflictRailUnchosen
                                + (GitLamaLayout.opacityConflictRailChosen - GitLamaLayout.opacityConflictRailUnchosen) * cell.railProgress)
                                : "transparent"
                        }
                        MeridianHairline { visible: cell.index === 0; vertical: true; anchors.right: parent.right; height: parent.height }
                        MeridianText {
                            id: number
                            x: GitLamaLayout.conflictChoiceRail + Theme.space.s3
                            width: GitLamaLayout.conflictLineColumnWidth
                            height: root.rowHeight
                            horizontalAlignment: Text.AlignRight
                            role: MeridianText.CodeSm
                            color: Theme.colors.inkMuted
                            text: cell.line === null || cell.line === undefined ? "" : String(cell.line)
                        }
                        Item {
                            x: number.x + number.width + Theme.space.s5
                            width: parent.width - x - Theme.space.s4 - (cell.index === 0 ? Metrics.hairline : 0)
                            height: parent.height
                            clip: true
                            // A wrapped line starts level with its number.
                            MeridianText {
                                id: lineText
                                readonly property string styled: root.styledAt(row.index, cell.current, cell.cellText)
                                x: root.wrap ? 0 : -root.horizontalOffset
                                y: root.wrap ? (root.rowHeight - root.wrapLineHeight) / 2 : 0
                                width: root.wrap ? parent.width : implicitWidth
                                height: root.wrap ? implicitHeight : parent.height
                                role: MeridianText.Code
                                elide: Text.ElideNone
                                wrapMode: root.wrap ? Text.WrapAnywhere : Text.NoWrap
                                textFormat: styled.length > 0 ? Text.StyledText : Text.PlainText
                                text: styled.length > 0 ? styled : cell.cellText
                                onImplicitWidthChanged: if (!root.wrap && implicitWidth > root.widestLine) root.widestLine = implicitWidth
                            }
                        }
                        // What a click does, next to the pointer.
                        MeridianChip {
                            visible: row.inRegion && !root.busy && cellArea.containsMouse
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.space.s4
                            anchors.verticalCenter: parent.verticalCenter
                            text: cell.chosen ? root.removeLabel(cell.side) : root.choiceLabel(cell.side)
                            iconName: cell.chosen ? "minus" : "plus"
                            tone: MeridianChip.Accent
                        }
                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            enabled: row.inRegion
                            hoverEnabled: true
                            cursorShape: row.inRegion ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (!root.busy) Store.conflicts.takeRegion(row.block, cell.side, cell.chosen)
                            Accessible.role: Accessible.Button
                            Accessible.name: cell.chosen ? root.removeLabel(cell.side) : root.choiceLabel(cell.side)
                        }
                    }
                }
            }
        }
    }
    MeridianScrollBar {
        id: horizontalBar
        visible: root.maxHorizontal > 0
        orientation: Qt.Horizontal
        y: list.y + list.height
        x: root.cellFixedWidth
        width: parent.width - x
        size: root.textWidth / Math.max(1, root.widestLine)
        position: root.horizontalOffset / Math.max(1, root.widestLine)
        onPositionChanged: if (pressed) root.horizontalOffset = position * root.widestLine
    }

    /// Scrolls the comparison until `region` sits near the top.
    function showRegion(region) {
        const extents = regionExtents()
        if (region < 0 || region >= extents.length)
            return
        Store.conflicts.focusRegion(region)
        const lead = GitLamaLayout.conflictLeadRows * rowHeight
        list.contentY = Math.max(0, Math.min(Math.max(0, list.contentHeight - list.height), extents[region].top - lead))
    }
    onFileChanged: widestLine = 0
    Component.onCompleted: {
        _measure()
        colourLater.restart()
    }
}
