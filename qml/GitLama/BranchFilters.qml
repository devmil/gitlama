pragma Singleton
import QtQuick

// The history graph's branch filter as sorted, distinct full reference
// names (the Dart HistoryBranchFilter), and the filter actions a
// reference's context menu offers.
QtObject {
    /// The most references a filter holds (ContractLimits).
    readonly property int maximumReferences: 1024

    function normalized(references) {
        return Array.from(new Set(references)).sort()
    }

    function isRemoteHead(reference) {
        return reference.startsWith("refs/remotes/") && reference.endsWith("/HEAD")
    }

    /// Whether the graph can be filtered to `reference`.
    function isFilterable(reference) {
        return reference.startsWith("refs/heads/")
            || (reference.startsWith("refs/remotes/") && !isRemoteHead(reference))
    }

    function contains(filter, reference) {
        return (filter ?? []).indexOf(reference) >= 0
    }

    function isFocusedOn(filter, reference, upstream) {
        return contains(filter, reference)
            && filter.every(value => value === reference || value === upstream)
    }

    function focus(reference, upstream) {
        return normalized(upstream ? [reference, upstream] : [reference])
    }

    /// `filter` with `reference` added (bringing `upstream`) or removed.
    function toggled(filter, reference, upstream) {
        filter = filter ?? []
        if (contains(filter, reference))
            return filter.filter(value => value !== reference)
        if (filter.length >= maximumReferences)
            return filter
        const next = filter.concat([reference])
        if (upstream && !contains(filter, upstream) && filter.length + 1 < maximumReferences)
            next.push(upstream)
        return normalized(next)
    }

    /// The filter commands of one branch's menu: {title, filter}.
    function menuActions(filter, reference, upstream) {
        filter = filter ?? []
        const actions = []
        if (!isFocusedOn(filter, reference, upstream))
            actions.push({ title: L10n.t("historyBranchFilterFocus"), filter: focus(reference, upstream) })
        if (contains(filter, reference))
            actions.push({ title: L10n.t("historyBranchFilterRemove"), filter: toggled(filter, reference) })
        else if (filter.length < maximumReferences)
            actions.push({ title: L10n.t("historyBranchFilterAdd"), filter: toggled(filter, reference, upstream) })
        if (filter.length > 0)
            actions.push({ title: L10n.t("historyBranchFilterShowAll"), filter: [] })
        return actions
    }
}
