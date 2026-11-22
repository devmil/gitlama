import QtQuick

// A toolbar badge: a small count pill, hidden at zero.
Item {
    id: root
    property int count: 0
    implicitWidth: count > 0 ? pill.implicitWidth : 0
    implicitHeight: count > 0 ? pill.implicitHeight : 0
    visible: count > 0
    MeridianCount {
        id: pill
        tone: MeridianCount.Accent
        label: root.count > 99 ? "99+" : String(root.count)
    }
}
