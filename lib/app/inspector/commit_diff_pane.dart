import '../../widgets/status_notification.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../byte_size.dart';
import '../../models/diff.dart';
import '../../models/diff_renderer.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../models/inspector.dart';
import '../../models/integrations.dart';
import '../../models/remote_command_policy.dart';
import '../app_shortcut_activator.dart';
import '../../services/repository_session_service.dart';
import '../../services/inspector/inspector_service.dart';
import '../../widgets/diff_view.dart';
import '../../widgets/image_diff_view.dart';
import '../app_theme.dart';
import '../workspace/shell_chrome.dart';
import '../workspace/command_availability.dart';
import '../workspace/labels.dart';
import '../workspace/diff_view_preferences.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../services/workflows/diff_renderer_workflow.dart';
import '../gitlama_layout.dart';
import '../../widgets/command_preview.dart';
import '../../widgets/find_bar_labels.dart';
import '../../widgets/gitlama_scroll.dart';

class CommitDiffPane extends StatefulWidget {
  const CommitDiffPane({
    required this.detail,
    required this.service,
    required this.repositories,
    required this.diffRenderer,
    required this.shortcuts,
    this.onCreatePatch,
    super.key,
  });

  final InspectorDiff detail;
  final InspectorService service;

  /// External diff tools; null where none can run, such as in a window.
  final RepositorySessionService? repositories;
  final DiffRendererDefinition? diffRenderer;
  final Map<AppCommandId, AppShortcut?> shortcuts;

  /// Creates a patch of the diff on screen: the commit or comparison, limited
  /// to the file when one is open. Null hides the action.
  final VoidCallback? onCreatePatch;

  @override
  State<CommitDiffPane> createState() => CommitDiffPaneState();
}

