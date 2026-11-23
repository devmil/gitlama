pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The viewing controls of every diff (the Dart DiffViewingActions): wrap,
// whitespace, context lines, minimap, text encoding, layout and the +/−
// markers. The stored diff preferences are their source; `setOptions`
// applies the load options to the host's diff.
Row {
    id: actions

    /// Called with (contextLines, whitespace, layout) to load other options.
    property var setOptions: null
    /// The minimap can be shown (not while every file is folded).
    property bool minimapAvailable: true
    /// The text encoding of this diff: "utf8" or "latin1".
    property string encoding: "utf8"
    signal encodingChosen(string encoding)

    readonly property var preferences: Store.appearance
    readonly property int contextLines: preferences.diffContextLines ?? 3
    readonly property string whitespace: preferences.diffWhitespace ?? "preserve"
    readonly property string layout: preferences.diffLayout ?? "unified"
    readonly property var whitespaces: ["preserve", "ignoreAll", "ignoreAmount", "ignoreEndOfLine"]

    function apply(context, space, shape) {
        if (setOptions)
            setOptions(context, space, shape)
    }

    spacing: Theme.space.s1

    MeridianIconButton {
        anchors.verticalCenter: parent.verticalCenter
        text: L10n.t("diffWrap")
        iconName: "wrap"
        active: actions.preferences.diffWrap === true
        controlSize: MeridianButton.Small
        onClicked: Store.app.updateAppearance({ diffWrap: !(actions.preferences.diffWrap === true) })
    }
    MeridianIconButton {
        anchors.verticalCenter: parent.verticalCenter
        text: L10n.t("diffWhitespace")
        iconName: "whitespace"
        controlSize: MeridianButton.Small
        onClicked: {
            const at = actions.whitespaces.indexOf(actions.whitespace)
            actions.apply(actions.contextLines, actions.whitespaces[(at + 1) % actions.whitespaces.length], actions.layout)
        }
    }
    MeridianIconButton {
        id: contextButton
        anchors.verticalCenter: parent.verticalCenter
        text: L10n.t("diffContextLines")
        iconName: "chevrons-down-up"
        controlSize: MeridianButton.Small
        onClicked: {
            contextMenu.items = [0, 3, 6, 10].map(value => ({
                title: L10n.tn("diffContextValue", { count: value }), checked: value === actions.contextLines, value: value }))
            contextMenu.show(contextButton, 0, contextButton.height)
        }
    }
    CommandMenu {
        id: contextMenu
        onSelected: value => actions.apply(value, actions.whitespace, actions.layout)
    }
    MeridianIconButton {
        anchors.verticalCenter: parent.verticalCenter
        text: L10n.t("diffMinimap")
        iconName: "map"
        active: actions.preferences.diffMinimap !== false && actions.minimapAvailable
        enabled: actions.minimapAvailable
        controlSize: MeridianButton.Small
        onClicked: Store.app.updateAppearance({ diffMinimap: actions.preferences.diffMinimap === false })
    }
    MeridianIconButton {
        id: encodingButton
        objectName: "diff-encoding"
        anchors.verticalCenter: parent.verticalCenter
        text: L10n.t("diffEncoding")
        iconName: "type"
        controlSize: MeridianButton.Small
        onClicked: {
            encodingMenu.items = [
                { title: L10n.t("diffEncodingUtf8"), checked: actions.encoding === "utf8", value: "utf8" },
                { title: L10n.t("diffEncodingLatin1"), checked: actions.encoding === "latin1", value: "latin1" },
            ]
            encodingMenu.show(encodingButton, 0, encodingButton.height)
        }
    }
    CommandMenu {
        id: encodingMenu
        onSelected: value => actions.encodingChosen(value)
    }
    MeridianSegmented {
        anchors.verticalCenter: parent.verticalCenter
        label: L10n.t("galleryDiffLayout")
        controlSize: MeridianButton.Small
        segments: [{ value: "unified", icon: "unified-diff", tooltip: L10n.t("diffUnified") },
                   { value: "sideBySide", icon: "side-by-side", tooltip: L10n.t("diffSideBySide") }]
        value: actions.layout
        onActivated: value => actions.apply(actions.contextLines, actions.whitespace, value)
    }
    MeridianIconButton {
        anchors.verticalCenter: parent.verticalCenter
        text: L10n.t("diffIndicators")
        iconName: "square-plus"
        active: actions.preferences.diffIndicators !== false
        controlSize: MeridianButton.Small
        onClicked: Store.app.updateAppearance({ diffIndicators: actions.preferences.diffIndicators === false })
    }
}
