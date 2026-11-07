import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import '../app/byte_size.dart';
import '../models/diff.dart';
import '../models/diff_syntax.dart';
import '../services/diff_syntax_service.dart';
import 'syntax_colours.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';
import 'native_menu.dart';
import 'status_notification.dart';

typedef DiffRowProvider = DiffDisplayRow Function(int index);
typedef DiffTextStyler =
    TextSpan Function(BuildContext context, DiffDisplayRow row);

/// Context menu entries a pane adds above Copy for the selected [rowIds],
/// in display order.
typedef DiffMenuItems = List<NativeMenuAction> Function(List<String> rowIds);

/// A unified patch of the change lines among [rowIds], or null when there is
/// none.
typedef DiffSelectionPatch = Future<List<int>?> Function(List<String> rowIds);

/// The actions shown on the selected lines [rowIds], or null for none.
typedef DiffSelectionActions = Widget? Function(List<String> rowIds);

/// Whether [row] can join a line selection: loaded text lines, context
/// included, so Copy takes what the reader sees.
bool isDiffLineRow(DiffDisplayRow row) =>
    !row.loading &&
    (row.kind == DiffRowKind.addition ||
        row.kind == DiffRowKind.deletion ||
        row.kind == DiffRowKind.context);

/// Fixed-extent diff surface. It never creates widgets for off-screen rows.
///
/// Text is selected like in an editor: click, drag, double-click for a
/// word, triple-click or the gutter for whole lines, Shift-click and
/// Shift+arrows to extend, and a hunk header selects its hunk. Every line the
/// text selection touches is selected implicitly; [selectedIds] reports
/// those lines, and the panes stage, unstage, discard and patch them. Copy
/// takes the selected text, Copy as Patch the selected lines. Without
/// wrapping, long lines scroll horizontally under fixed line number
/// gutters; hunk headers and their actions stay in place.
class DiffView extends StatefulWidget {
  const DiffView({
    required this.itemCount,
    required this.rowAt,
    required this.layout,
    required this.selectedIds,
    required this.onSelectionChanged,
    this.textStyler,
    this.syntax,
    this.controller,
    this.rowExtent = GitLamaLayout.diffLineHeight,
    this.wrap = false,
    this.showIndicators = true,
    this.encoding = DiffTextEncoding.utf8,
    this.searchMatchIds = const {},
    this.currentSearchId,
    this.searchMatchIndices = const {},
    this.currentSearchIndex,
    this.onImageActivate,
    this.onShowAsText,
    this.hunkActions,
    this.selectionActions,
    this.hunkIndices = const {},
    this.fallbackIndices = const {},
    this.loadedRows = const [],
    this.fileSections = const {},
    this.collapsibleFiles = false,
    this.collapseReset = 0,
    this.onShowMoreContext,
    this.onFileCollapseChanged,
    this.revealContextIds = const {},
    this.menuItems,
    this.onCopyPatch,
    super.key,
  });

  final int itemCount;
  final DiffRowProvider rowAt;
  final DiffViewLayout layout;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onSelectionChanged;
  final DiffTextStyler? textStyler;

  /// Syntax colours of the shown projection: an overlay that arrives after
  /// the text, applied only to rows the view shows. Null shows plain text.
  final DiffSyntaxView? syntax;
  final ScrollController? controller;
  final double rowExtent;
  final bool wrap;
  final bool showIndicators;
  final DiffTextEncoding encoding;
  final Set<String> searchMatchIds;
  final String? currentSearchId;
  final Set<int> searchMatchIndices;
  final int? currentSearchIndex;
  final ValueChanged<DiffDisplayRow>? onImageActivate;

  /// Reloads the diff with binary files compared as text; null offers no
  /// such action on binary rows.
  final VoidCallback? onShowAsText;
  final Widget Function(DiffDisplayRow row)? hunkActions;

  /// Actions floating at the top end of the selected lines, for the selected
  /// row ids in display order; null shows none.
  final DiffSelectionActions? selectionActions;
  final Set<int> hunkIndices;
  final Set<int> fallbackIndices;

  /// The rows loaded so far; the widest one sets the horizontal scroll
  /// extent.
  final Iterable<DiffDisplayRow> loadedRows;

  /// Loaded file headers indexed by their physical row offset. Each header
  /// carries an exclusive [DiffDisplayRow.sectionEnd] from the native page.
  final Map<int, DiffDisplayRow> fileSections;
  final bool collapsibleFiles;
  final int collapseReset;
  final VoidCallback? onShowMoreContext;
  final ValueChanged<bool>? onFileCollapseChanged;
  final Set<String> revealContextIds;
  final DiffMenuItems? menuItems;
  final DiffSelectionPatch? onCopyPatch;

  @override
  State<DiffView> createState() => _DiffViewState();
}

/// A caret position: a physical row and a UTF-16 offset into its displayed
/// text. [oldSide] is the split column the pointer was over.
@immutable
class _TextPoint implements Comparable<_TextPoint> {
  const _TextPoint(
    this.index,
    this.offset, {
    this.oldSide,
    this.gutter = false,
  });

  final int index;
  final int offset;
  final bool? oldSide;
  final bool gutter;

  @override
  int compareTo(_TextPoint other) => index != other.index
      ? index.compareTo(other.index)
      : offset.compareTo(other.offset);

  bool samePosition(_TextPoint other) => compareTo(other) == 0;
}

enum _Granularity { character, word, line }

class _DiffViewState extends State<DiffView> {
  // The mutation boundary accepts at most 4096 exact row identities.
  static const _maximumSelection = 4096;

  // How far apart two presses of a multi-click may land: a mouse stays put.
  static const _clickSlop = MeridianSpace.space3;

  final _viewport = GlobalKey();
  final _focus = FocusNode();
  late final _ownedScroll = ScrollController();
  final _horizontal = ScrollController();
  ScrollController get _scroll => widget.controller ?? _ownedScroll;
  final _registry = _DiffHitRegistry();
  final _actionsLink = LayerLink();

  // The text selection. [_base] stays put while [_extent] follows the
  // pointer or the keyboard.
  _TextPoint? _base;
  _TextPoint? _extent;
  String? _baseId;
  String? _extentId;
  var _granularity = _Granularity.character;
  bool? _selectionOld;
  TextRange _anchorWord = TextRange.empty;

  // Pointer state.
  var _dragActive = false;
  var _pointerClaimed = false;
  Offset? _dragPosition;
  Timer? _autoScroll;
  Duration? _lastDownTime;
  Offset? _lastDownPosition;
  var _clickCount = 0;

  /// Display index of each row this view selected, for ordered copies.
  final Map<String, int> _selectedIndex = {};

  /// The line ids last reported; a different [DiffView.selectedIds] means
  /// the owner replaced the selection.
  Set<String> _emitted = {};
  Object? _widthKey;
  double _textWidth = 0;
  final Set<int> _collapsedFiles = {};
  final Set<int> _expandingFiles = {};
  Timer? _expandTimer;

  List<({int start, int end})> get _collapsedRanges => [
    for (final start in _collapsedFiles.toList()..sort())
      if (widget.fileSections[start]?.sectionEnd case final int end)
        if (end > start + 1 && end <= widget.itemCount)
          (start: start, end: end),
  ];

  int get _visibleCount =>
      widget.itemCount -
      _collapsedRanges.fold<int>(
        0,
        (hidden, range) => hidden + range.end - range.start - 1,
      );

  int _physicalAt(int visible) {
    var hidden = 0;
    for (final range in _collapsedRanges) {
      if (visible <= range.start - hidden) break;
      hidden += range.end - range.start - 1;
    }
    return visible + hidden;
  }

  bool _isHidden(int physical) => _collapsedRanges.any(
    (range) => physical > range.start && physical < range.end,
  );

