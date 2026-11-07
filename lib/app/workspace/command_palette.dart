import 'command_availability.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../app_shortcut_activator.dart';
import '../../models/repository_state.dart';
import '../../models/integrations.dart';
import '../app_theme.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';

Future<T?> showCommandPalette<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Rect? originRect,
  bool Function()? ranCommand,
}) {
  if (originRect == null || MeridianMotion.reduced(context)) {
    return showMeridianDialog<T>(context: context, builder: builder);
  }
  final spring = SpringSimulation(MeridianSprings.snappy, 0, 1, 0);
  return showMeridianDialog<T>(
    context: context,
    builder: builder,
    transitionDuration: GitLamaMotion.paletteMorph,
    reverseTransitionDuration: MeridianDurations.dialog,
    transitionBuilder: (context, animation, secondary, child) =>
        AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            if (animation.status == AnimationStatus.reverse &&
                ranCommand?.call() == true) {
              return Opacity(opacity: animation.value, child: child);
            }
            final screen = MediaQuery.sizeOf(context);
            final width = math.min(
              GitLamaLayout.paletteWidth,
              screen.width - 2 * MeridianSpace.space6,
            );
            final height =
                screen.height * GitLamaLayout.paletteMaxHeightFraction;
            final target = Rect.fromCenter(
              center: Offset(screen.width / 2, screen.height / 2),
              width: width,
              height: height,
            );
            final t = animation.status == AnimationStatus.reverse
                ? MeridianCurves.exit.transform(animation.value)
                : spring.x(0.3 * animation.value).clamp(0.0, 1.0);
            final offset = Offset.lerp(
              originRect.center - target.center,
              Offset.zero,
              t,
            )!;
            final scaleX = 1 + (originRect.width / target.width - 1) * (1 - t);
            final scaleY =
                1 + (originRect.height / target.height - 1) * (1 - t);
            final visualRadius =
                originRect.height / 2 * (1 - t) +
                context.meridian.radius.lg * t;
            return _PaletteMotionScope(
              progress: t,
              radius: BorderRadius.all(
                Radius.elliptical(visualRadius / scaleX, visualRadius / scaleY),
              ),
              child: Transform.translate(
                offset: offset,
                child: Transform.scale(
                  alignment: Alignment.center,
                  scaleX: scaleX,
                  scaleY: scaleY,
                  child: child,
                ),
              ),
            );
          },
        ),
  );
}

class _PaletteMotionScope extends InheritedWidget {
  const _PaletteMotionScope({
    required this.progress,
    required this.radius,
    required super.child,
  });
  final double progress;
  final BorderRadius radius;

  @override
  bool updateShouldNotify(_PaletteMotionScope oldWidget) =>
      progress != oldWidget.progress || radius != oldWidget.radius;
}

class CommandPaletteDialog extends StatefulWidget {
  const CommandPaletteDialog({
    super.key,
    required this.hasRepository,
    required this.disabledSelectionCommands,
    required this.shortcuts,
    required this.activeScopes,
    required this.customCommands,
    this.onRun,
    this.availability,
    this.customCommandsDisabledReason,
  });

  final CommandMenuState? availability;
  final bool hasRepository;
  final Set<AppCommandId> disabledSelectionCommands;
  final Map<AppCommandId, AppShortcut?> shortcuts;
  final Set<AppCommandShortcutScope> activeScopes;
  final List<IntegrationDefinition> customCommands;
  final VoidCallback? onRun;

  /// Why custom commands cannot run for the active repository, if so.
  final String? customCommandsDisabledReason;

  bool get _customCommandsEnabled =>
      hasRepository && customCommandsDisabledReason == null;

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  String _query = '';
  bool _running = false;
  int _selectedIndex = 0;
  final ScrollController _resultsController = ScrollController();

  @override
  void dispose() {
    _resultsController.dispose();
    super.dispose();
  }

  final Map<Object, GlobalKey> _rowKeys = {};

