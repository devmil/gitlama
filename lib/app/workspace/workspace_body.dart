import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../models/history.dart';
import '../../models/remote_workspace.dart';
import '../../models/workspace.dart';
import 'sidebar.dart';
import 'changes_pane.dart';
import '../inspector/inspector_view.dart';
import '../inspector/pane_inspector_host.dart';
import '../../widgets/git_file_list/git_file_list.dart';
import 'command_availability.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../services/workflows/sync_change_tracker.dart';
import 'shell_scopes.dart';
import 'workspace_scope.dart';
import '../gitlama_layout.dart';

class WorkspaceBody extends StatelessWidget {
  const WorkspaceBody({
    super.key,
    required this.active,
    required this.powerToolsVisible,
    required this.onClosePowerTools,
    required this.onRevealPowerCommit,
    required this.width,
    required this.height,
    required this.commitFileListWidth,
    required this.onCommitFileListWidthChanged,
    required this.compactDetailHeight,
    required this.onCompactDetailHeightChanged,
    required this.onCommand,
    required this.history,
    required this.shortcuts,
    this.openMotionKey,
    this.sync = const SyncChange(),
  });

  final RepositoryTabState? active;
  final bool powerToolsVisible;
  final VoidCallback onClosePowerTools;
  final ValueChanged<String> onRevealPowerCommit;
  final double width;
  final double height;
  final double commitFileListWidth;
  final ValueChanged<double> onCommitFileListWidthChanged;

  /// The height of the Detail island under History; null splits the
  /// workspace evenly.
  final double? compactDetailHeight;
  final ValueChanged<double> onCompactDetailHeightChanged;
  final RunAppCommand onCommand;
  final HistoryState history;
  final Map<AppCommandId, AppShortcut?> shortcuts;
  final Object? openMotionKey;

  /// What the last transfer changed, for History's arriving rows.
  final SyncChange sync;