class CommitDiffPaneState extends State<CommitDiffPane>
    with DiffViewPreferencesState<CommitDiffPane>
    implements DiffRendererInteraction {
  /// Why [id] is unavailable for a repository on another computer, or null.
  String? _remoteReason(BuildContext context, AppCommandId id) =>
      switch (remoteCommandReason(
        id,
        CommandAvailabilityScope.read(context)?.remote,
      )) {
        final reason? => workspaceDisabledReason(context, reason),
        null => null,
      };

  PaneCommandContext? _paneCommands;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paneCommands = PaneCommandContextScope.maybeOf(context);
    if (!identical(paneCommands, _paneCommands)) {
      _paneCommands
        ?..removeDiff()
        ..withdrawHandler(PaneRole.commitDiff, _handler);
      _paneCommands = paneCommands
        ?..addDiff()
        ..registerHandler(PaneRole.commitDiff, _handler);
    }
  }

  late final PaneCommandHandler _handler = PaneCommandHandler(
    run: runCommand,
    focusFind: _focusFind,
    hasFocus: () => _paneFocus.hasFocus,
  );

  /// Focuses the find field with its query selected, for Find.
  bool _focusFind() {
    if (_searchFocus.context == null) return false;
    _searchFocus.requestFocus();
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
    return true;
  }

  final FocusNode _paneFocus = FocusNode();

  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Set<String> _selected = {};
  List<int> _matches = const [];
  List<int> _hunks = const [];
  int _match = -1;
  int _hunk = -1;
  bool _caseSensitive = false;
  String _searchedQuery = '';
  bool _searchedCaseSensitive = false;
  bool _filesCollapsed = false;
  bool _contextExhausted = false;
  bool _contextExpanding = false;
  int _collapseReset = 0;
  Set<String> _revealContextIds = {};
  Timer? _contextRevealTimer;
  DiffTextEncoding _encoding = DiffTextEncoding.utf8;

  /// The configured renderer's run on this diff, if one was started.
  DiffRendererRun? _renderer;
  DiffRendererResult? _rendererResult;

  @override
  void didUpdateWidget(covariant CommitDiffPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.diff.requestId != widget.detail.diff.requestId) {
      unawaited(_renderer?.cancel());
      _renderer = null;
      _rendererResult = null;
      _selected = {};
      _matches = const [];
      _hunks = const [];
      _match = -1;
      _hunk = -1;
      _searchedQuery = '';
      _searchedCaseSensitive = _caseSensitive;
      if (oldWidget.detail.newObjectId != widget.detail.newObjectId ||
          oldWidget.detail.oldObjectId != widget.detail.oldObjectId) {
        _contextExhausted = false;
      }
      _collapseReset = 0;
      _filesCollapsed = false;
    }
  }

  @override
  void dispose() {
    _paneCommands
      ?..removeDiff()
      ..withdrawHandler(PaneRole.commitDiff, _handler);
    _contextRevealTimer?.cancel();
    unawaited(_renderer?.cancel());
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _paneFocus.dispose();
    super.dispose();
  }

  @override
  bool diffLoadedOtherwise(DiffViewPreferences preferences) =>
      !preferences.loads(widget.service.diffOptions);

  @override
  void loadDiffPreferences(DiffViewPreferences preferences) =>
      unawaited(_apply(preferences.applyTo(widget.service.diffOptions)));

  void runCommand(AppCommandId command) {
    final preferences = diffPreferences;
    if (command == AppCommandId.diffToggleLayout) {
      changeDiffPreferences(
        preferences.copyWith(
          layout: preferences.layout == DiffViewLayout.unified
              ? DiffViewLayout.sideBySide
              : DiffViewLayout.unified,
        ),
      );
    } else if (command == AppCommandId.diffRenderConfigured) {
      if (widget.diffRenderer != null) _runRenderer();
    } else if (command == AppCommandId.diffToggleWrap) {
      changeDiffPreferences(preferences.copyWith(wrap: !preferences.wrap));
    } else if (command == AppCommandId.diffNextHunk) {
      unawaited(_moveHunk(1));
    } else if (command == AppCommandId.diffPreviousHunk) {
      unawaited(_moveHunk(-1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final patchReason = _remoteReason(context, AppCommandId.createPatch);
    final options = widget.service.diffOptions;
    final imageRow = imageDiffRow(widget.service.loadedDiffRows.values);
    final content = Column(
      children: [
        SizedBox(
          key: const ValueKey('commit-diff-toolbar-surface'),
          width: double.infinity,
          child: ColoredBox(
            color: context.colors.pane,
            child: Padding(
              padding: EdgeInsets.zero,
              child: IconTheme.merge(
                data: const IconThemeData(size: MeridianSize.icon),
                child: DiffToolbar(
                  key: const ValueKey('commit-diff-toolbar'),
                  path: options.newPath == null
                      ? context.l10n.diffAllFiles
                      : utf8.decode(options.newPath!, allowMalformed: true),
                  pinned: [
                    if (widget.onCreatePatch != null)
                      MeridianIconButton(
                        key: const ValueKey('commit-diff-create-patch'),
                        label: context.l10n.diffCreatePatch,
                        icon: 'file-diff',
                        size: MeridianControlSize.small,
                        disabledReason: patchReason,
                        onPressed: patchReason == null
                            ? widget.onCreatePatch
                            : null,
                      ),
                  ],
                  children: [
                    ListenableBuilder(
                      listenable: _search,
                      builder: (context, _) => MeridianFindBar(
                        fieldKey: const ValueKey('commit-diff-search'),
                        controller: _search,
                        focusNode: _searchFocus,
                        labels: gitLamaFindBarLabels(
                          context,
                          placeholder: context.l10n.diffSearchHint,
                          searched:
                              _search.text == _searchedQuery &&
                              _caseSensitive == _searchedCaseSensitive,
                        ),
                        matchCount: _matches.length,
                        currentMatch: _match < 0 ? null : _match,
                        onChanged: (value) {
                          if (value.isEmpty) _clearSearch();
                        },
                        onNext: () => unawaited(_activateSearch()),
                        onPrevious: () =>
                            unawaited(_activateSearch(backwards: true)),
                        caseSensitive: _caseSensitive,
                        onCaseSensitiveChanged: (value) {
                          setState(() => _caseSensitive = value);
                          if (_search.text.isNotEmpty) unawaited(_runSearch());
                        },
                      ),
                    ),
                    MeridianIconButton(
                      label: context.l10n.diffPreviousHunk,
                      icon: 'arrow-up-to-line',
                      size: MeridianControlSize.small,
                      onPressed: () => unawaited(_moveHunk(-1)),
                    ),
                    MeridianIconButton(
                      label: context.l10n.diffNextHunk,
                      icon: 'arrow-down-to-line',
                      size: MeridianControlSize.small,
                      onPressed: () => unawaited(_moveHunk(1)),
                    ),
                    ...DiffViewingActions(
                      // The stored choices: context widened by Show More
                      // is not one of them.
                      options: diffPreferences.applyTo(options),
                      onOptionsChanged: (value) => changeDiffPreferences(
                        diffPreferences.withLoadOptions(value),
                      ),
                      wrap: diffPreferences.wrap,
                      onWrapChanged: (value) => changeDiffPreferences(
                        diffPreferences.copyWith(wrap: value),
                      ),
                      showIndicators: diffPreferences.showIndicators,
                      onIndicatorsChanged: (value) => changeDiffPreferences(
                        diffPreferences.copyWith(showIndicators: value),
                      ),
                      showMinimap: diffPreferences.showMinimap,
                      minimapAvailable: !_filesCollapsed,
                      onMinimapChanged: (value) => changeDiffPreferences(
                        diffPreferences.copyWith(showMinimap: value),
                      ),
                      encoding: _encoding,
                      onEncodingChanged: (value) =>
                          setState(() => _encoding = value),
                    ).buttons(context),
                    MeridianIconButton(
                      key: const Key('commit-diff-renderer'),
                      label: widget.diffRenderer == null
                          ? context.l10n.diffRendererNotConfigured
                          : context.l10n.diffRendererRun,
                      icon: 'wand-sparkles',
                      size: MeridianControlSize.small,
                      onPressed:
                          widget.diffRenderer == null ||
                              _rendererResult?.state ==
                                  DiffRendererState.pending
                          ? null
                          : () => _runRenderer(),
                    ),
                    _externalDiffAction(context),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_rendererResult case final result?)
          if (result.state == DiffRendererState.pending)
            const MeridianProgressBar()
          else if (result.state == DiffRendererState.fallback ||
              result.state == DiffRendererState.canceled)
            Padding(
              padding: const EdgeInsets.all(MeridianSpace.space3),
              child: MeridianBanner(
                key: const ValueKey('commit-diff-renderer-failure'),
                tone: MeridianBannerTone.error,
                message: rendererFailureLabel(context, result.failure),
              ),
            ),
        Expanded(
          child: _rendererResult?.state == DiffRendererState.ready
              ? _rendererOutput(context, _rendererResult!)
              : imageRow != null
              ? ImageDiffView(
                  key: ValueKey(
                    'image-diff-${widget.detail.diff.requestId}-'
                    '${imageRow.stableId}',
                  ),
                  load: () => widget.service.imageDiff(imageRow),
                )
              : Row(
                  children: [
                    Expanded(
                      child: DiffView(
                        key: ValueKey(widget.detail.diff.requestId),
                        syntax: widget.service.diffSyntax,
                        itemCount: widget.detail.diff.totalRows,
                        fileSections: {
                          for (final entry
                              in widget.service.loadedDiffRows.entries)
                            if (entry.value.kind == DiffRowKind.file &&
                                entry.value.sectionEnd != null)
                              entry.key: entry.value,
                        },
                        collapsibleFiles: options.newPath == null,
                        onFileCollapseChanged: (collapsed) =>
                            setState(() => _filesCollapsed = collapsed),
                        collapseReset: _collapseReset,
                        onShowMoreContext:
                            options.contextLines < 10000 &&
                                !_contextExhausted &&
                                !_contextExpanding
                            ? () => unawaited(_showMoreContext())
                            : null,
                        revealContextIds: _revealContextIds,
                        onShowAsText: options.forceText
                            ? null
                            : () => unawaited(
                                _apply(options.copyWith(forceText: true)),
                              ),
                        hunkIndices: {
                          for (final entry
                              in widget.service.loadedDiffRows.entries)
                            if (entry.value.kind == DiffRowKind.hunk) entry.key,
                        },
                        fallbackIndices: {
                          for (final entry
                              in widget.service.loadedDiffRows.entries)
                            if (isDiffFallbackRow(entry.value, _encoding))
                              entry.key,
                        },
                        rowAt: _rowAt,
                        loadedRows: widget.service.loadedDiffRows.values,
                        layout: widget.detail.diff.layout,
                        selectedIds: _selected,
                        onSelectionChanged: (value) =>
                            setState(() => _selected = value),
                        onCopyPatch: widget.service.diffSelectionPatch,
                        controller: _scroll,
                        wrap: diffPreferences.wrap,
                        showIndicators: diffPreferences.showIndicators,
                        encoding: _encoding,
                        searchMatchIndices: _matches.toSet(),
                        currentSearchIndex: _match < 0
                            ? null
                            : _matches[_match],
                      ),
                    ),
                    if (diffPreferences.showMinimap && !_filesCollapsed)
                      DiffMinimap(
                        controller: _scroll,
                        totalRows: widget.detail.diff.totalRows,
                        rows: widget.service.loadedDiffRows,
                        searchMatches: _matches.toSet(),
                      ),
                  ],
                ),
        ),
      ],
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f3): () =>
            unawaited(_activateSearch()),
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
            unawaited(_activateSearch(backwards: true)),
        const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
        for (final command in const [
          AppCommandId.diffToggleLayout,
          AppCommandId.diffRenderConfigured,
          AppCommandId.diffToggleWrap,
          AppCommandId.diffNextHunk,
          AppCommandId.diffPreviousHunk,
        ])
          if (widget.shortcuts[command] case final shortcut?)
            shortcut.activator: () => runAvailableCommand(
              context,
              command,
              () => runCommand(command),
            ),
      },
      child: Focus(focusNode: _paneFocus, child: content),
    );
  }

  DiffDisplayRow _rowAt(int index) {
    final row = widget.service.diffRowAt(index);
    if (row != null) return row;
    unawaited(widget.service.ensureDiffIndex(index));
    return DiffDisplayRow(
      stableId: 'loading-$index',
      kind: DiffRowKind.context,
      text: utf8.encode('…'),
      loading: true,
    );
  }

  Widget _externalDiffAction(BuildContext context) {
    final options = widget.service.diffOptions;
    final tools =
        widget.repositories?.configuredIntegrations(IntegrationKind.diffTool) ??
        const <IntegrationDefinition>[];
    // For a repository on another computer the host reads both versions and
    // the tool compares copies on this computer.
    final remoteReason = _remoteReason(
      context,
      AppCommandId.diffRenderConfigured,
    );
    final available =
        remoteReason == null &&
        options.oldPath != null &&
        options.newPath != null;
    if (tools.length > 1 && available) {
      return NativeMenuButton<IntegrationDefinition>(
        key: const Key('commit-external-diff'),
        tooltip: context.l10n.conflictExternalTool,
        onSelected: (definition) => unawaited(_externalDiff(definition)),
        itemBuilder: (context) => [
          for (final definition in tools)
            NativeMenuItem(value: definition, title: definition.id),
        ],
        icon: const MeridianIcon('external-link'),
      );
    }
    return MeridianIconButton(
      key: const Key('commit-external-diff'),
      label: tools.isEmpty || !available
          ? context.l10n.integrationUnavailable
          : context.l10n.conflictExternalTool,
      disabledReason: remoteReason,
      icon: 'external-link',
      size: MeridianControlSize.small,
      onPressed: tools.isEmpty || !available
          ? null
          : () => unawaited(_externalDiff(tools.single)),
    );
  }

  Future<void> _externalDiff(IntegrationDefinition definition) async {
    final options = widget.service.diffOptions;
    final oldPath = options.oldPath;
    final newPath = options.newPath;
    final repositories = widget.repositories;
    if (oldPath == null || newPath == null || repositories == null) return;
    await runExternalCommitDiff(
      context,
      repositories,
      definition: definition,
      oldRevision: widget.detail.oldObjectId,
      newRevision: widget.detail.newObjectId,
      oldPath: oldPath,
      newPath: newPath,
    );
  }

  Future<void> _apply(DiffLoadOptions options) async {
    if (options.contextLines != widget.service.diffOptions.contextLines) {
      _contextExhausted = false;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    await widget.service.updateDiffOptions(options);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  Future<void> _showMoreContext() async {
    if (_contextExpanding) return;
    setState(() => _contextExpanding = true);
    final options = widget.service.diffOptions;
    final before = widget.detail.diff.totalRows;
    final commit = widget.detail.newObjectId;
    final seen = {
      for (final row in widget.service.loadedDiffRows.values)
        if (row.kind == DiffRowKind.context) diffContextPosition(row),
    };
    final nextContext = math.min(10000, options.contextLines + 3);
    try {
      await _apply(options.copyWith(contextLines: nextContext));
      if (!mounted ||
          widget.detail.newObjectId != commit ||
          widget.service.diffOptions.contextLines != nextContext) {
        return;
      }
      final next = widget.service.current.diff?.diff;
      final rows = widget.service.loadedDiffRows.values;
      setState(() {
        _contextExhausted = next?.totalRows == before;
        _revealContextIds = {
          for (final row in rows)
            if (row.kind == DiffRowKind.context &&
                !seen.contains(diffContextPosition(row)))
              row.stableId,
        };
      });
      _contextRevealTimer?.cancel();
      _contextRevealTimer = Timer(MeridianDurations.layout, () {
        if (mounted) setState(() => _revealContextIds = {});
      });
    } finally {
      if (mounted) setState(() => _contextExpanding = false);
    }
  }

  Future<void> _activateSearch({bool backwards = false}) async {
    final query = _search.text;
    if (query.isEmpty) {
      _clearSearch();
      return;
    }
    if (query != _searchedQuery ||
        _caseSensitive != _searchedCaseSensitive ||
        _matches.isEmpty) {
      await _runSearch(backwards: backwards);
      return;
    }
    _moveMatch(backwards ? -1 : 1);
  }

  Future<void> _runSearch({bool backwards = false}) async {
    final result = await widget.service.searchDiff(
      _search.text,
      caseSensitive: _caseSensitive,
    );
    if (!mounted || result == null) return;
    setState(() {
      _searchedQuery = _search.text;
      _searchedCaseSensitive = _caseSensitive;
      _matches = result.matches;
      _match = _matches.isEmpty ? -1 : (backwards ? _matches.length - 1 : 0);
    });
    if (_match >= 0) await _jumpTo(_matches[_match]);
  }

  void _moveMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _match = (_match + delta) % _matches.length);
    unawaited(_jumpTo(_matches[_match]));
  }

  void _clearSearch() {
    setState(() {
      _search.clear();
      _matches = const [];
      _match = -1;
      _searchedQuery = '';
      _searchedCaseSensitive = _caseSensitive;
    });
  }

  Future<void> _moveHunk(int delta) async {
    if (_hunks.isEmpty) _hunks = await widget.service.diffHunks();
    if (!mounted || _hunks.isEmpty) return;
    setState(() => _hunk = (_hunk + delta) % _hunks.length);
    await _jumpTo(_hunks[_hunk]);
  }

  Future<void> _jumpTo(int row) async {
    await widget.service.ensureDiffIndex(row);
    if (!mounted) return;
    setState(() {
      _collapseReset += 1;
      _filesCollapsed = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    await gitlamaScrollTo(_scroll, row * GitLamaLayout.diffLineHeight, context);
  }

  Widget _rendererOutput(BuildContext context, DiffRendererResult result) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MeridianListRow(
            title: result.title ?? context.l10n.diffRendererTitle,
            subtitle: context.l10n.diffRendererPlainText,
            trailing: MeridianButton(
              label: context.l10n.diffRendererUseBuiltIn,
              variant: MeridianButtonVariant.quiet,
              onPressed: () => setState(() => _rendererResult = null),
            ),
          ),
          const MeridianHairline(),
          Expanded(
            child: Semantics(
              label: result.accessibilityText,
              textField: true,
              readOnly: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(MeridianSpace.space5),
                child: SelectableText(
                  contextMenuBuilder: nativeTextContextMenuBuilder,
                  result.text ?? '',
                ),
              ),
            ),
          ),
        ],
      );

  @override
  bool get active => mounted;

  @override
  Future<bool> confirmRenderer(DiffRendererPreview preview) =>
      showMeridianConfirm(
        context,
        barrierDismissible: false,
        title: context.l10n.diffRendererPreviewTitle,
        confirmLabel: context.l10n.diffRendererRun,
        cancelLabel: context.l10n.cancel,
        content: DiffRendererPreviewContent(
          preview: preview,
          summary: context.l10n.diffRendererRunSummary,
        ),
      );

  void _runRenderer() {
    final definition = widget.diffRenderer;
    if (definition == null) return;
    unawaited(_renderer?.cancel());
    final run = DiffRendererWorkflow(widget.service).render(this, definition);
    _renderer = run;
    run.results.listen((result) {
      if (mounted && identical(_renderer, run)) {
        setState(() => _rendererResult = result);
      }
    });
  }
}

/// What a diff renderer does before it runs or is saved: one sentence, the
/// program and its limits, and both exact command lines behind "Command
/// details", one argument per line.
class DiffRendererPreviewContent extends StatelessWidget {
  const DiffRendererPreviewContent({
    required this.preview,
    required this.summary,
    this.run = true,
    super.key,
  });

  final DiffRendererPreview preview;
  final String summary;

  /// Running shows the diff's size and the limits; saving shows the output
  /// format instead.
  final bool run;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final outputFormat = MeridianProperty(
      label: l10n.diffRendererOutputFormat,
      value: preview.mediaType,
      monospace: true,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space6,
      children: [
        Text(
          summary,
          style: context.text.body.copyWith(color: context.colors.ink),
        ),
        MeridianPropertyList(
          key: const ValueKey('diff-renderer-facts'),
          properties: [
            if (preview.title.isNotEmpty)
              MeridianProperty(
                label: l10n.diffRendererName,
                value: preview.title,
              ),
            MeridianProperty(
              label: l10n.diffRendererProgram,
              value: preview.executable,
              monospace: true,
            ),
            if (run) ...[
              MeridianProperty(
                label: l10n.diffRendererInputSize,
                value: formatByteSize(l10n, preview.inputBytes),
              ),
              MeridianProperty(
                label: l10n.diffRendererOutputLimit,
                value: formatByteSize(l10n, preview.outputLimitBytes),
              ),
              MeridianProperty(
                label: l10n.diffRendererTimeLimit,
                value: l10n.secondsCount(preview.timeoutSeconds),
              ),
            ] else
              outputFormat,
          ],
        ),
        MeridianDisclosure(
          key: const ValueKey('diff-renderer-commands'),
          title: l10n.commandDetails,
          child: MeridianPropertyList(
            properties: [
              MeridianProperty(
                label: l10n.diffRendererCapabilityCommand,
                value: [
                  preview.executable,
                  ...preview.capabilityArguments,
                ].join('\n'),
                monospace: true,
              ),
              MeridianProperty(
                label: l10n.diffRendererRenderCommand,
                value: [preview.executable, ...preview.arguments].join('\n'),
                monospace: true,
              ),
              MeridianProperty(
                label: l10n.diffRendererProtocol,
                value: preview.protocol,
                monospace: true,
              ),
              if (run) outputFormat,
            ],
          ),
        ),
      ],
    );
  }
}

String rendererFailureLabel(
  BuildContext context,
  DiffRendererFailureCode? failure,
) => switch (failure) {
  DiffRendererFailureCode.invalidDefinition =>
    context.l10n.diffRendererInvalidDefinition,
  DiffRendererFailureCode.unavailable => context.l10n.diffRendererUnavailable,
  DiffRendererFailureCode.invalidCapability =>
    context.l10n.diffRendererInvalidCapability,
  DiffRendererFailureCode.inputTooLarge =>
    context.l10n.diffRendererInputTooLarge,
  DiffRendererFailureCode.outputTooLarge =>
    context.l10n.diffRendererOutputTooLarge,
  DiffRendererFailureCode.launchFailed => context.l10n.diffRendererLaunchFailed,
  DiffRendererFailureCode.processFailed =>
    context.l10n.diffRendererProcessFailed,
  DiffRendererFailureCode.timedOut => context.l10n.diffRendererTimedOut,
  DiffRendererFailureCode.canceled => context.l10n.diffRendererCanceled,
  DiffRendererFailureCode.stale || null => context.l10n.diffRendererStale,
};

class DiffMinimap extends StatelessWidget {
  const DiffMinimap({
    super.key,
    required this.controller,
    required this.totalRows,
    required this.rows,
    this.searchMatches = const {},
  });

  final ScrollController controller;
  final int totalRows;
  final Map<int, DiffDisplayRow> rows;
  final Set<int> searchMatches;

  // A replacing diff view attaches to the shared controller before the view
  // it replaces detaches, so two positions exist for one frame. The newest
  // one belongs to the view on screen.
  ScrollPosition? get _measuredPosition {
    final position = controller.positions.lastOrNull;
    return position != null && position.hasContentDimensions ? position : null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        final position = _measuredPosition;
        if (position == null || constraints.maxHeight <= 0) return;
        final viewportFraction =
            position.viewportDimension /
            (position.viewportDimension + position.maxScrollExtent);
        final available = 1 - viewportFraction;
        if (available <= 0) return;
        final fraction =
            (details.localPosition.dy / constraints.maxHeight -
                viewportFraction / 2) /
            available;
        final offset = fraction.clamp(0.0, 1.0) * position.maxScrollExtent;
        unawaited(gitlamaScrollTo(controller, offset, context));
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final position = _measuredPosition;
          final maximum = position?.maxScrollExtent ?? 0.0;
          final viewport = position?.viewportDimension ?? 0.0;
          final fraction = maximum <= 0 ? 0.0 : position!.pixels / maximum;
          final viewportFraction = maximum + viewport <= 0
              ? 1.0
              : viewport / (maximum + viewport);
          return CustomPaint(
            key: const ValueKey('diff-minimap-paint'),
            size: Size(GitLamaLayout.diffMinimapWidth, constraints.maxHeight),
            painter: DiffMinimapPainter(
              git: context.git,
              totalRows: totalRows,
              rows: rows,
              searchMatches: searchMatches,
              offsetFraction: fraction,
              viewportFraction: viewportFraction,
              tokens: context.meridian,
            ),
          );
        },
      ),
    ),
  );
}

