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
    signal doubleClicked()
    signal contextMenuRequested(real x, real y)
    /// The folder's chevron was tapped (folding never selects).
    signal folderToggled()
    /// A folder row shows an open or closed folder after its chevron.
    property bool folderIcon: false
    /// The keyboard modifiers of the last click.
    property int modifiers: 0
    /// Before the glyph (a checkbox) and at the end (counts, actions).
    property Component leading: null
    property Component trailing: null

    readonly property int slash: path.lastIndexOf("/")
    readonly property string directory: !showDirectory || slash < 0 ? "" : path.substring(0, slash + 1)
    readonly property string name: path.substring(slash + 1)

    implicitHeight: Theme.size.row
    activeFocusOnTab: true

    Accessible.role: Accessible.ListItem
    Accessible.name: status.length > 0 ? status + ", " + path : path
    Accessible.selected: selected

    Keys.onReturnPressed: row.clicked()
    // The menu key and Shift+F10 open the context menu at the row.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            row.contextMenuRequested(Theme.space.s6, row.height)
            event.accepted = true
        }
    }
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
        width: row.width - x - Theme.space.s4 - Theme.space.s2 - (trailingLoader.active ? trailingLoader.width + Theme.space.s2 : 0)
        height: parent.height
        spacing: Theme.space.s4

        Loader {
            id: leadingLoader
            active: row.leading !== null
            visible: active
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: row.leading
        }

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
            // The chevron takes the press, so folding never selects.
            MouseArea {
                enabled: row.folder
                anchors.fill: parent
                anchors.margins: -Theme.space.s1
                cursorShape: Qt.PointingHandCursor
                onClicked: row.folderToggled()
                Accessible.role: Accessible.Button
                Accessible.name: row.expanded ? L10n.t("changesCollapseFolder") : L10n.t("changesExpandFolder")
            }
            StatusGlyph {
                visible: !row.folder && row.status.length > 0
                anchors.centerIn: parent
                status: row.status
                partial: row.partial
            }
        }
        MeridianIcon {
            visible: row.folder && row.folderIcon
            anchors.verticalCenter: parent.verticalCenter
            name: row.expanded ? "folder-open" : "folder-closed"
        }
        Row {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - GitLamaLayout.glyphSize - parent.spacing
                - (leadingLoader.active ? leadingLoader.width + parent.spacing : 0)
                - (row.folder && row.folderIcon ? Theme.size.icon + parent.spacing : 0)
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

    Loader {
        id: trailingLoader
        active: row.trailing !== null
        visible: active
        x: row.width - width - Theme.space.s4
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: row.trailing
        z: 1
    }

    HoverHandler { id: hover }
    TapHandler {
        id: tap
        onTapped: {
            row.modifiers = tap.point.modifiers
            row.forceActiveFocus()
            row.clicked()
        }
        onDoubleTapped: row.doubleClicked()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: point => row.contextMenuRequested(point.position.x, point.position.y)
    }
}
