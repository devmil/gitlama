import QtQuick

// A host's automatic reconnection for a banner or a tab: the status texts, counting down each second while an attempt is
// due, and the actions Install helper, Reconnect (now / try again) and Stop.
QtObject {
    id: reconnect

    property string profileId
    readonly property var host: Labels.remoteHost(profileId)
    readonly property var state: host ? (host.reconnect ?? null) : null
    readonly property bool connecting: host !== null && host.connecting === true
    readonly property bool automatic: state !== null && state.phase !== "stopped"
    readonly property bool install: !connecting && host !== null && host.needsHelper === true
    /// When the next attempt starts (ms since the epoch), while one is due.
    property real dueAt: 0
    property int seconds: 0
    readonly property var status: state && host ? Labels.remoteReconnectStatus(host, seconds) : null
    readonly property string reconnectLabel: automatic ? L10n.t("remoteReconnectNow")
        : state && state.gaveUp ? L10n.t("remoteReconnectTryAgain") : L10n.t("remoteReconnect")

    onStateChanged: {
        if (state && state.phase === "waiting" && state.seconds !== null && state.seconds !== undefined) {
            dueAt = Date.now() + state.seconds * 1000
            seconds = state.seconds
            ticker.start()
        } else {
            ticker.stop()
        }
    }
    property Timer ticker: Timer {
        interval: GitLamaLayout.reconnectCountdownTick
        repeat: true
        onTriggered: reconnect.seconds = Math.max(0, Math.ceil((reconnect.dueAt - Date.now()) / 1000))
    }

    function reconnectNow() { Store.remote.reconnect(profileId) }
    function stop() { Store.remote.stopReconnecting(profileId) }
    function installHelper() { Store.remote.installHelper(profileId) }
}
