import QtQuick
import Meridian

// One file of a file list (GitLamaFileRow): status glyph, the folder in
// `ink-muted` (elided from its start) and the name. Full width like a list
// row so file and folder rows of one tree share the selection fill.
Item {
    id: row

    property string path
    property string status
    property bool partial: false
    property bool selected: false
    property int depth: 0
    /// A folder row of a tree: chevron instead of a status glyph.
    property bool folder: false
    property bool expanded: false
    property bool showDirectory: true

    signal clicked()
    signal contextMenuRequested(real x, real y)

    readonly property int slash: path.lastIndexOf("/")
    readonly property string directory: !showDirectory || slash < 0 ? "" : path.substring(0, slash + 1)
    readonly property string name: path.substring(slash + 1)

    implicitHeight: Theme.size.row
    activeFocusOnTab: true

    Accessible.role: Accessible.ListItem
    Accessible.name: status.length > 0 ? status + ", " + path : path
    Accessible.selected: selected

    Keys.onReturnPressed: row.clicked()
    Keys.onSpacePressed: row.clicked()

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius.sm
        color: row.selected ? Theme.colors.accentSoft
            : hover.hovered ? Theme.colors.paneHover : Theme.clear(Theme.colors.paneHover)
        Behavior on color { ColorAnimation { duration: row.selected ? Motion.select : Motion.hoverFor(hover.hovered) } }
        MeridianFocusRing { target: row; shown: row.activeFocus; targetRadius: Theme.radius.sm }
    }

    Row {
        x: Theme.space.s4 + Theme.space.s2 + row.depth * Metrics.treeIndent
        width: row.width - x - Theme.space.s4 - Theme.space.s2
        height: parent.height
        spacing: Theme.space.s4

        Item {
            width: GitLamaLayout.glyphSize
            height: GitLamaLayout.glyphSize
            anchors.verticalCenter: parent.verticalCenter
            MeridianIcon {
                visible: row.folder
                anchors.centerIn: parent
                name: row.expanded ? "chevron-down" : "chevron-right"
                iconSize: MeridianIcon.Small
                color: Theme.colors.inkMuted
            }
            StatusGlyph {
                visible: !row.folder && row.status.length > 0
                anchors.centerIn: parent
                status: row.status
                partial: row.partial
            }
        }
        Row {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - GitLamaLayout.glyphSize - parent.spacing
            // The name keeps its width; the folder gives way from its start.
            MeridianText {
                visible: text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Math.max(0, label.width - nameText.implicitWidth))
                text: row.directory
                color: Theme.colors.inkMuted
                elide: Text.ElideLeft
                horizontalAlignment: Text.AlignRight
            }
            MeridianText {
                id: nameText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, label.width)
                text: row.folder ? row.path : row.name
                color: Theme.colors.ink
                elide: Text.ElideRight
            }
        }
    }

    HoverHandler { id: hover }
    TapHandler {
        onTapped: {
            row.forceActiveFocus()
            row.clicked()
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: point => row.contextMenuRequested(point.position.x, point.position.y)
    }
}
