pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The shown commit's summary (CommitSummaryCard): subject, author, date,
// hash and parents; disclosed, the author, co-authors, committer, commit
// date and the message body. A long message scrolls inside the card.
Rectangle {
    id: card

    /// The inspector's `summary`.
    property var summary: ({})
    property var refs: []
    property bool expanded: false
    signal parentSelected(string commit)

    readonly property string author: summary.author ?? ""
    readonly property string committer: summary.committer ?? ""
    readonly property string coauthors: {
        const matches = (summary.message ?? "").match(/^Co-authored-by:\s*(.+)$/gmi) ?? []
        return matches.map(line => line.replace(/^Co-authored-by:\s*/i, "")).join(", ")
    }
    function when(seconds) {
        if (!seconds)
            return ""
        const date = new Date(seconds * 1000)
        return date.toLocaleDateString(Qt.locale(L10n.locale), "MMM d, yyyy") + " · "
            + date.toLocaleTimeString(Qt.locale(L10n.locale), "HH:mm")
    }
    readonly property string authorDate: when(summary.authorTime)
    readonly property string commitDate: when(summary.committerTime)

    color: Theme.colors.pane
    implicitHeight: content.implicitHeight + 2 * Theme.space.s5

    Flickable {
        id: scroller
        objectName: "commit-summary-scroll"
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + 2 * Theme.space.s5
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        MeridianWheelScroll { flickable: scroller }
        C.ScrollBar.vertical: MeridianScrollBar {}

        Column {
            id: content
            x: Theme.space.s5
            y: Theme.space.s5
            width: scroller.width - 2 * Theme.space.s5
            spacing: Theme.space.s3

            Item {
                width: parent.width
                height: subject.implicitHeight
                MeridianText {
                    id: subject
                    width: parent.width - toggle.width - Theme.space.s3
                    role: MeridianText.Heading
                    text: card.summary.subject ?? ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                // The header discloses the details (MeridianDisclosure).
                MeridianIcon {
                    id: toggle
                    anchors.right: parent.right
                    y: (Theme.type.headingLineHeight - height) / 2
                    name: "chevron-down"
                    iconSize: MeridianIcon.Small
                    color: Theme.colors.inkMuted
                    rotation: card.expanded ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: Motion.quick } }
                }
                TapHandler { onTapped: card.expanded = !card.expanded }
                Accessible.role: Accessible.Button
                Accessible.name: subject.text
            }
            Flow {
                width: parent.width
                spacing: Theme.space.s4
                AuthorAvatar {
                    author: card.author
                    avatarHash: card.summary.avatarHash ?? ""
                }
                MeridianText {
                    role: MeridianText.Label
                    fontWeight: Font.DemiBold
                    text: card.author
                }
                MeridianText {
                    role: MeridianText.Label
                    text: card.authorDate
                    color: Theme.colors.inkMuted
                }
                Rectangle {
                    width: hash.implicitWidth + 12
                    height: hash.implicitHeight + 2
                    radius: Theme.radius.sm
                    color: Theme.colors.paneAlt
                    border.color: Theme.colors.line
                    MeridianText {
                        id: hash
                        anchors.centerIn: parent
                        role: MeridianText.CodeSm
                        text: (card.summary.commit ?? "").substring(0, 10)
                        color: Theme.colors.inkMuted
                    }
                }
                Repeater {
                    model: card.summary.parents ?? []
                    delegate: MeridianText {
                        id: parentLink
                        required property string modelData
                        role: MeridianText.CodeSm
                        text: "← " + modelData.substring(0, 10)
                        color: Theme.colors.accentInk
                        HoverHandler { id: parentHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: card.parentSelected(parentLink.modelData) }
                        MeridianTooltip { shown: parentHover.hovered; text: parentLink.modelData }
                    }
                }
            }
            Flow {
                visible: card.refs.length > 0
                width: parent.width
                spacing: Theme.space.s2
                Repeater {
                    model: card.refs
                    delegate: RefChip {
                        required property var modelData
                        name: modelData.label
                        kind: modelData.kind === "remote" ? "remote" : modelData.kind === "tag" ? "tag" : "local"
                    }
                }
            }
            MeridianReveal {
                width: parent.width
                shown: card.expanded
                Column {
                    width: parent.width
                    spacing: Theme.space.s3
                    MeridianHairline { width: parent.width }
                    MeridianPropertyList {
                        width: parent.width
                        properties: {
                            const list = [{ label: L10n.t("historyAuthor"), value: card.author }]
                            if (card.coauthors.length > 0)
                                list.push({ label: L10n.t("historyCoAuthors"), value: card.coauthors })
                            if (card.committer !== card.author)
                                list.push({ label: L10n.t("historyCommitter"), value: card.committer })
                            if (card.commitDate !== card.authorDate)
                                list.push({ label: L10n.t("historyCommitDate"), value: card.commitDate })
                            return list
                        }
                    }
                    MeridianSelectableText {
                        visible: text.length > 0
                        width: parent.width
                        text: card.summary.body ?? ""
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
