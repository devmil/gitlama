pragma Singleton
import QtQuick

// Moments that play once per session (Flutter: MeridianMotionMemory): an entrance, a landing
// or an arrival is keyed, and a key seen once stays seen, so a recycled list row or a
// re-created view shows its content at rest. Bounded: the oldest keys are forgotten first.
QtObject {
    id: memory

    /// The most keys remembered.
    readonly property int capacity: 4096
    property var _seen: ({})
    property var _order: []

    /// Marks `key` seen; true only the first time.
    function markSeen(key) {
        const name = String(key)
        if (_seen[name] === true)
            return false
        _seen[name] = true
        _order.push(name)
        if (_order.length > capacity)
            delete _seen[_order.shift()]
        return true
    }

    /// Whether `key` was seen.
    function seen(key) {
        return _seen[String(key)] === true
    }

    /// Forgets every key (tests).
    function clear() {
        _seen = ({})
        _order = []
    }
}
