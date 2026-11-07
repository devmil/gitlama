import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/diff_syntax.dart';
import 'package:gitlama/models/remote_contract.g.dart';
import 'package:gitlama/models/source_syntax.dart';
import 'package:gitlama/repositories/source_syntax_repository.dart';
import 'package:gitlama/services/source_syntax_service.dart';

const _chunk = ContractLimits.textSyntaxPageLines;

final class _Call {
  _Call(
    this.viewId,
    this.syntaxRequestId,
    this.source,
    this.firstLine,
    this.maximumLines,
  );

  final BigInt viewId;
  final BigInt syntaxRequestId;
  final Uint8List source;
  final int firstLine;
  final int maximumLines;
  final Completer<SourceSyntaxPage> reply = Completer();

  String get text => utf8.decode(source);
}

/// Records requests; each answers when the test completes its reply.
final class _Repository implements SourceSyntaxRepository {
  final calls = <_Call>[];
  final cancelled = <BigInt>[];

  @override
  Future<SourceSyntaxPage> sourceSyntaxPage({
    required BigInt viewId,
    required BigInt syntaxRequestId,
    required List<int> path,
    required Uint8List source,
    required int firstLine,
    required int maximumLines,
  }) {
    final call = _Call(
      viewId,
      syntaxRequestId,
      source,
      firstLine,
      maximumLines,
    );
    calls.add(call);
    return call.reply.future;
  }

  @override
  Future<bool> cancelSourceSyntax({
    required BigInt viewId,
    required BigInt syntaxRequestId,
  }) async {
    cancelled.add(syntaxRequestId);
    return true;
  }
}

/// Answers [call] with `keyword` over the first word of each line it asks for.
void _answer(
  _Call call, {
  DiffSyntaxSideState state = DiffSyntaxSideState.ready,
  DiffSyntaxSideState lineState = DiffSyntaxSideState.ready,
  int? count,
  BigInt? syntaxRequestId,
}) {
  final lines = call.text.split('\n');
  if (call.text.endsWith('\n')) lines.removeLast();
  final asked = lines.skip(call.firstLine - 1).take(count ?? _chunk).toList();
  call.reply.complete(
    SourceSyntaxPage(
      viewId: call.viewId,
      syntaxRequestId: syntaxRequestId ?? call.syntaxRequestId,
      firstLine: call.firstLine,
      state: state,
      lines: state != DiffSyntaxSideState.ready
          ? const []
          : [
              for (final line in asked)
                SourceSyntaxLine(
                  state: lineState,
                  runs: lineState != DiffSyntaxSideState.ready
                      ? const []
                      : [
                          if (line.split(' ').first.isNotEmpty)
                            DiffSyntaxRun(
                              0,
                              line.split(' ').first.length,
                              DiffSyntaxKind.keyword,
                            ),
                        ],
                ),
            ],
    ),
  );
}

SourceSyntaxService _service(_Repository repository, {int concurrent = 2}) =>
    SourceSyntaxService(
      repository,
      nextFrame: () => Future<void>.delayed(const Duration(milliseconds: 16)),
      concurrentRequests: concurrent,
      linesPerFrame: 2,
    );

String _lines(int count) =>
    [for (var line = 1; line <= count; line += 1) 'word$line rest'].join('\n');

