pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// One file at the inspected commit (the Dart CommitFileContentView): line
// numbers and read-only text; a file that is not UTF-8 text shows as text
// on request.
Item {
    id: root

    property var contents: null
    property string failure: ""
    property bool forceText: false
    readonly property var lines: contents && contents.lines ? contents.lines : []

    onContentsChanged: forceText = false

    MeridianEmptyState {
        visible: root.failure.length > 0 || root.contents === null || root.contents.empty === true
            || (root.contents.binary === true && !root.forceText)
        anchors.fill: parent
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
        anchors.fill: parent
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
