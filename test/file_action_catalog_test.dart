import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/file_actions/file_actions.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/inspection.dart';
import 'package:gitlama/models/discard.dart';
import 'package:gitlama/widgets/native_menu.dart';

final class _Host extends FileActionHost {
  _Host(this.capabilities, {this.reason, this.actionReasons = const {}});

  @override
  final Set<FileAction> capabilities;
  final String? reason;
  final Map<FileAction, String> actionReasons;

  @override
  String? actionUnavailableReason(BuildContext context, FileAction action) =>
      actionReasons[action];

  @override
  String get fileBrowserName => 'Files';

  @override
  String? inspectionUnavailableReason(BuildContext context) => reason;

  @override
  void run(
    FileActionCommand command,
    FileActionSubject subject, {
    required bool invert,
  }) {}
}

final _all = _Host(FileAction.values.toSet());

/// Titles with '—' for separators and '#' before headers, as printed in the
/// evidence of IN04.
List<String> _render(List<NativeMenuItem<FileActionCommand>> items) => [
  for (final item in items)
    if (item.separator)
      '—'
    else if (item.header)
      '# ${item.title}'
    else
      '${item.shownTitle}${item.danger ? ' !' : ''}${item.available ? '' : ' (off)'}',
];

Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

FileActionSubject _subject(
  FileActionSource source, {
  CommitFileChangeKind? change,
  CommitTreeEntryKind? tree,
  bool exists = true,
  bool changedFolder = false,
  bool staged = false,
  bool discardable = false,
  bool untracked = false,
}) => FileActionSubject(
  source: source,
  path: 'lib/a.dart'.codeUnits,
  changeKind: change,
  treeKind: tree,
  existsInWorkingTree: exists,
  changedFolder: changedFolder,
  staged: staged,
  discardable: discardable,
  untracked: untracked,
);