  GlobalKey _rowKey(Object id) => _rowKeys.putIfAbsent(id, GlobalKey.new);
  final Object _openingKey = Object();

  void _run(Object command) {
    if (_running) return;
    _running = true;
    widget.onRun?.call();
    Navigator.pop(context, command);
  }

  // One policy decides; without the shell's state, a state built from what
  // the palette knows.
  AppCommandDisabledReason? _reason(AppCommandDefinition command) =>
      (widget.availability ??
              CommandMenuState(
                snapshot: widget.hasRepository
                    ? RepositorySnapshot(
                        revision: BigInt.zero,
                        phase: RepositoryPhase.ready,
                      )
                    : null,
                scopes: widget.activeScopes,
              ))
          .reason(command.id);

  @override
  Widget build(BuildContext context) {
    final commands = AppCommandRegistry.commands
        .where((command) {
          final query = _query.trim().toLowerCase();
          return query.isEmpty ||
              commandLabel(context, command.id).toLowerCase().contains(query);
        })
        .toList(growable: false);
    final query = _query.trim().toLowerCase();
    final customCommands = widget.customCommands
        .where(
          (definition) =>
              query.isEmpty || definition.id.toLowerCase().contains(query),
        )
        .toList(growable: false);
    final colors = context.colors;
    final motion = context
        .dependOnInheritedWidgetOfExactType<_PaletteMotionScope>();
    final progress = motion?.progress ?? 1;
    final results = <Object>[
      ...commands.map((command) => command.id),
      ...customCommands,
    ];
    return MeridianResultNavigation(
      itemCount: results.length,
      selectedIndex: _selectedIndex,
      onSelected: (index) {
        setState(() => _selectedIndex = index);
        // Wrapped commands are outside the lazy viewport. Bring that end
        // into layout before resolving the selected row's exact rectangle.
        if (_resultsController.hasClients) {
          if (index == 0) _resultsController.jumpTo(0);
          if (index == results.length - 1) {
            _resultsController.jumpTo(
              _resultsController.position.maxScrollExtent,
            );
          }
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final rowContext = _rowKeys[results[index]]?.currentContext;
          if (rowContext != null) Scrollable.ensureVisible(rowContext);
        });
      },
      onActivate: (index) {
        if (index < commands.length) {
          final command = commands[index];
          if (_reason(command) != null ||
              widget.disabledSelectionCommands.contains(command.id)) {
            return;
          }
        } else if (!widget._customCommandsEnabled) {
          return;
        }
        _run(results[index]);
      },
      child: MeridianDialogSurface(
        maxWidth: GitLamaLayout.paletteWidth,
        borderRadius:
            motion?.radius ?? BorderRadius.circular(context.meridian.radius.lg),
        child: Opacity(
          opacity: ((progress - 0.2) / 0.8).clamp(0.0, 1.0),
          child: SizedBox(
            width: GitLamaLayout.paletteWidth,
            height:
                MediaQuery.sizeOf(context).height *
                GitLamaLayout.paletteMaxHeightFraction,
            child: Column(
              children: [
                SizedBox(
                  height: GitLamaLayout.paletteQueryHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MeridianSpace.space6,
                    ),
                    child: Row(
                      children: [
                        MeridianIcon('command', color: colors.inkMuted),
                        const SizedBox(width: MeridianSpace.space4),
                        Expanded(
                          child: MeridianTextField(
                            fieldKey: const Key('command-palette-query'),
                            autofocus: true,
                            showLabel: false,
                            placeholder: context.l10n.commandPaletteSearch,
                            onChanged: (value) => setState(() {
                              _query = value;
                              _selectedIndex = 0;
                            }),
                          ),
                        ),
                        // Clear of the field's focus halo.
                        const SizedBox(width: MeridianSpace.space4),
                        const MeridianKbd(keys: ['esc']),
                      ],
                    ),
                  ),
                ),
                MeridianHairline(color: colors.line),
                Expanded(
                  child: commands.isEmpty && customCommands.isEmpty
                      ? MeridianEmptyState(
                          compact: true,
                          title: context.l10n.commandPaletteNoMatch(
                            _query.trim(),
                          ),
                        )
                      : MeridianSurfaceScope(
                          focused: true,
                          child: ListView(
                            controller: _resultsController,
                            padding: const EdgeInsets.all(MeridianSpace.space2),
                            children: [
                              if (commands.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    MeridianSpace.space4,
                                    MeridianSpace.space4,
                                    MeridianSpace.space4,
                                    MeridianSpace.space2,
                                  ),
                                  child: Text(
                                    context.l10n.commandGroupCommands
                                        .toUpperCase(),
                                    style: context.text.overline.copyWith(
                                      color: colors.inkMuted,
                                    ),
                                  ),
                                ),
                              for (
                                var index = 0;
                                index < commands.length;
                                index++
                              )
                                MeridianEntrance(
                                  entranceKey: (
                                    _openingKey,
                                    commands[index].id,
                                  ),
                                  delay: const Duration(milliseconds: 60),
                                  index: math.min(index, 5),
                                  child: Builder(
                                    builder: (context) {
                                      final command = commands[index];
                                      final reason = _reason(command);
                                      final missingSelection = widget
                                          .disabledSelectionCommands
                                          .contains(command.id);
                                      final shortcut =
                                          widget.shortcuts[command.id];
                                      return MeridianListRow(
                                        key: _rowKey(command.id),
                                        leading: MeridianIcon(command.icon),
                                        title: commandLabel(
                                          context,
                                          command.id,
                                        ),
                                        match: _query,
                                        selected: index == _selectedIndex,
                                        subtitle: reason != null
                                            ? workspaceDisabledReason(
                                                context,
                                                reason,
                                              )
                                            : missingSelection
                                            ? context
                                                  .l10n
                                                  .commandContextUnavailable
                                            : null,
                                        trailing: shortcut == null
                                            ? null
                                            : MeridianKbd(
                                                keys: [
                                                  platformShortcutLabel(
                                                    shortcut,
                                                  ),
                                                ],
                                              ),
                                        enabled:
                                            reason == null && !missingSelection,
                                        onTap: () => _run(command.id),
                                      );
                                    },
                                  ),
                                ),
                              if (customCommands.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    MeridianSpace.space4,
                                    MeridianSpace.space4,
                                    MeridianSpace.space4,
                                    MeridianSpace.space2,
                                  ),
                                  child: Text(
                                    context.l10n.integrationCustom
                                        .toUpperCase(),
                                    style: context.text.overline.copyWith(
                                      color: colors.inkMuted,
                                    ),
                                  ),
                                ),
                              for (final (index, definition)
                                  in customCommands.indexed)
                                KeyedSubtree(
                                  key: _rowKey(definition),
                                  child: MeridianListRow(
                                    key: ValueKey(
                                      'command-palette-custom-${definition.id}',
                                    ),
                                    leading: const MeridianIcon('command'),
                                    title: definition.id,
                                    match: _query,
                                    selected:
                                        _selectedIndex ==
                                        commands.length + index,
                                    subtitle:
                                        widget.customCommandsDisabledReason ??
                                        context.l10n.integrationCustom,
                                    enabled: widget._customCommandsEnabled,
                                    onTap: () => _run(definition),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
                MeridianHairline(color: colors.line),
                ColoredBox(
                  color: colors.paneAlt,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MeridianSpace.space6,
                      vertical: MeridianSpace.space4,
                    ),
                    child: Wrap(
                      spacing: MeridianSpace.space6,
                      runSpacing: MeridianSpace.space3,
                      children: [
                        for (final (keys, label) in [
                          (['↑', '↓'], context.l10n.galleryPaletteMove),
                          (['↵'], context.l10n.galleryPaletteRun),
                          (['⌘', '↵'], context.l10n.galleryPaletteBackground),
                          (['tab'], context.l10n.galleryPaletteScope),
                        ])
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MeridianKbd(keys: keys),
                              const SizedBox(width: MeridianSpace.space3),
                              Text(label),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
