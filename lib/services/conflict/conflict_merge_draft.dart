import 'dart:convert';

import '../../models/conflict.dart';

final _markerLine = RegExp(
  r'^(?:(?:<<<<<<<|\|\|\|\|\|\|\||>>>>>>>)(?: .*)?|=======)\r?$',
  multiLine: true,
);

/// Whether [text] still holds a conflict marker as Git writes one: seven
/// `<`, `|` or `>` followed by a space or the line end, or exactly seven `=`.
/// Longer runs, such as a Markdown heading underline, are content. The native
/// resolver stages a saved result under the same rule.
bool hasConflictMarkers(String text) => _markerLine.hasMatch(text);

/// A reviewable merge result. Choices and edits stay in memory until Resolve.
final class ConflictMergeDraft {
  ConflictMergeDraft._(this.text, this.blocks, this.rows);

  factory ConflictMergeDraft.fromFile(ConflictFile file) {
    final text = utf8.decode(file.result ?? const <int>[]);
    final blocks = <MergeDraftBlock>[];
    final rows = <MergeComparisonRow>[];
    final lines = _lines(text);
    var cursor = 0;
    var offset = 0;
    var currentLine = 1;
    var incomingLine = 1;
    while (cursor < lines.length) {
      final line = lines[cursor];
      if (!line.startsWith('<<<<<<<')) {
        rows.add(MergeComparisonRow(line, line, currentLine++, incomingLine++));
        offset += line.length;
        cursor++;
        continue;
      }
      final start = offset;
      final first = cursor + 1;
      var separator = first;
      while (separator < lines.length &&
          !lines[separator].startsWith('=======')) {
        separator++;
      }
      var end = separator + 1;
      while (end < lines.length && !lines[end].startsWith('>>>>>>>')) {
        end++;
      }
      if (separator == lines.length || end == lines.length) {
        rows.add(MergeComparisonRow(line, line, currentLine++, incomingLine++));
        offset += line.length;
        cursor++;
        continue;
      }
      // Diff3 adds ancestor lines between ||||||| and =======.
      var currentEnd = separator;
      for (var i = first; i < separator; i++) {
        if (lines[i].startsWith('|||||||')) {
          currentEnd = i;
          break;
        }
      }
      final current = lines.sublist(first, currentEnd).join();
      final incoming = lines.sublist(separator + 1, end).join();
      final original = lines.sublist(cursor, end + 1).join();
      final block = MergeDraftBlock(
        index: blocks.length,
        start: start,
        end: start + original.length,
        current: current,
        incoming: incoming,
        original: original,
      );
      blocks.add(block);
      final leftLines = _lines(current);
      final rightLines = _lines(incoming);
      final rowCount = [
        1,
        leftLines.length,
        rightLines.length,
      ].reduce((a, b) => a > b ? a : b);
      for (var i = 0; i < rowCount; i++) {
        rows.add(
          MergeComparisonRow(
            i < leftLines.length ? leftLines[i] : '',
            i < rightLines.length ? rightLines[i] : '',
            i < leftLines.length ? currentLine++ : null,
            i < rightLines.length ? incomingLine++ : null,
            block.index,
          ),
        );
      }
      offset += original.length;
      cursor = end + 1;
    }
    return ConflictMergeDraft._(text, blocks, _stageRows(file, blocks) ?? rows);
  }

  String text;
  final List<MergeDraftBlock> blocks;
  final List<MergeComparisonRow> rows;

  /// Where each block sits in [rows], by block index. A block without rows
  /// has a count of zero.
  late final List<({int first, int count})> blockRows = _blockRows();

  /// Rows that open a block. A sparse set, so a list can size a row without
  /// reading it.
  late final Set<int> blockFirstRows = {
    for (final rows in blockRows)
      if (rows.count > 0) rows.first,
  };

  List<({int first, int count})> _blockRows() {
    final first = List.filled(blocks.length, 0);
    final count = List.filled(blocks.length, 0);
    for (var index = 0; index < rows.length; index++) {
      final block = rows[index].blockIndex;
      if (block == null || block >= blocks.length) continue;
      if (count[block] == 0) first[block] = index;
      count[block]++;
    }
    return [
      for (var block = 0; block < blocks.length; block++)
        (first: first[block], count: count[block]),
    ];
  }