void main() {
  final matrix = <String, (FileActionSubject, List<String>)>{
    'changed file of a commit': (
      _subject(
        FileActionSource.committedFile,
        change: CommitFileChangeKind.modified,
      ),
      [
        'Show diff',
        'Show contents',
        'Blame',
        'File history',
        'Open in new window',
        '—',
        'Create patch from this file',
        'Open in external diff tool',
        '—',
        'Open in external editor',
        'Open in Files',
        'Copy path',
        '—',
        'Restore this version !',
      ],
    ),
    'changed file of a comparison': (
      _subject(
        FileActionSource.comparedFile,
        change: CommitFileChangeKind.modified,
        exists: false,
      ),
      [
        'Show diff',
        'Show contents',
        'Blame',
        'File history',
        'Open in new window',
        '—',
        'Create patch from this file',
        'Open in external diff tool',
        '—',
        'Copy path',
      ],
    ),
    'unchanged file of all files': (
      _subject(FileActionSource.treeFile),
      [
        'Show contents',
        'Blame',
        'File history',
        'Open in new window',
        '—',
        'Open in external editor',
        'Open in Files',
        'Copy path',
        '—',
        'Restore this version !',
      ],
    ),
    'folder of all files': (
      _subject(FileActionSource.folder, exists: false),
      ['Folder history', 'Open in new window', '—', 'Copy path'],
    ),
    'folder of the changed tree': (
      _subject(FileActionSource.folder, changedFolder: true),
      [
        'Folder history',
        'Open in new window',
        '—',
        'Create patch',
        '—',
        'Open in Files',
        'Copy path',
      ],
    ),
    'file of a history entry': (
      _subject(
        FileActionSource.historyEntryFile,
        change: CommitFileChangeKind.added,
        exists: false,
      ),
      [
        'Show diff',
        'Show contents',
        'Blame',
        'File history',
        'Open in new window',
        '—',
        'Open in external diff tool',
        '—',
        'Copy path',
        '—',
        'Restore this version !',
      ],
    ),
    'unstaged file': (
      _subject(FileActionSource.unstagedFile, discardable: true),
      [
        'Blame (HEAD)',
        'File history (HEAD)',
        '—',
        'Stage file',
        'Inspect changes',
        '—',
        'Create patch',
        '—',
        'Open in external editor',
        'Open in Files',
        'Copy path',
        '—',
        'Add to .gitignore…',
        '—',
        'Discard changes !',
      ],
    ),
    'untracked file': (
      _subject(
        FileActionSource.unstagedFile,
        discardable: true,
        untracked: true,
      ),
      [
        'Blame (HEAD)',
        'File history (HEAD)',
        '—',
        'Stage file',
        'Inspect changes',
        '—',
        'Create patch',
        '—',
        'Open in external editor',
        'Open in Files',
        'Copy path',
        '—',
        'Add to .gitignore…',
        '—',
        'Delete untracked file !',
      ],
    ),
    'staged file': (
      _subject(FileActionSource.stagedFile, staged: true),
      [
        'Blame (HEAD)',
        'File history (HEAD)',
        '—',
        'Unstage file',
        'Inspect changes',
        '—',
        'Create patch',
        '—',
        'Open in external editor',
        'Open in Files',
        'Copy path',
      ],
    ),
    'folder of the changes': (
      _subject(FileActionSource.changesFolder, discardable: true),
      [
        'Folder history (HEAD)',
        '—',
        'Stage selected',
        '—',
        'Create patch',
        '—',
        'Open in Files',
        'Copy path',
        '—',
        'Add to .gitignore…',
        '—',
        'Discard selected !',
      ],
    ),
    'conflict file': (
      _subject(FileActionSource.conflictFile),
      [
        'Blame (HEAD)',
        'File history (HEAD)',
        '—',
        'Open in external editor',
        'Open in Files',
        'Copy path',
      ],
    ),
    'review file': (
      _subject(FileActionSource.reviewFile, exists: false),
      ['Blame', 'File history', '—', 'Copy path'],
    ),
  };

  for (final entry in matrix.entries) {
    testWidgets('menu of a ${entry.key}', (tester) async {
      final context = await _context(tester);
      final (subject, expected) = entry.value;
      final rendered = _render(buildFileActionItems(context, subject, _all));
      expect(rendered, _localized(context, expected));
    });
  }

  testWidgets('notes: deleted, binary, submodule and symlink entries', (
    tester,
  ) async {
    final context = await _context(tester);
    List<String> titles(FileActionSubject subject) =>
        _render(buildFileActionItems(context, subject, _all));
    final deleted = titles(
      _subject(
        FileActionSource.committedFile,
        change: CommitFileChangeKind.deleted,
      ),
    );
    expect(deleted, isNot(contains('Show contents')));
    expect(deleted, isNot(contains('Blame')));
    expect(deleted, isNot(contains('Restore this version !')));
    for (final kind in [
      CommitFileChangeKind.binary,
      CommitFileChangeKind.image,
      CommitFileChangeKind.submodule,
    ]) {
      final binary = titles(
        _subject(FileActionSource.committedFile, change: kind),
      );
      expect(binary, isNot(contains('Blame')), reason: kind.name);
      // The menu follows the inspector's lens rule: a submodule has no
      // contents to show; binary files and images do.
      expect(
        binary,
        kind == CommitFileChangeKind.submodule
            ? isNot(contains('Show contents'))
            : contains('Show contents'),
        reason: kind.name,
      );
    }
    expect(
      titles(
        _subject(
          FileActionSource.treeFile,
          tree: CommitTreeEntryKind.submodule,
        ),
      ),
      isNot(contains('Show contents')),
    );
    expect(
      titles(
        _subject(FileActionSource.treeFile, tree: CommitTreeEntryKind.symlink),
      ),
      isNot(contains('Blame')),
    );
  });

  testWidgets('hosts omit actions they cannot perform', (tester) async {
    final context = await _context(tester);
    final host = _Host({FileAction.copyPath, FileAction.blame});
    expect(
      _render(
        buildFileActionItems(
          context,
          _subject(
            FileActionSource.committedFile,
            change: CommitFileChangeKind.modified,
          ),
          host,
        ),
      ),
      ['Blame', '—', 'Copy path'],
    );
  });

  testWidgets('busy hosts disable mutations; unavailable inspection says why', (
    tester,
  ) async {
    final context = await _context(tester);
    final rendered = _render(
      buildFileActionItems(
        context,
        _subject(FileActionSource.unstagedFile, discardable: true),
        _Host(FileAction.values.toSet(), reason: 'No commit yet'),
        busy: true,
      ),
    );
    expect(rendered, contains('Blame (HEAD) — No commit yet (off)'));
    expect(rendered, contains('Stage file (off)'));
    expect(rendered, contains('Discard file changes ! (off)'));
    expect(rendered, contains('Copy path'));
  });

  testWidgets('an unavailable action stays listed, disabled with its reason', (
    tester,
  ) async {
    final context = await _context(tester);
    const reason = 'Not available for repositories on another computer';
    final rendered = _render(
      buildFileActionItems(
        context,
        _subject(FileActionSource.unstagedFile, discardable: true),
        // Discard is outside the capabilities but has a reason.
        _Host(
          {FileAction.stage, FileAction.copyPath},
          actionReasons: {
            FileAction.discard: reason,
            FileAction.openExternally: reason,
          },
        ),
      ),
    );
    expect(rendered, contains('Stage file'));
    expect(rendered, contains('Discard file changes — $reason ! (off)'));
    expect(rendered.where((title) => title.startsWith('Open')), hasLength(1));
    expect(
      rendered.firstWhere((title) => title.startsWith('Open')),
      endsWith('— $reason (off)'),
    );
  });

  testWidgets('a multiple selection comes first under its own header', (
    tester,
  ) async {
    final context = await _context(tester);
    final rendered = _render(
      buildFileActionItems(
        context,
        _subject(FileActionSource.stagedFile, staged: true),
        _Host({
          FileAction.unstage,
          FileAction.createPatch,
          FileAction.copyPath,
        }),
        selection: const FileActionSelection(count: 3, staged: true),
      ),
    );
    expect(rendered, [
      '# 3 selected files',
      'Unstage selected',
      'Create patch from selection',
      '—',
      '# a.dart',
      'Unstage file',
      '—',
      'Create patch from this file',
      '—',
      'Copy path',
    ]);
  });

  testWidgets(
    'selection discard and clean use their own kind and availability',
    (tester) async {
      final context = await _context(tester);
      for (final kind in [DiscardKind.discard, DiscardKind.clean, null]) {
        for (final busy in [false, true]) {
          final items = buildFileActionItems(
            context,
            _subject(FileActionSource.unstagedFile, discardable: true),
            _all,
            selection: FileActionSelection(
              count: 2,
              staged: false,
              discardKind: kind,
            ),
            busy: busy,
          );
          final destructive = items
              .where((item) => item.danger && item.value?.selection == true)
              .toList();
          if (kind == null) {
            expect(destructive, isEmpty);
          } else {
            expect(destructive, hasLength(1));
            expect(
              destructive.single.value,
              FileActionCommand(
                kind == DiscardKind.clean
                    ? FileAction.clean
                    : FileAction.discard,
                selection: true,
              ),
            );
            expect(destructive.single.available, !busy);
          }
        }
      }
      final items = buildFileActionItems(
        context,
        _subject(FileActionSource.unstagedFile, discardable: true),
        _Host({}, actionReasons: {FileAction.discard: 'Unavailable'}),
        selection: const FileActionSelection(
          count: 2,
          staged: false,
          discardKind: DiscardKind.discard,
        ),
      );
      final discard = items.singleWhere(
        (item) => item.danger && item.value?.selection == true,
      );
      expect(discard.available, isFalse);
      expect(discard.disabledReason, 'Unavailable');
    },
  );

  testWidgets('no menu starts, ends or doubles a separator', (tester) async {
    final context = await _context(tester);
    for (final source in FileActionSource.values) {
      for (final capabilities in [
        FileAction.values.toSet(),
        {FileAction.copyPath},
        {FileAction.blame, FileAction.restoreFromCommit},
      ]) {
        final items = buildFileActionItems(
          context,
          _subject(source, change: CommitFileChangeKind.modified),
          _Host(capabilities),
        );
        if (items.isEmpty) continue;
        expect(items.first.separator, isFalse, reason: source.name);
        expect(items.last.separator, isFalse, reason: source.name);
        for (var index = 1; index < items.length; index += 1) {
          expect(
            items[index].separator && items[index - 1].separator,
            isFalse,
            reason: source.name,
          );
        }
      }
    }
  });
}

/// Resolves the English labels whose wording lives in the catalogs.
List<String> _localized(BuildContext context, List<String> expected) {
  final l10n = AppLocalizations.of(context);
  return [
    for (final title in expected)
      title
          .replaceAll('Discard changes', l10n.discardFile)
          .replaceAll('Delete untracked file', l10n.cleanFile)
          .replaceAll('Discard selected', l10n.discardSelected)
          .replaceAll('Stage selected', l10n.stageSelected)
          .replaceAll('Inspect changes', l10n.inspectChanges)
          .replaceAll('Create patch from this file', l10n.patchCreateFromFile)
          .replaceAll(RegExp(r'^Create patch$'), l10n.patchCreate),
  ];
}
