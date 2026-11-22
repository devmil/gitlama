pragma ComponentBehavior: Bound
import QtQuick

// A group's chip in MeridianTabStrip (internal): the icon and name (or a
// colour dot) on a tint of the group's colour, and the tab count while
// collapsed or dragged. A click collapses or expands the group.
Item {
    id: chip

    required property MeridianTabStrip strip
    property var group: null
    property int count: 0
    property bool lifted: false
    property string entryKey
    property real entryX: 0
    readonly property bool editing: !lifted && group !== null && group.id === strip._renamingGroup
    readonly property string name: group === null ? "" : group.name && group.name.length > 0 ? group.name
        : group.label ?? strip.unnamedGroupLabel
    readonly property bool hasName: group !== null && !!group.name && group.name.length > 0

    Accessible.role: Accessible.Button
    Accessible.name: _announced(strip.groupLabel, name, count)

    function _announced(template, name, count) {
        return typeof template === "function" ? template(name, count) : String(template).arg(name).arg(count)
    }
    Accessible.onPressAction: strip.groupToggled(group.id)

    HoverHandler { id: hover }
    TapHandler {
        enabled: !chip.editing
        onTapped: chip.strip.groupToggled(chip.group.id)
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (point) => {
            const at = chip.mapToItem(chip.strip, point.position.x, point.position.y)
            chip.strip.groupContextMenuRequested(chip.group.id, at.x, at.y)
        }
    }
    DragHandler {
        enabled: !chip.editing && chip.strip.groupsMovable
        target: null
        yAxis.enabled: false
        dragThreshold: 0
        onActiveChanged: {
            if (active) {
                const at = chip.mapToItem(chip.strip.contentItemForDrag(), centroid.pressPosition.x, 0)
                chip.strip._startDrag(chip.entryKey, at.x, chip.entryX)
            } else {
                chip.strip._endDrag(true)
            }
        }
        onCentroidChanged: {
            if (!active)
                return
            const at = chip.mapToItem(chip.strip.contentItemForDrag(), centroid.position.x, 0)
            chip.strip._updateDrag(at.x)
        }
    }

    MeridianTooltip {
        shown: hover.hovered && !chip.editing && !chip.strip.dragging
        text: chip.group !== null && chip.group.collapsed ? chip.strip.expandGroupLabel.arg(chip.name)
                                                          : chip.strip.collapseGroupLabel.arg(chip.name)
    }

    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Metrics.tabGroupChipHeight

        MeridianShadow {
            anchors.fill: parent
            visible: chip.lifted
            layers: Theme.shadows.float
            radius: Theme.radius.md
        }
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.md
            readonly property color tint: chip.group !== null ? chip.group.color : "transparent"
            // A lifted chip lays its tint over the pane's fill.
            color: chip.lifted ? Theme.blend(Theme.colors.pane, tint, Metrics.opacityTabGroupFillHover)
                 : Qt.alpha(tint, hover.hovered || chip.editing ? Metrics.opacityTabGroupFillHover : Metrics.opacityTabGroupFill)
            border.width: 1
            border.color: chip.editing ? Theme.colors.focus : Theme.clear(Theme.colors.focus)
            Behavior on color { ColorAnimation { duration: Motion.hoverFor(hover.hovered) } }
        }

        Row {
            visible: !chip.editing
            anchors.centerIn: parent
            spacing: 0
            MeridianIcon {
                visible: chip.group !== null && !!chip.group.icon
                anchors.verticalCenter: parent.verticalCenter
                name: chip.group !== null ? (chip.group.icon ?? "") : ""
                iconSize: MeridianIcon.Small
                color: chip.group !== null ? chip.group.color : Theme.colors.ink
            }
            Item { visible: chip.group !== null && !!chip.group.icon && chip.hasName; width: Theme.space.s3; height: 1 }
            MeridianText {
                visible: chip.hasName
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Metrics.tabGroupChipLabelMaxWidth)
                role: MeridianText.Label
                color: Theme.colors.ink
                text: chip.group !== null ? chip.group.name : ""
            }
            Rectangle {
                visible: !chip.hasName && chip.group !== null && !chip.group.icon
                anchors.verticalCenter: parent.verticalCenter
                width: Metrics.tabGroupDot
                height: Metrics.tabGroupDot
                radius: width / 2
                color: chip.group !== null ? chip.group.color : "transparent"
            }
            Item { visible: chip.group !== null && chip.group.collapsed === true; width: Theme.space.s3; height: 1 }
            MeridianText {
                visible: chip.group !== null && chip.group.collapsed === true
                anchors.verticalCenter: parent.verticalCenter
                role: MeridianText.Caption
                tabular: true
                color: Theme.colors.inkMuted
                text: String(chip.count)
            }
        }

        Loader {
            active: chip.editing
            anchors.fill: parent
            anchors.leftMargin: Theme.space.s3
            anchors.rightMargin: Theme.space.s3
            sourceComponent: TabStripNameField {
                initial: chip.group !== null ? chip.group.name : ""
                placeholder: chip.strip.groupNamePlaceholder
                accessibleName: chip.strip.renameGroupLabel
                maxLength: chip.strip.nameMaxLength
                fieldHeight: Metrics.tabGroupChipHeight
                onDone: (name) => chip.strip._finishGroupRename(chip.group.id, name)
            }
        }
    }
}
