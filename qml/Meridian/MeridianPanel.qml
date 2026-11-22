pragma ComponentBehavior: Bound
import QtQuick

// A floating panel over the page (Flutter: MeridianPanel): a `raised`
// card with `shadow-float` and `radius-xl`, a `body-strong` title row with
// optional actions and a close button, then the body. It grows from
// `transformOrigin` (the corner nearest the control that opened it) with
// the overlay entrance and leaves with the overlay exit (MM-40); set
// `shown` to false and wait for `hidden` before removing it. Escape closes.
FocusScope {
    id: panel

    property string title
    property string closeLabel: "Close"
    property bool closable: true
    /// Plays the entrance while true and the exit when set to false.
    property bool shown: true
    /// Small actions before the close button.
    property alias actions: actionRow.data
    /// The body (content items).
    default property alias content: body.data
    /// Body padding; the header already spaces the body from the top.
    property real leftPadding: Theme.space.s6
    property real rightPadding: Theme.space.s6
    property real bottomPadding: Theme.space.s6
    readonly property real headerHeight: Math.max(Metrics.floatingPanelHeaderHeight, Theme.size.minTarget)
    readonly property real bodyWidth: width - leftPadding - rightPadding

    signal closeRequested()
    /// The exit finished.
    signal hidden()

    implicitWidth: Metrics.panelWidth
    implicitHeight: headerHeight + body.childrenRect.height + bottomPadding
    transformOrigin: Item.Top
    Keys.onEscapePressed: event => { if (closable) { closeRequested(); event.accepted = true } }
    Accessible.role: Accessible.Pane
    Accessible.name: title

    // The entrance: fade in, rise and scale up; the exit: fade and scale.
    property real _progress: 0
    property bool _leaving: false
    opacity: _progress
    scale: Motion.reduced ? 1 : Motion.overlayEnterScale + (1 - Motion.overlayEnterScale) * _progress
    transform: Translate { y: panel._leaving || Motion.reduced ? 0 : -Motion.riseOverlay * (1 - panel._progress) }

    NumberAnimation {
        id: enter
        target: panel
        property: "_progress"
        to: 1
        duration: Motion.reduced ? Motion.fade(Motion.overlay) : Motion.overlay
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.enter
    }
    NumberAnimation {
        id: exit
        target: panel
        property: "_progress"
        to: 0
        duration: Motion.reduced ? Motion.fade(Motion.exit) : Motion.exit
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.exitCurve
        onFinished: if (!panel.shown) panel.hidden()
    }
    function _play() {
        if (shown) {
            exit.stop()
            _leaving = false
            enter.restart()
        } else {
            enter.stop()
            _leaving = true
            exit.restart()
        }
    }
    onShownChanged: _play()
    Component.onCompleted: _play()

    MeridianShadow {
        anchors.fill: card
        layers: Theme.shadows.float
        radius: card.radius
    }
    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.radius.xl
        color: Theme.colors.raised
        clip: true

        Item {
            id: header
            width: parent.width
            height: panel.headerHeight
            MeridianText {
                x: Theme.space.s6
                anchors.verticalCenter: parent.verticalCenter
                width: end.x - x - Theme.space.s3
                role: MeridianText.BodyStrong
                text: panel.title
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Row {
                id: end
                x: parent.width - width - Theme.space.s3
                anchors.verticalCenter: parent.verticalCenter
                Row { id: actionRow; anchors.verticalCenter: parent.verticalCenter }
                MeridianIconButton {
                    visible: panel.closable
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "x"
                    text: panel.closeLabel
                    surfaceColor: Theme.colors.raised
                    onClicked: panel.closeRequested()
                }
            }
        }
        Item {
            id: body
            x: panel.leftPadding
            y: header.height
            width: panel.bodyWidth
            height: parent.height - y - panel.bottomPadding
        }
    }
}
