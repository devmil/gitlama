pragma ComponentBehavior: Bound
import QtQuick

// Finds text in the content it sits above (Flutter: MeridianFindBar): a
// search field with the position of the current match ("3 of 12"),
// Previous and Next, optional toggles for case, whole words and regular
// expressions, the owner's own `trailing` controls and Close.
//
// The bar is controlled: the owner searches and reports `matchCount`,
// `currentMatch` and `searching`. Typing emits `edited`; Enter emits `next`
// and Shift+Enter `previous`, also before the first search (so the owner can
// search on Enter); the buttons step through matches once there are some.
// Escape clears the query (emitting `edited("")`) and, on an empty field,
// emits `closeRequested` when `closable`. Small by default; the field is
// `fieldWidth` wide and gives way first; when even the narrowest field does
// not fit beside the buttons, it takes the whole width and the buttons move
// below it.
Item {
    id: bar

    property alias text: input.text
    property int matchCount: 0
    /// The current match, from 0; -1 while none is current.
    property int currentMatch: -1
    property bool searching: false
    property bool caseSensitiveShown: false
    property bool caseSensitive: false
    property bool wholeWordShown: false
    property bool wholeWord: false
    property bool regexShown: false
    property bool regex: false
    property bool closable: false
    property int controlSize: MeridianButton.Small
    property real fieldWidth: Metrics.findFieldWidth
    /// A query the owner cannot search (an invalid regular expression).
    property string errorText
    /// The owner's own controls after the toggles: small icon buttons.
    property alias trailing: trailingRow.data
    readonly property alias searchField: input

    property string placeholder: "Find"
    property string previousLabel: "Previous match"
    property string nextLabel: "Next match"
    property string caseSensitiveLabel: "Match case"
    property string wholeWordLabel: "Whole word"
    property string regexLabel: "Regular expression"
    property string clearLabel: "Clear search"
    property string closeLabel: "Close find"
    property string searchingLabel: "Searching…"
    property string noMatchesLabel: "No matches"
    /// "3 of 12" and "12 matches".
    property var positionText: (current, total) => current + " of " + total
    property var countText: total => total === 1 ? "1 match" : total + " matches"

    signal edited(string text)
    signal next()
    signal previous()
    signal caseSensitiveToggled(bool value)
    signal wholeWordToggled(bool value)
    signal regexToggled(bool value)
    signal closeRequested()

    readonly property string counter: {
        if (searching)
            return searchingLabel
        if (input.text.length === 0)
            return ""
        if (matchCount <= 0)
            return noMatchesLabel
        if (currentMatch < 0 || currentMatch >= matchCount)
            return countText(matchCount)
        return positionText(currentMatch + 1, matchCount)
    }
    readonly property real minField: Metrics.findFieldMinWidth + buttons.height
    readonly property bool stacked: width > 0 && width - buttons.implicitWidth - Theme.space.s1 < minField

    implicitWidth: fieldWidth + Theme.space.s1 + buttons.implicitWidth
    implicitHeight: stacked ? input.height + Theme.space.s1 + buttons.height + (errorLabel.visible ? errorLabel.implicitHeight : 0)
                            : Math.max(input.height, buttons.height) + (errorLabel.visible ? errorLabel.implicitHeight : 0)

    Accessible.role: Accessible.Grouping
    Accessible.name: placeholder

    MeridianTextField {
        id: input
        width: bar.stacked ? bar.width : Math.max(bar.minField, Math.min(bar.fieldWidth, bar.width - buttons.implicitWidth - Theme.space.s1))
        variant: MeridianTextField.Search
        controlSize: bar.controlSize
        placeholderText: bar.placeholder
        clearLabel: bar.clearLabel
        trailingText: bar.counter
        error: bar.errorText.length > 0
        inputMethodHints: Qt.ImhNoPredictiveText
        Accessible.name: bar.placeholder
        onTextEdited: bar.edited(text)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (text.length > 0) {
                    text = ""
                    event.accepted = true
                } else if (bar.closable) {
                    bar.closeRequested()
                    event.accepted = true
                }
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (event.modifiers & Qt.ShiftModifier)
                    bar.previous()
                else
                    bar.next()
                event.accepted = true
            }
        }
        // The clear button empties the query.
        onTextChanged: if (text.length === 0 && activeFocus) bar.edited("")
    }
    Row {
        id: buttons
        x: bar.stacked ? bar.width - width : input.width + Theme.space.s1
        y: bar.stacked ? input.height + Theme.space.s1 : (input.height - height) / 2
        spacing: 0
        MeridianIconButton {
            objectName: "meridian-find-previous"
            text: bar.previousLabel
            iconName: "chevron-up"
            controlSize: bar.controlSize
            enabled: bar.enabled && bar.matchCount > 0
            onClicked: bar.previous()
        }
        MeridianIconButton {
            objectName: "meridian-find-next"
            text: bar.nextLabel
            iconName: "chevron-down"
            controlSize: bar.controlSize
            enabled: bar.enabled && bar.matchCount > 0
            onClicked: bar.next()
        }
        MeridianIconButton {
            objectName: "meridian-find-case"
            visible: bar.caseSensitiveShown
            text: bar.caseSensitiveLabel
            iconName: "case-sensitive"
            controlSize: bar.controlSize
            active: bar.caseSensitive
            onClicked: bar.caseSensitiveToggled(!bar.caseSensitive)
        }
        MeridianIconButton {
            objectName: "meridian-find-word"
            visible: bar.wholeWordShown
            text: bar.wholeWordLabel
            iconName: "whole-word"
            controlSize: bar.controlSize
            active: bar.wholeWord
            onClicked: bar.wholeWordToggled(!bar.wholeWord)
        }
        MeridianIconButton {
            objectName: "meridian-find-regex"
            visible: bar.regexShown
            text: bar.regexLabel
            iconName: "regex"
            controlSize: bar.controlSize
            active: bar.regex
            onClicked: bar.regexToggled(!bar.regex)
        }
        Row { id: trailingRow }
        Item { visible: bar.closable; width: Theme.space.s1; height: 1 }
        MeridianIconButton {
            objectName: "meridian-find-close"
            visible: bar.closable
            text: bar.closeLabel
            iconName: "x"
            controlSize: bar.controlSize
            onClicked: bar.closeRequested()
        }
    }
    MeridianText {
        id: errorLabel
        visible: bar.errorText.length > 0
        y: bar.stacked ? buttons.y + buttons.height : input.height
        width: input.width
        role: MeridianText.Caption
        color: Theme.colors.danger
        wrapMode: Text.Wrap
        text: bar.errorText
    }
}