class DiffMinimapPainter extends CustomPainter {
  const DiffMinimapPainter({
    required this.totalRows,
    required this.rows,
    required this.offsetFraction,
    required this.viewportFraction,
    required this.tokens,
    required this.git,
    this.searchMatches = const {},
  });

  final int totalRows;
  final Map<int, DiffDisplayRow> rows;
  final Set<int> searchMatches;
  final double offsetFraction;
  final double viewportFraction;
  final MeridianTheme tokens;
  final GitLamaGitColors git;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalRows == 0 || !size.height.isFinite) return;
    final paint = Paint();
    for (final entry in rows.entries) {
      final color = switch (entry.value.kind) {
        DiffRowKind.addition => tokens.colors.success,
        DiffRowKind.deletion => git.deleted,
        _ => null,
      };
      if (color == null) continue;
      paint.color = color;
      final y = entry.key / totalRows * size.height;
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
    paint.color = tokens.colors.accent;
    for (final index in searchMatches) {
      final y = index / totalRows * size.height;
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
    paint.color = tokens.colors.lineStrong;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = MeridianLayout.hairline;
    final extent = math.max(2.0, viewportFraction * size.height);
    final y = offsetFraction * (size.height - extent);
    canvas.drawRect(Rect.fromLTWH(0.5, y, size.width - 1, extent), paint);
  }

  @override
  bool shouldRepaint(covariant DiffMinimapPainter oldDelegate) =>
      totalRows != oldDelegate.totalRows ||
      offsetFraction != oldDelegate.offsetFraction ||
      viewportFraction != oldDelegate.viewportFraction ||
      !setEquals(searchMatches, oldDelegate.searchMatches) ||
      !mapEquals(rows, oldDelegate.rows) ||
      tokens != oldDelegate.tokens;
}

