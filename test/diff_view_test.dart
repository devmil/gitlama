import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/widgets/diff_view.dart';
import 'package:gitlama/widgets/native_menu.dart';
import 'package:gitlama/widgets/status_notification.dart';

import 'support/native_menu_model.dart';

Widget _host(
  Widget child, {
  double width = 420,
  double height = 200,
  Locale? locale,
}) => MaterialApp(
  locale: locale,
  theme: buildAppTheme(Brightness.light),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, app) => StatusNotificationScope(child: app!),
  home: Scaffold(
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: width, height: height, child: child),
        const StatusNotificationText(),
      ],
    ),
  ),
);

/// A hunk header, a context line, two changes and another context line.
final _hunkRows = [
  DiffDisplayRow(
    stableId: 'hunk',
    kind: DiffRowKind.hunk,
    text: utf8.encode('@@ -1,3 +1,3 @@ main'),
    oldLine: 1,
    newLine: 1,
  ),
  DiffDisplayRow(
    stableId: 'context-1',
    kind: DiffRowKind.context,
    text: utf8.encode('keep'),
    oldLine: 1,
    newLine: 1,
  ),
  DiffDisplayRow(
    stableId: 'removed',
    kind: DiffRowKind.deletion,
    text: utf8.encode('old line'),
    oldLine: 2,
    selectable: true,
  ),
  DiffDisplayRow(
    stableId: 'added',
    kind: DiffRowKind.addition,
    text: utf8.encode('new line ${'x' * 200}'),
    newLine: 2,
    selectable: true,
  ),
  DiffDisplayRow(
    stableId: 'context-2',
    kind: DiffRowKind.context,
    text: utf8.encode('tail'),
    oldLine: 3,
    newLine: 3,
  ),
];

/// Clipboard writes of the current test.
List<String> _captureClipboard(WidgetTester tester) {
  final copies = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copies.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copies;
}

/// The global position just after character [offset] of row [id]'s text.
Offset _charAt(
  WidgetTester tester,
  String id,
  int offset, {
  String side = 'new',
}) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.byKey(ValueKey('diff-content-$id-$side')),
  );
  final position = TextPosition(offset: offset);
  final caret = paragraph.getOffsetForCaret(position, Rect.zero);
  final line = paragraph.getFullHeightForCaret(position);
  return paragraph.localToGlobal(caret + Offset(1, line / 2));
}

/// The line number gutter of row [id].
Offset _gutter(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey('diff-row-$id'))) +
    const Offset(
      GitLamaLayout.diffGutterWidth / 2,
      GitLamaLayout.diffLineHeight / 2,
    );

