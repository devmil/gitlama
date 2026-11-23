pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// A diff: file headers, hunk headers and lines with
// their numbers and signs, unified or side by side. Lines keep their colours
// from Rust (syntax checked against each surface) and mark changed words.
// Only the visible rows are built; rows of pages not loaded yet are blank
// until they arrive. Text scrolls sideways under fixed gutters.
Item {
    id: view

    /// A DiffModel.
    property var model: null
    property string layout: "unified"
    property bool showIndicators: true
    /// Long lines wrap instead of scrolling sideways.
    property bool wrap: false
    /// A strip beside the rows marks where lines were added and removed.
    property bool showMinimap: false
    /// "utf8" or "latin1".
    property string encoding: "utf8"
    onEncodingChanged: if (model) model.setLatin1(encoding === "latin1")
    /// The rows of the found matches and the current one (-1 for none).
    property var searchMatches: []
    property int currentSearch: -1
    readonly property var searchSet: {
        const set = {}
        for (const row of searchMatches)
            set[row] = true
        return set
    }
    onSearchMatchesChanged: if (minimap.visible) minimapCanvas.requestPaint()
    /// Hunk headers offer Show more lines when set.
    property bool canShowMoreContext: false
    signal showMoreContext()
    /// A binary file's row offers Show as text.
    property bool canShowAsText: false
    signal showAsText()

    /// Hunk headers offer Stage (or Unstage) and Discard (a working diff).
    property bool hunkActions: false
    /// The diff shows staged changes: its hunks unstage.
    property bool hunkStagedSide: false
    property bool canDiscardHunks: false
    property bool hunkActionsEnabled: true
    /// Why staging is unavailable (an unmerged file); empty when it is.
    property string hunkStageDisabledReason
    signal stageHunk(string stableId)
    signal discardHunk(string stableId)
    /// Files whose sections are folded, by file row stable id.
    property var collapsed: ({})
    /// The horizontal scroll of the text columns.
    property real textOffset: 0
    property real widestText: 0
    readonly property bool split: layout === "sideBySide"
    // Unified and split crossfade (NM-46); the scroll position stays on the same line.
    onSplitChanged: if (!Motion.reduced) layoutFade.restart()
    NumberAnimation {
        id: layoutFade
        target: list
        property: "opacity"
        from: 0
        to: 1
        duration: Motion.select
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.standard
    }
    readonly property real gutters: (split ? GitLamaLayout.diffGutterWidth : 2 * GitLamaLayout.diffGutterWidth) + GitLamaLayout.diffSignWidth
    readonly property real textWidth: split ? (list.width - Metrics.hairline) / 2 - gutters - Theme.space.s6 : list.width - gutters - Theme.space.s6
    readonly property real maximumOffset: wrap ? 0 : Math.max(0, widestText - textWidth)

    signal rowActivated(int index, string kind)

    /// Lines can be selected (staging, discarding or copying lines).
    property bool lineSelection: false
    /// The selected rows' stable ids.
    property var selectedRows: []
    property int selectionAnchor: -1
    signal rowsSelected(var rows)
    signal lineMenuRequested(real x, real y)

    function rowSelected(id) { return selectedRows.indexOf(id) >= 0 }
    function selectLine(index, stableId, modifiers) {
        if (!lineSelection)
            return
        list.forceActiveFocus()
        let rows
        if ((modifiers & Qt.ShiftModifier) && selectionAnchor >= 0) {
            rows = model.lineIds(Math.min(selectionAnchor, index), Math.max(selectionAnchor, index))
        } else if (modifiers & (Qt.ControlModifier | Qt.MetaModifier)) {
            rows = selectedRows.slice()
            const at = rows.indexOf(stableId)
            if (at >= 0) rows.splice(at, 1); else rows.push(stableId)
            selectionAnchor = index
        } else {
            rows = rowSelected(stableId) && selectedRows.length === 1 ? [] : [stableId]
            selectionAnchor = index
        }
        rowsSelected(rows)
    }

    function positionAt(index) {
        list.positionViewAtIndex(index, ListView.Beginning)
    }

    /// Actions shown over the first selected line while lines are selected
    /// and that line is on screen.
    property Component selectionActions: null

    /// The bridge that builds a selection's patch (copyPatch, patchReady).
    property var patchSource: null
    property bool _patchPending: false
    /// Copies the selected lines' text (Ctrl+C, Copy lines).
    function copyLines() {
        if (!model || selectedRows.length === 0)
            return
        Store.actions.copyText(model.selectionText(selectedRows), L10n.t("diffSelectionCopied"))
    }
    /// Copies the selected lines as a patch.
    function copyPatch() {
        if (!patchSource || selectedRows.length === 0)
            return
        _patchPending = true
        patchSource.copyPatch(selectedRows, encoding === "latin1")
    }
    /// The copy entries of the selected lines' menu, after the caller's own.
    function copyMenuItems() {
        const items = [{ separator: true },
            { title: L10n.t("diffCopyLines"), icon: "copy", value: "copyLines", shortcut: Store.isMac ? "Cmd+C" : "Ctrl+C" }]
        if (patchSource)
            items.push({ title: L10n.t("diffCopyAsPatch"), icon: "file-diff", value: "copyPatch",
                         enabled: model !== null && model.selectionHasChange(selectedRows) })
        return items
    }
    /// Runs a copy entry of `copyMenuItems`; false for other values.
    function runCopyMenuItem(value) {
        if (value === "copyLines")
            copyLines()
        else if (value === "copyPatch")
            copyPatch()
        else
            return false
        return true
    }
    Connections {
        target: view.patchSource
        function onPatchReady(patch) {
            if (!view._patchPending)
                return
            view._patchPending = false
            if (patch.length === 0)
                Notifications.show(L10n.t("diffPatchUnavailable"), false)
            else
                Store.actions.copyText(patch, L10n.t("diffPatchCopied"))
        }
    }
    /// The bridge that lists every hunk of the diff (loadHunks,
    /// hunksLoaded); without one only loaded hunks are stepped through.
    property var hunkSource: null
    property var hunkRows: []
    property int hunkIndex: -1
    property int pendingHunkStep: 0
    function stepHunk(delta) {
        if (hunkRows.length === 0)
            return
        hunkIndex = hunkIndex < 0 ? (delta > 0 ? 0 : hunkRows.length - 1)
            : (hunkIndex + delta + hunkRows.length) % hunkRows.length
        positionAt(hunkRows[hunkIndex])
    }
    function nextHunk(forward) {
        if (hunkSource) {
            if (hunkRows.length === 0) {
                pendingHunkStep = forward ? 1 : -1
                hunkSource.loadHunks()
            } else {
                stepHunk(forward ? 1 : -1)
            }
            return
        }
        const at = list.indexAt(0, list.contentY + 1)
        const target = model ? model.hunkFrom(at < 0 ? 0 : at, forward) : -1
        if (target >= 0)
            positionAt(target)
    }
    Connections {
        target: view.hunkSource
        function onHunksLoaded(rows) {
            if (view.pendingHunkStep === 0)
                return
            view.hunkRows = rows ?? []
            const step = view.pendingHunkStep
            view.pendingHunkStep = 0
            view.stepHunk(step)
        }
    }

    onModelChanged: { textOffset = 0; widestText = 0; if (model) model.setLatin1(encoding === "latin1") }
    onMaximumOffsetChanged: textOffset = Math.min(textOffset, maximumOffset)

    // The syntax palette, checked against the surfaces lines are drawn on.
    readonly property var syntaxPalette: ({
        ink: String(Theme.colors.ink),
        syntax: {
            comment: String(Theme.colors.syntaxComment), keyword: String(Theme.colors.syntaxKeyword),
            string: String(Theme.colors.syntaxString), number: String(Theme.colors.syntaxNumber),
            type: String(Theme.colors.syntaxType), function: String(Theme.colors.syntaxFunction),
            variable: String(Theme.colors.syntaxVariable), constant: String(Theme.colors.syntaxConstant),
            operator: String(Theme.colors.syntaxOperator), punctuation: String(Theme.colors.syntaxPunctuation),
            attribute: String(Theme.colors.syntaxAttribute), tag: String(Theme.colors.syntaxTag),
        },
        surfaces: {
            context: [String(Theme.colors.pane)],
            addition: [String(Theme.colors.successBg), String(Theme.blend(Theme.colors.successBg, GitColors.addedStrong, 1))],
            deletion: [String(GitColors.deletedBg), String(Theme.blend(GitColors.deletedBg, GitColors.deletedStrong, 1))],
        },
    })
    function applyPalette() { if (model) model.setPalette(syntaxPalette) }
    onSyntaxPaletteChanged: if (model) model.setPalette(syntaxPalette)
    Component.onCompleted: if (model) model.setPalette(syntaxPalette)
    Connections {
        target: view.model
        // The model is still publishing: its colours follow on the next turn.
        function onCountChanged() { Qt.callLater(view.applyPalette); syntaxTimer.restart(); view.hunkRows = []; view.hunkIndex = -1 }
        function onModelReset() { view.hunkRows = []; view.hunkIndex = -1 }
    }

    FontMetrics { id: code; font: Theme.type.code }

    // Colours are read once the rows have been on screen for a moment.
    Timer {
        id: syntaxTimer
        interval: GitLamaLayout.detailDebounce
        onTriggered: {
            if (!view.model)
                return
            const first = list.indexAt(0, list.contentY + 1)
            let last = list.indexAt(0, list.contentY + list.height - 1)
            if (last < 0)
                last = view.model.count() - 1
            view.model.demandSyntax(Math.max(0, first), last)
        }
    }

    ListView {
        id: list
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width - (minimap.visible ? minimap.width : 0)
        clip: true
        model: view.model
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        cacheBuffer: 360
        keyNavigationEnabled: false
        Keys.onPressed: event => {
            if (event.matches(StandardKey.Copy) && view.selectedRows.length > 0) {
                view.copyLines()
                event.accepted = true
            }
        }
        onContentYChanged: syntaxTimer.restart()
        onHeightChanged: syntaxTimer.restart()

        MeridianWheelScroll { flickable: list }
        C.ScrollBar.vertical: MeridianScrollBar { viewHovered: viewHover.hovered }

        delegate: Item {
            id: line

            required property int index
            required property string stableId
            required property string kind
            required property bool loading
            required property int oldLine
            required property int newLine
            required property string text
            required property string styledOld
            required property string styledNew
            required property var marks
            required property string fileKind
            required property string oldPath
            required property string newPath
            required property bool invalid
            required property string hunkRange
            required property string hunkText

            readonly property bool lineRow: kind === "context" || kind === "addition" || kind === "deletion"
            readonly property bool chosen: view.lineSelection && lineRow && view.selectedRows.indexOf(stableId) >= 0
            readonly property bool added: kind === "addition"
            readonly property bool deleted: kind === "deletion"
            readonly property bool fallback: kind === "binary" || kind === "image" || kind === "submodule"
                || kind === "modeOnly" || kind === "tooLarge" || invalid
            readonly property bool currentMatch: view.currentSearch === index
            readonly property bool searchMatch: view.searchSet[index] === true
            readonly property color fill: currentMatch ? Theme.colors.accentSoft
                : searchMatch ? Theme.colors.paneHover
                : added ? Theme.colors.successBg
                : deleted ? GitColors.deletedBg
                : kind === "hunk" || kind === "noNewline" ? Theme.colors.paneAlt
                : Theme.colors.pane

            width: list.width
            /// The tallest wrapped text of the row's cells.
            readonly property real wrappedHeight: Math.max(GitLamaLayout.diffLineHeight, firstCell.textHeight, secondCell.visible ? secondCell.textHeight : 0)
            height: loading ? GitLamaLayout.diffLineHeight
                : view.wrap && lineRow ? wrappedHeight
                : kind === "hunk" ? GitLamaLayout.hunkHeaderHeight
                : kind === "file" ? Theme.size.row
                : fallback ? GitLamaLayout.diffFallbackHeight
                : GitLamaLayout.diffLineHeight

            Rectangle {
                anchors.fill: parent
                color: line.chosen ? Theme.blend(line.fill, Theme.colors.accent, GitLamaLayout.opacityDiffSelectedLine) : line.fill
                // The current match is framed.
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: Metrics.hairline
                    border.color: Theme.colors.accent
                    opacity: line.currentMatch ? 1 : 0
                    scale: line.currentMatch ? 1 : 1.08
                    Behavior on scale { NumberAnimation { duration: Motion.quick; easing.type: Easing.OutBack } }
                }
                // The frame around a run of selected lines.
                Rectangle {
                    visible: line.chosen
                    anchors.fill: parent
                    color: "transparent"
                    border.width: Metrics.hairline
                    border.color: Theme.colors.accent
                }
                Rectangle {
                    visible: line.kind === "hunk"
                    width: parent.width; height: Metrics.hairline
                    color: Theme.colors.line
                }
                Rectangle {
                    visible: line.kind === "hunk"
                    anchors.bottom: parent.bottom
                    width: parent.width; height: Metrics.hairline
                    color: Theme.colors.line
                }
            }

            // A file's header: activating it folds or unfolds the file.
            Item {
                visible: line.kind === "file"
                anchors.fill: parent
                Accessible.role: Accessible.Button
                Accessible.name: view.collapsed[line.stableId] ? L10n.t("diffExpandFile") : L10n.t("diffCollapseFile")
                Accessible.description: line.text
                Accessible.ignored: !visible
                MeridianIcon {
                    id: fileChevron
                    x: Theme.space.s4
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-down"
                    iconSize: MeridianIcon.Small
                    rotation: view.collapsed[line.stableId] ? -90 : 0
                    Behavior on rotation { NumberAnimation { duration: Motion.quick } }
                }
                MeridianText {
                    x: fileChevron.x + fileChevron.width + Theme.space.s3
                    width: parent.width - x - Theme.space.s3
                    anchors.verticalCenter: parent.verticalCenter
                    role: MeridianText.CodeSm
                    text: line.text
                    elide: Text.ElideRight
                }
            }

            // A hunk's header: its range, then the code it is in.
            DiffHunkHeader {
                visible: line.kind === "hunk"
                width: parent.width
                height: parent.height
                diff: view
                stableId: line.kind === "hunk" ? line.stableId : ""
                range: line.hunkRange
                text: line.hunkText
            }

            MeridianText {
                visible: line.kind === "noNewline"
                x: Theme.space.s5
                anchors.verticalCenter: parent.verticalCenter
                role: MeridianText.Caption
                text: L10n.t("diffNoNewline")
                color: Theme.colors.inkMuted
            }

            // Binary, image, submodule, mode-only and too-large files: a
            // binary or too large file names its size and type.
            MeridianEmptyState {
                id: fallbackState
                readonly property int byteCount: {
                    const size = Number(line.text.split(":")[0])
                    return line.text.length > 0 && Number.isInteger(size) ? size : -1
                }
                readonly property string extension: {
                    const name = (line.newPath || line.oldPath).split("/").pop()
                    const dot = name.lastIndexOf(".")
                    return dot > 0 && dot < name.length - 1 ? name.slice(dot + 1).toUpperCase() : L10n.t("diffFileTypeUnknown")
                }
                visible: line.fallback && !line.loading
                anchors.fill: parent
                compact: true
                iconName: line.kind === "image" ? "image" : line.kind === "submodule" ? "box"
                    : line.kind === "tooLarge" ? "triangle-alert" : "file-diff"
                title: line.invalid ? L10n.t("diffEncodingInvalid")
                    : line.kind === "binary" ? L10n.t("diffBinaryFallback")
                    : line.kind === "image" ? L10n.t("diffImageFallback")
                    : line.kind === "submodule" ? L10n.t("diffSubmoduleFallback")
                    : line.kind === "modeOnly" ? L10n.tn("diffModeOnlyFallback", { modes: line.text })
                    : line.text.endsWith(":0:0") ? L10n.t("diffLargeFileInformation") : L10n.t("diffTooLargeFallback")
                message: byteCount >= 0 && (line.kind === "tooLarge" || line.kind === "binary")
                    ? L10n.tn("diffFileSize", { size: Labels.byteSize(byteCount) }) + "\n" + L10n.tn("diffFileType", { extension: extension })
                    : ""
                MeridianButton {
                    objectName: "diff-show-as-text"
                    visible: line.kind === "binary" && view.canShowAsText
                    text: L10n.t("showBinaryAsText")
                    onClicked: view.showAsText()
                }
            }

            component Cell: Item {
                id: cell
                property bool oldSide: false
                property bool unified: true
                property string styled
                readonly property int number: oldSide ? line.oldLine : line.newLine
                readonly property bool blank: !unified && ((oldSide && line.added) || (!oldSide && line.deleted))
                readonly property real textHeight: view.wrap && !blank ? lineText.implicitHeight + 2 * Theme.space.s1 : 0
                height: line.height
                clip: true

                Row {
                    visible: !cell.blank
                    height: parent.height
                    Repeater {
                        model: cell.unified ? [line.oldLine, line.newLine] : [cell.number]
                        delegate: MeridianText {
                            required property int modelData
                            width: GitLamaLayout.diffGutterWidth
                            // A wrapped line keeps its number on the first row.
                            height: GitLamaLayout.diffLineHeight
                            rightPadding: Theme.space.s4
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                            role: MeridianText.CodeSm
                            tabular: true
                            text: modelData > 0 ? String(modelData) : ""
                            color: Theme.colors.inkMuted
                        }
                    }
                    MeridianText {
                        width: GitLamaLayout.diffSignWidth
                        height: GitLamaLayout.diffLineHeight
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        role: MeridianText.Code
                        text: !view.showIndicators ? "" : line.added ? "+" : line.deleted ? "−" : " "
                        color: line.added ? Theme.colors.success : line.deleted ? GitColors.deleted : Theme.colors.inkMuted
                    }
                    Item {
                        id: textCell
                        width: cell.width - x - Theme.space.s6
                        height: line.height
                        clip: true
                        Item {
                            x: -view.textOffset
                            height: parent.height
                            width: view.wrap ? textCell.width : lineText.implicitWidth
                            // Changed words (wrapped lines show none).
                            Repeater {
                                model: view.wrap ? [] : line.marks
                                delegate: Rectangle {
                                    required property var modelData
                                    x: code.advanceWidth(line.text.substring(0, modelData[0]))
                                    width: code.advanceWidth(line.text.substring(modelData[0], modelData[1]))
                                    y: 1
                                    height: GitLamaLayout.diffLineHeight - 2
                                    radius: Theme.radius.xs
                                    color: line.deleted ? GitColors.deletedStrong : GitColors.addedStrong
                                }
                            }
                            Text {
                                id: lineText
                                y: view.wrap ? Theme.space.s1 : (parent.height - height) / 2
                                width: view.wrap ? textCell.width : undefined
                                wrapMode: view.wrap ? Text.WrapAnywhere : Text.NoWrap
                                font: Theme.type.code
                                color: Theme.colors.ink
                                textFormat: cell.styled.length > 0 ? Text.StyledText : Text.PlainText
                                text: cell.styled.length > 0 ? cell.styled : line.text
                                onImplicitWidthChanged: if (!view.wrap && implicitWidth > view.widestText) view.widestText = implicitWidth
                            }
                        }
                    }
                }
            }

            Row {
                visible: !line.loading && !line.fallback && (line.kind === "context" || line.added || line.deleted)
                width: parent.width
                height: parent.height
                Cell {
                    id: firstCell
                    width: view.split ? (parent.width - Metrics.hairline) / 2 : parent.width
                    unified: !view.split
                    oldSide: view.split
                    styled: view.split ? line.styledOld : (line.deleted ? line.styledOld : line.styledNew)
                }
                Rectangle {
                    visible: view.split
                    width: Metrics.hairline
                    height: parent.height
                    color: Theme.colors.line
                }
                Cell {
                    id: secondCell
                    visible: view.split
                    width: (parent.width - Metrics.hairline) / 2
                    unified: false
                    oldSide: false
                    styled: line.styledNew
                }
            }

            TapHandler {
                id: lineTap
                enabled: !line.loading
                onTapped: {
                    if (view.lineSelection && line.lineRow)
                        view.selectLine(line.index, line.stableId, lineTap.point.modifiers)
                    view.rowActivated(line.index, line.kind)
                }
            }
            TapHandler {
                enabled: view.lineSelection && line.lineRow
                acceptedButtons: Qt.RightButton
                onTapped: point => {
                    if (!line.chosen)
                        view.selectLine(line.index, line.stableId, 0)
                    const at = line.mapToItem(view, point.position.x, point.position.y)
                    view.lineMenuRequested(at.x, at.y)
                }
            }
        }
    }

    // The minimap: where lines were added and
    // removed over the whole diff, and the part on screen; a click scrolls
    // there.
    Item {
        id: minimap
        objectName: "diff-minimap"
        visible: view.showMinimap && view.model !== null && list.count > 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: GitLamaLayout.diffMinimapWidth
        readonly property real maximum: Math.max(0, list.contentHeight - list.height)
        readonly property real viewportFraction: list.contentHeight <= 0 ? 1 : list.height / list.contentHeight
        readonly property real offsetFraction: maximum <= 0 ? 0 : (list.contentY - list.originY) / maximum
        Canvas {
            id: minimapCanvas
            anchors.fill: parent
            onPaint: {
                const context = getContext("2d")
                context.reset()
                if (!view.model)
                    return
                const buckets = Math.max(1, Math.floor(height))
                const map = view.model.changeMap(buckets)
                for (let i = 0; i < map.length; ++i) {
                    if (map[i] === 0)
                        continue
                    context.fillStyle = String(map[i] === 1 ? Theme.colors.success : GitColors.deleted)
                    context.fillRect(0, i * height / buckets, width, 1)
                }
                // Found matches over the changes.
                const total = view.model.count()
                context.fillStyle = String(Theme.colors.accent)
                for (const row of view.searchMatches)
                    context.fillRect(0, row / Math.max(1, total) * height, width, 1)
            }
        }
        Rectangle {
            x: Metrics.hairline / 2
            width: parent.width - Metrics.hairline
            height: Math.max(2, minimap.viewportFraction * parent.height)
            y: minimap.offsetFraction * (parent.height - height)
            color: "transparent"
            border.width: Metrics.hairline
            border.color: Theme.colors.lineStrong
        }
        MouseArea {
            anchors.fill: parent
            onPressed: mouse => {
                const available = 1 - minimap.viewportFraction
                if (available <= 0 || height <= 0)
                    return
                const fraction = Math.max(0, Math.min(1, (mouse.y / height - minimap.viewportFraction / 2) / available))
                list.contentY = list.originY + fraction * minimap.maximum
            }
        }
        Timer {
            id: minimapRepaint
            interval: GitLamaLayout.detailDebounce
            onTriggered: minimapCanvas.requestPaint()
        }
        Connections {
            target: view.model
            function onCountChanged() { minimapRepaint.restart() }
            function onDataChanged() { minimapRepaint.restart() }
        }
        onHeightChanged: minimapRepaint.restart()
        onVisibleChanged: if (visible) minimapRepaint.restart()
    }

    // The header of the hunk the top line belongs to stays pinned while its
    // own row is scrolled away (unwrapped diffs).
    Rectangle {
        id: pinnedHunk
        property var header: null
        function refresh() {
            if (view.wrap || !view.model) {
                header = null
                return
            }
            const top = list.indexAt(0, list.contentY + 1)
            const found = top < 0 ? null : view.model.hunkHeaderFor(top)
            header = found && found.index < top ? found : null
        }
        visible: header !== null
        anchors.left: list.left
        anchors.top: list.top
        width: list.width
        height: GitLamaLayout.hunkHeaderHeight
        color: Theme.colors.paneAlt
        Connections {
            target: list
            function onContentYChanged() { pinnedHunk.refresh() }
            function onCountChanged() { pinnedHunk.refresh() }
        }
        Connections {
            target: view
            function onWrapChanged() { pinnedHunk.refresh() }
            function onModelChanged() { pinnedHunk.refresh() }
        }
        // Clicks on the pinned header never reach the rows below it.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        DiffHunkHeader {
            anchors.fill: parent
            diff: view
            stableId: pinnedHunk.header ? pinnedHunk.header.stableId : ""
            range: pinnedHunk.header ? pinnedHunk.header.hunkRange : ""
            text: pinnedHunk.header ? pinnedHunk.header.hunkText : ""
        }
        Rectangle { width: parent.width; height: Metrics.hairline; color: Theme.colors.line }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: Metrics.hairline; color: Theme.colors.line }
    }

    // The selection's actions float at the top right of its first line.
    Loader {
        id: selectionActionsLoader
        property int rowIndex: -1
        property real rowY: 0
        function refresh() {
            rowIndex = view.model && view.selectedRows.length > 0 ? view.model.firstIndexOf(view.selectedRows) : -1
            const item = rowIndex < 0 ? null : list.itemAtIndex(rowIndex)
            rowY = item ? item.y - list.contentY : -1
        }
        active: view.selectionActions !== null && view.selectedRows.length > 0
        sourceComponent: view.selectionActions
        visible: active && rowIndex >= 0 && rowY >= 0 && rowY < list.height
        x: list.x + list.width - width - Theme.space.s6
        y: list.y + rowY - Theme.space.s1
        z: 2
        Connections {
            target: list
            function onContentYChanged() { selectionActionsLoader.refresh() }
            function onCountChanged() { selectionActionsLoader.refresh() }
        }
        Connections {
            target: view
            function onSelectedRowsChanged() { Qt.callLater(selectionActionsLoader.refresh) }
        }
    }

    HoverHandler { id: viewHover }
    // Sideways scrolling moves only the text, under the fixed gutters.
    WheelHandler {
        orientation: Qt.Horizontal
        onWheel: event => {
            const delta = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x / 2
            view.textOffset = Math.max(0, Math.min(view.maximumOffset, view.textOffset - delta))
        }
    }
    MeridianScrollBar {
        id: horizontalBar
        visible: view.maximumOffset > 0
        orientation: Qt.Horizontal
        anchors.left: parent.left
        anchors.right: list.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: view.gutters
        size: view.textWidth / Math.max(1, view.widestText)
        position: view.textOffset / Math.max(1, view.widestText)
        viewHovered: viewHover.hovered
        onPositionChanged: if (pressed) view.textOffset = position * view.widestText
    }
}
