import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/app_shortcut.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/services/settings_service.dart';

import 'support/fake_settings_repository.dart';

void main() {
  test('debounces view state and persists the newest revision', () async {
    final repository = FakeSettingsRepository();
    final service = SettingsService(
      repository,
      debounce: const Duration(milliseconds: 15),
      maximumFlushDelay: const Duration(milliseconds: 100),
    );
    await service.initialize();
    service.updateView(_document(sidebarWidth: 220));
    service.updateView(_document(sidebarWidth: 240));

    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(repository.saves, hasLength(1));
    expect(repository.saves.single.appearance.sidebarWidth, 240);
    await service.dispose();
  });

  test('maximum delay flushes during a continuous update stream', () async {
    final repository = FakeSettingsRepository();
    final service = SettingsService(
      repository,
      debounce: const Duration(milliseconds: 50),
      maximumFlushDelay: const Duration(milliseconds: 20),
    );
    await service.initialize();
    for (var width = 200; width < 206; width += 1) {
      service.updateView(_document(sidebarWidth: width));
      await Future<void>.delayed(const Duration(milliseconds: 6));
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(repository.saves, isNotEmpty);
    expect(repository.saves.last.appearance.sidebarWidth, 205);
    await service.dispose();
  });

  test('durable draft save reports failure and can be retried', () async {
    final repository = FakeSettingsRepository()
      ..saveFailure = const SettingsException(SettingsFailureCode.io);
    final service = SettingsService(repository);
    await service.initialize();
    final document = _document(draftSubject: 'not lost');

    await expectLater(
      service.saveDurable(document),
      throwsA(
        isA<SettingsException>().having(
          (error) => error.code,
          'code',
          SettingsFailureCode.io,
        ),
      ),
    );
    expect(service.current.worktrees.single.draft.subject, 'not lost');

    repository.saveFailure = null;
    await service.flush();
    expect(repository.saves.single, same(document));
    await service.dispose();
  });

  test(
    'loaded workspace preserves tab order active identity and closed draft',
    () async {
      final first = _identity(1);
      final second = _identity(2);
      final document = SettingsDocument(
        worktrees: [
          WorktreeSettings(identity: first),
          WorktreeSettings(
            identity: second,
            draft: const CommitDraft(subject: 'closed draft'),
          ),
        ],
        openWorktrees: [first],
        activeWorktree: first,
      );
      final repository = FakeSettingsRepository(
        loaded: LoadedSettings(
          state: SettingsLoadState.loaded,
          document: document,
        ),
      );
      final service = SettingsService(repository);

      await service.initialize();

      expect(service.current.openWorktrees, [first]);
      expect(service.current.activeWorktree, first);
      expect(service.current.worktrees[1].draft.subject, 'closed draft');
      await service.dispose();
    },
  );

  test('shutdown flush is best effort', () async {
    final repository = FakeSettingsRepository()
      ..saveFailure = const SettingsException(SettingsFailureCode.locked);
    final service = SettingsService(repository);
    await service.initialize();
    service.updateView(_document(sidebarWidth: 260));

    await service.dispose();
  });

  test(
    'shortcut overrides are validated before load and persistence',
    () async {
      final invalidRepository = FakeSettingsRepository(
        loaded: const LoadedSettings(
          state: SettingsLoadState.loaded,
          document: SettingsDocument(
            shortcutOverrides: [
              ShortcutOverride(commandId: 'showHistory', binding: 'Ctrl+F'),
            ],
          ),
        ),
      );
      final invalid = SettingsService(invalidRepository);
      await expectLater(
        invalid.initialize(),
        throwsA(
          isA<AppShortcutException>().having(
            (error) => error.code,
            'code',
            AppShortcutFailureCode.conflict,
          ),
        ),
      );

      final repository = FakeSettingsRepository();
      final service = SettingsService(repository);
      await service.initialize();
      const document = SettingsDocument(
        shortcutOverrides: [
          ShortcutOverride(commandId: 'showHistory', binding: 'Alt+H'),
        ],
      );
      await service.saveDurable(document);
      expect(repository.saves.single.shortcutOverrides.single.binding, 'Alt+H');
      await service.dispose();
    },
  );

  test(
    'invalid remote data is rejected without replacing the document',
    () async {
      final repository = FakeSettingsRepository();
      final service = SettingsService(repository);
      await service.initialize();
      const authority = RemoteAuthority(
        profileId: '123e4567-e89b-42d3-a456-426614174000',
        storeId: '0123456789abcdef0123456789abcdef',
        accountUid: '1000',
      );
      final remote = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/srv/project'.codeUnits,
        remote: authority,
      );
      final valid = SettingsDocument(
        worktrees: [
          WorktreeSettings(
            identity: remote,
            draft: const CommitDraft(subject: 'remote draft'),
          ),
        ],
        openWorktrees: [remote],
        activeWorktree: remote,
        remoteProfiles: const [
          RemoteHostProfile(
            id: '123e4567-e89b-42d3-a456-426614174000',
            label: 'Build server',
            alias: 'build-01',
          ),
        ],
      );
      await service.saveDurable(valid);
      expect(repository.saves.single, same(valid));

      final relative = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'srv/project'.codeUnits,
        remote: authority,
      );
      for (final invalid in [
        valid.copyWith(recentRepositories: [relative]),
        valid.copyWith(
          remoteProfiles: [
            const RemoteHostProfile(
              id: '123e4567-e89b-42d3-a456-426614174000',
              label: 'Build server',
              alias: 'user@@build-01',
            ),
          ],
        ),
      ]) {
        await expectLater(
          service.saveDurable(invalid),
          throwsA(
            isA<SettingsException>().having(
              (error) => error.code,
              'code',
              SettingsFailureCode.invalidDocument,
            ),
          ),
        );
        expect(
          () => service.updateView(invalid),
          throwsA(isA<SettingsException>()),
        );
        expect(service.current, same(valid));
      }
      expect(repository.saves, hasLength(1));
      await service.dispose();
    },
  );
}

SettingsDocument _document({int sidebarWidth = 200, String draftSubject = ''}) {
  final identity = _identity(1);
  return SettingsDocument(
    appearance: AppearanceSettings(sidebarWidth: sidebarWidth),
    worktrees: [
      WorktreeSettings(
        identity: identity,
        draft: CommitDraft(subject: draftSubject),
      ),
    ],
    openWorktrees: [identity],
    activeWorktree: identity,
  );
}

NativePathIdentity _identity(int value) =>
    NativePathIdentity(platform: NativePathPlatform.unix, units: [value]);
