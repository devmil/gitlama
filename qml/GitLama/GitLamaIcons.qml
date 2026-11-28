pragma Singleton
import QtQuick

// GitLama's semantic icon names (`fetch`, `push`, `close`) for Lucide icons
// in Meridian; installed as `Theme.iconAliases`, so `MeridianIcon` with
// name "fetch" draws `arrow-down-to-line`. Every other name is a Meridian
// icon name.
QtObject {
    readonly property var aliases: ({
        "back": "chevron-left",
        "blame": "file-user",
        "branch": "git-branch",
        "changes": "git-compare-arrows",
        "close": "x",
        "co-author": "user-plus",
        "command": "square-terminal",
        "commit-push": "upload",
        "fetch": "arrow-down-to-line",
        "fixup": "git-commit-horizontal",
        "folder-history": "folder-clock",
        "forward": "chevron-right",
        "inspect": "file-search",
        "list-view": "list",
        "manage": "folder-git-2",
        "more": "ellipsis",
        "pull": "download",
        "push": "upload",
        "recovery": "life-buoy",
        "redo": "redo-2",
        "refresh": "refresh-cw",
        "shortcuts": "keyboard",
        "side-by-side": "columns-2",
        "spellcheck": "spell-check",
        "squash": "git-merge",
        "stage-all": "file-input",
        "stash": "archive",
        "template": "layout-template",
        "trash": "trash-2",
        "tree-view": "list-tree",
        "undo": "undo-2",
        "unified-diff": "rows-2",
        "unstage-all": "file-output",
        "whitespace": "pilcrow",
        "wrap": "wrap-text"
    })
}
