pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The detail inspector (the Dart InspectorView): a location bar with Back,
// Forward, breadcrumbs and the lens choice; the commit's summary; its
// changed files beside the diff. Narrow, the files sit above the diff.
Rectangle {
    id: inspector

    readonly property var paneState: Store.inspector ? (Store.inspector.state ?? ({})) : ({})
    readonly property var location: paneState.location ?? null
    readonly property var summary: paneState.summary ?? null
    readonly property var files: paneState.files ?? []
    property bool filesHidden: false
    /// The width of the files column (the Dart commitFileListWidth).
    property real filesWidth: 280

    color: Theme.colors.pane

    function failureText(code) {
        switch (code) {
        case "missingObject": return L10n.t("inspectorMissingObject")
        case "closed": case "retiredSession": case "unknownSession": return L10n.t("inspectorRepositoryClosed")
        default: return L10n.t("inspectorLoadFailed")
        }
    }
    readonly property bool historyLens: location !== null && location !== undefined && location.path !== null && location.lens === "history"
    function lensReasonText(reason) {
        switch (reason) {
        case "notChanged": return L10n.t("inspectorNotChanged")
        case "deleted": return L10n.t("inspectorDeletedHere")
        case "needsText": return L10n.t("inspectorBlameNeedsText")
        case "submodule": return L10n.t("inspectorSubmoduleNoContents")
        case "directory": return L10n.t("inspectorFolderOnlyHistory")
        default: return ""
        }
    }
    function fileStatus(kind) {
        return ({ modified: "M", added: "A", deleted: "D", renamed: "R", copied: "C", modeChanged: "T",
                  typeChanged: "T", binary: "B", image: "I", submodule: "S", conflict: "U", untracked: "?" })[kind] ?? ""
    }

    /// Opens the menu of changed file `file` ({path, oldPath, kind, mode})
    /// at `x`, `y` of `item` (the Dart InspectorFileActions).
    function showFileMenu(file, item, x, y) {
        if (!location)
            return
        const host = Store.inspector.fileHost()
        const canOpen = host.canOpenWorkingCopy === true
        const remoteReason = L10n.t("remoteCommandUnsupported")
        const capabilities = ["showDiff", "showContents", "blame", "fileHistory", "folderHistory", "copyPath", "restoreFromCommit"]
        if (host.hasDiffTool === true)
            capabilities.push("externalDiff")
        if (canOpen)
            capabilities.push("openExternally", "revealInFileBrowser")
        fileMenu.file = file
        fileMenu.target = location
        fileMenu.showFor({
            source: location.kind === "comparison" ? "comparedFile" : "committedFile",
            path: file.path,
            change: file.kind,
            mode: file.mode ?? null,
            exists: canOpen && Store.inspector.existsInWorkingTree(file.path),
        }, null, {
            capabilities: capabilities,
            reasons: host.remote === true
                ? { openExternally: remoteReason, revealInFileBrowser: remoteReason, restoreFromCommit: remoteReason } : ({}),
            busy: false,
        }, item, x, y)
    }

    FileActionMenu {
        id: fileMenu
        property var file: null
        property var target: null
        run: (action, selection) => {
            const path = file.path
            const commit = target.commit
            switch (action) {
            case "showDiff": Store.inspector.openFileLens(path, "diff", false, commit); return
            case "showContents": Store.inspector.openFileLens(path, "contents", false, commit); return
            case "blame": Store.inspector.openFileLens(path, "blame", false, commit); return
            case "fileHistory": Store.inspector.openFileLens(path, "history", false, commit); return
            case "externalDiff":
                Store.inspector.externalDiff(target.base ?? "", commit, file.oldPath.length > 0 ? file.oldPath : path, path); return
            case "openExternally": Store.workflows.openTool("editor", path); return
            case "revealInFileBrowser": Store.workflows.openTool("fileManager", path); return
            case "copyPath": Store.actions.copyText(path, L10n.t("filePathCopied")); return
            case "restoreFromCommit": Store.inspector.restoreFile(path, commit); return
            }
        }
    }
    Component.onCompleted: Store.inspectorView = inspector
    /// Development screenshots: builds file `index`'s menu and runs `action`.
    function runFileAction(index, action) {
        showFileMenu(files[index], inspector, 10, 10)
        fileMenu.close()
        console.log("inspector file menu:", JSON.stringify(fileMenu.shownItems.map(item => item.separator ? "-" : item.title + (item.enabled === false ? "(off)" : ""))))
        if (action.length > 0)
            fileMenu.run(action, false)
    }

    // Back and Forward mouse buttons move through the inspector's history.
    TapHandler {
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onTapped: (point, button) => button === Qt.BackButton ? Store.inspector.back() : Store.inspector.forward()
    }

    MeridianEmptyState {
        visible: inspector.location === null
        anchors.fill: parent
        compact: true
        iconName: "inspect"
        title: L10n.t("workspaceNoSelection")
    }

    Item {
        visible: inspector.location !== null
        anchors.fill: parent

        // The location bar.
        Item {
            id: bar
            objectName: "inspector-location-bar"
            width: parent.width
            height: Theme.size.islandHeader + Theme.space.s3
            readonly property bool compact: width < 760

            Row {
                id: navigation
                x: Theme.space.s3
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                MeridianIconButton {
                    objectName: "inspector-back"
                    text: L10n.t("historyNavigateBack")
                    iconName: "back"
                    enabled: inspector.paneState.canBack === true
                    onClicked: Store.inspector.back()
                }
                MeridianIconButton {
                    objectName: "inspector-forward"
                    text: L10n.t("historyNavigateForward")
                    iconName: "forward"
                    enabled: inspector.paneState.canForward === true
                    onClicked: Store.inspector.forward()
                }
            }
            MeridianBreadcrumbs {
                id: crumbs
                objectName: "inspector-breadcrumbs"
                x: navigation.x + navigation.width + Theme.space.s2
                width: lenses.x - x - Theme.space.s3
                anchors.verticalCenter: parent.verticalCenter
                semanticLabel: L10n.t("inspectorLocation")
                crumbs: {
                    const location = inspector.location
                    if (!location)
                        return []
                    const subject = inspector.summary ? inspector.summary.subject : ""
                    const list = [location.kind === "comparison"
                        ? { label: location.base.substring(0, 10) + " → " + location.commit.substring(0, 10),
                            mono: true, icon: "git-commit-horizontal", enabled: location.path !== null }
                        : { label: subject.length > 0 ? subject : location.commit.substring(0, 10),
                            prefix: location.commit.substring(0, 10), icon: "git-commit-horizontal",
                            enabled: location.path !== null,
                            semanticLabel: location.commit.substring(0, 10) + " " + subject }]
                    if (location.path) {
                        const parts = location.path.split("/").filter(part => part.length > 0)
                        for (let i = 0; i < parts.length; ++i)
                            list.push({ label: parts[i], emphasis: i === parts.length - 1, enabled: false })
                    }
                    return list
                }
                onActivated: index => {
                    if (index === 0)
                        Store.inspector.selectFile("")
                }
            }
            MeridianSegmented {
                id: lenses
                objectName: "inspector-lens"
                visible: inspector.location !== null && inspector.location.path !== null
                anchors.right: parent.right
                anchors.rightMargin: Theme.space.s3
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? implicitWidth : 0
                label: L10n.t("inspectorLenses")
                controlSize: MeridianButton.Small
                value: inspector.location ? inspector.location.lens : "diff"
                segments: {
                    const availability = inspector.paneState.lensAvailability ?? []
                    const reasonOf = lens => {
                        const entry = availability.find(item => item.lens === lens)
                        return entry ? entry.reason : null
                    }
                    const names = { diff: L10n.t("inspectorLensDiff"), contents: L10n.t("inspectorLensContents"),
                                    blame: L10n.t("historyBlame"), history: L10n.t("inspectorLensHistory") }
                    const icons = { diff: "file-diff", contents: "file-text", blame: "blame", history: "history" }
                    return ["diff", "contents", "blame", "history"].map(lens => {
                        const reason = reasonOf(lens)
                        return { value: lens, icon: icons[lens], label: bar.compact ? "" : names[lens],
                                 enabled: !reason, tooltip: reason ? inspector.lensReasonText(reason) : names[lens] }
                    })
                }
                onActivated: lens => Store.inspector.selectLens(lens)
            }
            MeridianHairline { anchors.bottom: parent.bottom; width: parent.width }
        }

        Item {
            id: body
            anchors.top: bar.bottom
            anchors.bottom: parent.bottom
            width: parent.width

            MeridianEmptyState {
                visible: inspector.paneState.phase === "loading"
                anchors.fill: parent
                compact: true
                progress: true
                title: inspector.location ? L10n.tn("inspectorLoading", { commit: inspector.location.commit.substring(0, 10) }) : ""
            }
            MeridianBanner {
                visible: inspector.paneState.phase === "failed"
                anchors.top: parent.top
                anchors.margins: Theme.space.s5
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2 * Theme.space.s5
                tone: MeridianBanner.Error
                message: inspector.failureText(inspector.paneState.failure)
                MeridianButton {
                    objectName: "inspector-retry"
                    text: L10n.t("retry")
                    controlSize: MeridianButton.Small
                    onClicked: Store.inspector.retry()
                }
            }

            Item {
                id: ready
                visible: inspector.paneState.phase === "ready"
                anchors.fill: parent

                CommitSummaryCard {
                    id: card
                    visible: inspector.summary !== null && inspector.location !== null && (inspector.location.path === null || inspector.location.lens === "diff")
                    width: parent.width
                    height: visible ? Math.min(implicitHeight, parent.height * GitLamaLayout.commitSummaryMaxHeightFraction) : 0
                    summary: inspector.summary ?? ({})
                    onParentSelected: commit => Store.inspector.showCommit(commit)
                }
                MeridianHairline { visible: card.visible; anchors.top: card.bottom; width: parent.width }

                Item {
                    id: split
                    anchors.top: card.bottom
                    anchors.bottom: parent.bottom
                    width: parent.width
                    readonly property bool narrow: width < GitLamaLayout.inspectorWideWidth
                    readonly property real listWidth: Math.max(GitLamaLayout.inspectorSidebarMin,
                        Math.min(width - GitLamaLayout.inspectorContentMin, inspector.filesWidth))

                    // The changed files.
                    Item {
                        id: filesPane
                        objectName: "commit-changed-files"
                        visible: !inspector.filesHidden
                        width: split.narrow ? split.width : split.listWidth
                        height: split.narrow ? Math.min(Math.max(Theme.size.row * 5, split.height * 0.4), split.height * 0.6) : split.height

                        Item {
                            id: filesHeader
                            visible: !inspector.historyLens
                            width: parent.width
                            height: Theme.size.islandHeader
                            MeridianText {
                                x: Theme.space.s5
                                anchors.verticalCenter: parent.verticalCenter
                                role: MeridianText.BodyStrong
                                text: L10n.tn("historyFilesCount", { count: inspector.files.length })
                            }
                            MeridianIconButton {
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.space.s3
                                anchors.verticalCenter: parent.verticalCenter
                                text: L10n.t("inspectorHideFiles")
                                iconName: "panel-left"
                                controlSize: MeridianButton.Small
                                onClicked: inspector.filesHidden = true
                            }
                        }
                        // The history lens lists the path's commits here instead.
                        InspectorHistoryList {
                            visible: inspector.historyLens
                            anchors.fill: parent
                            paneState: inspector.paneState
                        }
                        ListView {
                            id: fileList
                            objectName: "commit-files-list"
                            visible: !inspector.historyLens
                            anchors.top: filesHeader.bottom
                            anchors.bottom: parent.bottom
                            width: parent.width
                            leftMargin: Theme.space.s2
                            rightMargin: Theme.space.s2
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: inspector.files
                            MeridianWheelScroll { flickable: fileList }
                            C.ScrollBar.vertical: MeridianScrollBar {}
                            header: MeridianListRow {
                                objectName: "commit-files-all-changes"
                                width: fileList.width - fileList.leftMargin - fileList.rightMargin
                                text: L10n.t("historyAllChanges")
                                iconName: "file-diff"
                                selected: inspector.location !== null && inspector.location.path === null
                                enabled: inspector.paneState.allChangesTooLarge !== true
                                meta: inspector.paneState.allChangesTooLarge === true ? L10n.t("historyAllChangesTooLarge") : ""
                                onClicked: Store.inspector.selectFile("")
                            }
                            delegate: FileRow {
                                required property var modelData
                                width: fileList.width - fileList.leftMargin - fileList.rightMargin
                                path: modelData.path
                                status: inspector.fileStatus(modelData.kind)
                                selected: inspector.location !== null && inspector.location.path === modelData.path
                                onClicked: Store.inspector.selectFile(modelData.path)
                                onContextMenuRequested: (x, y) => inspector.showFileMenu(modelData, this, x, y)
                            }
                        }
                    }
                    MeridianResizeHandle {
                        visible: !split.narrow && !inspector.filesHidden
                        x: filesPane.width
                        height: split.height
                        thickness: Theme.space.s3
                        semanticLabel: L10n.t("workspaceResizeDetail")
                        keyboardStep: GitLamaLayout.paneResizeStep
                        activeFocusOnTab: false
                        onDragged: delta => inspector.filesWidth = Math.max(GitLamaLayout.inspectorSidebarMin,
                            Math.min(split.width - GitLamaLayout.inspectorContentMin, inspector.filesWidth + delta))
                    }
                    Rectangle {
                        visible: !inspector.filesHidden
                        x: split.narrow ? 0 : filesPane.width + Theme.space.s3 / 2
                        y: split.narrow ? filesPane.height : 0
                        width: split.narrow ? split.width : Metrics.hairline
                        height: split.narrow ? Metrics.hairline : split.height
                        color: Theme.colors.line
                    }

                    // The lens.
                    Item {
                        id: lensPane
                        x: inspector.filesHidden || split.narrow ? 0 : filesPane.width + Theme.space.s3
                        y: inspector.filesHidden || !split.narrow ? 0 : filesPane.height + Metrics.hairline
                        width: split.width - x
                        height: split.height - y

                        MeridianIconButton {
                            id: showFiles
                            objectName: "inspector-show-files"
                            visible: inspector.filesHidden
                            x: Theme.space.s3
                            y: Theme.space.s2
                            text: L10n.t("inspectorShowFiles")
                            iconName: "panel-left"
                            controlSize: MeridianButton.Small
                            onClicked: inspector.filesHidden = false
                        }
                        MeridianProgressBar {
                            id: progress
                            visible: inspector.paneState.contentLoading === true && inspector.location.lens !== "contents"
                            anchors.top: showFiles.visible ? showFiles.bottom : parent.top
                            width: parent.width
                        }
                        MeridianBanner {
                            visible: inspector.paneState.contentFailure !== null && inspector.paneState.contentFailure !== undefined
                            anchors.top: parent.top
                            anchors.margins: Theme.space.s5
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 2 * Theme.space.s5
                            tone: MeridianBanner.Error
                            message: inspector.failureText(inspector.paneState.contentFailure)
                            MeridianButton {
                                text: L10n.t("retry")
                                controlSize: MeridianButton.Small
                                onClicked: Store.inspector.retry()
                            }
                        }
                        // The history lens: the selected commit, then its change to the path.
                        Item {
                            id: historyHeader
                            visible: inspector.historyLens && inspector.paneState.historyEntry !== null && inspector.paneState.historyEntry !== undefined
                            anchors.top: progress.visible ? progress.bottom : showFiles.visible ? showFiles.bottom : parent.top
                            width: parent.width
                            height: visible ? historyColumn.implicitHeight + 2 * Theme.space.s4 : 0
                            readonly property var entry: inspector.paneState.historyEntry ?? null
                            Column {
                                id: historyColumn
                                x: Theme.space.s5
                                y: Theme.space.s4
                                width: parent.width - 2 * Theme.space.s5
                                spacing: Theme.space.s2
                                MeridianText {
                                    width: parent.width
                                    role: MeridianText.BodyStrong
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    text: historyHeader.entry ? historyHeader.entry.subject : ""
                                }
                                Row {
                                    spacing: Theme.space.s3
                                    AuthorAvatar {
                                        anchors.verticalCenter: parent.verticalCenter
                                        author: historyHeader.entry ? historyHeader.entry.author : ""
                                    }
                                    MeridianText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        role: MeridianText.Caption
                                        color: Theme.colors.inkMuted
                                        text: historyHeader.entry ? historyHeader.entry.author.split("<")[0].trim() + " · "
                                            + Labels.historyDate(historyHeader.entry.authorTime, Store.appearance.dateFormat ?? "relative")
                                            + " · " + Labels.shortObjectId(historyHeader.entry.commit) : ""
                                    }
                                }
                            }
                            MeridianHairline { anchors.bottom: parent.bottom; width: parent.width }
                        }
                        InspectorContents {
                            visible: inspector.location !== null && inspector.location.lens === "contents"
                            anchors.top: showFiles.visible ? showFiles.bottom : parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width
                            contents: inspector.paneState.contents ?? null
                            failure: inspector.paneState.contentFailure ?? ""
                        }
                        InspectorBlame {
                            visible: inspector.location !== null && inspector.location.lens === "blame" && inspector.paneState.hasBlame === true
                            anchors.top: showFiles.visible ? showFiles.bottom : parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width
                        }
                        DiffView {
                            visible: inspector.paneState.hasDiff === true && (inspector.location.lens === "diff" || inspector.historyLens)
                                && !inspector.paneState.contentFailure
                            anchors.top: historyHeader.visible ? historyHeader.bottom : progress.visible ? progress.bottom : showFiles.visible ? showFiles.bottom : parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width
                            model: Store.inspectorDiff
                            layout: inspector.paneState.options ? inspector.paneState.options.layout : "unified"
                        }
                        MeridianEmptyState {
                            visible: inspector.location !== null && inspector.location.lens === "blame" && inspector.paneState.hasBlame !== true
                                && !inspector.paneState.contentFailure
                            anchors.fill: parent
                            compact: true
                            progress: true
                            title: L10n.t("loading")
                        }
                    }
                }
            }
        }
    }
}
