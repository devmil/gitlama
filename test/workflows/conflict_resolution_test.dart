import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/conflict.dart';
import 'package:gitlama/services/conflict/conflict_merge_draft.dart';
import 'package:gitlama/models/integrations.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/workflows/conflict_resolution.dart';
import 'package:gitlama/services/workflows/workflow.dart';

import '../support/workflow_fake_repository.dart';

ConflictSide _side(String text) => ConflictSide(
  present: true,
  byteCount: text.length,
  content: utf8.encode(text),
);

ConflictFile _file(String path, {int fingerprint = 1}) => ConflictFile(
  path: utf8.encode(path),
  kind: ConflictFileKind.text,
  ancestor: _side('a\n'),
  current: _side('b\n'),
  incoming: _side('c\n'),
  resultPresent: true,
  markerFree: false,
  regions: const [],
  fingerprint: BigInt.from(fingerprint),
  canUndoResolution: false,
  result: utf8.encode('<<<<<<< ours\nb\n=======\nc\n>>>>>>> theirs\n'),
);

ConflictSnapshot _conflicts(
  List<ConflictFile> files, {
  ConflictOperationKind operation = ConflictOperationKind.merge,
  String? message,
}) => ConflictSnapshot(
  operation: operation,
  currentLabel: utf8.encode('main'),
  incomingLabel: utf8.encode('topic'),
  files: files,
  resolvedUndoPaths: const [],
  canContinue: files.isEmpty,
  canSkip: false,
  suggestedMessage: message,
);

final class _Interaction implements ConflictInteraction {
  @override
  bool active = true;
  bool confirm = true;
  IntegrationDefinition? tool;
  final List<Object> reports = [];
  final List<String> asked = [];

  @override
  Future<bool> confirmSequencer(ConflictSequencerAction action) async {
    asked.add('confirm:${action.name}');
    return confirm;
  }

  @override
  Future<IntegrationDefinition?> chooseMergeTool(
    List<IntegrationDefinition> tools,
  ) async {
    asked.add('chooseTool:${tools.length}');
    return tool;
  }

  @override
  Future<bool> confirmExternalMerge(IntegrationPreview preview) async {
    asked.add('confirmExternal');
    return confirm;
  }

  @override
  void reportConflict(ConflictOutcome outcome) => reports.add(outcome);
}