/// Previews the external diff tool's command for one file of a commit or
/// comparison, and runs it once confirmed.
Future<void> runExternalCommitDiff(
  BuildContext context,
  RepositorySessionService repositories, {
  required IntegrationDefinition definition,
  required String? oldRevision,
  required String newRevision,
  required List<int> oldPath,
  required List<int> newPath,
}) async {
  IntegrationPreview? preview;
  try {
    preview = await repositories.integrations.previewExternalCommitDiff(
      oldRevision: oldRevision,
      newRevision: newRevision,
      oldPath: oldPath,
      newPath: newPath,
      definition: definition,
    );
    if (!context.mounted) return;
    final shown = preview;
    final confirmed = await showMeridianConfirm(
      context,
      barrierDismissible: false,
      title: context.l10n.integrationPreviewTitle,
      content: GitLamaCommandPreviewContent(
        summary: context.l10n.integrationDiffSummary,
        commandLines: [shown.executable, ...shown.arguments],
        external: true,
      ),
      confirmLabel: context.l10n.integrationRun,
      cancelLabel: context.l10n.cancel,
    );
    if (!confirmed) {
      await repositories.integrations.cancel(shown);
      return;
    }
    final result = await repositories.integrations.execute(
      shown,
      confirmed: true,
    );
    if (!context.mounted) return;
    if (result.state != IntegrationExecutionState.completed) {
      StatusNotificationScope.show(
        context,
        context.l10n.integrationLaunchFailed,
        error: true,
      );
    }
  } on Object {
    if (preview != null) await repositories.integrations.cancel(preview);
    if (context.mounted) {
      StatusNotificationScope.show(
        context,
        context.l10n.integrationLaunchFailed,
        error: true,
      );
    }
  }
}
