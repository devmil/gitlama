import 'gitlama_file_row.dart';
import 'git_file_list/git_file_list.dart';
import '../app/file_actions/file_actions.dart';
import '../models/inspector.dart';
import 'gitlama_ref_chip.dart';
import 'gitlama_workflow_header.dart';
import 'status_notification.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show PipelineOwner, RenderEditable, RenderStack;
import 'package:flutter/services.dart';

import 'native_menu.dart';
import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import '../app/app_shortcut_activator.dart';
import '../models/app_command.dart';
import '../models/app_shortcut.dart';
import '../models/conflict.dart';
import '../models/conflict_details.dart';
import '../models/git_names.dart';
import '../services/conflict/conflict_merge_draft.dart';
import '../services/source_syntax_service.dart';
import 'syntax_colours.dart';
import '../models/integrations.dart';
import '../services/workflows/conflict_resolution.dart';
import '../app/workspace/labels.dart'
    show showWorkflowMessage, conflictOutcomeMessage;
import '../app/workspace/workspace_scope.dart';
import '../services/workflows/workspace_effects.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';
import 'command_preview.dart';
import 'conflict_scroll_map.dart';
import 'conflict_syntax.dart';
import 'conflict_file_details.dart';
import 'gitlama_scroll.dart';

final class ConflictResolver extends StatefulWidget {
  const ConflictResolver({
    required this.shortcuts,
    required this.onFinished,
    super.key,
    this.banner,
    this.onOpenWorkingFile,
    this.onInspect,
    this.inspectionUnavailableReason,
    this.fileBrowserName = '',
    this.wrap,
    this.onWrapChanged,
  });

  final Map<AppCommandId, AppShortcut?> shortcuts;
  final VoidCallback onFinished;
  final Widget? banner;

  /// Opens a conflicted file in the editor or reveals it in the file
  /// manager; null where neither can run.
  final void Function(List<int> path, {required bool reveal})?
  onOpenWorkingFile;

  /// Opens a conflicted file's blame or history at the current commit.
  final InspectWorkingFile? onInspect;
  final String? inspectionUnavailableReason;
  final String fileBrowserName;

  /// Whether long comparison lines wrap, shared with the diff views; null
  /// keeps the choice in the resolver.
  final bool? wrap;
  final ValueChanged<bool>? onWrapChanged;

  @override
  State<ConflictResolver> createState() => ConflictResolverState();
}