  void _toggleFile(int start) {
    if (widget.fileSections[start]?.sectionEnd case final int end) {
      if (end <= start + 1) return;
      final collapsing = !_collapsedFiles.contains(start);
      setState(() {
        if (!_collapsedFiles.remove(start)) {
          _collapsedFiles.add(start);
          _expandingFiles.remove(start);
        } else {
          _expandingFiles.add(start);
        }
      });
      widget.onFileCollapseChanged?.call(_collapsedFiles.isNotEmpty);
      if (!collapsing) {
        _expandTimer?.cancel();
        _expandTimer = Timer(MeridianDurations.layout, () {
          if (mounted) setState(_expandingFiles.clear);
        });
      }
      // A selection cannot run through hidden lines.
      if (collapsing &&
          (_selectedIndex.values.any((index) => index > start && index < end) ||
              [_base, _extent].any(
                (point) =>
                    point != null && point.index > start && point.index < end,
              ))) {
        _clearSelection();
      }
      if (_scroll.positions.length == 1) {
        final target = _extentBefore(_visibleIndexForPhysical(start));
        if (_scroll.offset > target) _scroll.jumpTo(target);
      }
    }
  }

  int _visibleIndexForPhysical(int physical) {
    var hidden = 0;
    for (final range in _collapsedRanges) {
      if (physical < range.end) break;
      hidden += range.end - range.start - 1;
    }
    return physical - hidden;
  }

  int _nextVisible(int physical, int direction) {
    var next = (physical + direction).clamp(0, widget.itemCount - 1);
    while (_isHidden(next) && next > 0 && next < widget.itemCount - 1) {
      next += direction;
    }
    return next;
  }

  @override
  void initState() {
    super.initState();
    _emitted = widget.selectedIds.toSet();
    _attachSyntax();
  }

