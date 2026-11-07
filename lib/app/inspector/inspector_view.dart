import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../models/diff_renderer.dart';
import '../../models/inspection.dart';
import '../../models/inspector.dart';
import '../../services/inspector/inspector_service.dart';
import '../../widgets/blame_code_view.dart';
import '../../widgets/commit_file_content_view.dart';
import '../../widgets/find_bar_labels.dart';
import '../../widgets/git_file_list/git_file_list.dart';
import '../../widgets/native_menu.dart';
import '../../widgets/status_notification.dart';
import '../app_theme.dart';
import '../file_actions/file_actions.dart';
import '../gitlama_layout.dart';
import '../app_shortcut_activator.dart';
import '../workspace/labels.dart';
import '../../models/repository_state.dart';
import 'commit_diff_pane.dart';
import 'commit_summary_card.dart';
import 'inspector_actions.dart';
import 'inspector_history.dart';
import 'inspector_host.dart';
import 'inspector_sidebar.dart';
import '../../models/git_names.dart';

part 'inspector_location_bar.dart';

/// The name of a lens.
String inspectorLensName(BuildContext context, InspectorLens lens) =>
    switch (lens) {
      InspectorLens.diff => context.l10n.inspectorLensDiff,
      InspectorLens.contents => context.l10n.inspectorLensContents,
      InspectorLens.blame => context.l10n.historyBlame,
      InspectorLens.history => context.l10n.inspectorLensHistory,
    };

String _lensIcon(InspectorLens lens) => switch (lens) {
  InspectorLens.diff => 'file-diff',
  InspectorLens.contents => 'file-text',
  InspectorLens.blame => 'blame',
  InspectorLens.history => 'history',
};

/// Why a lens cannot show the focused path.
String lensUnavailableText(
  BuildContext context,
  LensUnavailableReason reason,
) => switch (reason) {
  LensUnavailableReason.notChanged => context.l10n.inspectorNotChanged,
  LensUnavailableReason.deleted => context.l10n.inspectorDeletedHere,
  LensUnavailableReason.needsText => context.l10n.inspectorBlameNeedsText,
  LensUnavailableReason.submodule => context.l10n.inspectorSubmoduleNoContents,
  LensUnavailableReason.directory => context.l10n.inspectorFolderOnlyHistory,
};

/// The label of [location] for menus, titles and announcements.
String inspectorLabel(BuildContext context, InspectorLocation location) =>
    inspectorLocationLabel(
      location,
      lensName: (lens) => inspectorLensName(context, lens),
    );

/// One inspector: a location bar with Back and Forward, the commit summary,
/// the file list and the focused file in its lens. The Detail pane and
/// inspector windows both show this widget.
class InspectorView extends StatefulWidget {
  const InspectorView({
    required this.service,
    required this.host,
    required this.shortcuts,
    required this.filesMode,
    required this.onFilesModeChanged,
    required this.sidebarWidth,
    required this.onSidebarWidthChanged,
    this.diffRenderer,
    this.filesHidden,
    this.handleShortcuts = true,
    super.key,
  });

  final InspectorService service;
  final InspectorHost host;
  final Map<AppCommandId, AppShortcut?> shortcuts;
  final GitFileListMode filesMode;
  final ValueChanged<GitFileListMode> onFilesModeChanged;
  final double sidebarWidth;
  final ValueChanged<double> onSidebarWidthChanged;
  final DiffRendererDefinition? diffRenderer;

  /// Whether the file list is hidden, when the host owns that choice.
  final ValueNotifier<bool>? filesHidden;

  /// Binds the inspector commands' shortcuts here. A host whose shell
  /// already dispatches them passes false.
  final bool handleShortcuts;

  @override
  State<InspectorView> createState() => InspectorViewState();
}

class InspectorViewState extends State<InspectorView> {
  late InspectorState _state = widget.service.current;
  StreamSubscription<InspectorState>? _subscription;
  late InspectorFileActions _actions = _createActions();
  final ValueNotifier<bool> _ownHidden = ValueNotifier(false);
  ValueNotifier<bool> get _hidden => widget.filesHidden ?? _ownHidden;
  bool get _sidebarHidden => _hidden.value;
  set _sidebarHidden(bool value) => _hidden.value = value;
  final ValueNotifier<String?> _revealDirectory = ValueNotifier(null);
  String? _announcement;
  InspectorLocation? _announced;

