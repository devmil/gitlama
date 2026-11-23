pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import Meridian

// The active repository's details (the Dart RepositoryDetailsPanel): the
// Compass grows into a panel with a health header (tile, name, verdict,
// location, kind and group), the path, branch, upstream and changes, paused
// Git operations, what runs now, the Git version and Open in the file
// manager; it shrinks back into the Compass when it closes. It closes when
// no repository is left to describe.
T.Popup {
    id: popup

    /// The Compass, which the panel grows from.
    property Item anchorItem: null
    readonly property var details: Store.workspace ? (Store.workspace.details ?? null) : null
    property var shown: null
    onDetailsChanged: {
        if (details)
            shown = details
        else if (opened)
            close()
    }

    /// 0 is the Compass, 1 the open panel.
    property real progress: 0
    readonly property rect source: {
        if (!anchorItem || !parent)
            return Qt.rect((parent ? parent.width : 0) / 2 - 100, (Theme.size.toolbar - GitLamaLayout.compassHeight) / 2, 200, GitLamaLayout.compassHeight)
        const at = anchorItem.mapToItem(parent, 0, 0)
        return Qt.rect(at.x, at.y, anchorItem.width, anchorItem.height)
    }

    parent: T.Overlay.overlay
    modal: true
    focus: true
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutside
    padding: 0
    readonly property real margin: Theme.space.s6
    width: Math.min(parent ? parent.width - 2 * margin : GitLamaLayout.repositoryDetailsWidth,
                    Math.max(GitLamaLayout.repositoryDetailsWidth, source.width))
    x: Math.max(margin, Math.min((parent ? parent.width : width) - margin - width, source.x + source.width / 2 - width / 2))
    y: source.y
    height: Math.min(content.implicitHeight, (parent ? parent.height : 800) - y - margin)

    T.Overlay.modal: Rectangle {
        color: Theme.colors.scrim
        Behavior on opacity { NumberAnimation { duration: Motion.fade(Motion.dialog) } }
    }

    enter: Transition {
        NumberAnimation {
            property: "progress"; from: 0; to: 1
            duration: Motion.reduced ? 0 : GitLamaLayout.paletteMorph
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snappy.curve
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "progress"; from: 1; to: 0
            duration: Motion.reduced ? 0 : Motion.dialog
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.exitCurve
        }
    }

    // The surface morphs from the Compass's pill to the panel's rectangle.
    background: Item {
        readonly property rect start: Qt.rect(popup.source.x - popup.x, popup.source.y - popup.y, popup.source.width, popup.source.height)
        readonly property real p: popup.progress
        MeridianShadow {
            anchors.fill: surface
            layers: popup.progress > 0.5 ? Theme.shadows.float : Theme.shadows.pane
            radius: surface.radius
        }
        Rectangle {
            id: surface
            x: parent.start.x * (1 - parent.p)
            y: parent.start.y * (1 - parent.p)
            width: parent.start.width + (popup.width - parent.start.width) * parent.p
            height: parent.start.height + (popup.height - parent.start.height) * parent.p
            radius: parent.start.height / 2 * (1 - parent.p) + Theme.radius.lg * parent.p
            color: Theme.blend(Theme.colors.pane, Theme.colors.raised, parent.p)
        }
    }

    readonly property var d: shown ?? ({})
    readonly property bool hasWorktree: d.bare !== true
    readonly property string health: (d.conflicts ?? 0) > 0 ? "conflicted"
        : (d.inProgress ?? []).length > 0 ? "paused"
        : !!d.operation ? "busy"
        : !d.gitVersion ? "unknown"
        : (d.changed ?? 0) > 0 && hasWorktree ? "changed" : "clean"
    readonly property color wash: ({ conflicted: Theme.colors.dangerBg, paused: Theme.colors.warningBg, changed: Theme.colors.warningBg,
                                     busy: Theme.colors.accentSoft, clean: Theme.colors.successBg, unknown: Theme.colors.paneAlt })[health]
    readonly property color ink: ({ conflicted: Theme.colors.danger, paused: Theme.colors.warning, changed: Theme.colors.warning,
                                    busy: Theme.colors.accentInk, clean: Theme.colors.success, unknown: Theme.colors.inkMuted })[health]
    readonly property string headline: ({ conflicted: L10n.t("repositoryDetailsHealthConflicted"),
        paused: L10n.t("repositoryDetailsHealthPaused"), busy: L10n.t("repositoryDetailsHealthBusy"),
        changed: L10n.t("repositoryDetailsHealthChanged"),
        clean: hasWorktree ? L10n.t("repositoryDetailsHealthClean") : L10n.t("repositoryDetailsBare"), unknown: "" })[health]

    contentItem: Flickable {
        clip: true
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        opacity: Math.max(0, Math.min(1, (popup.progress - 0.3) / 0.7))
        Accessible.role: Accessible.Dialog
        Accessible.name: L10n.t("repositoryDetailsTitle")

        Column {
            id: content
            objectName: "repository-details"
            width: popup.width

            // The header on its health's wash.
            Item {
                width: parent.width
                height: header.implicitHeight + Theme.space.s6 + Theme.space.s7
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius.lg
                    gradient: Gradient {
                        GradientStop { position: 0; color: popup.wash }
                        GradientStop { position: 0.4; color: popup.wash }
                        GradientStop { position: 1; color: Theme.clear(popup.wash) }
                    }
                }
                Row {
                    id: header
                    x: Theme.space.s6
                    y: Theme.space.s6
                    width: parent.width - 2 * Theme.space.s6
                    spacing: Theme.space.s5
                    Item {
                        width: GitLamaLayout.repositoryDetailsTileSize + Theme.space.s3
                        height: width
                        MeridianShadow {
                            anchors.fill: tile
                            layers: Theme.shadows.pane
                            radius: tile.radius
                        }
                        Rectangle {
                            id: tile
                            width: GitLamaLayout.repositoryDetailsTileSize
                            height: width
                            radius: Theme.radius.lg
                            border.color: popup.ink
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0; color: Theme.colors.raised }
                                GradientStop { position: 1; color: popup.wash }
                            }
                            MeridianIcon {
                                anchors.centerIn: parent
                                name: !popup.d.hasKind ? "folder-closed" : popup.d.bare ? "archive" : popup.d.linkedWorktree ? "folder-symlink" : "folder-closed"
                                extent: GitLamaLayout.repositoryDetailsTileIconSize
                                color: popup.ink
                            }
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: dot.implicitWidth + 2 * Theme.space.s2
                            height: width
                            radius: width / 2
                            color: Theme.colors.raised
                            MeridianStatusDot {
                                id: dot
                                anchors.centerIn: parent
                                tone: ({ conflicted: MeridianStatusDot.Danger, paused: MeridianStatusDot.Warning, changed: MeridianStatusDot.Warning,
                                         busy: MeridianStatusDot.Accent, clean: MeridianStatusDot.Success, unknown: MeridianStatusDot.Neutral })[popup.health]
                                halo: true
                                live: popup.health === "busy"
                                semanticLabel: popup.headline
                            }
                        }
                    }
                    Column {
                        width: parent.width - GitLamaLayout.repositoryDetailsTileSize - Theme.space.s3 - parent.spacing
                        MeridianText {
                            width: parent.width
                            role: MeridianText.Title
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: popup.d.name ?? ""
                        }
                        MeridianText {
                            objectName: "repository-details-headline"
                            visible: popup.headline.length > 0
                            role: MeridianText.Label
                            color: popup.ink
                            text: popup.headline
                        }
                        Item { width: 1; height: Theme.space.s4 }
                        Flow {
                            width: parent.width
                            spacing: Theme.space.s3
                            MeridianChip {
                                objectName: "repository-details-location"
                                text: popup.d.remote ? L10n.t("remoteHostUnknown") : L10n.t("repositoryDetailsThisComputer")
                                iconName: popup.d.remote ? "server" : "monitor"
                                maxWidth: GitLamaLayout.repositoryDetailsWidth
                                Accessible.description: L10n.t("repositoryDetailsLocation")
                            }
                            MeridianChip {
                                visible: popup.d.hasKind === true && popup.d.bare !== true
                                text: popup.d.linkedWorktree ? L10n.t("repositoryDetailsLinkedWorktree") : L10n.t("repositoryDetailsWorktree")
                                maxWidth: GitLamaLayout.repositoryDetailsWidth
                                Accessible.description: L10n.t("repositoryDetailsKind")
                            }
                            MeridianChip {
                                visible: !!popup.d.group
                                text: popup.d.group ?? ""
                                iconName: "layers"
                                tone: MeridianChip.Accent
                                maxWidth: GitLamaLayout.repositoryDetailsWidth
                                Accessible.description: L10n.t("repositoryDetailsGroup")
                            }
                        }
                    }
                }
            }

            Column {
                x: Theme.space.s6
                width: parent.width - 2 * Theme.space.s6
                spacing: Theme.space.s5

                // The path in a code well, with its copy action.
                Rectangle {
                    visible: !!popup.d.path
                    width: parent.width
                    height: pathRow.implicitHeight + 2 * Theme.space.s3
                    radius: Theme.radius.md
                    color: Theme.colors.paneAlt
                    border.color: Theme.colors.line
                    Row {
                        id: pathRow
                        x: Theme.space.s5
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.space.s5 - Theme.space.s3
                        spacing: Theme.space.s4
                        MeridianIcon { anchors.verticalCenter: parent.verticalCenter; name: "folder"; iconSize: MeridianIcon.Small; color: Theme.colors.inkMuted }
                        MeridianSelectableText {
                            objectName: "repository-details-path"
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.size.iconSmall - copyPath.width - 2 * parent.spacing
                            role: MeridianText.CodeSm
                            wrapMode: Text.WrapAnywhere
                            text: popup.d.path ?? ""
                            Accessible.name: L10n.t("repositoryDetailsPath")
                        }
                        MeridianIconButton {
                            id: copyPath
                            objectName: "repository-details-copy-path"
                            anchors.verticalCenter: parent.verticalCenter
                            text: L10n.t("repositoryCopyPath")
                            iconName: "copy"
                            controlSize: MeridianButton.Small
                            onClicked: Store.actions.copyText(popup.d.path ?? "", L10n.t("repositoryPathCopied"))
                        }
                    }
                }

                // Branch, upstream and changes side by side, stacked when narrow.
                Flow {
                    id: stats
                    width: parent.width
                    spacing: Theme.space.s4
                    readonly property var tiles: {
                        const d = popup.d
                        const result = []
                        const shortId = d.headObjectId ? d.headObjectId.substring(0, 8) : null
                        if (d.branch || shortId)
                            result.push({ label: L10n.t("repositoryDetailsBranch"), icon: "git-branch", tint: Theme.colors.accentInk,
                                          value: d.branch ? d.branch : L10n.tn("compassDetachedAt", { hash: shortId }),
                                          caption: d.unborn ? L10n.t("repositoryDetailsUnborn") : "", code: d.branch && shortId ? shortId : "" })
                        if (popup.hasWorktree && d.branch)
                            result.push({ label: L10n.t("repositoryDetailsUpstream"), icon: d.upstream ? "git-compare-arrows" : "unlink",
                                          tint: d.upstream ? Theme.colors.accentInk : Theme.colors.inkFaint,
                                          value: d.upstream ? d.upstream : L10n.t("repositoryDetailsNoUpstream"), muted: !d.upstream,
                                          sync: !!d.upstream })
                        if (popup.hasWorktree && d.gitVersion)
                            result.push({ label: L10n.t("repositoryDetailsChanges"),
                                          icon: d.conflicts > 0 ? "triangle-alert" : d.changed > 0 ? "file-diff" : "circle-check",
                                          tint: d.conflicts > 0 ? Theme.colors.danger : d.changed > 0 ? Theme.colors.warning : Theme.colors.success,
                                          value: d.changed > 0 ? L10n.tn("compassChangedFiles", { count: d.changed }) : L10n.t("repositoryDetailsClean"),
                                          danger: d.conflicts > 0 ? L10n.tn("compassConflicts", { count: d.conflicts }) : "" })
                        return result
                    }
                    readonly property bool side: tiles.length > 0
                        && (width - spacing * (tiles.length - 1)) / tiles.length >= GitLamaLayout.repositoryDetailsStatMinWidth
                    Repeater {
                        model: stats.tiles
                        delegate: Rectangle {
                            id: statTile
                            required property var modelData
                            width: stats.side ? (stats.width - stats.spacing * (stats.tiles.length - 1)) / stats.tiles.length : stats.width
                            height: Math.max(GitLamaLayout.repositoryDetailsStatMinHeight, tileColumn.implicitHeight + 2 * Theme.space.s5)
                            radius: Theme.radius.lg
                            color: Theme.colors.pane
                            border.color: Theme.colors.line
                            Column {
                                id: tileColumn
                                x: Theme.space.s5
                                y: Theme.space.s5
                                width: parent.width - 2 * Theme.space.s5
                                spacing: Theme.space.s3
                                Row {
                                    spacing: Theme.space.s3
                                    MeridianIcon { name: statTile.modelData.icon; iconSize: MeridianIcon.Small; color: statTile.modelData.tint }
                                    MeridianText { role: MeridianText.Caption; color: Theme.colors.inkMuted; text: statTile.modelData.label }
                                }
                                MeridianText {
                                    width: parent.width
                                    role: statTile.modelData.muted ? MeridianText.Body : MeridianText.Heading
                                    color: statTile.modelData.muted ? Theme.colors.inkMuted : Theme.colors.ink
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    text: statTile.modelData.value
                                }
                                MeridianText {
                                    visible: (statTile.modelData.caption ?? "").length > 0
                                    role: MeridianText.Caption
                                    color: Theme.colors.inkMuted
                                    text: statTile.modelData.caption ?? ""
                                }
                                MeridianText {
                                    visible: (statTile.modelData.code ?? "").length > 0
                                    role: MeridianText.CodeSm
                                    color: Theme.colors.inkMuted
                                    text: statTile.modelData.code ?? ""
                                }
                                MeridianText {
                                    visible: (statTile.modelData.danger ?? "").length > 0
                                    role: MeridianText.Caption
                                    color: Theme.colors.danger
                                    text: statTile.modelData.danger ?? ""
                                }
                                SyncBadge {
                                    visible: statTile.modelData.sync === true
                                    ahead: popup.d.ahead ?? 0
                                    behind: popup.d.behind ?? 0
                                    showZero: true
                                }
                            }
                        }
                    }
                }

                MeridianBanner {
                    visible: (popup.d.inProgress ?? []).length > 0
                    width: parent.width
                    tone: MeridianBanner.Warning
                    iconName: "git-merge"
                    title: L10n.t("repositoryDetailsInProgress")
                    message: (popup.d.inProgress ?? []).map(key => L10n.t(key)).join(" · ")
                }

                // What runs in the repository now.
                Column {
                    width: parent.width
                    spacing: Theme.space.s3
                    Accessible.role: Accessible.Grouping
                    Accessible.name: L10n.t("repositoryDetailsRunning")
                    Row {
                        width: parent.width
                        spacing: Theme.space.s4
                        MeridianStatusDot {
                            anchors.verticalCenter: parent.verticalCenter
                            tone: popup.d.operation ? MeridianStatusDot.Accent : MeridianStatusDot.Neutral
                            live: !!popup.d.operation
                        }
                        MeridianText {
                            id: runningLabel
                            anchors.verticalCenter: parent.verticalCenter
                            role: MeridianText.Caption
                            color: Theme.colors.inkMuted
                            text: L10n.t("repositoryDetailsRunning")
                        }
                        MeridianText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - runningLabel.width - Theme.space.s6
                            color: popup.d.operation ? Theme.colors.ink : Theme.colors.inkMuted
                            elide: Text.ElideRight
                            text: {
                                const operation = popup.d.operation
                                if (!operation)
                                    return L10n.t("repositoryDetailsIdle")
                                const action = L10n.t("operation" + operation.action.charAt(0).toUpperCase() + operation.action.slice(1))
                                const detail = Labels.operationProgress(operation.progress)
                                return detail.length > 0 ? L10n.tn("operationRunningDetail", { operation: action, detail: detail }) : action + "…"
                            }
                        }
                    }
                    MeridianProgressBar {
                        visible: !!popup.d.operation
                        width: parent.width
                        persistent: true
                        value: popup.d.operation && popup.d.operation.progress ? popup.d.operation.progress.fraction : -1
                    }
                }

                MeridianHairline { width: parent.width }

                Item {
                    width: parent.width
                    height: Math.max(gitRow.implicitHeight, openFolder.implicitHeight)
                    Row {
                        id: gitRow
                        visible: !!popup.d.gitVersion
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.s3
                        MeridianIcon { anchors.verticalCenter: parent.verticalCenter; name: "terminal"; iconSize: MeridianIcon.Small; color: Theme.colors.inkFaint }
                        MeridianText { anchors.verticalCenter: parent.verticalCenter; role: MeridianText.Caption; color: Theme.colors.inkMuted; text: L10n.t("repositoryDetailsGit") }
                        MeridianText { anchors.verticalCenter: parent.verticalCenter; role: MeridianText.CodeSm; color: Theme.colors.inkMuted; text: popup.d.gitVersion ?? "" }
                    }
                    MeridianButton {
                        id: openFolder
                        objectName: "repository-details-open-folder"
                        visible: !!popup.d.path && !popup.d.remote
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: L10n.tn("openInFileBrowser", { browser: Labels.fileBrowserName() })
                        iconName: "folder-open"
                        variant: MeridianButton.Quiet
                        onClicked: {
                            const path = popup.d.path
                            popup.close()
                            Store.actions.openFolder(path)
                        }
                    }
                }
                Item { width: 1; height: Theme.space.s1 }
            }
        }
    }
}
