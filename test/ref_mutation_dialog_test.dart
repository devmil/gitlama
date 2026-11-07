import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/ref_mutation_dialog.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/widgets/gitlama_list_well.dart';

const _topic = '1111111111111111111111111111111111111111';

RepositoryRefs _refs({bool upstreamGone = false, bool fetched = true}) =>
    RepositoryRefs(
      branches: [
        RepositoryReference(
          name: 'feat/login'.codeUnits,
          target: _topic,
          upstream: 'refs/remotes/team/fork/feat/login'.codeUnits,
          upstreamGone: upstreamGone,
        ),
        RepositoryReference(name: 'local-only'.codeUnits, target: _topic),
      ],
      remotes: [
        RepositoryRemote(
          name: 'team'.codeUnits,
          displayUrl: 'example.test/team'.codeUnits,
        ),
        RepositoryRemote(
          name: 'team/fork'.codeUnits,
          displayUrl: 'example.test/fork'.codeUnits,
          branches: [
            if (fetched)
              RepositoryReference(name: 'feat/login'.codeUnits, target: _topic),
          ],
        ),
      ],
    );

Future<RefMutationRequest?> _delete(
  WidgetTester tester, {
  required String name,
  RepositoryRefs? refs,
  bool tickUpstream = false,
}) async {
  RefMutationRequest? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Center(
          child: MeridianButton(
            label: 'Open',
            onPressed: () async {
              result = await showMeridianDialog<RefMutationRequest>(
                context: context,
                builder: (context) => RefMutationInputDialog(
                  kind: RefMutationKind.deleteBranch,
                  initialName: name,
                  initialTarget: null,
                  references: refs ?? _refs(),
                  choices: const [],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  final upstream = find.byKey(const ValueKey('delete-branch-upstream'));
  if (tickUpstream) {
    await tester.tap(upstream);
    await tester.pump();
  }
  await tester.tap(find.widgetWithText(MeridianButton, 'Delete branch'));
  await tester.pumpAndSettle();
  return result;
}

/// Opens Edit remote for "origin" with [displayUrl], optionally types [url],
/// and taps the primary action. Returns the request, or null while the dialog stays.
Future<RefMutationRequest?> _editRemote(
  WidgetTester tester, {
  required String displayUrl,
  String? url,
}) async {
  RefMutationRequest? result;
  final refs = RepositoryRefs(
    remotes: [
      RepositoryRemote(
        name: 'origin'.codeUnits,
        displayUrl: displayUrl.codeUnits,
      ),
    ],
  );
  // A fresh tree drops a dialog an earlier call left open.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Center(
          child: MeridianButton(
            label: 'Open',
            onPressed: () async {
              result = await showMeridianDialog<RefMutationRequest>(
                context: context,
                builder: (context) => RefMutationInputDialog(
                  kind: RefMutationKind.editRemote,
                  initialName: 'origin',
                  initialTarget: null,
                  references: refs,
                  choices: const [],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  if (url != null) {
    await tester.enterText(_urlField, url);
    await tester.pump();
  }
  await tester.tap(find.widgetWithText(MeridianButton, 'Change remote URL'));
  await tester.pumpAndSettle();
  return result;
}

/// Opens Rename remote for "origin", types [newName] when given and taps
/// the primary action. Returns the request, or null while the dialog stays.
Future<RefMutationRequest?> _renameRemote(
  WidgetTester tester, {
  String? newName,
}) async {
  RefMutationRequest? result;
  final refs = RepositoryRefs(
    remotes: [
      RepositoryRemote(
        name: 'origin'.codeUnits,
        displayUrl: 'example.test/origin'.codeUnits,
      ),
      RepositoryRemote(
        name: 'upstream'.codeUnits,
        displayUrl: 'example.test/upstream'.codeUnits,
      ),
    ],
  );
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Center(
          child: MeridianButton(
            label: 'Open',
            onPressed: () async {
              result = await showMeridianDialog<RefMutationRequest>(
                context: context,
                builder: (context) => RefMutationInputDialog(
                  kind: RefMutationKind.renameRemote,
                  initialName: 'origin',
                  initialTarget: null,
                  references: refs,
                  choices: const [],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  if (newName != null) {
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('ref-mutation-new-name')),
        matching: find.byType(EditableText),
      ),
      newName,
    );
    await tester.pump();
  }
  await tester.tap(find.widgetWithText(MeridianButton, 'Rename remote'));
  await tester.pumpAndSettle();
  return result;
}

final _urlField = find.descendant(
  of: find.widgetWithText(MeridianTextField, 'Remote URL'),
  matching: find.byType(EditableText),
);

void main() {
  testWidgets('offers the fetched upstream and names its remote exactly', (
    tester,
  ) async {
    final request = await _delete(
      tester,
      name: 'feat/login',
      tickUpstream: true,
    );
    // "team/fork" wins over its prefix "team".
    expect(request?.deleteUpstream?.remote, 'team/fork');
    expect(request?.deleteUpstream?.branch, 'feat/login');
  });

  testWidgets('keeps the upstream unless it is ticked', (tester) async {
    final request = await _delete(tester, name: 'feat/login');
    expect(request?.name, 'feat/login');
    expect(request?.deleteUpstream, isNull);
  });

  testWidgets('offers nothing without a live, fetched upstream', (
    tester,
  ) async {
    for (final refs in [_refs(upstreamGone: true), _refs(fetched: false)]) {
      final request = await _delete(tester, name: 'feat/login', refs: refs);
      expect(
        find.byKey(const ValueKey('delete-branch-upstream')),
        findsNothing,
      );
      expect(request?.deleteUpstream, isNull);
    }
    await _delete(tester, name: 'local-only');
    expect(find.byKey(const ValueKey('delete-branch-upstream')), findsNothing);
  });

  testWidgets('lines its options up with the name field', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Center(
          child: RefMutationInputDialog(
            kind: RefMutationKind.deleteBranch,
            initialName: 'feat/login',
            initialTarget: null,
            references: _refs(),
            choices: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The field's label marks the content's leading edge.
    final start = tester.getRect(find.text('Name')).left;
    final checkboxes = find.byType(MeridianCheckbox);
    expect(checkboxes, findsNWidgets(2));
    for (var index = 0; index < 2; index++) {
      expect(tester.getRect(checkboxes.at(index)).left, closeTo(start, 1));
    }
  });

  testWidgets('edits a visible remote URL and requires a change', (
    tester,
  ) async {
    const current = 'git@github.com:devmil/repo.git';
    expect(await _editRemote(tester, displayUrl: current), isNull);
    expect(tester.widget<EditableText>(_urlField).controller.text, current);
    final request = await _editRemote(
      tester,
      displayUrl: current,
      url: 'git@github.com:devmil/other.git',
    );
    expect(request?.url, 'git@github.com:devmil/other.git');
  });

  testWidgets('renames a remote to a free name and keeps its name fixed', (
    tester,
  ) async {
    // The unchanged name and another remote's name are refused.
    expect(await _renameRemote(tester), isNull);
    expect(
      tester
          .widget<MeridianTextField>(
            find.byKey(const ValueKey('ref-mutation-fixed-name')),
          )
          .readOnly,
      isTrue,
    );
    expect(await _renameRemote(tester, newName: 'upstream'), isNull);
    final request = await _renameRemote(tester, newName: 'fork');
    expect(request?.kind, RefMutationKind.renameRemote);
    expect(request?.name, 'origin');
    expect(request?.secondName, 'fork');
  });

  testWidgets('changing a remote URL shows the remote name read-only', (
    tester,
  ) async {
    await _editRemote(tester, displayUrl: 'example.test/repo');
    expect(
      tester
          .widget<MeridianTextField>(
            find.byKey(const ValueKey('ref-mutation-fixed-name')),
          )
          .readOnly,
      isTrue,
    );
  });

  testWidgets('never offers a URL with hidden credentials as the value', (
    tester,
  ) async {
    const hidden = 'https://[REDACTED]@example.test/repo.git';
    expect(await _editRemote(tester, displayUrl: hidden), isNull);
    expect(tester.widget<EditableText>(_urlField).controller.text, isEmpty);
    expect(
      find.text(
        'The current URL contains credentials and is not shown. '
        'Enter the complete new URL.',
      ),
      findsOneWidget,
    );
    expect(await _editRemote(tester, displayUrl: hidden, url: hidden), isNull);
    final request = await _editRemote(
      tester,
      displayUrl: hidden,
      url: 'https://example.test/repo.git',
    );
    expect(request?.url, 'https://example.test/repo.git');
  });

  testWidgets(
    'reselection retains branch input and explicitly labels the start',
    (tester) async {
      const previous = RefMutationRequest(
        kind: RefMutationKind.createBranch,
        name: 'release/v2',
        target: 'missing-commit',
        checkout: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RefMutationInputDialog(
              kind: RefMutationKind.createBranch,
              initialName: null,
              initialTarget: 'replacement-must-not-be-used',
              previousRequest: previous,
              references: _refs(),
              choices: const [],
            ),
          ),
        ),
      );
      expect(find.text('release/v2'), findsOneWidget);
      expect(find.text('missing-commit'), findsOneWidget);
      expect(find.text('Starting point'), findsOneWidget);
      expect(find.text('replacement-must-not-be-used'), findsNothing);
      final checkbox = tester.widget<MeridianCheckbox>(
        find.byKey(const ValueKey('create-branch-checkout')),
      );
      expect(checkbox.value, isFalse);
    },
  );

  testWidgets('Enter in the name field submits Create branch when valid', (
    tester,
  ) async {
    RefMutationRequest? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Center(
            child: MeridianButton(
              label: 'Open',
              onPressed: () async {
                result = await showMeridianDialog<RefMutationRequest>(
                  context: context,
                  builder: (context) => RefMutationInputDialog(
                    kind: RefMutationKind.createBranch,
                    initialName: null,
                    initialTarget: 'main',
                    references: _refs(),
                    choices: const [],
                  ),
                );
                closed = true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final name = find
        .descendant(
          of: find.widgetWithText(MeridianTextField, 'Name'),
          matching: find.byType(EditableText),
        )
        .first;

    // An empty name keeps the dialog open: Enter is rejected.
    await tester.showKeyboard(name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(find.byType(RefMutationInputDialog), findsOne);

    await tester.enterText(name, 'topic');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result?.kind, RefMutationKind.createBranch);
    expect(result?.name, 'topic');
    expect(result?.target, 'main');
  });

  testWidgets('deleting a tag offers its remotes as a bounded checklist', (
    tester,
  ) async {
    RefMutationRequest? result;
    final refs = RepositoryRefs(
      tags: [RepositoryReference(name: 'v1.0'.codeUnits, target: _topic)],
      remotes: [
        for (final name in ['origin', 'mirror', 'backup'])
          RepositoryRemote(
            name: name.codeUnits,
            displayUrl: 'example.test/$name'.codeUnits,
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Center(
            child: MeridianButton(
              label: 'Open',
              onPressed: () async {
                result = await showMeridianDialog<RefMutationRequest>(
                  context: context,
                  builder: (context) => RefMutationInputDialog(
                    kind: RefMutationKind.deleteTag,
                    initialName: 'v1.0',
                    initialTarget: null,
                    references: refs,
                    choices: const [],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('delete-tag-remotes'));
    expect(find.byType(GitLamaListWell), findsOne);
    // The label, the well and the caption share the name field's edge.
    final start = tester.getRect(find.text('Name')).left;
    expect(
      tester.getRect(find.text('Also delete from remotes')).left,
      closeTo(start, 1),
    );
    expect(tester.getRect(list).left, closeTo(start, 1));
    final rows = find.descendant(
      of: list,
      matching: find.byType(MeridianListRow),
    );
    expect(rows, findsNWidgets(3));
    expect(
      tester.widgetList<MeridianListRow>(rows).map((row) => row.checked),
      everyElement(isFalse),
    );

    await tester.tap(find.byKey(const ValueKey('delete-tag-remote-2')));
    await tester.tap(find.byKey(const ValueKey('delete-tag-remote-0')));
    await tester.pump();
    expect(
      tester
          .widget<MeridianListRow>(
            find.byKey(const ValueKey('delete-tag-remote-0')),
          )
          .checked,
      isTrue,
    );
    await tester.tap(find.widgetWithText(MeridianButton, 'Delete tag'));
    await tester.pumpAndSettle();
    expect(result?.name, 'v1.0');
    expect(result?.remoteNames, unorderedEquals(['origin', 'backup']));
  });
}