  int get resolvedCount => blocks.where((block) => block.choice != null).length;
  int get unresolvedCount => blocks.length - resolvedCount;

  String take(int index, ConflictRegionChoice choice) {
    final block = blocks[index];
    final next = switch ((block.choice, choice)) {
      (ConflictRegionChoice.current, ConflictRegionChoice.current) ||
      (ConflictRegionChoice.incoming, ConflictRegionChoice.incoming) ||
      (ConflictRegionChoice.both, ConflictRegionChoice.both) => block.choice,
      (ConflictRegionChoice.current, ConflictRegionChoice.incoming) ||
      (
        ConflictRegionChoice.incoming,
        ConflictRegionChoice.current,
      ) => ConflictRegionChoice.both,
      (ConflictRegionChoice.both, ConflictRegionChoice.current) ||
      (
        ConflictRegionChoice.both,
        ConflictRegionChoice.incoming,
      ) => ConflictRegionChoice.both,
      _ => choice,
    };
    return _set(index, next);
  }

  String remove(int index, ConflictRegionChoice choice) {
    final current = blocks[index].choice;
    final next = switch ((current, choice)) {
      (ConflictRegionChoice.both, ConflictRegionChoice.current) =>
        ConflictRegionChoice.incoming,
      (ConflictRegionChoice.both, ConflictRegionChoice.incoming) =>
        ConflictRegionChoice.current,
      (ConflictRegionChoice.current, ConflictRegionChoice.current) ||
      (ConflictRegionChoice.incoming, ConflictRegionChoice.incoming) ||
      (ConflictRegionChoice.both, ConflictRegionChoice.both) => null,
      _ => current,
    };
    return _set(index, next);
  }

  String _set(int index, ConflictRegionChoice? next) {
    final block = blocks[index];
    final replacement = switch (next) {
      ConflictRegionChoice.current => block.current,
      ConflictRegionChoice.incoming => block.incoming,
      ConflictRegionChoice.both => block.current + block.incoming,
      null => block.original,
    };
    _replace(block.start, block.end, replacement, index);
    block.choice = next;
    return text;
  }

  void edit(String updated) {
    if (updated == text) return;
    var prefix = 0;
    while (prefix < text.length &&
        prefix < updated.length &&
        text.codeUnitAt(prefix) == updated.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < text.length - prefix &&
        suffix < updated.length - prefix &&
        text.codeUnitAt(text.length - suffix - 1) ==
            updated.codeUnitAt(updated.length - suffix - 1)) {
      suffix++;
    }
    final oldEnd = text.length - suffix;
    final newEnd = updated.length - suffix;
    _shiftRanges(prefix, oldEnd, newEnd - prefix, null);
    text = updated;
  }

  void _replace(int start, int end, String replacement, int selected) {
    text = text.replaceRange(start, end, replacement);
    _shiftRanges(start, end, replacement.length, selected);
  }

  void _shiftRanges(int start, int end, int replacementLength, int? selected) {
    final delta = replacementLength - (end - start);
    for (final block in blocks) {
      if (block.index == selected) {
        block.start = start;
        block.end = start + replacementLength;
      } else if (block.start >= end) {
        block.start += delta;
        block.end += delta;
      } else if (block.end > start) {
        // Keep a manually edited block attached to its updated result span.
        block.start = block.start < start ? block.start : start;
        block.end = (block.end + delta).clamp(block.start, text.length + delta);
      }
    }
  }
}

final class MergeDraftBlock {
  MergeDraftBlock({
    required this.index,
    required this.start,
    required this.end,
    required this.current,
    required this.incoming,
    required this.original,
  });

  final int index;
  int start;
  int end;
  final String current;
  final String incoming;
  final String original;
  ConflictRegionChoice? choice;
}

final class MergeComparisonRow {
  const MergeComparisonRow(
    this.current,
    this.incoming,
    this.currentLine,
    this.incomingLine, [
    this.blockIndex,
    this.different = false,
  ]);

  final String current;
  final String incoming;
  final int? currentLine;
  final int? incomingLine;
  final int? blockIndex;
  final bool different;
}