  InspectorFileActions _createActions() => InspectorFileActions(
    context: () => context,
    service: widget.service,
    host: widget.host,
  );

  @override
  void initState() {
    super.initState();
    _subscription = widget.service.states.listen(_changed);
    _hidden.addListener(_hiddenChanged);
  }

  void _hiddenChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant InspectorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      unawaited(_subscription?.cancel());
      _state = widget.service.current;
      _subscription = widget.service.states.listen(_changed);
    }
    if (oldWidget.service != widget.service || oldWidget.host != widget.host) {
      _actions = _createActions();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _hidden.removeListener(_hiddenChanged);
    _ownHidden.dispose();
    _revealDirectory.dispose();
    super.dispose();
  }

  void _changed(InspectorState state) {
    if (!mounted) return;
    setState(() {
      _state = state;
      final location = state.location;
      if (location != null &&
          state.phase == InspectorPhase.ready &&
          !state.contentLoading &&
          !(_announced?.sameAs(location.copyWith(clearHistoryCommit: true)) ??
              false)) {
        _announced = location.copyWith(clearHistoryCommit: true);
        _announcement = context.l10n.inspectorShowing(
          inspectorLabel(context, location),
        );
      }
    });
  }

  InspectorService get _service => widget.service;
  InspectorHost get _host => widget.host;

  /// Runs an inspector command: Back, Forward, a lens or a host action.
  void runCommand(AppCommandId command) {
    final location = _state.location;
    void lens(InspectorLens lens) {
      if (location?.path == null ||
          _state.lensAvailability[lens] != null ||
          location!.lens == lens) {
        return;
      }
      unawaited(
        inspectLocation(
          _service,
          _host,
          location.copyWith(lens: lens, anchor: 0),
          invert: lens == InspectorLens.diff
              ? false
              : inspectionModifierPressed(),
        ),
      );
    }

    switch (command) {
      case AppCommandId.inspectorBack:
        unawaited(_service.back());
      case AppCommandId.inspectorForward:
        unawaited(_service.forward());
      case AppCommandId.inspectorLensDiff:
        lens(InspectorLens.diff);
      case AppCommandId.inspectorLensContents:
        lens(InspectorLens.contents);
      case AppCommandId.inspectorLensBlame || AppCommandId.historyBlame:
        lens(InspectorLens.blame);
      case AppCommandId.inspectorLensHistory || AppCommandId.historyPathHistory:
        lens(InspectorLens.history);
      case AppCommandId.inspectorOpenInWindow:
        if (location != null && _host.supportsWindows) {
          unawaited(_host.openInWindow(location));
        }
      case AppCommandId.inspectorToggleMaximize:
        if (_host.canMaximize) _host.toggleMaximize();
      case AppCommandId.inspectorToggleFiles:
        setState(() => _sidebarHidden = !_sidebarHidden);
      case AppCommandId.inspectorAllFiles:
        unawaited(_service.browseAllFiles());
      default:
        break;
    }
  }

  /// Moves one level up; false when Esc should continue to propagate.
  KeyEventResult _escape() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }
    final location = _state.location;
    final canGoUp =
        location != null &&
        (location.path != null || location.scope == InspectorScope.all);
    if (!canGoUp) return KeyEventResult.ignored;
    unawaited(_service.up());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final location = _state.location;
    if (location == null) {
      return Column(
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
      );
    }
    final summary = _state.inspection?.detail;
    final showSummary =
        summary != null &&
        _state.phase == InspectorPhase.ready &&
        (location.path == null || location.lens == InspectorLens.diff);
    return Listener(
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;
        if (event.buttons & kBackMouseButton != 0) {
          unawaited(_service.back());
        } else if (event.buttons & kForwardMouseButton != 0) {
          unawaited(_service.forward());
        }
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            return _escape();
          }
          return KeyEventResult.ignored;
        },
        child: CallbackShortcuts(
          bindings: {
            if (widget.handleShortcuts)
              for (final command in const [
                AppCommandId.inspectorBack,
                AppCommandId.inspectorForward,
                AppCommandId.inspectorLensDiff,
                AppCommandId.inspectorLensContents,
                AppCommandId.inspectorLensBlame,
                AppCommandId.inspectorLensHistory,
                AppCommandId.inspectorOpenInWindow,
                AppCommandId.inspectorToggleMaximize,
                AppCommandId.inspectorToggleFiles,
                AppCommandId.inspectorAllFiles,
              ])
                if (widget.shortcuts[command] case final shortcut?)
                  shortcut.activator: () => runCommand(command),
          },
          child: ColoredBox(
            color: context.colors.pane,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InspectorLocationBar(
                  state: _state,
                  service: _service,
                  host: _host,
                  actions: _actions,
                  sidebarHidden: _sidebarHidden,
                  onToggleSidebar: () =>
                      setState(() => _sidebarHidden = !_sidebarHidden),
                  onRevealDirectory: _revealInSidebar,
                ),
                const MeridianHairline(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // A long message scrolls inside the card, so the
                        // files and diff keep the rest of the pane.
                        if (showSummary)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  constraints.maxHeight *
                                  GitLamaLayout.commitSummaryMaxHeightFraction,
                            ),
                            child: CommitSummaryCard(
                              key: ValueKey(
                                'commit-summary-card-${summary.commit}',
                              ),
                              detail: summary,
                              refs: _host.refsFor(summary.commit),
                              onSaveArchive: _host.canSaveArchive
                                  ? () => _host.saveArchive(summary.commit)
                                  : null,
                              onSelectParent: (parent) => unawaited(
                                _service.navigate(
                                  InspectorLocation(
                                    target: CommitTarget(parent),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(child: _body(context, location)),
                      ],
                    ),
                  ),
                ),
                Semantics(
                  liveRegion: true,
                  label: _announcement ?? '',
                  child: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _revealInSidebar(List<int> directory) {
    final location = _state.location;
    if (location == null) return;
    setState(() => _sidebarHidden = false);
    if (location.scope == InspectorScope.all) {
      unawaited(_service.expandDirectory(directory));
    } else {
      _revealDirectory.value = null;
      _revealDirectory.value = utf8.decode(directory, allowMalformed: true);
    }
  }

  Widget _body(BuildContext context, InspectorLocation location) {
    switch (_state.phase) {
      case InspectorPhase.empty:
        return MeridianEmptyState(
          compact: true,
          icon: 'inspect',
          title: context.l10n.workspaceNoSelection,
        );
      case InspectorPhase.loading:
        return MeridianEmptyState(
          compact: true,
          progress: true,
          title: context.l10n.inspectorLoading(
            shortObjectId(location.target.commit),
          ),
        );
      case InspectorPhase.failed:
        return _failure(context, _state.failureCode);
      case InspectorPhase.ready:
        break;
    }
    final history =
        location.path != null && location.lens == InspectorLens.history;
    final sidebar = history
        ? InspectorHistoryList(state: _state, service: _service, host: _host)
        : InspectorSidebar(
            state: _state,
            service: _service,
            actions: _actions,
            mode: widget.filesMode,
            onModeChanged: widget.onFilesModeChanged,
            onHide: () => setState(() => _sidebarHidden = true),
            reveal: _revealDirectory,
          );
    final content = _content(context, location);
    if (_sidebarHidden) return content;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < GitLamaLayout.inspectorWideWidth) {
          final listHeight = math.max(
            context.meridian.density.rowExtent * 5,
            constraints.maxHeight * .4,
          );
          return Column(
            children: [
              SizedBox(
                key: const ValueKey('commit-changed-files'),
                height: math.min(listHeight, constraints.maxHeight * .6),
                child: sidebar,
              ),
              const MeridianHairline(),
              Expanded(child: content),
            ],
          );
        }
        final maximum = math.max(
          GitLamaLayout.inspectorSidebarMin,
          constraints.maxWidth - GitLamaLayout.inspectorContentMin,
        );
        final width = widget.sidebarWidth
            .clamp(GitLamaLayout.inspectorSidebarMin, maximum)
            .toDouble();
        // The width is clamped above; the split pane adds no minimums of
        // its own.
        return MeridianSplitPane(
          extent: width,
          onExtentChanged: widget.onSidebarWidthChanged,
          firstMinExtent: 0,
          secondMinExtent: 0,
          keyboardStep: GitLamaLayout.paneResizeStep,
          focusable: false,
          semanticLabel: context.l10n.workspaceResizeDetail,
          handleKey: const ValueKey('commit-files-splitter'),
          first: KeyedSubtree(
            key: const ValueKey('commit-changed-files'),
            child: sidebar,
          ),
          second: content,
        );
      },
    );
  }

  Widget _failure(BuildContext context, RepositoryFailureCode? code) => Padding(
    padding: const EdgeInsets.all(MeridianSpace.space5),
    child: Align(
      alignment: Alignment.topCenter,
      child: MeridianBanner(
        tone: MeridianBannerTone.error,
        message: inspectorFailureMessage(context, code),
        actions: [
          MeridianButton(
            key: const ValueKey('inspector-retry'),
            label: context.l10n.retry,
            size: MeridianControlSize.small,
            onPressed: () => unawaited(_service.retry()),
          ),
        ],
      ),
    ),
  );

  Widget _content(BuildContext context, InspectorLocation location) {
    if (_state.contentFailureCode case final code?) {
      return _failure(context, code);
    }
    final hiddenToggle = _sidebarHidden
        ? MeridianIconButton(
            key: const ValueKey('inspector-show-files'),
            label: context.l10n.inspectorShowFiles,
            icon: 'panel-left',
            size: MeridianControlSize.small,
            onPressed: () => setState(() => _sidebarHidden = false),
          )
        : null;
    final path = location.path;
    final Widget lens;
    if (path == null || location.lens == InspectorLens.diff) {
      final diff = _state.diff;
      lens = diff == null
          ? MeridianEmptyState(
              compact: true,
              progress: true,
              title: context.l10n.loading,
            )
          : CommitDiffPane(
              detail: diff,
              service: _service,
              repositories: _host.repositories,
              diffRenderer: widget.diffRenderer,
              shortcuts: widget.shortcuts,
              onCreatePatch: _host.canCreatePatch
                  ? () {
                      final options = _service.diffOptions;
                      final newPath = options.newPath;
                      _host.createPatch(
                        location.target,
                        newPath == null
                            ? const []
                            : filePatchPaths(newPath, options.oldPath),
                      );
                    }
                  : null,
            );
    } else {
      lens = switch (location.lens) {
        InspectorLens.contents => _ContentsLens(
          key: ValueKey('contents:${location.target.commit}:$path'),
          path: path,
          bytes: _state.fileBytes,
          loading: _state.contentLoading,
          anchor: location.anchor,
          onAnchorChanged: _service.reportAnchor,
        ),
        InspectorLens.blame =>
          _state.blame == null
              ? MeridianEmptyState(
                  compact: true,
                  progress: true,
                  title: context.l10n.loading,
                )
              : BlameCodeView(
                  key: ValueKey('blame:${_state.blame!.requestId}'),
                  page: _state.blame!,
                  anchor: location.anchor,
                  rowAt: _service.blameRowAt,
                  ensureRow: _service.ensureBlameIndex,
                  onAnchorChanged: _service.reportAnchor,
                  onSelectCommit: (commit) => unawaited(
                    inspectLocation(
                      _service,
                      _host,
                      InspectorLocation(
                        target: CommitTarget(commit),
                        path: path,
                      ),
                    ),
                  ),
                  onBlameBefore: (row) => unawaited(_service.blameBefore(row)),
                  onRangeHistory: (row) => unawaited(
                    inspectLocation(
                      _service,
                      _host,
                      location.copyWith(
                        lens: InspectorLens.history,
                        lines: InspectorLineRange(
                          row.spanFirstLine,
                          row.spanLastLine,
                        ),
                        clearHistoryCommit: true,
                        anchor: 0,
                      ),
                      invert: inspectionModifierPressed(),
                    ),
                  ),
                  onCopyCommit: (commit) => unawaited(
                    copyWithStatusNotification(
                      context,
                      commit,
                      context.l10n.menuCommitHashCopied,
                    ),
                  ),
                  onOpenInWindow: _host.supportsWindows
                      ? (row) => unawaited(
                          _host.openInWindow(
                            InspectorLocation(
                              target: CommitTarget(row.commit!),
                              path: row.originalPath,
                              lens: InspectorLens.blame,
                              anchor: math.max(0, row.originalLine - 1),
                            ),
                          ),
                        )
                      : null,
                ),
        InspectorLens.history => InspectorHistoryDetail(
          state: _state,
          service: _service,
          host: _host,
          actions: _actions,
          shortcuts: widget.shortcuts,
          diffRenderer: widget.diffRenderer,
        ),
        InspectorLens.diff => const SizedBox.shrink(),
      };
    }
    final loading =
        _state.contentLoading && location.lens != InspectorLens.contents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hiddenToggle != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: MeridianSpace.space3,
              top: MeridianSpace.space2,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: hiddenToggle,
            ),
          ),
        if (loading) const MeridianProgressBar(),
        // Lenses switch in place: a crossfade would keep the leaving diff
        // pane, and its key, alive beside the arriving one.
        Expanded(child: lens),
      ],
    );
  }
}

