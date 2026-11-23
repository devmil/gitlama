pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Issue and pull request references in a text field (the Dart
// HostingReferenceTextField): typing `#` and a query lists the bound
// repository's issues and pull requests under the caret; Up, Down, Page Up,
// Page Down and Enter pick one, Escape closes the list and restores the
// selection. Put one next to a field, set `target`, and let the field's
// keys reach `handleKey` first.
Item {
    id: assist

    /// The text control (a TextInput or TextEdit).
    property Item target: null
    readonly property var field: target
    property int revision: 0
    property var projection: null
    property int selected: 0
    property bool applying: false
    property var restoreSelection: null
    readonly property bool open: projection !== null

    function project() {
        if (!field || !field.activeFocus || !Store.hosting) {
            close()
            return
        }
        // The selection's fixed end, then the end the caret is at.
        const base = field.cursorPosition === field.selectionEnd ? field.selectionStart : field.selectionEnd
        const next = Store.hosting.projectReference(field.text, base, field.cursorPosition, revision)
        if (next === null) {
            close()
            return
        }
        if (projection === null)
            restoreSelection = { start: field.selectionStart, end: field.selectionEnd }
        projection = next
        selected = Math.max(0, Math.min(selected, next.candidates.length - 1))
        place()
    }
    function close() {
        projection = null
        restoreSelection = null
        selected = 0
    }
    function apply(candidate) {
        const result = Store.hosting.applyReference(field.text, revision, candidate.insertion)
        close()
        if (result === null)
            return
        applying = true
        field.text = result.text
        field.cursorPosition = result.caret
        revision += 1
        applying = false
        field.forceActiveFocus()
    }
    /// Handles a key while the list is open; true when it was used.
    function handleKey(event) {
        if (!open)
            return false
        if (event.key === Qt.Key_Escape) {
            const selection = restoreSelection
            close()
            if (selection)
                field.select(Math.min(selection.start, field.length), Math.min(selection.end, field.length))
            return true
        }
        const count = projection.candidates.length
        if (count === 0)
            return false
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            apply(projection.candidates[selected])
            return true
        }
        const delta = event.key === Qt.Key_Down ? 1 : event.key === Qt.Key_Up ? -1
            : event.key === Qt.Key_PageDown ? 5 : event.key === Qt.Key_PageUp ? -5 : 0
        if (delta === 0)
            return false
        selected = Math.max(0, Math.min(count - 1, selected + delta))
        return true
    }
    // Under the caret, within the field's width.
    function place() {
        const window = assist.Window.contentItem
        if (!window || !field)
            return
        list.parent = window
        const caret = field.cursorRectangle
        const width = Math.max(GitLamaLayout.referenceSuggestionMinWidth, Math.min(GitLamaLayout.referenceSuggestionMaxWidth, field.width))
        const at = field.mapToItem(window, Math.max(0, Math.min(caret.x, field.width - width)), caret.y + caret.height + Theme.space.s1)
        list.x = at.x
        list.y = at.y
        list.width = width
    }

    Connections {
        target: assist.field
        function onTextChanged() {
            if (assist.applying)
                return
            assist.revision += 1
            assist.project()
        }
        function onCursorPositionChanged() { if (!assist.applying) assist.project() }
        function onActiveFocusChanged() { if (!assist.field.activeFocus) assist.close() }
    }

    Rectangle {
        id: list
        objectName: "hosting-reference-results"
        visible: assist.open
        z: 1000
        height: assist.open ? Math.min(GitLamaLayout.gitSuggestionMaxHeight, content.implicitHeight + 2 * Theme.space.s1) : 0
        radius: Theme.radius.md
        color: Theme.colors.raised
        border.width: Metrics.hairline
        border.color: Theme.colors.line
        MeridianShadow { anchors.fill: parent; layers: Theme.shadows.float; radius: parent.radius; z: -1 }
        Column {
            id: content
            x: Theme.space.s1
            y: Theme.space.s1
            width: parent.width - 2 * Theme.space.s1
            MeridianText {
                visible: assist.open && assist.projection.candidates.length === 0
                width: parent.width
                padding: Theme.space.s5
                text: L10n.t("hostingReferenceEmpty")
                wrapMode: Text.Wrap
            }
            Repeater {
                model: assist.open ? assist.projection.candidates : []
                delegate: MeridianListRow {
                    required property var modelData
                    required property int index
                    objectName: "hosting-reference-" + modelData.stableId
                    width: content.width
                    text: modelData.insertion
                    meta: modelData.stale ? L10n.t("hostingStale") : modelData.title
                    iconName: "cloud"
                    selected: index === assist.selected
                    focusPolicy: Qt.NoFocus
                    onClicked: assist.apply(modelData)
                }
            }
        }
    }
}