List<MergeComparisonRow>? _stageRows(
  ConflictFile file,
  List<MergeDraftBlock> blocks,
) {
  if ((file.current.present && file.current.content == null) ||
      (file.incoming.present && file.incoming.content == null) ||
      file.regions.length != blocks.length) {
    return null;
  }
  try {
    final current = _lines(utf8.decode(file.current.content ?? const []));
    final incoming = _lines(utf8.decode(file.incoming.content ?? const []));
    final rows = <MergeComparisonRow>[];
    var left = 0;
    var right = 0;
    for (var region = 0; region < blocks.length; region++) {
      final leftConflict = _lines(utf8.decode(file.regions[region].current));
      final rightConflict = _lines(utf8.decode(file.regions[region].incoming));
      // An empty side has no unique anchor. Keep the merge-result projection
      // in that case rather than attaching actions to the wrong file lines.
      if (leftConflict.isEmpty || rightConflict.isEmpty) return null;
      final leftStart = _findLines(current, leftConflict, left);
      final rightStart = _findLines(incoming, rightConflict, right);
      if (leftStart < 0 || rightStart < 0) return null;
      _alignLines(rows, current, incoming, left, leftStart, right, rightStart);
      final count = leftConflict.length > rightConflict.length
          ? leftConflict.length
          : rightConflict.length;
      for (var i = 0; i < count; i++) {
        rows.add(
          MergeComparisonRow(
            i < leftConflict.length ? leftConflict[i] : '',
            i < rightConflict.length ? rightConflict[i] : '',
            i < leftConflict.length ? leftStart + i + 1 : null,
            i < rightConflict.length ? rightStart + i + 1 : null,
            region,
          ),
        );
      }
      left = leftStart + leftConflict.length;
      right = rightStart + rightConflict.length;
    }
    _alignLines(
      rows,
      current,
      incoming,
      left,
      current.length,
      right,
      incoming.length,
    );
    return rows;
  } on FormatException {
    return null;
  }
}

int _findLines(List<String> haystack, List<String> needle, int start) {
  for (var i = start; i + needle.length <= haystack.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return i;
  }
  return -1;
}

void _alignLines(
  List<MergeComparisonRow> rows,
  List<String> current,
  List<String> incoming,
  int left,
  int leftEnd,
  int right,
  int rightEnd,
) {
  while (left < leftEnd || right < rightEnd) {
    if (left >= leftEnd) {
      rows.add(
        MergeComparisonRow('', incoming[right], null, right + 1, null, true),
      );
      right++;
      continue;
    }
    if (right >= rightEnd) {
      rows.add(
        MergeComparisonRow(current[left], '', left + 1, null, null, true),
      );
      left++;
      continue;
    }
    if (current[left] == incoming[right]) {
      rows.add(
        MergeComparisonRow(current[left], incoming[right], left + 1, right + 1),
      );
      left++;
      right++;
      continue;
    }
    final leftMatch = _lookAhead(current, left + 1, leftEnd, incoming[right]);
    final rightMatch = _lookAhead(incoming, right + 1, rightEnd, current[left]);
    if (leftMatch >= 0 &&
        (rightMatch < 0 || leftMatch - left <= rightMatch - right)) {
      rows.add(
        MergeComparisonRow(current[left], '', left + 1, null, null, true),
      );
      left++;
    } else if (rightMatch >= 0) {
      rows.add(
        MergeComparisonRow('', incoming[right], null, right + 1, null, true),
      );
      right++;
    } else {
      rows.add(
        MergeComparisonRow(
          current[left],
          incoming[right],
          left + 1,
          right + 1,
          null,
          true,
        ),
      );
      left++;
      right++;
    }
  }
}

int _lookAhead(List<String> lines, int start, int end, String value) {
  final limit = start + 24 < end ? start + 24 : end;
  for (var i = start; i < limit; i++) {
    if (lines[i] == value) return i;
  }
  return -1;
}

List<String> _lines(String value) {
  if (value.isEmpty) return const [];
  final result = <String>[];
  var start = 0;
  for (var i = 0; i < value.length; i++) {
    if (value.codeUnitAt(i) == 10) {
      result.add(value.substring(start, i + 1));
      start = i + 1;
    }
  }
  if (start < value.length) result.add(value.substring(start));
  return result;
}
