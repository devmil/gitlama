import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/conflict.dart';
import 'package:gitlama/services/conflict/conflict_merge_draft.dart';

void main() {
  test('conflict markers match the fixture the native resolver uses', () {
    final fixture =
        jsonDecode(
              File('test/fixtures/conflict_markers.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    for (final text in (fixture['markers']! as List).cast<String>()) {
      expect(hasConflictMarkers(text), isTrue, reason: jsonEncode(text));
    }
    for (final text in (fixture['content']! as List).cast<String>()) {
      expect(hasConflictMarkers(text), isFalse, reason: jsonEncode(text));
    }
  });

  test('separate choices remain a draft and preserve later manual edits', () {
    const source =
        'before\n<<<<<<< HEAD\nleft one\n=======\nright one\n>>>>>>> topic\n'
        'between\n<<<<<<< HEAD\nleft two\n=======\nright two\n>>>>>>> topic\nafter\n';
    final file = ConflictFile(
      path: 'merge.txt'.codeUnits,
      kind: ConflictFileKind.text,
      ancestor: const ConflictSide(present: false, byteCount: 0),
      current: const ConflictSide(present: false, byteCount: 0),
      incoming: const ConflictSide(present: false, byteCount: 0),
      resultPresent: true,
      markerFree: false,
      regions: const [],
      fingerprint: BigInt.one,
      canUndoResolution: false,
      result: source.codeUnits,
    );
    final draft = ConflictMergeDraft.fromFile(file);
    expect(draft.blocks, hasLength(2));
    expect(draft.rows.where((row) => row.blockIndex == 0).length, 1);
    expect(draft.resolvedCount, 0);
    expect(
      draft.take(0, ConflictRegionChoice.both),
      contains('left one\nright one\n'),
    );
    expect(draft.unresolvedCount, 1);
    draft.edit(
      draft.text.replaceFirst('between\n', 'between manually edited\n'),
    );
    expect(
      draft.take(1, ConflictRegionChoice.incoming),
      'before\nleft one\nright one\nbetween manually edited\nright two\nafter\n',
    );
    expect(draft.resolvedCount, 2);
  });

  test('diff3 ancestor is excluded from current choice', () {
    final file = ConflictFile(
      path: 'merge.txt'.codeUnits,
      kind: ConflictFileKind.text,
      ancestor: const ConflictSide(present: false, byteCount: 0),
      current: const ConflictSide(present: false, byteCount: 0),
      incoming: const ConflictSide(present: false, byteCount: 0),
      resultPresent: true,
      markerFree: false,
      regions: const [],
      fingerprint: BigInt.one,
      canUndoResolution: false,
      result:
          '<<<<<<< HEAD\nleft\n||||||| base\nold\n=======\nright\n>>>>>>> topic\n'
              .codeUnits,
    );
    final draft = ConflictMergeDraft.fromFile(file);
    expect(draft.take(0, ConflictRegionChoice.current), 'left\n');
    expect(draft.take(0, ConflictRegionChoice.incoming), 'left\nright\n');
    expect(draft.take(0, ConflictRegionChoice.current), 'left\nright\n');
    expect(draft.remove(0, ConflictRegionChoice.current), 'right\n');
    expect(
      draft.remove(0, ConflictRegionChoice.incoming),
      '<<<<<<< HEAD\nleft\n||||||| base\nold\n=======\nright\n>>>>>>> topic\n',
    );
  });

  test(
    'comparison shows actual side files and aligns surrounding differences',
    () {
      final file = ConflictFile(
        path: 'merge.txt'.codeUnits,
        kind: ConflictFileKind.text,
        ancestor: const ConflictSide(present: false, byteCount: 0),
        current: ConflictSide(
          present: true,
          byteCount: 32,
          content: 'before\nleft\ncurrent only\nafter\n'.codeUnits,
        ),
        incoming: ConflictSide(
          present: true,
          byteCount: 33,
          content: 'before\nright\nincoming only\nafter\n'.codeUnits,
        ),
        resultPresent: true,
        markerFree: false,
        regions: [
          ConflictRegion(
            index: 0,
            current: 'left\n'.codeUnits,
            incoming: 'right\n'.codeUnits,
          ),
        ],
        fingerprint: BigInt.one,
        canUndoResolution: false,
        result:
            'before\n<<<<<<< HEAD\nleft\n=======\nright\n>>>>>>> topic\nafter\n'
                .codeUnits,
      );
      final rows = ConflictMergeDraft.fromFile(file).rows;
      expect(
        rows.map((row) => row.current).join(),
        'before\nleft\ncurrent only\nafter\n',
      );
      expect(
        rows.map((row) => row.incoming).join(),
        'before\nright\nincoming only\nafter\n',
      );
      expect(rows.singleWhere((row) => row.blockIndex == 0).current, 'left\n');
      expect(
        rows.singleWhere((row) => row.different).incoming,
        'incoming only\n',
      );
    },
  );
}