  /// Follows the syntax overlay; reports the visible rows once laid out.
  void _attachSyntax() {
    final syntax = widget.syntax;
    if (syntax == null) return;
    syntax.addListener(_syntaxChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(widget.syntax, syntax)) _reportVisible();
    });
  }

  void _syntaxChanged() {
    if (mounted) setState(() {});
  }

  /// Tells the syntax overlay which rows are on screen. Only after layout
  /// and when scrolling settles, never from build.
  void _reportVisible() {
    final syntax = widget.syntax;
    if (syntax == null ||
        !_scroll.hasClients ||
        _scroll.positions.length != 1 ||
        _visibleCount == 0) {
      return;
    }
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    syntax.setVisible(
      _physicalAt(_visibleAtOffset(position.pixels)),
      _physicalAt(
        _visibleAtOffset(position.pixels + position.viewportDimension),
      ),
    );
  }

  /// The visible row index at scroll [offset].
  int _visibleAtOffset(double offset) {
    var low = 0;
    var high = _visibleCount - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_extentBefore(middle) <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  bool _scrollChanged(ScrollNotification notification) {
    final syntax = widget.syntax;
    if (syntax == null || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      syntax.setInteracting(true);
    } else if (notification is ScrollEndNotification) {
      syntax.setInteracting(false);
      _reportVisible();
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant DiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.syntax, widget.syntax)) {
      oldWidget.syntax?.removeListener(_syntaxChanged);
      _attachSyntax();
    }
    if (oldWidget.collapseReset != widget.collapseReset ||
        !widget.collapsibleFiles) {
      _collapsedFiles.clear();
      _expandingFiles.clear();
    }
    // The owner replaced or trimmed the selection: the text range no longer
    // describes it.
    if (!setEquals(widget.selectedIds, _emitted)) {
      _dropRange();
      _emitted = widget.selectedIds.toSet();
    } else if (!_endpointValid(_base, _baseId) ||
        !_endpointValid(_extent, _extentId)) {
      // A reloaded diff moved or dropped the selected text.
      _dropRange();
    }
    // A reloaded diff may move or drop selected rows.
    _selectedIndex.removeWhere(
      (id, index) =>
          !widget.selectedIds.contains(id) ||
          index >= widget.itemCount ||
          widget.rowAt(index).stableId != id,
    );
    if (oldWidget.itemCount != widget.itemCount && _horizontal.hasClients) {
      _horizontal.jumpTo(0);
    }
  }

  bool _endpointValid(_TextPoint? point, String? id) =>
      point == null ||
      (point.index < widget.itemCount &&
          widget.rowAt(point.index).stableId == id);

  @override
  void dispose() {
    widget.syntax?.removeListener(_syntaxChanged);
    _autoScroll?.cancel();
    _expandTimer?.cancel();
    _ownedScroll.dispose();
    _horizontal.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;

  bool get _commandModifier => _mac
      ? HardwareKeyboard.instance.isMetaPressed
      : HardwareKeyboard.instance.isControlPressed;

  /// The current selection in display order.
  List<String> get _orderedSelection {
    final entries = [
      for (final id in widget.selectedIds)
        if (_selectedIndex[id] case final index?) (id, index),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final entry in entries) entry.$1];
  }

  String _rowText(int index) => _decode(
    widget.rowAt(index).text,
    widget.encoding,
    context.l10n.diffEncodingInvalid,
  );

  int _textLength(int index) =>
      isDiffLineRow(widget.rowAt(index)) ? _rowText(index).length : 0;

  /// Whether the text selection selects anything: a character range, or
  /// whole lines even when they are empty.
  bool get _hasRange =>
      _base != null &&
      _extent != null &&
      (_granularity == _Granularity.line || !_base!.samePosition(_extent!));

  (_TextPoint, _TextPoint) get _ordered =>
      _base!.compareTo(_extent!) <= 0 ? (_base!, _extent!) : (_extent!, _base!);

  void _dropRange() {
    _base = null;
    _extent = null;
    _baseId = null;
    _extentId = null;
  }

  void _clearSelection() {
    setState(_dropRange);
    _emitLines();
  }

  /// Sets the text selection and reports the lines it touches.
  void _select(
    _TextPoint base,
    _TextPoint extent, {
    _Granularity granularity = _Granularity.character,
  }) {
    final limit = _maximumSelection - 1;
    if ((extent.index - base.index).abs() > limit) {
      final index = extent.index > base.index
          ? base.index + limit
          : base.index - limit;
      extent = _TextPoint(
        index,
        extent.index > base.index ? _textLength(index) : 0,
      );
    }
    setState(() {
      _base = base;
      _extent = extent;
      _baseId = widget.rowAt(base.index).stableId;
      _extentId = widget.rowAt(extent.index).stableId;
      _granularity = granularity;
    });
    _emitLines();
  }

  /// Reports the lines the text selection touches. A selection that ends at
  /// the start of a line, or starts at the end of one, leaves that line out.
  void _emitLines() {
    final next = <String, int>{};
    if (_hasRange) {
      final (start, end) = _ordered;
      var first = start.index;
      var last = end.index;
      if (_granularity != _Granularity.line) {
        if (last > first && end.offset == 0) last--;
        if (last > first && start.offset > 0) {
          if (start.offset >= _textLength(first)) first++;
        }
      }
      for (var index = first; index <= last; index++) {
        final row = widget.rowAt(index);
        if (!_isHidden(index) &&
            isDiffLineRow(row) &&
            next.length < _maximumSelection) {
          next[row.stableId] = index;
        }
      }
    }
    _selectedIndex
      ..clear()
      ..addAll(next);
    final ids = next.keys.toSet();
    if (setEquals(ids, _emitted)) return;
    _emitted = ids;
    widget.onSelectionChanged(ids);
  }

  /// Selects whole lines from [anchor] to [target].
  void _selectLines(int anchor, int target) => _select(
    _TextPoint(anchor, target >= anchor ? 0 : _textLength(anchor)),
    _TextPoint(target, target >= anchor ? _textLength(target) : 0),
    granularity: _Granularity.line,
  );

  /// Selects the lines of the hunk whose header is at [index].
  void _selectHunk(int index) {
    int? first;
    int? last;
    var count = 0;
    for (
      var cursor = index + 1;
      cursor < widget.itemCount && count < _maximumSelection;
      cursor++
    ) {
      final row = widget.rowAt(cursor);
      if (row.kind == DiffRowKind.hunk || row.kind == DiffRowKind.file) break;
      if (!isDiffLineRow(row)) continue;
      first ??= cursor;
      last = cursor;
      count++;
    }
    if (first == null || last == null) return;
    _focus.requestFocus();
    _selectLines(first, last);
  }

  RenderBox? get _viewportBox =>
      _viewport.currentContext?.findRenderObject() as RenderBox?;

  int _indexAt(Offset global) {
    final box = _viewportBox!;
    final y = box.globalToLocal(global).dy.clamp(0.0, box.size.height - 1);
    return _physicalAt(_indexForOffset(y + _scroll.offset));
  }

  /// The text position under [global]. The pointer's height is clamped to
  /// the viewport so a drag past an edge reaches the edge row. Row and text
  /// geometry come from the laid-out rows, so wrapped lines map exactly.
  _TextPoint? _pointAt(Offset global, {bool? preferOld}) {
    final box = _viewportBox;
    if (box == null || !box.hasSize || widget.itemCount == 0) return null;
    final local = box.globalToLocal(global);
    final probe = box.localToGlobal(
      Offset(local.dx, local.dy.clamp(0.0, box.size.height - 1)),
    );
    final hit = _registry.rowAt(probe);
    if (hit == null) {
      final index = _indexAt(global);
      return _TextPoint(index, local.dy < 0 ? 0 : _textLength(index));
    }
    final index = hit;
    if (!isDiffLineRow(widget.rowAt(index))) return _TextPoint(index, 0);
    final cell = _registry.cellAt(index, probe, preferOld: preferOld);
    if (cell == null) return _TextPoint(index, 0);
    final inCell = cell.globalToLocal(probe);
    if (inCell.dx < 0) {
      return _TextPoint(index, 0, oldSide: cell.oldSide, gutter: true);
    }
    return _TextPoint(
      index,
      cell.offsetAt(inCell).clamp(0, _textLength(index)),
      oldSide: cell.oldSide,
    );
  }

  TextRange _wordAt(_TextPoint point) {
    final cell = _registry.cell(point.index, point.oldSide);
    final word = cell?.wordAt(point.offset);
    return word == null || !word.isValid
        ? TextRange.collapsed(point.offset)
        : word;
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointerClaimed) {
      _pointerClaimed = false;
      _dragActive = false;
      return;
    }
    _dragActive = false;
    if (event.buttons != kPrimaryButton) return;
    final box = _viewportBox;
    if (box == null || !box.hasSize) return;
    // The trailing strip belongs to the vertical scrollbar.
    if (box.globalToLocal(event.position).dx >
        box.size.width - MeridianSpace.space6) {
      return;
    }
    final point = _pointAt(event.position);
    if (point == null || !isDiffLineRow(widget.rowAt(point.index))) return;
    _focus.requestFocus();
    _dragActive = true;
    final repeat =
        _lastDownTime != null &&
        event.timeStamp - _lastDownTime! <= kDoubleTapTimeout &&
        (event.position - _lastDownPosition!).distance <= _clickSlop;
    _clickCount = repeat ? _clickCount % 3 + 1 : 1;
    _lastDownTime = event.timeStamp;
    _lastDownPosition = event.position;
    _selectionOld = point.oldSide;
    if (HardwareKeyboard.instance.isShiftPressed && _base != null) {
      _clickCount = 1;
      if (point.gutter || _granularity == _Granularity.line) {
        _selectLines(_base!.index, point.index);
      } else {
        _select(_base!, point, granularity: _granularity);
      }
      return;
    }
    if (point.gutter || _clickCount == 3) {
      _granularity = _Granularity.line;
      _selectLines(point.index, point.index);
    } else if (_clickCount == 2) {
      final word = _wordAt(point);
      _anchorWord = word;
      _select(
        _TextPoint(point.index, word.start, oldSide: point.oldSide),
        _TextPoint(point.index, word.end, oldSide: point.oldSide),
        granularity: _Granularity.word,
      );
    } else {
      _select(point, point);
    }
  }

  /// Moves the selection's moving end to [global], in the granularity the
  /// selection started with.
  void _extendTo(Offset global) {
    final base = _base;
    if (base == null) return;
    final point = _pointAt(global, preferOld: _selectionOld);
    if (point == null) return;
    switch (_granularity) {
      case _Granularity.character:
        _select(base, point);
      case _Granularity.line:
        _selectLines(base.index, point.index);
      case _Granularity.word:
        final start = _TextPoint(base.index, _anchorWord.start);
        final word = _wordAt(point);
        if (point.compareTo(start) < 0) {
          _select(
            _TextPoint(base.index, _anchorWord.end),
            _TextPoint(point.index, word.start),
            granularity: _Granularity.word,
          );
        } else {
          _select(
            start,
            _TextPoint(point.index, word.end),
            granularity: _Granularity.word,
          );
        }
    }
  }

  void _dragStart(DragStartDetails details) {
    if (!_dragActive) return;
    _dragPosition = details.globalPosition;
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 32), (_) {
      final point = _dragPosition;
      final box = _viewportBox;
      if (point == null || box == null || !_scroll.hasClients) return;
      final y = box.globalToLocal(point).dy;
      final delta = y < 24
          ? -widget.rowExtent
          : y > box.size.height - 24
          ? widget.rowExtent
          : 0.0;
      if (delta == 0) return;
      _scroll.jumpTo(
        (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
      );
      // The rows reach their new positions in the next layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dragActive) _extendTo(point);
      });
    });
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_dragActive) return;
    _dragPosition = details.globalPosition;
    _extendTo(details.globalPosition);
  }

  void _endDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragPosition = null;
    _dragActive = false;
  }

  void _tapHunk(int index) {
    _selectionOld = null;
    _selectHunk(index);
  }

  /// The selected text; without a text selection, the selected lines.
  String _selectionText() {
    if (!_hasRange) {
      return [
        for (final id in _orderedSelection) _rowText(_selectedIndex[id]!),
      ].join('\n');
    }
    final (start, end) = _ordered;
    final lines = <String>[];
    for (var index = start.index; index <= end.index; index++) {
      if (_isHidden(index) || !isDiffLineRow(widget.rowAt(index))) continue;
      final text = _rowText(index);
      final from = index == start.index
          ? start.offset.clamp(0, text.length)
          : 0;
      final to = index == end.index
          ? end.offset.clamp(from, text.length)
          : text.length;
      lines.add(text.substring(from, to));
    }
    return lines.join('\n');
  }

  bool get _canCopy => _hasRange || _orderedSelection.isNotEmpty;

  Future<void> _copyText() async {
    if (!_canCopy) return;
    await Clipboard.setData(ClipboardData(text: _selectionText()));
    if (mounted) {
      StatusNotificationScope.show(context, context.l10n.diffSelectionCopied);
    }
  }

  Future<void> _copyPatch() async {
    final ids = _orderedSelection;
    final build = widget.onCopyPatch;
    if (ids.isEmpty || build == null) return;
    final patch = await build(ids);
    if (!mounted) return;
    if (patch == null || patch.isEmpty) {
      StatusNotificationScope.show(context, context.l10n.diffPatchUnavailable);
      return;
    }
    await Clipboard.setData(
      ClipboardData(
        text: widget.encoding == DiffTextEncoding.latin1
            ? latin1.decode(patch)
            : utf8.decode(patch, allowMalformed: true),
      ),
    );
    if (mounted) {
      StatusNotificationScope.show(context, context.l10n.diffPatchCopied);
    }
  }

  SingleActivator get _copyActivator =>
      SingleActivator(LogicalKeyboardKey.keyC, meta: _mac, control: !_mac);

  Future<List<NativeMenuAction>?> _menu(Offset position) async {
    if (widget.itemCount == 0 || _viewportBox == null) return null;
    final point = _pointAt(position);
    if (point == null) return null;
    final row = widget.rowAt(point.index);
    // Right-clicking outside the selected lines selects the line under the
    // pointer first.
    if (!widget.selectedIds.contains(row.stableId)) {
      if (row.kind == DiffRowKind.hunk) {
        _tapHunk(point.index);
      } else if (isDiffLineRow(row)) {
        _focus.requestFocus();
        _selectionOld = point.oldSide;
        _selectLines(point.index, point.index);
      }
    }
    // The selection above reaches this view on the next build.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    final ids = _orderedSelection;
    if (ids.isEmpty && !_hasRange) return null;
    final hasChange = ids.any(
      (id) => widget.rowAt(_selectedIndex[id]!).kind != DiffRowKind.context,
    );
    final extra = ids.isEmpty
        ? const <NativeMenuAction>[]
        : widget.menuItems?.call(ids) ?? const <NativeMenuAction>[];
    return withDestructiveLast([
      ...extra,
      const NativeMenuAction.separator(),
      NativeMenuAction(
        value: () => unawaited(_copyText()),
        title: context.l10n.diffCopyLines,
        icon: 'copy',
        activator: _copyActivator,
      ),
      if (widget.onCopyPatch != null)
        NativeMenuAction(
          value: () => unawaited(_copyPatch()),
          title: context.l10n.diffCopyAsPatch,
          icon: 'file-diff',
          enabled: hasChange,
        ),
    ]);
  }

  /// Keyboard extension: moves the selection's moving end by a line or a
  /// character.
  void _extendByKey({int lines = 0, int characters = 0}) {
    final extent = _extent;
    final base = _base;
    if (extent == null || base == null) return;
    var index = extent.index;
    var offset = extent.offset;
    if (lines != 0) {
      index = _nextVisible(index, lines);
      offset = offset.clamp(0, _textLength(index));
    } else if (characters < 0) {
      if (offset > 0) {
        offset--;
      } else if (index > 0) {
        index = _nextVisible(index, -1);
        offset = _textLength(index);
      }
    } else if (characters > 0) {
      if (offset < _textLength(index)) {
        offset++;
      } else if (index < widget.itemCount - 1) {
        index = _nextVisible(index, 1);
        offset = 0;
      }
    }
    _select(base, _TextPoint(index, offset));
  }

  void _selectAll() {
    if (widget.itemCount == 0) return;
    _selectionOld = null;
    _selectLines(0, math.min(widget.itemCount, _maximumSelection) - 1);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    widget.syntax?.noteActivity();
    final key = event.logicalKey;
    if (_commandModifier && key == LogicalKeyboardKey.keyC) {
      if (!_canCopy) return KeyEventResult.ignored;
      unawaited(_copyText());
      return KeyEventResult.handled;
    }
    if (_commandModifier && key == LogicalKeyboardKey.keyA) {
      _selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape &&
        (_base != null || widget.selectedIds.isNotEmpty)) {
      _clearSelection();
      return KeyEventResult.handled;
    }
    if (_extent == null || !HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    switch (key) {
      case LogicalKeyboardKey.arrowDown:
        _extendByKey(lines: 1);
      case LogicalKeyboardKey.arrowUp:
        _extendByKey(lines: -1);
      case LogicalKeyboardKey.arrowLeft:
        _extendByKey(characters: -1);
      case LogicalKeyboardKey.arrowRight:
        _extendByKey(characters: 1);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// The part of row [index] the text selection covers; a null end runs to
  /// the end of the line.
  ({int start, int? end})? _rowSelection(int index) {
    if (!_hasRange) return null;
    final (start, end) = _ordered;
    if (index < start.index || index > end.index) return null;
    return (
      start: index == start.index ? start.offset : 0,
      end: index == end.index ? end.offset : null,
    );
  }

  /// The first selected row, which carries the selection actions.
  int? get _firstSelectedIndex {
    int? first;
    for (final id in widget.selectedIds) {
      final index = _selectedIndex[id];
      if (index != null && (first == null || index < first)) first = index;
    }
    return first;
  }

  bool _selectedAt(int visible) =>
      visible >= 0 &&
      visible < _visibleCount &&
      widget.selectedIds.contains(widget.rowAt(_physicalAt(visible)).stableId);

  /// The widest loaded line, measured with the code style. Cached until
  /// rows load or the text metrics change.
  double _measureTextWidth(BuildContext context) {
    // Merged as Text merges it, so the measure matches the painted line.
    final style = DefaultTextStyle.of(context).style.merge(context.text.code);
    final scaler = MediaQuery.textScalerOf(context);
    final rows = widget.loadedRows;
    final key = (
      rows.length,
      widget.itemCount,
      rows.isEmpty ? null : rows.first.stableId,
      widget.encoding,
      scaler,
      style,
    );
    if (key == _widthKey) return _textWidth;
    // Monospaced: the longest lines in bytes are the widest candidates.
    final widest = <DiffDisplayRow>[];
    for (final row in rows) {
      if (!isDiffLineRow(row)) continue;
      if (widest.length < 8) {
        widest.add(row);
      } else {
        var shortest = 0;
        for (var index = 1; index < widest.length; index++) {
          if (widest[index].text.length < widest[shortest].text.length) {
            shortest = index;
          }
        }
        if (row.text.length > widest[shortest].text.length) {
          widest[shortest] = row;
        }
      }
    }
    var width = 0.0;
    for (final row in widest) {
      final painter = TextPainter(
        text: TextSpan(
          text: _decode(row.text, widget.encoding, ''),
          style: style,
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      width = math.max(width, painter.width);
      painter.dispose();
    }
    _widthKey = key;
    return _textWidth = width.ceilToDouble();
  }

  /// Lets [child] own its pointer presses: the text selection ignores them.
  Widget _claimPointer(Widget child) =>
      Listener(onPointerDown: (_) => _pointerClaimed = true, child: child);

  @override
  Widget build(BuildContext context) {
    final firstSelected = _firstSelectedIndex;
    final selectionActions = firstSelected == null
        ? null
        : widget.selectionActions?.call(_orderedSelection);
    Widget body = Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _scrollChanged,
          child: ListView.builder(
            key: _viewport,
            padding: EdgeInsets.zero,
            controller: _scroll,
            itemCount: _visibleCount,
            itemExtentBuilder: widget.wrap
                ? null
                : (visible, _) {
                    final index = _physicalAt(visible);
                    return widget.hunkIndices.contains(index)
                        ? GitLamaLayout.hunkHeaderHeight
                        : widget.fallbackIndices.contains(index)
                        ? GitLamaLayout.diffFallbackHeight
                        : widget.rowExtent;
                  },
            itemBuilder: (context, visible) {
              final index = _physicalAt(visible);
              final row = widget.rowAt(index);
              final selected = widget.selectedIds.contains(row.stableId);
              final content = _DiffRow(
                row: row,
                index: index,
                syntax: widget.syntax?.rowSyntax(row.stableId),
                registry: _registry,
                layout: widget.layout,
                selected: selected,
                frameTop: selected && !_selectedAt(visible - 1),
                frameBottom: selected && !_selectedAt(visible + 1),
                actionsLink: selectionActions != null && index == firstSelected
                    ? _actionsLink
                    : null,
                textSelection: _rowSelection(index),
                selectionOld: _selectionOld,
                searchMatch:
                    widget.searchMatchIds.contains(row.stableId) ||
                    widget.searchMatchIndices.contains(index),
                currentSearch:
                    widget.currentSearchId == row.stableId ||
                    widget.currentSearchIndex == index,
                textStyler: widget.textStyler,
                wrap: widget.wrap,
                horizontal: widget.wrap ? null : _horizontal,
                showIndicators: widget.showIndicators,
                encoding: widget.encoding,
                onShowAsText: row.kind == DiffRowKind.binary
                    ? widget.onShowAsText
                    : null,
                actions: row.kind == DiffRowKind.hunk
                    ? widget.hunkActions?.call(row)
                    : null,
                fileCollapsed: _collapsedFiles.contains(index),
                onToggleFile:
                    widget.collapsibleFiles &&
                        row.kind == DiffRowKind.file &&
                        row.sectionEnd != null
                    ? () => _toggleFile(index)
                    : null,
                onShowMoreContext: row.kind == DiffRowKind.hunk
                    ? widget.onShowMoreContext
                    : null,
                onTap: row.kind == DiffRowKind.hunk
                    ? () => _tapHunk(index)
                    : row.kind == DiffRowKind.image &&
                          widget.onImageActivate != null
                    ? () => widget.onImageActivate!(row)
                    : null,
              );
              return RepaintBoundary(
                key: ValueKey('diff-row-${row.stableId}'),
                child: _RegisteredRow(
                  registry: _registry,
                  index: index,
                  child:
                      widget.revealContextIds.contains(row.stableId) ||
                          _expandingFiles.any((start) {
                            final end = widget.fileSections[start]?.sectionEnd;
                            return end != null && index > start && index < end;
                          })
                      ? MeridianReveal(
                          visible: true,
                          appear: true,
                          child: content,
                        )
                      : content,
                ),
              );
            },
          ),
        ),
        if (!widget.wrap && widget.hunkIndices.isNotEmpty)
          AnimatedBuilder(
            animation: _scroll,
            builder: (context, _) {
              if (!_scroll.hasClients) return const SizedBox.shrink();
              if (_scroll.positions.length != 1) {
                // A replacing view shares the caller's controller with the
                // view it replaces until that one unmounts after this frame.
                // The offset is ambiguous until then.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
                return const SizedBox.shrink();
              }
              final current = _physicalAt(_indexForOffset(_scroll.offset));
              final preceding = widget.hunkIndices.where(
                (index) =>
                    index <= current &&
                    !_isHidden(index) &&
                    _extentBefore(_visibleIndexForPhysical(index)) +
                            GitLamaLayout.hunkHeaderHeight <=
                        _scroll.offset,
              );
              if (preceding.isEmpty) return const SizedBox.shrink();
              final row = widget.rowAt(preceding.reduce(math.max));
              final colors = context.colors;
              return PositionedDirectional(
                top: 0,
                start: 0,
                end: 0,
                child: _claimPointer(
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.paneAlt,
                      border: Border.symmetric(
                        horizontal: BorderSide(color: colors.line),
                      ),
                    ),
                    child: _HunkCell(
                      row: row,
                      encoding: widget.encoding,
                      actions: widget.hunkActions?.call(row),
                      onShowMoreContext: widget.onShowMoreContext,
                    ),
                  ),
                ),
              );
            },
          ),
        if (selectionActions != null)
          PositionedDirectional(
            top: 0,
            start: 0,
            child: CompositedTransformFollower(
              link: _actionsLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(
                -MeridianSpace.space6,
                -MeridianSpace.space1,
              ),
              child: _claimPointer(
                KeyedSubtree(
                  key: const ValueKey('diff-selection-actions'),
                  child: selectionActions,
                ),
              ),
            ),
          ),
      ],
    );
    if (!widget.wrap) {
      final split = widget.layout == DiffViewLayout.sideBySide;
      body = MeridianSharedHorizontalScroll(
        controller: _horizontal,
        contentWidth: _measureTextWidth(context),
        columns: split ? 2 : 1,
        // Gutters, sign and end padding of one column (_LineCell).
        fixedWidth:
            (split ? 1 : 2) * GitLamaLayout.diffGutterWidth +
            GitLamaLayout.diffSignWidth +
            MeridianSpace.space6,
        child: body,
      );
    }
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: GitLamaContextMenuWidget(
        menuItems: _menu,
        child: Listener(
          onPointerDown: (event) {
            // A press may start a drag selection: colours wait for it.
            widget.syntax?.setInteracting(true);
            _pointerDown(event);
          },
          onPointerUp: (_) => widget.syntax?.setInteracting(false),
          onPointerCancel: (_) => widget.syntax?.setInteracting(false),
          child: GestureDetector(
            supportedDevices: const {PointerDeviceKind.mouse},
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: _dragStart,
            onPanUpdate: _dragUpdate,
            onPanEnd: (_) => _endDrag(),
            onPanCancel: _endDrag,
            child: body,
          ),
        ),
      ),
    );
  }

  double _physicalExtentBefore(int index) {
    if (widget.wrap) return index * widget.rowExtent;
    final hunks = widget.hunkIndices.where((row) => row < index).length;
    final fallbacks = widget.fallbackIndices.where((row) => row < index).length;
    return index * widget.rowExtent +
        hunks * (GitLamaLayout.hunkHeaderHeight - widget.rowExtent) +
        fallbacks * (GitLamaLayout.diffFallbackHeight - widget.rowExtent);
  }

  double _extentBefore(int visible) {
    final physical = _physicalAt(visible);
    var hiddenExtent = 0.0;
    for (final range in _collapsedRanges) {
      if (range.end > physical) break;
      hiddenExtent +=
          _physicalExtentBefore(range.end) -
          _physicalExtentBefore(range.start + 1);
    }
    return _physicalExtentBefore(physical) - hiddenExtent;
  }

  int _indexForOffset(double offset) {
    if (_visibleCount == 0) return 0;
    var low = 0;
    var high = _visibleCount;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_extentBefore(mid) <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low.clamp(0, _visibleCount - 1);
  }
}

