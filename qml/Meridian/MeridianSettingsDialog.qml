pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T

// Preferences in one dialog (Flutter: MeridianSettingsDialog): the title
// with a ✕, a page list on `ground` at the left and the current page on
// `raised` at the right with its `title`, caption description and content.
// Narrow windows and touch density pick the page from a select instead.
//
// `pages` is an array of { label, icon, description }; put one Item per page
// in `pageItems` (in the same order). Arrow keys move through the list.
T.Dialog {
    id: control

    property var pages: []
    property int currentPage: 0
    property string closeLabel: "Close"
    default property list<Item> pageItems
    property alias footerContent: footerSlot.data

    readonly property real inset: Theme.touch ? Theme.space.s8 : Theme.space.s7

    parent: T.Overlay.overlay
    modal: true
    focus: true
    closePolicy: T.Popup.CloseOnEscape
    anchors.centerIn: parent
    width: Math.min(Metrics.settingsDialogWidth, (parent ? parent.width : Metrics.settingsDialogWidth) - 2 * Theme.space.s6)
    height: Math.min(Metrics.settingsDialogHeight, (parent ? parent.height : Metrics.settingsDialogHeight) * Metrics.dialogMaxHeightFraction)
    padding: 0

    readonly property bool paged: Theme.touch || width < Metrics.settingsDialogPagedBreakpoint

    T.Overlay.modal: Rectangle {
        color: Theme.colors.scrim
        Behavior on opacity { NumberAnimation { duration: Motion.fade(Motion.dialog) } }
    }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.fade(Motion.dialog) }
            NumberAnimation {
                property: "scale"; from: Motion.dialogEnterScale; to: 1; duration: Motion.dialog
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.enter
            }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.fade(Motion.exit) }
    }

    background: MeridianSurface {}

    contentItem: Item {
        Accessible.role: Accessible.Dialog
        Accessible.name: control.title

        Item {
            id: titleRow
            width: parent.width
            height: Theme.space.s5 + Math.max(titleText.height, closeButton.height) + Theme.space.s4
            MeridianText {
                id: titleText
                x: control.inset
                y: Theme.space.s5 + (closeButton.height - height) / 2
                width: closeButton.x - x - Theme.space.s4
                role: MeridianText.Title
                text: control.title
            }
            MeridianIconButton {
                id: closeButton
                x: parent.width - Theme.space.s5 - width
                y: Theme.space.s5
                iconName: "x"
                text: control.closeLabel
                surfaceColor: Theme.colors.raised
                onClicked: control.close()
            }
        }
        MeridianHairline {
            id: topRule
            y: titleRow.height
            width: parent.width
        }

        MeridianSelect {
            id: pagePicker
            visible: control.paged
            x: control.inset
            y: topRule.y + 1 + Theme.space.s5
            fixedWidth: parent.width - 2 * control.inset
            label: control.title
            values: control.pages.map((_, index) => index)
            value: control.currentPage
            valueLabel: index => control.pages[index] ? control.pages[index].label : ""
            onActivated: index => control.currentPage = index
        }

        Rectangle {
            id: pageList
            visible: !control.paged
            y: topRule.y + 1
            width: Metrics.settingsDialogPageListWidth
            height: footerRule.visible ? footerRule.y - y : parent.height - y
            color: Theme.colors.ground
            ListView {
                id: list
                MeridianWheelScroll { flickable: list }
                anchors.fill: parent
                anchors.margins: Theme.space.s3
                model: control.pages
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                focus: true
                keyNavigationEnabled: true
                currentIndex: control.currentPage
                onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex !== control.currentPage) control.currentPage = currentIndex
                delegate: MeridianNavRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    text: modelData.label
                    iconName: modelData.icon ?? ""
                    current: index === control.currentPage
                    sidebarFocused: list.activeFocus
                    onClicked: control.currentPage = index
                }
            }
            MeridianHairline {
                vertical: true
                anchors.right: parent.right
                height: parent.height
            }
        }

        Flickable {
            id: body
            MeridianWheelScroll { flickable: body }
            readonly property real topEdge: control.paged ? pagePicker.y + pagePicker.height : topRule.y + 1
            x: control.paged ? 0 : pageList.width
            y: topEdge
            width: parent.width - x
            height: (footerRule.visible ? footerRule.y : parent.height) - topEdge
            contentHeight: page.height + 2 * control.inset
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: page
                x: control.inset
                y: control.inset
                width: body.width - 2 * control.inset
                readonly property var info: control.pages[control.currentPage] ?? ({})
                MeridianText {
                    width: parent.width
                    role: MeridianText.Title
                    text: page.info.label ?? ""
                    Accessible.role: Accessible.Heading
                }
                Item { width: 1; height: Theme.space.s2; visible: (page.info.description ?? "").length > 0 }
                MeridianText {
                    width: parent.width
                    visible: (page.info.description ?? "").length > 0
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: page.info.description ?? ""
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
                Item { width: 1; height: Theme.space.s7 }
                Item {
                    id: pageHost
                    width: parent.width
                    height: childrenRect.height
                    data: control.pageItems
                    Component.onCompleted: control._layoutPages()
                }
            }
            onContentHeightChanged: returnToTop()
            function returnToTop() { contentY = 0 }
        }

        MeridianHairline {
            id: footerRule
            visible: footerSlot.children.length > 0
            y: parent.height - footerBox.height - 1
            width: parent.width
        }
        Item {
            id: footerBox
            visible: footerRule.visible
            y: parent.height - height
            width: parent.width
            height: visible ? footerSlot.childrenRect.height + 2 * Theme.space.s4 : 0
            Item {
                id: footerSlot
                x: control.inset
                y: Theme.space.s4
                width: parent.width - 2 * control.inset
            }
        }
    }

    onCurrentPageChanged: {
        _layoutPages()
        body.returnToTop()
    }
    onPageItemsChanged: _layoutPages()

    function _layoutPages() {
        for (let i = 0; i < pageItems.length; ++i) {
            const item = pageItems[i]
            item.visible = i === currentPage
            item.width = Qt.binding(() => page.width)
        }
    }
}
