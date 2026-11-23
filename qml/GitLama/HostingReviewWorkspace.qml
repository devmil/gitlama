pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// A pull request review over the whole window: the changed files, the selected file's provider
// patch with its commentable lines, and a rail (a drawer when narrow) with
// the review threads, the checks, the review action and text and the line
// comments. The text is kept as a draft; Preview review shows the exact
// request before it is submitted.
MeridianDialogSurface {
    id: workspace

    readonly property var review: Store.hosting ? Store.hosting.review : null
    readonly property bool busy: review !== null && review.busy === true
    readonly property bool compact: width < GitLamaLayout.reviewDrawerBreakpoint
    property bool commentsVisible: false
    property bool treeMode: false

    /// Opens the review of `pull` ({number, headSha}) of the bound repository.
    function show(pull) {
        const binding = Store.hosting.repository.binding
        if (!binding)
            return
        commentsVisible = false
        Store.hosting.reviewOpen(binding.connectionId, binding.providerRepository, pull.number, pull.headSha)
        open()
    }

    objectName: "hosting-review-workspace"
    fillWindow: true
    label: review ? L10n.tn("hostingReviewTitle", { number: review.number }) : ""
    onClosed: Store.hosting.reviewClose()

    // A submitted review ends the workspace.
    onReviewChanged: if (review !== null && review.completed === true) close()

    Timer {
        id: draftTimer
        interval: 250
        onTriggered: Store.hosting.reviewSaveDraft()
    }

    WorkflowHeader {
        id: header
        width: parent.width
        title: workspace.review ? L10n.tn("hostingReviewTitle", { number: workspace.review.number }) : ""
        status: workspace.review ? workspace.review.headSha : ""
        exitLabel: L10n.t("close")
        onExit: workspace.close()
        MeridianSpinner { visible: workspace.review !== null && workspace.review.loading === true }
        MeridianIconButton {
            visible: workspace.compact
            text: L10n.t("hostingReviewThreads")
            iconName: "message-square-text"
            enabled: workspace.review !== null && workspace.review.hasPage === true
            onClicked: workspace.commentsVisible = !workspace.commentsVisible
        }
    }

    Item {
        id: body
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: parent.width

        MeridianEmptyState {
            visible: workspace.review !== null && workspace.review.hasPage !== true && !workspace.review.failure
            anchors.fill: parent
            compact: true
            progress: true
            title: L10n.t("loading")
        }
        MeridianBanner {
            visible: workspace.review !== null && workspace.review.hasPage !== true && !!workspace.review.failure
            anchors.centerIn: parent
            width: Math.min(parent.width - 2 * Theme.space.s6, Metrics.dialogFormWidth)
            tone: MeridianBanner.Error
            message: L10n.t("hostingReviewLoadFailed")
        }

        Row {
            visible: workspace.review !== null && workspace.review.hasPage === true
            x: Theme.space.s3
            y: Theme.space.s3
            width: parent.width - 2 * Theme.space.s3
            height: parent.height - 2 * Theme.space.s3
            spacing: Theme.space.s3

            // The changed files.
            MeridianIsland {
                width: GitLamaLayout.conflictFileListWidth
                height: parent.height
                Item {
                    id: filesHeader
                    width: parent.width
                    height: Theme.size.islandHeader
                    MeridianText {
                        x: Theme.space.s5
                        anchors.verticalCenter: parent.verticalCenter
                        role: MeridianText.Label
                        text: L10n.tn("historyFilesCount", { count: workspace.review ? workspace.review.files.length : 0 })
                    }
                    MeridianSegmented {
                        objectName: "hosting-review-files-mode"
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.space.s3
                        anchors.verticalCenter: parent.verticalCenter
                        label: L10n.t("changesListView")
                        controlSize: MeridianButton.Small
                        segments: [{ value: "list", icon: "list-view", tooltip: L10n.t("changesListView") },
                                   { value: "tree", icon: "tree-view", tooltip: L10n.t("changesTreeView") }]
                        value: workspace.treeMode ? "tree" : "list"
                        onActivated: value => workspace.treeMode = value === "tree"
                    }
                }
                ListView {
                    id: files
                    objectName: "hosting-review-files"
                    anchors.top: filesHeader.bottom
                    anchors.bottom: parent.bottom
                    width: parent.width
                    leftMargin: Theme.space.s2
                    rightMargin: Theme.space.s2
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: !workspace.review ? [] : workspace.treeMode ? workspace.review.fileTree : workspace.review.files
                    MeridianWheelScroll { flickable: files }
                    C.ScrollBar.vertical: MeridianScrollBar {}
                    delegate: FileRow {
                        id: fileRow
                        required property var modelData
                        objectName: "hosting-review-file-" + (modelData.stableId ?? modelData.identity)
                        width: files.width - files.leftMargin - files.rightMargin
                        path: workspace.treeMode ? modelData.label : modelData.path
                        depth: modelData.depth ?? 0
                        folder: modelData.directory === true
                        folderIcon: true
                        expanded: modelData.expanded === true
                        showDirectory: !workspace.treeMode
                        status: modelData.status ?? ""
                        selected: !folder && workspace.review !== null && workspace.review.selected !== null
                            && workspace.review.selected.stableId === modelData.stableId
                        onClicked: if (!folder) Store.hosting.reviewSelect(modelData.stableId)
                        onFolderToggled: Store.hosting.reviewToggleFolder(modelData.identity)
                        onContextMenuRequested: (x, y) => { if (!folder) workspace.showFileMenu(modelData.path ?? modelData.identity, fileRow, x, y) }
                    }
                    footer: Item {
                        width: files.width
                        height: workspace.review && workspace.review.hasMore ? loadMore.height + 2 * Theme.space.s3 : 0
                        MeridianButton {
                            id: loadMore
                            objectName: "hosting-review-load-more"
                            visible: workspace.review !== null && workspace.review.hasMore === true
                            x: Theme.space.s4
                            y: Theme.space.s3
                            text: L10n.t("hostingLoadMore")
                            controlSize: MeridianButton.Small
                            enabled: workspace.review !== null && workspace.review.loading !== true
                            onClicked: Store.hosting.reviewLoadMore()
                        }
                    }
                }
            }

            // The selected file's patch and its commentable lines.
            MeridianIsland {
                id: diffIsland
                width: parent.width - GitLamaLayout.conflictFileListWidth - parent.spacing
                    - (workspace.compact ? 0 : GitLamaLayout.reviewCommentRailWidth + parent.spacing)
                height: parent.height
                readonly property var diff: workspace.review ? workspace.review.selected : null
                MeridianEmptyState {
                    visible: parent.diff === null
                    anchors.fill: parent
                    compact: true
                    title: L10n.t("hostingReviewNoDiff")
                }
                Flickable {
                    id: patchScroller
                    visible: parent.diff !== null
                    anchors.fill: parent
                    contentHeight: patchColumn.implicitHeight + 2 * Theme.space.s5
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    MeridianWheelScroll { flickable: patchScroller }
                    C.ScrollBar.vertical: MeridianScrollBar {}
                    Column {
                        id: patchColumn
                        x: Theme.space.s5
                        y: Theme.space.s5
                        width: patchScroller.width - 2 * Theme.space.s5
                        spacing: Theme.space.s4
                        MeridianSelectableText {
                            width: parent.width
                            role: MeridianText.Code
                            text: diffIsland.diff ? diffIsland.diff.patch : ""
                            wrapMode: Text.WrapAnywhere
                        }
                        Flow {
                            width: parent.width
                            spacing: Theme.space.s2
                            Repeater {
                                model: diffIsland.diff ? diffIsland.diff.anchors : []
                                delegate: MeridianButton {
                                    required property var modelData
                                    text: String(modelData.line)
                                    controlSize: MeridianButton.Small
                                    onClicked: workspace.addInline(modelData, "")
                                }
                            }
                        }
                    }
                }
            }

            MeridianIsland {
                visible: !workspace.compact
                width: GitLamaLayout.reviewCommentRailWidth
                height: parent.height
                Loader {
                    anchors.fill: parent
                    active: !workspace.compact
                    sourceComponent: commentsContent
                }
            }
        }

        // The rail as a drawer on narrow windows.
        MeridianPanel {
            visible: workspace.compact && workspace.commentsVisible
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.space.s3
            width: Math.min(GitLamaLayout.reviewDrawerWidth, parent.width - 2 * Theme.space.s3)
            title: L10n.t("hostingReviewThreads")
            closeLabel: L10n.t("close")
            onCloseRequested: workspace.commentsVisible = false
            Loader {
                width: parent.width
                height: Math.max(GitLamaLayout.reviewDrawerMinHeight, body.height - Metrics.floatingPanelHeaderHeight - 2 * Theme.space.s3)
                active: workspace.compact && workspace.commentsVisible
                sourceComponent: commentsContent
            }
        }
    }

    // Threads, checks, the review action and text, line comments, Preview.
    Component {
        id: commentsContent
        Flickable {
            id: rail
            contentHeight: railColumn.implicitHeight + 2 * Theme.space.s5
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            MeridianWheelScroll { flickable: rail }
            C.ScrollBar.vertical: MeridianScrollBar {}
            Column {
                id: railColumn
                x: Theme.space.s5
                y: Theme.space.s5
                width: rail.width - 2 * Theme.space.s5
                spacing: Theme.space.s4
                MeridianSelectableText {
                    visible: !!workspace.review && !!workspace.review.failure
                    width: parent.width
                    text: workspace.review && workspace.review.failure ? L10n.tn("hostingReviewFailure", { reason: workspace.review.failure }) : ""
                }
                MeridianText { role: MeridianText.BodyStrong; text: L10n.t("hostingReviewThreads") }
                Repeater {
                    model: workspace.review ? workspace.review.threads : []
                    delegate: Column {
                        id: thread
                        required property var modelData
                        width: railColumn.width
                        spacing: Theme.space.s2
                        Row {
                            width: parent.width
                            spacing: Theme.space.s3
                            AuthorAvatar {
                                anchors.verticalCenter: parent.verticalCenter
                                author: thread.modelData.author
                                avatarSize: MeridianAvatar.Small
                            }
                            MeridianText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - (outdatedRow.visible ? outdatedRow.width + parent.spacing : 0)
                                text: thread.modelData.author
                                elide: Text.ElideRight
                            }
                            Row {
                                id: outdatedRow
                                visible: thread.modelData.outdated === true
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.space.s2
                                MeridianCount {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: L10n.t("hostingReviewOutdated")
                                    tone: MeridianCount.Quiet
                                }
                                MeridianButton {
                                    text: L10n.t("hostingReviewReanchor")
                                    controlSize: MeridianButton.Small
                                    variant: MeridianButton.Quiet
                                    onClicked: workspace.reanchor(thread.modelData)
                                }
                            }
                        }
                        MeridianSelectableText { width: parent.width; text: thread.modelData.body; wrapMode: Text.Wrap }
                    }
                }
                MeridianHairline { width: parent.width }
                MeridianText { role: MeridianText.BodyStrong; text: L10n.t("hostingChecks") }
                Repeater {
                    model: workspace.review ? workspace.review.checks : []
                    delegate: MeridianListRow {
                        id: checkRow
                        required property var modelData
                        width: railColumn.width
                        text: modelData.name
                        subtitle: modelData.state
                        twoLine: true
                        onClicked: if (modelData.detailsUrl && Store.hosting.openable(modelData.detailsUrl)) Qt.openUrlExternally(modelData.detailsUrl)
                        trailing: Component {
                            MeridianButton {
                                objectName: "hosting-check-retry-" + checkRow.modelData.stableId
                                text: L10n.t("hostingCheckRetry")
                                controlSize: MeridianButton.Small
                                enabled: !workspace.busy
                                onClicked: Store.hosting.reviewRetryCheck(checkRow.modelData.stableId)
                            }
                        }
                    }
                }
                MeridianHairline { width: parent.width }
                MeridianText { role: MeridianText.Label; text: L10n.t("hostingReviewAction") }
                MeridianSelect {
                    fixedWidth: parent.width
                    label: L10n.t("hostingReviewAction")
                    enabled: !workspace.busy
                    values: ["comment", "approve", "requestChanges"]
                    value: workspace.review ? workspace.review.action : "comment"
                    valueLabel: value => workspace.actionLabel(value)
                    onActivated: value => Store.hosting.reviewSetAction(value)
                }
                MeridianText { role: MeridianText.Label; text: L10n.t("hostingReviewComment") }
                MeridianTextArea {
                    objectName: "hosting-review-body"
                    width: parent.width
                    minimumLines: 4
                    maximumLines: 10
                    Accessible.name: L10n.t("hostingReviewComment")
                    Component.onCompleted: text = workspace.review ? workspace.review.body : ""
                    onTextChanged: {
                        if (workspace.review && text !== workspace.review.body) {
                            Store.hosting.reviewSetBody(text)
                            draftTimer.restart()
                        }
                    }
                }
                Repeater {
                    model: workspace.review ? workspace.review.inline : []
                    delegate: MeridianListRow {
                        id: draftRow
                        required property var modelData
                        width: railColumn.width
                        text: modelData.path + ":" + modelData.line
                        subtitle: modelData.body
                        twoLine: true
                        trailing: Component {
                            MeridianIconButton {
                                text: L10n.t("delete")
                                iconName: "close"
                                controlSize: MeridianButton.Small
                                onClicked: Store.hosting.reviewRemoveInline(draftRow.modelData.stableId)
                            }
                        }
                    }
                }
                MeridianButton {
                    objectName: "hosting-review-preview"
                    text: L10n.t("hostingReviewPreview")
                    variant: MeridianButton.Primary
                    enabled: !workspace.busy
                    onClicked: Store.hosting.reviewSubmit()
                }
            }
        }
    }

    function actionLabel(action) {
        return action === "approve" ? L10n.t("hostingReviewApprove")
            : action === "requestChanges" ? L10n.t("hostingReviewRequestChanges") : L10n.t("hostingReviewCommentAction")
    }
    /// A comment on `anchor`'s line; the one already there is edited.
    function addInline(anchor, body) {
        const existing = (review ? review.inline : []).find(draft => draft.path === anchor.path && draft.line === anchor.line)
        inlineDialog.anchor = anchor
        inlineDialog.title = L10n.tn("hostingReviewInlineTitle", { line: anchor.line })
        inlineField.text = existing ? existing.body : body
        inlineDialog.open()
        inlineField.textArea.forceActiveFocus()
    }
    function reanchor(thread) {
        if (thread.anchor)
            addInline(thread.anchor, thread.body)
    }
    function showFileMenu(path, item, x, y) {
        fileMenu.path = path
        fileMenu.showFor({ source: "reviewFile", path: path, exists: true }, null, {
            capabilities: ["copyPath"], reasons: ({}), inspectionReason: null, busy: false, allowStagingWhileBusy: false,
        }, item, x, y)
    }

    FileActionMenu {
        id: fileMenu
        property string path
        run: (action, selection) => {
            if (action === "copyPath")
                Store.actions.copyText(path, L10n.t("filePathCopied"))
        }
    }

    // One line's comment.
    MeridianDialog {
        id: inlineDialog
        property var anchor: null
        widthClass: MeridianDialog.Form
        onSubmitted: save()
        function save() {
            const text = inlineField.text.trim()
            close()
            if (anchor && text.length > 0)
                Store.hosting.reviewAddInline(anchor.stableId, anchor.path, anchor.line, text)
        }
        Column {
            width: parent ? parent.width : 0
            spacing: Theme.space.s2
            MeridianText { role: MeridianText.Label; text: L10n.t("hostingReviewComment") }
            MeridianTextArea {
                id: inlineField
                objectName: "hosting-review-inline-body"
                width: parent.width
                minimumLines: 3
                maximumLines: 8
                Accessible.name: L10n.t("hostingReviewComment")
            }
        }
        actions: [
            MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: inlineDialog.close() },
            MeridianButton {
                objectName: "hosting-review-inline-save"
                text: L10n.t("hostingReviewInlineSave")
                variant: MeridianButton.Primary
                onClicked: inlineDialog.save()
            }
        ]
    }
}
