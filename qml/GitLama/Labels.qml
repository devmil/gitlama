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
}
