pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// A field for a branch, tag or commit name (GitReferenceField): typing
// filters `names` into a list below it; Up, Down and Enter pick one. It is
// a searchable form picker, not an action menu.
Column {
    id: field

    property string label
    property alias text: input.text
    property var names: []
    property string helperText
    property string selectionIcon: "branch"
    signal edited()

    readonly property var matches: {
        const query = input.text.trim().toLowerCase()
        const all = names.filter(name => query.length === 0 || name.toLowerCase().indexOf(query) >= 0)
        return all.slice(0, 50)
    }
    property int highlighted: 0

    spacing: Theme.space.s2

    MeridianText {
        role: MeridianText.Label
        text: field.label
        color: Theme.colors.ink
    }
    MeridianTextField {
        id: input
        width: parent.width
        Accessible.name: field.label
        onTextEdited: {
            field.highlighted = 0
            suggestions.visible = activeFocus && field.matches.length > 0
            field.edited()
        }
        onActiveFocusChanged: if (!activeFocus) suggestions.visible = false
        Keys.onDownPressed: {
            if (!suggestions.visible && field.matches.length > 0) suggestions.visible = true
            else field.highlighted = Math.min(field.matches.length - 1, field.highlighted + 1)
        }
        Keys.onUpPressed: field.highlighted = Math.max(0, field.highlighted - 1)
        Keys.onEscapePressed: event => {
            if (suggestions.visible) { suggestions.visible = false; event.accepted = true }
            else event.accepted = false
        }
        Keys.onReturnPressed: event => {
            if (suggestions.visible && field.matches.length > 0) {
                field.pick(field.matches[field.highlighted])
                event.accepted = true
            } else {
                event.accepted = false
            }
        }
    }
    function pick(name) {
        input.text = name
        suggestions.visible = false
        field.edited()
    }
    Rectangle {
        id: suggestions
        visible: false
        width: parent.width
        height: Math.min(GitLamaLayout.gitSuggestionMaxHeight, list.contentHeight + 2 * Theme.space.s1)
        radius: Theme.radius.md
        color: Theme.colors.raised
        border.color: Theme.colors.line
        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: Theme.space.s1
            clip: true
            model: field.matches
            currentIndex: field.highlighted
            delegate: MeridianListRow {
                required property string modelData
                required property int index
                width: list.width
                text: modelData
                iconName: field.selectionIcon
                selected: index === field.highlighted
                focusPolicy: Qt.NoFocus
                onClicked: field.pick(modelData)
            }
        }
    }
    MeridianText {
        visible: field.helperText.length > 0
        width: parent.width
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        text: field.helperText
        wrapMode: Text.Wrap
    }
}
