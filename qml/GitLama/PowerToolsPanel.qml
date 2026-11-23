pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The power tools floating at the trailing edge (outside History, which
// docks them).
MeridianPanel {
    id: panel

    property real availableHeight: GitLamaLayout.powerToolsBodyHeight + headerHeight
    property real maximumWidth: GitLamaLayout.powerToolsPanelWidth

    title: L10n.t("powerToolsTitle")
    closeLabel: L10n.t("close")
    width: Math.min(GitLamaLayout.powerToolsPanelWidth, maximumWidth)
    leftPadding: 0
    rightPadding: 0
    bottomPadding: 0

    PowerTools {
        width: panel.bodyWidth
        height: Math.min(GitLamaLayout.powerToolsBodyHeight, panel.availableHeight - panel.headerHeight)
        onCloseRequested: panel.closeRequested()
    }
}
