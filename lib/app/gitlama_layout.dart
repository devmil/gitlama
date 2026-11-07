import 'package:meridian_ui/meridian_ui.dart';

/// GitLama's component dimensions that are not Meridian tokens or
/// `MeridianLayout` values: the git components (graph, diff, ref chips,
/// Compass, Logbook, composer) and the window layout. Source:
/// docs/design-system (components/reference/bundle.css and specs/*.md).
/// Shared control and chrome dimensions come from meridian_ui.
abstract final class GitLamaLayout {
  /// Below this width the inspector stacks its file list above the content.
  static const double inspectorWideWidth = 560;

  /// The narrowest inspector file list.
  static const double inspectorSidebarMin = 180;

  /// The narrowest inspector content beside the file list.
  static const double inspectorContentMin = 320;

  // Window chrome (foundations.md, FLUTTER_ADAPTATION.md)
  static const double titleBarDragWidth = 24;
  static const double statusBranchMaxWidth = 160; // M08 status bar
  static const double compactBreakpoint = 1100;
  static const double contentMaxWidth = 640;

  // Compass (.ns-compass)
  static const double compassHeight = 32;
  static const double compassMinWidth = 360;
  static const double compassCompactMinWidth = 240;
  static const double compassMaxWidth = 560;
  static const double compassBranchMaxWidth = 220;
  static const double compassRepositoryMaxWidth = 220;

  // Islands and regions (.ns-island, specs/workflows.md)
  static const double listMinWidth = 180;
  static const double codePaneMinWidth = 220;

  /// Changes keeps at least this much width for the diff beside the file
  /// lists, and the file lists at least [changesFilePaneMinWidth].
  static const double changesDiffMinWidth = 300;
  static const double changesFilePaneMinWidth = 280;

  /// History's query toolbar scrolls sideways below this width.
  static const double historyQueryToolbarMinWidth = 672;
  static const double primaryIslandMinHeight = 260;
  static const double detailIslandDefaultWidth = 440;
  static const double workflowHeaderHeight = 44;

  // Split panes: one arrow-key or accessibility step, and the Unstaged
  // list's share of the Changes file lists.
  static const double paneResizeStep = 32;
  static const double changesSplitRatioMin = 0.1;
  static const double changesSplitRatioMax = 0.9;

  // Searchable pickers
  static const double gitSuggestionMaxHeight = 180;
  static const double branchFilterWidth = 360;
  static const double branchFilterListMaxHeight = 320;

  // Git components (.ns-glyph, .ns-ref, .ns-avatar, .ns-sync)
  static const double laneWidth = 14; // size-lane
  static const double glyphSize = 16;
  static const double refChipHeight = 18;
  static const double refChipPaddingX = 6;
  static const double refChipMaxWidth = 220;
  static const double refDotSize = 6;
  static const double refIconSize = 11;
  static const double tagNotch = 6;
  static const double tagPaddingStart = 9;
  static const double syncIconSize = 11;

  // Graph (specs/graph.md)
  static const double graphLaneOrigin = 9;
  static const double graphCommitRadius = 4.5;
  static const double graphRingStroke = 2;
  static const double graphStrokeLit = 2.5;
  static const double graphHeadInnerRadius = 4;
  static const double graphHeadOuterRadius = 7;
  static const double graphHeadOuterStroke = 1.5;
  static const double graphMergeDotRadius = 1.75;
  static const double graphDash = 2.2;
  static const double graphBoundarySquare = 7;
  static const double graphBoundaryStroke = 1.5;
  static const double graphNodeInkRadius = 8;
  static const double graphNodeHitWidth = 14;
  static const int graphMaxRefChips = 2;

  // Diff (specs/changes-and-diff.md)
  static const double diffLineHeight = 18;
  static const double diffGutterWidth = 44;
  static const double diffSignWidth = 18;
  static const double hunkHeaderHeight = 30;
  static const double diffFallbackHeight = 180;
  static const double diffPickRail = 3;
  static const double diffWrapIndent = 106;
  static const double diffMinCodeUnified = 280;
  static const double diffMinCodeSplit = 220;

  /// Below this toolbar width the diff toolbar drops its path label (the
  /// file header above names it) so the controls keep their room.
  static const double diffToolbarPathMinWidth = 720;

