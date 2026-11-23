pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// The power tools: a search through every
// commit's changes, the repository's statistics and bisect. Floating, the
// three sections are stacked under their headers; docked in History, a
// section switch shows one. The jobs and bisect run in Rust
// (Store.workflows.powerTools); each panel shown owns that state while open.
Item {
    id: tools

    property bool docked: false
    signal closeRequested()

    readonly property int owner: Math.floor(Math.random() * 2000000000) + 1
    readonly property var panelState: Store.workflows ? (Store.workflows.powerTools ?? ({})) : ({})
    readonly property var search: panelState.search ?? null
    readonly property var statistics: panelState.statistics ?? null
    readonly property var bisect: panelState.bisect ?? null
    readonly property bool searchRunning: panelState.searchRunning === true
    readonly property bool bisectBusy: panelState.bisectBusy === true
    property bool caseSensitive: false
    property string searchScope: "allRefs"
    property string section: "search"
    property string query: ""
    property string good: ""
    property string bad: ""

    readonly property var sections: ["search", "statistics", "bisect"]
    function sectionTitle(name) {
        return L10n.t(name === "search" ? "powerSearchTitle" : name === "statistics" ? "powerStatisticsTitle" : "powerBisectTitle")
    }
    function sectionIcon(name) {
        return name === "search" ? "text-search" : name === "statistics" ? "chart-column" : "bug"
    }
    function act(action, options) { Store.workflows.powerTool(action, options ?? ({})) }
    function startSearch() {
        if (query.trim().length === 0 || searchRunning)
            return
        act("search", { query: query, caseSensitive: caseSensitive, currentBranch: searchScope === "currentBranch" })
    }
    function runBisect(step) {
        if (bisectBusy)
            return
        act("bisect", { step: step, good: good, bad: bad })
    }
    function reveal(commit) {
        act("reveal", { commit: commit })
        tools.closeRequested()
    }
    function number(value) { return Number(value ?? 0).toLocaleString(Qt.locale(L10n.locale), "f", 0) }

    // Another tab's repository has its own tools.
    readonly property var tabId: Store.workspace.active ? Store.workspace.active.id : null
    onTabIdChanged: {
        query = ""
        good = ""
        bad = ""
        act("open", { owner: owner })
    }
    Component.onCompleted: act("open", { owner: owner })
    Component.onDestruction: act("close", { owner: owner })

    Column {
        id: frame
        anchors.fill: parent

        MeridianProgressBar {
            visible: tools.panelState.busy === true
            width: parent.width
        }
        Item {
            visible: tools.panelState.failed === true
            width: parent.width
            height: visible ? failure.implicitHeight + 2 * Theme.space.s5 : 0
            MeridianBanner {
                id: failure
                x: Theme.space.s5
                y: Theme.space.s5
                width: parent.width - 2 * Theme.space.s5
                tone: MeridianBanner.Error
                message: L10n.t("powerFailed")
            }
        }
        Item {
            visible: tools.docked
            width: parent.width
            height: visible ? sectionSwitch.implicitHeight + 2 * Theme.space.s2 : 0
            MeridianSegmented {
                id: sectionSwitch
                objectName: "power-tools-section"
                x: Theme.space.s5
                y: Theme.space.s2
                width: parent.width - 2 * Theme.space.s5
                expand: true
                label: L10n.t("powerToolsTitle")
                segments: tools.sections.map(name => ({ value: name, label: tools.sectionTitle(name) }))
                value: tools.section
                onActivated: value => tools.section = value
            }
        }
        ListView {
            id: list
            objectName: "power-tools-list"
            width: parent.width
            height: frame.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: tools.docked ? [tools.section] : tools.sections
            MeridianWheelScroll { flickable: list }
            C.ScrollBar.vertical: MeridianScrollBar {}
            delegate: Column {
                id: sectionColumn
                required property string modelData
                width: list.width
                MeridianSectionHeader {
                    visible: !tools.docked
                    width: parent.width
                    iconName: tools.sectionIcon(sectionColumn.modelData)
                    title: tools.sectionTitle(sectionColumn.modelData)
                }
                Item {
                    width: parent.width
                    height: loader.height + Theme.space.s5 + (tools.docked ? Theme.space.s5 : Theme.space.s8)
                    Loader {
                        id: loader
                        x: Theme.space.s5
                        y: Theme.space.s5
                        width: parent.width - 2 * Theme.space.s5
                        sourceComponent: sectionColumn.modelData === "search" ? searchSection
                            : sectionColumn.modelData === "statistics" ? statisticsSection : bisectSection
                    }
                }
            }
        }
    }

    Component {
        id: searchSection
        Column {
            spacing: Theme.space.s6
            Column {
                width: parent.width
                spacing: Theme.space.s2
                MeridianText { role: MeridianText.Label; text: L10n.t("powerSearchQuery") }
                MeridianTextField {
                    objectName: "power-search-query"
                    width: parent.width
                    text: tools.query
                    enabled: !tools.searchRunning
                    Accessible.name: L10n.t("powerSearchQuery")
                    onTextEdited: tools.query = text
                    onAccepted: tools.startSearch()
                }
                MeridianText {
                    width: parent.width
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    wrapMode: Text.Wrap
                    text: L10n.t("powerSearchBound")
                }
            }
            Item {
                width: parent.width
                height: Math.max(options.implicitHeight, searchButton.implicitHeight)
                Flow {
                    id: options
                    width: parent.width - searchButton.width - Theme.space.s6
                    spacing: Theme.space.s6
                    MeridianSegmented {
                        label: L10n.t("powerSearchScope")
                        segments: [{ value: "allRefs", label: L10n.t("powerSearchAllRefs") },
                                   { value: "currentBranch", label: L10n.t("powerSearchCurrentBranch") }]
                        value: tools.searchScope
                        onActivated: value => { if (!tools.searchRunning) tools.searchScope = value }
                    }
                    MeridianCheckbox {
                        height: Theme.size.control
                        text: L10n.t("powerSearchCaseSensitive")
                        checked: tools.caseSensitive
                        enabled: !tools.searchRunning
                        onToggled: tools.caseSensitive = checked
                    }
                }
                MeridianButton {
                    id: searchButton
                    objectName: tools.searchRunning ? "power-search-cancel" : "power-search-start"
                    anchors.right: parent.right
                    text: tools.searchRunning ? L10n.t("powerSearchCancel") : L10n.t("powerSearchAction")
                    variant: tools.searchRunning ? MeridianButton.Secondary : MeridianButton.Primary
                    onClicked: tools.searchRunning ? tools.act("cancelSearch") : tools.startSearch()
                }
            }
            MeridianBanner {
                visible: tools.search !== null && tools.search.completeness === "commits"
                width: parent.width
                tone: MeridianBanner.Info
                message: L10n.t("powerSearchIncompleteCommits")
            }
            MeridianBanner {
                visible: tools.search !== null && tools.search.completeness === "results"
                width: parent.width
                tone: MeridianBanner.Info
                message: L10n.t("powerSearchIncompleteResults")
            }
            MeridianText {
                objectName: "power-search-summary"
                visible: tools.search !== null && tools.search.matches.length === 0
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: summary(tools.search)
                function summary(search) {
                    if (search === null)
                        return ""
                    return L10n.tn("powerSearchFound", { count: search.matches.length }) + " · "
                        + L10n.tn("powerSearchExamined", { count: search.examined })
                }
            }
            ListWell {
                visible: tools.search !== null && tools.search.matches.length > 0
                width: parent.width
                height: visible ? implicitHeight : 0
                model: tools.search ? tools.search.matches : []
                header: Item {
                    width: ListView.view ? ListView.view.width : 0
                    height: headerText.implicitHeight + Theme.space.s4
                    MeridianText {
                        id: headerText
                        objectName: "power-search-summary"
                        x: Theme.space.s6
                        y: Theme.space.s4
                        width: parent.width - Theme.space.s6 - Theme.space.s3
                        role: MeridianText.Caption
                        color: Theme.colors.inkMuted
                        text: tools.search ? L10n.tn("powerSearchFound", { count: tools.search.matches.length }) + " · "
                            + L10n.tn("powerSearchExamined", { count: tools.search.examined }) : ""
                    }
                }
                delegate: MeridianListRow {
                    required property var modelData
                    width: ListView.view ? ListView.view.width : 0
                    iconName: "git-commit-horizontal"
                    text: modelData.summary
                    meta: modelData.short
                    onClicked: tools.reveal(modelData.commit)
                }
            }
        }
    }

    Component {
        id: statisticsSection
        Column {
            spacing: Theme.space.s4
            Item {
                visible: tools.statistics === null
                width: parent.width
                height: visible ? loadButton.implicitHeight : 0
                MeridianButton {
                    id: loadButton
                    objectName: "power-statistics-load"
                    text: L10n.t("powerStatisticsLoad")
                    enabled: tools.panelState.statisticsRunning !== true
                    onClicked: tools.act("statistics")
                }
            }
            MeridianPropertyList {
                objectName: "power-statistics-facts"
                visible: tools.statistics !== null
                width: parent.width
                properties: tools.statistics === null ? [] : [
                    { label: L10n.t("powerStatisticsCommits"), value: tools.number(tools.statistics.commits), selectable: false },
                    { label: L10n.t("powerStatisticsBranches"), value: tools.number(tools.statistics.branches), selectable: false },
                    { label: L10n.t("powerStatisticsTags"), value: tools.number(tools.statistics.tags), selectable: false },
                    { label: L10n.t("powerStatisticsChangedFiles"), value: tools.number(tools.statistics.changedFiles), selectable: false },
                ]
            }
            MeridianText {
                visible: tools.statistics !== null && tools.statistics.incomplete === true
                width: parent.width
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                wrapMode: Text.Wrap
                text: L10n.t("powerStatisticsIncomplete")
            }
        }
    }

    Component {
        id: bisectSection
        Item {
            implicitHeight: tools.bisect === null ? Theme.size.control * 2
                : tools.bisect.active ? activeColumn.implicitHeight : idleColumn.implicitHeight
            MeridianSpinner {
                visible: tools.bisect === null
                anchors.centerIn: parent
            }
            Column {
                id: idleColumn
                visible: tools.bisect !== null && !tools.bisect.active
                width: parent.width
                spacing: Theme.space.s6
                MeridianText {
                    width: parent.width
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    wrapMode: Text.Wrap
                    text: L10n.t("powerBisectHelp")
                }
                ReferenceField {
                    objectName: "power-bisect-good"
                    width: parent.width
                    label: L10n.t("powerBisectGood")
                    names: []
                    choices: Store.history ? Store.history.referenceChoices() : []
                    text: tools.good
                    onEdited: tools.good = text
                }
                ReferenceField {
                    objectName: "power-bisect-bad"
                    width: parent.width
                    label: L10n.t("powerBisectBad")
                    names: []
                    choices: Store.history ? Store.history.referenceChoices() : []
                    text: tools.bad
                    onEdited: tools.bad = text
                }
                Item {
                    width: parent.width
                    height: startButton.implicitHeight
                    MeridianButton {
                        id: startButton
                        objectName: "power-bisect-start"
                        anchors.right: parent.right
                        text: L10n.t("powerBisectStart")
                        variant: MeridianButton.Primary
                        enabled: !tools.bisectBusy
                        onClicked: tools.runBisect("start")
                    }
                }
            }
            Column {
                id: activeColumn
                visible: tools.bisect !== null && tools.bisect.active
                width: parent.width
                spacing: Theme.space.s6
                MeridianPropertyList {
                    width: parent.width
                    properties: tools.bisect === null ? [] : [
                        { label: L10n.t("powerBisectTesting"), value: tools.bisect.current ?? "—", monospace: !!tools.bisect.current },
                        { label: L10n.t("powerBisectProgressLabel"),
                          value: L10n.tn("powerBisectProgress", { tested: tools.bisect.steps, remaining: tools.bisect.remaining }),
                          selectable: false },
                    ]
                }
                Column {
                    width: parent.width
                    spacing: Theme.space.s4
                    MeridianText { role: MeridianText.Body; color: Theme.colors.ink; text: L10n.t("powerBisectQuestion") }
                    Item {
                        width: parent.width
                        height: Math.max(marks.implicitHeight, resetButton.implicitHeight)
                        Flow {
                            id: marks
                            width: parent.width - resetButton.width - Theme.space.s4
                            spacing: Theme.space.s4
                            MeridianButton {
                                text: L10n.t("powerBisectMarkGood")
                                iconName: "circle-check"
                                enabled: !tools.bisectBusy
                                onClicked: tools.runBisect("good")
                            }
                            MeridianButton {
                                text: L10n.t("powerBisectMarkBad")
                                iconName: "bug"
                                enabled: !tools.bisectBusy
                                onClicked: tools.runBisect("bad")
                            }
                            MeridianButton {
                                text: L10n.t("powerBisectSkip")
                                variant: MeridianButton.Quiet
                                enabled: !tools.bisectBusy
                                onClicked: tools.runBisect("skip")
                            }
                        }
                        MeridianButton {
                            id: resetButton
                            anchors.right: parent.right
                            text: L10n.t("powerBisectReset")
                            variant: MeridianButton.Quiet
                            enabled: !tools.bisectBusy
                            onClicked: tools.runBisect("reset")
                        }
                    }
                }
            }
        }
    }
}
