import QtQuick

// Initials on a categorical colour from a stable hash of the name, or an
// image that fades in over them once loaded (Flutter: MeridianAvatar).
Item {
    id: root

    enum Size { Small, Medium, Large, XLarge }

    property string name
    property int avatarSize: MeridianAvatar.Small
    /// An image URL; the initials stay until it loads.
    property url source
    property string colorKey
    property string monogram
    /// The decoded size of `source` per logical pixel.
    property real sourceScale: Screen.devicePixelRatio

    readonly property real dimension: [Metrics.avatarSmall, Metrics.avatarMedium,
        Metrics.avatarLarge, Metrics.avatarXLarge][avatarSize] ?? Metrics.avatarSmall
    readonly property real fontPixels: [Metrics.avatarFontSmall, Metrics.avatarFontMedium,
        Metrics.avatarFontLarge, Metrics.avatarFontXLarge][avatarSize] ?? Metrics.avatarFontSmall

    function initials(value) {
        const parts = value.trim().split(/[\s._@-]+/).filter(p => p.length > 0)
        if (parts.length === 0)
            return "?"
        if (parts.length === 1)
            return Array.from(parts[0])[0].toUpperCase()
        return String(Array.from(parts[0])[0] + Array.from(parts[1])[0]).toUpperCase()
    }
    function colorIndex(key) {
        const order = [0, 1, 5, 4, 6, 3, 2, 7]
        let hash = 0
        const lower = key.toLowerCase()
        for (let i = 0; i < lower.length; ++i)
            hash = (Math.imul(hash, 31) + lower.charCodeAt(i)) & 0x7fffffff
        return order[hash % order.length]
    }

    implicitWidth: dimension
    implicitHeight: dimension
    Accessible.ignored: true

    Rectangle {
        id: disc
        anchors.fill: parent
        radius: width / 2
        visible: picture.status !== Image.Ready || picture.opacity < 1
        color: {
            const c = Theme.colors
            const series = [c.series1, c.series2, c.series3, c.series4, c.series5, c.series6, c.series7, c.series8]
            return series[root.colorIndex(root.colorKey.length > 0 ? root.colorKey : root.name)]
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.space.s1
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 4
            font.family: Theme.type.sansFamily.length > 0 ? Theme.type.sansFamily : Application.font.family
            font.pixelSize: root.fontPixels
            font.weight: Font.Bold
            color: Theme.colors.pane
            text: {
                const given = root.monogram.trim()
                return given.length > 0 ? Array.from(given).slice(0, 2).join("").toUpperCase() : root.initials(root.name.length > 0 ? root.name : "?")
            }
        }
    }

    Image {
        id: picture
        anchors.fill: parent
        visible: root.source.toString().length > 0
        source: root.source
        asynchronous: true
        cache: true
        smooth: true
        mipmap: false
        fillMode: Image.PreserveAspectFit
        readonly property real decoded: Math.min(96, Math.max(16, Math.ceil(root.dimension * root.sourceScale)))
        sourceSize: Qt.size(decoded, decoded)
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity {
            enabled: picture.status === Image.Ready
            NumberAnimation { duration: Motion.quick; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
        }
    }
}