  @override
  Widget build(BuildContext context) {
    final services = WorkspaceServicesScope.of(context);
    final repositories = services.repositories;
    final settings = services.settings;
    final navigator = services.workflows.navigator;
    final files = FileActionsScope.of(context);
    final inspector = InspectorHostScope.of(context);
    final appearance = settings.current.appearance;
    Widget openEntrance(Widget child, int index) => openMotionKey == null
        ? child
        : MeridianEntrance(
            entranceKey: ('repository-open', openMotionKey, index),
            delay: GitLamaMotion.openStagger * index,
            child: child,
          );
    final compactSidebar =
        width < GitLamaLayout.compactBreakpoint + MeridianSpace.space5;
    final safeSidebarWidth = appearance.sidebarWidth
        .toDouble()
        .clamp(MeridianLayout.sidebarMinWidth, MeridianLayout.sidebarMaxWidth)
        .toDouble();
    final occupiedSidebarWidth = compactSidebar
        ? MeridianLayout.sidebarRailWidth + MeridianSpace.space3
        : safeSidebarWidth + MeridianSpace.space3;
    final conflictActive =
        active?.navigation.pane == WorkspacePane.changes &&
        hasActiveConflicts(active?.session?.snapshot.status);
    final showDetail = !conflictActive;
    final workspaceWidth = math.max(
      0.0,
      width - occupiedSidebarWidth - MeridianSpace.space3,
    );
    final maximumDetailWidth = math.max(
      MeridianLayout.islandMinWidth,
      workspaceWidth - MeridianLayout.islandMinWidth - MeridianSpace.space3,
    );
    final safeDetailWidth = appearance.diffWidth
        .toDouble()
        .clamp(MeridianLayout.islandMinWidth, maximumDetailWidth)
        .toDouble();
    final maximumCompactDetailHeight = math.max(
      180.0,
      height - GitLamaLayout.primaryIslandMinHeight - MeridianSpace.space3,
    );
    final safeCompactDetailHeight =
        (compactDetailHeight ?? (height - MeridianSpace.space3) / 2)
            .clamp(180.0, maximumCompactDetailHeight)
            .toDouble();
    final primary = PrimaryPane(
      active: active,
      powerToolsVisible: powerToolsVisible,
      onClosePowerTools: onClosePowerTools,
      onRevealPowerCommit: onRevealPowerCommit,
      onCommand: onCommand,
      history: history,
      sync: sync,
      shortcuts: shortcuts,
      changesFilePaneWidth: safeDetailWidth,
      onChangesFilePaneWidthChanged: (width) => settings.updateAppearance(
        (appearance) =>
            appearance.copyWith(diffWidth: width.round().clamp(240, 8192)),
      ),
    );
    final shownDetail = active?.navigation.selectedIdentity;
    final maximized =
        inspector.maximized && active?.navigation.pane == WorkspacePane.history;
    final detail = active?.navigation.pane != WorkspacePane.history
        ? Column(
            children: [
              detailSectionHeader(context),
              Expanded(
                child: MeridianEmptyState(
                  compact: true,
                  icon: 'inspect',
                  title: context.l10n.workspaceNoSelection,
                ),
              ),
            ],
          )
        : InspectorView(
            service: repositories.inspector,
            host: PaneInspectorHost(
              historyService: repositories.history,
              repositoryIdentity: active?.canonicalIdentity,
              // A repository on another computer opens its inspector
              // windows through this window's connection to its host.
              inspectionWindows: services.inspectionWindows,
              repositories: repositories,
              inspectionOpenIn: appearance.inspectionOpenIn,
              fileBrowserName: files.fileBrowserName,
              maximized: maximized,
              onToggleMaximize: inspector.onToggleMaximized,
              onOpenFile: files.openExternal,
              onRevealFile: files.revealInFileBrowser,
              onCreatePatch: inspector.onCreatePatch,
              onSaveArchive: (commit) => onCommand(
                AppCommandId.saveCommitArchive,
                initialTarget: commit,
              ),
              onOpenWindowFailed: inspector.onOpenWindowFailed,
              remote: active?.canonicalIdentity?.isRemote ?? false,
              remoteConnected:
                  CommandAvailabilityScope.read(context)?.remote?.connected ??
                  true,
              restoreAllowed:
                  CommandAvailabilityScope.read(
                    context,
                  )?.remote?.allows(RemoteCapability.recovery) ??
                  true,
            ),
            shortcuts: shortcuts,
            diffRenderer: settings.current.diffRenderer,
            filesHidden: inspector.filesHidden,
            handleShortcuts: false,
            sidebarWidth: commitFileListWidth,
            onSidebarWidthChanged: onCommitFileListWidthChanged,
            filesMode: GitFileListMode.values.byName(
              appearance.commitFilesMode,
            ),
            onFilesModeChanged: (mode) => settings.updateAppearance(
              (appearance) => appearance.copyWith(commitFilesMode: mode.name),
            ),
          );
    final changesActive = active?.navigation.pane == WorkspacePane.changes;
    final workspace = changesActive && active?.session?.snapshot.status != null
        ? openEntrance(primary, 1)
        : !showDetail
        ? openEntrance(MeridianIsland(expandChild: true, child: primary), 1)
        // History keeps the full width above; details and the diff below.
        : Column(
            children: [
              if (maximized)
                // The graph stays mounted at its full size, so its scroll
                // position and selection survive the maximized inspector.
                SizedBox(
                  height: 0,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: 0,
                    maxHeight: height,
                    child: Offstage(
                      child: MeridianIsland(expandChild: true, child: primary),
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: openEntrance(
                    MeridianIsland(expandChild: true, child: primary),
                    1,
                  ),
                ),
                paneSplitter(
                  context,
                  key: const ValueKey('detail-pane-splitter'),
                  axis: Axis.horizontal,
                  label: context.l10n.workspaceResizeDetail,
                  value: safeCompactDetailHeight,
                  onDrag: (delta) => onCompactDetailHeightChanged(
                    safeCompactDetailHeight - delta,
                  ),
                  onIncrease: () => onCompactDetailHeightChanged(
                    safeCompactDetailHeight + 32,
                  ),
                  onDecrease: () => onCompactDetailHeightChanged(
                    safeCompactDetailHeight - 32,
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                height: maximized
                    ? height - MeridianSpace.space3
                    : safeCompactDetailHeight,
                child: openEntrance(
                  MeridianIsland(
                    key: const ValueKey('detail-pane'),
                    contentKey: shownDetail,
                    expandChild: true,
                    child: detail,
                  ),
                  2,
                ),
              ),
            ],
          );
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        end: MeridianSpace.space3,
        bottom: MeridianSpace.space3,
      ),
      child: Row(
        children: [
          if (compactSidebar)
            SizedBox(
              key: const ValueKey('sidebar-rail'),
              width: MeridianLayout.sidebarRailWidth,
              child: SidebarRail(
                pane: active?.navigation.pane,
                onSelectPane: navigator.selectPane,
              ),
            )
          else
            Expanded(
              // The shell clamps the width itself; the split pane adds no
              // minimums of its own.
              child: MeridianSplitPane(
                extent: safeSidebarWidth,
                onExtentChanged: (width) => settings.updateAppearance(
                  (appearance) => appearance.copyWith(
                    sidebarWidth: width.round().clamp(
                      MeridianLayout.sidebarMinWidth.toInt(),
                      MeridianLayout.sidebarMaxWidth.toInt(),
                    ),
                  ),
                ),
                firstMinExtent: 0,
                secondMinExtent: 0,
                keyboardStep: GitLamaLayout.paneResizeStep,
                focusable: false,
                semanticLabel: context.l10n.workspaceResizeSidebar,
                handleKey: const ValueKey('sidebar-pane-splitter'),
                second: workspace,
                first: openEntrance(
                  WorkspaceSidebar(
                    active: active,
                    pane: active?.navigation.pane,
                    onCommand: onCommand,
                    shortcuts: shortcuts,
                  ),
                  0,
                ),
              ),
            ),
          if (compactSidebar) Expanded(child: workspace),
        ],
      ),
    );
  }
}

Widget paneSplitter(
  BuildContext context, {
  required Key key,
  required Axis axis,
  required String label,
  required double value,
  required ValueChanged<double> onDrag,
  required VoidCallback onIncrease,
  required VoidCallback onDecrease,
  VoidCallback? onReset,
}) {
  final vertical = axis == Axis.vertical;
  // Meridian's handle shows where to drag (its rule on hover and while
  // dragging); the splitter keeps its adjustable semantics and stays out of
  // the Tab order.
  return Semantics(
    label: label,
    value: '${value.round()}',
    increasedValue: '${(value + 32).round()}',
    decreasedValue: '${math.max(0, value - 32).round()}',
    onIncrease: onIncrease,
    onDecrease: onDecrease,
    child: ExcludeSemantics(
      child: ExcludeFocus(
        child: SizedBox(
          width: vertical ? MeridianSpace.space3 : double.infinity,
          height: vertical ? double.infinity : MeridianSpace.space3,
          child: MeridianResizeHandle(
            key: key,
            semanticLabel: label,
            direction: vertical ? Axis.horizontal : Axis.vertical,
            onDrag: onDrag,
            onReset: onReset,
          ),
        ),
      ),
    ),
  );
}
