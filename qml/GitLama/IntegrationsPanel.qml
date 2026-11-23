pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The bound repository's provider resources (the Dart IntegrationsPanel):
// refresh and Create pull request, a filter, then its pull requests and
// issues in groups that remember whether they are open, each with its
// actions, and more pages on request. The state is Store.hosting.repository.
MeridianPanel {
    id: panel

    property real availableHeight: GitLamaLayout.integrationsBodyHeight + headerHeight
    readonly property var repositoryState: Store.hosting ? (Store.hosting.repository ?? ({})) : ({})
    readonly property var binding: repositoryState.binding ?? null
    readonly property bool bound: binding !== null && binding.state === "bound"
    readonly property bool busy: repositoryState.busy === true
    readonly property var capabilities: repositoryState.capabilities ?? []
    readonly property string query: filter.text.trim().toLowerCase()
    readonly property var pulls: (repositoryState.changeRequests ?? []).filter(pull => query.length === 0
        || pull.title.toLowerCase().indexOf(query) >= 0 || pull.author.toLowerCase().indexOf(query) >= 0
        || pull.sourceBranch.toLowerCase().indexOf(query) >= 0 || String(pull.number).indexOf(query) >= 0)
    readonly property var issues: (repositoryState.issues ?? []).filter(issue => query.length === 0
        || issue.title.toLowerCase().indexOf(query) >= 0 || issue.author.toLowerCase().indexOf(query) >= 0
        || String(issue.number).indexOf(query) >= 0)
    /// The groups shown open, remembered in the settings.
    property var expanded: ({})
    Component.onCompleted: {
        const open = {}
        for (const node of (Store.hosting.accounts.expandedNodes ?? []))
            open[node] = true
        expanded = open
    }

    function openUrl(url) {
        if (url && Store.hosting.openable(url))
            Qt.openUrlExternally(url)
    }
    function createChangeRequest() {
        const url = Store.hosting.resourceLink("createChangeRequest", 0)
        openUrl(url)
    }
    function failureText(code) {
        if (!code)
            return ""
        const words = { notFound: "hostingFailureNotFound", redirected: "hostingFailureRedirected", serverError: "hostingFailureServerError",
                        network: "hostingFailureNetwork", certificate: "hostingFailureCertificate", timedOut: "hostingFailureTimedOut" }[code]
        return L10n.tn("hostingFailure", { reason: words ? L10n.t(words) : code })
    }
    function toggleGroup(id, open) {
        const next = Object.assign({}, expanded)
        next[id] = open
        expanded = next
        Store.hosting.setExpandedNodes(Object.keys(next).filter(key => next[key]))
    }

    title: L10n.t("hostingResources")
    closeLabel: L10n.t("close")
    width: GitLamaLayout.integrationsPanelWidth
    leftPadding: 0
    rightPadding: 0
    bottomPadding: 0
    actions: [
        MeridianIconButton {
            text: L10n.t("settingsIntegrations")
            iconName: "settings"
            controlSize: MeridianButton.Small
            onClicked: Store.actions.showSettings("integrations")
        }
    ]

    Flickable {
        id: scroller
        objectName: "integration-list"
        width: panel.bodyWidth
        height: Math.min(GitLamaLayout.integrationsBodyHeight, panel.availableHeight - panel.headerHeight)
        contentHeight: content.implicitHeight + Theme.space.s5
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        MeridianWheelScroll { flickable: scroller }
        C.ScrollBar.vertical: MeridianScrollBar {}

        Column {
            id: content
            x: Theme.space.s5
            width: scroller.width - 2 * Theme.space.s5
            spacing: Theme.space.s4

            Item {
                width: parent.width
                height: Math.max(heading.implicitHeight, headerActions.implicitHeight)
                MeridianText {
                    id: heading
                    anchors.verticalCenter: parent.verticalCenter
                    role: MeridianText.BodyStrong
                    text: L10n.t("hostingResources")
                }
                Row {
                    id: headerActions
                    anchors.right: parent.right
                    spacing: Theme.space.s2
                    MeridianButton {
                        text: L10n.t("hostingRefresh")
                        iconName: "refresh"
                        variant: MeridianButton.Quiet
                        enabled: panel.bound && !panel.busy
                        onClicked: Store.hosting.refresh(true, 1)
                    }
                    MeridianButton {
                        text: L10n.t("hostingCreateChangeRequest")
                        enabled: panel.bound
                        onClicked: panel.createChangeRequest()
                    }
                }
            }
            MeridianTextField {
                id: filter
                objectName: "hosting-resource-filter"
                width: parent.width
                variant: MeridianTextField.Search
                placeholderText: L10n.t("hostingFilter")
                clearLabel: L10n.t("searchClear")
                Accessible.name: L10n.t("hostingFilter")
            }
            Column {
                visible: panel.repositoryState.loading === true
                width: parent.width
                MeridianProgressBar { width: parent.width }
                MeridianText {
                    visible: (panel.repositoryState.changeRequests ?? []).length > 0 || (panel.repositoryState.issues ?? []).length > 0
                    text: L10n.t("hostingLoadingCached")
                }
            }
            MeridianSelectableText {
                visible: !!panel.repositoryState.failure
                width: parent.width
                color: Theme.colors.danger
                wrapMode: Text.Wrap
                text: panel.failureText(panel.repositoryState.failure)
            }

            // Pull requests.
            MeridianDisclosure {
                width: parent.width
                title: L10n.t("hostingChangeRequests")
                expanded: panel.query.length > 0 || panel.expanded.changeRequests === true
                onToggled: value => { if (panel.query.length === 0) panel.toggleGroup("changeRequests", value) }
                trailing: MeridianCount { label: String(panel.pulls.length); tone: MeridianCount.Quiet }
                Column {
                    width: parent ? parent.width : 0
                    Repeater {
                        model: panel.pulls
                        delegate: MeridianListRow {
                            id: pullRow
                            required property var modelData
                            readonly property bool checkoutSupported: panel.capabilities.indexOf("changeRequestCheckout") >= 0
                            readonly property bool sameRepository: modelData.sourceRepository.length > 0
                                && panel.binding !== null && modelData.sourceRepository === panel.binding.providerRepository
                            objectName: "hosting-pull-" + modelData.stableId
                            width: parent ? parent.width : 0
                            text: "#" + modelData.number + " " + modelData.title
                            subtitle: modelData.author + " · " + modelData.sourceBranch + " → " + modelData.targetBranch + " · " + modelData.checks
                            leading: Component { AuthorAvatar { author: pullRow.modelData.author } }
                            trailing: Component {
                                Row {
                                    spacing: Theme.space.s2
                                    MeridianButton {
                                        text: L10n.t("hostingCheckout")
                                        controlSize: MeridianButton.Small
                                        enabled: pullRow.checkoutSupported && pullRow.sameRepository
                                        disabledReason: !pullRow.checkoutSupported ? L10n.t("hostingCapabilityUnavailable")
                                            : !pullRow.sameRepository ? L10n.t("hostingForkCheckoutUnavailable") : ""
                                        onClicked: Store.actions.runCommand("createBranch", {
                                            initialName: pullRow.modelData.sourceBranch, initialTarget: pullRow.modelData.headSha })
                                    }
                                    MeridianButton {
                                        text: L10n.t("hostingReview")
                                        controlSize: MeridianButton.Small
                                        enabled: panel.capabilities.indexOf("changeRequestReview") >= 0
                                        disabledReason: enabled ? "" : L10n.t("hostingCapabilityUnavailable")
                                        onClicked: Store.actions.showPullRequestReview(pullRow.modelData)
                                    }
                                    MeridianIconButton {
                                        text: L10n.t("hostingOpenBrowser")
                                        iconName: "external-link"
                                        controlSize: MeridianButton.Small
                                        onClicked: panel.openUrl(pullRow.modelData.webUrl)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Issues.
            MeridianDisclosure {
                width: parent.width
                title: L10n.t("hostingIssues")
                expanded: panel.query.length > 0 || panel.expanded.issues === true
                onToggled: value => { if (panel.query.length === 0) panel.toggleGroup("issues", value) }
                trailing: MeridianCount { label: String(panel.issues.length); tone: MeridianCount.Quiet }
                Column {
                    width: parent ? parent.width : 0
                    Repeater {
                        model: panel.issues
                        delegate: MeridianListRow {
                            id: issueRow
                            required property var modelData
                            width: parent ? parent.width : 0
                            text: "#" + modelData.number + " " + modelData.title
                            subtitle: modelData.author + " · " + (modelData.open ? "open" : "closed")
                            leading: Component { AuthorAvatar { author: issueRow.modelData.author } }
                            trailing: Component {
                                MeridianIconButton {
                                    text: L10n.t("hostingOpenBrowser")
                                    iconName: "external-link"
                                    controlSize: MeridianButton.Small
                                    onClicked: panel.openUrl(issueRow.modelData.webUrl)
                                }
                            }
                        }
                    }
                }
            }
            MeridianText {
                visible: panel.repositoryState.loading !== true && panel.bound && panel.pulls.length === 0 && panel.issues.length === 0
                    && !panel.repositoryState.failure
                text: L10n.t("hostingEmpty")
            }
            Item {
                visible: panel.repositoryState.hasMore === true
                width: parent.width
                height: visible ? moreButton.implicitHeight : 0
                MeridianButton {
                    id: moreButton
                    anchors.right: parent.right
                    text: L10n.t("hostingLoadMore")
                    enabled: !panel.busy
                    onClicked: Store.hosting.refresh(true, (panel.repositoryState.page ?? 1) + 1)
                }
            }
        }
    }
}
