pragma ComponentBehavior: Bound
import QtQuick

// Views of one subject (Flutter: MeridianTabs, underline style): `label`
// text, `semibold` while active, and an `accent` rule that glides to the
// active tab on `spring-snappy`. Arrow keys, Home and End move between
// enabled tabs. `tabs` is an array of { label, icon, count, enabled }.
FocusScope {
    id: root

    property var tabs: []
    property int currentIndex: 0
    signal activated(int index)

    readonly property real tabHeight: Theme.size.control + Theme.space.s3
    property Item _activeItem: null

    implicitHeight: tabHeight
    implicitWidth: row.implicitWidth
    activeFocusOnTab: true

    Accessible.role: Accessible.PageTabList

    function step(from, delta) {
        const count = tabs.length
        for (let k = 1; k <= count; ++k) {
            const i = ((from + delta * k) % count + count) % count
            if (tabs[i].enabled !== false)
                return i
        }
        return -1
    }

    Keys.onPressed: event => {
        if (tabs.length === 0)
            return
        const from = Math.max(0, Math.min(currentIndex, tabs.length - 1))
        let target = -2
        if (event.key === Qt.Key_Right) target = step(from, 1)
        else if (event.key === Qt.Key_Left) target = step(from, -1)
        else if (event.key === Qt.Key_Home) target = step(tabs.length - 1, 1)
        else if (event.key === Qt.Key_End) target = step(0, -1)
        if (target === -2)
            return
        event.accepted = true
        if (target >= 0 && target !== currentIndex)
            activated(target)
    }

    Row {
        id: row
        height: parent.height
        Repeater {
            id: repeater
            model: root.tabs
            delegate: Item {
                id: tab
                required property var modelData
                required property int index
                readonly property bool active: index === root.currentIndex
                readonly property bool enabledTab: modelData.enabled !== false
                width: content.implicitWidth + 2 * Theme.space.s4
                height: root.tabHeight
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.count !== undefined ? modelData.label + ", " + modelData.count : modelData.label
                Accessible.selected: active

                Binding {
                    target: root
                    property: "_activeItem"
                    value: tab
                    when: tab.active
                }

                HoverHandler { id: hover; enabled: tab.enabledTab }
                TapHandler {
                    enabled: tab.enabledTab
                    onTapped: {
                        root.forceActiveFocus(Qt.MouseFocusReason)
                        if (!tab.active)
                            root.activated(tab.index)
                    }
                }

                Row {
                    id: content
                    anchors.centerIn: parent
                    spacing: Theme.space.s3
                    readonly property color ink: !tab.enabledTab ? Theme.colors.inkFaint
                        : tab.active || hover.hovered ? Theme.colors.ink : Theme.colors.inkMuted
                    MeridianIcon {
                        visible: (tab.modelData.icon ?? "").length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        name: tab.modelData.icon ?? ""
                        iconSize: MeridianIcon.Small
                        color: content.ink
                    }
                    MeridianText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, Metrics.tabLabelMaxWidth)
                        role: MeridianText.Label
                        fontWeight: tab.active ? Font.DemiBold : -1
                        text: tab.modelData.label
                        color: content.ink
                        Behavior on color { ColorAnimation { duration: Motion.hoverFor(hover.hovered) } }
                    }
                    MeridianCount {
                        visible: tab.modelData.count !== undefined && tab.modelData.count !== null
                        anchors.verticalCenter: parent.verticalCenter
                        label: String(tab.modelData.count ?? "")
                    }
                }
                MeridianFocusRing {
                    target: tab
                    shown: root.activeFocus && tab.active && root.focusReasonVisible
                    targetRadius: Theme.radius.md
                }
            }
        }
    }

    property bool focusReasonVisible: false
    onActiveFocusChanged: focusReasonVisible = activeFocus && !_pointerFocus
    property bool _pointerFocus: false

    Rectangle {
        id: rule
        y: root.tabHeight - height
        height: Metrics.tabRuleHeight
        radius: height / 2
        color: Theme.colors.accent
        visible: root._activeItem !== null
        x: root._activeItem ? root._activeItem.x + Theme.space.s4 : 0
        width: root._activeItem ? root._activeItem.width - 2 * Theme.space.s4 : 0
        Behavior on x {
            enabled: rule.visible
            NumberAnimation { duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve }
        }
        Behavior on width {
            enabled: rule.visible
            NumberAnimation { duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve }
        }
    }
}
