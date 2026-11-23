import QtQuick
import Meridian

// Where to place the helper by hand (the Dart _manualLocation): the exact location with this
// build's helper ID, selectable, and how to place it.
Column {
    id: location

    readonly property var helper: Store.remote ? (Store.remote.helper ?? ({})) : ({})
    readonly property bool known: !!helper.buildId

    spacing: Theme.space.s2

    MeridianText {
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        text: L10n.t("remoteHelperLocationLabel")
    }
    MeridianSelectableText {
        objectName: "remote-helper-location"
        width: parent.width
        role: MeridianText.CodeSm
        wrapMode: Text.WrapAnywhere
        text: location.known ? location.helper.location
            : "~/.local/lib/gitlama/remote/" + L10n.t("remoteHelperBuildPlaceholder") + "/gitlama-remote-helper"
    }
    MeridianText {
        width: parent.width
        role: MeridianText.Caption
        wrapMode: Text.Wrap
        color: Theme.colors.inkMuted
        text: location.known ? L10n.t("remoteHelperExactLocationHelp") : L10n.t("remoteHelperLocationHelp")
    }
}
