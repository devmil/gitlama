pragma ComponentBehavior: Bound
import QtQuick

// One tab of MeridianTabStrip (internal): a pill with an optional leading
// mark, the label with its unsaved-changes dot, and the close button.
Item {
    id: pill

    required property MeridianTabStrip strip
    property var tab: null
    property bool lifted: false
    property bool ghost: false
    property string entryKey
    property real entryX: 0
    readonly property bool active: !ghost && tab !== null && tab.id === strip.activeTab
    readonly property bool editing: !ghost && !lifted && tab !== null && tab.id === strip._renamingTab
    readonly property bool highlighted: active || lifted || hover.hovered
    readonly property string label: tab !== null ? tab.label : ""

    Accessible.role: Accessible.PageTab
    Accessible.name: tab === null ? "" : (tab.semanticLabel ?? tab.label) + (tab.dirty ? ", " + strip.dirtyLabel : "")
    Accessible.selected: active
    Accessible.onPressAction: if (!ghost) strip._tapped(tab)

    HoverHandler { id: hover; enabled: !pill.ghost }
    TapHandler {
        enabled: !pill.ghost && !pill.editing
        onTapped: pill.strip._tapped(pill.tab)
    }
    TapHandler {
        enabled: !pill.ghost && pill.strip.closable
        acceptedButtons: Qt.MiddleButton
        onTapped: pill.strip.closeRequested(pill.tab.id)
    }
    TapHandler {
        enabled: !pill.ghost
        acceptedButtons: Qt.RightButton
        onTapped: (point) => {
            const at = pill.mapToItem(pill.strip, point.position.x, point.position.y)
            pill.strip.contextMenuRequested(pill.tab.id, at.x, at.y)
        }
    }
    DragHandler {
        enabled: !pill.ghost && !pill.editing && pill.strip.movable
        target: null
        yAxis.enabled: false
        dragThreshold: 0
        onActiveChanged: {
            if (active) {
                const at = pill.mapToItem(pill.strip.contentItemForDrag(), centroid.pressPosition.x, 0)
                pill.strip._startDrag(pill.entryKey, at.x, pill.entryX)
            } else {
                pill.strip._endDrag(true)
            }
        }
        onCentroidChanged: {
            if (!active)
                return
            const at = pill.mapToItem(pill.strip.contentItemForDrag(), centroid.position.x, 0)
            pill.strip._updateDrag(at.x)
        }
    }

    Keys.onMenuPressed: pill.strip.contextMenuRequested(pill.tab.id, pill.x, pill.height)

    MeridianTooltip {
        shown: hover.hovered && !pill.strip.dragging && !pill.editing
        text: pill.tab === null ? "" : (pill.tab.tooltip ?? pill.tab.label)
    }

    Item {
        id: body
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Metrics.tabPillHeight

        MeridianShadow {
            anchors.fill: parent
            visible: pill.lifted
            layers: Theme.shadows.float
            radius: Theme.radius.md
        }
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.md
            color: pill.lifted ? Theme.colors.pane
                 : !pill.active && (hover.hovered || pill.editing) ? Theme.colors.groundHover
                 : Theme.clear(Theme.colors.groundHover)
            border.width: 1
            border.color: pill.editing ? Theme.colors.focus : Theme.clear(Theme.colors.focus)
            Behavior on color { ColorAnimation { duration: Motion.hoverFor(hover.hovered) } }
        }

        Row {
            id: leadingRow
            x: Theme.space.s4
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s3
            readonly property bool hasMark: leadingLoader.active || icon.visible || spinner.visible || dot.visible
            width: hasMark ? implicitWidth : 0
            Loader {
                id: leadingLoader
                active: pill.strip.leadingDelegate !== null && pill.tab !== null
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: pill.strip.leadingDelegate
                property var tab: pill.tab
                property bool tabActive: pill.active
            }
            MeridianSpinner {
                id: spinner
                visible: !leadingLoader.active && pill.tab !== null && pill.tab.spinner === true
                anchors.verticalCenter: parent.verticalCenter
                size: Metrics.tabCloseIconSize
            }
            MeridianIcon {
                id: icon
                visible: !leadingLoader.active && !spinner.visible && pill.tab !== null && (pill.tab.iconName ?? "").length > 0
                anchors.verticalCenter: parent.verticalCenter
                name: pill.tab !== null ? (pill.tab.iconName ?? "") : ""
                iconSize: MeridianIcon.Small
                color: pill.tab !== null && pill.tab.iconColor ? pill.tab.iconColor : Theme.colors.inkMuted
            }
            MeridianStatusDot {
                id: dot
                visible: !leadingLoader.active && !spinner.visible && !icon.visible && pill.tab !== null
                    && pill.tab.dotTone !== undefined && pill.tab.dotTone !== null
                anchors.verticalCenter: parent.verticalCenter
                tone: pill.tab !== null ? (pill.tab.dotTone ?? MeridianStatusDot.Neutral) : MeridianStatusDot.Neutral
                halo: pill.tab !== null && pill.tab.dotHalo === true
            }
        }

        Item {
            id: labelSlot
            x: leadingRow.x + leadingRow.width + (leadingRow.hasMark ? Theme.space.s3 : 0)
            width: close.x - x - Theme.space.s3
            height: parent.height

            Row {
                visible: !pill.editing
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                MeridianText {
                    id: labelText
                    width: Math.min(implicitWidth, parent.width - dirtyDot.width)
                    role: MeridianText.Label
                    text: pill.label
                    color: pill.highlighted ? Theme.colors.ink : Theme.colors.inkMuted
                }
                // The unsaved-changes dot pops in on `spring-pop` and
                // shrinks out over `motion-exit`.
                Item {
                    id: dirtyDot
                    readonly property bool dirty: pill.tab !== null && pill.tab.dirty === true
                    width: dirty || scaleTarget.scale > 0 ? Theme.space.s2 + Metrics.statusDot : 0
                    height: Metrics.statusDot
                    anchors.verticalCenter: parent.verticalCenter
                    onDirtyChanged: {
                        if (dirty) {
                            shrink.stop()
                            grow.restart()
                        } else {
                            grow.stop()
                            shrink.restart()
                        }
                    }
                    Rectangle {
                        id: scaleTarget
                        x: Theme.space.s2
                        width: Metrics.statusDot
                        height: Metrics.statusDot
                        radius: width / 2
                        color: Theme.colors.warning
                        scale: dirtyDot.dirty ? 1 : 0
                    }
                    NumberAnimation { id: grow; target: scaleTarget; property: "scale"; to: 1; duration: Motion.pop.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.pop.curve }
                    NumberAnimation { id: shrink; target: scaleTarget; property: "scale"; to: 0; duration: Motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve }
                }
            }

            Loader {
                active: pill.editing
                anchors.fill: parent
                sourceComponent: TabStripNameField {
                    initial: pill.label
                    placeholder: pill.tab !== null ? (pill.tab.renamePlaceholder ?? pill.label) : ""
                    accessibleName: pill.strip.renameTabLabel
                    maxLength: pill.strip.nameMaxLength
                    fieldHeight: Metrics.tabPillHeight - Theme.space.s2
                    onDone: (name) => pill.strip._finishTabRename(pill.tab.id, name)
                }
            }
        }

        Item {
            id: close
            x: parent.width - Theme.space.s3 - width
            anchors.verticalCenter: parent.verticalCenter
            width: Metrics.tabCloseSize
            height: Metrics.tabCloseSize
            visible: pill.highlighted && !pill.editing && pill.strip.closable && !pill.ghost
            Accessible.role: Accessible.Button
            Accessible.name: pill.strip.closeLabel.arg(pill.label)
            Accessible.onPressAction: pill.strip.closeRequested(pill.tab.id)
            HoverHandler { id: closeHover }
            TapHandler { id: closeTap; onTapped: pill.strip.closeRequested(pill.tab.id) }
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
                text: pill.strip.closeLabel.arg(pill.label)
            }
        }
    }
}
