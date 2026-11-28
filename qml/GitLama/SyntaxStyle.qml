pragma Singleton
import QtQuick
import Meridian

// Syntax colours for texts GitLama colours itself (the conflict resolver's sides, ancestor
// and result): the palette by category, and a line with its runs as styled text.
QtObject {
    /// Colour by category, as the Rust side names them.
    readonly property var palette: ({
        comment: Theme.colors.syntaxComment, keyword: Theme.colors.syntaxKeyword,
        string: Theme.colors.syntaxString, number: Theme.colors.syntaxNumber,
        type: Theme.colors.syntaxType, function: Theme.colors.syntaxFunction,
        variable: Theme.colors.syntaxVariable, constant: Theme.colors.syntaxConstant,
        operator: Theme.colors.syntaxOperator, punctuation: Theme.colors.syntaxPunctuation,
        attribute: Theme.colors.syntaxAttribute, tag: Theme.colors.syntaxTag
    })

    function _escape(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;").replace(/ /g, "&nbsp;")
    }

    /// `text` coloured by `runs` ([start, end, category] over UTF-16 offsets) as styled
    /// text, or "" when nothing is coloured.
    function styled(text, runs) {
        if (!runs || runs.length === 0 || text.length === 0)
            return ""
        let out = ""
        let cursor = 0
        let coloured = false
        for (const run of runs) {
            const start = Math.min(run[0], text.length)
            const end = Math.min(run[1], text.length)
            const colour = palette[run[2]]
            if (start < cursor || end <= start || colour === undefined)
                continue
            out += _escape(text.substring(cursor, start))
            out += "<font color=\"" + colour + "\">" + _escape(text.substring(start, end)) + "</font>"
            cursor = end
            coloured = true
        }
        return coloured ? out + _escape(text.substring(cursor)) : ""
    }
}
