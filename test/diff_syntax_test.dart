import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/diff_syntax.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/repositories/diff_syntax_repository.dart';
import 'package:gitlama/services/diff_syntax_service.dart';
import 'package:gitlama/widgets/diff_view.dart';
import 'package:gitlama/widgets/status_notification.dart';
import 'package:meridian_ui/meridian_ui.dart';

final _identity = RepositorySessionIdentity(
  nativeId: BigInt.from(7),
  generation: 3,
);

DiffDisplayRow _line(int index, String text, {DiffRowKind? kind}) =>
    DiffDisplayRow(
      stableId: 'row-$index',
      kind: kind ?? DiffRowKind.addition,
      text: utf8.encode(text),
      newLine: index + 1,
      oldLine: kind == DiffRowKind.context ? index + 1 : null,
      selectable: kind != DiffRowKind.context,
    );

DiffPage _page(
  List<DiffDisplayRow> rows, {
  int offset = 0,
  int? total,
  BigInt? requestId,
}) => DiffPage(
  requestId: requestId ?? BigInt.one,
  layout: DiffViewLayout.unified,
  totalRows: total ?? offset + rows.length,
  offset: offset,
  rows: rows,
  payloadBytes: 0,
);

/// `keyword` over the first word of each row's text.
List<DiffSyntaxByteSpan> _firstWord(DiffDisplayRow row) {
  final end = utf8.decode(row.text).indexOf(' ');
  return end <= 0
      ? const []
      : [
          DiffSyntaxByteSpan(
            0,
            utf8.encode(utf8.decode(row.text).substring(0, end)).length,
            DiffSyntaxKind.keyword,
          ),
        ];
}

final class _Call {
  _Call(this.offset, this.maximumRows, this.syntaxRequestId);

  final int offset;
  final int maximumRows;
  final BigInt syntaxRequestId;
  final Completer<DiffSyntaxPage> reply = Completer();
}

/// Records requests; each answers when the test completes its reply.
final class _Repository implements DiffSyntaxRepository {
  final calls = <_Call>[];
  final cancelled = <BigInt>[];

  @override
  Future<DiffSyntaxPage> diffSyntaxPage(
    RepositorySessionIdentity identity, {
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
    required BigInt syntaxRequestId,
    required int offset,
    required int maximumRows,
  }) {
    final call = _Call(offset, maximumRows, syntaxRequestId);
    calls.add(call);
    return call.reply.future;
  }

  @override
  Future<bool> cancelDiffSyntax(
    RepositorySessionIdentity identity, {
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
    required BigInt syntaxRequestId,
  }) async {
    cancelled.add(syntaxRequestId);
    return true;
  }
}

/// Answers [call] for [rows] of [page] with first-word keywords.
void _answer(
  _Call call,
  DiffPage page, {
  DiffSyntaxSideState state = DiffSyntaxSideState.ready,
  int? count,
  int? nextOffset,
  String Function(int index, String id)? stableId,
  BigInt? syntaxRequestId,
}) {
  final rows = page.rows
      .skip(call.offset - page.offset)
      .take(count ?? call.maximumRows)
      .toList();
  call.reply.complete(
    DiffSyntaxPage(
      origin: DiffSyntaxOrigin.committed,
      diffRequestId: page.requestId,
      syntaxRequestId: syntaxRequestId ?? call.syntaxRequestId,
      offset: call.offset,
      nextOffset: nextOffset,
      rows: [
        for (final (index, row) in rows.indexed)
          DiffSyntaxRowResult(
            stableId: stableId?.call(index, row.stableId) ?? row.stableId,
            oldState: DiffSyntaxSideState.unsupported,
            newState: state,
            newSpans: state == DiffSyntaxSideState.ready
                ? _firstWord(row)
                : const [],
          ),
      ],
    ),
  );
}

Future<List<DiffRowSyntax?>> _convertNow(List<DiffSyntaxConversion> rows) =>
    SynchronousFuture(convertDiffSyntax(rows));

DiffSyntaxService _service(_Repository repository, {int concurrent = 2}) =>
    DiffSyntaxService(
      repository,
      convert: _convertNow,
      nextFrame: () => Future<void>.delayed(const Duration(milliseconds: 16)),
      concurrentRequests: concurrent,
    );