/// The laid-out rows and line texts of one diff view, so pointer positions
/// map to text positions without assuming row extents.
class _DiffHitRegistry {
  final Map<int, _RenderRegisteredRow> rows = {};
  final Map<(int, bool), _RenderRegisteredCell> cells = {};

  /// The physical index of the row under [global].
  int? rowAt(Offset global) {
    for (final MapEntry(key: index, value: row) in rows.entries) {
      if (!row.attached || !row.hasSize) continue;
      final local = row.globalToLocal(global);
      if (local.dy >= 0 && local.dy < row.size.height) return index;
    }
    return null;
  }

  _RenderRegisteredCell? cell(int index, bool? oldSide) =>
      cells[(index, oldSide ?? false)] ?? cells[(index, !(oldSide ?? false))];

  /// The text column of row [index] under [global]: the preferred split
  /// side when the row has both, else the nearer column.
  _RenderRegisteredCell? cellAt(int index, Offset global, {bool? preferOld}) {
    final old = cells[(index, true)];
    final current = cells[(index, false)];
    if (old == null || current == null) return old ?? current;
    if (preferOld != null) return preferOld ? old : current;
    final left = old.localToGlobal(Offset.zero).dx;
    final right = current.localToGlobal(Offset.zero).dx;
    return (global.dx - right).abs() <= (global.dx - left).abs() ||
            global.dx >= right
        ? current
        : old;
  }
}

