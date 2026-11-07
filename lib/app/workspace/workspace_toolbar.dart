import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../app_shortcut_activator.dart';
import '../../models/operation_center.dart';
import '../../models/repository_state.dart';
import '../../models/workspace.dart';
import '../../widgets/gitlama_compass.dart';
import '../../widgets/gitlama_window_caption.dart';
import '../app_theme.dart';
import 'sidebar.dart';
import 'command_availability.dart';
import 'command_menus.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';

class WorkspaceToolbar extends StatelessWidget {
  const WorkspaceToolbar({
    super.key,
    required this.active,
    this.repositoryLabel,
    required this.onCommand,
    this.onOpenPalette,
    required this.operations,
    required this.operationsVisible,
    required this.activityVisible,
    required this.shortcuts,
    required this.compassKey,
    this.paletteButtonKey,
    this.onShowDetails,
    this.detailsOpen = false,
    this.refreshing = false,
    this.syncSequence = 0,
    this.syncChanged = false,
    this.paletteOpen = false,
    this.repositoryBusy = false,
  });

  final RepositoryTabState? active;

  /// The active tab's name as the compass shows it; defaults to its label.
  final String? repositoryLabel;

  /// An operation blocks the active repository: its commands wait.
  final bool repositoryBusy;
  final RunAppCommand onCommand;
  final VoidCallback? onOpenPalette;

  /// Opens the active repository's details from the Compass.
  final VoidCallback? onShowDetails;

  /// The Compass has grown into the details overlay: it hides meanwhile.
  final bool detailsOpen;
  final OperationCenterSnapshot operations;

  /// A refresh has run longer than `refreshSpinDelay`: its icon spins
  /// (NM-11).
  final bool refreshing;
  final int syncSequence;
  final bool syncChanged;
  final bool paletteOpen;
  final bool operationsVisible;
  final bool activityVisible;
  final Map<AppCommandId, AppShortcut?> shortcuts;
  final GlobalKey compassKey;

  /// The Commands button beside the Compass, where the palette opens from.
  final GlobalKey? paletteButtonKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth <= GitLamaLayout.compactBreakpoint;
      final hasRepository = active?.session != null;
      final status = active?.session?.snapshot.status;
      final head = checkedOut(context, active?.session?.snapshot);
      final foreground = operations.entries
          .where(
            (entry) =>
                entry.origin == OperationCenterOrigin.user &&
                entry.state == OperationCenterState.running,
          )
          .firstOrNull;
      final runningOperation =
          foreground ??
          operations.entries
              .where((entry) => entry.state == OperationCenterState.running)
              .firstOrNull;
      final progress = runningOperation?.progress;
      final commandSlot =
          context.meridian.density.controlExtent + MeridianSpace.space2;
      Widget action(
        AppCommandId id, {
        int? badge,
        String? label,
        String? icon,
      }) {
        final definition = AppCommandRegistry.byId(id);
        final reason =
            (CommandAvailabilityScope.read(context) ??
                    CommandMenuState(
                      snapshot: active?.session?.snapshot,
                      busy: repositoryBusy,
                    ))
                .reason(id);
        return MeridianToolbarButton(
          key: ValueKey('toolbar-action-${id.name}'),
          label: label ?? commandLabel(context, id),
          // A shortened caption keeps the full command name as its tooltip.
          tooltip: label == null
              ? null
              : dialogTitle(commandLabel(context, id)),
          icon: icon ?? definition.icon,
          showLabel: !compact,
          badge: badge,
          // Fetch, Pull and Stash nudge down (NM-10).
          nudge: switch (id) {
            AppCommandId.fetch ||
            AppCommandId.pull ||
            AppCommandId.createStash => MeridianNudge.down,
            _ => MeridianNudge.none,
          },
          disabledReason: reason == null
              ? null
              : workspaceDisabledReason(context, reason),
          onPressed: reason == null ? () => onCommand(id) : null,
        );
      }

