pragma Singleton
import QtQuick
import Meridian

// GitLama's component dimensions, opacities and timings that are not
// Meridian tokens: the git components (graph, diff, ref chips, Compass,
// Logbook, composer) and the window layout. Source: docs/design-system
// (components/reference/bundle.css and specs/*.md).
QtObject {
    // GitLamaLayout
    readonly property real inspectorWideWidth: 560
    readonly property real inspectorSidebarMin: 180
    readonly property real inspectorContentMin: 320
    readonly property real titleBarDragWidth: 24
    readonly property real statusBranchMaxWidth: 160
    readonly property real compactBreakpoint: 1100
    readonly property real contentMaxWidth: 640
    readonly property real compassHeight: 32
    readonly property real compassMinWidth: 360
    readonly property real compassCompactMinWidth: 240
    readonly property real compassMaxWidth: 560
    readonly property real compassBranchMaxWidth: 220
    readonly property real compassRepositoryMaxWidth: 220
    readonly property real listMinWidth: 180
    readonly property real codePaneMinWidth: 220
    readonly property real changesDiffMinWidth: 300
    readonly property real changesFilePaneMinWidth: 280
    readonly property real historyQueryToolbarMinWidth: 672
    readonly property real primaryIslandMinHeight: 260
    readonly property real detailIslandDefaultWidth: 440
    readonly property real workflowHeaderHeight: 44
    readonly property real paneResizeStep: 32
    readonly property real changesSplitRatioMin: 0.1
    readonly property real changesSplitRatioMax: 0.9
    readonly property real gitSuggestionMaxHeight: 180
    readonly property real branchFilterWidth: 360
    readonly property real branchFilterListMaxHeight: 320
    readonly property real laneWidth: 14
    readonly property real glyphSize: 16
    readonly property real refChipHeight: 18
    readonly property real refChipPaddingX: 6
    readonly property real refChipMaxWidth: 220
    readonly property real refDotSize: 6
    readonly property real refIconSize: 11
    readonly property real tagNotch: 6
    readonly property real tagPaddingStart: 9
    readonly property real syncIconSize: 11
    readonly property real graphLaneOrigin: 9
    readonly property real graphCommitRadius: 4.5
    readonly property real graphRingStroke: 2
    readonly property real graphStrokeLit: 2.5
    readonly property real graphHeadInnerRadius: 4
    readonly property real graphHeadOuterRadius: 7
    readonly property real graphHeadOuterStroke: 1.5
    readonly property real graphMergeDotRadius: 1.75
    readonly property real graphDash: 2.2
    readonly property real graphBoundarySquare: 7
    readonly property real graphBoundaryStroke: 1.5
    readonly property real graphNodeInkRadius: 8
    readonly property real graphNodeHitWidth: 14
    readonly property int graphMaxRefChips: 2
    readonly property real diffLineHeight: 18
    readonly property real diffGutterWidth: 44
    readonly property real diffSignWidth: 18
    readonly property real hunkHeaderHeight: 30
    readonly property real diffFallbackHeight: 180
    readonly property real diffPickRail: 3
    readonly property real diffWrapIndent: 106
    readonly property real diffMinCodeUnified: 280
    readonly property real diffMinCodeSplit: 220
    readonly property real diffToolbarPathMinWidth: 720
    readonly property real diffToolbarPathWidthFraction: 0.23
    readonly property real diffToolbarPathMinLabelWidth: 64
    readonly property real diffToolbarPathMaxWidth: 180
    readonly property real diffMinimapWidth: 8
    readonly property real blameBandWidth: 180
    readonly property real blameDetailStripHeight: 38
    readonly property real remoteHostListMaxHeight: 220
    readonly property real remoteDirectoryListHeight: 260
    readonly property real remoteHostBadgeMaxWidth: 260
    readonly property int tabGroupPreviewTabs: 3
    readonly property real paletteWidth: 600
    readonly property real repositoryDetailsWidth: 520
    readonly property real repositoryDetailsTileSize: 44
    readonly property real repositoryDetailsTileIconSize: 22
    readonly property real repositoryDetailsStatMinWidth: 140
    readonly property real repositoryDetailsStatMinHeight: 76
    readonly property real changesHeaderActionsMaxWidth: 300
    readonly property real paletteQueryHeight: 48
    readonly property real paletteMaxHeightFraction: 0.7
    readonly property real overlayMaxHeightFraction: 0.8
    readonly property real commitSummaryMaxHeightFraction: 0.5
    readonly property real logbookWidth: 420
    readonly property real logbookMarkSize: 20
    readonly property real logbookMarkIconSize: 12
    readonly property real logbookRailWidth: 2
    readonly property real dragThreshold: 6
    readonly property real composerSubjectHeight: 32
    readonly property int composerDescriptionMinLines: 2
    readonly property int composerDescriptionMaxLines: 5
    readonly property int subjectGuide: 50
    readonly property int subjectLimit: 72
    readonly property real rebaseIndent: 14
    readonly property real rebaseActionWidth: 96
    readonly property real conflictFileListWidth: 220
    readonly property real conflictFileListMinWidth: 180
    readonly property real conflictEditorMinWidth: 320
    readonly property real conflictWideEditorMinWidth: 840
    readonly property real conflictResultCompactHeight: 220
    readonly property real conflictSourceActionMinWidth: 400
    readonly property real conflictDetailsMaxHeight: 180
    readonly property real conflictRail: 3
    readonly property real conflictRegionToolbarHeight: 42
    readonly property real conflictLineColumnWidth: 34
    readonly property real resultMinHeightFraction: 0.4
    readonly property real reviewCommentRailWidth: 280
    readonly property real reviewDrawerBreakpoint: 1280
    readonly property real reviewDrawerWidth: 360
    /// The review drawer's least body height.
    readonly property real reviewDrawerMinHeight: 200
    readonly property real welcomeMarkSize: 64
    readonly property real licenseMarkSize: 40
    readonly property real aboutMarkSize: 96
    readonly property real launchMarkSize: 128
    readonly property real resolvedStateIconSize: 40
    readonly property real snapshotsPanelWidth: 620
    readonly property real extensionsPanelWidth: 680
    readonly property real integrationsPanelWidth: 720
    readonly property real powerToolsPanelWidth: 720
    readonly property real extensionsBodyMaxHeight: 436
    readonly property real recoveryBodyHeight: 456
    readonly property real snapshotsBodyHeight: 576
    readonly property real powerToolsBodyHeight: 640
    readonly property real integrationsBodyHeight: 676
    readonly property real powerToolsDockedMaxHeight: 280
    readonly property real powerToolsDockedHeightFraction: 0.35
    readonly property real commandDetailsMaxHeight: 240
    readonly property real logbookOutputMaxHeight: 180
    readonly property real activityHeight: 170
    readonly property real activityOutputMaxHeight: 120
    readonly property real commitFailureOutputMaxHeight: 160
    readonly property real previewDialogBodyHeight: 520
    readonly property real rebaseTargetListHeight: 320
    readonly property real dialogListMaxHeight: 232
    readonly property real rebaseInstructionListMaxHeight: 360
    readonly property real shortcutReferenceBodyHeight: 520
    readonly property real shortFieldWidth: 180
    readonly property real shortcutFieldWidth: 210
    readonly property real trackingLabelMaxWidth: 72
    readonly property real mergeMessageMaxWidth: 620
    readonly property real referenceSuggestionMinWidth: 180
    readonly property real referenceSuggestionMaxWidth: 360
    readonly property real dropPromptWidth: 420
    readonly property real dropTargetBorder: 2
    readonly property real refPairDividerHeight: 12
    readonly property real historyAuthorWidth: 132
    readonly property real historyMetaSkeletonWidth: 72
    // A loading row's text bars: the subject bar's start, longest width and
    // the room it leaves before the metadata, and every bar's thickness.
    readonly property real historySkeletonTextStart: 40
    readonly property real historySkeletonTextMaxWidth: 320
    readonly property real historySkeletonTextGap: 92
    readonly property real historySkeletonBarHeight: 8
    // A window without a saved frame opens at this size.
    readonly property real windowDefaultWidth: 1280
    readonly property real windowDefaultHeight: 800
    readonly property real windowMinimumWidth: 900
    readonly property real windowMinimumHeight: 600
    // The settings keep frames up to this extent.
    readonly property real windowMaximumExtent: 16384
    // A saved frame keeps its position when a screen shows this much of it.
    readonly property real windowVisibleOverlap: 100
    // Frame changes are saved after this pause.
    readonly property int windowGeometrySaveDelay: 250
    // The window shows without its saved frame when settings take longer.
    readonly property int windowRestoreTimeout: 2000
    // An inspection window opens at this size.
    readonly property real inspectionWindowWidth: 1100
    readonly property real inspectionWindowHeight: 760
    readonly property real conflictChoiceRail: 2
    readonly property real conflictComparisonRowHeight: 25
    readonly property real conflictAncestorHeight: 100
    readonly property real conflictTitleMinHeight: 40
    readonly property real conflictTitleHeight: 32
    readonly property int conflictLeadRows: 2
    // GitLamaOpacity
    readonly property real opacityGlint: 0.6
    readonly property real opacityConflictDivider: 0.45
    readonly property real opacityConflictDiff: 0.06
    readonly property real opacityConflictChosen: 0.16
    readonly property real opacityConflictUnchosen: 0.09
    readonly property real opacityConflictRailChosen: 0.78
    readonly property real opacityConflictRailUnchosen: 0.48
    readonly property real opacityConflictFocus: 0.07
    readonly property real opacityConflictHighlight: 0.10
    readonly property real opacityConflictHover: 0.24
    readonly property real opacityUnlit: 0.3
    readonly property real opacityUnlitText: 0.5
    readonly property real opacityIgnoredRow: 0.6
    readonly property real opacityHeadChipUpstream: 0.75
    readonly property real opacityDiffSelectedLine: 0.10
    readonly property real opacityDiffSelectedText: 0.28
    // GitLamaMotion
    readonly property int foregroundLogbookDelay: 300
    readonly property int laneFocusDelay: 400
    readonly property int laneDim: 180
    readonly property int laneFlowStep: 12
    readonly property int laneFlowMaxRows: 16
    readonly property int laneDrawStep: 10
    readonly property int laneDrawRow: 140
    readonly property int laneDrawMaxRows: 24
    readonly property int commitLand: Motion.highlight
    readonly property int landRingClose: 160
    readonly property int commitTintDelay: 120
    readonly property int glint: Motion.celebrate
    readonly property int remotePathFollowDelay: 250
    readonly property int syncGlintDelay: 300
    /// The tab's own workflow shows in the Compass once it runs this long.
    readonly property int localWorkDelay: 300
    readonly property real glintWidth: 40
    /// The Compass's indeterminate activity band, as a share of the pill.
    readonly property real compassFillBandFraction: 0.45
    readonly property int compassFillSweep: 1600
    /// The Compass wash's resting tint under the band, as a share of `accent-soft`.
    readonly property real compassFillRest: 0.55
    /// How much `accent` the band's crest mixes into `accent-soft`.
    readonly property real compassFillCrest: 0.16
    /// The highlight that crosses the filled pill once an operation ends.
    readonly property int compassFillShine: Motion.celebrate
    readonly property real compassFillShineFraction: 0.35
    readonly property int compassFillFinishHold: Motion.hold
    readonly property int detailDebounce: 150
    readonly property int refreshSpinDelay: Motion.spinnerDelay
    readonly property int stageWash: Motion.emphasized
    readonly property int copiedHold: 1200
    /// How long a press on a Changes row holds before the row drags (Flutter's long press).
    readonly property int longPressDrag: 500
    /// A text selection dragged this close to a list's edge scrolls it, every interval.
    readonly property real dragAutoScrollEdge: 24
    readonly property int dragAutoScrollInterval: 32
    /// Quiet time after a text appears or changes before it is coloured.
    readonly property int syntaxIdle: 150
    /// The palette's content fades in this long after its surface starts growing (NH-6).
    readonly property int paletteContentDelay: 60
    /// Leaving Logbook rows start `motion-stagger` apart, bottom-up, at most this many steps.
    readonly property int logbookLeaveStaggerMax: 5
    /// A file row dragged to the other list stays behind at this opacity.
    readonly property real opacityDragSource: 0.35
    readonly property int openStagger: 40
    readonly property int pullLanesDelay: 60
    readonly property int paletteMorph: 300
    readonly property int paletteRowsDelay: 60
    // Debounces and holds of timers
    readonly property int commitDraftDebounce: 300
    readonly property int reviewDraftDebounce: 250
    readonly property int conflictCountCollapseDelay: 200
    readonly property int conflictsResolvedHold: 1200
    readonly property int continuePulseDelay: 200
    readonly property int reconnectCountdownTick: 1000
    readonly property int remoteCheckSettle: 3000
    readonly property int screenshotSettle: 2500
    readonly property int screenshotStepWait: 1200
}