void main() {
  testWidgets('asks once idle for the visible lines and publishes a few '
      'lines per frame', (tester) async {
    final repository = _Repository();
    final service = _service(repository);
    addTearDown(service.dispose);
    final view = service.view(path: 'a.dart'.codeUnits, text: _lines(5));
    var notified = 0;
    view
      ..addListener(() => notified += 1)
      ..noteActivity();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repository.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 60));
    expect(repository.calls, hasLength(1));
    expect(repository.calls.single.firstLine, 1);
    expect(repository.calls.single.maximumLines, _chunk);
    expect(repository.calls.single.text, _lines(5));

    _answer(repository.calls.single);
    await tester.pump();
    expect(view.runsOf(1), isNull);
    await tester.pump(const Duration(milliseconds: 16));
    expect(view.runsOf(1), const [DiffSyntaxRun(0, 5, DiffSyntaxKind.keyword)]);
    expect(view.runsOf(3), isNull);
    await tester.pump(const Duration(milliseconds: 50));
    expect(view.runsOf(5), isNotNull);
    expect(notified, 3);
    // A settled chunk is not asked for again.
    view.setVisible(1, 5);
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.calls, hasLength(1));
  });

  testWidgets('waits while the user scrolls and follows the visible lines', (
    tester,
  ) async {
    final repository = _Repository();
    final service = _service(repository);
    addTearDown(service.dispose);
    final view = service.view(path: 'a.rs'.codeUnits, text: _lines(1000));
    view
      ..setInteracting(true)
      ..setVisible(600, 640);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.calls, isEmpty);
    view.setInteracting(false);
    await tester.pump(const Duration(milliseconds: 160));
    expect(repository.calls.single.firstLine, 4 * _chunk + 1);
    _answer(repository.calls.single);
    // Two lines per frame: the whole chunk within 64 frames.
    for (var frame = 0; frame < 70; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(view.runsOf(600), isNotNull);
    expect(view.runsOf(1), isNull);
    // The chunk below the visible lines followed at the next idle moment.
    expect(repository.calls, hasLength(2));
    expect(repository.calls.last.firstLine, 5 * _chunk + 1);
    _answer(repository.calls.last);
    await tester.pump(const Duration(milliseconds: 1200));
  });

  testWidgets('a reply that does not match the request stays plain', (
    tester,
  ) async {
    final repository = _Repository();
    final service = _service(repository);
    addTearDown(service.dispose);
    final view = service.view(path: 'a.rs'.codeUnits, text: _lines(5))
      ..noteActivity();
    await tester.pump(const Duration(milliseconds: 160));
    _answer(repository.calls.single, syntaxRequestId: BigInt.from(999));
    await tester.pump(const Duration(milliseconds: 100));
    expect(view.hasColours, isFalse);

    final short = service.view(path: 'a.rs'.codeUnits, text: _lines(5))
      ..noteActivity();
    await tester.pump(const Duration(milliseconds: 160));
    // Fewer lines than the text has from the first line asked for.
    _answer(repository.calls.last, count: 3);
    await tester.pump(const Duration(milliseconds: 100));
    expect(short.hasColours, isFalse);

    final outside = service.view(path: 'a.rs'.codeUnits, text: 'ab\ncd')
      ..noteActivity();
    await tester.pump(const Duration(milliseconds: 160));
    repository.calls.last.reply.complete(
      SourceSyntaxPage(
        viewId: repository.calls.last.viewId,
        syntaxRequestId: repository.calls.last.syntaxRequestId,
        firstLine: 1,
        state: DiffSyntaxSideState.ready,
        lines: const [
          SourceSyntaxLine(
            state: DiffSyntaxSideState.ready,
            runs: [DiffSyntaxRun(0, 3, DiffSyntaxKind.keyword)],
          ),
          SourceSyntaxLine(
            state: DiffSyntaxSideState.ready,
            runs: [DiffSyntaxRun(0, 2, DiffSyntaxKind.keyword)],
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // The run longer than its line is dropped; the valid line keeps colours.
    expect(outside.runsOf(1), isNull);
    expect(outside.runsOf(2), isNotNull);
    expect(repository.calls, hasLength(3));
  });

  testWidgets('a text without grammar stays plain until it changes', (
    tester,
  ) async {
    final repository = _Repository();
    final service = _service(repository);
    addTearDown(service.dispose);
    final view = service.view(path: 'notes'.codeUnits, text: _lines(500))
      ..noteActivity();
    await tester.pump(const Duration(milliseconds: 160));
    _answer(repository.calls.single, state: DiffSyntaxSideState.unsupported);
    await tester.pump();
    view.setVisible(300, 320);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.calls, hasLength(1));
    view.update('${_lines(500)}\nmore');
    await tester.pump(const Duration(milliseconds: 160));
    expect(repository.calls, hasLength(2));
  });

  testWidgets('asks again once after a deferred reply, then stays plain', (
    tester,
  ) async {
    final repository = _Repository();
    final service = _service(repository);
    addTearDown(service.dispose);
    final view = service.view(path: 'a.rs'.codeUnits, text: _lines(3))
      ..noteActivity();
    await tester.pump(const Duration(milliseconds: 160));
    _answer(repository.calls.single, state: DiffSyntaxSideState.deferred);
    await tester.pump(const Duration(milliseconds: 160));
    expect(repository.calls, hasLength(2));
    _answer(repository.calls.last, lineState: DiffSyntaxSideState.deferred);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.calls, hasLength(2));
    expect(view.hasColours, isFalse);
  });

  testWidgets('an edit keeps the colours of unchanged lines, shifted, and '
      'retires the request for the old text', (tester) async {
    final repository = _Repository();
    final service = _service(repository);
    addTearDown(service.dispose);
    const before = 'alpha one\nbeta two\ngamma three\ndelta four';
    final view = service.view(path: 'a.rs'.codeUnits, text: before)
      ..noteActivity();
    await tester.pump(const Duration(milliseconds: 160));
    _answer(repository.calls.single);
    await tester.pump(const Duration(milliseconds: 100));
    expect(view.runsOf(4), isNotNull);

    // Line 2 is replaced by two lines.
    const after = 'alpha one\nbe\nta two\ngamma three\ndelta four';
    view.update(after);
    expect(view.text, after);
    expect(view.runsOf(1), const [DiffSyntaxRun(0, 5, DiffSyntaxKind.keyword)]);
    expect(view.runsOf(2), isNull);
    expect(view.runsOf(3), isNull);
    expect(view.runsOf(4), const [DiffSyntaxRun(0, 5, DiffSyntaxKind.keyword)]);
    expect(view.runsOf(5), const [DiffSyntaxRun(0, 5, DiffSyntaxKind.keyword)]);
    expect(view.lineCount, 5);
    expect(view.lineAt(after.indexOf('ta two')), 3);

    await tester.pump(const Duration(milliseconds: 160));
    expect(repository.calls, hasLength(2));
    expect(repository.calls.last.text, after);
    // Typing again before the answer retires the request in flight.
    view.update('$after!');
    expect(repository.cancelled, [repository.calls.last.syntaxRequestId]);
    _answer(repository.calls.last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(view.runsOf(2), isNull);
    await tester.pump(const Duration(milliseconds: 160));
    expect(repository.calls, hasLength(3));
    _answer(repository.calls.last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(view.runsOf(2), const [DiffSyntaxRun(0, 2, DiffSyntaxKind.keyword)]);
  });

  testWidgets('disposing cancels the request in flight and drops its reply', (
    tester,
  ) async {
    final repository = _Repository();
    final service = _service(repository);
    addTearDown(service.dispose);
    final view = service.view(path: 'a.rs'.codeUnits, text: _lines(3))
      ..noteActivity();
    await tester.pump(const Duration(milliseconds: 160));
    view.dispose();
    expect(repository.cancelled, [repository.calls.single.syntaxRequestId]);
    _answer(repository.calls.single);
    await tester.pump(const Duration(milliseconds: 100));
    expect(view.hasColours, isFalse);
  });

  testWidgets('bounds concurrent requests across views', (tester) async {
    final repository = _Repository();
    final service = _service(repository, concurrent: 1);
    addTearDown(service.dispose);
    service.view(path: 'a.rs'.codeUnits, text: _lines(3)).noteActivity();
    service.view(path: 'b.rs'.codeUnits, text: _lines(3)).noteActivity();
    await tester.pump(const Duration(milliseconds: 160));
    expect(repository.calls, hasLength(1));
    _answer(repository.calls.single);
    await tester.pump();
    expect(repository.calls, hasLength(2));
    expect(repository.calls.last.viewId, isNot(repository.calls.first.viewId));
    _answer(repository.calls.last);
    await tester.pump(const Duration(milliseconds: 100));
  });

  test('counts lines the way the core does', () {
    final service = SourceSyntaxService(_Repository());
    addTearDown(service.dispose);
    expect(service.view(path: const [], text: '').lineCount, 0);
    expect(service.view(path: const [], text: 'a').lineCount, 1);
    expect(service.view(path: const [], text: 'a\n').lineCount, 1);
    expect(service.view(path: const [], text: 'a\r\nb').lineCount, 2);
    final view = service.view(path: const [], text: 'ab\ncd\nef');
    expect(
      [view.lineAt(0), view.lineAt(2), view.lineAt(3), view.lineAt(8)],
      [1, 1, 2, 3],
    );
    expect(view.lineStart(3), 6);
  });
}
