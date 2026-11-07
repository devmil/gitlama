import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../models/conflict.dart';
import '../models/diff_syntax.dart';
import '../services/conflict/conflict_merge_draft.dart';
import '../services/source_syntax_service.dart';
import 'syntax_colours.dart';

/// The syntax colours of the shown conflicted file: its current and
/// incoming sides as the comparison shows them, its ancestor and its
/// result. Notifies whenever any of them gains colours.
final class ConflictSyntax extends ChangeNotifier {
  ConflictSyntax(
    this._service, {
    required this.file,
    required this.draft,
    required String result,
  }) : result = _service.view(path: file.path, text: result) {
    final rows = draft?.rows ?? const <MergeComparisonRow>[];
    final current = <String>[];
    final incoming = <String>[];
    _currentLines = List.filled(rows.length, null);
    _incomingLines = List.filled(rows.length, null);
    for (final (index, row) in rows.indexed) {
      if (row.currentLine != null) {
        current.add(_cellText(row.current));
        _currentLines[index] = current.length;
      }
      if (row.incomingLine != null) {
        incoming.add(_cellText(row.incoming));
        _incomingLines[index] = incoming.length;
      }
    }
    if (draft != null) {
      this.current = _service.view(path: file.path, text: current.join('\n'));
      this.incoming = _service.view(path: file.path, text: incoming.join('\n'));
    }
    for (final view in _views) {
      view.addListener(notifyListeners);
    }
  }

  final SourceSyntaxService _service;
  final ConflictFile file;
  final ConflictMergeDraft? draft;

  /// The comparison's sides, one source line per row that shows the side.
  SourceSyntaxView? current;
  SourceSyntaxView? incoming;
  late final List<int?> _currentLines;
  late final List<int?> _incomingLines;

  /// The merge result as the editor holds it.
  final SourceSyntaxView result;
  SourceSyntaxView? _ancestor;

  Iterable<SourceSyntaxView> get _views => [
    ?current,
    ?incoming,
    result,
    ?_ancestor,
  ];

  /// Whether these colours belong to [file] as [draft] shows it.
  bool matches(ConflictFile file, ConflictMergeDraft? draft) =>
      identical(draft, this.draft) &&
      file.fingerprint == this.file.fingerprint &&
      listEquals(file.path, this.file.path);

  /// The ancestor's colours once it was shown.
  SourceSyntaxView? get ancestor => _ancestor;

  /// Starts colouring the ancestor, which is now shown.
  void showAncestor() {
    final content = file.ancestor.content;
    if (content == null || _ancestor != null) return;
    _ancestor = _service.view(
      path: file.path,
      text: utf8.decode(content, allowMalformed: true),
    )..addListener(notifyListeners);
    _ancestor!.noteActivity();
  }

  /// Starts colouring the shown texts once they are on screen.
  void start() {
    for (final view in _views) {
      view.noteActivity();
    }
  }

  /// The colours of comparison row [row] on the [current] or incoming side.
  List<DiffSyntaxRun>? comparisonRuns(int row, {required bool current}) {
    final lines = current ? _currentLines : _incomingLines;
    final line = row < lines.length ? lines[row] : null;
    if (line == null) return null;
    return (current ? this.current : incoming)?.runsOf(line);
  }

  /// Tells the sides which comparison rows are on screen.
  void showComparisonRows(int first, int last) {
    for (final (view, lines) in [
      (current, _currentLines),
      (incoming, _incomingLines),
    ]) {
      if (view == null || lines.isEmpty) continue;
      final (start, end) = _lineRange(
        lines,
        first.clamp(0, lines.length - 1),
        last.clamp(0, lines.length - 1),
      );
      if (start != null && end != null) view.setVisible(start, end);
    }
  }

  /// The first and last source line shown by rows [first] to [last].
  static (int?, int?) _lineRange(List<int?> lines, int first, int last) {
    int? start;
    int? end;
    for (var row = first; row <= last; row += 1) {
      final line = lines[row];
      if (line == null) continue;
      start ??= line;
      end = line;
    }
    return (start, end);
  }

  /// Scrolling or dragging in the comparison: pauses its sides.
  void setComparisonInteracting(bool interacting) {
    current?.setInteracting(interacting);
    incoming?.setInteracting(interacting);
  }

  @override
  void dispose() {
    for (final view in _views) {
      view.dispose();
    }
    super.dispose();
  }
}

String _cellText(String line) => line.replaceAll('\n', '');

/// [text] painted with [runs] when they describe it exactly, on every one of
/// [backgrounds]; plain otherwise.
TextSpan conflictSyntaxSpan(
  MeridianTheme theme,
  String text,
  List<DiffSyntaxRun>? runs,
  List<Color> backgrounds,
) {
  if (runs == null || runs.isEmpty) return TextSpan(text: text);
  final palette = syntaxPalette(theme.syntax, theme.colors.ink, backgrounds);
  return palette.span(text, meridianSyntaxRuns(runs));
}

/// [text] with [view]'s colours on each of its lines, as one span.
TextSpan conflictSyntaxText(
  MeridianTheme theme,
  String text,
  SourceSyntaxView? view,
  List<Color> backgrounds,
) {
  if (view == null || view.text != text || !view.hasColours) {
    return TextSpan(text: text);
  }
  final palette = syntaxPalette(theme.syntax, theme.colors.ink, backgrounds);
  final children = <InlineSpan>[];
  var cursor = 0;
  for (final line in view.colouredLines) {
    if (line > view.lineCount) break;
    final start = view.lineStart(line);
    final runs = meridianSyntaxRuns(view.runsOf(line)!);
    final end = line < view.lineCount
        ? view.lineStart(line + 1) - 1
        : text.length;
    final content = text.substring(start, end);
    if (runs.isEmpty || !meridianSyntaxRunsValid(content, runs)) continue;
    if (start > cursor) {
      children.add(TextSpan(text: text.substring(cursor, start)));
    }
    children.add(palette.span(content, runs));
    cursor = end;
  }
  if (cursor < text.length) {
    children.add(TextSpan(text: text.substring(cursor)));
  }
  return TextSpan(children: children);
}
