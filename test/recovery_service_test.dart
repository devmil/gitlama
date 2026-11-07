import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/recovery.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/services/recovery_service.dart';
import 'package:gitlama/services/settings_service.dart';

import 'support/fake_recovery_repository.dart';
import 'support/fake_settings_repository.dart';

void main() {
  test(
    'failed initialization does not finish a run that never started',
    () async {
      final repository = FakeRecoveryRepository()
        ..beginFailure = const RecoveryException(RecoveryFailureCode.locked);
      final settings = SettingsService(FakeSettingsRepository());
      await settings.initialize();
      final recovery = RecoveryService(repository, settings);

      await expectLater(
        recovery.initialize(),
        throwsA(isA<RecoveryException>()),
      );
      await recovery.dispose();

      expect(repository.cleanFinishes, isEmpty);
      await settings.dispose();
    },
  );

  test(
    'unclean startup exposes safe checkpoint without replaying work',
    () async {
      final checkpoint = _document('crash draft');
      final recoveryRepository = FakeRecoveryRepository(
        start: StartupRecovery(
          previousShutdown: PreviousShutdown.unclean,
          checkpoint: checkpoint,
        ),
      );
      final settings = SettingsService(FakeSettingsRepository());
      await settings.initialize();
      final recovery = RecoveryService(recoveryRepository, settings);

      await recovery.initialize();

      expect(recovery.startup.previousShutdown, PreviousShutdown.unclean);
      expect(
        recovery.startup.checkpoint.worktrees.single.draft.subject,
        'crash draft',
      );
      expect(recoveryRepository.checkpoints, isEmpty);
      await recovery.dispose();
      await settings.dispose();
    },
  );

  test(
    'settings changes checkpoint safely and clean shutdown is last',
    () async {
      final recoveryRepository = FakeRecoveryRepository();
      final settings = SettingsService(FakeSettingsRepository());
      await settings.initialize();
      final recovery = RecoveryService(recoveryRepository, settings);
      await recovery.initialize();

      final changed = _document('durable draft');
      settings.updateView(changed);
      await recovery.checkpointNow();
      await recovery.dispose();

      expect(recoveryRepository.checkpoints, isNotEmpty);
      expect(
        recoveryRepository.checkpoints.last.worktrees.single.draft.subject,
        'durable draft',
      );
      expect(recoveryRepository.cleanFinishes, [changed]);
      await settings.dispose();
    },
  );

  test(
    'typed disk inspection is forwarded without authorizing mutation',
    () async {
      const state = SequencerRecoveryState(
        kind: SequencerKind.rebase,
        current: 2,
        total: 5,
        indexHasConflicts: true,
        canContinue: false,
        canAbort: true,
      );
      final repository = FakeRecoveryRepository()
        ..inspections['repository'] = state;
      final settings = SettingsService(FakeSettingsRepository());
      await settings.initialize();
      final recovery = RecoveryService(repository, settings);
      await recovery.initialize();

      expect(await recovery.inspectRepository('repository'), same(state));
      expect(repository.checkpoints, isEmpty);
      await recovery.dispose();
      await settings.dispose();
    },
  );

  test(
    'failed checkpoint is visible and a newer snapshot can recover',
    () async {
      final repository = FakeRecoveryRepository()
        ..checkpointFailure = const RecoveryException(RecoveryFailureCode.io);
      final settings = SettingsService(FakeSettingsRepository());
      await settings.initialize();
      final recovery = RecoveryService(repository, settings);
      await recovery.initialize();

      settings.updateView(_document('first'));
      await expectLater(
        recovery.checkpointNow(),
        throwsA(isA<RecoveryException>()),
      );
      expect(recovery.checkpointFailure, RecoveryFailureCode.io);

      repository.checkpointFailure = null;
      settings.updateView(_document('second'));
      await recovery.checkpointNow();
      expect(recovery.checkpointFailure, isNull);
      expect(
        repository.checkpoints.last.worktrees.single.draft.subject,
        'second',
      );
      await recovery.dispose();
      await settings.dispose();
    },
  );
}

SettingsDocument _document(String subject) {
  final identity = NativePathIdentity(
    platform: NativePathPlatform.unix,
    units: const [1, 2, 3],
  );
  return SettingsDocument(
    worktrees: [
      WorktreeSettings(
        identity: identity,
        draft: CommitDraft(subject: subject),
      ),
    ],
    openWorktrees: [identity],
    activeWorktree: identity,
  );
}
