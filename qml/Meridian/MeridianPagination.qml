pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T

// Pages of a paged source (Flutter: MeridianPagination). Up to seven pages
// show in full; beyond that the first, the last and the current page's
// neighbours with … for the gaps. Nothing shows for a single page. Labels are
// the app's localized strings; `pageLabel` takes %1 for the number.
//
// A non-empty `jumpLabel` adds Flutter's direct page field after the pages:
// "<jumpLabel> [field] <pageCountLabel>". `pageCountLabel` and
// `jumpAccessibleName` take %1 for the page count. Enter selects the typed
// page, clamped to 1…pageCount; anything else restores the current page.
Item {
    id: root

    property int page: 1
    property int pageCount: 1
    property string previousLabel
    property string nextLabel
    property string pageLabel: "%1"
    property string jumpLabel
    property string jumpAccessibleName
    property string pageCountLabel

    function submitJump(text) {
        const typed = parseInt(text, 10)
        if (isNaN(typed)) {
            jumpField.text = String(page)
            return
        }
        const target = Math.max(1, Math.min(pageCount, typed))
        jumpField.text = String(target)
        if (target !== page)
            pageSelected(target)
    }

    signal pageSelected(int page)

    readonly property var entries: {
        const n = pageCount, p = page, full = Metrics.paginationFullRange
        if (n <= full)
            return Array.from({ length: n }, (_, i) => i + 1)
        const out = [1]
        const start = Math.max(2, Math.min(p - 1, n - 4))
        const end = Math.min(n - 1, Math.max(p + 1, 5))
        if (start > 2) out.push(0)
        for (let i = start; i <= end; ++i) out.push(i)
        if (end < n - 1) out.push(0)
        out.push(n)
        return out
    }

    visible: pageCount > 1
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.size.controlSmall

    Accessible.role: Accessible.PageTabList

    Row {
        id: row
        spacing: Theme.space.s2

        MeridianIconButton {
            objectName: "paginationPrevious"
            iconName: "chevron-left"
            text: root.previousLabel
            controlSize: MeridianButton.Small
            enabled: root.enabled && root.page > 1
            onClicked: root.pageSelected(root.page - 1)
        }
        Repeater {
            model: root.entries
            delegate: T.AbstractButton {
                id: pageButton
                required property int modelData
                readonly property bool gap: modelData === 0
                readonly property bool current: modelData === root.page
                objectName: "paginationPage" + modelData
                enabled: !gap && root.enabled
                hoverEnabled: true
                focusPolicy: gap ? Qt.NoFocus : Qt.StrongFocus
                implicitWidth: Math.max(Theme.size.controlSmall, Math.ceil(number.implicitWidth + 2 * Theme.space.s3))
                implicitHeight: Theme.size.controlSmall
                text: gap ? "…" : String(modelData)
                Accessible.name: gap ? "" : root.pageLabel.arg(modelData)
                Accessible.selected: current
                onClicked: if (!current) root.pageSelected(modelData)
                contentItem: MeridianText {
                    id: number
                    horizontalAlignment: Text.AlignHCenter
                    role: MeridianText.Label
                    text: pageButton.text
                    color: pageButton.current ? Theme.colors.accentInk : pageButton.hovered ? Theme.colors.ink : Theme.colors.inkMuted
                    tabular: true
                }
                background: Rectangle {
                    radius: Theme.radius.md
                    color: pageButton.current ? Theme.colors.accentSoft
                         : pageButton.hovered && !pageButton.gap ? Theme.colors.paneHover
                         : Theme.clear(Theme.colors.paneHover)
                    Behavior on color { ColorAnimation { duration: Motion.select } }
                    MeridianFocusRing {
                        target: pageButton
                        shown: pageButton.visualFocus
                        targetRadius: Theme.radius.md
                    }
                }
            }
        }
        MeridianText {
            visible: root.jumpLabel.length > 0
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: root.jumpLabel
        }
        MeridianTextField {
            id: jumpField
            objectName: "paginationJump"
            visible: root.jumpLabel.length > 0
            width: Metrics.paginationFieldWidth
            controlSize: MeridianButton.Small
            enabled: root.enabled
            horizontalAlignment: TextInput.AlignHCenter
            maximumLength: Metrics.paginationFieldMaxDigits
            inputMethodHints: Qt.ImhDigitsOnly
            validator: RegularExpressionValidator { regularExpression: /[0-9]*/ }
            text: String(root.page)
            Accessible.name: root.jumpAccessibleName.length > 0 ? root.jumpAccessibleName.arg(root.pageCount) : ""
            onAccepted: root.submitJump(text)
            onActiveFocusChanged: if (!activeFocus) text = String(root.page)
            Connections {
                target: root
                function onPageChanged() { jumpField.text = String(root.page) }
            }
        }
        MeridianText {
            visible: root.jumpLabel.length > 0 && root.pageCountLabel.length > 0
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            tabular: true
            text: root.pageCountLabel.length > 0 ? root.pageCountLabel.arg(root.pageCount) : ""
        }
        MeridianIconButton {
            objectName: "paginationNext"
            iconName: "chevron-right"
            text: root.nextLabel
            controlSize: MeridianButton.Small
            enabled: root.enabled && root.page < root.pageCount
            onClicked: root.pageSelected(root.page + 1)
        }
    }
}