void main() {
  late WorkflowFakeRepository repository;
  late RepositorySessionService repositories;
  late ConflictResolutionService service;
  late _Interaction interaction;

  setUp(() async {
    repository = WorkflowFakeRepository(
      RepositorySnapshot(revision: BigInt.one, phase: RepositoryPhase.ready),
    );
    repositories = RepositorySessionService(repository);
    await repositories.open('/repository');
    service = ConflictResolutionService(repositories);
    interaction = _Interaction();
  });

  tearDown(() async {
    await service.dispose();
    await repositories.dispose();
  });

  test('a merge takes its message once, without comment lines', () async {
    repository.conflictSnapshots.add(
      _conflicts([
        _file('a.txt'),
      ], message: 'Merge topic\n\n# Conflicts:\n#\ta.txt\nDetails'),
    );
    final session = service.active!;
    await session.load();
    expect(session.mergeSubject, 'Merge topic');
    expect(session.mergeDescription, 'Details');
    session.mergeSubject = 'Edited';
    await session.load();
    expect(session.mergeSubject, 'Edited');
    expect(session.current.selectedFile?.path, utf8.encode('a.txt'));
  });

  test(
    'unsaved drafts survive the resolver and drop when the file changes',
    () async {
      repository.conflictSnapshots.add(_conflicts([_file('a.txt')]));
      final session = service.active!;
      await session.load();
      final file = session.current.selectedFile!;
      final draft = ConflictMergeDraft.fromFile(file);
      session.remember(
        file,
        ConflictFileDraft(
          fingerprint: file.fingerprint,
          text: draft.take(0, ConflictRegionChoice.current),
          draft: draft,
          focusedRegion: 0,
        ),
      );
      // The resolver of another tab came and went: the same session returns.
      expect(identical(service.active, session), isTrue);
      expect(session.draftOf(file)?.text, 'b\n');
      // The file changed on disk; its draft no longer applies.
      repository.conflictSnapshots
        ..clear()
        ..add(_conflicts([_file('a.txt', fingerprint: 2)]));
      await session.load();
      expect(session.draftOf(session.current.selectedFile!), isNull);
    },
  );

  test('a result with markers is refused and says how many remain', () async {
    repository.conflictSnapshots.add(_conflicts([_file('a.txt')]));
    final session = service.active!;
    await session.load();
    final file = session.current.selectedFile!;
    final saved = await session.save(
      interaction,
      file,
      text: '<<<<<<< ours\nb\n',
      unresolved: 1,
    );
    expect(saved, isFalse);
    expect((interaction.reports.single as ConflictRegionsRemaining).count, 1);
    expect(repository.calls, isNot(contains('saveConflict')));
    // A Markdown underline is content, not a marker.
    repository.conflictSnapshots
      ..clear()
      ..add(_conflicts(const [], operation: ConflictOperationKind.standalone));
    expect(
      await session.save(interaction, file, text: 'Title\n========\n'),
      isTrue,
    );
    expect(utf8.decode(repository.savedResults.single), 'Title\n========\n');
    // A standalone conflict with nothing left is finished.
    expect(session.current.finished, isTrue);
  });

  test('a chosen side saves through the core', () async {
    repository.conflictSnapshots.add(_conflicts([_file('a.txt')]));
    final session = service.active!;
    await session.load();
    await session.save(
      interaction,
      session.current.selectedFile!,
      text: '',
      side: ConflictSideChoice.incoming,
    );
    expect(repository.calls.last, 'chooseSide:incoming');
  });

  test('remembers how each file was resolved until it is undone', () async {
    final deleted = ConflictFile(
      path: utf8.encode('gone.txt'),
      kind: ConflictFileKind.text,
      ancestor: _side('a\n'),
      current: _side('b\n'),
      incoming: const ConflictSide(present: false, byteCount: 0),
      resultPresent: true,
      markerFree: true,
      regions: const [],
      fingerprint: BigInt.two,
      canUndoResolution: false,
      result: utf8.encode('b\n'),
    );
    repository.conflictSnapshots.addAll([
      _conflicts([deleted, _file('a.txt'), _file('b.txt')]),
      _conflicts([_file('a.txt'), _file('b.txt')]),
      _conflicts([_file('b.txt')]),
      _conflicts(const []),
      _conflicts([_file('b.txt')]),
    ]);
    final session = service.active!;
    await session.load();
    expect(
      ConflictSession.sideResolution(deleted, ConflictSideChoice.incoming),
      ConflictResolutionKind.deleted,
    );

    await session.save(
      interaction,
      deleted,
      text: '',
      side: ConflictSideChoice.incoming,
    );
    await session.save(
      interaction,
      session.current.selectedFile!,
      text: '',
      side: ConflictSideChoice.current,
    );
    await session.save(
      interaction,
      session.current.selectedFile!,
      text: 'merged\n',
    );
    expect(
      session.resolutionOf(utf8.encode('gone.txt')),
      ConflictResolutionKind.deleted,
    );
    expect(
      session.resolutionOf(utf8.encode('a.txt')),
      ConflictResolutionKind.current,
    );
    expect(
      session.resolutionOf(utf8.encode('b.txt')),
      ConflictResolutionKind.merged,
    );

    await session.undo(interaction, utf8.encode('b.txt'));
    expect(session.resolutionOf(utf8.encode('b.txt')), isNull);
    expect(
      session.resolutionOf(utf8.encode('gone.txt')),
      ConflictResolutionKind.deleted,
    );
  });

  test(
    'a resolved file gives way to the next, the last to the first',
    () async {
      repository.conflictSnapshots.addAll([
        _conflicts([
          _file('a.txt'),
          _file('b.txt'),
          _file('c.txt'),
          _file('d.txt'),
        ]),
        _conflicts([_file('a.txt'), _file('c.txt'), _file('d.txt')]),
        _conflicts([_file('a.txt'), _file('c.txt')]),
      ]);
      final session = service.active!;
      await session.load();
      session.select(1);

      await session.save(
        interaction,
        session.current.selectedFile!,
        text: '',
        side: ConflictSideChoice.current,
      );
      expect(utf8.decode(session.current.selectedFile!.path), 'c.txt');

      session.select(2);
      await session.save(
        interaction,
        session.current.selectedFile!,
        text: 'merged\n',
      );
      expect(utf8.decode(session.current.selectedFile!.path), 'a.txt');
    },
  );

  test('ticked files take one side in turn and keep the shown file', () async {
    repository.conflictSnapshots.addAll([
      _conflicts([_file('a.txt'), _file('b.txt'), _file('c.txt')]),
      _conflicts([_file('b.txt'), _file('c.txt')]),
      _conflicts([_file('b.txt')]),
    ]);
    final session = service.active!;
    await session.load();
    session.select(1);
    final first = session.current.snapshot!.files.first;
    session.remember(
      first,
      ConflictFileDraft(fingerprint: first.fingerprint, text: 'draft'),
    );
    await session.chooseSideForAll(interaction, [
      utf8.encode('a.txt'),
      utf8.encode('c.txt'),
      utf8.encode('gone.txt'),
    ], ConflictSideChoice.current);
    expect(repository.calls.where((call) => call.startsWith('chooseSide')), [
      'chooseSide:current',
      'chooseSide:current',
    ]);
    expect(session.current.selectedFile?.path, utf8.encode('b.txt'));
    expect(session.current.busy, isFalse);
    expect(session.draftOf(first), isNull);
    expect(interaction.reports, isEmpty);
  });

  test('a failed bulk choice stops, reports and reloads', () async {
    repository.conflictSnapshots.add(
      _conflicts([_file('a.txt'), _file('b.txt')]),
    );
    final session = service.active!;
    await session.load();
    repository.conflictError = StateError('failed');
    await session.chooseSideForAll(interaction, [
      utf8.encode('a.txt'),
      utf8.encode('b.txt'),
    ], ConflictSideChoice.incoming);
    expect(
      repository.calls.where((call) => call.startsWith('chooseSide')),
      hasLength(1),
    );
    expect(interaction.reports.single, isA<ConflictSaveFailed>());
    expect(session.current.busy, isFalse);
  });

  test('Continue waits for every file and sends the merge message', () async {
    repository.conflictSnapshots.add(
      _conflicts([_file('a.txt')], message: 'Merge topic'),
    );
    final session = service.active!;
    await session.load();
    await session.sequence(
      interaction,
      ConflictSequencerAction.continueOperation,
    );
    expect(repository.calls, isNot(contains('continue:continueOperation')));

    repository.conflictSnapshots
      ..clear()
      ..add(_conflicts(const [], message: 'Merge topic'));
    await session.load();
    session.mergeDescription = 'Why';
    await session.sequence(
      interaction,
      ConflictSequencerAction.continueOperation,
    );
    expect(repository.continuedMergeMessage, 'Merge topic\n\nWhy');
    expect(
      (interaction.reports.single as ConflictContinued).state,
      ConflictContinuationState.completed,
    );
    expect(session.current.finished, isTrue);
  });

  test('Abort and Skip ask first', () async {
    repository.conflictSnapshots.add(_conflicts([_file('a.txt')]));
    final session = service.active!;
    await session.load();
    interaction.confirm = false;
    await session.sequence(interaction, ConflictSequencerAction.abort);
    expect(interaction.asked, ['confirm:abort']);
    expect(repository.calls, isNot(contains('continue:abort')));
    interaction.confirm = true;
    repository.continuation = ConflictContinuationState.aborted;
    await session.sequence(interaction, ConflictSequencerAction.abort);
    expect(repository.calls.last, 'continue:abort');
    expect(session.current.finished, isTrue);
  });

  test('without a paused operation the resolver closes', () async {
    repository.conflictError = const ConflictException(
      ConflictFailureCode.noActiveOperation,
    );
    final session = service.active!;
    await session.load();
    expect(session.current.finished, isTrue);
    expect(session.current.loadFailed, isFalse);
  });

  test('an unknown remote outcome of a save is reported as such', () async {
    repository.conflictSnapshots.add(_conflicts([_file('a.txt')]));
    final session = service.active!;
    await session.load();
    repository.conflictError = const RemoteOutcomeUnknownException();
    await session.save(
      interaction,
      session.current.selectedFile!,
      text: 'resolved\n',
    );
    expect(
      (interaction.reports.single as ConflictWorkflowFailed).failure,
      isA<OutcomeUnknownFailure>(),
    );
  });

  test('a finished session is forgotten', () async {
    final session = service.active!;
    service.finish(session);
    expect(identical(service.active, session), isFalse);
  });
}