Future<void> _click(
  WidgetTester tester,
  Offset at, {
  bool shift = false,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tapAt(at, kind: PointerDeviceKind.mouse);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final mouse = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await mouse.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await mouse.moveTo(to);
  await tester.pump();
  await mouse.up();
  await tester.pump();
}

Future<void> _copyShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// A selectable view of [_hunkRows] whose owner keeps the reported lines.
Widget _selectableHunk({
  required Set<String> Function() selected,
  required ValueChanged<Set<String>> onChanged,
  DiffSelectionActions? selectionActions,
  bool wrap = false,
}) => _host(
  StatefulBuilder(
    builder: (context, update) => DiffView(
      itemCount: _hunkRows.length,
      rowAt: (index) => _hunkRows[index],
      hunkIndices: const {0},
      layout: DiffViewLayout.unified,
      wrap: wrap,
      selectedIds: selected(),
      onSelectionChanged: (value) => update(() => onChanged(value)),
      selectionActions: selectionActions,
    ),
  ),
);

void main() {
  testWidgets('large file information fits a narrow German diff pane', (
    tester,
  ) async {
    final row = DiffDisplayRow(
      stableId: 'large-de',
      kind: DiffRowKind.tooLarge,
      text: utf8.encode('72351744:0:0'),
      newPath: utf8.encode('releases/app.aab'),
    );
    await tester.pumpWidget(
      _host(
        DiffView(
          itemCount: 1,
          rowAt: (_) => row,
          hunkIndices: const {},
          fallbackIndices: const {0},
          layout: DiffViewLayout.unified,
          selectedIds: const {},
          onSelectionChanged: (_) {},
        ),
        width: 220,
        height: 200,
        locale: const Locale('de'),
      ),
    );
    expect(find.text('Größe: 69 MB\nDateityp: AAB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('oversized files show size and type without selectable lines', (
    tester,
  ) async {
    final row = DiffDisplayRow(
      stableId: 'large-file',
      kind: DiffRowKind.tooLarge,
      text: utf8.encode('72351744:0:0'),
      newPath: utf8.encode('releases/app.apk'),
    );
    await tester.pumpWidget(
      _host(
        DiffView(
          itemCount: 1,
          rowAt: (_) => row,
          hunkIndices: const {},
          fallbackIndices: const {0},
          layout: DiffViewLayout.unified,
          selectedIds: const {},
          onSelectionChanged: (_) {},
        ),
        height: 300,
      ),
    );
    expect(
      find.text(
        'File exceeds the 8 MiB preview limit. Only file information is shown.',
      ),
      findsOneWidget,
    );
    expect(find.text('Size: 69 MB\nFile type: APK'), findsOneWidget);
    expect(isDiffLineRow(row), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a binary file offers to show it as text when the pane can', (
    tester,
  ) async {
    final row = DiffDisplayRow(
      stableId: 'binary-file',
      kind: DiffRowKind.binary,
      text: utf8.encode('2048'),
      newPath: utf8.encode('data/table.dat'),
    );
    var shown = 0;
    Widget view({VoidCallback? onShowAsText}) => _host(
      DiffView(
        itemCount: 1,
        rowAt: (_) => row,
        hunkIndices: const {},
        fallbackIndices: const {0},
        layout: DiffViewLayout.unified,
        selectedIds: const {},
        onSelectionChanged: (_) {},
        onShowAsText: onShowAsText,
      ),
      height: 300,
    );
    await tester.pumpWidget(view());
    expect(
      find.text('Binary content — text comparison is unavailable'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('diff-show-as-text')), findsNothing);

    await tester.pumpWidget(view(onShowAsText: () => shown += 1));
    await tester.tap(find.text('Show as text'));
    expect(shown, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NM-43 file headers collapse and restore only their own rows', (
    tester,
  ) async {
    final rows = [
      const DiffDisplayRow(
        stableId: 'file-a',
        kind: DiffRowKind.file,
        text: [97, 46, 116, 120, 116],
        sectionEnd: 3,
      ),
      const DiffDisplayRow(
        stableId: 'hunk-a',
        kind: DiffRowKind.hunk,
        text: [64, 64, 32, 45, 49, 32, 43, 49, 32, 64, 64],
      ),
      const DiffDisplayRow(
        stableId: 'line-a',
        kind: DiffRowKind.addition,
        text: [97],
      ),
      const DiffDisplayRow(
        stableId: 'file-b',
        kind: DiffRowKind.file,
        text: [98, 46, 116, 120, 116],
        sectionEnd: 6,
      ),
      const DiffDisplayRow(
        stableId: 'hunk-b',
        kind: DiffRowKind.hunk,
        text: [64, 64, 32, 45, 49, 32, 43, 49, 32, 64, 64],
      ),
      const DiffDisplayRow(
        stableId: 'line-b',
        kind: DiffRowKind.addition,
        text: [98],
      ),
    ];
    await tester.pumpWidget(
      _host(
        DiffView(
          itemCount: rows.length,
          rowAt: (index) => rows[index],
          fileSections: {0: rows[0], 3: rows[3]},
          collapsibleFiles: true,
          layout: DiffViewLayout.unified,
          selectedIds: const {},
          onSelectionChanged: (_) {},
        ),
        height: 300,
      ),
    );
    expect(find.byKey(const ValueKey('diff-row-line-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('diff-row-line-b')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diff-file-toggle-file-a')));
    await tester.pump();
    expect(find.byKey(const ValueKey('diff-row-line-a')), findsNothing);
    expect(find.byKey(const ValueKey('diff-row-line-b')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diff-file-toggle-file-a')));
    await tester.pump(MeridianDurations.quick);
    expect(find.byKey(const ValueKey('diff-row-line-a')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a replacing view tolerates the controller it shares', (
    tester,
  ) async {
    // The commit pane keys the view by request and keeps one controller. The
    // replaced view releases its position only after the frame that mounts
    // its replacement.
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Widget view(String key) => _host(
      DiffView(
        key: ValueKey(key),
        itemCount: _hunkRows.length,
        rowAt: (index) => _hunkRows[index],
        hunkIndices: const {0},
        controller: scroll,
        layout: DiffViewLayout.unified,
        selectedIds: const {},
        onSelectionChanged: (_) {},
      ),
    );
    await tester.pumpWidget(view('first'));
    await tester.pumpWidget(view('second'));
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(scroll.positions, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('NM-43 a large collapsed file keeps row builds bounded', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var calls = 0;
    const first = DiffDisplayRow(
      stableId: 'file-large',
      kind: DiffRowKind.file,
      text: [108, 97, 114, 103, 101],
      sectionEnd: 50000,
    );
    const second = DiffDisplayRow(
      stableId: 'file-next',
      kind: DiffRowKind.file,
      text: [110, 101, 120, 116],
      sectionEnd: 100000,
    );
    DiffDisplayRow rowAt(int index) {
      calls += 1;
      if (index == 0) return first;
      if (index == 50000) return second;
      return DiffDisplayRow(
        stableId: 'line-$index',
        kind: DiffRowKind.context,
        text: const [120],
      );
    }

    await tester.pumpWidget(
      _host(
        DiffView(
          itemCount: 100000,
          rowAt: rowAt,
          fileSections: const {0: first, 50000: second},
          collapsibleFiles: true,
          controller: scroll,
          layout: DiffViewLayout.unified,
          selectedIds: const {},
          onSelectionChanged: (_) {},
        ),
        height: 300,
      ),
    );
    calls = 0;
    await tester.tap(find.byKey(const ValueKey('diff-file-toggle-file-large')));
    await tester.pump();
    expect(find.byKey(const ValueKey('diff-row-file-next')), findsOneWidget);
    expect(calls, lessThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'NM-42 hunk context control triggers reload and reveals new line',
    (tester) async {
      var calls = 0;
      final rows = [
        _hunkRows.first,
        const DiffDisplayRow(
          stableId: 'new-context',
          kind: DiffRowKind.context,
          text: [110, 101, 119],
        ),
      ];
      await tester.pumpWidget(
        _host(
          DiffView(
            itemCount: rows.length,
            rowAt: (index) => rows[index],
            hunkIndices: const {0},
            layout: DiffViewLayout.unified,
            selectedIds: const {},
            onSelectionChanged: (_) {},
            onShowMoreContext: () => calls += 1,
            revealContextIds: const {'new-context'},
          ),
        ),
      );
      expect(find.byType(MeridianReveal), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('diff-more-hunk')));
      expect(calls, 1);
    },
  );
  testWidgets('NM-42 reduced motion shows expanded context immediately', (
    tester,
  ) async {
    const row = DiffDisplayRow(
      stableId: 'new-context',
      kind: DiffRowKind.context,
      text: [110, 101, 119],
    );
    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: DiffView(
            itemCount: 1,
            rowAt: (_) => row,
            layout: DiffViewLayout.unified,
            selectedIds: const {},
            onSelectionChanged: (_) {},
            revealContextIds: const {'new-context'},
          ),
        ),
      ),
    );
    expect(find.byType(MeridianReveal), findsOneWidget);
    expect(find.text('new'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a mouse drag selects the lines it touches, context too', (
    tester,
  ) async {
    var selected = <String>{};
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => DiffView(
              itemCount: 100,
              controller: scroll,
              rowAt: (index) => DiffDisplayRow(
                stableId: 'row-$index',
                kind: index == 1 ? DiffRowKind.context : DiffRowKind.addition,
                text: utf8.encode('line $index'),
                selectable: index != 1,
              ),
              layout: DiffViewLayout.unified,
              selectedIds: selected,
              onSelectionChanged: (value) => update(() => selected = value),
            ),
          ),
        ),
      ),
    );
    final start =
        tester.getTopLeft(find.byKey(const ValueKey('diff-row-row-0'))) +
        const Offset(130, 10);
    final mouse = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(start + const Offset(80, 60));
    await tester.pump();
    await mouse.up();
    await tester.pump();
    expect(selected, {'row-0', 'row-1', 'row-2', 'row-3'});
    expect(
      scroll.offset,
      0,
      reason: 'Mouse text selection must not also drag the scrollable.',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const ValueKey('diff-row-row-5')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(selected, {'row-0', 'row-1', 'row-2', 'row-3', 'row-4', 'row-5'});
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(selected, isEmpty);
    await tester.fling(find.byType(DiffView), const Offset(0, -250), 1000);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      scroll.offset,
      greaterThan(0),
      reason: 'Touch scrolling remains owned by Scrollable.',
    );
  });

  testWidgets(
    'virtualizes 100k unified and split rows and styles only live rows',
    (tester) async {
      final controller = ScrollController();
      var builds = 0;
      var syntaxCalls = 0;
      Set<String> selected = {};
      DiffDisplayRow rowAt(int index) {
        builds += 1;
        return DiffDisplayRow(
          stableId: 'line-$index',
          kind: index.isEven ? DiffRowKind.addition : DiffRowKind.deletion,
          text: utf8.encode('line $index ${'x' * 20000}'),
          oldLine: index,
          newLine: index,
          selectable: true,
          textTruncated: true,
        );
      }

      Widget app(DiffViewLayout layout) => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            height: 400,
            width: 900,
            child: DiffView(
              itemCount: 100000,
              rowAt: rowAt,
              layout: layout,
              selectedIds: selected,
              controller: controller,
              textStyler: (_, row) {
                syntaxCalls += 1;
                return TextSpan(text: utf8.decode(row.text));
              },
              onSelectionChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      );

      await tester.pumpWidget(app(DiffViewLayout.unified));
      expect(builds, lessThan(100));
      expect(syntaxCalls, lessThan(100));
      await _click(tester, _gutter(tester, 'line-0'));
      expect(selected, {'line-0'});

      builds = 0;
      syntaxCalls = 0;
      controller.jumpTo(50000 * 18);
      await tester.pump();
      expect(builds, lessThan(100));
      expect(syntaxCalls, lessThan(100));
      expect(find.textContaining('line 50000'), findsWidgets);

      await tester.pumpWidget(app(DiffViewLayout.sideBySide));
      await tester.pump();
      expect(builds, lessThan(150));
    },
  );

  test('latest request wins rapid selection races', () {
    final guard = DiffRequestGuard();
    final old = guard.begin();
    final current = guard.begin();
    expect(guard.accepts(old), isFalse);
    expect(guard.accepts(current), isTrue);
  });

  testWidgets('renders dual gutters, bounded syntax and intraline spans', (
    tester,
  ) async {
    final row = DiffDisplayRow(
      stableId: 'native-line',
      kind: DiffRowKind.addition,
      text: utf8.encode('final value = "changed";'),
      oldLine: 7,
      newLine: 8,
      selectable: true,
      syntax: 'dart'.codeUnits,
      intraLine: const [DiffSpan(6, 11)],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SizedBox(
          width: 420,
          height: 120,
          child: DiffView(
            itemCount: 1,
            rowAt: (_) => row,
            layout: DiffViewLayout.unified,
            selectedIds: const {},
            onSelectionChanged: (_) {},
            wrap: true,
          ),
        ),
      ),
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
    expect(find.byKey(const ValueKey('diff-row-native-line')), findsOneWidget);
    final marks = tester.widget<DiffLineMarks>(
      find.ancestor(
        of: find.byKey(const ValueKey('diff-content-native-line-new')),
        matching: find.byType(DiffLineMarks),
      ),
    );
    expect(marks.marks, [const TextRange(start: 6, end: 11)]);
    expect(marks.markColor, GitLamaGitColors.light.addedStrong);
    expect(marks.selection, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('intra-line marks are offsets into the decoded text', (
    tester,
  ) async {
    final row = DiffDisplayRow(
      stableId: 'accented',
      kind: DiffRowKind.addition,
      text: utf8.encode('café value'),
      newLine: 1,
      selectable: true,
      // Bytes 6..11: "value" after the two-byte é.
      intraLine: const [DiffSpan(6, 11)],
    );
    await tester.pumpWidget(
      _host(
        DiffView(
          itemCount: 1,
          rowAt: (_) => row,
          layout: DiffViewLayout.unified,
          selectedIds: const {},
          onSelectionChanged: (_) {},
        ),
      ),
    );
    expect(tester.widget<DiffLineMarks>(find.byType(DiffLineMarks)).marks, [
      const TextRange(start: 5, end: 10),
    ]);
    expect(find.text('café value'), findsOneWidget);
  });

  testWidgets('invalid UTF-8 fails explicitly and can use Latin-1 fallback', (
    tester,
  ) async {
    const row = DiffDisplayRow(
      stableId: 'encoded-line',
      kind: DiffRowKind.context,
      text: [0x63, 0x61, 0x66, 0xe9],
    );
    Widget app(DiffTextEncoding encoding) => MaterialApp(
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SizedBox(
        width: 420,
        height: 120,
        child: DiffView(
          itemCount: 1,
          rowAt: (_) => row,
          fallbackIndices: encoding == DiffTextEncoding.utf8
              ? const {0}
              : const {},
          layout: DiffViewLayout.unified,
          selectedIds: const {},
          onSelectionChanged: (_) {},
          encoding: encoding,
        ),
      ),
    );

    await tester.pumpWidget(app(DiffTextEncoding.utf8));
    expect(find.text('Not valid UTF-8 — choose an encoding'), findsOneWidget);
    expect(find.text('caf�'), findsNothing);
    await tester.pumpWidget(app(DiffTextEncoding.latin1));
    expect(find.text('café'), findsOneWidget);
  });

  testWidgets('long lines scroll horizontally under fixed gutters', (
    tester,
  ) async {
    Widget view({required bool wrap}) => _host(
      DiffView(
        itemCount: _hunkRows.length,
        rowAt: (index) => _hunkRows[index],
        loadedRows: _hunkRows,
        hunkIndices: const {0},
        layout: DiffViewLayout.unified,
        selectedIds: const {},
        onSelectionChanged: (_) {},
        wrap: wrap,
      ),
    );
    await tester.pumpWidget(view(wrap: false));
    final horizontal = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right,
    );
    expect(horizontal, findsOneWidget);
    final position = tester.state<ScrollableState>(horizontal).position;
    expect(position.maxScrollExtent, greaterThan(0));
    final text = find.byKey(const ValueKey('diff-content-added-new'));
    final gutter = find.text('2').last;
    final textBefore = tester.getTopLeft(text).dx;
    final gutterBefore = tester.getTopLeft(gutter).dx;
    final hunkBefore = tester.getTopLeft(find.text('main')).dx;

    position.jumpTo(100);
    await tester.pump();
    expect(tester.getTopLeft(text).dx, textBefore - 100);
    expect(tester.getTopLeft(gutter).dx, gutterBefore);
    expect(tester.getTopLeft(find.text('main')).dx, hunkBefore);

    // The whole line is reachable.
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    final viewRight = tester.getTopRight(find.byType(DiffView)).dx;
    expect(tester.getTopRight(text).dx, lessThanOrEqualTo(viewRight));

    await tester.pumpWidget(view(wrap: true));
    expect(horizontal, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a drag selects text and implicitly the lines it touches', (
    tester,
  ) async {
    final copies = _captureClipboard(tester);
    var selected = <String>{};
    await tester.pumpWidget(
      _selectableHunk(
        selected: () => selected,
        onChanged: (value) => selected = value,
      ),
    );
    await _drag(
      tester,
      _charAt(tester, 'removed', 2),
      _charAt(tester, 'added', 3),
    );
    expect(selected, {'removed', 'added'});
    expect(
      tester
          .widget<DiffLineMarks>(
            find.ancestor(
              of: find.byKey(const ValueKey('diff-content-removed-new')),
              matching: find.byType(DiffLineMarks),
            ),
          )
          .selection,
      const TextRange(start: 2, end: 8),
    );
    expect(
      find.byKey(const ValueKey('diff-selection-frame-removed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('diff-selection-frame-context-1')),
      findsNothing,
    );
    await _copyShortcut(tester);
    expect(copies, ['d line\nnew']);
    expect(find.text('Selection copied.'), findsOneWidget);

    // Ending at the start of a line leaves that line out.
    await _drag(
      tester,
      _charAt(tester, 'context-1', 0),
      _charAt(tester, 'removed', 0),
    );
    expect(selected, {'context-1'});

    // Shift-click moves the selection's free end.
    await _click(tester, _charAt(tester, 'added', 1), shift: true);
    expect(selected, {'context-1', 'removed', 'added'});

    // A plain click only places the caret.
    await _click(tester, _charAt(tester, 'context-2', 2));
    expect(selected, isEmpty);

    await _click(tester, _charAt(tester, 'removed', 4));
    await _click(tester, _charAt(tester, 'added', 2), shift: true);
    expect(selected, {'removed', 'added'});
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(selected, isEmpty);
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets(
    'double-click selects a word; triple-click and the gutter lines',
    (tester) async {
      final copies = _captureClipboard(tester);
      var selected = <String>{};
      await tester.pumpWidget(
        _selectableHunk(
          selected: () => selected,
          onChanged: (value) => selected = value,
        ),
      );
      final word = _charAt(tester, 'added', 1);
      await _click(tester, word);
      await _click(tester, word);
      expect(selected, {'added'});
      await _copyShortcut(tester);
      expect(copies.last, 'new');

      await _click(tester, word);
      await _copyShortcut(tester);
      expect(copies.last, 'new line ${'x' * 200}');

      await _click(tester, _gutter(tester, 'context-1'));
      expect(selected, {'context-1'});
      await _click(tester, _gutter(tester, 'removed'), shift: true);
      expect(selected, {'context-1', 'removed'});
      await _copyShortcut(tester);
      expect(copies.last, 'keep\nold line');

      // Dragging down the gutter selects whole lines.
      await _drag(tester, _gutter(tester, 'removed'), _gutter(tester, 'added'));
      expect(selected, {'removed', 'added'});
      await tester.pump(const Duration(seconds: 9));
    },
  );

  testWidgets('wrapped lines map pointer positions to their text', (
    tester,
  ) async {
    var selected = <String>{};
    await tester.pumpWidget(
      _selectableHunk(
        selected: () => selected,
        onChanged: (value) => selected = value,
        wrap: true,
      ),
    );
    await _drag(
      tester,
      _charAt(tester, 'context-1', 1),
      _charAt(tester, 'added', 150),
    );
    expect(selected, {'context-1', 'removed', 'added'});
    expect(
      tester
          .widget<DiffLineMarks>(
            find.ancestor(
              of: find.byKey(const ValueKey('diff-content-added-new')),
              matching: find.byType(DiffLineMarks),
            ),
          )
          .selection,
      const TextRange(start: 0, end: 150),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection actions float on the selected lines', (tester) async {
    var selected = <String>{};
    List<String>? staged;
    late StateSetter setOwner;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, update) {
            setOwner = update;
            return DiffView(
              itemCount: _hunkRows.length,
              rowAt: (index) => _hunkRows[index],
              hunkIndices: const {0},
              layout: DiffViewLayout.unified,
              selectedIds: selected,
              onSelectionChanged: (value) => update(() => selected = value),
              selectionActions: (ids) => MeridianButton(
                label: 'Stage',
                size: MeridianControlSize.small,
                onPressed: () => staged = ids,
              ),
            );
          },
        ),
      ),
    );
    final actions = find.byKey(const ValueKey('diff-selection-actions'));
    expect(actions, findsNothing);

    await _drag(
      tester,
      _charAt(tester, 'removed', 2),
      _charAt(tester, 'added', 3),
    );
    expect(actions, findsOneWidget);
    final firstLine = tester.getRect(
      find.byKey(const ValueKey('diff-row-removed')),
    );
    final bounds = tester.getRect(actions);
    expect(bounds.top, closeTo(firstLine.top, MeridianSpace.space2));
    expect(bounds.right, lessThan(firstLine.right));

    // Pressing an action keeps the selection it acts on.
    await tester.tap(find.text('Stage'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(staged, ['removed', 'added']);
    expect(selected, {'removed', 'added'});

    // The owner replacing the selection drops the text range too.
    setOwner(() => selected = {});
    await tester.pump();
    expect(actions, findsNothing);
    expect(
      tester
          .widgetList<DiffLineMarks>(find.byType(DiffLineMarks))
          .every((marks) => marks.selection == null),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hunk header selects its lines; the keyboard copies them', (
    tester,
  ) async {
    final copies = _captureClipboard(tester);
    var selected = <String>{};
    await tester.pumpWidget(
      _selectableHunk(
        selected: () => selected,
        onChanged: (value) => selected = value,
      ),
    );
    await tester.tap(find.text('main'));
    await tester.pump();
    expect(selected, {'context-1', 'removed', 'added', 'context-2'});

    await _click(tester, _gutter(tester, 'removed'));
    await _click(tester, _gutter(tester, 'added'), shift: true);
    expect(selected, {'removed', 'added'});

    await _copyShortcut(tester);
    expect(copies, ['old line\nnew line ${'x' * 200}']);
    expect(find.text('Selection copied.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('the context menu selects the clicked line and copies a patch', (
    tester,
  ) async {
    final copies = _captureClipboard(tester);
    final previousPresenter = nativeMenuTestPresenter;
    final shown = <Menu>[];
    nativeMenuTestPresenter = (_, menu, _) async {
      shown.add(menu);
      return MenuResult(itemSelected: false);
    };
    addTearDown(() => nativeMenuTestPresenter = previousPresenter);
    var selected = <String>{};
    List<String>? patchRows;
    var staged = <String>[];
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, update) => DiffView(
            itemCount: _hunkRows.length,
            rowAt: (index) => _hunkRows[index],
            hunkIndices: const {0},
            layout: DiffViewLayout.unified,
            selectedIds: selected,
            onSelectionChanged: (value) => update(() => selected = value),
            menuItems: (ids) => [
              NativeMenuAction(value: () => staged = ids, title: 'Stage'),
            ],
            onCopyPatch: (ids) async {
              patchRows = ids;
              return utf8.encode('+new line\n');
            },
          ),
        ),
      ),
    );

    List<String?> titles() => [
      for (final item in shown.last.children)
        item is MenuAction ? item.title : '-',
    ];
    MenuAction action(String title) => shown.last.children
        .whereType<MenuAction>()
        .firstWhere((item) => item.title == title);

    await tester.tap(
      find.byKey(const ValueKey('diff-row-context-1')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(selected, {'context-1'});
    expect(titles(), ['Stage', '-', 'Copy', 'Copy as Patch']);
    expect(action('Copy as Patch').attributes.disabled, isTrue);

    await _drag(
      tester,
      _charAt(tester, 'removed', 1),
      _charAt(tester, 'added', 5),
    );
    // Right-clicking inside the selection keeps it.
    await tester.tap(
      find.byKey(const ValueKey('diff-row-added')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(selected, {'removed', 'added'});
    expect(action('Copy as Patch').attributes.disabled, isFalse);
    action('Stage').callback();
    expect(staged, ['removed', 'added']);
    action('Copy').callback();
    await tester.pumpAndSettle();
    expect(copies, ['ld line\nnew l']);
    action('Copy as Patch').callback();
    await tester.pumpAndSettle();
    expect(patchRows, ['removed', 'added']);
    expect(copies.last, '+new line\n');
    expect(find.text('Patch copied.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
  });
}
