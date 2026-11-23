pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// One-line diff chrome (the Dart DiffToolbar): the path (folder muted, then
// the name) when the pane is wide enough, the actions, and pinned actions
// that stay at the end. When the pane narrows the path goes first, then the
// action strip scrolls.
Rectangle {
    id: toolbar

    property string path
    /// The actions that may scroll.
    default property alias actions: strip.data
    /// Actions that stay visible at the end.
    property alias pinned: pinnedRow.data

    readonly property bool showPath: width >= GitLamaLayout.diffToolbarPathMinWidth
    readonly property int slash: path.lastIndexOf("/")

    implicitHeight: Theme.size.islandHeader
    color: Theme.colors.pane

    MeridianText {
        id: pathLabel
        visible: toolbar.showPath
        x: Theme.space.s5
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(GitLamaLayout.diffToolbarPathMaxWidth,
                        Math.max(GitLamaLayout.diffToolbarPathMinLabelWidth, toolbar.width * GitLamaLayout.diffToolbarPathWidthFraction))
        role: MeridianText.Label
        textFormat: Text.StyledText
        elide: Text.ElideRight
        text: "<font color=\"" + Theme.colors.inkMuted + "\">" + Theme.escapeHtml(toolbar.slash < 0 ? "" : toolbar.path.substring(0, toolbar.slash + 1))
            + "</font>" + Theme.escapeHtml(toolbar.path.substring(toolbar.slash + 1))
    }
    Flickable {
        id: scroller
        x: toolbar.showPath ? pathLabel.x + pathLabel.width + Theme.space.s4 : Theme.space.s3
        width: Math.max(0, pinnedRow.x - x - Theme.space.s2)
        height: parent.height
        contentWidth: strip.implicitWidth
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Row {
            id: strip
            height: scroller.height
            spacing: Theme.space.s1
        }
    }
    Row {
        id: pinnedRow
        x: parent.width - width - Theme.space.s3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s1
    }
    MeridianHairline { anchors.bottom: parent.bottom; width: parent.width }
}
