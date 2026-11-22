pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// What is unusual about the active repository (the Dart
// RepositoryConditions): watch and read failures, a detached HEAD, the
// conflict count, a moment of "all resolved", and each paused operation,
// whose banner continues, skips or aborts it.
Column {
    id: conditions

    readonly property var active: Store.workspace ? Store.workspace.active : null
    readonly property int conflictCount: active ? (active.conflicts ?? 0) : 0
    readonly property var operations: active ? (active.operations ?? []) : []
    /// The first paused operation that is not a bisect.
    readonly property var paused: operations.find(operation => operation.kind !== "bisect") ?? null
    property bool recentlyResolved: false
    property int _previousConflicts: 0
    readonly property var availability: Store.actions ? Store.actions.availability : ({})
    readonly property string continueReason: Commands.reason("rebaseContinue", availability)
    readonly property string abortReason: Commands.reason("rebaseAbort", availability)

    signal command(string id)
    signal skip()

    readonly property var items: {
        const list = []
        if (!active)
            return list
        if (active.watchOverflow)
            list.push({ tone: MeridianBanner.Warning, message: L10n.t("workspaceWatchOverflow") })
        if (active.watchFailure)
            list.push({ tone: MeridianBanner.Error, message: L10n.t("workspaceWatchFailure") })
        if (active.statusFailure)
            list.push({ tone: MeridianBanner.Error, message: L10n.t("workspaceStatusFailure") })
        if (active.refsFailure)
            list.push({ tone: MeridianBanner.Error, message: L10n.t("workspaceRefsFailure") })
        if (active.detached)
            list.push({ tone: MeridianBanner.Info, message: L10n.t("workspaceDetachedHead") })
        if (conflictCount > 0)
            list.push({ tone: MeridianBanner.Attention, message: L10n.tn("workspaceConflictCount", { count: conflictCount }) })
        if (conflictCount === 0 && recentlyResolved)
            list.push({ tone: MeridianBanner.Success, message: L10n.t("conflictAllResolved"), icon: "circle-check" })
        for (const operation of operations)
            list.push({ tone: operation.kind === "bisect" ? MeridianBanner.Info : MeridianBanner.Attention,
                        message: L10n.t("workspaceOperation" + operation.kind.charAt(0).toUpperCase() + operation.kind.slice(1)),
                        operation: operation.kind !== "bisect" && operation === conditions.paused })
        return list
    }

    onConflictCountChanged: {
        if (conflictCount > 0) {
            resolvedTimer.stop()
            recentlyResolved = false
        } else if (_previousConflicts > 0) {
            recentlyResolved = true
            resolvedTimer.restart()
        }
        _previousConflicts = conflictCount
    }
    Timer { id: resolvedTimer; interval: 1200; onTriggered: conditions.recentlyResolved = false }

    padding: items.length > 0 ? Theme.space.s3 : 0
    spacing: Theme.space.s3
    visible: items.length > 0

    Repeater {
        model: conditions.items
        delegate: MeridianBanner {
            id: banner
            required property var modelData
            width: conditions.width - 2 * conditions.padding
            tone: modelData.tone
            iconName: modelData.icon ?? ["info", "circle-check", "triangle-alert", "circle-alert", "circle-x"][modelData.tone]
            message: modelData.message
            MeridianButton {
                visible: banner.modelData.operation === true
                text: L10n.t("conflictContinue")
                variant: MeridianButton.Primary
                controlSize: MeridianButton.Small
                enabled: conditions.conflictCount === 0 && conditions.continueReason.length === 0
                disabledReason: conditions.conflictCount > 0 ? L10n.tn("workspaceConflictCount", { count: conditions.conflictCount })
                    : conditions.continueReason.length > 0 ? Commands.reasonText(conditions.continueReason) : ""
                onClicked: conditions.command("rebaseContinue")
            }
            MeridianButton {
                visible: banner.modelData.operation === true && conditions.paused !== null && conditions.paused.kind !== "merge"
                text: L10n.t("conflictSkip")
                variant: MeridianButton.Secondary
                controlSize: MeridianButton.Small
                enabled: conditions.abortReason.length === 0
                disabledReason: conditions.abortReason.length > 0 ? Commands.reasonText(conditions.abortReason) : ""
                onClicked: conditions.skip()
            }
            MeridianButton {
                visible: banner.modelData.operation === true
                text: L10n.t("conflictAbort")
                variant: MeridianButton.DangerQuiet
                controlSize: MeridianButton.Small
                enabled: conditions.abortReason.length === 0
                disabledReason: conditions.abortReason.length > 0 ? Commands.reasonText(conditions.abortReason) : ""
                onClicked: conditions.command("rebaseAbort")
            }
        }
    }
}
