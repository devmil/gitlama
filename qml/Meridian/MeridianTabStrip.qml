pragma ComponentBehavior: Bound
import QtQuick

// Open documents or hosts as pills on `ground` (Flutter: MeridianTabStrip).
// Tabs share the width between `tab-pill-min-width` and the label maximum;
// the active pill (`pane`, `shadow-pane`) glides to the active tab; resting
// tabs are separated by a `line-strong` hairline. A tab shows its ✕ while
// active or hovered; a middle click closes it. Drag a tab to reorder.
//
// `tabs` is an array of { id, label, tooltip, semanticLabel, dotTone,
// dotHalo }; a `dotTone` (MeridianStatusDot.Tone) adds a leading state dot.
Item {
    id: root

    property var tabs: []
    property string activeTab
    property string closeLabel: "Close %1"
    property string moveLeftLabel: "Move left"
    property string moveRightLabel: "Move right"

    signal activated(string id)
    signal closeRequested(string id)
    /// A tab dropped at `index` (within `tabs`).
    signal moveRequested(string id, int index)

    readonly property real gap: Theme.space.s2
    readonly property real tabWidth: tabs.length === 0 ? Metrics.tabLabelMaxWidth
        : Math.max(Metrics.tabPillMinWidth, Math.min(Metrics.tabLabelMaxWidth,
              (width - Math.max(0, tabs.length - 1) * gap) / tabs.length))
    readonly property int activeIndex: tabs.findIndex(tab => tab.id === activeTab)
    property int _dragIndex: -1
    property int _dropIndex: -1
    property real _dragX: 0

    implicitHeight: Metrics.tabStripHeight
    implicitWidth: tabs.length * Metrics.tabLabelMaxWidth + Math.max(0, tabs.length - 1) * gap
    clip: true

    Accessible.role: Accessible.PageTabList

    function slotX(index) {
        // While dragging, the others make room where the drag would land.
        if (_dragIndex < 0)
            return index * (tabWidth + gap)
        let slot = index
        if (index > _dragIndex) slot -= 1
        if (slot >= _dropIndex) slot += 1
        return slot * (tabWidth + gap)
    }

    // The active pill.
    Item {
        id: indicator
        visible: root.activeIndex >= 0 && root._dragIndex !== root.activeIndex
        x: root.activeIndex >= 0 ? root.slotX(root.activeIndex) : 0
        width: root.tabWidth
        height: Metrics.tabPillHeight
        anchors.verticalCenter: parent.verticalCenter
        Behavior on x {
            NumberAnimation { duration: Motion.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve }
        }
        MeridianShadow {
            anchors.fill: parent
            layers: Theme.shadows.pane
            radius: Theme.radius.md
        }
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.md
            color: Theme.colors.pane
        }
    }

    Repeater {
        model: root.tabs
        delegate: Item {
            id: tab
            required property var modelData
            required property int index
            readonly property bool active: modelData.id === root.activeTab
            readonly property bool lifted: root._dragIndex === index
            readonly property bool showClose: active || lifted || hover.hovered

            x: lifted ? root._dragX : root.slotX(index)
            z: lifted ? 10 : 1
            width: root.tabWidth
            height: root.height
            Behavior on x {
                enabled: !tab.lifted
                NumberAnimation { duration: Motion.layout; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
            }

            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.semanticLabel ?? modelData.label
            Accessible.selected: active

            // The separator after this tab, between two resting tabs.
            Rectangle {
                readonly property var next: root.tabs[tab.index + 1]
                visible: next !== undefined
                x: parent.width + (root.gap - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: Metrics.hairline
                height: Metrics.tabSeparatorHeight
                color: Theme.colors.lineStrong
                opacity: root._dragIndex < 0 && !tab.active && next !== undefined && next.id !== root.activeTab ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.exit } }
            }

            HoverHandler { id: hover }
            TapHandler {
                onTapped: if (!tab.active) root.activated(tab.modelData.id)
            }
            TapHandler {
                acceptedButtons: Qt.MiddleButton
                onTapped: root.closeRequested(tab.modelData.id)
            }
            DragHandler {
                id: drag
                target: null
                yAxis.enabled: false
                dragThreshold: Metrics.tabDragThreshold
                property real startX: 0
                onActiveChanged: {
                    if (active) {
                        startX = root.slotX(tab.index)
                        root._dragX = startX
                        root._dragIndex = tab.index
                        root._dropIndex = tab.index
                    } else if (root._dragIndex === tab.index) {
                        const target = root._dropIndex
                        const id = tab.modelData.id
                        root._dragIndex = -1
                        root._dropIndex = -1
                        if (target !== tab.index)
                            root.moveRequested(id, target)
                    }
                }
                onActiveTranslationChanged: {
                    if (!active)
                        return
                    const maxX = Math.max(0, (root.tabs.length - 1) * (root.tabWidth + root.gap))
                    root._dragX = Math.max(0, Math.min(maxX, startX + activeTranslation.x))
                    root._dropIndex = Math.max(0, Math.min(root.tabs.length - 1,
                        Math.round(root._dragX / (root.tabWidth + root.gap))))
                }
            }

            MeridianTooltip {
                shown: hover.hovered && !drag.active
                text: tab.modelData.tooltip ?? tab.modelData.label
            }

            Item {
                id: pill
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Metrics.tabPillHeight
                MeridianShadow {
                    anchors.fill: parent
                    visible: tab.lifted
                    layers: Theme.shadows.float
                    radius: Theme.radius.md
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius.md
                    color: tab.lifted ? Theme.colors.pane
                         : !tab.active && hover.hovered ? Theme.colors.groundHover
                         : Theme.clear(Theme.colors.groundHover)
                    Behavior on color { ColorAnimation { duration: Motion.hoverFor(hover.hovered) } }
                }
                MeridianStatusDot {
                    id: leading
                    visible: tab.modelData.dotTone !== undefined && tab.modelData.dotTone !== null
                    x: Theme.space.s4
                    anchors.verticalCenter: parent.verticalCenter
                    tone: tab.modelData.dotTone ?? MeridianStatusDot.Neutral
                    halo: tab.modelData.dotHalo === true
                }
                MeridianText {
                    x: leading.visible ? leading.x + leading.width + Theme.space.s3 : Theme.space.s4
                    width: close.x - x - Theme.space.s3
                    anchors.verticalCenter: parent.verticalCenter
                    role: MeridianText.Label
                    text: tab.modelData.label
                    color: tab.active || tab.lifted || hover.hovered ? Theme.colors.ink : Theme.colors.inkMuted
                }
                Item {
                    id: close
                    x: parent.width - Theme.space.s3 - width
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.tabCloseSize
                    height: Metrics.tabCloseSize
                    visible: tab.showClose
                    Accessible.role: Accessible.Button
                    Accessible.name: root.closeLabel.arg(tab.modelData.label)
                    HoverHandler { id: closeHover }
                    TapHandler { id: closeTap; onTapped: root.closeRequested(tab.modelData.id) }
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius.xs
                        readonly property color hoverFill: Qt.alpha(Theme.colors.ink, Metrics.opacityPrimaryHoverOverlay)
                        color: closeTap.pressed ? Theme.blend(hoverFill, Theme.colors.ink, Metrics.opacityPressedOverlay)
                             : closeHover.hovered ? hoverFill : Theme.clear(Theme.colors.ink)
                        Behavior on color { ColorAnimation { duration: Motion.hoverFor(closeHover.hovered) } }
                    }
                    MeridianIcon {
                        anchors.centerIn: parent
                        name: "x"
                        extent: Metrics.tabCloseIconSize
                        color: closeHover.hovered || closeTap.pressed ? Theme.colors.ink : Theme.colors.inkMuted
                    }
                    MeridianTooltip {
                        shown: closeHover.hovered
                        text: root.closeLabel.arg(tab.modelData.label)
                    }
                }
            }
        }
    }
}
