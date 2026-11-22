import QtQuick
import QtQuick.Templates as T

// A command menu (Flutter: MeridianMenu) of MeridianMenuItems,
// MeridianMenuSeparators and nested MeridianMenus (submenus, one level deep
// where you can). Arrow keys, Home and End move the highlight; typing the
// first letters of a label jumps to it; Enter runs it; Escape closes.
//
// `nativeMenu: true` asks Qt for the platform's own menu (NSMenu on macOS; on
// Linux and Windows where the platform theme provides one) with the same
// items, check state, shortcuts and submenus. Menus with custom content stay
// Meridian menus.
T.Menu {
    id: control

    property bool nativeMenu: false
    property string _typed: ""
    /// False until the pointer moves after opening: a menu that opens under
    /// a resting pointer does not highlight the row it happens to cover.
    property bool pointerArmed: false
    property point _pointerOrigin: Qt.point(NaN, NaN)
    onAboutToShow: {
        pointerArmed = false
        _pointerOrigin = Qt.point(NaN, NaN)
    }
    /// Rows report pointer positions; the first one is where the menu
    /// opened, and a move of 2px or more arms hover highlighting.
    function notePointer(position) {
        if (pointerArmed)
            return
        if (isNaN(_pointerOrigin.x))
            _pointerOrigin = position
        else if (Math.abs(position.x - _pointerOrigin.x) + Math.abs(position.y - _pointerOrigin.y) >= 2)
            pointerArmed = true
    }

    popupType: nativeMenu ? T.Popup.Native : T.Popup.Item
    implicitWidth: Math.min(Metrics.menuMaxWidth, Math.max(Metrics.menuMinWidth, contentWidth + leftPadding + rightPadding))
    implicitHeight: Math.min(Metrics.menuMaxHeight, contentHeight + topPadding + bottomPadding)
    padding: Theme.space.s2
    margins: Theme.space.s2
    overlap: 1
    focus: true
    transformOrigin: T.Popup.Top
    cascade: true


    delegate: MeridianMenuItem {}

    function typeAhead(text) {
        const timer = typeReset
        _typed += text.toLowerCase()
        timer.restart()
        for (let i = 0; i < count; ++i) {
            // Separators and custom blocks are not buttons; type-ahead skips them.
            const item = itemAt(i) as T.AbstractButton
            if (item && item.enabled && item.visible && item.text.toLowerCase().startsWith(_typed)) {
                currentIndex = i
                return true
            }
        }
        return false
    }

    Timer {
        id: typeReset
        interval: 800
        onTriggered: control._typed = ""
    }

    contentItem: ListView {
        id: menuList
        MeridianWheelScroll { flickable: menuList }
        focus: true
        Accessible.role: Accessible.PopupMenu
        implicitHeight: contentHeight
        implicitWidth: {
            let widest = 0
            for (let i = 0; i < count; ++i) {
                const item = control.itemAt(i)
                if (item)
                    widest = Math.max(widest, item.implicitWidth)
            }
            return widest
        }
        model: control.contentModel
        interactive: Window.window ? contentHeight + control.topPadding + control.bottomPadding > control.height : false
        clip: true
        currentIndex: control.currentIndex
        keyNavigationEnabled: true
        boundsBehavior: Flickable.StopAtBounds
        Keys.onPressed: event => {
            if (event.text.length === 1 && event.text.trim().length === 1
                    && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                if (control.typeAhead(event.text))
                    event.accepted = true
            }
        }
    }

    background: MeridianSurface {
        implicitWidth: Metrics.menuMinWidth
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.fade(Motion.overlay) }
            NumberAnimation {
                property: "scale"; from: Motion.overlayEnterScale; to: 1; duration: Motion.overlay
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.enter
            }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.fade(Motion.exit) }
    }
}
