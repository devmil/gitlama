pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Merges the shown conflicted file in an external tool: unavailable without a configured merge tool, a
// button for one, a native menu of several. `iconOnly` shows the icon
// button of the compact toolbar.
Item {
    id: mergeAction

    property bool iconOnly: false
    property bool busy: false
    readonly property var tools: Store.conflicts && Store.conflicts.state ? (Store.conflicts.state.mergeTools ?? []) : []

    implicitWidth: iconOnly ? iconButton.implicitWidth : button.implicitWidth
    implicitHeight: iconOnly ? iconButton.implicitHeight : button.implicitHeight

    function run() {
        if (tools.length === 1) {
            Store.conflicts.mergeExternally(tools[0])
            return
        }
        toolMenu.items = tools.map(name => ({ title: name, value: name }))
        toolMenu.show(mergeAction, 0, mergeAction.height)
    }

    MeridianButton {
        id: button
        objectName: "conflict-external-merge"
        visible: !mergeAction.iconOnly
        text: L10n.t("conflictExternalTool")
        iconName: "external-link"
        controlSize: MeridianButton.Small
        enabled: mergeAction.tools.length > 0 && !mergeAction.busy
        disabledReason: mergeAction.tools.length === 0 ? L10n.t("conflictExternalUnavailable") : ""
        onClicked: mergeAction.run()
    }
    MeridianIconButton {
        id: iconButton
        visible: mergeAction.iconOnly
        text: L10n.t("conflictExternalTool")
        iconName: "external-link"
        controlSize: MeridianButton.Small
        enabled: mergeAction.tools.length > 0 && !mergeAction.busy
        disabledReason: mergeAction.tools.length === 0 ? L10n.t("conflictExternalUnavailable") : ""
        onClicked: mergeAction.run()
    }
    CommandMenu {
        id: toolMenu
        onSelected: value => Store.conflicts.mergeExternally(value)
    }
}
