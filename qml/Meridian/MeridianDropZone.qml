import QtQuick
import QtQuick.Shapes
import QtQuick.Templates as T

// Where files can be dropped (Flutter: MeridianDropZone). The app owns the
// drag transport (a DropArea) and sets `state`. A drop is never the only way
// in: with `browsable` the zone is a button that emits `browseRequested`.
T.AbstractButton {
    id: control

    enum DropState { Idle, Active, Invalid }

    property int dropState: MeridianDropZone.Idle
    property string message
    property string iconName: "upload"
    property bool browsable: true

    readonly property color edgeColor: dropState === MeridianDropZone.Active ? Theme.colors.accent
        : dropState === MeridianDropZone.Invalid ? Theme.colors.danger
        : hovered ? Theme.colors.inkMuted : Theme.colors.lineStrong
    readonly property color inkColor: dropState === MeridianDropZone.Active ? Theme.colors.accentInk
        : dropState === MeridianDropZone.Invalid ? Theme.colors.danger : Theme.colors.inkMuted

    signal browseRequested()

    hoverEnabled: browsable
    focusPolicy: browsable ? Qt.StrongFocus : Qt.NoFocus
    implicitHeight: Math.max(104, column.implicitHeight + 2 * Theme.space.s6)
    implicitWidth: 320
    Accessible.role: browsable ? Accessible.Button : Accessible.StaticText
    Accessible.name: message.length > 0 ? text + ", " + message : text
    onClicked: if (browsable) browseRequested()

    contentItem: Item {
        Column {
            id: column
            anchors.centerIn: parent
            width: parent.width
            spacing: Theme.space.s3
            MeridianIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: control.iconName
                extent: 24
                color: control.inkColor
            }
            MeridianText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                role: MeridianText.Label
                text: control.text
                color: control.dropState === MeridianDropZone.Idle ? Theme.colors.ink : control.inkColor
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            MeridianText {
                width: parent.width
                visible: control.message.length > 0
                horizontalAlignment: Text.AlignHCenter
                role: MeridianText.Caption
                text: control.message
                color: control.inkColor
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
        }
    }

    background: Item {
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.lg
            color: control.dropState === MeridianDropZone.Active ? Theme.colors.accentSoft
                 : control.dropState === MeridianDropZone.Invalid ? Theme.colors.dangerBg
                 : Theme.clear(Theme.colors.accentSoft)
            Behavior on color { ColorAnimation { duration: Motion.select } }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                id: edge
                fillColor: "transparent"
                strokeColor: control.edgeColor
                strokeWidth: 1
                strokeStyle: ShapePath.DashLine
                dashPattern: [4, 3]
                // The dashes march while a drag is over the zone (MM-77).
                NumberAnimation on dashOffset {
                    from: 7; to: 0
                    duration: Motion.march
                    loops: Animation.Infinite
                    running: control.dropState === MeridianDropZone.Active && !Motion.reduced
                }
                PathRectangle {
                    x: 0.5; y: 0.5
                    width: control.width - 1
                    height: control.height - 1
                    radius: Theme.radius.lg
                }
            }
        }
        MeridianFocusRing {
            target: control
            shown: control.visualFocus
            targetRadius: Theme.radius.lg
        }
    }
}
