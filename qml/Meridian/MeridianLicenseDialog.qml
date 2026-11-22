pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls.Basic as C

// The licenses of the app and what it bundles (Flutter:
// MeridianLicenseDialog): the application header and a filterable package
// list on `ground` at the left, the selected package's license text at the
// right. Narrow windows page between the list and the text.
//
// `packages` is an array of { name, licenses: [text, …] }.
T.Dialog {
    id: control

    property var packages: []
    property string applicationName
    property string applicationVersion
    property url applicationIcon
    property string closeLabel: "Close"
    property string backLabel: "Back"
    property string filterPlaceholder: "Filter"
    property string noMatchesLabel: "No matching packages"
    /// `%1 licenses`; `%1` is the count.
    property string countLabel: "%1 licenses"
    property string selected: packages.length > 0 ? packages[0].name : ""
    property string query: ""
    property bool showingPackage: false

    readonly property real inset: Theme.touch ? Theme.space.s8 : Theme.space.s7
    readonly property bool paged: Theme.touch || width < Metrics.licenseDialogPagedBreakpoint
    readonly property var visiblePackages: query.trim().length === 0 ? packages
        : packages.filter(p => p.name.toLowerCase().includes(query.trim().toLowerCase()))
    readonly property var selectedPackage: packages.find(p => p.name === selected) ?? null

    parent: T.Overlay.overlay
    modal: true
    focus: true
    closePolicy: T.Popup.CloseOnEscape
    anchors.centerIn: parent
    width: Math.min(Metrics.licenseDialogWidth, (parent ? parent.width : Metrics.licenseDialogWidth) - 2 * Theme.space.s6)
    height: Math.min(Metrics.licenseDialogHeight, (parent ? parent.height : Metrics.licenseDialogHeight) * Metrics.dialogMaxHeightFraction)
    padding: 0

    T.Overlay.modal: Rectangle {
        color: Theme.colors.scrim
        Behavior on opacity { NumberAnimation { duration: Motion.fade(Motion.dialog) } }
    }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.fade(Motion.dialog) }
            NumberAnimation { property: "scale"; from: Motion.dialogEnterScale; to: 1; duration: Motion.dialog; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.enter }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.fade(Motion.exit) }
    }
    background: MeridianSurface {}

    function select(name) {
        showingPackage = true
        if (name === selected)
            return
        selected = name
        licenseText.contentY = 0
    }
    onQueryChanged: {
        const visible = visiblePackages
        if (visible.length > 0 && !visible.some(p => p.name === selected))
            selected = visible[0].name
    }

    contentItem: Item {
        Accessible.role: Accessible.Dialog
        Accessible.name: control.title

        Item {
            id: titleRow
            width: parent.width
            height: Theme.space.s5 + closeButton.height + Theme.space.s4
            MeridianIconButton {
                id: back
                visible: control.paged && control.showingPackage
                x: Theme.space.s5
                y: Theme.space.s5
                iconName: "arrow-left"
                text: control.backLabel
                surfaceColor: Theme.colors.raised
                onClicked: control.showingPackage = false
            }
            MeridianText {
                x: back.visible ? back.x + back.width + Theme.space.s3 : control.inset
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
        MeridianHairline { id: rule; y: titleRow.height; width: parent.width }

        Rectangle {
            id: list
            visible: !control.paged || !control.showingPackage
            y: rule.y + 1
            width: control.paged ? parent.width : Metrics.licenseDialogPackageListWidth
            height: parent.height - y
            color: control.paged ? Theme.colors.raised : Theme.colors.ground

            Row {
                id: header
                visible: control.applicationName.length > 0
                x: Theme.space.s4
                y: Theme.space.s5
                width: parent.width - 2 * Theme.space.s4
                spacing: Theme.space.s4
                Image {
                    visible: control.applicationIcon.toString().length > 0
                    source: control.applicationIcon
                    width: 40
                    height: 40
                    sourceSize: Qt.size(80, 80)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    MeridianText { role: MeridianText.BodyStrong; text: control.applicationName }
                    MeridianText {
                        visible: control.applicationVersion.length > 0
                        role: MeridianText.Caption
                        color: Theme.colors.inkMuted
                        text: control.applicationVersion
                    }
                }
            }
            MeridianTextField {
                id: filter
                x: Theme.space.s3
                y: (header.visible ? header.y + header.height + Theme.space.s4 : 0) + Theme.space.s3
                width: parent.width - 2 * Theme.space.s3
                variant: MeridianTextField.Search
                placeholderText: control.filterPlaceholder
                onTextChanged: control.query = text
            }
            ListView {
                id: packageList
                MeridianWheelScroll { flickable: packageList }
                y: filter.y + filter.height + Theme.space.s2
                width: parent.width
                height: parent.height - y
                clip: true
                leftMargin: Theme.space.s3
                rightMargin: Theme.space.s3
                topMargin: Theme.space.s3
                bottomMargin: Theme.space.s3
                boundsBehavior: Flickable.StopAtBounds
                model: control.visiblePackages
                C.ScrollBar.vertical: MeridianScrollBar {}
                keyNavigationEnabled: true
                currentIndex: control.visiblePackages.findIndex(p => p.name === control.selected)
                Keys.onDownPressed: if (currentIndex + 1 < count) control.select(control.visiblePackages[currentIndex + 1].name)
                Keys.onUpPressed: if (currentIndex > 0) control.select(control.visiblePackages[currentIndex - 1].name)
                delegate: MeridianNavRow {
                    required property var modelData
                    width: ListView.view.width - Theme.space.s3 * 2
                    text: modelData.name
                    count: modelData.licenses.length
                    current: modelData.name === control.selected
                    sidebarFocused: packageList.activeFocus
                    onClicked: control.select(modelData.name)
                }
                MeridianEmptyState {
                    anchors.centerIn: parent
                    visible: packageList.count === 0
                    compact: true
                    iconName: "search"
                    title: control.noMatchesLabel
                }
            }
            MeridianHairline { visible: !control.paged; vertical: true; anchors.right: parent.right; height: parent.height }
        }

        Flickable {
            id: licenseText
            MeridianWheelScroll { flickable: licenseText }
            visible: !control.paged || control.showingPackage
            x: control.paged ? 0 : list.width
            y: rule.y + 1
            width: parent.width - x
            height: parent.height - y
            contentHeight: textColumn.height + 2 * control.inset
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: MeridianScrollBar { visibility: MeridianScrollBar.Always }
            Column {
                id: textColumn
                x: control.inset
                y: control.inset
                width: Math.min(Metrics.licenseTextMaxWidth, licenseText.width - 2 * control.inset)
                MeridianText {
                    width: parent.width
                    role: MeridianText.Title
                    text: control.selectedPackage ? control.selectedPackage.name : ""
                }
                Item { width: 1; height: Theme.space.s2 }
                MeridianText {
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: control.countLabel.arg(control.selectedPackage ? control.selectedPackage.licenses.length : 0)
                }
                Item { width: 1; height: Theme.space.s6 }
                Repeater {
                    model: control.selectedPackage ? control.selectedPackage.licenses : []
                    delegate: Column {
                        id: entry
                        required property string modelData
                        required property int index
                        width: textColumn.width
                        Item {
                            visible: entry.index > 0
                            width: parent.width
                            height: visible ? 2 * Theme.space.s6 + 1 : 0
                            MeridianHairline { anchors.verticalCenter: parent.verticalCenter; width: parent.width }
                        }
                        MeridianSelectableText {
                            width: parent.width
                            role: MeridianText.CodeSm
                            color: Theme.colors.inkMuted
                            text: entry.modelData
                        }
                    }
                }
            }
        }
    }
}