  /// The diff toolbar's path label: this share of the toolbar, kept between
  /// [diffToolbarPathMinLabelWidth] and [diffToolbarPathMaxWidth].
  static const double diffToolbarPathWidthFraction = 0.23;
  static const double diffToolbarPathMinLabelWidth = 64;
  static const double diffToolbarPathMaxWidth = 180;
  static const double diffMinimapWidth = 8;
  static const double blameBandWidth = 180;
  static const double blameDetailStripHeight = 38;

  // Floating surfaces (.ns-dialog, .ns-palette, .ns-logbook, specs/workflows.md)
  static const double remoteHostListMaxHeight = 220;
  static const double remoteDirectoryListHeight = 260;
  static const double remoteHostBadgeMaxWidth = 260;

  /// How many of a group's tabs the group editor's preview shows.
  static const int tabGroupPreviewTabs = 3;

  static const double paletteWidth = 600;

  /// The repository details the Compass opens; never narrower than the
  /// Compass it grows from.
  static const double repositoryDetailsWidth = 520;

  /// The tile that shows the repository's kind and health in its header.
  static const double repositoryDetailsTileSize = 44;
  static const double repositoryDetailsTileIconSize = 22;

  /// Below this width per tile the branch, upstream and changes stack.
  static const double repositoryDetailsStatMinWidth = 140;
  static const double repositoryDetailsStatMinHeight = 76;

  /// The Changes section header's mode toggle, discard group, divider and
  /// staging group.
  static const double changesHeaderActionsMaxWidth = 300;
  static const double paletteQueryHeight = 48;
  static const double paletteMaxHeightFraction = 0.7;
  static const double overlayMaxHeightFraction = 0.8;

  /// The most of the inspector the commit summary takes before its message
  /// scrolls.
  static const double commitSummaryMaxHeightFraction = 0.5;
  static const double logbookWidth = 420;
  static const double logbookMarkSize = 20;
  static const double logbookMarkIconSize = 12;
  static const double logbookRailWidth = 2;
  static const double dragThreshold = 6;

  // Composer (.ns-composer)
  static const double composerSubjectHeight = 32;
  static const int composerDescriptionMinLines = 2;
  static const int composerDescriptionMaxLines = 5;
  static const int subjectGuide = 50;
  static const int subjectLimit = 72;

  // Workflows (specs/workflows.md)
  static const double rebaseIndent = 14;
  static const double rebaseActionWidth = 96;
  static const double conflictFileListWidth = 220;
  static const double conflictFileListMinWidth = 180;
  static const double conflictEditorMinWidth = 320;
  static const double conflictWideEditorMinWidth = 840;
  static const double conflictResultCompactHeight = 220;
  static const double conflictSourceActionMinWidth = 400;
  static const double conflictDetailsMaxHeight = 180;
  static const double conflictRail = 3;
  static const double conflictRegionToolbarHeight = 42;
  static const double conflictLineColumnWidth = 34;
  static const double resultMinHeightFraction = 0.4;
  static const double reviewCommentRailWidth = 280;
  static const double reviewDrawerBreakpoint = 1280;
  static const double reviewDrawerWidth = 360;
  static const double welcomeMarkSize = 64;

  /// The app mark at the top of About.
  static const double aboutMarkSize = 96;
  static const double launchMarkSize = 128; // matches the macOS launch cover
  static const double resolvedStateIconSize = 40;

  // Floating tool panels (plan decision 2.7), anchored space-2 below the
  // tab strip and space-3 from the window's right edge.
  static const double snapshotsPanelWidth = 620;
  static const double extensionsPanelWidth = 680;
  static const double integrationsPanelWidth = 720;
  static const double powerToolsPanelWidth = 720;
  static const double extensionsBodyMaxHeight = 436;

  // Preferred body heights of the floating panels; a short window gets less
  // (floatingPanelBodyHeight).
  static const double recoveryBodyHeight = 456;
  static const double snapshotsBodyHeight = 576;
  static const double powerToolsBodyHeight = 640;
  static const double integrationsBodyHeight = 676;

  /// Repository tools docked above History: at most this tall, and at most
  /// [powerToolsDockedHeightFraction] of the window.
  static const double powerToolsDockedMaxHeight = 280;
  static const double powerToolsDockedHeightFraction = 0.35;