class _RegisteredRow extends SingleChildRenderObjectWidget {
  const _RegisteredRow({
    required this.registry,
    required this.index,
    super.child,
  });

  final _DiffHitRegistry registry;
  final int index;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRegisteredRow(registry, index);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRegisteredRow renderObject,
  ) {
    renderObject.index = index;
  }
}

class _RenderRegisteredRow extends RenderProxyBox {
  _RenderRegisteredRow(this._registry, this._index);

  final _DiffHitRegistry _registry;
  int _index;
  set index(int value) {
    if (value == _index) return;
    _unregister();
    _index = value;
    if (attached) _registry.rows[_index] = this;
  }

  void _unregister() {
    if (identical(_registry.rows[_index], this)) _registry.rows.remove(_index);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _registry.rows[_index] = this;
  }

  @override
  void detach() {
    _unregister();
    super.detach();
  }
}

class _RegisteredCell extends SingleChildRenderObjectWidget {
  const _RegisteredCell({
    required this.registry,
    required this.index,
    required this.oldSide,
    super.child,
  });

  final _DiffHitRegistry registry;
  final int index;
  final bool oldSide;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRegisteredCell(registry, (index, oldSide));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRegisteredCell renderObject,
  ) {
    renderObject.key = (index, oldSide);
  }
}

