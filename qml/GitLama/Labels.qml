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

    /// The platform's file browser: Finder, Explorer or Files.
    /// `bytes` for people: "512 bytes", "47 KB", "1.5 MB" (binary units,
    /// one decimal below 10, the locale's number format; the Dart
    /// formatByteSize).
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
        return L10n.t("remoteRecentSubtitle", [recent.hostName ?? "", recent.path])
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

    /// A running operation's phase and completion (the Dart
    /// operationProgressLabel); "" while Git reported neither. Git names
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

    /// The first eight characters of an object ID (the Dart shortObjectId).
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
}
