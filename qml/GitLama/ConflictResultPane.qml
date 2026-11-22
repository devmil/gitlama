pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls.Basic as C
import Meridian
import GitLamaNative

// The merge result (the Dart resolver's result pane): the editable text
// with each region's band (open, or taken from a side), the common
// ancestor on demand, and Resolve. Lines are as tall as comparison rows so
// unchanged text stays level across the panes.
Item {
    id: root

    property var file: null
    property var conflictState: ({})
    readonly property bool busy: conflictState.busy === true
    readonly property bool textFile: file !== null && file.kind === "text"
    readonly property bool compact: height < GitLamaLayout.conflictResultCompactHeight
    readonly property bool deletionChosen: file !== null && file.deletionChosen === true
    readonly property string sideChosen: file && file.side ? file.side : ""
    readonly property bool canResolve: !busy && (sideChosen.length > 0 || (textFile && file.markerFree === true))
    readonly property real rowHeight: GitLamaLayout.conflictComparisonRowHeight
    readonly property alias flick: flick
    property bool showAncestor: false
    property int _boundRevision: -1

    signal scrolled()

    readonly property string resolveLabel: deletionChosen ? L10n.t("conflictResolveByDeleting")
        : busy ? L10n.t("conflictSaving") : L10n.t("conflictResolveFile")
    readonly property string resolveIcon: deletionChosen ? "trash-2" : "save"

    // Takes the result text when Rust changes it (a choice, another file),
    // never while the user's own typing is what changed it.
    function bind() {
        if (!Store.conflicts || Store.conflicts.textRevision === _boundRevision)
            return
        _boundRevision = Store.conflicts.textRevision
        editor.text = Store.conflicts.resultText
    }
    Connections {
        target: Store.conflicts
        function onResultChanged() { root.bind() }
    }
    Component.onCompleted: bind()
    onFileChanged: if (file === null) showAncestor = false

    // The header: title, ancestor, external merge and Resolve.
    Rectangle {
        id: header
        width: parent.width
        height: Math.max(GitLamaLayout.conflictTitleMinHeight, actions.implicitHeight)
        color: Theme.colors.paneAlt
        MeridianText {
            x: Theme.space.s5
            anchors.verticalCenter: parent.verticalCenter
            width: actions.x - x - Theme.space.s4
            role: MeridianText.BodyStrong
            text: L10n.t("conflictResult")
        }
        Row {
            id: actions
            x: parent.width - width - Theme.space.s4
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s2
            MeridianButton {
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t("conflictExternalTool")
                iconName: "external-link"
                controlSize: MeridianButton.Small
                enabled: false
                disabledReason: L10n.t("conflictExternalUnavailable")
            }
            MeridianButton {
                visible: root.textFile && root.file.ancestorPresent === true
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t(root.showAncestor ? "conflictHideAncestor" : "conflictShowAncestor")
                variant: MeridianButton.Quiet
                controlSize: MeridianButton.Small
                onClicked: root.showAncestor = !root.showAncestor
            }
            MeridianButton {
                anchors.verticalCenter: parent.verticalCenter
                text: root.resolveLabel
                iconName: root.resolveIcon
                variant: MeridianButton.Primary
                controlSize: MeridianButton.Small
                enabled: root.canResolve
                onClicked: Store.conflicts.save()
            }
        }
    }

    // The common ancestor.
    Item {
        id: ancestor
        visible: root.showAncestor && root.textFile && root.file.ancestorPresent === true
        y: header.height
        width: parent.width
        height: visible ? Math.min(GitLamaLayout.conflictAncestorHeight, root.height * GitLamaLayout.resultMinHeightFraction) : 0
        Rectangle {
            id: ancestorTitle
            width: parent.width
            height: GitLamaLayout.conflictTitleHeight
            color: Theme.colors.paneAlt
            MeridianText {
                x: Theme.space.s5
                anchors.verticalCenter: parent.verticalCenter
                role: MeridianText.BodyStrong
                text: L10n.t("conflictAncestor")
            }
        }
        Flickable {
            id: ancestorFlick
            y: ancestorTitle.height
            width: parent.width
            height: parent.height - y
            clip: true
            contentHeight: ancestorText.implicitHeight + 2 * Theme.space.s4
            boundsBehavior: Flickable.StopAtBounds
            MeridianWheelScroll { flickable: ancestorFlick }
            MeridianSelectableText {
                id: ancestorText
                x: Theme.space.s4
                y: Theme.space.s4
                width: ancestorFlick.width - 2 * Theme.space.s4
                role: MeridianText.Code
                text: root.file && root.file.ancestor ? root.file.ancestor : ""
            }
        }
    }

    // A binary or huge file, or a chosen deletion: no text to edit.
    MeridianEmptyState {
        visible: !root.textFile || root.deletionChosen
        y: ancestor.y + ancestor.height
        width: parent.width
        height: footer.y - y
        compact: true
        iconName: root.deletionChosen ? "trash-2" : ""
        title: root.deletionChosen ? L10n.t("conflictDeletionResult")
            : root.sideChosen.length > 0 ? L10n.tn("conflictWholeFileChosenTitle",
                { branch: root.sideChosen === "current" ? (root.conflictState.currentLabel ?? "") : (root.conflictState.incomingLabel ?? "") })
            : root.file && root.file.kind === "binary" ? L10n.t("conflictBinaryFile") : L10n.t("conflictHugeFile")
        message: root.sideChosen.length === 0 && !root.textFile ? L10n.t("conflictChooseVersion") : ""
    }

    // The editor: bands under the text, lines as tall as comparison rows.
    Rectangle {
        id: well
        visible: root.textFile && !root.deletionChosen
        y: ancestor.y + ancestor.height
        width: parent.width
        height: footer.y - y
        color: Theme.colors.pane
        Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            contentWidth: Math.max(width, editor.implicitWidth)
            contentHeight: Math.max(height, editor.implicitHeight)
            boundsBehavior: Flickable.StopAtBounds
            MeridianWheelScroll { flickable: flick }
            C.ScrollBar.vertical: MeridianScrollBar {}
            C.ScrollBar.horizontal: MeridianScrollBar {}
            onContentYChanged: root.scrolled()

            Repeater {
                model: root.file && root.sideChosen.length === 0 ? (root.file.marks ?? []) : []
                delegate: Item {
                    required property var modelData
                    readonly property color fill: modelData.kind === "open" ? Theme.colors.attentionBg
                        : Qt.alpha(modelData.kind === "current" ? GitColors.sideOurs : GitColors.sideTheirs, GitLamaLayout.opacityConflictUnchosen)
                    readonly property color rail: modelData.kind === "open" ? Qt.alpha(Theme.colors.attention, GitLamaLayout.opacityConflictRailChosen)
                        : Qt.alpha(modelData.kind === "current" ? GitColors.sideOurs : GitColors.sideTheirs, GitLamaLayout.opacityConflictRailChosen)
                    y: editor.topPadding + modelData.first * root.rowHeight
                    width: flick.contentWidth
                    height: (modelData.last - modelData.first + 1) * root.rowHeight
                    Rectangle { anchors.fill: parent; color: parent.fill }
                    Rectangle { width: GitLamaLayout.conflictChoiceRail; height: parent.height; color: parent.rail }
                }
            }
            T.TextArea {
                id: editor
                width: flick.contentWidth
                implicitWidth: contentWidth + leftPadding + rightPadding
                implicitHeight: contentHeight + topPadding + bottomPadding
                leftPadding: Theme.space.s4
                rightPadding: Theme.space.s4
                topPadding: Theme.space.s3
                bottomPadding: Theme.space.s3
                wrapMode: TextEdit.NoWrap
                textFormat: TextEdit.PlainText
                font: Theme.type.code
                color: enabled ? Theme.colors.ink : Theme.colors.inkFaint
                selectionColor: Theme.colors.accentSoft
                selectedTextColor: Theme.colors.ink
                selectByMouse: true
                enabled: !root.busy
                Accessible.role: Accessible.EditableText
                Accessible.name: L10n.t("conflictResult")
                onTextChanged: if (root._boundRevision === Store.conflicts.textRevision && text !== Store.conflicts.resultText) Store.conflicts.editResult(text)
                onCursorRectangleChanged: {
                    if (!activeFocus)
                        return
                    if (cursorRectangle.y < flick.contentY)
                        flick.contentY = cursorRectangle.y
                    else if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height)
                        flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height + bottomPadding
                }
                TextFormatter { document: editor.textDocument; lineHeight: root.rowHeight }
            }
        }
    }

    // What is left to do.
    Item {
        id: footer
        visible: !root.compact
        y: parent.height - height
        width: parent.width
        height: visible ? footerText.implicitHeight + Theme.space.s2 + Theme.space.s4 : 0
        MeridianText {
            id: footerText
            x: Theme.space.s5
            y: Theme.space.s2
            width: parent.width - 2 * Theme.space.s5
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: root.sideChosen.length > 0 || !root.textFile ? ""
                : (root.file.markers ?? 0) === 0 ? L10n.t("conflictReviewResult")
                : L10n.tn("conflictRegionsRemaining", { count: root.file.markers })
        }
    }

    /// The result offset of a line's top.
    function lineTop(line) { return editor.topPadding + line * rowHeight }
}