/// A line's text column; its child paints at its origin, so its
/// coordinates are the paragraph's.
class _RenderRegisteredCell extends RenderProxyBox {
  _RenderRegisteredCell(this._registry, this._key);

  final _DiffHitRegistry _registry;
  (int, bool) _key;
  set key((int, bool) value) {
    if (value == _key) return;
    _unregister();
    _key = value;
    if (attached) _registry.cells[_key] = this;
  }

  bool get oldSide => _key.$2;

  void _unregister() {
    if (identical(_registry.cells[_key], this)) _registry.cells.remove(_key);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _registry.cells[_key] = this;
  }

  @override
  void detach() {
    _unregister();
    super.detach();
  }

  RenderParagraph? get _paragraph {
    RenderObject? node = child;
    while (node is RenderProxyBox) {
      node = node.child;
    }
    return node is RenderParagraph && node.hasSize ? node : null;
  }

  int offsetAt(Offset local) =>
      _paragraph?.getPositionForOffset(local).offset ?? 0;

  TextRange? wordAt(int offset) =>
      _paragraph?.getWordBoundary(TextPosition(offset: offset));
}

/// Paints a diff line's intra-line [marks] and its [selection] under the
/// line's text. Offsets are UTF-16 offsets into the displayed text.
class DiffLineMarks extends SingleChildRenderObjectWidget {
  const DiffLineMarks({
    required this.marks,
    required this.markColor,
    required this.markRadius,
    required this.selection,
    required this.selectionColor,
    super.child,
    super.key,
  });

  final List<TextRange> marks;
  final Color markColor;
  final Radius markRadius;
  final TextRange? selection;
  final Color selectionColor;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderDiffLineMarks(
    marks,
    markColor,
    markRadius,
    selection,
    selectionColor,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderDiffLineMarks)
      ..marks = marks
      ..markColor = markColor
      ..markRadius = markRadius
      ..selection = selection
      ..selectionColor = selectionColor;
  }
}

class _RenderDiffLineMarks extends RenderProxyBox {
  _RenderDiffLineMarks(
    this._marks,
    this._markColor,
    this._markRadius,
    this._selection,
    this._selectionColor,
  );

  List<TextRange> _marks;
  set marks(List<TextRange> value) {
    if (listEquals(value, _marks)) return;
    _marks = value;
    markNeedsPaint();
  }

  Color _markColor;
  set markColor(Color value) {
    if (value == _markColor) return;
    _markColor = value;
    markNeedsPaint();
  }

  Radius _markRadius;
  set markRadius(Radius value) {
    if (value == _markRadius) return;
    _markRadius = value;
    markNeedsPaint();
  }

  TextRange? _selection;
  set selection(TextRange? value) {
    if (value == _selection) return;
    _selection = value;
    markNeedsPaint();
  }