final class ConflictResolverState extends State<ConflictResolver>
    implements ConflictInteraction {
  final _resultController = _MergeResultController();
  final TextEditingController _mergeSubjectController = TextEditingController();
  final TextEditingController _mergeDescriptionController =
      TextEditingController();
  final FocusNode _resultFocus = FocusNode(debugLabel: 'conflict-result');
  final FocusNode _resolverFocus = FocusNode(debugLabel: 'conflict-resolver');
  final GlobalKey _externalMergeKey = GlobalKey();

  /// The repository's conflict session; it owns the snapshot, the drafts of
  /// every file and the workflows, and outlives this widget.
  ConflictSession? _session;
  StreamSubscription<ConflictResolutionState>? _states;
  var _state = const ConflictResolutionState();
  String _boundText = '';
  var _binding = false;
  var _showAncestor = false;
  var _fileListMode = GitFileListMode.list;
  double _fileListWidth = GitLamaLayout.conflictFileListWidth;
  final _fileReveal = ValueNotifier<String?>(null);
  var _finishReported = false;
  ConflictMergeDraft? _draft;
  ConflictSideChoice? _pendingWholeSide;
  int _focusedRegion = 0;

  /// Conflicted files ticked for resolving together, by encoded path.
  final Set<String> _checked = {};

  /// The file last ticked, where a Shift-tick range starts.
  String? _checkAnchor;
  final ScrollController _comparisonScroll = ScrollController();
  final ScrollController _resultScroll = ScrollController();
  final ScrollController _ancestorScroll = ScrollController();

  /// Syntax colours of the shown file; null where they are unavailable.
  ConflictSyntax? _syntax;

  /// Runs while a pane scrolls; colours wait until it settles.
  Timer? _syntaxScrollTimer;

  /// The file whose conflict was last scrolled into view.
  String? _revealedFile;

  /// Row heights and offsets of the comparison as last laid out.
  _ComparisonGeometry? _geometry;

  /// Whether long comparison lines wrap, when [ConflictResolver.wrap]
  /// leaves it here; otherwise they scroll sideways.
  var _ownWrap = true;
  bool get _wrap => widget.wrap ?? _ownWrap;
  final ScrollController _comparisonHorizontal = ScrollController();

  /// The side of a conflict under the pointer, or both sides while the
  /// pointer is on "Take both".
  final _hoveredHunk = ValueNotifier<_Hunk?>(null);

  /// True while one pane is being moved to follow the other.
  var _following = false;

  /// Running scrolls to a chosen conflict. Meanwhile the focused conflict
  /// does not follow the scroll offset.
  var _navigations = 0;
  BoxConstraints? _comparisonConstraints;
  var _hasPreviousRegion = false;
  var _hasNextRegion = false;
  _ScrollMapKey? _scrollMapKey;
  ConflictScrollMap? _cachedScrollMap;

  ConflictSnapshot? get _snapshot => _state.snapshot;
  bool get _loading => _state.loading;
  bool get _busy => _state.busy;
  int get _selectedIndex => _state.selectedIndex;
  String? get _error =>
      _state.loadFailed ? context.l10n.conflictLoadFailed : null;

  int get _markerCount => RegExp(
    r'^<<<<<<<',
    multiLine: true,
  ).allMatches(_resultController.text).length;

  void runCommand(AppCommandId command) {
    switch (command) {
      case AppCommandId.conflictNext:
        _stepConflict(1);
      case AppCommandId.conflictPrevious:
        _stepConflict(-1);
      case AppCommandId.conflictTakeCurrent:
        _takeFocused(ConflictRegionChoice.current);
      case AppCommandId.conflictTakeIncoming:
        _takeFocused(ConflictRegionChoice.incoming);
      case AppCommandId.conflictTakeBoth:
        _takeFocused(ConflictRegionChoice.both);
      case AppCommandId.conflictOpenExternal:
        unawaited(_externalMerge());
      case AppCommandId.rebaseContinue:
        unawaited(_sequence(ConflictSequencerAction.continueOperation));
      case AppCommandId.rebaseAbort:
        unawaited(_sequence(ConflictSequencerAction.abort));
      default:
        break;
    }
  }

  void skipOperation() => unawaited(_sequence(ConflictSequencerAction.skip));

  // The questions the conflict workflows ask.

  @override
  bool get active => mounted;

  @override
  Future<bool> confirmSequencer(ConflictSequencerAction action) {
    final abort = action == ConflictSequencerAction.abort;
    return showMeridianConfirm(
      context,
      title: abort
          ? context.l10n.conflictAbortTitle
          : context.l10n.conflictSkipTitle,
      description: abort
          ? context.l10n.conflictAbortMessage
          : context.l10n.conflictSkipMessage,
      confirmLabel: abort
          ? context.l10n.conflictAbort
          : context.l10n.conflictSkip,
      cancelLabel: context.l10n.cancel,
      destructive: true,
    );
  }

  /// Several merge tools are offered in a native menu at the external merge
  /// button, or at the resolver's top when the button is not shown.
  @override
  Future<IntegrationDefinition?> chooseMergeTool(
    List<IntegrationDefinition> tools,
  ) {
    final anchor = (_externalMergeKey.currentContext ?? context)
        .findRenderObject();
    final position = anchor is RenderBox && anchor.hasSize
        ? anchor.localToGlobal(anchor.size.bottomLeft(Offset.zero))
        : Offset.zero;
    return showNativeMenuItems<IntegrationDefinition>(
      context: context,
      position: position,
      items: [
        for (final tool in tools) NativeMenuItem(value: tool, title: tool.id),
      ],
    );
  }

  @override
  Future<bool> confirmExternalMerge(IntegrationPreview preview) =>
      showMeridianConfirm(
        context,
        barrierDismissible: false,
        title: context.l10n.integrationPreviewTitle,
        content: GitLamaCommandPreviewContent(
          summary: context.l10n.integrationMergeSummary,
          commandLines: [preview.executable, ...preview.arguments],
          external: true,
        ),
        confirmLabel: context.l10n.integrationRun,
        cancelLabel: context.l10n.cancel,
      );

  @override
  void reportConflict(ConflictOutcome outcome) {
    if (!mounted) return;
    showWorkflowMessage(context, conflictOutcomeMessage(context, outcome));
  }

  void _takeFocused(ConflictRegionChoice choice) {
    final file = _selectedFile;
    if (file == null) return;
    if (file.kind == ConflictFileKind.text &&
        _draft?.blocks.isNotEmpty == true) {
      _takeRegion(_focusedRegion, choice);
      return;
    }
    final side = switch (choice) {
      ConflictRegionChoice.current => ConflictSideChoice.current,
      ConflictRegionChoice.incoming => ConflictSideChoice.incoming,
      ConflictRegionChoice.both => null,
    };
    if (side != null) unawaited(_chooseSide(side));
  }

  @override
  void initState() {
    super.initState();
    _resultController
      ..addListener(_resultChanged)
      ..addListener(_resultSyntaxChanged);
    _comparisonScroll.addListener(_comparisonScrolled);
    _resultScroll.addListener(_resultScrolled);
    _ancestorScroll.addListener(_syntaxScrolled);
    _mergeSubjectController.addListener(_mergeMessageChanged);
    _mergeDescriptionController.addListener(_mergeMessageChanged);
  }

  StreamSubscription<WorkspaceEffect>? _commands;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Conflict commands from menus and shortcuts reach the shown resolver.
    _commands ??= listenForEffects(
      context,
      WorkspaceEffectKind.conflictCommand,
      (effect) => switch (effect.payload) {
        final AppCommandId command => runCommand(command),
        ConflictSequencerAction.skip => skipOperation(),
        _ => null,
      },
    );
    if (_session != null) return;
    final session = WorkspaceServicesScope.of(
      context,
    ).workflows.conflicts.active;
    if (session == null) return;
    _session = session;
    _state = session.current;
    _states = session.states.listen(_stateChanged);
    unawaited(_reload());
  }

  void _stateChanged(ConflictResolutionState state) {
    if (!mounted) return;
    setState(() {
      _state = state;
      // A file that left the conflicts loses its tick, so it returns
      // unticked when its resolution is undone.
      final conflicted = {
        for (final file in state.snapshot?.files ?? const <ConflictFile>[])
          base64.encode(file.path),
      };
      _checked.retainAll(conflicted);
      if (!conflicted.contains(_checkAnchor)) _checkAnchor = null;
    });
    if (state.finished && !_finishReported) {
      _finishReported = true;
      widget.onFinished();
    }
  }

  void _mergeMessageChanged() {
    final session = _session;
    if (session == null) return;
    session
      ..mergeSubject = _mergeSubjectController.text
      ..mergeDescription = _mergeDescriptionController.text;
  }

  @override
  void dispose() {
    _fileReveal.dispose();
    // Unsaved choices stay with the session for when the resolver returns.
    _rememberDraft();
    unawaited(_states?.cancel());
    unawaited(_commands?.cancel());
    _syntaxScrollTimer?.cancel();
    _resultController
      ..removeListener(_resultChanged)
      ..removeListener(_resultSyntaxChanged)
      ..syntax = null
      ..dispose();
    _syntax?.dispose();
    _ancestorScroll.dispose();
    _mergeSubjectController.dispose();
    _mergeDescriptionController.dispose();
    _resultFocus.dispose();
    _resolverFocus.dispose();
    _comparisonScroll.dispose();
    _comparisonHorizontal.dispose();
    _hoveredHunk.dispose();
    _resultScroll.dispose();
    super.dispose();
  }

  ConflictFile? get _selectedFile => _state.selectedFile;

  /// Keeps the shown file's unsaved resolution in the session.
  void _rememberDraft() {
    final file = _selectedFile;
    if (file == null || _snapshot == null) return;
    _session?.remember(
      file,
      ConflictFileDraft(
        fingerprint: file.fingerprint,
        text: _resultController.text,
        draft: _draft,
        side: _pendingWholeSide,
        focusedRegion: _focusedRegion,
      ),
    );
  }

  Future<void> _reload() async {
    final session = _session;
    if (session == null) return;
    _rememberDraft();
    await session.load();
    if (!mounted || _state.loadFailed || _state.finished) return;
    final subject = session.mergeSubject;
    final description = session.mergeDescription;
    if (_mergeSubjectController.text != subject) {
      _mergeSubjectController.text = subject;
    }
    if (_mergeDescriptionController.text != description) {
      _mergeDescriptionController.text = description;
    }
    _bindResult();
    if (_snapshot?.files.isEmpty ?? false) _resolverFocus.requestFocus();
  }

  void _bindResult({bool preserveSelection = false}) {
    final file = _selectedFile;
    final saved = file == null ? null : _session?.draftOf(file);
    _draft =
        saved?.draft ??
        (file != null && file.kind == ConflictFileKind.text
            ? ConflictMergeDraft.fromFile(file)
            : null);
    _pendingWholeSide = saved?.side;
    _focusedRegion = saved?.focusedRegion ?? 0;
    final selection = _resultController.selection;
    _binding = true;
    final text =
        saved?.text ??
        _draft?.text ??
        utf8.decode(file?.result ?? const <int>[], allowMalformed: true);
    _resultController.value = TextEditingValue(
      text: text,
      selection: preserveSelection && selection.isValid
          ? TextSelection(
              baseOffset: selection.baseOffset.clamp(0, text.length),
              extentOffset: selection.extentOffset.clamp(0, text.length),
            )
          : TextSelection.collapsed(offset: text.length),
    );
    _boundText = text;
    _resultController.draft = _pendingWholeSide == null ? _draft : null;
    _binding = false;
    _bindSyntax();
    final bound = file == null
        ? null
        : '${base64.encode(file.path)} ${file.fingerprint}';
    if (bound != _revealedFile) {
      _revealedFile = bound;
      _fileReveal.value = file == null ? null : _path(file.path);
      _revealFocusedRegion();
    }
  }

  /// Colours for the shown file: kept while its draft stays, made anew for
  /// another file or version.
  void _bindSyntax() {
    final file = _selectedFile;
    final service = _session?.syntax;
    final current = _syntax;
    if (current != null && file != null && current.matches(file, _draft)) {
      current.result.update(_resultController.text);
      return;
    }
    final next =
        service == null || file == null || file.kind != ConflictFileKind.text
        ? null
        : _newSyntax(service, file);
    _resultController.syntax = next;
    // Panes listen to the shown file's colours from their next build.
    if (mounted) setState(() => _syntax = next);
    _syntax = next;
    current?.dispose();
    if (next == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_syntax, next)) return;
      next.start();
      _reportSyntaxVisible();
    });
  }

  ConflictSyntax _newSyntax(SourceSyntaxService service, ConflictFile file) =>
      ConflictSyntax(
        service,
        file: file,
        draft: _draft,
        result: _resultController.text,
      );

  void _resultSyntaxChanged() => _syntax?.result.update(_resultController.text);

  /// A pane scrolled: colours pause until it settles, then follow what is
  /// on screen.
  void _syntaxScrolled() {
    final syntax = _syntax;
    if (syntax == null) return;
    if (_syntaxScrollTimer == null) _syntaxInteracting(syntax, true);
    _syntaxScrollTimer?.cancel();
    _syntaxScrollTimer = Timer(_syntaxSettle, () {
      _syntaxScrollTimer = null;
      if (!mounted || !identical(_syntax, syntax)) return;
      _syntaxInteracting(syntax, false);
      _reportSyntaxVisible();
    });
  }

  static void _syntaxInteracting(ConflictSyntax syntax, bool interacting) {
    syntax.setComparisonInteracting(interacting);
    syntax.result.setInteracting(interacting);
    syntax.ancestor?.setInteracting(interacting);
  }

  /// Tells each text which of its lines are on screen.
  void _reportSyntaxVisible() {
    final syntax = _syntax;
    if (syntax == null) return;
    final geometry = _geometry;
    if (geometry != null &&
        identical(geometry.draft, syntax.draft) &&
        _comparisonScroll.hasClients &&
        _comparisonScroll.position.hasContentDimensions) {
      final position = _comparisonScroll.position;
      syntax.showComparisonRows(
        geometry.rowAt(position.pixels),
        geometry.rowAt(position.pixels + position.viewportDimension),
      );
    }
    final box = _viewport(_resultScroll);
    final editable = box == null ? null : _resultEditable();
    if (box != null &&
        editable != null &&
        editable.plainText == _resultController.text) {
      int offsetAt(double y) =>
          editable.getPositionForPoint(box.localToGlobal(Offset(1, y))).offset;
      syntax.result.setVisible(
        syntax.result.lineAt(offsetAt(1)),
        syntax.result.lineAt(offsetAt(box.size.height - 1)),
      );
    }
    final ancestor = syntax.ancestor;
    if (ancestor != null &&
        _ancestorScroll.hasClients &&
        _ancestorScroll.position.hasContentDimensions) {
      // Ancestor lines may wrap: a line is never below its unwrapped row,
      // and the margin covers moderate wrapping above the viewport.
      final position = _ancestorScroll.position;
      final row = MediaQuery.textScalerOf(
        context,
      ).scale(context.text.code.fontSize! * (context.text.code.height ?? 1.2));
      ancestor.setVisible(
        (position.pixels / row).floor() - _ancestorWrapMargin,
        ((position.pixels + position.viewportDimension) / row).ceil() + 1,
      );
    }
  }

  void _resultChanged() {
    if (_binding || _selectedFile?.kind != ConflictFileKind.text) return;
    if (_resultController.text == _boundText) return;
    _boundText = _resultController.text;
    _draft?.edit(_boundText);
    _pendingWholeSide = null;
    if (mounted) setState(() {});
  }

  Future<bool> _flushResult({required bool showFailure}) async {
    final file = _selectedFile;
    final session = _session;
    if (file == null || session == null) return true;
    final side = _pendingWholeSide;
    final savedText = _resultController.text;
    final saved = await session.save(
      this,
      file,
      text: savedText,
      side: side,
      unresolved: _draft?.unresolvedCount ?? file.regions.length,
      reportFailure: showFailure,
    );
    if (!mounted || !saved) return saved;
    final next = _selectedFile;
    final moved = next != null && !sameBytes(next.path, file.path);
    if (side != null || moved) {
      _bindResult();
    } else if (_resultController.text == savedText) {
      _bindResult(preserveSelection: true);
    }
    if (_snapshot?.files.isEmpty ?? false) _resolverFocus.requestFocus();
    // The resolved file left the list: say where the resolver went on.
    if (moved &&
        !(_snapshot?.files.any((other) => sameBytes(other.path, file.path)) ??
            true)) {
      StatusNotificationScope.show(
        context,
        context.l10n.conflictResolvedNext(
          _fileName(file.path),
          _fileName(next.path),
        ),
      );
    }
    return true;
  }

  static String _fileName(List<int> path) {
    final shown = _path(path);
    return shown.substring(shown.lastIndexOf('/') + 1);
  }

  Future<void> _selectFile(int index, {bool lastRegion = false}) async {
    final files = _snapshot?.files ?? const <ConflictFile>[];
    if (_busy ||
        index == _selectedIndex ||
        index < 0 ||
        index >= files.length) {
      return;
    }
    _rememberDraft();
    setState(() => _showAncestor = false);
    _session?.select(index);
    _bindResult();
    final blocks = _draft?.blocks.length ?? 0;
    if (lastRegion && blocks > 0) _focusedRegion = blocks - 1;
  }

  Future<void> _chooseSide(ConflictSideChoice choice) async {
    final file = _selectedFile;
    if (_busy || file == null) return;
    // Choosing the chosen side again takes the choice back.
    if (_pendingWholeSide == choice) return _clearWholeSide();
    setState(() {
      _pendingWholeSide = choice;
      if (file.kind == ConflictFileKind.text) {
        final content = choice == ConflictSideChoice.current
            ? file.current.content
            : file.incoming.content;
        if (content != null) {
          _binding = true;
          _resultController.text = _text(content);
          _boundText = _resultController.text;
          _binding = false;
        }
      }
      _resultController.draft = null;
    });
  }

  /// Takes back a whole-file choice: the result shows the regions' merge
  /// again.
  void _clearWholeSide() {
    final file = _selectedFile;
    if (_busy || file == null || _pendingWholeSide == null) return;
    setState(() {
      _pendingWholeSide = null;
      _binding = true;
      _resultController.text =
          _draft?.text ??
          utf8.decode(file.result ?? const <int>[], allowMalformed: true);
      _boundText = _resultController.text;
      _resultController.draft = _draft;
      _binding = false;
    });
    _followAfterLayout();
  }

  /// The branch or commit label of [side].
  String _sideLabel(ConflictSideChoice side) => _text(
    side == ConflictSideChoice.current
        ? _snapshot!.currentLabel
        : _snapshot!.incomingLabel,
  );

  /// Whether choosing the whole [side] of [file] deletes the file.
  static bool _deletes(ConflictFile file, ConflictSideChoice side) =>
      !(side == ConflictSideChoice.current ? file.current : file.incoming)
          .present;

  /// Whether the chosen result of [file] deletes it.
  bool _deletionChosen(ConflictFile file) =>
      _pendingWholeSide != null && _deletes(file, _pendingWholeSide!);

  /// The whole-file decision above the editor: asks to decide a file that
  /// one side deleted, and confirms a whole-file choice until it is saved.
  Widget? _wholeFileBanner(ConflictFile file) {
    final l10n = context.l10n;
    final chosen = _pendingWholeSide;
    if (chosen != null) {
      final deletes = _deletes(file, chosen);
      return MeridianBanner(
        key: const Key('conflict-whole-file-banner'),
        tone: deletes ? MeridianBannerTone.warning : MeridianBannerTone.info,
        icon: deletes ? 'trash-2' : 'check',
        title: deletes
            ? l10n.conflictDeletionChosenTitle
            : l10n.conflictWholeFileChosenTitle(_sideLabel(chosen)),
        message: deletes
            ? l10n.conflictDeletionChosenBody(_sideLabel(chosen))
            : l10n.conflictWholeFileChosenBody,
        actions: [
          MeridianButton(
            key: const Key('conflict-choose-differently'),
            label: l10n.conflictChooseDifferently,
            variant: MeridianButtonVariant.quiet,
            size: MeridianControlSize.small,
            onPressed: _busy ? null : _clearWholeSide,
          ),
        ],
      );
    }
    if (file.current.present == file.incoming.present) return null;
    final deleted = file.current.present
        ? ConflictSideChoice.incoming
        : ConflictSideChoice.current;
    final kept = deleted == ConflictSideChoice.current
        ? ConflictSideChoice.incoming
        : ConflictSideChoice.current;
    return MeridianBanner(
      key: const Key('conflict-deletion-decision'),
      tone: MeridianBannerTone.attention,
      icon: 'trash-2',
      title: l10n.conflictDeletionDecisionTitle,
      message: [
        conflictPresenceText(context, ConflictDetails(file).presence),
        l10n.conflictDeletionDecisionHint,
      ].map((part) => part.endsWith('.') ? part : '$part.').join(' '),
      actions: [
        MeridianButton(
          key: const Key('conflict-keep-deletion'),
          label: l10n.conflictKeepDeletion,
          icon: 'trash-2',
          variant: MeridianButtonVariant.secondary,
          size: MeridianControlSize.small,
          onPressed: _busy ? null : () => unawaited(_chooseSide(deleted)),
        ),
        MeridianButton(
          key: const Key('conflict-keep-file'),
          label: l10n.conflictKeepFileFrom(_sideLabel(kept)),
          variant: MeridianButtonVariant.secondary,
          size: MeridianControlSize.small,
          onPressed: _busy ? null : () => unawaited(_chooseSide(kept)),
        ),
      ],
    );
  }

  /// The resolve button's label and icon for [file]'s chosen result.
  (String, String) _resolveAction(ConflictFile file) => _deletionChosen(file)
      ? (context.l10n.conflictResolveByDeleting, 'trash-2')
      : (
          _busy
              ? context.l10n.conflictSaving
              : context.l10n.conflictResolveFile,
          'save',
        );

  void _takeRegion(
    int index,
    ConflictRegionChoice choice, {
    bool remove = false,
  }) {
    if (_busy || _draft == null || index >= _draft!.blocks.length) return;
    setState(() {
      _pendingWholeSide = null;
      _focusedRegion = index;
      final text = remove
          ? _draft!.remove(index, choice)
          : _draft!.take(index, choice);
      _resultController.draft = _draft;
      _binding = true;
      _resultController.text = text;
      _boundText = text;
      _binding = false;
    });
    // The result changed its length under a comparison that stayed put.
    _followAfterLayout();
  }

  void _followAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _follow(fromComparison: true);
      _regionsMoved();
    });
  }

  Future<void> _undo(List<int> path) async {
    final session = _session;
    if (_busy || session == null) return;
    await session.undo(this, path);
    if (!mounted) return;
    _bindResult();
    if (_snapshot?.files.isEmpty ?? false) _resolverFocus.requestFocus();
  }

  /// Resolves every ticked file with its whole [side].
  Future<void> _chooseSideForChecked(ConflictSideChoice side) async {
    final session = _session;
    final files = _snapshot?.files ?? const <ConflictFile>[];
    if (_busy || session == null) return;
    final paths = [
      for (final file in files)
        if (_checked.contains(base64.encode(file.path))) file.path,
    ];
    if (paths.isEmpty) return;
    _rememberDraft();
    await session.chooseSideForAll(this, paths, side);
    if (!mounted) return;
    setState(() {
      _checked.clear();
      _checkAnchor = null;
    });
    if (!_state.finished) _bindResult();
    if (_snapshot?.files.isEmpty ?? false) _resolverFocus.requestFocus();
  }

  Future<void> _undoAll(List<List<int>> paths) async {
    final session = _session;
    if (_busy || session == null) return;
    await session.undoAll(this, paths);
    if (!mounted) return;
    _bindResult();
  }

  /// Ticks or clears [file]; with Shift held, everything from the file
  /// ticked last takes the same state.
  void _toggleChecked(List<ConflictFile> files, ConflictFile file, bool on) {
    final key = base64.encode(file.path);
    final anchor = _checkAnchor;
    final keys = [for (final file in files) base64.encode(file.path)];
    final from = anchor == null ? -1 : keys.indexOf(anchor);
    final to = keys.indexOf(key);
    setState(() {
      final range = HardwareKeyboard.instance.isShiftPressed && from >= 0
          ? keys.sublist(math.min(from, to), math.max(from, to) + 1)
          : [key];
      on ? _checked.addAll(range) : _checked.removeAll(range);
      _checkAnchor = key;
    });
  }

  Future<void> _sequence(ConflictSequencerAction action) async {
    final session = _session;
    if (session == null) return;
    await session.sequence(this, action);
    if (mounted && !_state.finished) _bindResult();
  }

  /// Merges the shown file in an external tool: [definition], or the one
  /// the user picks when several are configured.
  Future<void> _externalMerge([IntegrationDefinition? definition]) async {
    final file = _selectedFile;
    final session = _session;
    if (file == null || session == null) return;
    await session.mergeExternally(this, file, definition: definition);
    if (mounted && !_state.finished) _bindResult();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return MeridianIsland(
        expandChild: true,
        child: Column(
          children: [
            ?widget.banner,
            Expanded(
              child: Center(
                child: Semantics(
                  liveRegion: true,
                  child: Text(context.l10n.conflictLoading),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null || _snapshot == null) {
      return MeridianIsland(
        expandChild: true,
        child: Column(
          children: [
            ?widget.banner,
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error ?? context.l10n.conflictLoadFailed),
                    const SizedBox(height: MeridianSpace.space5),
                    MeridianButton(
                      label: context.l10n.workspaceRefresh,
                      variant: MeridianButtonVariant.secondary,
                      onPressed: _reload,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    final snapshot = _snapshot!;
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
          unawaited(_flushResult(showFailure: true)),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          unawaited(_flushResult(showFailure: true)),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
          unawaited(_selectFile(_selectedIndex - 1)),
      const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
          unawaited(_selectFile(_selectedIndex + 1)),
      const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
          unawaited(_sequence(ConflictSequencerAction.continueOperation)),
      for (final command in const [
        AppCommandId.conflictNext,
        AppCommandId.conflictPrevious,
        AppCommandId.conflictTakeCurrent,
        AppCommandId.conflictTakeIncoming,
        AppCommandId.conflictTakeBoth,
        AppCommandId.conflictOpenExternal,
        AppCommandId.rebaseContinue,
        AppCommandId.rebaseAbort,
      ])
        if (widget.shortcuts[command] case final shortcut?)
          shortcut.activator: () => runCommand(command),
    };
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        focusNode: _resolverFocus,
        autofocus: true,
        child: Column(
          children: [
            _header(snapshot),
            const MeridianHairline(),
            _guide(snapshot),
            const MeridianHairline(),
            Expanded(child: _body(snapshot)),
            const MeridianHairline(),
            _footer(snapshot),
          ],
        ),
      ),
    );
  }

  /// The way through the conflicts: pick the changes of the shown file,
  /// review its result, resolve it, and once every file is resolved,
  /// continue the operation. Next to it, what to do now.
  Widget _guide(ConflictSnapshot snapshot) {
    final l10n = context.l10n;
    final file = snapshot.files.isEmpty ? null : _selectedFile;
    final standalone = snapshot.operation == ConflictOperationKind.standalone;
    final resolved = snapshot.resolvedUndoPaths.length;
    final total = resolved + snapshot.files.length;
    final String hint;
    final int step;
    if (file == null) {
      step = standalone ? 4 : 3;
      hint = standalone ? l10n.conflictGuideDone : l10n.conflictGuideContinue;
    } else if (_pendingWholeSide != null) {
      step = 1;
      hint = _deletionChosen(file)
          ? l10n.conflictGuideReviewDeletion
          : l10n.conflictGuideReview;
    } else if (file.current.present != file.incoming.present) {
      step = 0;
      hint = l10n.conflictGuideDecideDeletion;
    } else if (file.kind != ConflictFileKind.text) {
      step = 0;
      hint = l10n.conflictChooseVersion;
    } else if (_markerCount > 0) {
      step = 0;
      hint = l10n.conflictGuidePick(_markerCount);
    } else {
      step = 1;
      hint = l10n.conflictGuideReview;
    }
    return Padding(
      key: const Key('conflict-guide'),
      padding: const EdgeInsets.symmetric(
        horizontal: MeridianSpace.space5,
        vertical: MeridianSpace.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MeridianSteps(
            semanticLabel: l10n.conflictGuideTitle,
            current: step,
            steps: [
              MeridianStep(label: l10n.conflictStepPick),
              MeridianStep(label: l10n.conflictStepReview),
              MeridianStep(label: l10n.conflictStepResolve),
              MeridianStep(
                label: standalone
                    ? l10n.conflictStepDone
                    : l10n.conflictStepContinue,
              ),
            ],
          ),
          const SizedBox(height: MeridianSpace.space2),
          Row(
            children: [
              Expanded(
                child: Text(
                  hint,
                  key: const Key('conflict-guide-hint'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.caption.copyWith(
                    color: context.colors.ink,
                  ),
                ),
              ),
              if (total > 1) ...[
                const SizedBox(width: MeridianSpace.space3),
                Text(
                  l10n.conflictGuideResolvedCount(resolved, total),
                  maxLines: 1,
                  style: context.text.caption.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(ConflictSnapshot snapshot) {
    final operation = switch (snapshot.operation) {
      ConflictOperationKind.merge => context.l10n.conflictOperationMerge,
      ConflictOperationKind.rebase => context.l10n.conflictOperationRebase,
      ConflictOperationKind.cherryPick =>
        context.l10n.conflictOperationCherryPick,
      ConflictOperationKind.revert => context.l10n.conflictOperationRevert,
      ConflictOperationKind.snapshot => context.l10n.conflictOperationSnapshot,
      ConflictOperationKind.stash => context.l10n.conflictOperationStash,
      ConflictOperationKind.standalone =>
        context.l10n.conflictOperationStandalone,
    };
    final compact = MediaQuery.sizeOf(context).width < 1100;
    final progress = snapshot.currentStep != null && snapshot.totalSteps != null
        ? context.l10n.conflictStepProgress(
            snapshot.currentStep!,
            snapshot.totalSteps!,
          )
        : null;
    return GitLamaWorkflowHeader(
      title: context.l10n.conflictResolverTitle,
      status: progress == null ? operation : '$operation · $progress',
      exitLabel: context.l10n.workflowExit,
      onExit: widget.onFinished,
      primaryAction: snapshot.operation == ConflictOperationKind.standalone
          ? null
          : MeridianButton(
              label: context.l10n.conflictContinue,
              variant: MeridianButtonVariant.primary,
              size: MeridianControlSize.small,
              onPressed:
                  _busy ||
                      !snapshot.canContinue ||
                      (snapshot.operation == ConflictOperationKind.merge &&
                          _mergeSubjectController.text.trim().isEmpty)
                  ? null
                  : () => _sequence(ConflictSequencerAction.continueOperation),
            ),
      actions: [
        if (_busy) const MeridianSpinner(),
        if (compact)
          NativeMenuButton<ConflictSequencerAction>(
            tooltip: context.l10n.toolbarMore,
            icon: const MeridianIcon('more'),
            onSelected: (action) => unawaited(_sequence(action)),
            itemBuilder: (_) => [
              if (snapshot.canSkip)
                NativeMenuItem(
                  value: ConflictSequencerAction.skip,
                  title: context.l10n.conflictSkip,
                  enabled: !_busy,
                ),
              if (snapshot.operation != ConflictOperationKind.standalone)
                NativeMenuItem(
                  value: ConflictSequencerAction.abort,
                  title: context.l10n.conflictAbort,
                  enabled: !_busy,
                ),
            ],
          )
        else ...[
          if (snapshot.canSkip)
            MeridianButton(
              label: context.l10n.conflictSkip,
              variant: MeridianButtonVariant.quiet,
              size: MeridianControlSize.small,
              onPressed: _busy
                  ? null
                  : () => _sequence(ConflictSequencerAction.skip),
            ),
          if (snapshot.operation != ConflictOperationKind.standalone)
            MeridianButton(
              label: context.l10n.conflictAbort,
              variant: MeridianButtonVariant.dangerQuiet,
              size: MeridianControlSize.small,
              onPressed: _busy
                  ? null
                  : () => _sequence(ConflictSequencerAction.abort),
            ),
        ],
        MeridianIconButton(
          label: context.l10n.conflictExternalTool,
          icon: 'external-link',
          size: MeridianControlSize.small,
          onPressed: _busy ? null : () => unawaited(_externalMerge()),
        ),
        MeridianIconButton(
          label: context.l10n.workspaceRefresh,
          icon: 'refresh',
          size: MeridianControlSize.small,
          onPressed: _busy ? null : _reload,
        ),
      ],
    );
  }

  Widget _body(ConflictSnapshot snapshot) {
    if (snapshot.files.isEmpty) return _resolved(snapshot);
    return LayoutBuilder(
      builder: (context, constraints) => MeridianSplitPane(
        extent: _fileListWidth,
        onExtentChanged: (width) => setState(() => _fileListWidth = width),
        onReset: () => setState(
          () => _fileListWidth = GitLamaLayout.conflictFileListWidth,
        ),
        firstMinExtent: GitLamaLayout.conflictFileListMinWidth,
        secondMinExtent: GitLamaLayout.conflictEditorMinWidth,
        keyboardStep: GitLamaLayout.paneResizeStep,
        semanticLabel: context.l10n.conflictResizeFiles,
        handleKey: const Key('conflict-files-splitter'),
        first: MeridianIsland(
          expandChild: true,
          child: Column(
            children: [
              ?widget.banner,
              GitFileListHeader(
                title: context.l10n.conflictFilesTitle,
                count: snapshot.files.length,
                mode: _fileListMode,
                modeKey: const Key('conflict-files-mode'),
                onModeChanged: (mode) => setState(() => _fileListMode = mode),
              ),
              _selectionBar(snapshot),
              Expanded(child: _fileList(snapshot)),
              ?_bulkActions(snapshot),
            ],
          ),
        ),
        second: MeridianIsland(
          expandChild: true,
          child: Column(
            children: [
              ConflictFileDetails(
                file: _selectedFile!,
                markerFree: !hasConflictMarkers(_resultController.text),
              ),
              const MeridianHairline(),
              if (_wholeFileBanner(_selectedFile!) case final banner?)
                Padding(
                  padding: const EdgeInsets.all(MeridianSpace.space3),
                  child: banner,
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, editorConstraints) =>
                      editorConstraints.maxWidth >=
                          GitLamaLayout.conflictWideEditorMinWidth
                      ? _wideEditor(snapshot)
                      : _compactEditor(snapshot),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// How this session resolved the file at [path], in words; null when it
  /// was resolved before GitLama showed the operation.
  String? _outcome(List<int> path) {
    final l10n = context.l10n;
    return switch (_session?.resolutionOf(path)) {
      ConflictResolutionKind.deleted => l10n.conflictOutcomeDeleted,
      ConflictResolutionKind.current => l10n.conflictOutcomeCurrent(
        _sideLabel(ConflictSideChoice.current),
      ),
      ConflictResolutionKind.incoming => l10n.conflictOutcomeIncoming(
        _sideLabel(ConflictSideChoice.incoming),
      ),
      ConflictResolutionKind.merged => l10n.conflictOutcomeMerged,
      ConflictResolutionKind.external => l10n.conflictOutcomeExternal,
      null => null,
    };
  }

  /// Once no file is conflicted: the merge message and the resolved files,
  /// each of which can be put back. The page scrolls as one, so any number
  /// of files fits.
  Widget _resolved(ConflictSnapshot snapshot) {
    final l10n = context.l10n;
    final undoPaths = snapshot.resolvedUndoPaths;
    final merge = snapshot.operation == ConflictOperationKind.merge;
    return MeridianIsland(
      expandChild: true,
      child: Column(
        children: [
          ?widget.banner,
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final inset = math.max(
                  MeridianSpace.space8,
                  (constraints.maxWidth - GitLamaLayout.mergeMessageMaxWidth) /
                      2,
                );
                return CustomScrollView(
                  key: const ValueKey('conflict-resolved'),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        inset,
                        MeridianSpace.space9,
                        inset,
                        undoPaths.isEmpty ? MeridianSpace.space9 : 0,
                      ),
                      sliver: SliverList.list(
                        children: [
                          Center(
                            child: SizedBox.square(
                              dimension: GitLamaLayout.resolvedStateIconSize,
                              child: FittedBox(
                                child: MeridianIcon(
                                  'circle-check',
                                  color: context.colors.success,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: MeridianSpace.space5),
                          Text(
                            snapshot.operation ==
                                    ConflictOperationKind.standalone
                                ? l10n.conflictStandaloneResolved
                                : l10n.conflictAllResolved,
                            textAlign: TextAlign.center,
                            style: context.text.title.copyWith(
                              color: context.colors.ink,
                            ),
                          ),
                          if (merge) ...[
                            const SizedBox(height: MeridianSpace.space8),
                            MeridianTextField(
                              fieldKey: const Key('conflict-merge-subject'),
                              controller: _mergeSubjectController,
                              onChanged: (_) => setState(() {}),
                              label: l10n.commitSubject,
                            ),
                            const SizedBox(height: MeridianSpace.space5),
                            MeridianTextField(
                              fieldKey: const Key('conflict-merge-description'),
                              controller: _mergeDescriptionController,
                              maxLines: 5,
                              label: l10n.commitDescription,
                              minLines: 3,
                            ),
                          ],
                          if (undoPaths.isNotEmpty) ...[
                            const SizedBox(height: MeridianSpace.space8),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    l10n.conflictResolvedFiles,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.bodyStrong.copyWith(
                                      color: context.colors.ink,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: MeridianSpace.space3),
                                MeridianCount(label: '${undoPaths.length}'),
                                const Spacer(),
                                if (undoPaths.length > 1)
                                  MeridianButton(
                                    key: const Key('conflict-undo-all'),
                                    label: l10n.conflictUndoAll,
                                    icon: 'undo',
                                    variant: MeridianButtonVariant.quiet,
                                    size: MeridianControlSize.small,
                                    onPressed: _busy
                                        ? null
                                        : () => unawaited(_undoAll(undoPaths)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: MeridianSpace.space2),
                            Text(
                              l10n.conflictResolvedHint,
                              style: context.text.caption.copyWith(
                                color: context.colors.inkMuted,
                              ),
                            ),
                            const SizedBox(height: MeridianSpace.space3),
                          ],
                        ],
                      ),
                    ),
                    if (undoPaths.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                          inset,
                          0,
                          inset,
                          MeridianSpace.space9,
                        ),
                        sliver: DecoratedSliver(
                          decoration: BoxDecoration(
                            color: context.colors.paneAlt,
                            borderRadius: BorderRadius.circular(
                              context.meridian.radius.lg,
                            ),
                          ),
                          sliver: SliverPadding(
                            padding: const EdgeInsets.all(MeridianSpace.space3),
                            sliver: SliverList.builder(
                              itemCount: undoPaths.length,
                              itemBuilder: (context, index) {
                                final path = undoPaths[index];
                                final shown = _path(path);
                                final slash = shown.lastIndexOf('/');
                                final outcome = _outcome(path);
                                final deleted =
                                    _session?.resolutionOf(path) ==
                                    ConflictResolutionKind.deleted;
                                final subtitle = [
                                  ?outcome,
                                  if (slash >= 0) shown.substring(0, slash),
                                ].join(' · ');
                                return MeridianListRow(
                                  key: ValueKey(base64.encode(path)),
                                  leading: MeridianIcon(
                                    deleted ? 'trash-2' : 'check',
                                    color: deleted
                                        ? context.colors.danger
                                        : context.colors.success,
                                  ),
                                  title: shown.substring(slash + 1),
                                  subtitle: subtitle.isEmpty ? null : subtitle,
                                  semanticLabel: [shown, ?outcome].join(', '),
                                  trailing: MeridianIconButton(
                                    label: l10n.conflictUndoResolution,
                                    icon: 'undo',
                                    size: MeridianControlSize.small,
                                    onPressed: _busy
                                        ? null
                                        : () => unawaited(_undo(path)),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Ticks every conflicted file at once, or clears the ticks.
  Widget _selectionBar(ConflictSnapshot snapshot) {
    final files = snapshot.files;
    final count = files
        .where((file) => _checked.contains(base64.encode(file.path)))
        .length;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        MeridianSpace.space4 + MeridianSpace.space2,
        MeridianSpace.space3,
        MeridianSpace.space4,
        MeridianSpace.space2,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: MeridianCheckbox(
          key: const Key('conflict-select-all'),
          tristate: true,
          value: count == 0
              ? false
              : count == files.length
              ? true
              : null,
          label: count == 0
              ? context.l10n.conflictSelectAll
              : context.l10n.conflictSelectedCount(count),
          onChanged: _busy
              ? null
              : (_) => setState(() {
                  _checkAnchor = null;
                  if (count == files.length) {
                    _checked.clear();
                  } else {
                    _checked.addAll(
                      files.map((file) => base64.encode(file.path)),
                    );
                  }
                }),
        ),
      ),
    );
  }

  /// Resolves the ticked files with one whole side; null while none is
  /// ticked.
  Widget? _bulkActions(ConflictSnapshot snapshot) {
    final count = snapshot.files
        .where((file) => _checked.contains(base64.encode(file.path)))
        .length;
    if (count == 0) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MeridianHairline(),
        Padding(
          padding: const EdgeInsets.all(MeridianSpace.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MeridianButton(
                key: const Key('conflict-bulk-current'),
                label: context.l10n.conflictBulkUseCurrent(count),
                size: MeridianControlSize.small,
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _chooseSideForChecked(ConflictSideChoice.current),
                      ),
              ),
              const SizedBox(height: MeridianSpace.space2),
              MeridianButton(
                key: const Key('conflict-bulk-incoming'),
                label: context.l10n.conflictBulkUseIncoming(count),
                size: MeridianControlSize.small,
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _chooseSideForChecked(ConflictSideChoice.incoming),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  late final _ConflictActionHost _actionHost = _ConflictActionHost(this);

  Widget _fileList(ConflictSnapshot snapshot) => GitFileList<ConflictFile>(
    listKey: const ValueKey('conflict-file-list'),
    items: snapshot.files,
    displayPath: (file) => _path(file.path),
    mode: _fileListMode,
    reveal: _fileReveal,
    // The queue order is the order Previous and Next follow.
    preserveOrder: true,
    fileRowBuilder: (context, row) {
      final file = row.item!;
      final index = snapshot.files.indexOf(file);
      final remaining = file.kind == ConflictFileKind.text
          ? index == _selectedIndex
                ? _markerCount
                : RegExp(r'^<<<<<<<', multiLine: true)
                      .allMatches(
                        _session?.draftOf(file)?.text ??
                            utf8.decode(
                              file.result ?? const <int>[],
                              allowMalformed: true,
                            ),
                      )
                      .length
          : null;
      final deletion = switch (ConflictDetails(file).presence) {
        ConflictPresence.deletedCurrent ||
        ConflictPresence.deletedIncoming ||
        ConflictPresence.bothDeleted => conflictPresenceText(
          context,
          ConflictDetails(file).presence,
        ),
        _ => null,
      };
      final subject = FileActionSubject(
        source: FileActionSource.conflictFile,
        path: file.path,
        existsInWorkingTree: true,
      );
      return fileActionContextMenu(
        context: context,
        subject: () => subject,
        host: _actionHost,
        child: GitLamaFileRow(
          status: 'U',
          path: row.label,
          depth: row.depth,
          selected: index == _selectedIndex,
          leading: _FileCheckbox(
            label: _path(file.path),
            checked: _checked.contains(base64.encode(file.path)),
            onChanged: _busy
                ? null
                : (on) => _toggleChecked(snapshot.files, file, on),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (deletion != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    end: MeridianSpace.space2,
                  ),
                  child: Tooltip(
                    message: deletion,
                    child: MeridianIcon(
                      'trash-2',
                      key: ValueKey((
                        'conflict-file-deleted',
                        base64.encode(file.path),
                      )),
                      size: MeridianIconSize.small,
                      color: context.colors.danger,
                    ),
                  ),
                ),
              if (remaining == null || remaining == 0)
                Tooltip(
                  message: remaining == 0
                      ? context.l10n.conflictReviewFile
                      : file.kind == ConflictFileKind.binary
                      ? context.l10n.conflictBinaryFile
                      : context.l10n.conflictHugeFile,
                  child: MeridianIcon(
                    'circle-alert',
                    size: MeridianIconSize.small,
                    color: context.colors.attention,
                  ),
                )
              else
                MeridianCount(
                  label: '$remaining',
                  tone: MeridianCountTone.attention,
                ),
              FileActionButton(subject: () => subject, host: _actionHost),
            ],
          ),
          onActivate: () {
            if (!_busy) unawaited(_selectFile(index));
          },
        ),
      );
    },
  );

  Widget _wideEditor(ConflictSnapshot snapshot) {
    final file = _selectedFile!;
    return Row(
      children: [
        Expanded(flex: 3, child: _comparison(file)),
        const MeridianHairline(axis: Axis.vertical),
        Expanded(flex: 2, child: _result(file)),
      ],
    );
  }

  Widget _compactEditor(ConflictSnapshot snapshot) {
    final file = _selectedFile!;
    return Column(
      children: [
        Expanded(flex: 3, child: _comparison(file)),
        const MeridianHairline(),
        Expanded(flex: 2, child: _result(file)),
      ],
    );
  }

  void _navigateRegion(int delta) {
    final region = _neighbourRegion(delta);
    if (region != null) _showRegion(region, animate: true);
  }

  /// Moves to the neighbouring conflict, continuing in the neighbouring file
  /// after the last and before the first one.
  void _stepConflict(int delta) {
    final region = _selectedFile?.kind == ConflictFileKind.text
        ? _neighbourRegion(delta)
        : null;
    if (region != null) {
      _showRegion(region, animate: true);
      return;
    }
    unawaited(_selectFile(_selectedIndex + delta, lastRegion: delta < 0));
  }

  /// The conflict before or after the place the comparison shows. Where the
  /// comparison cannot scroll further, the focused conflict counts instead.
  int? _neighbourRegion(int delta) {
    final draft = _draft;
    if (draft == null || draft.blocks.isEmpty) return null;
    final lines = _referenceLines();
    if (lines != null) {
      final position = _comparisonScroll.position;
      final stopped = delta > 0
          ? position.pixels >= position.maxScrollExtent - _scrollTolerance
          : position.pixels <= position.minScrollExtent + _scrollTolerance;
      if (!stopped) {
        final line = position.pixels + lines.comparison;
        final extents = _regionExtents(draft);
        final region = delta > 0
            ? extents.indexWhere(
                (extent) => extent.top > line + _scrollTolerance,
              )
            : extents.lastIndexWhere(
                (extent) => extent.top < line - _scrollTolerance,
              );
        return region < 0 ? null : region;
      }
    }
    final region = _focusedRegion + delta;
    return region >= 0 && region < draft.blocks.length ? region : null;
  }

  void _revealFocusedRegion() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_comparisonHorizontal.hasClients) _comparisonHorizontal.jumpTo(0);
      if (_draft?.blocks.isEmpty ?? true) {
        for (final scroll in [_comparisonScroll, _resultScroll]) {
          if (scroll.hasClients) scroll.jumpTo(0);
        }
        return;
      }
      _showRegion(_focusedRegion, animate: false);
      _regionsMoved();
    });
  }

  /// Scrolls the comparison until [region] sits on the reference line. The
  /// result follows.
  void _showRegion(int region, {required bool animate}) {
    final draft = _draft;
    if (draft == null || region < 0 || region >= draft.blocks.length) return;
    if (region != _focusedRegion) setState(() => _focusedRegion = region);
    final lines = _referenceLines();
    if (lines == null) return;
    final target = _regionExtents(draft)[region].top - lines.comparison;
    _navigations++;
    unawaited(
      (animate
              ? gitlamaScrollTo(_comparisonScroll, target, context)
              : Future.sync(
                  () => _comparisonScroll.jumpTo(
                    target.clamp(
                      _comparisonScroll.position.minScrollExtent,
                      _comparisonScroll.position.maxScrollExtent,
                    ),
                  ),
                ))
          .whenComplete(() {
            _navigations--;
            if (!mounted) return;
            _follow(fromComparison: true);
            _regionsMoved();
          }),
    );
  }

  void _comparisonScrolled() {
    _syntaxScrolled();
    if (_following) return;
    _follow(fromComparison: true);
    _regionsMoved();
  }

  void _resultScrolled() {
    _syntaxScrolled();
    if (_following) return;
    _follow(fromComparison: false);
    _regionsMoved();
  }

  /// Moves the pane that was not scrolled to the place the other one shows.
  void _follow({required bool fromComparison}) {
    if (_following) return;
    final map = _scrollMap();
    if (map == null) return;
    final follower = fromComparison ? _resultScroll : _comparisonScroll;
    final target = fromComparison
        ? map.resultFor(_comparisonScroll.offset, current: follower.offset)
        : map.comparisonFor(_resultScroll.offset, current: follower.offset);
    if ((target - follower.offset).abs() < _scrollTolerance) return;
    _following = true;
    try {
      follower.jumpTo(target);
    } finally {
      _following = false;
    }
  }

  /// Focuses the conflict on or after the reference line and updates which
  /// neighbours navigation can reach.
  void _regionsMoved() {
    final draft = _draft;
    final lines = _referenceLines();
    if (draft == null || draft.blocks.isEmpty || lines == null) return;
    var region = _focusedRegion;
    if (_navigations == 0) {
      final line = _comparisonScroll.offset + lines.comparison;
      final extents = _regionExtents(draft);
      region = extents.indexWhere(
        (extent) => extent.bottom > line + _scrollTolerance,
      );
      if (region < 0) region = extents.length - 1;
    }
    final previous = _neighbourRegion(-1) != null;
    final next = _neighbourRegion(1) != null;
    if (region == _focusedRegion &&
        previous == _hasPreviousRegion &&
        next == _hasNextRegion) {
      return;
    }
    setState(() {
      _focusedRegion = region;
      _hasPreviousRegion = previous;
      _hasNextRegion = next;
    });
  }

  /// Comparison content offsets of each region, toolbar included.
  List<({double top, double bottom})> _regionExtents(ConflictMergeDraft draft) {
    final geometry = _geometry?.draft == draft
        ? _geometry!
        : _ComparisonGeometry.unwrapped(draft);
    return [
      for (final rows in draft.blockRows)
        (
          top: geometry.tops[rows.first],
          bottom: geometry.tops[rows.first + rows.count],
        ),
    ];
  }

  /// Switches line wrapping and keeps the comparison row on the reference
  /// line in place.
  void _toggleWrap() {
    final lines = _referenceLines();
    final anchor = lines == null || _geometry == null
        ? null
        : _geometry!.rowAt(_comparisonScroll.offset + lines.comparison);
    if (widget.onWrapChanged case final onWrapChanged?) {
      onWrapChanged(!_wrap);
    } else {
      setState(() => _ownWrap = !_ownWrap);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lines = _referenceLines();
      final geometry = _geometry;
      if (anchor != null && lines != null && geometry != null) {
        final position = _comparisonScroll.position;
        _comparisonScroll.jumpTo(
          (geometry.tops[math.min(anchor, geometry.tops.length - 1)] -
                  lines.comparison)
              .clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
      _follow(fromComparison: true);
      _regionsMoved();
    });
  }

  RenderBox? _viewport(ScrollController controller) {
    if (!controller.hasClients) return null;
    final position = controller.position;
    if (!position.hasContentDimensions) return null;
    final box = position.context.notificationContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// Where the line on which both panes show the same place crosses each
  /// viewport. Side by side it is one line across the window.
  ({double comparison, double result})? _referenceLines() {
    final comparison = _viewport(_comparisonScroll);
    final result = _viewport(_resultScroll);
    if (comparison == null || result == null) return null;
    const lead =
        GitLamaLayout.conflictLeadRows *
        GitLamaLayout.conflictComparisonRowHeight;
    final comparisonTop = comparison.localToGlobal(Offset.zero).dy;
    final resultTop = result.localToGlobal(Offset.zero).dy;
    final sideBySide =
        resultTop < comparisonTop + comparison.size.height &&
        comparisonTop < resultTop + result.size.height;
    final line = math.max(comparisonTop, resultTop) + lead;
    return (
      comparison: (sideBySide ? line - comparisonTop : lead).clamp(
        0,
        comparison.size.height / 2,
      ),
      result: (sideBySide ? line - resultTop : lead).clamp(
        0,
        result.size.height / 2,
      ),
    );
  }

  ConflictScrollMap? _scrollMap() {
    final lines = _referenceLines();
    if (lines == null) return null;
    final comparisonMax = _comparisonScroll.position.maxScrollExtent;
    final resultMax = _resultScroll.position.maxScrollExtent;
    final comparisonEnd =
        comparisonMax + _comparisonScroll.position.viewportDimension;
    final resultEnd = resultMax + _resultScroll.position.viewportDimension;
    final draft = _pendingWholeSide == null ? _draft : null;
    final text = _resultController.text;
    final editable = _resultEditable();
    final key = (
      text: text,
      draft: draft,
      comparisonMax: comparisonMax,
      resultMax: resultMax,
      comparisonLine: lines.comparison,
      resultLine: lines.result,
      geometry: _geometry,
      width: editable?.size.width,
    );
    if (key == _scrollMapKey) return _cachedScrollMap;
    // Before its next layout the editor still holds the previous text.
    final laidOut = editable != null && editable.plainText == text;
    final map = ConflictScrollMap(
      comparisonMax: comparisonMax,
      resultMax: resultMax,
      anchors: [
        (-lines.comparison, -lines.result),
        if (draft != null && laidOut)
          for (final (index, extent) in _regionExtents(draft).indexed)
            if (draft.blockRows[index].count > 0) ...[
              (
                extent.top - lines.comparison,
                _resultLineTop(editable, draft.blocks[index].start) -
                    lines.result,
              ),
              (
                extent.bottom - lines.comparison,
                _resultLineTop(editable, draft.blocks[index].end) -
                    lines.result,
              ),
            ],
        (comparisonEnd - lines.comparison, resultEnd - lines.result),
      ],
    );
    if (laidOut) {
      _scrollMapKey = key;
      _cachedScrollMap = map;
    }
    return map;
  }

  /// The result editor's text, once laid out.
  RenderEditable? _resultEditable() => _resultScroll.hasClients
      ? _resultScroll.position.context.notificationContext
            ?.findAncestorStateOfType<EditableTextState>()
            ?.renderEditable
      : null;

  /// Result content offset of the line that holds the text [offset]. Result
  /// lines are as tall as comparison rows.
  double _resultLineTop(RenderEditable editable, int offset) {
    const row = GitLamaLayout.conflictComparisonRowHeight;
    final caret = editable.getLocalRectForCaret(
      TextPosition(offset: offset.clamp(0, _resultController.text.length)),
    );
    return ((caret.center.dy + _resultScroll.offset) / row).floor() * row;
  }

  Widget _comparison(ConflictFile file) {
    final draft = _draft;
    if (file.kind != ConflictFileKind.text || draft == null) {
      return Row(
        children: [
          Expanded(child: _wholeSideCard(file, ConflictSideChoice.current)),
          const SizedBox(width: MeridianSpace.space4),
          Expanded(child: _wholeSideCard(file, ConflictSideChoice.incoming)),
        ],
      );
    }
    final tokens = context.meridian;
    final resolved = (draft.blocks.length - _markerCount).clamp(
      0,
      draft.blocks.length,
    );
    return Column(
      children: [
        MeridianSectionHeader(
          color: tokens.colors.paneAlt,
          size: MeridianSectionHeaderSize.small,
          divider: false,
          title: draft.blocks.isEmpty
              ? context.l10n.conflictComparisonTitle
              : context.l10n.conflictRegionNumber(_focusedRegion + 1),
          actions: [
            MeridianIconButton(
              key: const Key('conflict-wrap'),
              label: context.l10n.diffWrap,
              icon: 'wrap',
              active: _wrap,
              size: MeridianControlSize.small,
              onPressed: _toggleWrap,
            ),
            if (draft.blocks.isNotEmpty)
              MeridianRollingNumber(
                key: const Key('conflict-resolved-count'),
                value: resolved,
                format: (count) => '$count/${draft.blocks.length}',
                style: context.text.label.copyWith(
                  color: _markerCount == 0
                      ? tokens.colors.accent
                      : tokens.colors.danger,
                ),
              ),
            MeridianIconButton(
              label: context.l10n.conflictPreviousRegion,
              icon: 'chevron-up',
              size: MeridianControlSize.small,
              onPressed: _hasPreviousRegion ? () => _navigateRegion(-1) : null,
            ),
            MeridianIconButton(
              label: context.l10n.conflictNextRegion,
              icon: 'chevron-down',
              size: MeridianControlSize.small,
              onPressed: _hasNextRegion ? () => _navigateRegion(1) : null,
            ),
          ],
        ),
        SizedBox(
          height: GitLamaLayout.conflictRegionToolbarHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _sourceHeader(
                  label: context.l10n.conflictCurrent(
                    _text(_snapshot!.currentLabel),
                  ),
                  action: file.current.present
                      ? context.l10n.conflictUseCurrentFile
                      : context.l10n.conflictKeepDeletion,
                  color: context.git.sideOurs,
                  side: ConflictSideChoice.current,
                  deletes: !file.current.present,
                ),
              ),
              const MeridianHairline(axis: Axis.vertical),
              Expanded(
                child: _sourceHeader(
                  label: context.l10n.conflictIncoming(
                    _text(_snapshot!.incomingLabel),
                  ),
                  action: file.incoming.present
                      ? context.l10n.conflictUseIncomingFile
                      : context.l10n.conflictKeepDeletion,
                  color: context.git.sideTheirs,
                  side: ConflictSideChoice.incoming,
                  deletes: !file.incoming.present,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final geometry = _measureComparison(draft, constraints.maxWidth);
              if (constraints != _comparisonConstraints) {
                _comparisonConstraints = constraints;
                _followAfterLayout();
              }
              final lines = ListView.builder(
                key: const Key('conflict-comparison-lines'),
                controller: _comparisonScroll,
                padding: EdgeInsets.zero,
                itemCount: draft.rows.length,
                itemExtentBuilder: (index, _) => index < geometry.extents.length
                    ? geometry.extents[index]
                    : null,
                itemBuilder: (context, index) {
                  final row = draft.rows[index];
                  final region = row.blockIndex;
                  final first =
                      region != null && draft.blockFirstRows.contains(index);
                  return Column(
                    children: [
                      if (first) _regionToolbar(region),
                      SizedBox(
                        key: ValueKey('conflict-comparison-row-$index'),
                        height: geometry.rowHeight(index),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _comparisonCell(
                                row.current,
                                row.currentLine,
                                region,
                                ConflictRegionChoice.current,
                                row.different,
                                rowIndex: index,
                                firstInRegion: first,
                              ),
                            ),
                            const MeridianHairline(axis: Axis.vertical),
                            Expanded(
                              child: _comparisonCell(
                                row.incoming,
                                row.incomingLine,
                                region,
                                ConflictRegionChoice.incoming,
                                row.different,
                                rowIndex: index,
                                firstInRegion: first,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
              if (_wrap) return lines;
              return MeridianSharedHorizontalScroll(
                controller: _comparisonHorizontal,
                contentWidth: geometry.contentWidth,
                columns: 2,
                fixedWidth: _cellFixedWidth,
                child: lines,
              );
            },
          ),
        ),
      ],
    );
  }

  /// The comparison's row heights at [width]; measured again only when the
  /// file, the width, the wrapping or the text style changes.
  _ComparisonGeometry _measureComparison(
    ConflictMergeDraft draft,
    double width,
  ) {
    final style = _comparisonStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final textWidth = math.max(
      0.0,
      (width - MeridianLayout.hairline) / 2 - _cellFixedWidth,
    );
    final cached = _geometry;
    if (cached != null &&
        cached.draft == draft &&
        cached.wrap == _wrap &&
        cached.textWidth == textWidth &&
        cached.style == style &&
        cached.scaler == scaler) {
      return cached;
    }
    return _geometry = _ComparisonGeometry.measure(
      draft: draft,
      wrap: _wrap,
      textWidth: textWidth,
      style: style,
      scaler: scaler,
      direction: Directionality.of(context),
    );
  }

  Widget _wholeSideCard(ConflictFile file, ConflictSideChoice choice) {
    final selected = _pendingWholeSide == choice;
    final side = choice == ConflictSideChoice.current
        ? file.current
        : file.incoming;
    final branch = _text(
      choice == ConflictSideChoice.current
          ? _snapshot!.currentLabel
          : _snapshot!.incomingLabel,
    );
    final action = choice == ConflictSideChoice.current
        ? context.l10n.conflictUseCurrentFile
        : context.l10n.conflictUseIncomingFile;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(MeridianSpace.space5),
        child: Semantics(
          button: true,
          selected: selected,
          label: '$action, $branch',
          child: MeridianInteraction(
            onTap: _busy ? null : () => unawaited(_chooseSide(choice)),
            borderRadius: BorderRadius.circular(context.meridian.radius.lg),
            builder: (context, state) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(MeridianSpace.space5),
              decoration: BoxDecoration(
                color: state.hovered
                    ? context.colors.paneHover
                    : context.colors.paneAlt,
                borderRadius: BorderRadius.circular(context.meridian.radius.lg),
                border: Border.all(
                  color: selected ? context.colors.accent : context.colors.line,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      GitLamaRefChip(
                        name: branch,
                        kind: choice == ConflictSideChoice.current
                            ? GitLamaRefKind.local
                            : GitLamaRefKind.remote,
                      ),
                      const Spacer(),
                      if (selected)
                        MeridianIcon(
                          'check',
                          color: context.colors.accent,
                          size: MeridianIconSize.small,
                        ),
                    ],
                  ),
                  const SizedBox(height: MeridianSpace.space4),
                  Text(
                    side.present
                        ? side.content?.isEmpty == true
                              ? context.l10n.conflictEmptySide
                              : action
                        : context.l10n.conflictKeepDeletion,
                    style: context.text.body.copyWith(
                      color: context.colors.ink,
                    ),
                  ),
                  const SizedBox(height: MeridianSpace.space2),
                  Text(
                    context.l10n.conflictUnknownProvenance,
                    style: context.text.caption.copyWith(
                      color: context.colors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceHeader({
    required String label,
    required String action,
    required Color color,
    required ConflictSideChoice side,
    required bool deletes,
  }) {
    final chosen = _pendingWholeSide == side;
    // A chosen side says so on its button, which takes the choice back.
    final shown = chosen
        ? deletes
              ? context.l10n.conflictKeepingDeletion
              : context.l10n.conflictUsingThisFile
        : action;
    final icon = chosen ? 'check' : (deletes ? 'trash-2' : 'check-check');
    return LayoutBuilder(
      builder: (context, constraints) => DecoratedBox(
        key: ValueKey(('conflict-source-header', side, chosen)),
        decoration: BoxDecoration(
          color: chosen
              ? Color.alphaBlend(
                  color.withValues(alpha: GitLamaOpacity.conflictChosen),
                  context.colors.pane,
                )
              : context.colors.pane,
          border: Border(
            bottom: BorderSide(
              color: chosen
                  ? color
                  : color.withValues(alpha: GitLamaOpacity.conflictDivider),
              width: chosen
                  ? GitLamaLayout.conflictChoiceRail
                  : MeridianLayout.hairline,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space4),
          child: Row(
            children: [
              SizedBox(
                width: GitLamaLayout.conflictRail,
                height: MeridianSize.icon,
                child: ColoredBox(color: color),
              ),
              const SizedBox(width: MeridianSpace.space4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.label.copyWith(color: context.colors.ink),
                ),
              ),
              if (constraints.maxWidth <
                  GitLamaLayout.conflictSourceActionMinWidth *
                      MediaQuery.textScalerOf(context).scale(1))
                MeridianIconButton(
                  label: shown,
                  icon: icon,
                  active: chosen,
                  size: MeridianControlSize.small,
                  onPressed: _busy ? null : () => _chooseSide(side),
                )
              else
                MeridianButton(
                  label: shown,
                  icon: chosen || deletes ? icon : null,
                  variant: chosen
                      ? MeridianButtonVariant.secondary
                      : MeridianButtonVariant.quiet,
                  size: MeridianControlSize.small,
                  onPressed: _busy ? null : () => _chooseSide(side),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _comparisonCell(
    String text,
    int? line,
    int? region,
    ConflictRegionChoice side,
    bool different, {
    required int rowIndex,
    required bool firstInRegion,
  }) {
    final colors = context.colors;
    final sideColor = side == ConflictRegionChoice.current
        ? context.git.sideOurs
        : context.git.sideTheirs;
    final chosen =
        region != null &&
        (_draft!.blocks[region].choice == side ||
            _draft!.blocks[region].choice == ConflictRegionChoice.both);
    final style = _comparisonStyle(context);
    final pane = colors.pane;
    // Every fill the cell can show, so a colour stays put while hovering.
    final backgrounds = region == null
        ? [pane, if (different) Color.alphaBlend(colors.attentionBg, pane)]
        : [
            for (final alpha in const [
              GitLamaOpacity.conflictUnchosen,
              GitLamaOpacity.conflictChosen,
              GitLamaOpacity.conflictHover,
            ])
              Color.alphaBlend(sideColor.withValues(alpha: alpha), pane),
          ];
    final content = ListenableBuilder(
      listenable: _syntax ?? _noSyntax,
      builder: (context, _) => Text.rich(
        conflictSyntaxSpan(
          context.meridian,
          _cellText(text),
          _syntax?.comparisonRuns(
            rowIndex,
            current: side == ConflictRegionChoice.current,
          ),
          backgrounds,
        ),
        maxLines: _wrap ? null : 1,
        softWrap: _wrap,
        overflow: TextOverflow.clip,
        style: style.copyWith(color: colors.ink),
      ),
    );
    final action = chosen ? _removeChoiceLabel(side) : _choiceLabel(side);
    Widget cell({bool hunkHovered = false, bool showAction = false}) =>
        MeridianAnimatedValue(
          value: chosen || hunkHovered ? 1 : 0,
          duration: MeridianDurations.select,
          builder: (context, railProgress, _) => Container(
            decoration: BoxDecoration(
              color: region == null
                  ? different
                        ? colors.attentionBg
                        : null
                  : sideColor.withValues(
                      alpha: hunkHovered
                          ? GitLamaOpacity.conflictHover
                          : chosen
                          ? GitLamaOpacity.conflictChosen
                          : GitLamaOpacity.conflictUnchosen,
                    ),
              // Every row keeps the rail's width so line numbers align.
              border: Border(
                left: BorderSide(
                  color: region == null
                      ? Colors.transparent
                      : sideColor.withValues(
                          alpha:
                              GitLamaOpacity.conflictRailUnchosen +
                              (GitLamaOpacity.conflictRailChosen -
                                      GitLamaOpacity.conflictRailUnchosen) *
                                  railProgress,
                        ),
                  width: GitLamaLayout.conflictChoiceRail,
                ),
              ),
            ),
            padding: const EdgeInsets.only(
              left: MeridianSpace.space3,
              right: MeridianSpace.space4,
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: GitLamaLayout.conflictLineColumnWidth,
                      child: Text(
                        line?.toString() ?? '',
                        textAlign: TextAlign.right,
                        style: _lineNumberStyle(
                          context,
                        ).copyWith(color: colors.inkMuted),
                      ),
                    ),
                    const SizedBox(width: MeridianSpace.space5),
                    Expanded(
                      child: _wrap
                          ? content
                          : MeridianHorizontalShift(
                              controller: _comparisonHorizontal,
                              child: content,
                            ),
                    ),
                  ],
                ),
                // What a click does, next to the pointer. The whole cell is
                // the button, so the label neither takes input nor speaks.
                if (showAction)
                  PositionedDirectional(
                    top: 0,
                    end: 0,
                    height: GitLamaLayout.conflictComparisonRowHeight,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Center(
                          child: MeridianChip(
                            key: ValueKey(
                              'conflict-hover-action-$rowIndex-${side.name}',
                            ),
                            label: action,
                            icon: chosen ? 'minus' : 'plus',
                            tone: MeridianChipTone.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
    if (region == null) return cell();
    final hunk = (region: region, side: side);
    return Semantics(
      button: true,
      selected: chosen,
      label: action,
      child: MouseRegion(
        onEnter: (_) => _hoveredHunk.value = hunk,
        onExit: (_) => _leaveHunk(hunk),
        child: MeridianInteraction(
          key: ValueKey('conflict-inline-$rowIndex-${side.name}'),
          canRequestFocus: firstInRegion,
          onTap: _busy ? null : () => _takeRegion(region, side, remove: chosen),
          builder: (context, state) => ValueListenableBuilder(
            valueListenable: _hoveredHunk,
            builder: (context, hovered, _) => cell(
              hunkHovered:
                  !_busy &&
                  (state.focused ||
                      (hovered?.region == region &&
                          (hovered?.side == side ||
                              hovered?.side == ConflictRegionChoice.both))),
              showAction: !_busy && (state.hovered || state.focused),
            ),
          ),
        ),
      ),
    );
  }

  void _leaveHunk(_Hunk hunk) {
    if (_hoveredHunk.value == hunk) _hoveredHunk.value = null;
  }

  /// A conflict's choices, each above the side it takes: "Take current"
  /// over the current lines, "Take incoming" and "Take both" over the
  /// incoming ones. Pointing at a choice lights the lines it takes.
  Widget _regionToolbar(int index) {
    final chosen = _draft!.blocks[index].choice;
    final colors = context.colors;
    final focused = index == _focusedRegion;
    Widget take(ConflictRegionChoice choice) {
      final remove =
          choice == chosen ||
          (chosen == ConflictRegionChoice.both &&
              choice != ConflictRegionChoice.both);
      final hunk = (region: index, side: choice);
      return MouseRegion(
        onEnter: (_) => _hoveredHunk.value = hunk,
        onExit: (_) => _leaveHunk(hunk),
        // Narrow columns shrink the button rather than overflow.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: MeridianButton(
            key: ValueKey('conflict-take-$index-${choice.name}'),
            label: remove ? _removeChoiceLabel(choice) : _choiceLabel(choice),
            icon: remove ? 'minus' : null,
            variant: choice == chosen
                ? MeridianButtonVariant.secondary
                : MeridianButtonVariant.quiet,
            size: MeridianControlSize.small,
            onPressed: _busy
                ? null
                : () => _takeRegion(index, choice, remove: remove),
          ),
        ),
      );
    }

    Widget half(List<Widget> children, {required bool rail}) => Container(
      padding: const EdgeInsetsDirectional.only(
        start: MeridianSpace.space3,
        end: MeridianSpace.space4,
      ),
      decoration: BoxDecoration(
        color: focused ? colors.accentSoft : colors.paneAlt,
        border: Border(
          left: BorderSide(
            color: rail
                ? focused
                      ? colors.accent
                      : colors.line
                : Colors.transparent,
            width: GitLamaLayout.conflictRail,
          ),
        ),
      ),
      child: Row(children: children),
    );

    return SizedBox(
      height: GitLamaLayout.conflictRegionToolbarHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: half(rail: true, [
              Flexible(child: take(ConflictRegionChoice.current)),
              const SizedBox(width: MeridianSpace.space4),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    context.l10n.conflictRegionNumber(index + 1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.label.copyWith(
                      color: focused ? colors.ink : colors.inkMuted,
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const MeridianHairline(axis: Axis.vertical),
          Expanded(
            child: half(rail: false, [
              Flexible(child: take(ConflictRegionChoice.incoming)),
              const SizedBox(width: MeridianSpace.space4),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: take(ConflictRegionChoice.both),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  String _choiceLabel(ConflictRegionChoice choice) => switch (choice) {
    ConflictRegionChoice.current => context.l10n.conflictTakeCurrent,
    ConflictRegionChoice.incoming => context.l10n.conflictTakeIncoming,
    ConflictRegionChoice.both => context.l10n.conflictTakeBoth,
  };

  String _removeChoiceLabel(ConflictRegionChoice choice) => switch (choice) {
    ConflictRegionChoice.current => context.l10n.conflictRemoveCurrent,
    ConflictRegionChoice.incoming => context.l10n.conflictRemoveIncoming,
    ConflictRegionChoice.both => context.l10n.conflictRemoveBoth,
  };

  Widget _result(ConflictFile file) => LayoutBuilder(
    builder: (context, constraints) => _resultPane(
      file,
      compact:
          constraints.maxHeight <
          GitLamaLayout.conflictResultCompactHeight *
              MediaQuery.textScalerOf(context).scale(1),
    ),
  );

  Widget _resultPane(ConflictFile file, {required bool compact}) {
    final mergeTools = _session?.mergeTools ?? const <IntegrationDefinition>[];
    final externalButton = compact && mergeTools.length <= 1
        ? MeridianIconButton(
            key: const Key('conflict-external-merge'),
            label: context.l10n.conflictExternalTool,
            icon: 'external-link',
            size: MeridianControlSize.small,
            onPressed: _busy || mergeTools.isEmpty
                ? null
                : () => unawaited(_externalMerge(mergeTools.single)),
          )
        : mergeTools.isEmpty
        ? MeridianButton(
            label: context.l10n.conflictExternalTool,
            disabledReason: context.l10n.conflictExternalUnavailable,
            onPressed: null,
            icon: 'external-link',
            size: MeridianControlSize.small,
          )
        : mergeTools.length == 1
        ? MeridianButton(
            key: const Key('conflict-external-merge'),
            label: context.l10n.conflictExternalTool,
            onPressed: _busy
                ? null
                : () => unawaited(_externalMerge(mergeTools.single)),
            icon: 'external-link',
            size: MeridianControlSize.small,
          )
        : NativeMenuButton<IntegrationDefinition>(
            key: const Key('conflict-external-merge'),
            enabled: !_busy,
            tooltip: context.l10n.conflictExternalTool,
            onSelected: (definition) => unawaited(_externalMerge(definition)),
            itemBuilder: (context) => [
              for (final definition in mergeTools)
                NativeMenuItem(value: definition, title: definition.id),
            ],
            icon: const MeridianIcon('external-link'),
          );
    // The menu of several merge tools opens at this button.
    final externalAction = KeyedSubtree(
      key: _externalMergeKey,
      child: externalButton,
    );
    if (file.kind != ConflictFileKind.text) {
      return _Pane(
        title: context.l10n.conflictResult,
        actions: [
          externalAction,
          if (compact)
            MeridianIconButton(
              label: context.l10n.conflictResolveFile,
              icon: 'save',
              size: MeridianControlSize.small,
              onPressed: _busy || _pendingWholeSide == null
                  ? null
                  : () => unawaited(_flushResult(showFailure: true)),
            )
          else
            MeridianButton(
              label: _resolveAction(file).$1,
              icon: _resolveAction(file).$2,
              variant: MeridianButtonVariant.primary,
              size: MeridianControlSize.small,
              onPressed: _busy || _pendingWholeSide == null
                  ? null
                  : () => unawaited(_flushResult(showFailure: true)),
            ),
        ],
        child: MeridianEmptyState(
          compact: true,
          icon: _deletionChosen(file) ? 'trash-2' : null,
          title: _deletionChosen(file)
              ? context.l10n.conflictDeletionResult
              : _pendingWholeSide != null
              ? context.l10n.conflictWholeFileChosenTitle(
                  _sideLabel(_pendingWholeSide!),
                )
              : file.kind == ConflictFileKind.binary
              ? context.l10n.conflictBinaryFile
              : context.l10n.conflictHugeFile,
          message: _pendingWholeSide == null
              ? context.l10n.conflictChooseVersion
              : null,
        ),
      );
    }
    return _Pane(
      title: context.l10n.conflictResult,
      actions: [
        externalAction,
        if (file.ancestor.present && compact)
          MeridianIconButton(
            label: _showAncestor
                ? context.l10n.conflictHideAncestor
                : context.l10n.conflictShowAncestor,
            icon: 'file-text',
            active: _showAncestor,
            size: MeridianControlSize.small,
            onPressed: () {
              setState(() => _showAncestor = !_showAncestor);
              if (_showAncestor) _syntax?.showAncestor();
              _followAfterLayout();
            },
          ),
        if (file.ancestor.present && !compact)
          MeridianButton(
            label: _showAncestor
                ? context.l10n.conflictHideAncestor
                : context.l10n.conflictShowAncestor,
            variant: MeridianButtonVariant.quiet,
            size: MeridianControlSize.small,
            onPressed: () {
              setState(() => _showAncestor = !_showAncestor);
              if (_showAncestor) _syntax?.showAncestor();
              _followAfterLayout();
            },
          ),
        if (compact)
          MeridianIconButton(
            label: _resolveAction(file).$1,
            icon: _resolveAction(file).$2,
            size: MeridianControlSize.small,
            onPressed:
                _busy ||
                    (hasConflictMarkers(_resultController.text) &&
                        _pendingWholeSide == null)
                ? null
                : () => unawaited(_flushResult(showFailure: true)),
          )
        else
          MeridianButton(
            label: _resolveAction(file).$1,
            variant: MeridianButtonVariant.primary,
            size: MeridianControlSize.small,
            onPressed:
                _busy ||
                    (hasConflictMarkers(_resultController.text) &&
                        _pendingWholeSide == null)
                ? null
                : () => unawaited(_flushResult(showFailure: true)),
            icon: _resolveAction(file).$2,
          ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            if (_showAncestor && file.ancestor.present)
              SizedBox(
                height: math.min(
                  GitLamaLayout.conflictAncestorHeight,
                  constraints.maxHeight * GitLamaLayout.resultMinHeightFraction,
                ),
                child: _Pane(
                  title: context.l10n.conflictAncestor,
                  child: SingleChildScrollView(
                    controller: _ancestorScroll,
                    padding: const EdgeInsets.all(MeridianSpace.space4),
                    child: ListenableBuilder(
                      listenable: _syntax ?? _noSyntax,
                      builder: (context, _) => SelectableText.rich(
                        contextMenuBuilder: nativeTextContextMenuBuilder,
                        conflictSyntaxText(
                          context.meridian,
                          _text(file.ancestor.content ?? const []),
                          _syntax?.ancestor,
                          [context.colors.pane],
                        ),
                        style: context.text.code.copyWith(
                          color: context.colors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_deletionChosen(file))
              Expanded(
                child: MeridianEmptyState(
                  key: const Key('conflict-deletion-result'),
                  compact: true,
                  icon: 'trash-2',
                  title: context.l10n.conflictDeletionResult,
                ),
              )
            else
              Expanded(
                child: MeridianTextField(
                  fieldKey: const Key('conflict-result-editor'),
                  controller: _resultController,
                  focusNode: _resultFocus,
                  scrollController: _resultScroll,
                  enabled: !_busy,
                  expands: true,
                  monospace: true,
                  // Lines as tall as comparison rows keep unchanged text level
                  // across the panes.
                  textStyle: context.text.code.copyWith(
                    height:
                        GitLamaLayout.conflictComparisonRowHeight /
                        context.text.code.fontSize!,
                  ),
                  minLines: 3,
                  maxLines: 8,
                  underlay: _ResultMarks(
                    controller: _resultController,
                    scroll: _resultScroll,
                    colors: _ResultMarkColors.of(context),
                    radius: context.meridian.radius.sm,
                  ),
                ),
              ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.only(
                  left: MeridianSpace.space5,
                  right: MeridianSpace.space5,
                  top: MeridianSpace.space2,
                  bottom: MeridianSpace.space4,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _pendingWholeSide != null
                        ? ''
                        : _markerCount == 0
                        ? context.l10n.conflictReviewResult
                        : context.l10n.conflictRegionsRemaining(_markerCount),
                    style: context.text.caption.copyWith(
                      color: context.colors.inkMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer(ConflictSnapshot snapshot) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: MeridianSpace.space5,
      vertical: MeridianSpace.space4,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            snapshot.files.isEmpty
                ? snapshot.operation == ConflictOperationKind.standalone
                      ? context.l10n.conflictStandaloneResolved
                      : context.l10n.conflictAllResolved
                : context.l10n.conflictFileProgress(
                    _selectedIndex + 1,
                    snapshot.files.length,
                  ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: MeridianSpace.space3),
        MeridianIconButton(
          label: context.l10n.conflictPreviousFile,
          icon: 'back',
          size: MeridianControlSize.small,
          onPressed: _busy || _selectedIndex <= 0
              ? null
              : () => _selectFile(_selectedIndex - 1),
        ),
        MeridianIconButton(
          label: context.l10n.conflictNextFile,
          icon: 'chevron-right',
          size: MeridianControlSize.small,
          onPressed: _busy || _selectedIndex >= snapshot.files.length - 1
              ? null
              : () => _selectFile(_selectedIndex + 1),
        ),
        if (snapshot.resolvedUndoPaths.isNotEmpty)
          NativeMenuButton<List<int>>(
            tooltip: context.l10n.conflictUndoResolution,
            enabled: !_busy,
            icon: const MeridianIcon('undo'),
            onSelected: _undo,
            itemBuilder: (context) => [
              for (final path in snapshot.resolvedUndoPaths)
                NativeMenuItem(
                  value: path,
                  title: switch (_outcome(path)) {
                    final outcome? => '${_path(path)} · $outcome',
                    null => _path(path),
                  },
                ),
            ],
          ),
      ],
    ),
  );
}

final class _Pane extends StatelessWidget {
  const _Pane({
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720 && actions.isNotEmpty;
          final label = Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyStrong.copyWith(color: context.colors.ink),
          );
          return Container(
            constraints: const BoxConstraints(
              minHeight: GitLamaLayout.conflictTitleMinHeight,
            ),
            padding: const EdgeInsets.only(
              left: MeridianSpace.space5,
              right: MeridianSpace.space4,
            ),
            color: context.colors.paneAlt,
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: GitLamaLayout.conflictTitleHeight,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: label,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: MeridianSpace.space2,
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: MeridianSpace.space2,
                          runSpacing: MeridianSpace.space2,
                          children: actions,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: label),
                      ...actions,
                    ],
                  ),
          );
        },
      ),
      Expanded(child: child),
    ],
  );
}

String _path(List<int> bytes) => _text(bytes).replaceAll('\\', '/');

String _text(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

/// Offsets closer than this count as the same place.
const double _scrollTolerance = 0.5;

/// How long a pane rests before colours follow what it shows.
const _syntaxSettle = Duration(milliseconds: 100);

/// Ancestor lines above the viewport's unwrapped rows that are coloured too.
const _ancestorWrapMargin = 64;

/// Stands in for absent colours, so panes listen to one thing either way.
final Listenable _noSyntax = ValueNotifier<int>(0);

/// The part of a comparison cell that does not hold text: the choice rail,
/// the line number and the padding around them.
const double _cellFixedWidth =
    GitLamaLayout.conflictChoiceRail +
    MeridianSpace.space3 +
    GitLamaLayout.conflictLineColumnWidth +
    MeridianSpace.space5 +
    MeridianSpace.space4;

typedef _Hunk = ({int region, ConflictRegionChoice side});

String _cellText(String line) => line.replaceAll('\n', '');

/// Comparison text: each line as tall as a row, like the result editor's,
/// with the glyphs centred in it.
TextStyle _comparisonStyle(BuildContext context) => context.text.code.copyWith(
  height:
      GitLamaLayout.conflictComparisonRowHeight / context.text.code.fontSize!,
  leadingDistribution: TextLeadingDistribution.even,
);

TextStyle _lineNumberStyle(BuildContext context) =>
    context.text.codeSm.copyWith(
      height:
          GitLamaLayout.conflictComparisonRowHeight /
          context.text.codeSm.fontSize!,
      leadingDistribution: TextLeadingDistribution.even,
    );

/// Heights and offsets of the comparison rows. A row is as tall as the
/// longer of its two sides once wrapped, in whole rows of text; the first
/// row of a conflict also carries the conflict's toolbar.
final class _ComparisonGeometry {
  _ComparisonGeometry._({
    required this.draft,
    required this.wrap,
    required this.textWidth,
    required this.style,
    required this.scaler,
    required List<int> lines,
    required this.contentWidth,
  }) : _lines = lines {
    extents = [
      for (var index = 0; index < lines.length; index++) extentOf(index),
    ];
    var top = 0.0;
    tops = [0, for (final extent in extents) top += extent];
  }

  /// Every row one line tall: the layout before the first measurement.
  factory _ComparisonGeometry.unwrapped(ConflictMergeDraft draft) =>
      _ComparisonGeometry._(
        draft: draft,
        wrap: false,
        textWidth: 0,
        style: null,
        scaler: TextScaler.noScaling,
        lines: List.filled(draft.rows.length, 1),
        contentWidth: 0,
      );

  factory _ComparisonGeometry.measure({
    required ConflictMergeDraft draft,
    required bool wrap,
    required double textWidth,
    required TextStyle style,
    required TextScaler scaler,
    required TextDirection direction,
  }) {
    final measure = _LineMeasure(style, scaler, direction);
    var contentWidth = 0.0;
    final lines = <int>[];
    for (final row in draft.rows) {
      final current = _cellText(row.current);
      final incoming = _cellText(row.incoming);
      if (wrap) {
        lines.add(
          math.max(
            measure.lines(current, textWidth),
            measure.lines(incoming, textWidth),
          ),
        );
      } else {
        lines.add(1);
        contentWidth = math.max(
          contentWidth,
          math.max(measure.width(current), measure.width(incoming)),
        );
      }
    }
    return _ComparisonGeometry._(
      draft: draft,
      wrap: wrap,
      textWidth: textWidth,
      style: style,
      scaler: scaler,
      lines: lines,
      contentWidth: contentWidth.ceilToDouble(),
    );
  }

  final ConflictMergeDraft draft;
  final bool wrap;
  final double textWidth;
  final TextStyle? style;
  final TextScaler scaler;

  /// Lines of text in each row.
  final List<int> _lines;

  /// The widest line of either side; the extent of unwrapped scrolling.
  final double contentWidth;

  /// Content offset of each row's top, toolbar included, and of the end.
  late final List<double> tops;

  /// Each row's extent in the list, toolbar included.
  late final List<double> extents;

  double rowHeight(int index) =>
      _lines[index] * GitLamaLayout.conflictComparisonRowHeight;

  double extentOf(int index) =>
      rowHeight(index) +
      (draft.blockFirstRows.contains(index)
          ? GitLamaLayout.conflictRegionToolbarHeight
          : 0);

  /// The row at content [offset].
  int rowAt(double offset) {
    var low = 0;
    var high = _lines.length - 1;
    if (high < 0) return 0;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (tops[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }
}

/// Measures comparison lines. Printable ASCII in the monospaced code face
/// is counted by its advance; anything else is laid out.
final class _LineMeasure {
  _LineMeasure(this._style, this._scaler, this._direction) {
    final probe = _painter('M')..layout();
    _advance = probe.width;
    probe.dispose();
  }

  final TextStyle _style;
  final TextScaler _scaler;
  final TextDirection _direction;
  late final double _advance;

  TextPainter _painter(String text, {int? maxLines}) => TextPainter(
    text: TextSpan(text: text, style: _style),
    textDirection: _direction,
    textScaler: _scaler,
    maxLines: maxLines,
  );

  static bool _plain(String text) {
    for (final unit in text.codeUnits) {
      if (unit < 0x20 || unit > 0x7e) return false;
    }
    return true;
  }

  double width(String text) {
    if (_plain(text)) return text.length * _advance;
    final painter = _painter(text, maxLines: 1)..layout();
    try {
      return painter.width;
    } finally {
      painter.dispose();
    }
  }

  /// Lines [text] takes when wrapped at [maxWidth].
  int lines(String text, double maxWidth) {
    if (text.isEmpty || (_plain(text) && text.length * _advance <= maxWidth)) {
      return 1;
    }
    final painter = _painter(text)..layout(maxWidth: math.max(1, maxWidth));
    try {
      return math.max(1, painter.computeLineMetrics().length);
    } finally {
      painter.dispose();
    }
  }
}

typedef _ScrollMapKey = ({
  String text,
  ConflictMergeDraft? draft,
  double comparisonMax,
  double resultMax,
  double comparisonLine,
  double resultLine,
  _ComparisonGeometry? geometry,
  double? width,
});

final class _MergeResultController extends TextEditingController {
  ConflictMergeDraft? draft;
  ConflictSyntax? _syntax;

  /// The colours of the shown file; the text restyles when they arrive.
  set syntax(ConflictSyntax? value) {
    if (identical(value, _syntax)) return;
    _syntax?.removeListener(notifyListeners);
    _syntax = value;
    value?.addListener(notifyListeners);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final view = _syntax?.result;
    final coloured = view != null && view.text == text && view.hasColours;
    if (!coloured) return TextSpan(style: style, text: text);
    final colors = context.colors;
    final pane = colors.pane;
    // Every fill under the text: the chosen-block marks and the selection.
    final palette = syntaxPalette(context.meridian.syntax, colors.ink, [
      pane,
      colors.paneAlt,
      Color.alphaBlend(colors.accentSoft, pane),
      for (final fill in _ResultMarkColors.of(context).fills)
        Color.alphaBlend(fill, pane),
    ]);
    // Each coloured run of text, by UTF-16 range, in order.
    final inks = <(int, int, Color)>[];
    final lines = view.lineCount;
    for (final line in view.colouredLines) {
      if (line > lines) break;
      final start = view.lineStart(line);
      final end = line < lines ? view.lineStart(line + 1) - 1 : text.length;
      final runs = meridianSyntaxRuns(view.runsOf(line)!);
      if (!meridianSyntaxRunsValid(text.substring(start, end), runs)) {
        continue;
      }
      for (final run in runs) {
        inks.add((
          start + run.start,
          start + run.end,
          palette.colorOf(run.kind),
        ));
      }
    }
    final cuts = <int>{
      0,
      text.length,
      for (final (start, end, _) in inks) ...[start, end],
    }.toList()..sort();
    final spans = <TextSpan>[];
    var ink = 0;
    for (var index = 0; index + 1 < cuts.length; index += 1) {
      final start = cuts[index];
      final end = cuts[index + 1];
      while (ink < inks.length && inks[ink].$2 <= start) {
        ink += 1;
      }
      final foreground = ink < inks.length && inks[ink].$1 <= start
          ? inks[ink].$3
          : null;
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: foreground == null ? null : TextStyle(color: foreground),
        ),
      );
    }
    return TextSpan(style: style, children: spans);
  }
}

/// The fill and rail of each kind of block in the merge result. None is
/// `accent-soft`, the selection colour, so a selection over a block shows.
final class _ResultMarkColors {
  _ResultMarkColors.of(BuildContext context)
    : open = (
        context.colors.attentionBg,
        context.colors.attention.withValues(
          alpha: GitLamaOpacity.conflictRailChosen,
        ),
      ),
      current = _side(context.git.sideOurs),
      incoming = _side(context.git.sideTheirs);

  static (Color, Color) _side(Color color) => (
    color.withValues(alpha: GitLamaOpacity.conflictUnchosen),
    color.withValues(alpha: GitLamaOpacity.conflictRailChosen),
  );

  /// An unresolved conflict.
  final (Color, Color) open;

  /// Text taken from the current side.
  final (Color, Color) current;

  /// Text taken from the incoming side.
  final (Color, Color) incoming;

  Iterable<Color> get fills => [open.$1, current.$1, incoming.$1];
}

/// The marks of [draft]'s blocks in [text], by UTF-16 range, in order: an
/// unresolved block, or the parts taken from each side. A block that keeps
/// both sides shows the current part and then the incoming part.
List<(int, int, (Color, Color))> _resultMarks(
  String text,
  ConflictMergeDraft? draft,
  _ResultMarkColors colors,
) {
  final marks = <(int, int, (Color, Color))>[];
  var offset = 0;
  for (final block in draft?.blocks ?? const <MergeDraftBlock>[]) {
    final start = block.start.clamp(offset, text.length);
    final end = block.end.clamp(start, text.length);
    offset = end;
    switch (block.choice) {
      case null:
        marks.add((start, end, colors.open));
      case ConflictRegionChoice.current:
        marks.add((start, end, colors.current));
      case ConflictRegionChoice.incoming:
        marks.add((start, end, colors.incoming));
      case ConflictRegionChoice.both:
        final split = (start + block.current.length).clamp(start, end);
        marks
          ..add((start, split, colors.current))
          ..add((split, end, colors.incoming));
    }
  }
  return marks;
}

/// Paints the merge result's block marks as whole-line bands under the
/// editor's text and selection, in step with its text and scroll offset.
final class _ResultMarks extends LeafRenderObjectWidget {
  const _ResultMarks({
    required this.controller,
    required this.scroll,
    required this.colors,
    required this.radius,
  });

  final _MergeResultController controller;
  final ScrollController scroll;
  final _ResultMarkColors colors;
  final double radius;

  @override
  _RenderResultMarks createRenderObject(BuildContext context) =>
      _RenderResultMarks(controller, scroll, colors, radius);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderResultMarks renderObject,
  ) {
    renderObject
      ..listenable = Listenable.merge([controller, scroll])
      ..controller = controller
      ..colors = colors
      ..radius = radius
      // The draft's choices can change without a text change.
      ..markNeedsPaint();
  }
}

final class _RenderResultMarks extends RenderBox {
  _RenderResultMarks(
    this.controller,
    ScrollController scroll,
    this.colors,
    this.radius,
  ) : _listenable = Listenable.merge([controller, scroll]);

  _MergeResultController controller;
  _ResultMarkColors colors;
  double radius;

  Listenable _listenable;
  set listenable(Listenable value) {
    if (attached) {
      _listenable.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _listenable = value;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listenable.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _listenable.removeListener(markNeedsPaint);
    _editable = null;
    super.detach();
  }

  RenderEditable? _editable;

  /// The editor this box lies under: the editable text in the same stack.
  RenderEditable? get _field {
    final known = _editable;
    if (known != null && known.attached) return known;
    RenderObject? stack = parent;
    while (stack != null && stack is! RenderStack) {
      stack = stack.parent;
    }
    RenderEditable? found;
    void visit(RenderObject node) {
      if (found != null || identical(node, this)) return;
      if (node is RenderEditable) {
        found = node;
      } else {
        node.visitChildren(visit);
      }
    }

    stack?.visitChildren(visit);
    return _editable = found;
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final text = controller.text;
    final field = _field;
    if (field == null || field.plainText != text) return;
    final marks = _resultMarks(text, controller.draft, colors);
    if (marks.isEmpty) return;
    const row = GitLamaLayout.conflictComparisonRowHeight;
    final scrolled = field.offset.pixels;
    // The editor's content top, in this box.
    final top = globalToLocal(field.localToGlobal(Offset.zero)).dy - scrolled;
    double rowOf(TextPosition position) =>
        ((field.getLocalRectForCaret(position).center.dy + scrolled) / row)
            .floor() *
        row;
    final canvas = context.canvas
      ..save()
      ..clipRect(offset & size);
    for (final (start, end, (fill, rail)) in marks) {
      // A trailing line break ends the band on its line.
      final last = end > start && text.codeUnitAt(end - 1) == 0x0A
          ? end - 1
          : end;
      final from = top + rowOf(TextPosition(offset: start));
      final to = end == start
          ? from
          : top +
                rowOf(
                  TextPosition(offset: last, affinity: TextAffinity.upstream),
                ) +
                row;
      if (to < 0 || from > size.height) continue;
      if (to == from) {
        // An empty block (a side that deletes) is a rule where it was.
        canvas.drawRect(
          Rect.fromLTWH(
            offset.dx,
            offset.dy + from - GitLamaLayout.conflictChoiceRail / 2,
            size.width,
            GitLamaLayout.conflictChoiceRail,
          ),
          Paint()..color = rail,
        );
        continue;
      }
      final band = Rect.fromLTRB(
        offset.dx,
        offset.dy + from,
        offset.dx + size.width,
        offset.dy + to,
      );
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(band, Radius.circular(radius)),
          Paint()..color = fill,
        )
        ..drawRect(
          Rect.fromLTWH(
            band.left,
            band.top,
            GitLamaLayout.conflictChoiceRail,
            band.height,
          ),
          Paint()..color = rail,
        );
    }
    canvas.restore();
  }
}

/// The file actions of the conflict queue.
final class _ConflictActionHost extends FileActionHost {
  _ConflictActionHost(this._state);

  final ConflictResolverState _state;

  ConflictResolver get _widget => _state.widget;

  @override
  Set<FileAction> get capabilities => {
    FileAction.copyPath,
    if (_widget.onOpenWorkingFile != null) ...{
      FileAction.openExternally,
      FileAction.revealInFileBrowser,
    },
    if (_widget.onInspect != null) ...{
      FileAction.blame,
      FileAction.fileHistory,
    },
  };

  @override
  String get fileBrowserName => _widget.fileBrowserName;

  @override
  String? inspectionUnavailableReason(BuildContext context) =>
      _widget.inspectionUnavailableReason;

  @override
  void run(
    FileActionCommand command,
    FileActionSubject subject, {
    required bool invert,
  }) {
    switch (command.action) {
      case FileAction.copyPath:
        unawaited(_copy(_path(subject.path)));
      case FileAction.openExternally:
        _widget.onOpenWorkingFile?.call(subject.path, reveal: false);
      case FileAction.revealInFileBrowser:
        _widget.onOpenWorkingFile?.call(subject.path, reveal: true);
      case FileAction.blame:
        _widget.onInspect?.call(
          subject.path,
          InspectorLens.blame,
          directory: false,
          invert: invert,
        );
      case FileAction.fileHistory:
        _widget.onInspect?.call(
          subject.path,
          InspectorLens.history,
          directory: false,
          invert: invert,
        );
      default:
        break;
    }
  }

  Future<void> _copy(String text) async {
    if (_state.mounted) await copyPathWithNotification(_state.context, text);
  }
}

/// A conflicted file's tick in the file list: a checkbox without a visible
/// label, since the row shows the path.
final class _FileCheckbox extends StatelessWidget {
  const _FileCheckbox({
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: MeridianSpace.space3),
    child: SizedBox(
      width: MeridianLayout.checkboxSize,
      // The checkbox's label is empty (the path is the row); its empty
      // label area overflows the slot invisibly.
      child: OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: 0,
        maxWidth: double.infinity,
        child: MergeSemantics(
          child: Semantics(
            label: label,
            child: MeridianCheckbox(
              value: checked,
              label: '',
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    ),
  );
}
