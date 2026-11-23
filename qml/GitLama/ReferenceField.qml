pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// A field for a branch, tag or commit name:
// typing filters `names` and `choices` into a list below it; Up, Down and
// Enter pick one, and Enter without a pick submits the dialog. `normalize`
// turns characters Git refuses in a ref name into "-" as QSpline does;
// `suggestSegments` completes one path segment of a new name at a time.
// The chevron opens every choice in a searchable picker. It is a
// searchable form picker, not an action menu.
Column {
    id: field

    property string label
    property alias text: input.text
    property var names: []
    /// [{value, description, icon}]: references with their target or subject.
    property var choices: []
    property bool normalize: false
    property bool suggestSegments: false
    property bool suggestions: true
    property string helperText
    property string selectionIcon: "branch"
    /// The label becomes the placeholder of a small field.
    property bool compact: false
    readonly property alias searchField: input
    signal edited()

    readonly property var allNames: {
        const seen = {}
        const all = []
        for (const name of names.concat(choices.map(choice => choice.value)))
            if (!seen[name]) { seen[name] = true; all.push(name) }
        return all
    }
    function choiceOf(name) {
        return choices.find(choice => choice.value === name) ?? ({ value: name, description: "", icon: selectionIcon })
    }
    // QSpline's typing assistance; Git stays the validator.
    function normalized(value) {
        return value.replace(/[\x00-\x20\x7f~^:?*\[\\]/g, "-").replace(/@\{/g, "@-").replace(/\.\./g, ".-")
    }
    // A full branch reference suggests its branch path.
    function branchPath(name) {
        if (name.startsWith("refs/heads/"))
            return name.substring(11)
        if (name.startsWith("refs/remotes/")) {
            const rest = name.substring(13)
            const slash = rest.indexOf("/")
            return slash < 0 ? rest : rest.substring(slash + 1)
        }
        return name
    }
    readonly property var matches: {
        if (!suggestions)
            return []
        const value = input.text
        if (!suggestSegments) {
            if (allNames.indexOf(value) >= 0)
                return []
            const query = value.toLowerCase()
            return allNames.filter(name => (name + " " + choiceOf(name).description).toLowerCase().indexOf(query) >= 0).slice(0, 50)
        }
        const cursor = input.cursorPosition
        const prefix = value.substring(0, cursor)
        if (prefix.length === 0)
            return []
        const slash = prefix.lastIndexOf("/")
        const parent = prefix.substring(0, slash + 1)
        const partial = prefix.substring(slash + 1).toLowerCase()
        const nextSlash = value.indexOf("/", cursor)
        const suffix = nextSlash < 0 ? "" : value.substring(nextSlash)
        const options = {}
        for (const original of names) {
            const name = branchPath(original)
            if (!name.startsWith(parent))
                continue
            const segment = name.substring(parent.length).split("/")[0]
            if (segment.toLowerCase().startsWith(partial))
                options[parent + segment + suffix] = true
        }
        // Offering what is already typed would make Enter a no-op pick.
        delete options[value]
        return Object.keys(options).sort()
    }
    property int highlighted: 0

    spacing: Theme.space.s2

    MeridianText {
        visible: !field.compact && field.label.length > 0
        role: MeridianText.Label
        text: field.label
        color: Theme.colors.ink
    }
    MeridianTextField {
        id: input
        width: field.compact ? Metrics.selectMinWidth : parent.width
        controlSize: field.compact ? MeridianButton.Small : MeridianButton.Regular
        placeholderText: field.compact ? field.label : ""
        iconName: field.selectionIcon
        Accessible.name: field.label
        onTextEdited: {
            if (field.normalize) {
                const fixed = field.normalized(text)
                if (fixed !== text) {
                    const cursor = cursorPosition
                    text = fixed
                    cursorPosition = cursor
                }
            }
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
                // Enter that picks nothing submits the dialog.
                event.accepted = false
            }
        }
        trailingContent: [
            MeridianIconButton {
                visible: field.suggestions && !field.suggestSegments && field.allNames.length > 0
                text: L10n.t("referencePickerTitle")
                iconName: "chevron-down"
                controlSize: MeridianButton.Small
                onClicked: picker.ask(field.label, field.allNames.map(name => field.choiceOf(name)))
            }
        ]
    }
    function pick(name) {
        input.text = name
        input.cursorPosition = name.length
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
                readonly property var choice: field.choiceOf(modelData)
                width: list.width
                text: modelData
                meta: choice.description.length > 12 && /^[0-9a-f]+$/.test(choice.description)
                    ? choice.description.substring(0, 8) : choice.description
                iconName: choice.icon
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
    ReferencePickerDialog {
        id: picker
        onChosen: value => {
            field.pick(value)
            input.forceActiveFocus()
        }
    }
}
