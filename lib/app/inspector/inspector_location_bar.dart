part of 'inspector_view.dart';

/// Back, Forward, the breadcrumb, the lens switch and the host actions.
class _InspectorLocationBar extends StatelessWidget {
  const _InspectorLocationBar({
    required this.state,
    required this.service,
    required this.host,
    required this.actions,
    required this.sidebarHidden,
    required this.onToggleSidebar,
    required this.onRevealDirectory,
  });

  final InspectorState state;
  final InspectorService service;
  final InspectorHost host;
  final InspectorFileActions actions;
  final bool sidebarHidden;
  final VoidCallback onToggleSidebar;
  final ValueChanged<List<int>> onRevealDirectory;

  Future<void> _historyMenu(
    BuildContext context,
    Offset position, {
    required bool back,
  }) async {
    final entries = back ? state.backLocations : state.forwardLocations;
    if (entries.isEmpty) return;
    final selected = await showNativeMenuItems<int>(
      context: context,
      position: position,
      items: [
        for (var index = 0; index < entries.length; index += 1)
          NativeMenuItem(
            value: back ? -(index + 1) : index + 1,
            title: inspectorLabel(context, entries[index]),
          ),
      ],
    );
    if (selected != null) unawaited(service.jump(selected));
  }

  Widget _navigationButton(BuildContext context, {required bool back}) {
    final enabled = back ? state.canBack : state.canForward;
    Future<void> menu(Offset position) =>
        _historyMenu(context, position, back: back);
    return GestureDetector(
      onSecondaryTapUp: (details) => unawaited(menu(details.globalPosition)),
      onLongPressStart: (details) => unawaited(menu(details.globalPosition)),
      child: MeridianIconButton(
        key: ValueKey(back ? 'inspector-back' : 'inspector-forward'),
        label: back
            ? context.l10n.historyNavigateBack
            : context.l10n.historyNavigateForward,
        icon: back ? 'back' : 'forward',
        onPressed: enabled
            ? () => unawaited(back ? service.back() : service.forward())
            : null,
      ),
    );
  }

