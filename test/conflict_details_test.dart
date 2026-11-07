import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/conflict.dart';
import 'package:gitlama/models/conflict_details.dart';
import 'package:gitlama/services/conflict/conflict_merge_draft.dart';
import 'package:gitlama/widgets/conflict_file_details.dart';

const absent = ConflictSide(present: false, byteCount: 0);
ConflictSide side(String value, {int mode = 0x81a4}) => ConflictSide(
  present: true,
  mode: mode,
  content: utf8.encode(value),
  byteCount: utf8.encode(value).length,
);
ConflictFile file(
  ConflictSide current,
  ConflictSide incoming, {
  ConflictSide ancestor = absent,
  ConflictFileKind kind = ConflictFileKind.text,
}) => ConflictFile(
  path: utf8.encode('src/file.txt'),
  kind: kind,
  ancestor: ancestor,
  current: current,
  incoming: incoming,
  result: current.content ?? incoming.content,
  resultMode: current.mode ?? incoming.mode,
  resultPresent: current.present || incoming.present,
  markerFree: true,
  regions: const [],
  fingerprint: BigInt.one,
  canUndoResolution: false,
);

void main() {
  test('all seven unmerged presence combinations stay distinct', () {
    final present = side('');
    final cases = [
      (true, false, false, ConflictPresence.bothDeleted),
      (false, true, false, ConflictPresence.addedCurrent),
      (true, true, false, ConflictPresence.deletedIncoming),
      (false, false, true, ConflictPresence.addedIncoming),
      (true, false, true, ConflictPresence.deletedCurrent),
      (false, true, true, ConflictPresence.bothAdded),
      (true, true, true, ConflictPresence.bothPresent),
    ];
    for (final (base, current, incoming, expected) in cases) {
      expect(
        ConflictDetails(
          file(
            current ? present : absent,
            incoming ? present : absent,
            ancestor: base ? present : absent,
          ),
        ).presence,
        expected,
      );
    }
  });

  test('identical bytes do not hide executable and entry type changes', () {
    for (final mode in [0x81ed, 0xa000, 0xe000, 0x4000]) {
      final details = ConflictDetails(
        file(side('target'), side('target', mode: mode)),
      );
      expect(details.contentDifference, ConflictContentDifference.identical);
      expect(details.modeDiffers, isTrue);
    }
    expect(
      ConflictDetails(file(side(''), absent)).contentDifference,
      ConflictContentDifference.missingSide,
    );
  });

  test(
    'invisible byte differences are explained without conflating content',
    () {
      for (final (a, b, difference) in [
        ('one\ntwo\n', 'one\r\ntwo\r\n', ConflictContentDifference.lineEndings),
        ('one\rtwo\r', 'one\ntwo\n', ConflictContentDifference.lineEndings),
        ('one\n', 'one', ConflictContentDifference.finalNewline),
        ('one\r\n', 'one', ConflictContentDifference.finalNewline),
        ('one', '\uFEFFone', ConflictContentDifference.byteOrderMark),
        ('one two\n', 'one\ttwo \n', ConflictContentDifference.whitespace),
        ('one', 'two', ConflictContentDifference.content),
      ]) {
        expect(
          ConflictDetails(file(side(a), side(b))).contentDifference,
          difference,
          reason: '$a compared with $b',
        );
      }
    },
  );

  test('binary differences and missing previews never imply equal content', () {
    final left = const ConflictSide(
      present: true,
      byteCount: 1,
      content: [0xff],
    );
    final right = const ConflictSide(
      present: true,
      byteCount: 1,
      content: [0xfe],
    );
    expect(
      ConflictDetails(
        file(left, right, kind: ConflictFileKind.binary),
      ).contentDifference,
      ConflictContentDifference.content,
    );
    final unloaded = const ConflictSide(present: true, byteCount: 2000000);
    expect(
      ConflictDetails(
        file(unloaded, unloaded, kind: ConflictFileKind.huge),
      ).contentDifference,
      ConflictContentDifference.unavailable,
    );
  });

  test('marker-free delete/modify comparison renders actual missing side', () {
    for (final missingCurrent in [true, false]) {
      final changed = side('changed\n');
      final draft = ConflictMergeDraft.fromFile(
        file(
          missingCurrent ? absent : changed,
          missingCurrent ? changed : absent,
          ancestor: side('base\n'),
        ),
      );
      expect(
        draft.rows.map((row) => row.current).join(),
        missingCurrent ? '' : 'changed\n',
      );
      expect(
        draft.rows.map((row) => row.incoming).join(),
        missingCurrent ? 'changed\n' : '',
      );
      expect(draft.rows.every((row) => row.different), isTrue);
      expect(draft.blocks, isEmpty);
    }
  });

  for (final locale in ['en', 'de']) {
    testWidgets('metadata explanation fits a narrow $locale pane at 130%', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          theme: buildAppTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: Column(
              children: [
                ConflictFileDetails(
                  file: file(side('same\r\n'), side('same\r\n', mode: 0x81ed)),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          locale == 'en' ? 'identical file bytes' : 'bytegleich',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(locale == 'en' ? 'unmerged state' : 'Git führt'),
        findsOneWidget,
      );
      final disclosure = find.text(
        locale == 'en' ? 'Entry details' : 'Eintragsdetails',
      );
      await tester.ensureVisible(disclosure);
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      expect(find.textContaining('100755'), findsWidgets);
      expect(find.textContaining('CRLF'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