DiffSyntaxView _view(DiffSyntaxService service, {BigInt? requestId}) =>
    service.view(
      identity: _identity,
      origin: DiffSyntaxOrigin.committed,
      diffRequestId: requestId ?? BigInt.one,
    );

void main() {
  group('convertDiffSyntax', () {
    List<DiffSyntaxRun>? convert(String text, List<DiffSyntaxByteSpan> spans) =>
        convertDiffSyntax([
          DiffSyntaxConversion(
            utf8.encode(text),
            DiffSyntaxRowResult(
              stableId: 'r',
              oldState: DiffSyntaxSideState.unsupported,
              newState: DiffSyntaxSideState.ready,
              newSpans: spans,
            ),
          ),
        ]).single?.current;

    test('turns byte spans into UTF-16 runs after non-ASCII text', () {
      // é is two bytes and one unit; 🙂 four bytes and two units.
      const text = 'é🙂 x = "ü"';
      final runs = convert(text, const [
        DiffSyntaxByteSpan(2, 6, DiffSyntaxKind.variable),
        DiffSyntaxByteSpan(9, 10, DiffSyntaxKind.operator),
        DiffSyntaxByteSpan(11, 15, DiffSyntaxKind.string),
      ]);
      expect(runs, const [
        DiffSyntaxRun(1, 3, DiffSyntaxKind.variable),
        DiffSyntaxRun(6, 7, DiffSyntaxKind.operator),
        DiffSyntaxRun(8, 11, DiffSyntaxKind.string),
      ]);
      expect(text.substring(8, 11), '"ü"');
    });

    test('keeps combining sequences and drops plain runs', () {
      const text = 'é = 1';
      expect(
        convert(text, const [
          DiffSyntaxByteSpan(0, 3, DiffSyntaxKind.plain),
          DiffSyntaxByteSpan(6, 7, DiffSyntaxKind.number),
        ]),
        const [DiffSyntaxRun(5, 6, DiffSyntaxKind.number)],
      );
    });

    test('leaves a side plain for malformed spans or text', () {
      for (final spans in [
        const [DiffSyntaxByteSpan(1, 2, DiffSyntaxKind.keyword)], // inside é
        const [DiffSyntaxByteSpan(0, 9, DiffSyntaxKind.keyword)], // past end
        const [DiffSyntaxByteSpan(2, 2, DiffSyntaxKind.keyword)], // empty
        const [
          DiffSyntaxByteSpan(3, 4, DiffSyntaxKind.keyword),
          DiffSyntaxByteSpan(2, 3, DiffSyntaxKind.keyword),
        ], // unordered
      ]) {
        expect(convert('é abc', spans), isNull, reason: '$spans');
      }
      final invalid = convertDiffSyntax([
        DiffSyntaxConversion(
          [0x61, 0xFF, 0x62],
          const DiffSyntaxRowResult(
            stableId: 'r',
            oldState: DiffSyntaxSideState.ready,
            newState: DiffSyntaxSideState.ready,
            oldSpans: [DiffSyntaxByteSpan(0, 1, DiffSyntaxKind.keyword)],
            newSpans: [DiffSyntaxByteSpan(0, 1, DiffSyntaxKind.keyword)],
          ),
        ),
      ]).single;
      expect(invalid, isNull);
    });

    test('keeps a valid side when the other is malformed', () {
      final syntax = convertDiffSyntax([
        DiffSyntaxConversion(
          utf8.encode('let a'),
          const DiffSyntaxRowResult(
            stableId: 'r',
            oldState: DiffSyntaxSideState.ready,
            newState: DiffSyntaxSideState.ready,
            oldSpans: [DiffSyntaxByteSpan(0, 3, DiffSyntaxKind.keyword)],
            newSpans: [DiffSyntaxByteSpan(4, 9, DiffSyntaxKind.variable)],
          ),
        ),
      ]).single!;
      expect(syntax.old, const [DiffSyntaxRun(0, 3, DiffSyntaxKind.keyword)]);
      expect(syntax.current, isNull);
      expect(syntax.forCell(oldSide: false, split: false), syntax.old);
      expect(syntax.forCell(oldSide: false, split: true), isNull);
    });
  });

  group('DiffSyntaxService', () {
    final rows = [for (var i = 0; i < 40; i += 1) _line(i, 'word$i rest')];

    testWidgets(
      'asks only after the plain rows were accepted and input paused',
      (tester) async {
        final repository = _Repository();
        final service = _service(repository);
        final view = _view(service);
        await tester.pump(const Duration(seconds: 1));
        expect(repository.calls, isEmpty, reason: 'no accepted rows yet');
        view.accept(_page(rows));
        await tester.pump(const Duration(milliseconds: 100));
        view.noteActivity();
        await tester.pump(const Duration(milliseconds: 100));
        expect(repository.calls, isEmpty, reason: 'still within idle time');
        view.setInteracting(true);
        await tester.pump(const Duration(seconds: 1));
        expect(repository.calls, isEmpty, reason: 'scrolling pauses requests');
        view.setInteracting(false);
        await tester.pump(const Duration(milliseconds: 160));
        expect(repository.calls, hasLength(1));
        expect(repository.calls.single.offset, 0);
        expect(repository.calls.single.maximumRows, 32);
        service.dispose();
      },
    );

    testWidgets('publishes a few rows per frame and only while idle', (
      tester,
    ) async {
      final repository = _Repository();
      final service = _service(repository);
      final view = _view(service);
      var notified = 0;
      view.addListener(() => notified += 1);
      final page = _page(rows);
      view.accept(page);
      await tester.pump(const Duration(milliseconds: 160));
      _answer(repository.calls.single, page);
      await tester.pump();
      expect(view.rowSyntax('row-0'), isNull, reason: 'waits for a frame');
      await tester.pump(const Duration(milliseconds: 16));
      expect(notified, 1);
      expect(
        [for (var i = 0; i < 6; i += 1) view.rowSyntax('row-$i') != null],
        [true, true, true, true, false, false],
      );
      view.setInteracting(true);
      await tester.pump(const Duration(milliseconds: 200));
      expect(view.rowSyntax('row-4'), isNull, reason: 'held while scrolling');
      view.setInteracting(false);
      await tester.pump(const Duration(milliseconds: 16 * 8));
      expect(view.rowSyntax('row-31'), isNotNull);
      expect(view.rowSyntax('row-32'), isNull);
      expect(view.rowSyntax('row-0')!.current, const [
        DiffSyntaxRun(0, 5, DiffSyntaxKind.keyword),
      ]);
      // The next chunk follows below the visible rows.
      await tester.pump(const Duration(milliseconds: 200));
      expect(repository.calls, hasLength(2));
      expect(repository.calls.last.offset, 32);
      expect(repository.calls.last.maximumRows, 8);
      service.dispose();
    });

    testWidgets('rejects replies that do not match the request or the rows', (
      tester,
    ) async {
      final repository = _Repository();
      final service = _service(repository);
      final view = _view(service);
      final page = _page(rows.take(4).toList());
      view.accept(page);
      await tester.pump(const Duration(milliseconds: 160));
      _answer(
        repository.calls.single,
        page,
        stableId: (index, id) => index == 2 ? 'other' : id,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(view.rowSyntax('row-0'), isNull);
      expect(repository.calls, hasLength(1), reason: 'settled plain');

      final second = _view(service, requestId: BigInt.two);
      final page2 = _page(rows.take(4).toList(), requestId: BigInt.two);
      second.accept(page2);
      await tester.pump(const Duration(milliseconds: 160));
      _answer(
        repository.calls.last,
        page2,
        syntaxRequestId: repository.calls.last.syntaxRequestId + BigInt.one,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(second.rowSyntax('row-0'), isNull);
      service.dispose();
    });

    testWidgets('a page of another diff never reaches a view', (tester) async {
      final repository = _Repository();
      final service = _service(repository);
      final view = _view(service);
      view.accept(_page(rows, requestId: BigInt.two));
      await tester.pump(const Duration(seconds: 1));
      expect(repository.calls, isEmpty);
      service.dispose();
    });

    testWidgets('follows a shortened reply from its continuation', (
      tester,
    ) async {
      final repository = _Repository();
      final service = _service(repository);
      final view = _view(service);
      final page = _page(rows.take(10).toList());
      view.accept(page);
      await tester.pump(const Duration(milliseconds: 160));
      _answer(repository.calls.single, page, count: 6, nextOffset: 6);
      await tester.pump();
      expect(repository.calls, hasLength(2));
      expect(repository.calls.last.offset, 6);
      expect(repository.calls.last.maximumRows, 4);
      _answer(repository.calls.last, page);
      await tester.pump(const Duration(seconds: 1));
      expect(view.rowSyntax('row-9'), isNotNull);
      service.dispose();
    });

    testWidgets('asks again once after a deferred reply, then stays plain', (
      tester,
    ) async {
      final repository = _Repository();
      final service = _service(repository);
      final view = _view(service);
      final page = _page(rows.take(4).toList());
      view.accept(page);
      await tester.pump(const Duration(milliseconds: 160));
      _answer(
        repository.calls.single,
        page,
        state: DiffSyntaxSideState.deferred,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(repository.calls, hasLength(2));
      _answer(repository.calls.last, page, state: DiffSyntaxSideState.deferred);
      await tester.pump(const Duration(seconds: 2));
      expect(repository.calls, hasLength(2));
      expect(view.rowSyntax('row-0'), isNull);
      service.dispose();
    });

    testWidgets('a failed read leaves text plain without retrying', (
      tester,
    ) async {
      final repository = _Repository();
      final service = _service(repository);
      final view = _view(service);
      view.accept(_page(rows.take(4).toList()));
      await tester.pump(const Duration(milliseconds: 160));
      repository.calls.single.reply.completeError(
        const RepositorySessionException(
          RepositoryFailure(RepositoryFailureCode.staleGeneration),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(repository.calls, hasLength(1));
      service.dispose();
    });

    testWidgets('bounds concurrent requests across views', (tester) async {
      final repository = _Repository();
      final service = _service(repository);
      final pages = [
        for (var id = 1; id <= 3; id += 1)
          _page(rows.take(4).toList(), requestId: BigInt.from(id)),
      ];
      for (final (index, page) in pages.indexed) {
        _view(service, requestId: BigInt.from(index + 1)).accept(page);
      }
      await tester.pump(const Duration(milliseconds: 160));
      expect(repository.calls, hasLength(2));
      _answer(repository.calls.first, pages[0]);
      await tester.pump();
      expect(repository.calls, hasLength(3));
      await tester.pump(const Duration(seconds: 1));
      service.dispose();
    });

    testWidgets(
      'a retired view cancels its request and ignores the late reply',
      (tester) async {
        final repository = _Repository();
        final service = _service(repository);
        final view = _view(service);
        final page = _page(rows.take(4).toList());
        view.accept(page);
        await tester.pump(const Duration(milliseconds: 160));
        final call = repository.calls.single;
        view.dispose();
        await tester.pump();
        expect(repository.cancelled, [call.syntaxRequestId]);
        _answer(call, page);
        await tester.pump(const Duration(seconds: 1));
        expect(view.rowSyntax('row-0'), isNull);
        service.dispose();
      },
    );
  });

  group('DiffView syntax colours', () {
    Widget host(DiffView view) => MaterialApp(
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, app) => StatusNotificationScope(child: app!),
      home: Scaffold(body: SizedBox(width: 600, height: 300, child: view)),
    );

    TextSpan? spanOf(WidgetTester tester, String id, {bool old = false}) {
      final finder = find.byKey(
        ValueKey('diff-content-$id-${old ? 'old' : 'new'}'),
      );
      if (finder.evaluate().isEmpty) return null;
      return tester.widget<Text>(finder).textSpan as TextSpan?;
    }

    Color? colorOf(TextSpan span, String text) {
      Color? found;
      span.visitChildren((child) {
        if (child is TextSpan && child.text == text) {
          found = child.style?.color;
          return false;
        }
        return true;
      });
      return found;
    }

    testWidgets('colours arrive after the plain text, beside intra-line marks, '
        'without changing copied text or scroll position', (tester) async {
      final repository = _Repository();
      final service = _service(repository);
      final rows = [
        for (var i = 0; i < 60; i += 1)
          DiffDisplayRow(
            stableId: 'row-$i',
            kind: DiffRowKind.addition,
            text: utf8.encode('final value$i = 1;'),
            newLine: i + 1,
            selectable: true,
            intraLine: i == 0 ? const [DiffSpan(0, 5)] : const [],
          ),
      ];
      final page = _page(rows);
      final view = _view(service)..accept(page);
      final controller = ScrollController();
      await tester.pumpWidget(
        host(
          DiffView(
            itemCount: rows.length,
            rowAt: (index) => rows[index],
            layout: DiffViewLayout.unified,
            selectedIds: const {},
            onSelectionChanged: (_) {},
            controller: controller,
            syntax: view,
          ),
        ),
      );
      // Plain text first.
      expect(spanOf(tester, 'row-0')!.toPlainText(), 'final value0 = 1;');
      expect(spanOf(tester, 'row-0')!.children, isNull);
      await tester.pump(const Duration(milliseconds: 200));
      expect(repository.calls, hasLength(1));
      controller.jumpTo(9);
      final position = controller.position;
      _answer(repository.calls.single, page);
      for (var frame = 0; frame < 10; frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final first = spanOf(tester, 'row-1')!;
      expect(first.toPlainText(), 'final value1 = 1;');
      expect(colorOf(first, 'final'), MeridianSyntaxColors.light.keyword);
      // Intra-line marks are computed independently of colours.
      final marks = tester.widget<DiffLineMarks>(
        find.ancestor(
          of: find.byKey(const ValueKey('diff-content-row-0-new')),
          matching: find.byType(DiffLineMarks),
        ),
      );
      expect(marks.marks, [const TextRange(start: 0, end: 5)]);
      expect(spanOf(tester, 'row-0')!.toPlainText(), 'final value0 = 1;');
      expect(identical(controller.position, position), isTrue);
      expect(controller.offset, 9);
      expect(tester.takeException(), isNull);
      service.dispose();
      controller.dispose();
    });

    testWidgets('Latin-1 and truncated rows stay plain', (tester) async {
      final repository = _Repository();
      final service = _service(repository);
      final rows = [
        _line(0, 'final a = 1;'),
        DiffDisplayRow(
          stableId: 'row-1',
          kind: DiffRowKind.addition,
          text: utf8.encode('final b = 2;'),
          newLine: 2,
          selectable: true,
          textTruncated: true,
        ),
      ];
      final page = _page(rows);
      final view = _view(service)..accept(page);
      Widget build(DiffTextEncoding encoding) => host(
        DiffView(
          itemCount: rows.length,
          rowAt: (index) => rows[index],
          layout: DiffViewLayout.unified,
          selectedIds: const {},
          onSelectionChanged: (_) {},
          encoding: encoding,
          syntax: view,
        ),
      );
      await tester.pumpWidget(build(DiffTextEncoding.utf8));
      await tester.pump(const Duration(milliseconds: 200));
      _answer(repository.calls.single, page);
      for (var frame = 0; frame < 4; frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(view.rowSyntax('row-1'), isNotNull);
      expect(colorOf(spanOf(tester, 'row-0')!, 'final'), isNotNull);
      expect(spanOf(tester, 'row-1')!.children, isNull);
      await tester.pumpWidget(build(DiffTextEncoding.latin1));
      expect(spanOf(tester, 'row-0')!.children, isNull);
      service.dispose();
    });

    testWidgets('copying coloured lines copies their text', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      final repository = _Repository();
      final service = _service(repository);
      final rows = [_line(0, 'final a = 1;'), _line(1, 'return a;')];
      final page = _page(rows);
      final view = _view(service)..accept(page);
      Set<String> selected = {};
      await tester.pumpWidget(
        host(
          DiffView(
            itemCount: rows.length,
            rowAt: (index) => rows[index],
            layout: DiffViewLayout.unified,
            selectedIds: selected,
            onSelectionChanged: (value) => selected = value,
            syntax: view,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      _answer(repository.calls.single, page);
      for (var frame = 0; frame < 4; frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(colorOf(spanOf(tester, 'row-1')!, 'return'), isNotNull);
      // Select both lines from the gutter and copy.
      final gutter = tester.getTopLeft(
        find.byKey(const ValueKey('diff-row-row-0')),
      );
      await tester.tapAt(gutter + const Offset(10, 9));
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('diff-row-row-1'))) +
            const Offset(10, 9),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      final meta = defaultTargetPlatform == TargetPlatform.macOS;
      await tester.sendKeyDownEvent(
        meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(
        meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
      );
      await tester.pump();
      expect(copied.last, 'final a = 1;\nreturn a;');
      service.dispose();
    });
  });
}