  List<MeridianBreadcrumb> _crumbs(BuildContext context) {
    final location = state.location!;
    final target = location.target;
    final detail = state.inspection?.detail;
    final subject = detail == null
        ? ''
        : utf8
              .decode(detail.message, allowMalformed: true)
              .trim()
              .split('\n')
              .first;
    final tokens = context.meridian;
    final crumbs = <MeridianBreadcrumb>[
      MeridianBreadcrumb(
        label: switch (target) {
          ComparisonTarget(:final base, :final commit) =>
            '${shortObjectId(base)} → ${shortObjectId(commit)}',
          CommitTarget() =>
            subject.isEmpty ? shortObjectId(target.commit) : subject,
        },
        mono: target is ComparisonTarget,
        semanticLabel: target is ComparisonTarget
            ? null
            : '${shortObjectId(target.commit)} $subject',
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MeridianIcon(
              'git-commit-horizontal',
              size: MeridianIconSize.small,
            ),
            if (target is CommitTarget) ...[
              const SizedBox(width: MeridianSpace.space2),
              Text(
                shortObjectId(target.commit),
                style: context.text.codeSm.copyWith(
                  color: tokens.colors.inkMuted,
                ),
              ),
            ],
          ],
        ),
        onActivate: location.path == null
            ? null
            : () => unawaited(
                service.navigate(location.copyWith(clearPath: true)),
              ),
        onContextMenu: (position) =>
            unawaited(_targetMenu(context, position, target)),
      ),
    ];
    final path = location.path;
    if (path != null) {
      final parts = <List<int>>[];
      var start = 0;
      for (var index = 0; index <= path.length; index += 1) {
        if (index == path.length || path[index] == 0x2f) {
          if (index > start) parts.add(path.sublist(0, index));
          start = index + 1;
        }
      }
      for (var index = 0; index < parts.length; index += 1) {
        final part = parts[index];
        final last = index == parts.length - 1;
        final name = inspectorFileName(part);
        crumbs.add(
          MeridianBreadcrumb(
            label: name,
            emphasis: last,
            leading: last && location.directory
                ? const MeridianIcon(
                    'folder-open',
                    size: MeridianIconSize.small,
                  )
                : null,
            onActivate: last ? null : () => onRevealDirectory(part),
            onContextMenu: last
                ? (position) => unawaited(_fileMenu(context, position))
                : null,
          ),
        );
      }
    }
    return crumbs;
  }

  FileActionSubject? _focusSubject() {
    final location = state.location;
    final path = location?.path;
    if (location == null || path == null) return null;
    if (location.directory) {
      return FileActionSubject(
        source: FileActionSource.folder,
        path: path,
        revision: location.target.commit,
      );
    }
    for (final file in state.inspection?.files ?? const <CommitFileChange>[]) {
      if (sameBytes(file.newPath.isEmpty ? file.oldPath : file.newPath, path)) {
        return changedFileSubject(file, location.target);
      }
    }
    return FileActionSubject(
      source: FileActionSource.treeFile,
      path: path,
      revision: location.target.commit,
    );
  }

  Future<void> _fileMenu(BuildContext context, Offset position) async {
    final focus = _focusSubject();
    if (focus == null) return;
    final subject = await actions.resolve(focus);
    if (!context.mounted) return;
    final command = await showNativeMenuItems<FileActionCommand>(
      context: context,
      position: position,
      items: buildFileActionItems(context, subject, actions),
    );
    if (command != null) {
      actions.run(command, subject, invert: inspectionModifierPressed());
    }
  }

  Future<void> _targetMenu(
    BuildContext context,
    Offset position,
    InspectorTarget target,
  ) async {
    final selected = await showNativeMenuItems<_TargetAction>(
      context: context,
      position: position,
      items: [
        NativeMenuItem(
          value: _TargetAction.copy,
          title: context.l10n.fileActionCopyCommitHash,
          icon: 'copy',
        ),
        if (host.canShowInGraph)
          NativeMenuItem(
            value: _TargetAction.graph,
            title: host.isWindow
                ? context.l10n.inspectorShowInMainWindow
                : context.l10n.inspectorShowInGraph,
            icon: 'locate',
          ),
        if (host.supportsWindows)
          NativeMenuItem(
            value: _TargetAction.window,
            title: context.l10n.inspectorOpenInWindow,
            icon: 'app-window',
          ),
      ],
    );
    switch (selected) {
      case _TargetAction.copy:
        if (!context.mounted) return;
        await copyWithStatusNotification(
          context,
          target.commit,
          context.l10n.menuCommitHashCopied,
        );
      case _TargetAction.graph:
        await host.showInGraph(target);
      case _TargetAction.window:
        await host.openInWindow(InspectorLocation(target: target));
      case null:
        break;
    }
  }

  Future<void> _overflow(BuildContext context, Object value) async {
    final location = state.location!;
    if (value is FileActionCommand) {
      final subject = _focusSubject();
      if (subject != null) {
        actions.run(value, subject, invert: inspectionModifierPressed());
      }
      return;
    }
    switch (value as _OverflowAction) {
      case _OverflowAction.allFiles:
        unawaited(service.browseAllFiles());
      case _OverflowAction.toggleFiles:
        onToggleSidebar();
      case _OverflowAction.copyHash:
        await copyWithStatusNotification(
          context,
          location.target.commit,
          context.l10n.menuCommitHashCopied,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // The focused file as its menu found it when it opened.
    FileActionSubject? resolvedFocus;
    final location = state.location!;
    final path = location.path;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Semantics(
      container: true,
      label: context.l10n.inspectorLocation,
      child: Container(
        key: const ValueKey('inspector-location-bar'),
        height: MeridianSize.islandHeader + MeridianSpace.space3,
        padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space3),
        color: context.colors.pane,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760 || narrow;
            return Row(
              children: [
                _navigationButton(context, back: true),
                _navigationButton(context, back: false),
                const SizedBox(width: MeridianSpace.space2),
                Expanded(
                  child: MeridianBreadcrumbs(
                    key: const ValueKey('inspector-breadcrumbs'),
                    semanticLabel: context.l10n.inspectorLocation,
                    crumbs: _crumbs(context),
                    onOverflow: (hidden, position) async {
                      final index = await showNativeMenuItems<int>(
                        context: context,
                        position: position,
                        items: [
                          for (var item = 0; item < hidden.length; item += 1)
                            NativeMenuItem(
                              value: item,
                              title: hidden[item].label,
                              enabled: hidden[item].onActivate != null,
                            ),
                        ],
                      );
                      if (index != null) hidden[index].onActivate?.call();
                    },
                  ),
                ),
                if (path != null) ...[
                  const SizedBox(width: MeridianSpace.space3),
                  MeridianSegmented<InspectorLens>(
                    key: const ValueKey('inspector-lens'),
                    label: context.l10n.inspectorLenses,
                    size: MeridianControlSize.small,
                    segments: [
                      for (final lens in InspectorLens.values)
                        MeridianSegment(
                          value: lens,
                          icon: _lensIcon(lens),
                          label: compact
                              ? null
                              : inspectorLensName(context, lens),
                          enabled: state.lensAvailability[lens] == null,
                          tooltip: switch (state.lensAvailability[lens]) {
                            final reason? => lensUnavailableText(
                              context,
                              reason,
                            ),
                            null => inspectorLensName(context, lens),
                          },
                        ),
                    ],
                    value: location.lens,
                    onChanged: (lens) {
                      if (lens == location.lens) return;
                      unawaited(
                        inspectLocation(
                          service,
                          host,
                          location.copyWith(
                            lens: lens,
                            anchor: 0,
                            clearLines: true,
                            clearHistoryCommit: true,
                          ),
                          invert: lens == InspectorLens.diff
                              ? false
                              : inspectionModifierPressed(),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(width: MeridianSpace.space2),
                if (host.isWindow)
                  MeridianIconButton(
                    key: const ValueKey('inspector-show-in-main-window'),
                    label: context.l10n.inspectorShowInMainWindow,
                    icon: 'locate',
                    disabledReason: host.canShowInGraph
                        ? null
                        : context.l10n.inspectorRepositoryNotOpen,
                    onPressed: host.canShowInGraph
                        ? () => unawaited(host.showInGraph(location.target))
                        : null,
                  ),
                if (host.supportsWindows || host.windowsDisconnected)
                  MeridianIconButton(
                    key: const ValueKey('inspector-open-window'),
                    label: context.l10n.inspectorOpenInWindow,
                    icon: 'app-window',
                    disabledReason: host.supportsWindows
                        ? null
                        : context.l10n.remoteCommandDisconnected,
                    onPressed: host.supportsWindows
                        ? () => unawaited(host.openInWindow(location))
                        : null,
                  ),
                if (host.canMaximize)
                  MeridianIconButton(
                    key: const ValueKey('inspector-maximize'),
                    label: host.maximized
                        ? context.l10n.inspectorRestoreLayout
                        : context.l10n.inspectorMaximize,
                    icon: host.maximized ? 'minimize-2' : 'maximize-2',
                    active: host.maximized,
                    onPressed: host.toggleMaximize,
                  ),
                NativeMenuButton<Object>(
                  key: const ValueKey('inspector-more'),
                  tooltip: context.l10n.inspectorMoreActions,
                  onSelected: (value) => unawaited(_overflow(context, value)),
                  beforeOpen: () async {
                    final focus = _focusSubject();
                    resolvedFocus = focus == null
                        ? null
                        : await actions.resolve(focus);
                  },
                  itemBuilder: (context) {
                    final subject = resolvedFocus ?? _focusSubject();
                    return [
                      if (canBrowseAllFiles(location))
                        NativeMenuItem<Object>(
                          value: _OverflowAction.allFiles,
                          title: context.l10n.inspectorBrowseAllFiles,
                          icon: 'tree-view',
                        ),
                      NativeMenuItem<Object>(
                        value: _OverflowAction.toggleFiles,
                        title: sidebarHidden
                            ? context.l10n.inspectorShowFiles
                            : context.l10n.inspectorHideFiles,
                        icon: 'panel-left',
                      ),
                      NativeMenuItem<Object>(
                        value: _OverflowAction.copyHash,
                        title: context.l10n.fileActionCopyCommitHash,
                        icon: 'copy',
                      ),
                      if (subject != null) ...[
                        const NativeMenuItem<Object>.separator(),
                        NativeMenuItem<Object>.header(
                          inspectorFileName(subject.path),
                        ),
                        for (final item in buildFileActionItems(
                          context,
                          subject,
                          actions,
                        ))
                          _asObjectItem(item),
                      ],
                    ];
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

NativeMenuItem<Object> _asObjectItem(NativeMenuItem<FileActionCommand> item) {
  if (item.separator) return const NativeMenuItem<Object>.separator();
  if (item.header) return NativeMenuItem<Object>.header(item.title);
  return NativeMenuItem<Object>(
    value: item.value!,
    title: item.title,
    icon: item.icon,
    enabled: item.enabled,
    disabledReason: item.disabledReason,
    danger: item.danger,
  );
}

enum _OverflowAction { allFiles, toggleFiles, copyHash }

enum _TargetAction { copy, graph, window }
