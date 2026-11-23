pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// A pull request's CI result and, when it has conflicts, a conflict mark,
// each only where the provider reported it (the Dart
// HostingPullRequestStatus). `checks` is a state name or "".
Row {
    id: status

    property string checks
    property bool conflicting: false
    /// On the accent fill of a selected row, where state colours would not read.
    property bool onAccent: false

    function icon(state) {
        return ({ passing: "circle-check", failing: "circle-x", pending: "clock", canceled: "ban", skipped: "skip-forward" })[state] ?? "circle-help"
    }
    function color(state) {
        return state === "passing" ? Theme.colors.success : state === "failing" ? Theme.colors.danger
            : state === "pending" ? Theme.colors.warning : Theme.colors.inkMuted
    }
    function label(state) {
        return L10n.t("hostingCheck" + state.charAt(0).toUpperCase() + state.slice(1))
    }

    spacing: Theme.space.s1
    visible: (checks.length > 0 && checks !== "unknown") || conflicting

    MeridianIcon {
        objectName: "hosting-status-checks"
        visible: status.checks.length > 0 && status.checks !== "unknown"
        anchors.verticalCenter: parent.verticalCenter
        name: status.icon(status.checks)
        iconSize: MeridianIcon.Small
        color: status.onAccent ? Theme.colors.inkOnAccent : status.color(status.checks)
        Accessible.name: status.checks.length > 0 ? status.label(status.checks) : ""
    }
    MeridianIcon {
        objectName: "hosting-status-conflicts"
        visible: status.conflicting
        anchors.verticalCenter: parent.verticalCenter
        name: "triangle-alert"
        iconSize: MeridianIcon.Small
        color: status.onAccent ? Theme.colors.inkOnAccent : Theme.colors.danger
        Accessible.name: L10n.t("hostingMergeConflicting")
    }
}
