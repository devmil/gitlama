pragma Singleton
import QtQuick

// The command registry (owned by the core) as the UI reads it: definitions,
// localized names, shortcuts in effect and the availability policy every
// toolbar, menu, palette and shortcut applies (the Flutter
// CommandMenuState).
QtObject {
    id: root

    readonly property var registry: Store.app ? (Store.app.commands ?? []) : []
    readonly property var byId: {
        const map = {}
        for (const command of registry)
            map[command.id] = command
        return map
    }
    readonly property var shortcuts: Store.app ? (Store.app.shortcuts ?? ({})) : ({})

    function definition(id) {
        return byId[id] ?? null
    }

    function icon(id) {
        const command = byId[id]
        return command ? command.icon : ""
    }

    /// The command's name; Open in file browser names the platform's.
    function label(id) {
        const command = byId[id]
        if (!command)
            return id
        if (id === "openInFileManager")
            return L10n.t("openInFileBrowser", [Labels.fileBrowserName()])
        return L10n.t(command.label)
    }

    /// A dialog's title from a command name: without its trailing ellipsis.
    function dialogTitle(text) {
        const value = text ?? ""
        return value.endsWith("…") ? value.slice(0, -1) : value
    }

    /// The Qt key sequence bound to `id`, or "".
    function sequence(id) {
        const shortcut = shortcuts[id]
        return shortcut && shortcut.sequence ? shortcut.sequence : ""
    }

    /// The shortcut `id` shows, as the platform writes it (⌘⇧P, Ctrl+Shift+P).
    function shortcutLabel(id) {
        const shortcut = shortcuts[id]
        if (!shortcut || !shortcut.canonical)
            return ""
        return platformShortcutLabel(shortcut.canonical)
    }

    function platformShortcutKeys(canonical) {
        const parts = canonical.split("+")
        let key = parts.pop()
        if (canonical.endsWith("++"))
            key = "+"
        const mac = Store.isMac
        const control = parts.indexOf("Ctrl") >= 0
        const meta = parts.indexOf("Cmd") >= 0
        const alt = parts.indexOf("Alt") >= 0
        const shift = parts.indexOf("Shift") >= 0 || key === "?"
        const keys = []
        if (control) keys.push(mac ? "⌃" : "Ctrl")
        if (meta) keys.push(mac ? "⌘" : "Meta")
        if (shift && key !== "?") keys.push(mac ? "⇧" : "Shift")
        if (alt) keys.push(mac ? "⌥" : "Alt")
        keys.push(key === "Enter" ? (mac ? "↵" : "Enter") : key)
        return keys
    }

    function platformShortcutLabel(canonical) {
        return platformShortcutKeys(canonical).join(Store.isMac ? "" : "+")
    }

    // Availability ------------------------------------------------------------

    /// Commands a running operation never blocks.
    readonly property var _busyExempt: ["activityCancel", "activityCopy", "showChanges", "showHistory", "showActivity", "showOperations"]
    readonly property var _stagingCommands: ["stageSelection", "unstageSelection", "stageToggle"]

    /// Why `id` cannot run now, or "" when it can: a disabled reason name
    /// (repositoryRequired, repositoryBusy, contextRequired, ...).
    /// `state` carries what panes contribute: {busy, canQueueStaging,
    /// selectedCommits, disabledSelections, mergeCommits, hasHistoryPath,
    /// hasDiff, inspectorShown, canBrowseAllFiles, inspectorCanBack,
    /// inspectorCanForward, hasActivity, canRetryActivity,
    /// canCancelActivity, remote}; `context` {reference, target, current}.
    function reason(id, state, context) {
        const command = byId[id]
        if (!command)
            return "featureUnavailable"
        state = state ?? ({})
        context = context ?? ({})
        const active = Store.workspace ? Store.workspace.active : null
        const hasRepository = active !== null && active !== undefined && active.hasSession === true
        const busy = state.busy === true
            && !(state.canQueueStaging === true && _stagingCommands.indexOf(id) >= 0)
            && _busyExempt.indexOf(id) < 0
        if (command.requiresRepository && !hasRepository)
            return "repositoryRequired"
        if (command.requiresRepository && busy)
            return "repositoryBusy"
        if (!command.available)
            return "featureUnavailable"
        const remoteReason = remoteCommandReason(command, state.remote)
        if (remoteReason.length > 0)
            return remoteReason
        if (!hasRepository)
            return ""
        const reference = context.reference ?? null
        const target = context.target ?? null
        const sameBranch = context.current === true || (reference !== null && reference === active.headRef)
        const sameCheckout = sameBranch || (reference !== null && reference === active.upstream)
        const sameTarget = target !== null && target === active.headObjectId
        const selectedCommits = state.selectedCommits ?? []
        const selected = target === null ? selectedCommits.filter(commit => commit !== "wip") : [target]
        const operations = active.operations ?? []
        const activeOperation = operations.length > 0
        const sequencerOperation = operations.some(operation => operation.kind !== "bisect")
        const clean = active.workingTree === "clean"
        const attached = active.attached === true
        const conflicts = active.conflicts > 0
        const noBranches = active.branchCount === 0
        const noRemoteBranches = active.remoteBranchCount === 0
        const merges = state.mergeCommits ?? []
        const isMerge = commit => merges.indexOf(commit) >= 0
        const disabledSelections = state.disabledSelections ?? ["stageToggle", "stageSelection", "unstageSelection", "discardChanges"]
        let unavailable = false
        switch (id) {
        case "checkoutBranch":
            unavailable = sameCheckout || activeOperation || (noBranches && noRemoteBranches); break
        case "autoStashCheckout":
            unavailable = sameCheckout || clean || activeOperation || noBranches; break
        case "deleteBranch":
            unavailable = sameBranch || activeOperation || noBranches; break
        case "deleteRemoteBranch":
            unavailable = active.remoteBranchesOnlyHead === true; break
        case "integrateBranch": case "mergeBranch": case "rebaseBranch":
            unavailable = sameBranch || sameTarget || !clean || !attached || activeOperation || (noBranches && noRemoteBranches); break
        case "interactiveRebase": case "restackBranches":
            unavailable = !clean || !attached || activeOperation; break
        case "revertSelected":
            unavailable = selected.length === 0 || conflicts || active.workingTree === "conflicted" || !attached || activeOperation || selected.some(isMerge); break
        case "cherryPickSelected":
            unavailable = selected.length === 0 || !clean || !attached || activeOperation || selected.some(isMerge); break
        case "historyCompare":
            unavailable = selected.length !== 2; break
        case "checkoutCommit":
            unavailable = selected.length !== 1 || activeOperation || conflicts; break
        case "saveCommitArchive":
            unavailable = selected.length !== 1; break
        case "historyBlame": case "historyPathHistory": case "inspectorLensDiff": case "inspectorLensContents":
        case "inspectorLensBlame": case "inspectorLensHistory":
            unavailable = state.hasHistoryPath !== true; break
        case "inspectorBack":
            unavailable = state.inspectorCanBack !== true; break
        case "inspectorForward":
            unavailable = state.inspectorCanForward !== true; break
        case "inspectorOpenInWindow": case "inspectorToggleMaximize": case "inspectorToggleFiles":
            unavailable = state.inspectorShown !== true; break
        case "inspectorAllFiles":
            unavailable = state.canBrowseAllFiles !== true; break
        case "stageToggle": case "stageSelection": case "unstageSelection": case "discardChanges":
            unavailable = disabledSelections.indexOf(id) >= 0; break
        case "commitCreate":
            unavailable = !active.hasStatus || activeOperation || active.staged === 0; break
        case "commitAmend":
            unavailable = !active.headObjectId || activeOperation; break
        case "conflictNext": case "conflictPrevious": case "conflictTakeCurrent": case "conflictTakeIncoming":
        case "conflictTakeBoth": case "conflictOpenExternal":
            unavailable = !conflicts; break
        case "rebaseContinue":
            unavailable = !sequencerOperation || conflicts; break
        case "rebaseAbort":
            unavailable = !sequencerOperation; break
        case "rebaseSquash": case "rebaseFixup": case "rebaseReword": case "rebaseDrop":
            unavailable = true; break
        case "renameBranch":
            unavailable = noBranches; break
        case "editRemote": case "renameRemote": case "removeRemote": case "remoteFetch": case "remotePush":
        case "fetch": case "pull": case "push":
            unavailable = active.remoteCount === 0; break
        case "pushTag":
            unavailable = active.remoteCount === 0 || active.tagCount === 0; break
        case "deleteTag":
            unavailable = active.tagCount === 0; break
        case "createStash":
            unavailable = !active.hasStatus || clean || activeOperation; break
        case "applyStash": case "popStash": case "renameStash": case "dropStash":
            unavailable = active.stashCount === 0 || activeOperation; break
        case "diffToggleLayout": case "diffRenderConfigured": case "diffToggleWrap": case "diffNextHunk":
        case "diffPreviousHunk":
            unavailable = state.hasDiff !== true; break
        case "activityCopy":
            unavailable = state.hasActivity !== true; break
        case "activityRetry":
            unavailable = state.canRetryActivity !== true; break
        case "activityCancel":
            unavailable = state.canCancelActivity !== true; break
        }
        return unavailable ? "contextRequired" : ""
    }

    /// Why `command` cannot run on the active remote tab ({connected,
    /// capabilities: [...], writeBlock}), or "" (always "" for a local tab).
    function remoteCommandReason(command, access) {
        if (access === undefined || access === null)
            return ""
        switch (command.remote) {
        case "view": return ""
        case "read": return access.connected ? "" : "remoteDisconnected"
        case "unsupported": return "remoteUnsupported"
        default: return remoteCapabilityReason(access, command.remote)
        }
    }

    function remoteCapabilityReason(access, capability) {
        if (access === undefined || access === null)
            return ""
        if (!access.connected)
            return "remoteDisconnected"
        if ((access.capabilities ?? []).indexOf(capability) >= 0)
            return ""
        switch (access.writeBlock) {
        case "notAllowed": return "remoteWritesOff"
        case "reconnect": return "remoteWritesReconnect"
        case "ledgerUnavailable": return "remoteWritesLedger"
        default: return "remoteWritesUnavailable"
        }
    }

    /// The localized text of a disabled reason.
    function reasonText(reason) {
        switch (reason) {
        case "repositoryRequired": return L10n.t("commandRepositoryRequired")
        case "repositoryBusy": return L10n.t("commandRepositoryBusy")
        case "contextRequired": return L10n.t("commandContextUnavailable")
        case "featureUnavailable": return L10n.t("commandFeatureUnavailable")
        case "remoteUnsupported": return L10n.t("remoteCommandUnsupported")
        case "remoteDisconnected": return L10n.t("remoteCommandDisconnected")
        case "remoteWritesUnavailable": return L10n.t("remoteCommandWritesUnavailable")
        case "remoteWritesOff": return L10n.t("remoteCommandWritesOff")
        case "remoteWritesReconnect": return L10n.t("remoteCommandWritesReconnect")
        case "remoteWritesLedger": return L10n.t("remoteCommandWritesLedger")
        default: return ""
        }
    }
}