      Widget iconAction(
        AppCommandId id, {
        required String label,
        required String icon,
        bool active = false,
        bool requiresRepository = false,
        String? tooltip,
        MeridianNudge nudge = MeridianNudge.none,
        bool spinning = false,
        int? badge,
        MeridianCountTone badgeTone = MeridianCountTone.accent,
      }) {
        // Repository actions follow the shared availability, including a
        // remote repository whose connection is down.
        final reason = requiresRepository
            ? CommandAvailabilityScope.read(context)?.reason(id)
            : null;
        return MeridianIconButton(
          label: label,
          icon: icon,
          tooltip: tooltip,
          active: active,
          nudge: nudge,
          spinning: spinning,
          badge: badge,
          badgeTone: badgeTone,
          onGround: true,
          disabledReason: reason == null
              ? null
              : workspaceDisabledReason(context, reason),
          onPressed:
              reason != null ||
                  requiresRepository && (!hasRepository || repositoryBusy)
              ? null
              : () => onCommand(id),
        );
      }

      return Container(
        key: const ValueKey('toolbar-row'),
        height: MeridianSize.toolbar,
        color: context.colors.ground,
        padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space5),
        child: Row(
          children: [
            Row(
              key: const ValueKey('toolbar-leading-group'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (defaultTargetPlatform == TargetPlatform.macOS)
                  const GitLamaWindowDragArea(
                    child: SizedBox(
                      key: ValueKey('macos-titlebar-leading'),
                      width: MeridianLayout.macOSTrafficLightInset,
                      height: MeridianSize.toolbar,
                    ),
                  ),
                if (hasRepository) ...[
                  action(AppCommandId.fetch),
                  const SizedBox(width: MeridianSpace.space1),
                  action(
                    AppCommandId.pull,
                    badge: status != null && status.behind > BigInt.zero
                        ? status.behind.toInt()
                        : null,
                  ),
                  const SizedBox(width: MeridianSpace.space1),
                  _PushSplitButton(
                    enabled: true,
                    busy: repositoryBusy,
                    showLabel: !compact,
                    badge: status != null && status.ahead > BigInt.zero
                        ? status.ahead.toInt()
                        : null,
                    onPush: () => onCommand(AppCommandId.push),
                    onPushOption: (force) =>
                        onCommand(AppCommandId.push, force: force),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: MeridianSpace.space1),
                    action(
                      AppCommandId.createBranch,
                      label: context.l10n.toolbarBranch,
                      icon: 'branch',
                    ),
                    const SizedBox(width: MeridianSpace.space1),
                    action(AppCommandId.createStash),
                  ],
                ],
              ],
            ),
            const SizedBox(width: MeridianSpace.space4),
            Expanded(
              key: const ValueKey('toolbar-compass-slot'),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: GitLamaWindowDragArea(child: SizedBox.expand()),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Balances the Commands button, so the Compass
                        // stays centred in the window.
                        SizedBox(width: commandSlot),
                        Flexible(
                          child: KeyedSubtree(
                            key: const Key('repository-toolbar-context'),
                            child: MeridianAnimatedValue(
                              value: detailsOpen ? 0 : 1,
                              duration: MeridianDurations.exit,
                              builder: (context, opacity, child) => Opacity(
                                opacity: opacity.clamp(0, 1),
                                child: child,
                              ),
                              child: GitLamaCompass(
                                key: compassKey,
                                repository:
                                    repositoryLabel ??
                                    active?.label ??
                                    context.l10n.appTitle,
                                branch: head?.label,
                                detached: head?.detached ?? false,
                                ahead: status?.ahead.toInt() ?? 0,
                                behind: status?.behind.toInt() ?? 0,
                                dirty: status?.totalEntries.toInt() ?? 0,
                                conflicts:
                                    status?.entries
                                        .where((entry) => entry.conflicted)
                                        .length ??
                                    0,
                                operation: foreground == null
                                    ? null
                                    : '${operationActionLabel(context, foreground.action)}…',
                                operationDetail: switch ((
                                  foreground,
                                  operationProgressLabel(
                                    context,
                                    foreground?.progress,
                                  ),
                                )) {
                                  (final running?, final detail?) =>
                                    context.l10n.operationRunningDetail(
                                      operationActionLabel(
                                        context,
                                        running.action,
                                      ),
                                      detail,
                                    ),
                                  _ => null,
                                },
                                activeProgress: runningOperation != null,
                                syncSequence: syncSequence,
                                syncChanged: syncChanged,
                                progress:
                                    progress?.total == null ||
                                        progress!.total == BigInt.zero
                                    ? null
                                    : progress.completed.toDouble() /
                                          progress.total!.toDouble(),
                                compact: compact,
                                onShowDetails:
                                    onShowDetails ??
                                    () => onCommand(
                                      AppCommandId.showRepositoryDetails,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: MeridianSpace.space2),
                        MeridianAnimatedValue(
                          value: paletteOpen ? 0 : 1,
                          duration: MeridianDurations.exit,
                          builder: (context, opacity, child) => Opacity(
                            opacity: opacity.clamp(0, 1),
                            child: child,
                          ),
                          child: KeyedSubtree(
                            key: paletteButtonKey,
                            child: MeridianIconButton(
                              key: const ValueKey('toolbar-command-palette'),
                              label: context.l10n.commandPaletteTitle,
                              icon: 'command',
                              onGround: true,
                              tooltip: switch (shortcuts[AppCommandId
                                  .showCommandPalette]) {
                                final shortcut? =>
                                  context.l10n.commandPaletteShortcutTooltip(
                                    platformShortcutLabel(shortcut),
                                  ),
                                null => context.l10n.commandPaletteTitle,
                              },
                              onPressed:
                                  onOpenPalette ??
                                  () => onCommand(
                                    AppCommandId.showCommandPalette,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: MeridianSpace.space4),
            Row(
              key: const ValueKey('toolbar-trailing-group'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!compact)
                  iconAction(
                    AppCommandId.refreshRepository,
                    label: context.l10n.workspaceRefresh,
                    icon: 'refresh',
                    tooltip: context.l10n.workspaceRefreshLocalHint,
                    requiresRepository: true,
                    nudge: MeridianNudge.rotate,
                    spinning: refreshing,
                  ),
                // Running work, or failures in `attention`, as a badge
                // (NM-12).
                iconAction(
                  AppCommandId.showOperations,
                  label: context.l10n.logbookTitle,
                  icon: 'history',
                  active: operationsVisible,
                  badge: operations.failedCount > 0
                      ? operations.failedCount
                      : operations.runningCount > 0
                      ? operations.runningCount
                      : null,
                  badgeTone: operations.failedCount > 0
                      ? MeridianCountTone.attention
                      : MeridianCountTone.accent,
                ),
                if (!compact) ...[
                  iconAction(
                    AppCommandId.showActivity,
                    label: context.l10n.workspaceActivity,
                    icon: 'list-view',
                    active: activityVisible,
                  ),
                  iconAction(
                    AppCommandId.showSettings,
                    label: context.l10n.settingsTitle,
                    icon: 'settings',
                  ),
                ],
                _ToolbarOverflow(
                  active: active,
                  shortcuts: shortcuts,
                  hasRepository: hasRepository,
                  repositoryBusy: repositoryBusy,
                  onCommand: onCommand,
                ),
                if (defaultTargetPlatform == TargetPlatform.macOS)
                  const GitLamaWindowDragArea(
                    child: SizedBox(
                      key: ValueKey('macos-titlebar-trailing-drag'),
                      width: GitLamaLayout.titleBarDragWidth,
                      height: MeridianSize.toolbar,
                    ),
                  ),
                // Linux hides the GTK title bar; its window buttons follow
                // the toolbar actions.
                const GitLamaWindowControls(),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _PushSplitButton extends StatelessWidget {
  const _PushSplitButton({
    required this.enabled,
    required this.onPush,
    required this.onPushOption,
    this.showLabel = true,
    this.badge,
    this.busy = false,
  });

  final bool enabled;

  /// An operation blocks the repository.
  final bool busy;
  final VoidCallback onPush;
  final ValueChanged<bool> onPushOption;
  final bool showLabel;

  /// Commits the branch is ahead of its upstream, like Pull's behind count.
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final reason =
        (CommandAvailabilityScope.read(context) ??
                CommandMenuState(
                  snapshot: enabled
                      ? RepositorySnapshot(
                          revision: BigInt.zero,
                          phase: RepositoryPhase.ready,
                        )
                      : null,
                  busy: busy,
                ))
            .reason(AppCommandId.push);
    // The menu items stay native menu data; the toolbar button's caret
    // shows them through the app's native menu presenter.
    final items = <NativeMenuItem<bool>>[
      NativeMenuItem(value: false, title: context.l10n.commandPush),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        value: true,
        title: context.l10n.transferForceWithLease,
        danger: true,
      ),
    ];
    return KeyedSubtree(
      key: const ValueKey('push-split-button'),
      child: MeridianToolbarButton(
        key: const ValueKey('push-primary'),
        label: context.l10n.commandPush,
        icon: AppCommandRegistry.byId(AppCommandId.push).icon,
        showLabel: showLabel,
        badge: badge,
        nudge: MeridianNudge.up,
        onPressed: reason == null ? onPush : null,
        disabledReason: reason == null
            ? null
            : workspaceDisabledReason(context, reason),
        menu: _meridianMenuEntries(items, onPushOption),
        menuLabel: context.l10n.pushOptions,
      ),
    );
  }
}

/// Native menu [items] as Meridian menu entries; selecting an available
/// item calls [onSelected] with its value.
List<MeridianMenuEntry> _meridianMenuEntries<T>(
  List<NativeMenuItem<T>> items,
  ValueChanged<T> onSelected,
) => [
  for (final item in items)
    if (item.separator)
      const MeridianMenuDivider()
    else if (item.header)
      MeridianMenuHeader(item.title)
    else if (item.children case final children?)
      MeridianMenuItem(
        label: item.title,
        icon: item.icon,
        children: _meridianMenuEntries(children, onSelected),
      )
    else
      MeridianMenuItem(
        label: item.shownTitle,
        icon: item.icon,
        checked: item.checked,
        danger: item.danger,
        onSelected: switch (item.value) {
          final T value when item.available => () => onSelected(value),
          _ => null,
        },
      ),
];

class _ToolbarOverflow extends StatelessWidget {
  const _ToolbarOverflow({
    required this.active,
    required this.shortcuts,
    required this.hasRepository,
    required this.onCommand,
    this.repositoryBusy = false,
  });

  final RepositoryTabState? active;
  final Map<AppCommandId, AppShortcut?> shortcuts;
  final bool hasRepository;
  final bool repositoryBusy;
  final RunAppCommand onCommand;

  @override
  Widget build(BuildContext context) => NativeMenuButton<AppCommandId>(
    key: const Key('toolbar-overflow'),
    tooltip: context.l10n.toolbarMore,
    onSelected: onCommand,
    itemBuilder: (context) => workspaceCommandMenu(
      context,
      state:
          CommandAvailabilityScope.read(context) ??
          CommandMenuState(
            snapshot: active?.session?.snapshot,
            busy: repositoryBusy,
          ),
      shortcuts: shortcuts,
    ),
    child: const SizedBox(
      width: MeridianLayout.toolbarButtonCompactWidth,
      height: MeridianLayout.toolbarButtonHeight,
      child: Center(
        child: MeridianIcon('more', size: MeridianIconSize.toolbar),
      ),
    ),
  );
}
