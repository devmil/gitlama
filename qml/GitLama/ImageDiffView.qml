pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// One image change shown inline in a diff pane (the Dart ImageDiffView and
// ImageDiffComparison): side by side, swipe or onion skin over a
// checkerboard, each side with its pixel size and file size. `source` is
// the bridge that decodes the change (loadImageDiff, imageDiffLoaded);
// `row` the image row ({key, oldPath, newPath}).
Item {
    id: view

    property var source: null
    property var row: null
    /// Calls the bridge's loader for `row`.
    property var load: null
    property var content: null
    property string mode: "sideBySide"
    property real amount: 0.5

    function reload() {
        content = null
        if (row && load)
            load(row)
    }
    onRowChanged: reload()
    Component.onCompleted: reload()

    function details(image) {
        const dimensions = L10n.tn("diffImageDimensions", { width: image.width, height: image.height })
        return image.bytes ? L10n.tn("diffImageDetails", { dimensions: dimensions, size: Labels.byteSize(image.bytes) }) : dimensions
    }
    function sideText(label, image) {
        return image ? L10n.tn("diffImageSideDetails", { side: label, details: details(image) }) : label
    }

    Connections {
        target: view.source
        function onImageDiffLoaded(key, image) {
            if (view.row && key === view.row.key)
                view.content = image
        }
    }

    // Loading, or a failure that leaves nothing to compare.
    MeridianProgressBar {
        visible: view.content === null
        width: parent.width
    }
    MeridianEmptyState {
        visible: view.content === null || view.content.failed === true || !!view.content.decodeFailure
        anchors.fill: parent
        compact: true
        iconName: view.content === null ? "" : "circle-alert"
        title: view.content === null ? L10n.t("diffImagePreparing")
            : view.content.failed === true ? L10n.t("diffImageLoadFailed") : L10n.t("diffImageDecodeFailed")
        message: view.content !== null && !!view.content.decodeFailure ? L10n.t(view.content.decodeFailure) : ""
    }

    Item {
        id: comparison
        visible: view.content !== null && view.content.failed !== true && !view.content.decodeFailure
        anchors.fill: parent

        Flow {
            id: controls
            x: Theme.space.s3
            y: Theme.space.s3
            width: parent.width - 2 * Theme.space.s3
            spacing: Theme.space.s4
            MeridianSegmented {
                label: L10n.t("diffImageComparison")
                controlSize: MeridianButton.Small
                segments: [{ value: "sideBySide", label: L10n.t("diffImageSideBySide") },
                           { value: "swipe", label: L10n.t("diffImageSwipe") },
                           { value: "onionSkin", label: L10n.t("diffImageOnionSkin") }]
                value: view.mode
                onActivated: value => view.mode = value
            }
            // Stacked sides share one area, so their sizes are listed here.
            Repeater {
                model: view.mode === "sideBySide" || !view.content ? [] : [[L10n.t("diffOldImage"), view.content.old], [L10n.t("diffNewImage"), view.content.new]]
                delegate: MeridianText {
                    required property var modelData
                    visible: !!modelData[1]
                    height: Theme.size.controlSmall
                    verticalAlignment: Text.AlignVCenter
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: modelData[1] ? view.sideText(modelData[0], modelData[1]) : ""
                }
            }
        }
        Row {
            id: amountRow
            visible: view.mode !== "sideBySide"
            x: Theme.space.s3
            y: controls.y + controls.height + Theme.space.s2
            width: parent.width - 2 * Theme.space.s3
            height: visible ? slider.implicitHeight : 0
            spacing: Theme.space.s3
            MeridianText {
                id: amountLabel
                anchors.verticalCenter: parent.verticalCenter
                text: view.mode === "swipe" ? L10n.t("diffImageDivider") : L10n.t("diffImageBlend")
            }
            MeridianSlider {
                id: slider
                objectName: "image-diff-amount"
                width: parent.width - amountLabel.width - parent.spacing
                label: amountLabel.text
                value: view.amount
                onMoved: view.amount = value
            }
        }

        Item {
            id: stage
            y: (amountRow.visible ? amountRow.y + amountRow.height : controls.y + controls.height) + Theme.space.s2
            width: parent.width
            height: parent.height - y

            // Side by side.
            Row {
                visible: view.mode === "sideBySide"
                anchors.fill: parent
                ImageSide {
                    width: (parent.width - Metrics.hairline) / 2
                    height: parent.height
                    label: L10n.t("diffOldImage")
                    image: view.content ? view.content.old : null
                }
                Rectangle { width: Metrics.hairline; height: parent.height; color: Theme.colors.line }
                ImageSide {
                    width: (parent.width - Metrics.hairline) / 2
                    height: parent.height
                    label: L10n.t("diffNewImage")
                    image: view.content ? view.content.new : null
                }
            }
            // Swipe: the new image over the old one up to the divider;
            // onion skin: the new image blended over the old one.
            Item {
                visible: view.mode !== "sideBySide"
                anchors.fill: parent
                ImageSide {
                    anchors.fill: parent
                    stacked: true
                    label: L10n.t("diffOldImage")
                    image: view.content ? view.content.old : null
                }
                Item {
                    width: view.mode === "swipe" ? parent.width * view.amount : parent.width
                    height: parent.height
                    clip: true
                    opacity: view.mode === "onionSkin" ? view.amount : 1
                    ImageSide {
                        width: stage.width
                        height: stage.height
                        stacked: true
                        label: L10n.t("diffNewImage")
                        image: view.content ? view.content.new : null
                    }
                }
            }
        }
    }

    // One side: its caption, then the image over a checkerboard.
    component ImageSide: Item {
        id: side
        property string label
        property var image: null
        /// Drawn over the other side; the controls name both sides instead.
        property bool stacked: false

        Accessible.role: Accessible.Graphic
        Accessible.name: label

        MeridianText {
            id: caption
            x: Theme.space.s4
            y: Theme.space.s4
            width: parent.width - 2 * Theme.space.s4
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            elide: Text.ElideRight
            text: side.stacked ? "" : view.sideText(side.label, side.image)
        }
        Item {
            y: caption.y + caption.height + Theme.space.s4
            width: parent.width
            height: parent.height - y
            MeridianEmptyState {
                visible: side.image === null || side.image.failed === true
                anchors.fill: parent
                compact: true
                iconName: side.image === null ? "" : "circle-alert"
                title: side.image === null ? L10n.t("diffImageMissing") : L10n.t("diffImageDecodeFailed")
            }
            // A checkerboard shows through transparent pixels.
            Canvas {
                visible: side.image !== null && side.image.failed !== true
                anchors.fill: parent
                onPaint: {
                    const context = getContext("2d")
                    context.fillStyle = String(Theme.colors.pane)
                    context.fillRect(0, 0, width, height)
                    context.fillStyle = String(Theme.colors.paneAlt)
                    for (let y = 0; y < height; y += 8)
                        for (let x = (Math.floor(y / 8) % 2 === 0 ? 0 : 8); x < width; x += 16)
                            context.fillRect(x, y, 8, 8)
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    source: side.image && side.image.url ? side.image.url : ""
                }
            }
        }
    }
}
