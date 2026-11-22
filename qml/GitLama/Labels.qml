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
    function fileBrowserName() {
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
