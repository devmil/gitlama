import QtQuick
import Meridian

// Commits ahead and behind the upstream (GitLamaSyncBadge): ↑n in
// `accent-ink`, ↓n in `warning`; in sync shows a check when `showZero`.
// In sync ↔ counts swap with a rise; counts roll (NM-03, NM-21); a side that
// reaches 0 fades and collapses.
MeridianSwap {
    id: badge

    property int ahead: 0
    property int behind: 0
    property bool showZero: false
    /// Drawn on a solid `accent` selection.
    property bool onAccent: false
    readonly property bool synced: ahead === 0 && behind === 0

    swapKey: synced
    alignment: 1

    Item {
        implicitWidth: badge.synced ? (badge.showZero ? check.width : 0) : counts.implicitWidth
        implicitHeight: Math.max(check.height, counts.implicitHeight)

        MeridianIcon {
            id: check
            visible: badge.synced && badge.showZero
            anchors.verticalCenter: parent.verticalCenter
            name: "check"
            iconSize: MeridianIcon.Small
            color: Theme.colors.inkMuted
        }

        Row {
            id: counts
            visible: !badge.synced
            anchors.verticalCenter: parent.verticalCenter
            MeridianReveal {
                axis: MeridianReveal.Horizontal
                shown: badge.ahead > 0
                SyncPart {
                    iconName: "arrow-up"
                    count: badge.ahead
                    popOnIncrease: true
                    color: badge.onAccent ? Theme.colors.inkOnAccent : Theme.colors.accentInk
                }
            }
            MeridianReveal {
                axis: MeridianReveal.Horizontal
                shown: badge.ahead > 0 && badge.behind > 0
                Item { implicitWidth: Theme.space.s3; implicitHeight: 1 }
            }
            MeridianReveal {
                axis: MeridianReveal.Horizontal
                shown: badge.behind > 0
                SyncPart {
                    iconName: "arrow-down"
                    count: badge.behind
                    color: badge.onAccent ? Theme.colors.inkOnAccent : Theme.colors.warning
                }
            }

            HoverHandler { id: hover }
            MeridianTooltip {
                shown: hover.hovered
                text: L10n.t("syncAheadBehind", [badge.ahead, badge.behind])
            }
        }
    }
}
