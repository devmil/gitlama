pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// Every command with a shortcut in effect:
// searchable by name or keys, grouped, with the keys as caps; shortcuts that
// several commands share are listed first.
MeridianDialog {
    id: dialog

    readonly property string query: search.text.trim().toLowerCase()
    readonly property var groups: ["commands", "repository", "settings"]
    readonly property var commands: Commands.registry.filter(command => Commands.shortcutLabel(command.id).length > 0)
    readonly property var shown: commands.filter(command => query.length === 0
        || Commands.label(command.id).toLowerCase().indexOf(query) >= 0
        || Commands.shortcutLabel(command.id).toLowerCase().indexOf(query) >= 0)
    readonly property var conflicts: {
        const byKeys = {}
        for (const command of commands) {
            const keys = Commands.shortcutLabel(command.id)
            byKeys[keys] = (byKeys[keys] ?? []).concat([command])
        }
        return Object.keys(byKeys).filter(keys => byKeys[keys].length > 1)
            .map(keys => ({ keys: keys, commands: byKeys[keys].map(command => Commands.label(command.id)).join(", ") }))
    }
    function groupLabel(group) {
        return L10n.t("commandGroup" + group.charAt(0).toUpperCase() + group.slice(1))
    }
    /// Rows: a header per group, then its commands.
    readonly property var rows: {
        const result = []
        for (const group of groups) {
            const members = shown.filter(command => command.group === group)
            if (members.length === 0)
                continue
            result.push({ header: true, group: group })
            for (const command of members)
                result.push({ header: false, group: group, id: command.id })
        }
        return result
    }

    function show() {
        search.text = ""
        open()
        search.forceActiveFocus()
    }

    widthClass: MeridianDialog.Workflow
    title: L10n.t("shortcutReferenceTitle")
    closeLabel: L10n.t("close")

    Column {
        width: parent ? parent.width : 0
        height: GitLamaLayout.shortcutReferenceBodyHeight

        MeridianTextField {
            id: search
            objectName: "shortcut-search"
            width: parent.width
            variant: MeridianTextField.Search
            placeholderText: L10n.t("shortcutSearch")
            clearLabel: L10n.t("searchClear")
            Accessible.name: L10n.t("shortcutSearch")
        }
        Item { width: 1; height: Theme.space.s5; visible: conflictBox.visible }
        Rectangle {
            id: conflictBox
            visible: dialog.conflicts.length > 0
            width: parent.width
            height: visible ? conflictColumn.implicitHeight + 2 * Theme.space.s5 : 0
            radius: Theme.radius.lg
            color: Theme.colors.paneAlt
            Accessible.role: Accessible.Note
            Accessible.name: L10n.t("shortcutConflictTitle")
            Column {
                id: conflictColumn
                x: Theme.space.s5
                y: Theme.space.s5
                width: parent.width - 2 * Theme.space.s5
                spacing: Theme.space.s1
                MeridianCount { label: L10n.t("shortcutConflictTitle") }
                Repeater {
                    model: dialog.conflicts
                    delegate: MeridianText {
                        required property var modelData
                        width: conflictColumn.width
                        role: MeridianText.Caption
                        color: Theme.colors.inkMuted
                        wrapMode: Text.Wrap
                        text: L10n.tn("shortcutConflictDetail", { shortcut: modelData.keys, commands: modelData.commands })
                    }
                }
                MeridianText {
                    width: conflictColumn.width
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    wrapMode: Text.Wrap
                    text: L10n.t("shortcutConflictWinner")
                }
            }
        }
        Item { width: 1; height: Theme.space.s3 }
        ListView {
            id: list
            width: parent.width
            height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: dialog.rows
            MeridianWheelScroll { flickable: list }
            C.ScrollBar.vertical: MeridianScrollBar {}
            delegate: Loader {
                id: rowLoader
                required property var modelData
                width: list.width
                sourceComponent: modelData.header ? groupHeader : commandRow
                Component {
                    id: groupHeader
                    Item {
                        width: rowLoader.width
                        height: headerText.implicitHeight + Theme.space.s5 + Theme.space.s2
                        MeridianText {
                            id: headerText
                            x: Theme.space.s4
                            y: Theme.space.s5
                            role: MeridianText.Overline
                            color: Theme.colors.inkMuted
                            text: dialog.groupLabel(rowLoader.modelData.group).toUpperCase()
                        }
                    }
                }
                Component {
                    id: commandRow
                    MeridianListRow {
                        width: rowLoader.width
                        iconName: Commands.icon(rowLoader.modelData.id)
                        text: Commands.label(rowLoader.modelData.id)
                        subtitle: dialog.groupLabel(rowLoader.modelData.group)
                        trailing: Component {
                            MeridianKbd { keys: Commands.platformShortcutKeys(Commands.shortcuts[rowLoader.modelData.id].canonical) }
                        }
                    }
                }
            }
        }
    }
}
