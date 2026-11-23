pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Find in a diff (the Dart diff panes' search): Enter searches the whole
// diff in Rust and shows the first match (Shift+Enter the last); Enter again
// and the buttons step through the matches, wrapping around. A changed
// query or case setting searches again. `searcher` is the bridge that owns
// the diff (searchDiff, diffSearched); `view` the DiffView it scrolls and
// marks.
MeridianFindBar {
    id: find

    property var searcher: null
    property var view: null
    /// Changes when the diff does; a new diff clears the search.
    property var diffKey: null

    property string searchedQuery
    property bool searchedCase: false
    property var matches: []
    property bool pendingBackwards: false

    placeholder: L10n.t("diffSearchHint")
    previousLabel: L10n.t("diffPreviousMatch")
    nextLabel: L10n.t("diffNextMatch")
    caseSensitiveLabel: L10n.t("diffCaseSensitive")
    clearLabel: L10n.t("searchClear")
    noMatchesLabel: text === searchedQuery && caseSensitive === searchedCase ? L10n.t("findNoMatches") : ""
    positionText: (current, total) => L10n.tn("findMatchPosition", { current: current, total: total })
    countText: total => L10n.tn("findMatchCount", { count: total })
    caseSensitiveShown: true
    matchCount: matches.length

    function clear() {
        matches = []
        currentMatch = -1
        searchedQuery = ""
        searchedCase = caseSensitive
        if (view) {
            view.searchMatches = []
            view.currentSearch = -1
        }
    }
    function show() {
        if (!view)
            return
        view.searchMatches = matches
        view.currentSearch = currentMatch >= 0 ? matches[currentMatch] : -1
        if (currentMatch >= 0)
            view.positionAt(matches[currentMatch])
    }
    function run(backwards) {
        if (!searcher)
            return
        pendingBackwards = backwards
        searcher.searchDiff(text, caseSensitive)
    }
    function activate(backwards) {
        if (text.length === 0) {
            clear()
            return
        }
        if (text !== searchedQuery || caseSensitive !== searchedCase || matches.length === 0) {
            run(backwards)
            return
        }
        currentMatch = (currentMatch + (backwards ? matches.length - 1 : 1)) % matches.length
        show()
    }

    onDiffKeyChanged: if (text.length > 0) clear()
    onEdited: value => { if (value.length === 0) clear() }
    onNext: activate(false)
    onPrevious: activate(true)
    onCaseSensitiveToggled: value => {
        caseSensitive = value
        if (text.length > 0)
            run(false)
    }

    Connections {
        target: find.searcher
        function onDiffSearched(query, caseSensitive, rows) {
            if (query !== find.text || caseSensitive !== find.caseSensitive)
                return
            if (rows === null) {
                find.clear()
                return
            }
            find.searchedQuery = query
            find.searchedCase = caseSensitive
            find.matches = rows
            find.currentMatch = rows.length === 0 ? -1 : find.pendingBackwards ? rows.length - 1 : 0
            find.show()
        }
    }
}