  Color _selectionColor;
  set selectionColor(Color value) {
    if (value == _selectionColor) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child case final RenderParagraph paragraph) {
      final canvas = context.canvas;
      Iterable<Rect> boxes(TextRange range) => paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: range.start, extentOffset: range.end),
          )
          .map((box) => box.toRect().shift(offset));
      final markPaint = Paint()..color = _markColor;
      for (final mark in _marks) {
        for (final rect in boxes(mark)) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, _markRadius),
            markPaint,
          );
        }
      }
      if (_selection case final selection? when !selection.isCollapsed) {
        final selectionPaint = Paint()..color = _selectionColor;
        for (final rect in boxes(selection)) {
          canvas.drawRect(rect, selectionPaint);
        }
      }
    }
    super.paint(context, offset);
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.row,
    required this.index,
    required this.syntax,
    required this.registry,
    required this.layout,
    required this.selected,
    required this.frameTop,
    required this.frameBottom,
    required this.actionsLink,
    required this.textSelection,
    required this.selectionOld,
    required this.searchMatch,
    required this.currentSearch,
    required this.textStyler,
    required this.wrap,
    required this.horizontal,
    required this.showIndicators,
    required this.encoding,
    required this.onTap,
    required this.fileCollapsed,
    required this.onToggleFile,
    required this.onShowMoreContext,
    this.onShowAsText,
    this.actions,
  });

  final DiffDisplayRow row;
  final int index;
  final DiffRowSyntax? syntax;
  final _DiffHitRegistry registry;
  final DiffViewLayout layout;
  final Widget? actions;
  final ScrollController? horizontal;

  /// Whether the row is one of the selected lines; [frameTop] and
  /// [frameBottom] mark the edges of a run of them.
  final bool selected;
  final bool frameTop;
  final bool frameBottom;

  /// Anchors the selection actions to this row.
  final LayerLink? actionsLink;
  final ({int start, int? end})? textSelection;

  /// The split column that shows the text selection on context lines.
  final bool? selectionOld;
  final bool searchMatch;
  final bool currentSearch;
  final DiffTextStyler? textStyler;
  final bool wrap;
  final bool showIndicators;
  final DiffTextEncoding encoding;
  final VoidCallback? onTap;
  final bool fileCollapsed;
  final VoidCallback? onToggleFile;
  final VoidCallback? onShowMoreContext;
  final VoidCallback? onShowAsText;

  @override
  Widget build(BuildContext context) {
    final tokens = context.meridian;
    final isAdded = row.kind == DiffRowKind.addition;
    final isDeleted = row.kind == DiffRowKind.deletion;
    final fill = currentSearch
        ? tokens.colors.accentSoft
        : searchMatch
        ? tokens.colors.paneHover
        : isAdded
        ? tokens.colors.successBg
        : isDeleted
        ? context.git.deletedBg
        : row.kind == DiffRowKind.hunk || row.kind == DiffRowKind.noNewline
        ? tokens.colors.paneAlt
        : tokens.colors.pane;
    final background = selected
        ? Color.alphaBlend(
            tokens.colors.accent.withValues(
              alpha: GitLamaOpacity.diffSelectedLine,
            ),
            fill,
          )
        : fill;
    final split = layout == DiffViewLayout.sideBySide;
    ({int start, int? end})? selectionFor(bool oldSide) =>
        split && row.kind == DiffRowKind.context && selectionOld != oldSide
        ? null
        : textSelection;
    _LineCell lineCell({required bool oldSide, required bool unified}) =>
        _LineCell(
          row: row,
          index: index,
          syntax: syntax?.forCell(oldSide: oldSide, split: !unified),
          background: background,
          registry: registry,
          selected: selected,
          textSelection: selectionFor(oldSide),
          oldSide: oldSide,
          textStyler: textStyler,
          unified: unified,
          wrap: wrap,
          horizontal: horizontal,
          showIndicators: showIndicators,
          encoding: encoding,
        );
    final fallback = isDiffFallbackRow(row, encoding);
    final child = fallback
        ? _FallbackPanel(
            row: row,
            encoding: encoding,
            onActivate: onTap,
            onShowAsText: onShowAsText,
          )
        : row.kind == DiffRowKind.noNewline
        ? _NoNewlineCell()
        : row.kind == DiffRowKind.hunk
        ? _HunkCell(
            row: row,
            encoding: encoding,
            actions: actions,
            onShowMoreContext: onShowMoreContext,
          )
        : row.kind == DiffRowKind.file && onToggleFile != null
        ? _FileCell(
            row: row,
            encoding: encoding,
            collapsed: fileCollapsed,
            onToggle: onToggleFile!,
          )
        : split && (isAdded || isDeleted || row.kind == DiffRowKind.context)
        ? Row(
            children: [
              Expanded(
                child: isAdded
                    ? const SizedBox()
                    : lineCell(oldSide: true, unified: false),
              ),
              MeridianHairline(axis: Axis.vertical, color: tokens.colors.line),
              Expanded(
                child: isDeleted
                    ? const SizedBox()
                    : lineCell(oldSide: false, unified: false),
              ),
            ],
          )
        : lineCell(oldSide: false, unified: true);
    final frame = BorderSide(
      color: tokens.colors.accent,
      width: MeridianLayout.hairline,
    );
    Widget result = Semantics(
      selected: selected,
      button: onTap != null,
      label:
          '${row.kind.name}, ${row.oldLine ?? ''}, ${row.newLine ?? ''}, ${_decode(row.text, encoding, context.l10n.diffEncodingInvalid)}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: row.kind == DiffRowKind.hunk
              ? Border.symmetric(
                  horizontal: BorderSide(color: tokens.colors.line),
                )
              : null,
        ),
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: MeridianInteraction(
                    onTap: onTap,
                    child: MeridianSwap(
                      swapKey: layout,
                      style: MeridianSwapStyle.fade,
                      duration: MeridianDurations.select,
                      child: child,
                    ),
                  ),
                ),
                if (row.kind != DiffRowKind.hunk && actions != null) actions!,
              ],
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: MeridianAnimatedValue(
                  value: currentSearch ? 1 : 0,
                  spring: MeridianSprings.pop,
                  builder: (context, progress, child) => Opacity(
                    opacity: currentSearch ? 1 : 0,
                    child: Transform.scale(
                      scale: 1.08 - 0.08 * progress,
                      child: child,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: tokens.colors.accent),
                    ),
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: ValueKey('diff-selection-frame-${row.stableId}'),
                    decoration: BoxDecoration(
                      border: Border(
                        left: frame,
                        right: frame,
                        top: frameTop ? frame : BorderSide.none,
                        bottom: frameBottom ? frame : BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (actionsLink case final link?) {
      result = CompositedTransformTarget(link: link, child: result);
    }
    return result;
  }
}

class _FileCell extends StatelessWidget {
  const _FileCell({
    required this.row,
    required this.encoding,
    required this.collapsed,
    required this.onToggle,
  });

  final DiffDisplayRow row;
  final DiffTextEncoding encoding;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: collapsed
        ? context.l10n.diffExpandFile
        : context.l10n.diffCollapseFile,
    child: MeridianInteraction(
      key: ValueKey('diff-file-toggle-${row.stableId}'),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: MeridianSpace.space4,
          end: MeridianSpace.space3,
        ),
        child: Row(
          children: [
            MeridianAnimatedValue(
              value: collapsed ? 1 : 0,
              duration: MeridianDurations.quick,
              builder: (context, value, child) =>
                  Transform.rotate(angle: -math.pi / 2 * value, child: child),
              child: const MeridianIcon(
                'chevron-down',
                size: MeridianIconSize.small,
              ),
            ),
            const SizedBox(width: MeridianSpace.space3),
            Expanded(
              child: Text(
                _decode(row.text, encoding, context.l10n.diffEncodingInvalid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.codeSm,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HunkCell extends StatelessWidget {
  const _HunkCell({
    required this.row,
    required this.encoding,
    this.actions,
    this.onShowMoreContext,
  });

  final DiffDisplayRow row;
  final DiffTextEncoding encoding;
  final Widget? actions;
  final VoidCallback? onShowMoreContext;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = _decode(row.text, encoding, context.l10n.diffEncodingInvalid);
    final match = RegExp(r'^(@@[^@]*@@)(.*)$').firstMatch(text);
    return SizedBox(
      height: GitLamaLayout.hunkHeaderHeight,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: MeridianSpace.space5,
          end: MeridianSpace.space3,
        ),
        child: Row(
          children: [
            Text(
              match?.group(1) ?? text,
              style: context.text.codeSm.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(width: MeridianSpace.space4),
            Expanded(
              child: Text(
                match?.group(2)?.trim() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.codeSm.copyWith(color: colors.ink),
              ),
            ),
            if (onShowMoreContext != null)
              MeridianIconButton(
                key: ValueKey('diff-more-${row.stableId}'),
                label: context.l10n.diffShowMoreLines,
                icon: 'chevrons-down-up',
                size: MeridianControlSize.small,
                onPressed: onShowMoreContext,
              ),
            ?actions,
          ],
        ),
      ),
    );
  }
}

bool _isFallback(DiffRowKind kind) => switch (kind) {
  DiffRowKind.binary ||
  DiffRowKind.image ||
  DiffRowKind.submodule ||
  DiffRowKind.modeOnly ||
  DiffRowKind.tooLarge => true,
  _ => false,
};

/// Whether a projected row needs the centred fallback panel extent.
bool isDiffFallbackRow(DiffDisplayRow row, DiffTextEncoding encoding) {
  if (_isFallback(row.kind)) return true;
  if (encoding != DiffTextEncoding.utf8) return false;
  try {
    utf8.decode(row.text, allowMalformed: false);
    return false;
  } on FormatException {
    return true;
  }
}

class _NoNewlineCell extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: MeridianSpace.space5),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        context.l10n.diffNoNewline,
        style: context.text.caption.copyWith(color: context.colors.inkMuted),
      ),
    ),
  );
}

class _FallbackPanel extends StatelessWidget {
  const _FallbackPanel({
    required this.row,
    required this.encoding,
    required this.onActivate,
    this.onShowAsText,
  });

  final DiffDisplayRow row;
  final DiffTextEncoding encoding;
  final VoidCallback? onActivate;
  final VoidCallback? onShowAsText;

  @override
  Widget build(BuildContext context) {
    final decodeFailed = !_isFallback(row.kind);
    final metadataOnly =
        row.kind == DiffRowKind.tooLarge &&
        utf8.decode(row.text, allowMalformed: true).endsWith(':0:0');
    final sizeText = utf8
        .decode(row.text, allowMalformed: true)
        .split(':')
        .first;
    final byteCount = int.tryParse(sizeText);
    final path = utf8.decode(
      row.newPath ?? row.oldPath ?? const [],
      allowMalformed: true,
    );
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    final extension = dot > 0 && dot < name.length - 1
        ? name.substring(dot + 1).toUpperCase()
        : context.l10n.diffFileTypeUnknown;
    final message = decodeFailed
        ? context.l10n.diffEncodingInvalid
        : switch (row.kind) {
            DiffRowKind.binary => context.l10n.diffBinaryFallback,
            DiffRowKind.image => context.l10n.diffImageFallback,
            DiffRowKind.submodule => context.l10n.diffSubmoduleFallback,
            DiffRowKind.modeOnly => context.l10n.diffModeOnlyFallback(
              _decode(row.text, encoding, context.l10n.diffEncodingInvalid),
            ),
            _ =>
              metadataOnly
                  ? context.l10n.diffLargeFileInformation
                  : context.l10n.diffTooLargeFallback,
          };
    final icon = switch (row.kind) {
      DiffRowKind.image => 'image',
      DiffRowKind.submodule => 'box',
      DiffRowKind.tooLarge => 'triangle-alert',
      _ => 'file-diff',
    };
    final showsSize =
        byteCount != null &&
        (row.kind == DiffRowKind.tooLarge || row.kind == DiffRowKind.binary);
    return MeridianEmptyState(
      compact: true,
      icon: icon,
      title: message,
      message: showsSize
          ? '${context.l10n.diffFileSize(formatByteSize(context.l10n, byteCount))}\n'
                '${context.l10n.diffFileType(extension)}'
          : null,
      action: row.kind == DiffRowKind.image && onActivate != null
          ? MeridianButton(
              label: context.l10n.diffImageComparison,
              variant: MeridianButtonVariant.secondary,
              onPressed: onActivate,
            )
          : row.kind == DiffRowKind.binary && onShowAsText != null
          ? MeridianButton(
              key: const ValueKey('diff-show-as-text'),
              label: context.l10n.showBinaryAsText,
              variant: MeridianButtonVariant.secondary,
              onPressed: onShowAsText,
            )
          : null,
    );
  }
}

