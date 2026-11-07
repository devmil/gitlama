import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/file_actions/file_actions.dart';
import 'package:gitlama/app/inspector/inspector_actions.dart';
import 'package:gitlama/app/inspector/inspector_host.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/inspection.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/repositories/inspection_repository.dart';
import 'package:gitlama/services/inspector/inspector_service.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/widgets/native_menu.dart';

const _commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// An inspector host whose working tree holds only [present].
final class _Host extends InspectorHost {
  _Host(this.present);

  final Set<String> present;
  final List<String> asked = [];

  @override
  bool get isWindow => false;
  @override
  bool get supportsWindows => false;
  @override
  Future<void> openInWindow(InspectorLocation location) async {}
  @override
  Future<bool> showInGraph(InspectorTarget target) async => true;
  @override
  String get inspectionOpenIn => 'pane';
  @override
  RepositorySessionService? get repositories => null;
  @override
  bool get canOpenWorkingCopy => true;
  @override
  void openWorkingCopy(List<int> path, {required bool reveal}) {}
  @override
  String get fileBrowserName => 'Files';
  @override
  bool get canCreatePatch => false;
  @override
  void createPatch(InspectorTarget target, List<List<int>> paths) {}
  @override
  bool get canRestore => false;

  @override
  Future<bool> existsInWorkingTree(List<int> path) async {
    final text = String.fromCharCodes(path);
    asked.add(text);
    return present.contains(text);
  }
}

final class _NoReads implements InspectionRepository {
  @override
  Never noSuchMethod(Invocation invocation) => throw StateError('no_reads');
}

CommitFileChange _file(String path) => CommitFileChange(
  oldMode: 0x81a4,
  newMode: 0x81a4,
  kind: CommitFileChangeKind.modified,
  oldPath: path.codeUnits,
  newPath: path.codeUnits,
);

void main() {
  Future<List<String>> menuOf(
    WidgetTester tester,
    _Host host,
    FileActionSubject Function() subject,
  ) async {
    late Widget menu;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => menu = fileActionContextMenu(
            context: context,
            subject: subject,
            host: InspectorFileActions(
              context: () => context,
              service: InspectorService(_NoReads()),
              host: host,
            ),
            child: const SizedBox(),
          ),
        ),
      ),
    );
    final items = await (menu as GitLamaContextMenuWidget).menuItems(
      Offset.zero,
    );
    return [
      for (final item in items ?? const <NativeMenuAction>[])
        if (!item.separator && !item.header) item.title,
    ];
  }

  // Likely defect #8 of the 2026-10-11 review: inspector subjects claimed
  // every path exists in the working tree.
  testWidgets('a changed file missing locally offers no local file actions', (
    tester,
  ) async {
    final host = _Host({'present.txt'});
    final missing = await menuOf(
      tester,
      host,
      () => changedFileSubject(_file('gone.txt'), const CommitTarget(_commit)),
    );
    expect(missing, isNot(contains('Open in external editor')));
    expect(missing, isNot(contains('Open in Files')));
    expect(missing, contains('Copy path'));
    expect(host.asked, ['gone.txt']);

    final present = await menuOf(
      tester,
      host,
      () =>
          changedFileSubject(_file('present.txt'), const CommitTarget(_commit)),
    );
    expect(present, contains('Open in external editor'));
    expect(present, contains('Open in Files'));
  });

  testWidgets('a tree file that exists locally keeps its local actions', (
    tester,
  ) async {
    final host = _Host({'present.txt'});
    final items = await menuOf(
      tester,
      host,
      () => FileActionSubject(
        source: FileActionSource.treeFile,
        path: 'present.txt'.codeUnits,
        revision: _commit,
      ),
    );
    expect(items, contains('Open in external editor'));
    expect(host.asked, ['present.txt']);
  });
}
