pragma ComponentBehavior: Bound
import QtQuick

// A browser-style strip of document tabs on `ground` (Flutter:
// MeridianTabStrip). Tabs share the width (between `tab-pill-min-width` and
// `tab-label-max-width`) and scroll when they do not fit. The active tab is a
// `pane` pill that glides between tabs; resting tabs are separated by a
// `line-strong` hairline. A tab shows its ✕ while active or hovered; a middle
// click closes it. New tabs grow in, closed ones fade while they collapse.
//
// Groups: `groups` are { id, color, name, icon, collapsed, label }; a tab's
// `group` names one. A group's chip stands before its tabs, a rule in the
// group's colour runs under them, and a collapsed group shows only its chip
// and tab count. Tabs and chips are dragged straight along the strip: the
// others make room, a chip carries its whole group, and a tab joins a group
// once it passes the chip or the group's last tab; at a group's end a short
// nudge outwards takes it out. Escape cancels a drag.
//
// `tabs` are { id, label, group, tooltip, semanticLabel, dirty, renamable,
// renamePlaceholder, iconName, iconColor, spinner, dotTone, dotHalo }. Give
// `leadingDelegate` for a custom mark: its Loader carries `tab` (the entry)
// and `tabActive`.
Item {
    id: root

    property var tabs: []
    property var groups: []
    property var activeTab
    property bool closable: true
    property bool movable: true
    property bool groupsMovable: false
    property bool renamable: false
    property int nameMaxLength: -1
    property Component leadingDelegate: null

    property string closeLabel: "Close %1"
    property string moveLeftLabel: "Move left"
    property string moveRightLabel: "Move right"
    property string collapseGroupLabel: "Collapse %1"
    property string expandGroupLabel: "Expand %1"
    /// The chip's announced name: a template (%1 group, %2 tab count) or a
    /// function (name, count) for plural-aware wording.
    property var groupLabel: "%1, tab group, %2 tabs"
    property string unnamedGroupLabel: "Unnamed group"
    property string renameTabLabel: "Tab name"
    property string renameGroupLabel: "Group name"
    property string groupNamePlaceholder: "Name this group"
    property string dirtyLabel: "unsaved changes"

    signal activated(var id)
    signal closeRequested(var id)
    /// A tab dropped at `index` among the other tabs, in `group` (or none).
    signal moveRequested(var id, int index, var group)
    /// A group's chip dropped so its tabs start at `index` among the others.
    signal groupMoveRequested(var group, int index)
    /// A right click or the menu key on a tab, at `x`, `y` in the strip.
    signal contextMenuRequested(var id, real x, real y)
    /// A tab named in place; an empty name asks for the default.
    signal renamed(var id, string name)
    signal groupToggled(var group)
    signal groupContextMenuRequested(var group, real x, real y)
    signal groupRenamed(var group, string name)

    readonly property real gap: Theme.space.s2
    readonly property bool dragging: _drag !== null && _drag.started
    /// The tab width of the last layout.
    property real tabWidth: Metrics.tabLabelMaxWidth
    property real _total: 0
    property var _renamingTab: null
    property var _renamingGroup: null

    implicitHeight: Metrics.tabStripHeight
    implicitWidth: _total
    Accessible.role: Accessible.PageTabList

    /// Edits `id`'s name in place.
    function renameTab(id) {
        if (!renamable)
            return
        _renamingGroup = null
        _renamingTab = id
        _relayout()
    }

    /// Edits group `id`'s name in place.
    function renameGroup(id) {
        if (!renamable)
            return
        _renamingTab = null
        _renamingGroup = id
        _relayout()
    }

    // ---------------------------------------------------------------- state

    /// The order a drop asked for, kept until the owner's tabs change.
    property var _pending: null
    property var _pendingBase: null
    property var _drag: null
    /// Closed tabs still collapsing: [{tab, index}].
    property var _closing: []
    property var _previousTabs: []
    property bool _built: false
    property var _lastTap: null
    property var _tabsById: ({})
    property var _groupsById: ({})
    readonly property bool _animate: _built && !Motion.reduced

    onTabsChanged: _tabsUpdated()
    onGroupsChanged: _relayout()
    onActiveTabChanged: _relayout(true)
    onWidthChanged: _relayout()
    Component.onCompleted: {
        _tabsUpdated()
        _built = true
    }
    Connections {
        target: Theme
        function onDensityChanged() { root._relayout() }
        function onTextScaleChanged() { root._relayout() }
    }

    function _order(list) {
        return list.map(tab => ({ id: tab.id, group: tab.group ?? null }))
    }

    function _sameOrder(a, b) {
        if (a.length !== b.length)
            return false
        for (let i = 0; i < a.length; ++i)
            if (a[i].id !== b[i].id || a[i].group !== b[i].group)
                return false
        return true
    }

    function _tabsUpdated() {
        const after = {}
        for (const tab of tabs)
            after[tab.id] = true
        if (_renamingTab !== null && !after[_renamingTab])
            _renamingTab = null
        if (_pendingBase !== null && !_sameOrder(_pendingBase, _order(tabs)))
            _clearPending()
        if (_drag !== null && _drag.tab !== null && !after[_drag.tab])
            _endDrag(false)
        if (_built && !Motion.reduced) {
            const closing = _closing.filter(ghost => after[ghost.tab.id] === undefined)
            _previousTabs.forEach((tab, index) => {
                if (after[tab.id] || closing.some(ghost => ghost.tab.id === tab.id))
                    return
                closing.push({ tab: tab, index: index })
                ghostCleanup.restart()
            })
            _closing = closing
        }
        _previousTabs = tabs.slice()
        _relayout()
    }

    function _clearPending() {
        _pending = null
        _pendingBase = null
        pendingTimeout.stop()
    }

    Timer {
        id: pendingTimeout
        interval: Tokens.durations.attention
        onTriggered: { root._clearPending(); root._relayout() }
    }
    Timer {
        id: ghostCleanup
        interval: Motion.layout + 20
        onTriggered: { root._closing = []; root._relayout() }
    }
    Timer {
        id: tapTimeout
        interval: Application.styleHints.mouseDoubleClickInterval
        onTriggered: root._lastTap = null
    }

    // --------------------------------------------------------------- layout

    TextMetrics { id: nameMetrics; font: Theme.type.label }
    TextMetrics { id: countMetrics; font: Theme.type.caption }

    function _measure(metrics, text) {
        metrics.text = text
        return metrics.advanceWidth
    }

    function _chipWidth(group, count, editing) {
        if (editing)
            return Metrics.tabGroupChipEditWidth
        const icon = group.icon ? Theme.size.iconSmall : -1
        const name = group.name && group.name.length > 0
            ? Math.min(_measure(nameMetrics, group.name), Metrics.tabGroupChipLabelMaxWidth) : -1
        let content = icon >= 0 && name >= 0 ? icon + Theme.space.s3 + name
            : icon >= 0 ? icon : name >= 0 ? name : Metrics.tabGroupDot
        if (group.collapsed)
            content += Theme.space.s3 + _measure(countMetrics, String(count))
        const padding = name >= 0 || group.collapsed ? Theme.space.s4
            : (Metrics.tabGroupChipHeight - (icon >= 0 ? icon : Metrics.tabGroupDot)) / 2
        return Math.ceil(content + padding * 2)
    }

    /// The live entries in `order`: each group's chip before its first tab.
    function _entries(order) {
        const counts = {}
        for (const entry of order)
            if (entry.group !== null && _groupsById[entry.group] !== undefined)
                counts[entry.group] = (counts[entry.group] ?? 0) + 1
        const seen = {}
        const result = []
        for (const entry of order) {
            const tab = _tabsById[entry.id]
            if (tab === undefined)
                continue
            const group = entry.group !== null ? _groupsById[entry.group] : undefined
            if (group !== undefined) {
                if (!seen[group.id]) {
                    seen[group.id] = true
                    result.push({ key: "group:" + group.id, kind: "chip", group: group, count: counts[group.id] ?? 0 })
                }
                result.push({ key: "tab:" + tab.id, kind: "tab", tab: tab, group: group })
            } else {
                result.push({ key: "tab:" + tab.id, kind: "tab", tab: tab, group: null })
            }
        }
        return result
    }

    function _withGhosts(entries) {
        if (_closing.length === 0)
            return entries
        const result = entries.slice()
        for (const ghost of _closing) {
            let at = 0
            let tabs = 0
            while (at < result.length && tabs < ghost.index) {
                if (result[at].kind === "tab")
                    tabs++
                at++
            }
            result.splice(at, 0, { key: "closing:" + ghost.tab.id, kind: "ghost", tab: ghost.tab, group: null })
        }
        return result
    }

    function _hidden(entry) {
        return entry.kind === "tab" && entry.group !== null && entry.group.collapsed === true
    }

    function _width(entry) {
        if (entry.kind === "chip")
            return _chipWidth(entry.group, entry.count, entry.group.id === _renamingGroup)
        if (entry.kind === "ghost" || _hidden(entry))
            return 0
        return tabWidth
    }

    function _starts(widths) {
        const starts = []
        let x = 0
        for (const width of widths) {
            starts.push(x)
            if (width > 0)
                x += width + gap
        }
        return starts
    }

    /// The live entries without the dragged tab or group.
    function _rest(entries, drag) {
        return entries.filter(entry => {
            if (entry.kind === "ghost")
                return false
            if (entry.kind === "tab")
                return entry.tab.id !== drag.tab && (drag.group === null || entry.group === null || entry.group.id !== drag.group)
            return entry.group.id !== drag.group
        })
    }

    /// The drop nearest to `start`: {slot, group}.
    function _dropAt(rest, widths, start, drag) {
        const starts = _starts(widths)
        const startOf = slot => slot < rest.length ? starts[slot]
            : (rest.length === 0 ? 0 : starts[starts.length - 1] + (widths[widths.length - 1] > 0 ? widths[widths.length - 1] + gap : 0))
        const candidates = []
        for (let slot = 0; slot <= rest.length; ++slot) {
            const previous = slot > 0 ? rest[slot - 1] : null
            const next = slot < rest.length ? rest[slot] : null
            // A collapsed group's folded tabs travel with its chip.
            if (next !== null && _hidden(next))
                continue
            const open = previous !== null && previous.group !== null && !previous.group.collapsed ? previous.group : null
            const inside = open !== null && next !== null && next.group !== null && next.group.id === open.id
            if (drag.group !== null) {
                // A group never lands inside another.
                if (!inside)
                    candidates.push([{ slot: slot, group: null }, startOf(slot)])
                continue
            }
            if (open === null) {
                candidates.push([{ slot: slot, group: null }, startOf(slot)])
                continue
            }
            candidates.push([{ slot: slot, group: open.id }, startOf(slot)])
            // At the group's end a short nudge outwards leaves it.
            if (!inside)
                candidates.push([{ slot: slot, group: null }, startOf(slot) + Metrics.tabGroupEdgeShift])
        }
        let best = candidates[0]
        for (let i = 1; i < candidates.length; ++i)
            if (Math.abs(candidates[i][1] - start) < Math.abs(best[1] - start))
                best = candidates[i]
        return best[0]
    }

    /// The order with the dragged tab or group at `drop`.
    function _dropped(rest, drag, drop) {
        const before = rest.slice(0, drop.slot).filter(entry => entry.kind === "tab")
        const after = rest.slice(drop.slot).filter(entry => entry.kind === "tab")
        const moved = drag.tab !== null ? [{ id: drag.tab, group: drop.group }]
            : tabs.filter(tab => (tab.group ?? null) === drag.group).map(tab => ({ id: tab.id, group: tab.group ?? null }))
        return before.map(entry => ({ id: entry.tab.id, group: entry.group ? entry.group.id : null }))
            .concat(moved)
            .concat(after.map(entry => ({ id: entry.tab.id, group: entry.group ? entry.group.id : null })))
    }

    property bool _activeMoved: false
    function _relayout(activeChanged) {
        if (activeChanged === true)
            _activeMoved = true
        Qt.callLater(_layout)
    }

    function _layout() {
        const byId = {}
        for (const tab of tabs)
            byId[tab.id] = tab
        _tabsById = byId
        const groupsById = {}
        for (const group of groups)
            groupsById[group.id] = group
        _groupsById = groupsById

        const base = _entries(_pending ?? _order(tabs))
        let entries = _withGhosts(base)
        let chipsWidth = 0
        let chips = 0
        let shownTabs = 0
        for (const entry of entries) {
            if (entry.kind === "chip") {
                chipsWidth += _width(entry)
                chips++
            } else if (entry.kind === "tab" && !_hidden(entry)) {
                shownTabs++
            }
        }
        const gaps = Math.max(0, shownTabs + chips - 1) * gap
        const available = width > 0 ? width : shownTabs * Metrics.tabLabelMaxWidth + chipsWidth + gaps
        tabWidth = shownTabs === 0 ? Metrics.tabLabelMaxWidth
            : Math.max(Metrics.tabPillMinWidth, Math.min(Metrics.tabLabelMaxWidth, (available - chipsWidth - gaps) / shownTabs))

        // While dragging, the others make room where the drag would land.
        const dragged = {}
        let dragStart = 0
        const drag = _drag !== null && _drag.started ? _drag : null
        if (drag !== null) {
            const rest = _rest(base, drag)
            const restWidths = rest.map(entry => _width(entry))
            dragStart = drag.pointer - drag.grab
            const drop = _dropAt(rest, restWidths, dragStart, drag)
            const moving = base.filter(entry => rest.indexOf(entry) < 0).map(entry => {
                if (entry.kind === "tab")
                    return { key: entry.key, kind: "tab", tab: entry.tab,
                             group: drag.tab !== null ? (drop.group !== null ? _groupsById[drop.group] ?? null : null) : entry.group }
                return entry
            })
            for (const entry of moving)
                dragged[entry.key] = true
            entries = _withGhosts(rest.slice(0, drop.slot).concat(moving).concat(rest.slice(drop.slot)))
        }

        const widths = entries.map(entry => _width(entry))
        const starts = _starts(widths)
        let blockOffset = 0
        const targets = []
        for (let index = 0; index < entries.length; ++index) {
            const entry = entries[index]
            let x = starts[index]
            if (dragged[entry.key]) {
                x = dragStart + blockOffset
                if (widths[index] > 0)
                    blockOffset += widths[index] + gap
            }
            targets.push({ entry: entry, x: x, w: widths[index], lifted: dragged[entry.key] === true })
        }

        // Group rules: from the chip to the group's last shown tab.
        const spans = {}
        for (const target of targets) {
            const group = target.entry.group
            if (group === null || group === undefined || group.collapsed || target.entry.kind === "ghost")
                continue
            const span = spans[group.id]
            const right = target.x + target.w
            spans[group.id] = span === undefined ? [target.x, right] : [Math.min(span[0], target.x), Math.max(span[1], right)]
        }

        // Separators between two resting tabs.
        for (let index = 0; index < targets.length; ++index) {
            const target = targets[index]
            target.separated = false
            if (target.entry.kind !== "tab" || _hidden(target.entry))
                continue
            let next = null
            for (let after = index + 1; after < targets.length; ++after) {
                if (targets[after].w > 0) {
                    next = targets[after]
                    break
                }
            }
            target.separated = next !== null && next.entry.kind === "tab" && drag === null
                && target.entry.tab.id !== activeTab && next.entry.tab.id !== activeTab
        }

        _apply(targets, spans)

        let total = 0
        for (const target of targets)
            total = Math.max(total, target.x + target.w)
        _total = total

        // The active pill.
        const activeTarget = targets.find(target => target.entry.kind === "tab" && target.entry.tab.id === activeTab)
        if (activeTarget !== undefined) {
            indicator.duration = !_animate ? 0 : _activeMoved ? Motion.select : Motion.layout
            indicator.following = activeTarget.lifted
            indicator.targetX = activeTarget.x
            indicator.targetW = activeTarget.w
            indicator.shown = true
        } else {
            indicator.shown = false
        }
        _activeMoved = false
    }

    function _apply(targets, spans) {
        const live = {}
        for (let index = 0; index < targets.length; ++index) {
            const target = targets[index]
            const entry = target.entry
            live[entry.key] = true
            const values = {
                key: entry.key,
                kind: entry.kind,
                tabId: entry.kind === "chip" ? null : entry.tab.id,
                groupId: entry.group ? entry.group.id : null,
                targetX: target.x,
                targetW: target.w,
                lifted: target.lifted,
                separated: target.separated === true,
                spanW: entry.kind === "chip" && spans[entry.group.id] !== undefined ? spans[entry.group.id][1] - target.x : 0,
                hidden: _hidden(entry),
                count: entry.kind === "chip" ? entry.count : 0,
                ghostLabel: entry.kind === "ghost" ? entry.tab.label : "",
            }
            const at = _indexOf(entry.key)
            if (at < 0) {
                // A new tab grows in where it stands.
                const grow = _animate && entry.kind !== "ghost"
                entryModel.insert(Math.min(index, entryModel.count), Object.assign({}, values, { targetW: grow ? 0 : target.w, fresh: true }))
                if (grow)
                    entryModel.setProperty(Math.min(index, entryModel.count - 1), "targetW", target.w)
            } else {
                if (at !== index && index < entryModel.count)
                    entryModel.move(at, index, 1)
                const row = Math.min(index, entryModel.count - 1)
                for (const name in values)
                    if (entryModel.get(row)[name] !== values[name])
                        entryModel.setProperty(row, name, values[name])
            }
        }
        for (let row = entryModel.count - 1; row >= 0; --row)
            if (!live[entryModel.get(row).key])
                entryModel.remove(row)
    }

    function _indexOf(key) {
        for (let row = 0; row < entryModel.count; ++row)
            if (entryModel.get(row).key === key)
                return row
        return -1
    }

    ListModel {
        id: entryModel
        dynamicRoles: true
    }

    // ----------------------------------------------------------------- drag

    function _startDrag(key, pointer, startX) {
        const tabId = key.startsWith("tab:") ? key.slice(4) : null
        const groupId = key.startsWith("group:") ? key.slice(6) : null
        const resolve = (text, ids) => ids.find(id => String(id) === text) ?? null
        _drag = {
            tab: tabId !== null ? resolve(tabId, tabs.map(tab => tab.id)) : null,
            group: groupId !== null ? resolve(groupId, groups.map(group => group.id)) : null,
            grab: pointer - startX,
            pointer: pointer,
            down: pointer,
            started: false,
        }
    }

    function _updateDrag(pointer) {
        if (_drag === null)
            return
        const drag = _drag
        drag.pointer = pointer
        if (!drag.started) {
            if (Math.abs(drag.pointer - drag.down) < Metrics.tabDragThreshold)
                return
            drag.started = true
            _clearPending()
        }
        _drag = drag
        _layout()
        _autoScroll()
    }

    /// Ends the drag; with `drop`, reports where it landed and keeps that
    /// order until the owner's tabs follow.
    function _endDrag(drop) {
        const drag = _drag
        _drag = null
        if (drag === null || !drag.started) {
            _layout()
            return
        }
        if (drop) {
            const base = _order(tabs)
            const rest = _rest(_entries(base), drag)
            const landed = _dropAt(rest, rest.map(entry => _width(entry)), drag.pointer - drag.grab, drag)
            const order = _dropped(rest, drag, landed)
            if (!_sameOrder(order, base)) {
                _pending = order
                _pendingBase = base
                pendingTimeout.restart()
                const others = rest.slice(0, landed.slot).filter(entry => entry.kind === "tab").length
                if (drag.tab !== null)
                    moveRequested(drag.tab, others, landed.group)
                else if (drag.group !== null)
                    groupMoveRequested(drag.group, others)
            }
        }
        _layout()
    }

    /// Scrolls while a drag holds the pointer near the strip's edges.
    function _autoScroll() {
        if (!dragging || flick.contentWidth <= flick.width)
            return
        const local = _drag.pointer - flick.contentX
        const edge = Metrics.tabStripScrollEdge
        let delta = 0
        if (local < edge)
            delta = -(edge - local)
        if (local > flick.width - edge)
            delta = local - (flick.width - edge)
        if (delta === 0)
            return
        const next = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX + delta * Metrics.tabStripScrollRate))
        if (next === flick.contentX)
            return
        const moved = next - flick.contentX
        flick.contentX = next
        _drag.pointer += moved
        autoScroll.restart()
    }
    Timer {
        id: autoScroll
        interval: 16
        onTriggered: if (root.dragging) { root._layout(); root._autoScroll() }
    }

    Shortcut {
        enabled: root.dragging
        sequence: "Escape"
        onActivated: root._endDrag(false)
    }

    /// The number of entries (chips, tabs, closing tabs) laid out.
    function entryCount() {
        return entryModel.count
    }

    /// The key of laid-out entry `row`: `group:<id>`, `tab:<id>` or `closing:<id>`.
    function entryKeyAt(row) {
        return entryModel.get(row).key
    }

    /// The item drag positions are measured in.
    function contentItemForDrag() {
        return content
    }

    // --------------------------------------------------------------- actions

    function _tapped(tab) {
        const active = tab.id === activeTab
        // A second click on the active tab names it.
        if (active && _lastTap === tab.id && tab.renamable !== false && renamable) {
            _lastTap = null
            tapTimeout.stop()
            renameTab(tab.id)
            return
        }
        _lastTap = active ? tab.id : null
        if (active)
            tapTimeout.restart()
        activated(tab.id)
    }

    function _finishTabRename(id, name) {
        if (_renamingTab !== id)
            return
        _renamingTab = null
        _relayout()
        if (name !== null)
            renamed(id, name)
    }

    function _finishGroupRename(id, name) {
        if (_renamingGroup !== id)
            return
        _renamingGroup = null
        _relayout()
        if (name !== null)
            groupRenamed(id, name)
    }

    /// Moves `tab` one place for assistive technology.
    function _step(tab, delta) {
        const order = _order(tabs)
        const index = order.findIndex(entry => entry.id === tab.id)
        const target = index + delta
        if (index < 0 || target < 0 || target >= order.length)
            return
        const rest = order.slice()
        rest.splice(index, 1)
        const before = target > 0 ? rest[target - 1].group : null
        const after = target < rest.length ? rest[target].group : null
        const own = tab.group ?? null
        const group = before !== null && before === after ? before
            : own !== null && (before === own || after === own) ? own : null
        moveRequested(tab.id, target, group)
    }

    // ----------------------------------------------------------------- view

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: root._total
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width && !root.dragging
        clip: true

        Item {
            id: content
            width: root._total
            height: flick.height

            // Rules under each open group.
            Repeater {
                model: entryModel
                delegate: Rectangle {
                    id: rule
                    required property string kind
                    required property real targetX
                    required property real spanW
                    required property var groupId
                    required property bool lifted
                    readonly property var group: root._groupsById[groupId]
                    visible: kind === "chip" && group !== undefined && !group.collapsed && spanW > 0 && !lifted
                    x: targetX
                    width: spanW
                    height: Metrics.tabRuleHeight
                    y: parent.height - Metrics.tabGroupRuleInset - height
                    radius: height / 2
                    color: group !== undefined ? group.color : "transparent"
                    Behavior on x { enabled: root._animate; NumberAnimation { duration: Motion.layout; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard } }
                    Behavior on width { enabled: root._animate; NumberAnimation { duration: Motion.layout; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard } }
                }
            }

            // The active pill glides to the active tab.
            Item {
                id: indicator
                property real targetX: 0
                property real targetW: 0
                property int duration: 0
                property bool following: false
                property bool shown: false
                visible: shown
                x: targetX
                width: targetW
                height: Metrics.tabPillHeight
                anchors.verticalCenter: parent.verticalCenter
                Behavior on x { enabled: !indicator.following && indicator.duration > 0; NumberAnimation { duration: indicator.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard } }
                Behavior on width { enabled: !indicator.following && indicator.duration > 0; NumberAnimation { duration: indicator.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard } }
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
                model: entryModel
                delegate: Item {
                    id: slot
                    required property int index
                    required property string key
                    required property string kind
                    required property var tabId
                    required property var groupId
                    required property real targetX
                    required property real targetW
                    required property bool lifted
                    required property bool separated
                    required property bool hidden
                    required property int count
                    required property string ghostLabel
                    readonly property var tab: kind === "chip" ? null : (root._tabsById[tabId] ?? { id: tabId, label: ghostLabel })
                    readonly property var group: root._groupsById[groupId]
                    readonly property real fullWidth: kind === "chip" ? targetW : root.tabWidth

                    x: targetX
                    width: targetW
                    height: parent.height
                    z: lifted ? 10 : 1
                    visible: width > 0.5 && !hidden
                    clip: width < fullWidth - 0.5
                    opacity: kind === "ghost" ? Math.max(0, Math.min(1, width / Math.max(1, root.tabWidth))) : 1
                    Behavior on x { enabled: root._animate && !slot.lifted; NumberAnimation { duration: Motion.layout; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard } }
                    Behavior on width { enabled: root._animate && !slot.lifted; NumberAnimation { duration: Motion.layout; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard } }

                    // The separator after a resting tab.
                    Rectangle {
                        visible: slot.kind === "tab"
                        x: slot.width + (root.gap - width) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: Metrics.hairline
                        height: Metrics.tabSeparatorHeight
                        color: Theme.colors.lineStrong
                        opacity: slot.separated ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.exit } }
                    }

                    TabStripPill {
                        visible: slot.kind !== "chip"
                        enabled: slot.kind !== "ghost" && !slot.hidden
                        width: slot.fullWidth
                        height: parent.height
                        strip: root
                        tab: slot.tab
                        lifted: slot.lifted
                        ghost: slot.kind === "ghost"
                        entryKey: slot.key
                        entryX: slot.x
                    }
                    TabStripChip {
                        visible: slot.kind === "chip"
                        width: slot.fullWidth
                        height: parent.height
                        strip: root
                        group: slot.group ?? null
                        count: slot.count
                        lifted: slot.lifted
                        entryKey: slot.key
                        entryX: slot.x
                    }
                }
            }
        }
    }
}
