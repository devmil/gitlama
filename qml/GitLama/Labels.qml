pragma Singleton
import QtQuick

// Localized wording of core values: failure codes, recent repositories.
QtObject {
    /// The specific reason a repository could not be opened or created, or
    /// "" when the failure has no more to say than that it failed.
    function repositoryFailureDetail(code) {
        switch (code) {
        case "existingRepository": return L10n.t("repositoryAlreadyExists")
        case "destinationNotEmpty": return L10n.t("destinationNotEmpty")
        case "destinationNotDirectory": return L10n.t("destinationNotDirectory")
        case "missingGit": return L10n.t("gitUnavailable")
        case "unsupported": return L10n.t("gitUnsupported")
        case "pathNotFound": return L10n.t("repositoryPathNotFound")
        case "permissionDenied": return L10n.t("repositoryPermissionDenied")
        case "notRepository": return L10n.t("repositoryNotRepository")
        case "capacity": return L10n.t("remoteRepositoryCapacity")
        default: return ""
        }
    }

    /// Why a repository could not be opened or created.
    function repositoryFailureMessage(code) {
        const detail = repositoryFailureDetail(code)
        return detail.length > 0 ? detail : L10n.t("repositoryOpenFailed")
    }

    /// A tool kind's name.
    function integrationKind(kind) {
        return L10n.t("integration" + kind.charAt(0).toUpperCase() + kind.slice(1))
    }

    /// `bytes` for people: "512 bytes", "47 KB", "1.5 MB" (binary units,
    /// one decimal below 10, the locale's number format).
    function byteSize(bytes) {
        if (bytes < 1024)
            return L10n.tn("byteCount", { count: bytes })
        const units = ["sizeKilobytes", "sizeMegabytes", "sizeGigabytes", "sizeTerabytes"]
        let value = bytes / 1024
        let index = 0
        while (true) {
            const digits = value < 10 ? 1 : 0
            const rounded = digits === 0 ? Math.round(value) : Math.round(value * 10) / 10
            // 1,023.7 KB reads as 1 MB, not as 1,024 KB.
            if (rounded < 1024 || index === units.length - 1) {
                const size = rounded.toLocaleString(L10n.locale, { minimumFractionDigits: 0, maximumFractionDigits: digits })
                return L10n.tn(units[index], { size: size })
            }
            value /= 1024
            index++
        }
    }

    function fileBrowserName() {
        if (Store.workflows && Store.workflows.fileBrowser.length > 0)
            return Store.workflows.fileBrowser
        if (Store.isMac)
            return "Finder"
        if (Store.isWindows)
            return "Explorer"
        return "Files"
    }

    /// Whether every word of `query` occurs in `text`, ignoring case.
    function recentMatches(query, text) {
        const haystack = String(text).toLowerCase()
        const words = String(query).toLowerCase().split(/\s+/).filter(word => word.length > 0)
        return words.every(word => haystack.indexOf(word) >= 0)
    }

    /// What the recent repositories filter searches: the text a row shows.
    function recentSearchText(recent) {
        return recent.remote ? remoteRecentName(recent) + " " + remoteRecentSubtitle(recent) : recent.path
    }

    /// The last path segment of a remote recent, for its title.
    function remoteRecentName(recent) {
        const path = String(recent.path)
        const trimmed = path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path
        const separator = trimmed.lastIndexOf("/")
        return separator < 0 || separator === trimmed.length - 1 ? trimmed : trimmed.slice(separator + 1)
    }

    /// A remote recent's secondary line: its host and path.
    function remoteRecentSubtitle(recent) {
        return L10n.tn("remoteRecentSubtitle", { host: remoteHostName(recent.profileId ?? ""), path: recent.path })
    }

    /// A commit date in History's date column: `iso` (2026-11-22), `local`
    /// (the locale's medium date) or `relative` (now, 5 min, 3 h, 2 d, then
    /// the medium date). `seconds` since the epoch; 0 shows nothing.
    /// What went wrong with a clone, in the user's words.
    function cloneFailureMessage(failure) {
        switch (failure) {
        case "invalidSource": return L10n.t("cloneInvalidSource")
        case "embeddedCredential": return L10n.t("cloneEmbeddedCredential")
        case "invalidDestination": return L10n.t("cloneInvalidDestination")
        case "destinationOccupied": return L10n.t("cloneDestinationOccupied")
        case "authentication": return L10n.t("cloneAuthenticationRequired")
        case "credentialBrokerUnavailable": return L10n.t("cloneCredentialBrokerUnavailable")
        case "hostKey": return L10n.t("cloneHostKeyUntrusted")
        case "hostKeyProbeFailed": return L10n.t("hostKeyProbeFailed")
        case "hostKeyChallengeExpired": return L10n.t("hostKeyChallengeExpired")
        case "hostKeyWriteFailed": return L10n.t("hostKeyWriteFailed")
        case "missingGit": return L10n.t("gitUnavailable")
        case "timedOut": return L10n.t("cloneTimedOut")
        case "canceled": return L10n.t("cloneCanceled")
        default: return L10n.t("cloneFailed")
        }
    }

    /// A running operation's phase and completion; "" while Git reported neither. Git names
    /// its phases in English whatever the locale.
    function operationProgress(progress) {
        if (!progress)
            return ""
        const phase = ({ "Counting objects": "operationPhaseCounting", "Compressing objects": "operationPhaseCompressing",
                         "Receiving objects": "operationPhaseReceiving", "Resolving deltas": "operationPhaseResolving",
                         "Updating files": "operationPhaseUpdatingFiles", "Filtering content": "operationPhaseFiltering",
                         "Rebasing": "operationPhaseRebasing" })[progress.phase]
        return phase === undefined ? L10n.tn("operationPercent", { percent: progress.percent })
            : L10n.tn("operationPhaseProgress", { phase: L10n.t(phase), percent: progress.percent })
    }

    /// The first eight characters of an object ID.
    function shortObjectId(value) {
        return value.length <= 8 ? value : value.substring(0, 8)
    }

    function historyDate(seconds, format, now) {
        if (!seconds)
            return ""
        const value = new Date(seconds * 1000)
        if (format === "iso")
            return Qt.formatDate(value, "yyyy-MM-dd")
        const medium = () => value.toLocaleDateString(Qt.locale(L10n.locale), "MMM d, yyyy")
        if (format === "local")
            return medium()
        const difference = (now ?? Date.now()) - value.getTime()
        const minutes = Math.floor(difference / 60000)
        if (difference < 0 || minutes < 1)
            return L10n.t("historyDateNow")
        if (minutes < 60)
            return L10n.tn("historyDateMinutes", { count: minutes })
        const hours = Math.floor(minutes / 60)
        if (hours < 24)
            return L10n.tn("historyDateHours", { count: hours })
        const days = Math.floor(hours / 24)
        if (days < 30)
            return L10n.tn("historyDateDays", { count: days })
        return medium()
    }

    /// What the working tree row says in place of a subject.
    function worktreeSubject(conflict, changed, staged) {
        return conflict ? L10n.tn("historyWorkingTreeConflicts", { count: changed })
                        : L10n.tn("historyWorkingTreeChanges", { count: changed, staged: staged })
    }

    // Remote workspaces ---------------------------------------------------------

    /// A connection phase's name.
    function remotePhase(phase) {
        switch (phase) {
        case "installing": return L10n.t("remotePhaseInstalling")
        case "connecting": return L10n.t("remotePhaseConnecting")
        case "handshaking": return L10n.t("remotePhaseHandshaking")
        case "ready": return L10n.t("remotePhaseReady")
        case "disconnecting": return L10n.t("remotePhaseDisconnecting")
        case "disconnected": return L10n.t("remotePhaseDisconnected")
        case "failed": return L10n.t("remotePhaseFailed")
        case "identityChanged": return L10n.t("remotePhaseIdentityChanged")
        default: return L10n.t("remotePhaseIdle")
        }
    }

    /// The status dot tone of a connection phase (MeridianStatusDot tones).
    function remotePhaseTone(phase) {
        switch (phase) {
        case "ready": return 2
        case "installing": case "connecting": case "handshaking": case "disconnecting": return 1
        case "failed": return 4
        case "identityChanged": case "disconnected": return 3
        default: return 0
        }
    }

    /// Whether a connection phase is busy connecting.
    function remoteBusy(phase) {
        return phase === "installing" || phase === "connecting" || phase === "handshaking"
    }

    /// The localized text of a remote failure {code, key, args}.
    function remoteFailure(failure) {
        if (!failure)
            return ""
        if (failure.args && failure.args.alias === null)
            return L10n.tn(failure.key, { alias: L10n.t("remoteAliasExample") })
        return failure.args ? L10n.tn(failure.key, failure.args) : L10n.t(failure.key)
    }

    /// Whether a (re)installation of the helper resolves a failure code.
    function remoteInstallResolves(code) {
        return ["helperNotInstalled", "installDirectory", "installWrite", "installDigest", "installExecute", "installFailed"].indexOf(code) >= 0
    }

    /// A host profile's name, or a generic one once the profile was deleted.
    function remoteHostName(profileId) {
        const host = remoteHost(profileId)
        return host ? host.label : L10n.t("remoteHostUnknown")
    }

    /// The host profile `profileId`, or null.
    function remoteHost(profileId) {
        const hosts = Store.remote ? (Store.remote.hosts ?? []) : []
        for (let index = 0; index < hosts.length; index += 1) {
            if (hosts[index].id === profileId)
                return hosts[index]
        }
        return null
    }

    /// What a remote write family is called.
    function remoteFamily(family) {
        const name = family.length > 0 ? family[0].toUpperCase() + family.slice(1) : family
        return L10n.t("remoteOperation" + name)
    }

    /// Whether a recorded remote write needs the user's review.
    function remoteOperationNeedsReview(operation) {
        return operation.pending || ["succeeded", "failed", "notApplied"].indexOf(operation.outcome) < 0
    }

    /// A recorded remote write's state.
    function remoteOperationState(operation) {
        if (operation.pending && !operation.outcome)
            return L10n.t("remoteOperationRunning")
        switch (operation.outcome) {
        case "succeeded": return L10n.t("remoteOperationSucceeded")
        case "failed": return L10n.t("remoteOperationFailed")
        case "notApplied": return L10n.t("remoteOperationNotApplied")
        case "desiredStateObserved": return L10n.t("remoteOperationDesiredState")
        case "partial": return L10n.t("remoteOperationPartial")
        default: return L10n.t("remoteOperationUnknown")
        }
    }

    /// What automatic reconnection of a host says: {title, reason, detail}.
    function remoteReconnectStatus(host, seconds) {
        const reconnect = host.reconnect
        const name = host.label
        const reason = reconnect.failure ? remoteFailure(reconnect.failure) : ""
        const detail = reason.length > 0 ? reason + " " + L10n.t("remoteReconnectStale") : L10n.t("remoteReconnectStale")
        switch (reconnect.phase) {
        case "waiting": return { title: L10n.tn("remoteReconnectIn", { host: name, seconds: seconds }), reason: reason, detail: detail }
        case "connecting": return { title: L10n.tn("remoteReconnecting", { host: name }), reason: reason, detail: detail }
        default: return {
            title: reconnect.gaveUp ? L10n.tn("remoteReconnectGaveUp", { host: name }) : L10n.tn("remoteReconnectStopped", { host: name }),
            reason: reason,
            detail: detail
        }
        }
    }

    /// The last path segment of a remote path for display.
    function remotePathName(path) {
        const trimmed = path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path
        const separator = trimmed.lastIndexOf("/")
        return separator < 0 || separator === trimmed.length - 1 ? trimmed : trimmed.slice(separator + 1)
    }

    /// What tells a renamed or moved file's `source` path apart from its
    /// `path`: the old name for a rename in place, otherwise the old folder
    /// after the folders both share ("…/Classes/"), with the old name when
    /// that changed too; "./" is the repository's top folder. "" for no move.
    function renameSource(source, path) {
        if (!source || !path || source === path)
            return ""
        const oldParts = source.split("/")
        const newParts = path.split("/")
        const oldName = oldParts.pop()
        const name = newParts.pop()
        const renamed = oldName !== name
        if (oldParts.join("/") === newParts.join("/"))
            return oldName
        let shared = 0
        while (shared < oldParts.length && shared < newParts.length && oldParts[shared] === newParts[shared])
            ++shared
        const folder = oldParts.slice(shared)
        const lead = shared > 0 ? "…/" : oldParts.length === 0 ? "./" : ""
        return lead + folder.map(part => part + "/").join("") + (renamed ? oldName : "")
    }

    /// Whether `source` → `path` changed the file's folder (a move) rather
    /// than only its name.
    function movedFolder(source, path) {
        if (!source || !path)
            return false
        const folder = value => value.lastIndexOf("/") < 0 ? "" : value.slice(0, value.lastIndexOf("/"))
        return folder(source) !== folder(path)
    }
}