class _LineCell extends StatelessWidget {
  const _LineCell({
    required this.row,
    required this.index,
    required this.syntax,
    required this.background,
    required this.registry,
    required this.selected,
    required this.textSelection,
    required this.oldSide,
    required this.textStyler,
    required this.unified,
    required this.wrap,
    required this.horizontal,
    required this.showIndicators,
    required this.encoding,
  });

  final DiffDisplayRow row;
  final int index;

  /// Category runs over this cell's text, or null for plain text.
  final List<DiffSyntaxRun>? syntax;

  /// The opaque fill behind the row, for the colours' contrast check.
  final Color background;
  final _DiffHitRegistry registry;
  final bool selected;
  final ({int start, int? end})? textSelection;
  final bool oldSide;
  final DiffTextStyler? textStyler;
  final bool unified;
  final bool wrap;
  final ScrollController? horizontal;
  final bool showIndicators;
  final DiffTextEncoding encoding;

  @override
  Widget build(BuildContext context) {
    final line = oldSide ? row.oldLine : row.newLine;
    final prefix = switch (row.kind) {
      DiffRowKind.addition => '+',
      DiffRowKind.deletion => '−',
      _ => ' ',
    };
    final colors = context.colors;
    final styled = textStyler?.call(context, row);
    final (content, length, marks) = styled != null
        ? (
            styled,
            styled.toPlainText().length,
            _intraLineMarks(styled.toPlainText()),
          )
        : _styledContent(context);
    TextRange? selection;
    if (textSelection case (:final start, :final end)) {
      final from = start.clamp(0, length);
      selection = TextRange(
        start: from,
        end: (end ?? length).clamp(from, length),
      );
    }
    final text = DiffLineMarks(
      marks: marks,
      markColor: row.kind == DiffRowKind.deletion
          ? context.git.deletedStrong
          : context.git.addedStrong,
      markRadius: Radius.circular(context.meridian.radius.xs),
      selection: selection,
      selectionColor: colors.accent.withValues(
        alpha: GitLamaOpacity.diffSelectedText,
      ),
      child: Text.rich(
        key: ValueKey(
          'diff-content-${row.stableId}-${oldSide ? 'old' : 'new'}',
        ),
        content,
        maxLines: wrap ? null : 1,
        softWrap: wrap,
        overflow: TextOverflow.clip,
        style: context.text.code.copyWith(color: colors.ink),
      ),
    );
    final gutterStyle = context.text.codeSm.copyWith(color: colors.inkMuted);
    Widget gutter(int? number) => SizedBox(
      width: GitLamaLayout.diffGutterWidth,
      height: GitLamaLayout.diffLineHeight,
      child: ColoredBox(
        color: selected ? colors.accentSoft : Colors.transparent,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: MeridianSpace.space4),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(number?.toString() ?? '', style: gutterStyle),
          ),
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (unified) ...[
          gutter(row.oldLine),
          gutter(row.newLine),
        ] else
          gutter(line),
        SizedBox(
          width: GitLamaLayout.diffSignWidth,
          child: Text(
            showIndicators ? prefix : '',
            textAlign: TextAlign.center,
            style: context.text.diffSign.copyWith(
              color: row.kind == DiffRowKind.addition
                  ? colors.success
                  : row.kind == DiffRowKind.deletion
                  ? context.git.deleted
                  : colors.inkMuted,
            ),
          ),
        ),
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                end: MeridianSpace.space6,
              ),
              child: ClipRect(
                child: _RegisteredCell(
                  registry: registry,
                  index: index,
                  oldSide: oldSide,
                  child: switch (horizontal) {
                    final horizontal? => MeridianHorizontalShift(
                      controller: horizontal,
                      child: text,
                    ),
                    null => text,
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The line's spans, the length of its displayed text and its intra-line
  /// spans as UTF-16 ranges of that text. Intra-line marks never depend on
  /// syntax colours; colours only change the glyphs' foreground.
  (TextSpan, int, List<TextRange>) _styledContent(BuildContext context) {
    final text = _displayText(context);
    final marks = _intraLineMarks(text);
    final runs = _syntaxRuns(text);
    if (runs == null || runs.isEmpty) {
      return (TextSpan(text: text), text.length, marks);
    }
    final colors = context.colors;
    final markColor = row.kind == DiffRowKind.deletion
        ? context.git.deletedStrong
        : context.git.addedStrong;
    final palette = syntaxPalette(context.meridian.syntax, colors.ink, [
      background,
      if (marks.isNotEmpty) Color.alphaBlend(markColor, background),
      if (textSelection != null)
        Color.alphaBlend(
          colors.accent.withValues(alpha: GitLamaOpacity.diffSelectedText),
          background,
        ),
    ]);
    return (palette.span(text, runs), text.length, marks);
  }

  /// This cell's syntax runs when they describe exactly [text]: decoded
  /// UTF-8 of a complete line. Latin-1, truncated, fallback and header rows
  /// stay plain.
  List<MeridianSyntaxRun>? _syntaxRuns(String text) {
    final runs = syntax;
    if (runs == null ||
        runs.isEmpty ||
        encoding != DiffTextEncoding.utf8 ||
        row.textTruncated ||
        !isDiffLineRow(row)) {
      return null;
    }
    return meridianSyntaxRuns(runs);
  }

  /// The intra-line spans as UTF-16 ranges of [text].
  List<TextRange> _intraLineMarks(String text) {
    if (row.intraLine.isEmpty) return const [];
    // Byte offsets into the line become offsets into the decoded text.
    int offset(int byte) => encoding == DiffTextEncoding.latin1
        ? byte
        : utf8.decode(row.text.sublist(0, byte), allowMalformed: true).length;
    final marks = <TextRange>[];
    var cursor = 0;
    for (final span in row.intraLine.take(6)) {
      final start = span.start.clamp(cursor, row.text.length);
      final end = span.end.clamp(start, row.text.length);
      final range = TextRange(
        start: offset(start).clamp(0, text.length),
        end: offset(end).clamp(0, text.length),
      );
      if (!range.isCollapsed) marks.add(range);
      cursor = end;
    }
    return marks;
  }

  String _displayText(BuildContext context) => switch (row.kind) {
    DiffRowKind.noNewline => context.l10n.diffNoNewline,
    DiffRowKind.binary => context.l10n.diffBinaryFallback,
    DiffRowKind.image => context.l10n.diffImageFallback,
    DiffRowKind.submodule => context.l10n.diffSubmoduleFallback,
    DiffRowKind.modeOnly => context.l10n.diffModeOnlyFallback(
      _decode(row.text, encoding, context.l10n.diffEncodingInvalid),
    ),
    DiffRowKind.tooLarge => context.l10n.diffTooLargeFallback,
    _ => _decode(row.text, encoding, context.l10n.diffEncodingInvalid),
  };
}

String _decode(List<int> bytes, DiffTextEncoding encoding, String invalid) {
  if (encoding == DiffTextEncoding.latin1) return latin1.decode(bytes);
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    return invalid;
  }
}
