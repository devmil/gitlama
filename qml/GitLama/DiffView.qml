pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// A diff (the Dart DiffView): file headers, hunk headers and lines with
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
    /// Files whose sections are folded, by file row stable id.
    property var collapsed: ({})
    /// The horizontal scroll of the text columns.
    property real textOffset: 0
    property real widestText: 0
    readonly property bool split: layout === "sideBySide"
    readonly property real gutters: (split ? GitLamaLayout.diffGutterWidth : 2 * GitLamaLayout.diffGutterWidth) + GitLamaLayout.diffSignWidth
    readonly property real textWidth: split ? (list.width - Metrics.hairline) / 2 - gutters - Theme.space.s6 : list.width - gutters - Theme.space.s6
    readonly property real maximumOffset: Math.max(0, widestText - textWidth)

    signal rowActivated(int index, string kind)

    function positionAt(index) {
        list.positionViewAtIndex(index, ListView.Beginning)
    }
    function nextHunk(forward) {
        const at = list.indexAt(0, list.contentY + 1)
        const target = model ? model.hunkFrom(at < 0 ? 0 : at, forward) : -1
        if (target >= 0)
            positionAt(target)
    }

    onModelChanged: { textOffset = 0; widestText = 0 }
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
    onSyntaxPaletteChanged: if (model) model.setPalette(syntaxPalette)
    Component.onCompleted: if (model) model.setPalette(syntaxPalette)
    Connections {
        target: view.model
        function onCountChanged() { view.model.setPalette(view.syntaxPalette); syntaxTimer.restart() }
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
        anchors.fill: parent
        clip: true
        model: view.model
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        cacheBuffer: 360
        keyNavigationEnabled: false
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

            readonly property bool added: kind === "addition"
            readonly property bool deleted: kind === "deletion"
            readonly property bool fallback: kind === "binary" || kind === "image" || kind === "submodule"
                || kind === "modeOnly" || kind === "tooLarge" || invalid
            readonly property color fill: added ? Theme.colors.successBg
                : deleted ? GitColors.deletedBg
                : kind === "hunk" || kind === "noNewline" ? Theme.colors.paneAlt
                : Theme.colors.pane

            width: list.width
            height: loading ? GitLamaLayout.diffLineHeight
                : kind === "hunk" ? GitLamaLayout.hunkHeaderHeight
                : kind === "file" ? Theme.size.row
                : fallback ? GitLamaLayout.diffFallbackHeight
                : GitLamaLayout.diffLineHeight

            Rectangle {
                anchors.fill: parent
                color: line.fill
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

            // A file's header.
            Item {
                visible: line.kind === "file"
                anchors.fill: parent
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
            Row {
                visible: line.kind === "hunk"
                x: Theme.space.s5
                width: parent.width - x - Theme.space.s3
                height: parent.height
                spacing: Theme.space.s4
                MeridianText {
                    anchors.verticalCenter: parent.verticalCenter
                    role: MeridianText.CodeSm
                    text: line.hunkRange
                    color: Theme.colors.inkMuted
                }
                MeridianText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - x)
                    role: MeridianText.CodeSm
                    text: line.hunkText
                    elide: Text.ElideRight
                }
            }

            MeridianText {
                visible: line.kind === "noNewline"
                x: Theme.space.s5
                anchors.verticalCenter: parent.verticalCenter
                role: MeridianText.Caption
                text: L10n.t("diffNoNewline")
                color: Theme.colors.inkMuted
            }

            // Binary, image, submodule, mode-only and too-large files.
            MeridianEmptyState {
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
            }

            component Cell: Item {
                id: cell
                property bool oldSide: false
                property bool unified: true
                property string styled
                readonly property int number: oldSide ? line.oldLine : line.newLine
                readonly property bool blank: !unified && ((oldSide && line.added) || (!oldSide && line.deleted))
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
                            height: line.height
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
                        height: line.height
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
                            width: lineText.implicitWidth
                            // Changed words.
                            Repeater {
                                model: line.marks
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
                                anchors.verticalCenter: parent.verticalCenter
                                font: Theme.type.code
                                color: Theme.colors.ink
                                textFormat: cell.styled.length > 0 ? Text.StyledText : Text.PlainText
                                text: cell.styled.length > 0 ? cell.styled : line.text
                                onImplicitWidthChanged: if (implicitWidth > view.widestText) view.widestText = implicitWidth
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
                    visible: view.split
                    width: (parent.width - Metrics.hairline) / 2
                    unified: false
                    oldSide: false
                    styled: line.styledNew
                }
            }

            TapHandler {
                enabled: !line.loading
                onTapped: view.rowActivated(line.index, line.kind)
            }
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
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: view.gutters
        size: view.textWidth / Math.max(1, view.widestText)
        position: view.textOffset / Math.max(1, view.widestText)
        viewHovered: viewHover.hovered
        onPositionChanged: if (pressed) view.textOffset = position * view.widestText
    }
}
