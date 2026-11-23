pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The blame lens (the Dart BlameCodeView): each line with the commit that
// last changed it in a band at the left (author and age where a commit's
// run starts), its number and its text. Clicking a band blames the file
// before that change; the context menu shows the commit, the line's
// history, or copies the hash.
Item {
    id: root

    readonly property real lineHeight: GitLamaLayout.diffLineHeight
    property real widest: 0

    // How long ago the line changed, compactly (the Dart _blameAge).
    function age(seconds) {
        if (seconds <= 0)
            return ""
        const elapsed = Math.max(0, Math.floor(Date.now() / 1000) - seconds)
        if (elapsed < 3600)
            return L10n.tn("blameAgeMinutes", { count: Math.max(1, Math.floor(elapsed / 60)) })
        if (elapsed < 86400)
            return L10n.tn("blameAgeHours", { count: Math.floor(elapsed / 3600) })
        if (elapsed < 86400 * 30)
            return L10n.tn("blameAgeDays", { count: Math.floor(elapsed / 86400) })
        if (elapsed < 86400 * 365)
            return L10n.tn("blameAgeMonths", { count: Math.floor(elapsed / (86400 * 30)) })
        return L10n.tn("blameAgeYears", { count: Math.floor(elapsed / (86400 * 365)) })
    }

    CommandMenu {
        id: lineMenu
        onSelected: value => { if (typeof value === "function") value() }
    }

    ListView {
        id: list
        objectName: "blame-code"
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickIfNeeded
        contentWidth: Math.max(width, GitLamaLayout.blameBandWidth + GitLamaLayout.diffGutterWidth + root.widest + Theme.space.s6)
        model: Store.inspectorBlame
        MeridianWheelScroll { flickable: list }
        C.ScrollBar.vertical: MeridianScrollBar {}
        C.ScrollBar.horizontal: MeridianScrollBar {}
        delegate: Rectangle {
            id: row
            required property int index
            required property bool loading
            required property int line
            required property var content
            required property var commit
            required property var author
            required property var summary
            required property var authorTime
            required property var boundary
            required property var groupStart
            required property var groupEnd
            readonly property bool hasCommit: !loading && (commit ?? "").length > 0
            width: list.contentWidth
            height: root.lineHeight
            color: index % 2 === 0 ? Theme.colors.pane : Qt.alpha(Theme.colors.paneAlt, GitLamaLayout.opacityUnlit)
            Component.onCompleted: if (loading) Store.inspector.ensureBlameRow(index)
            onLoadingChanged: if (loading) Store.inspector.ensureBlameRow(index)

            // The commit band.
            Rectangle {
                id: band
                width: GitLamaLayout.blameBandWidth
                height: parent.height
                color: row.hasCommit ? Qt.alpha(Theme.colors.paneAlt, 0.65) : "transparent"
                Rectangle { width: GitLamaLayout.diffPickRail; height: parent.height; color: row.hasCommit ? Theme.colors.line : Theme.colors.pane }
                Rectangle { visible: row.groupStart === true; width: parent.width; height: Metrics.hairline; color: Theme.colors.line }
                Rectangle { visible: row.groupEnd === true; y: parent.height - height; width: parent.width; height: Metrics.hairline; color: Theme.colors.line }
                Row {
                    x: Theme.space.s4
                    width: parent.width - 2 * Theme.space.s4
                    height: parent.height
                    spacing: Theme.space.s2
                    AuthorAvatar {
                        visible: row.groupStart === true && (row.author ?? "").length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        author: row.author ?? ""
                    }
                    MeridianText {
                        width: parent.width - ageText.width - (row.groupStart === true ? Metrics.avatarSmall + 2 * parent.spacing : parent.spacing)
                        height: parent.height
                        role: MeridianText.Caption
                        text: row.groupStart === true ? (row.author ?? "") : ""
                    }
                    MeridianText {
                        id: ageText
                        visible: row.groupStart === true
                        height: parent.height
                        role: MeridianText.Caption
                        color: Theme.colors.inkMuted
                        text: row.groupStart === true ? root.age(row.authorTime ?? 0) : ""
                    }
                }
                HoverHandler { id: bandHover; cursorShape: row.hasCommit && !row.boundary ? Qt.PointingHandCursor : Qt.ArrowCursor }
                MeridianTooltip {
                    shown: bandHover.hovered
                    text: row.loading ? L10n.t("historyInspectionLoading")
                        : (row.author ?? "") + " · " + (row.summary ?? "") + (row.hasCommit && !row.boundary ? " · " + L10n.t("historyBlameBefore") : "")
                }
                TapHandler {
                    enabled: row.hasCommit && row.boundary !== true
                    onTapped: Store.inspector.blameBefore(row.index)
                }
            }
            MeridianHairline { x: band.width; vertical: true; height: parent.height }
            MeridianText {
                x: band.width + Metrics.hairline
                width: GitLamaLayout.diffGutterWidth - Theme.space.s4
                height: parent.height
                horizontalAlignment: Text.AlignRight
                role: MeridianText.CodeSm
                tabular: true
                color: Theme.colors.inkMuted
                text: String(row.line)
            }
            MeridianText {
                x: band.width + Metrics.hairline + GitLamaLayout.diffGutterWidth
                height: parent.height
                role: MeridianText.Code
                elide: Text.ElideNone
                text: row.loading ? "" : (row.content ?? "")
                onImplicitWidthChanged: if (implicitWidth > root.widest) root.widest = implicitWidth
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                enabled: !row.loading
                onTapped: point => {
                    const items = []
                    if (row.hasCommit)
                        items.push({ title: L10n.t("inspectorShowCommit"), icon: "git-commit-horizontal", value: () => Store.inspector.showCommit(row.commit) })
                    if (row.hasCommit && row.boundary !== true)
                        items.push({ title: L10n.t("inspectorBlameBefore"), icon: "blame", value: () => Store.inspector.blameBefore(row.index) })
                    items.push({ title: L10n.t("inspectorLineHistory"), icon: "history", value: () => Store.inspector.lineHistory(row.line, row.line) })
                    if (row.hasCommit) {
                        items.push({ separator: true })
                        items.push({ title: L10n.t("fileActionCopyCommitHash"), icon: "copy",
                                     value: () => Store.actions.copyText(row.commit, L10n.t("menuCommitHashCopied")) })
                    }
                    lineMenu.items = items
                    lineMenu.show(row, point.position.x, point.position.y)
                }
            }
        }
    }
}
