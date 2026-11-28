pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// One file at the inspected commit: its path and size with a find bar, then line
// numbers and read-only text; a file that is not UTF-8 text shows as text
// on request. Matching lines are marked, the current one stronger.
Item {
    id: root

    property var contents: null
    property string failure: ""
    property string path
    property bool forceText: false
    readonly property var lines: contents && contents.lines ? contents.lines : []
    property var matches: []
    property int match: -1
    readonly property var matchSet: {
        const set = {}
        for (const line of matches)
            set[line] = true
        return set
    }

    onContentsChanged: {
        forceText = false
        search()
    }

    function search() {
        const query = find.caseSensitive ? find.text : find.text.toLowerCase()
        if (query.length === 0 || lines.length === 0) {
            matches = []
            match = -1
            return
        }
        const found = []
        for (let index = 0; index < lines.length; index += 1) {
            const line = find.caseSensitive ? lines[index] : lines[index].toLowerCase()
            if (line.indexOf(query) >= 0)
                found.push(index)
        }
        matches = found
        match = found.length === 0 ? -1 : 0
        jump()
    }
    function findText(query) {
        find.text = query
        search()
    }
    function move(delta) {
        if (matches.length === 0)
            return
        match = (match + delta + matches.length) % matches.length
        jump()
    }
    function jump() {
        if (match < 0)
            return
        list.contentY = Math.max(0, Math.min((matches[match] - 2) * GitLamaLayout.diffLineHeight,
                                             list.contentHeight - list.height))
    }

    MeridianSectionHeader {
        id: contentsHeader
        width: parent.width
        color: Theme.colors.pane
        title: root.path
        caption: root.contents && root.contents.size !== undefined ? root.contents.size + " B" : ""
        MeridianFindBar {
            id: find
            objectName: "inspector-contents-search"
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            placeholder: L10n.t("findInFileHint")
            previousLabel: L10n.t("diffPreviousMatch")
            nextLabel: L10n.t("diffNextMatch")
            caseSensitiveLabel: L10n.t("diffCaseSensitive")
            clearLabel: L10n.t("searchClear")
            searchingLabel: L10n.t("findSearching")
            noMatchesLabel: L10n.t("findNoMatches")
            positionText: (current, total) => L10n.tn("findMatchPosition", { current: current, total: total })
            countText: total => L10n.tn("findMatchCount", { count: total })
            caseSensitiveShown: true
            matchCount: root.matches.length
            currentMatch: root.match
            onEdited: root.search()
            onNext: root.move(1)
            onPrevious: root.move(-1)
            onCaseSensitiveToggled: value => {
                caseSensitive = value
                root.search()
            }
        }
    }

    MeridianEmptyState {
        anchors.top: contentsHeader.bottom
        visible: root.failure.length > 0 || root.contents === null || root.contents.empty === true
            || (root.contents.binary === true && !root.forceText)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        compact: true
        iconName: root.failure.length > 0 ? "circle-alert" : ""
        progress: root.failure.length === 0 && root.contents === null
        title: root.failure === "tooLarge" ? L10n.t("historyTreeFileTooLarge")
            : root.failure.length > 0 ? L10n.t("historyTreeFileFailed")
            : root.contents === null ? L10n.t("loading")
            : root.contents.empty === true ? L10n.t("historyTreeEmptyFile")
            : L10n.t("historyTreeBinaryFile")
        MeridianButton {
            visible: root.contents !== null && root.contents.binary === true && !root.forceText
            text: L10n.t("showBinaryAsText")
            variant: MeridianButton.Secondary
            onClicked: root.forceText = true
        }
    }
    ListView {
        id: list
        objectName: "commit-file-content"
        visible: root.lines.length > 0 && (root.contents.binary !== true || root.forceText)
        anchors.top: contentsHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickIfNeeded
        contentWidth: Math.max(width, widest + GitLamaLayout.diffGutterWidth + GitLamaLayout.diffSignWidth + Theme.space.s6)
        property real widest: 0
        model: root.lines
        MeridianWheelScroll { flickable: list }
        C.ScrollBar.vertical: MeridianScrollBar {}
        C.ScrollBar.horizontal: MeridianScrollBar {}
        delegate: Item {
            id: line
            required property string modelData
            required property int index
            width: list.contentWidth
            height: GitLamaLayout.diffLineHeight
            Rectangle {
                anchors.fill: parent
                visible: root.matchSet[line.index] === true
                color: root.match >= 0 && root.matches[root.match] === line.index ? Theme.colors.accentSoft : Theme.colors.paneHover
            }
            MeridianText {
                width: GitLamaLayout.diffGutterWidth - Theme.space.s4
                height: parent.height
                horizontalAlignment: Text.AlignRight
                role: MeridianText.CodeSm
                tabular: true
                color: Theme.colors.inkMuted
                text: String(line.index + 1)
            }
            MeridianSelectableText {
                x: GitLamaLayout.diffGutterWidth + GitLamaLayout.diffSignWidth
                anchors.verticalCenter: parent.verticalCenter
                role: MeridianText.Code
                text: line.modelData
                onImplicitWidthChanged: if (implicitWidth > list.widest) list.widest = implicitWidth
            }
        }
    }
}
