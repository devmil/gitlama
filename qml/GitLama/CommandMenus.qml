pragma Singleton
import QtQuick

// The command menus: every registered command in a
// stable place, as CommandMenu items.
QtObject {
    id: root

    readonly property var groups: [
        ["repository", ["openRepository", "openRemoteRepository", "cloneRepository", "initializeRepository",
                        "closeRepositoryTab", "refreshRepository", "showRepositoryDetails"]],
        ["changes", ["commitCreate", "commitAmend", "stageToggle", "stageSelection", "unstageSelection",
                     "discardChanges", "patch", "createPatch", "applyPatch", "createStash", "applyStash",
                     "popStash", "renameStash", "dropStash"]],
        ["history", ["historyCompare", "saveCommitArchive", "checkoutCommit", "historyBlame", "historyPathHistory",
                     "inspectorBack", "inspectorForward", "inspectorLensDiff", "inspectorLensContents",
                     "inspectorLensBlame", "inspectorLensHistory", "inspectorOpenInWindow",
                     "inspectorToggleMaximize", "inspectorToggleFiles", "inspectorAllFiles",
                     "cherryPickSelected", "revertSelected", "resetBranch"]],
        ["branches", ["createBranch", "checkoutBranch", "autoStashCheckout", "renameBranch", "deleteBranch",
                      "deleteRemoteBranch", "integrateBranch", "mergeBranch", "rebaseBranch", "interactiveRebase",
                      "restackBranches", "createTag", "deleteTag", "pushTag"]],
        ["remotes", ["fetch", "pull", "push", "addRemote", "renameRemote", "editRemote", "removeRemote",
                     "remoteFetch", "remotePush", "hostingCreatePullRequest"]],
        ["recovery", ["showSnapshots", "inspectIndexLock", "rebaseContinue", "rebaseAbort", "conflictNext",
                      "conflictPrevious", "conflictTakeCurrent", "conflictTakeIncoming", "conflictTakeBoth",
                      "conflictOpenExternal", "rebaseSquash", "rebaseFixup", "rebaseReword", "rebaseDrop"]],
        ["tools", ["openInEditor", "openInTerminal", "openInFileManager", "addWorktree", "trackLfsPattern",
                   "addIntegration", "showIntegrations", "showPowerTools"]],
        ["view", ["showChanges", "showHistory", "nextPane", "find", "diffToggleLayout", "diffRenderConfigured",
                  "diffToggleWrap", "diffNextHunk", "diffPreviousHunk", "showOperations", "showActivity",
                  "activityCopy", "activityRetry", "activityCancel"]],
        ["application", ["showCommandPalette", "showSettings", "showShortcutReference", "showLicenses", "reportIssue"]],
    ]

    readonly property var nested: ({
        "changes": [["patch", ["patch", "createPatch", "applyPatch"]],
                    ["stash", ["createStash", "applyStash", "popStash", "renameStash", "dropStash"]]],
        "branches": [["tags", ["createTag", "deleteTag", "pushTag"]]],
        "recovery": [["conflicts", ["conflictNext", "conflictPrevious", "conflictTakeCurrent", "conflictTakeIncoming",
                                    "conflictTakeBoth", "conflictOpenExternal"]],
                     ["rebase", ["rebaseContinue", "rebaseAbort", "rebaseSquash", "rebaseFixup", "rebaseReword", "rebaseDrop"]]],
        "view": [["diff", ["diffToggleLayout", "diffRenderConfigured", "diffToggleWrap", "diffNextHunk", "diffPreviousHunk"]],
                 ["activity", ["showOperations", "showActivity", "activityCopy", "activityRetry", "activityCancel"]]],
    })

    function groupLabel(group) {
        switch (group) {
        case "repository": return L10n.t("menuRepository")
        case "changes": return L10n.t("menuChanges")
        case "history": return L10n.t("menuHistory")
        case "branches": return L10n.t("menuBranches")
        case "remotes": return L10n.t("menuRemotes")
        case "recovery": return L10n.t("menuRecovery")
        case "tools": return L10n.t("menuTools")
        case "view": return L10n.t("menuView")
        case "application": return L10n.t("menuApplication")
        case "patch": return L10n.t("patchTitle")
        case "stash": return L10n.t("workspaceStashes")
        case "tags": return L10n.t("workspaceTags")
        case "conflicts": return L10n.t("conflictResolverTitle")
        case "rebase": return L10n.t("menuRebase")
        case "diff": return L10n.t("menuDiff")
        case "activity": return L10n.t("menuActivity")
        default: return group
        }
    }

    /// A disabled reason the menu names next to the item: only remote ones.
    function remoteMenuReason(reason) {
        return reason.startsWith("remote") ? Commands.reasonText(reason) : ""
    }

    /// `ids` as menu items with icons and shortcuts; commands that delete
    /// come last, after a separator. `reasonOf(id)` says why one cannot run.
    function commandItems(ids, reasonOf, enabledOf) {
        const item = id => {
            const reason = reasonOf ? reasonOf(id) : ""
            const remote = remoteMenuReason(reason)
            return {
                title: remote.length > 0 ? Commands.label(id) + " — " + remote : Commands.label(id),
                value: id,
                icon: Commands.icon(id),
                shortcut: Commands.shortcutLabel(id),
                danger: Commands.definition(id)?.destructive === true,
                enabled: (enabledOf ? enabledOf(id) : true) && reason.length === 0,
            }
        }
        const destructive = id => Commands.definition(id)?.destructive === true
        const safe = ids.filter(id => !destructive(id))
        const dangerous = ids.filter(destructive)
        const result = safe.map(item)
        if (safe.length > 0 && dangerous.length > 0)
            result.push({ separator: true })
        return result.concat(dangerous.map(item))
    }

    /// The workspace's command menu: every group as a submenu.
    function workspaceMenu(state) {
        const reasonOf = id => Commands.reason(id, state)
        return groups.map(([group, ids]) => {
            const inner = nested[group] ?? []
            const nestedIds = [].concat(...inner.map(pair => pair[1]))
            const children = commandItems(ids.filter(id => nestedIds.indexOf(id) < 0), reasonOf)
            for (const [name, members] of inner)
                children.push({ title: groupLabel(name), children: commandItems(members, reasonOf) })
            return { title: groupLabel(group), children: children }
        })
    }
}