/// A file's bytes at the target commit, with find.
class _ContentsLens extends StatefulWidget {
  const _ContentsLens({
    required this.path,
    required this.bytes,
    required this.loading,
    required this.anchor,
    required this.onAnchorChanged,
    super.key,
  });

  final List<int> path;
  final List<int>? bytes;
  final bool loading;
  final int anchor;
  final ValueChanged<int> onAnchorChanged;

  @override
  State<_ContentsLens> createState() => _ContentsLensState();
}

class _ContentsLensState extends State<_ContentsLens> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.anchor * GitLamaLayout.diffLineHeight,
  )..addListener(_scrolled);
  final TextEditingController _query = TextEditingController();
  List<int> _matches = const [];
  int _match = -1;
  bool _caseSensitive = false;
  Timer? _anchorReport;

  void _scrolled() {
    _anchorReport?.cancel();
    _anchorReport = Timer(MeridianDurations.quick, () {
      if (!mounted || !_scroll.hasClients) return;
      widget.onAnchorChanged(
        (_scroll.offset / GitLamaLayout.diffLineHeight).floor(),
      );
    });
  }

  @override
  void dispose() {
    _anchorReport?.cancel();
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  void _search() {
    final query = _caseSensitive ? _query.text : _query.text.toLowerCase();
    final bytes = widget.bytes;
    if (query.isEmpty || bytes == null) {
      setState(() {
        _matches = const [];
        _match = -1;
      });
      return;
    }
    final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
    final matches = [
      for (var index = 0; index < lines.length; index += 1)
        if ((_caseSensitive ? lines[index] : lines[index].toLowerCase())
            .contains(query))
          index,
    ];
    setState(() {
      _matches = matches;
      _match = matches.isEmpty ? -1 : 0;
    });
    _jump();
  }

  void _move(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _match = (_match + delta) % _matches.length);
    _jump();
  }

  void _jump() {
    if (_match < 0 || !_scroll.hasClients) return;
    _scroll.jumpTo(
      (_matches[_match] * GitLamaLayout.diffLineHeight -
              2 * GitLamaLayout.diffLineHeight)
          .clamp(0, _scroll.position.maxScrollExtent)
          .toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MeridianSectionHeader(
          color: context.colors.pane,
          title: utf8.decode(widget.path, allowMalformed: true),
          caption: bytes == null ? null : Text('${bytes.length} B'),
          actions: [
            MeridianFindBar(
              fieldKey: const ValueKey('inspector-contents-search'),
              controller: _query,
              labels: gitLamaFindBarLabels(
                context,
                placeholder: context.l10n.findInFileHint,
              ),
              matchCount: _matches.length,
              currentMatch: _match < 0 ? null : _match,
              onChanged: (_) => _search(),
              onNext: () => _move(1),
              onPrevious: () => _move(-1),
              caseSensitive: _caseSensitive,
              onCaseSensitiveChanged: (value) {
                _caseSensitive = value;
                _search();
              },
            ),
          ],
        ),
        Expanded(
          child: widget.loading && bytes == null
              ? MeridianEmptyState(
                  compact: true,
                  progress: true,
                  title: context.l10n.loading,
                )
              : CommitFileContentView(
                  bytes: bytes,
                  controller: _scroll,
                  matchLines: _matches.toSet(),
                  currentLine: _match < 0 ? null : _matches[_match],
                ),
        ),
      ],
    );
  }
}