  // Bounded output and preview areas
  static const double commandDetailsMaxHeight = 240;
  static const double logbookOutputMaxHeight = 180;
  static const double activityHeight = 170;
  static const double activityOutputMaxHeight = 120;
  static const double commitFailureOutputMaxHeight = 160;
  static const double previewDialogBodyHeight = 520;
  static const double rebaseTargetListHeight = 320;

  /// About seven rows of a dialog's file, commit, branch or step list.
  static const double dialogListMaxHeight = 232;

  /// About eight instructions in the interactive rebase editor.
  static const double rebaseInstructionListMaxHeight = 360;
  static const double shortcutReferenceBodyHeight = 520;

  // Fields and labels
  static const double shortFieldWidth = 180;
  static const double shortcutFieldWidth = 210;
  static const double trackingLabelMaxWidth = 72;
  static const double mergeMessageMaxWidth = 620;
  static const double referenceSuggestionMinWidth = 180;
  static const double referenceSuggestionMaxWidth = 360;
  static const double dropPromptWidth = 420;
  static const double dropTargetBorder = 2;
  static const double refPairDividerHeight = 12;
  static const double historyAuthorWidth = 132; // specs/graph.md §7
  static const double historyMetaSkeletonWidth = 72;

  // Conflict resolver (specs/workflows.md)
  static const double conflictChoiceRail = 2;
  static const double conflictComparisonRowHeight = 25;
  static const double conflictAncestorHeight = 100;
  static const double conflictTitleMinHeight = 40;
  static const double conflictTitleHeight = 32;
  // Unchanged lines kept above a conflict that navigation scrolls to.
  static const int conflictLeadRows = 2;
}

/// Opacity values of GitLama's git components. Shared ones are in
/// `MeridianOpacity`. Use only these with `withValues(alpha:)`.
abstract final class GitLamaOpacity {
  static const double glint = 0.6;
  static const double conflictDivider = 0.45;
  static const double conflictDiff = 0.06;
  static const double conflictChosen = 0.16;
  static const double conflictUnchosen = 0.09;
  static const double conflictRailChosen = 0.78;
  static const double conflictRailUnchosen = 0.48;
  static const double conflictFocus = 0.07;
  static const double conflictHighlight = 0.10;
  static const double conflictHover = 0.24;
  static const double unlit = 0.3; // graph.md lane focus, search dimming
  static const double unlitText = 0.5; // graph.md lane focus, row text
  static const double ignoredRow = 0.6; // changes-and-diff.md ignored files
  static const double headChipUpstream = 0.75; // .ns-ref.head.pair .up
  static const double diffSelectedLine = 0.10; // changes-and-diff.md selection
  static const double diffSelectedText = 0.28; // changes-and-diff.md selection
}

/// GitLama's own timings (docs/design-system/specs/motion.md).
/// Shared durations are in MeridianDurations.
abstract final class GitLamaMotion {
  static const Duration foregroundLogbookDelay = Duration(milliseconds: 300);
  static const Duration laneFocusDelay = Duration(milliseconds: 400);
  static const Duration laneDim = Duration(milliseconds: 180);
  static const Duration laneFlowStep = Duration(milliseconds: 12);
  static const int laneFlowMaxRows = 16;
  static const Duration laneDrawStep = Duration(milliseconds: 10);
  static const Duration laneDrawRow = Duration(milliseconds: 140);
  static const int laneDrawMaxRows = 24;
  static const Duration commitLand = MeridianDurations.highlight;
  static const Duration landRingClose = Duration(milliseconds: 160);
  static const Duration commitTintDelay = Duration(milliseconds: 120);
  static const Duration glint = MeridianDurations.celebrate;

  /// How long typing pauses before the folder picker follows the path.
  static const Duration remotePathFollowDelay = Duration(milliseconds: 250);
  static const Duration syncGlintDelay = Duration(milliseconds: 300);
  static const double glintWidth = 40;
  static const Duration detailDebounce = Duration(milliseconds: 150);
  static const Duration refreshSpinDelay = MeridianDurations.spinnerDelay;
  static const Duration stageWash = MeridianDurations.emphasized;
  static const Duration copiedHold = Duration(milliseconds: 1200);
  static const Duration openStagger = Duration(milliseconds: 40);
  static const Duration pullLanesDelay = Duration(milliseconds: 60);
  static const Duration paletteMorph = Duration(milliseconds: 300);
}
