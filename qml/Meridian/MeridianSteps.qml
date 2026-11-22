pragma ComponentBehavior: Bound
import QtQuick

// Where a multi-step task stands (Flutter: MeridianSteps): a numbered pill
// marker and label per step joined by `line-strong` connectors. Steps before
// `current` are done (a check on `success-bg`), `current` is filled with
// `accent` and its label is strong, later steps are outlined. When every
// label does not fit, only the current one shows (ellipsized). `current`
// equal to the step count marks every step done.
//
// `steps` is an array of labels.
Item {
    id: root

    property var steps: []
    property int current: 0
    /// Names the whole line for assistive technology ("Resolve conflicts").
    property string semanticLabel
    /// "Done", "Current" and "Upcoming" for assistive technology.
    property string doneLabel: "Done"
    property string currentLabel: "Current"
    property string upcomingLabel: "Upcoming"

    readonly property real markerExtent: Theme.touch ? Metrics.stepMarkerTouch : Metrics.stepMarker
    readonly property real connectorWidth: Metrics.stepConnectorLength + 2 * Theme.space.s3
    // Markers and connectors: what the line needs without any label.
    readonly property real fixedWidth: steps.length * markerExtent + Math.max(0, steps.length - 1) * connectorWidth
    readonly property real labelsWidth: {
        let width = 0
        for (let i = 0; i < labels.count; ++i)
            width += labels.itemAt(i) ? labels.itemAt(i).implicitWidth + Theme.space.s2 : 0
        return width
    }
    /// Every label fits; otherwise only the current one shows.
    readonly property bool allLabels: fixedWidth + labelsWidth <= width

    implicitWidth: fixedWidth + labelsWidth
    implicitHeight: Math.max(markerExtent, Theme.type.bodyLineHeight)

    Accessible.role: Accessible.List
    Accessible.name: semanticLabel

    function stateOf(index) {
        return index < current ? 0 : index === current ? 1 : 2
    }

    Row {
        id: line
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            id: markers
            model: root.steps.length
            delegate: Row {
                id: step
                required property int index
                readonly property int stepState: root.stateOf(index)
                readonly property real labelWidth: {
                    const label = labels.itemAt(index)
                    if (!label)
                        return 0
                    if (root.allLabels)
                        return label.implicitWidth + Theme.space.s2
                    if (index !== root.current)
                        return 0
                    return Math.max(0, root.width - root.fixedWidth)
                }
                Accessible.role: Accessible.ListItem
                Accessible.name: root.steps[index] + ", " + [root.doneLabel, root.currentLabel, root.upcomingLabel][stepState]
                    + ", " + (index + 1) + "/" + root.steps.length

                Rectangle {
                    id: marker
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(root.markerExtent, number.implicitWidth + 2 * Metrics.stepMarkerPaddingX)
                    height: root.markerExtent
                    radius: height / 2
                    color: step.stepState === 0 ? Theme.colors.successBg : step.stepState === 1 ? Theme.colors.accent : "transparent"
                    border.width: Metrics.hairline
                    border.color: step.stepState === 0 ? Theme.colors.successBg : step.stepState === 1 ? Theme.colors.accent : Theme.colors.lineStrong
                    Behavior on color { ColorAnimation { duration: Motion.select } }
                    MeridianIcon {
                        visible: step.stepState === 0
                        anchors.centerIn: parent
                        name: "check"
                        extent: Theme.touch ? Metrics.stepCheckIconTouch : Metrics.stepCheckIcon
                        color: Theme.colors.success
                    }
                    MeridianText {
                        id: number
                        visible: step.stepState !== 0
                        anchors.centerIn: parent
                        role: MeridianText.Label
                        fontPixelSize: Metrics.countFontSize
                        fontWeight: Font.DemiBold
                        tabular: true
                        text: String(step.index + 1)
                        color: step.stepState === 1 ? Theme.colors.inkOnAccent : Theme.colors.inkMuted
                    }
                }
                Item {
                    width: step.labelWidth > 0 ? step.labelWidth + Theme.space.s2 : 0
                    height: root.implicitHeight
                    clip: true
                    MeridianText {
                        x: Theme.space.s2
                        width: step.labelWidth
                        anchors.verticalCenter: parent.verticalCenter
                        role: step.stepState === 1 ? MeridianText.BodyStrong : MeridianText.Body
                        color: step.stepState === 1 ? Theme.colors.ink : Theme.colors.inkMuted
                        text: root.steps[step.index]
                    }
                }
                Item {
                    visible: step.index < root.steps.length - 1
                    width: root.connectorWidth
                    height: root.implicitHeight
                    Rectangle {
                        x: Theme.space.s3
                        anchors.verticalCenter: parent.verticalCenter
                        width: Metrics.stepConnectorLength
                        height: Metrics.hairline
                        color: Theme.colors.lineStrong
                    }
                }
            }
        }
    }
    // The labels' natural widths, measured off screen.
    Repeater {
        id: labels
        model: root.steps.length
        delegate: MeridianText {
            required property int index
            visible: false
            role: index === root.current ? MeridianText.BodyStrong : MeridianText.Body
            text: root.steps[index]
        }
    }
}
