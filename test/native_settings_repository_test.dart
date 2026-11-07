import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/native_mappers.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/app_shortcut.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/repositories/impl/native_settings_repository.dart';

const _profileId = '123e4567-e89b-42d3-a456-426614174000';
const _otherProfileId = '00000000-0000-4000-8000-00000000000a';
const _storeId = '0123456789abcdef0123456789abcdef';

NativePathIdentity _local(String path) => NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: path.codeUnits,
);

NativePathIdentity _remote(String path, [String profileId = _profileId]) =>
    NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: path.codeUnits,
      remote: RemoteAuthority(
        profileId: profileId,
        storeId: _storeId,
        accountUid: '1000',
      ),
    );

RemoteHostProfile _profile(String id) => RemoteHostProfile(
  id: id,
  label: 'Build server',
  alias: 'build-01.example',
  verified: const RemoteVerifiedIdentity(
    storeId: _storeId,
    accountUid: '1000',
    accountName: 'builder',
  ),
);

void main() {
  test('remote identities and profiles survive the native mapping', () {
    final local = _local('/home/dev/project');
    final first = _remote('/home/dev/project');
    final second = _remote('/home/dev/project', _otherProfileId);
    final document = SettingsDocument(
      recentRepositories: [first, local],
      worktrees: [
        WorktreeSettings(
          identity: first,
          draft: const CommitDraft(subject: 'first host'),
        ),
        WorktreeSettings(
          identity: second,
          draft: const CommitDraft(subject: 'second host'),
        ),
        WorktreeSettings(
          identity: local,
          draft: const CommitDraft(subject: 'this computer'),
        ),
      ],
      openWorktrees: [first, second, local],
      activeWorktree: second,
      tabGroups: [
        TabGroupSettings(color: 'blue', members: [first, local]),
      ],
      remoteProfiles: [
        _profile(_profileId),
        const RemoteHostProfile(
          id: _otherProfileId,
          label: 'Laptop',
          alias: 'laptop',
          writesAllowed: true,
        ),
      ],
    );
    expect(document.hasValidRemoteData, isTrue);

    final native = settingsDocumentToNative(document);
    expect(native.openWorktrees[2].remote, isNull);
    expect(native.activeWorktree!.remote!.profileId, _otherProfileId);
    expect(native.remoteProfiles[1].verified, isNull);
    final mapped = settingsDocumentFromNative(native);

    expect(mapped.recentRepositories, [first, local]);
    expect(mapped.openWorktrees, [first, second, local]);
    expect(mapped.activeWorktree, second);
    expect(mapped.tabGroups.single.members, [first, local]);
    expect(mapped.remoteProfiles, document.remoteProfiles);
    expect(mapped.remoteProfiles[1].writesAllowed, isTrue);
    expect(
      {
        for (final worktree in mapped.worktrees)
          worktree.identity: worktree.draft.subject,
      },
      {first: 'first host', second: 'second host', local: 'this computer'},
    );
  });

  test(
    'hosting bindings preserve local and remote authorities in native settings',
    () {
      final identities = [
        _local('/home/dev/project'),
        _remote('/home/dev/project'),
        _remote('/home/dev/project', _otherProfileId),
      ];
      final document = SettingsDocument(
        hostingConnections: const [
          HostingConnection(
            id: 'github:test',
            preset: HostingPreset.gitHub,
            login: 'tester',
            webBaseUrl: 'https://github.com',
            apiBaseUrl: 'https://api.github.com',
            oauthClientId: 'public-client',
            enabled: true,
            capabilities: [HostingCapability.changeRequests],
            credentialIdentity: 'credential:github:test',
          ),
        ],
        hostingBindings: [
          for (var i = 0; i < identities.length; i++)
            HostingBindingOverride(
              repository: identities[i],
              remote: 'origin'.codeUnits,
              connectionId: 'github:test',
              providerRepository: 'team/project$i',
            ),
        ],
      );
      expect(document.hasValidRemoteData, isTrue);
      final mapped = settingsDocumentFromNative(
        settingsDocumentToNative(document),
      );
      expect(mapped.hasValidRemoteData, isTrue);
      expect(
        {
          for (final binding in mapped.hostingBindings)
            binding.repository: binding.providerRepository,
        },
        {
          for (var i = 0; i < identities.length; i++)
            identities[i]: 'team/project$i',
        },
      );
      expect(
        mapped.hostingBindings.every(
          (binding) => binding.connectionId == 'github:test',
        ),
        isTrue,
      );
    },
  );

  test('diff preferences survive the native mapping', () {
    const preferences = DiffViewPreferences(
      wrap: true,
      layout: DiffViewLayout.sideBySide,
      whitespace: DiffWhitespace.ignoreEndOfLine,
      contextLines: 10,
      showIndicators: false,
      showMinimap: false,
    );
    const document = SettingsDocument(
      appearance: AppearanceSettings(diffView: preferences),
    );
    final native = settingsDocumentToNative(document);
    expect(native.appearance.diffLayout, 'sideBySide');
    expect(native.appearance.diffWhitespace, 'ignoreEndOfLine');
    expect(settingsDocumentFromNative(native).appearance.diffView, preferences);
  });

  test('the history reference scope survives the native mapping', () {
    expect(const AppearanceSettings().historyOtherRefs, isFalse);
    const document = SettingsDocument(
      appearance: AppearanceSettings(historyOtherRefs: true),
    );
    final native = settingsDocumentToNative(document);
    expect(native.appearance.historyOtherRefs, isTrue);
    expect(
      settingsDocumentFromNative(native).appearance.historyOtherRefs,
      isTrue,
    );
  });

  test('overrides of the removed undo commands are dropped on load', () {
    final native = settingsDocumentToNative(
      const SettingsDocument(
        shortcutOverrides: [
          ShortcutOverride(commandId: 'undo', binding: 'Ctrl+U'),
          ShortcutOverride(commandId: 'redo', binding: null),
          ShortcutOverride(commandId: 'showRecovery', binding: 'Ctrl+J'),
          ShortcutOverride(commandId: 'fetch', binding: 'Ctrl+K'),
        ],
      ),
    );
    final loaded = settingsDocumentFromNative(native);
    expect(
      [for (final override in loaded.shortcutOverrides) override.commandId],
      ['fetch'],
    );
    expect(
      () => AppShortcutCatalog.resolve(loaded.shortcutOverrides, macOS: true),
      returnsNormally,
    );
  });

  test('identical paths on different hosts are different identities', () {
    final local = _local('/srv/project');
    final first = _remote('/srv/project');
    final second = _remote('/srv/project', _otherProfileId);
    expect(first, isNot(second));
    expect(first, isNot(local));
    expect(first.isRemote, isTrue);
    expect(local.isRemote, isFalse);
    expect({first, second, local, _remote('/srv/project')}, hasLength(3));
  });

  test('invalid remote data is rejected before it reaches storage', () async {
    final valid = SettingsDocument(
      openWorktrees: [_remote('/srv/project')],
      worktrees: [WorktreeSettings(identity: _remote('/srv/project'))],
      activeWorktree: _remote('/srv/project'),
      remoteProfiles: [_profile(_profileId)],
    );
    expect(valid.hasValidRemoteData, isTrue);
    NativePathIdentity remoteWith({
      List<int>? units,
      NativePathPlatform platform = NativePathPlatform.unix,
      String profileId = _profileId,
      String storeId = _storeId,
      String accountUid = '1000',
    }) => NativePathIdentity(
      platform: platform,
      units: units ?? '/srv/project'.codeUnits,
      remote: RemoteAuthority(
        profileId: profileId,
        storeId: storeId,
        accountUid: accountUid,
      ),
    );
    final invalidIdentities = [
      remoteWith(units: 'srv/project'.codeUnits),
      remoteWith(units: const []),
      remoteWith(units: [...'/srv'.codeUnits, 0]),
      remoteWith(units: [...'/srv'.codeUnits, 0x100]),
      remoteWith(units: [0x2f, ...List.filled(remotePathByteCapacity, 0x61)]),
      remoteWith(platform: NativePathPlatform.windows),
      remoteWith(profileId: _profileId.toUpperCase()),
      remoteWith(storeId: 'abc'),
      remoteWith(accountUid: '01000'),
      remoteWith(accountUid: '4294967296'),
      remoteWith(accountUid: '-1'),
    ];
    for (final identity in invalidIdentities) {
      expect(
        SettingsDocument(recentRepositories: [identity]).hasValidRemoteData,
        isFalse,
      );
    }
    expect(
      SettingsDocument(
        recentRepositories: [remoteWith(accountUid: '4294967295')],
      ).hasValidRemoteData,
      isTrue,
    );
    final invalidProfiles = [
      _profile('not-a-uuid'),
      _profile(_profileId).copyWith(alias: '-oProxyCommand=x'),
      _profile(_profileId).copyWith(alias: 'user@@host'),
      _profile(_profileId).copyWith(label: '   '),
      _profile(_profileId).copyWith(label: 'line\nbreak'),
      _profile(_profileId).copyWith(label: 'é' * 129),
      _profile(_profileId).copyWith(
        verified: const RemoteVerifiedIdentity(
          storeId: _storeId,
          accountUid: '1000',
          accountName: 'tab\there',
        ),
      ),
    ];
    for (final profile in invalidProfiles) {
      expect(
        SettingsDocument(remoteProfiles: [profile]).hasValidRemoteData,
        isFalse,
      );
    }
    expect(
      SettingsDocument(
        remoteProfiles: [_profile(_profileId), _profile(_profileId)],
      ).hasValidRemoteData,
      isFalse,
    );
    String identifier(int index) =>
        '00000000-0000-4000-8000-${index.toRadixString(16).padLeft(12, '0')}';
    expect(
      SettingsDocument(
        remoteProfiles: [
          for (var index = 0; index < RemoteHostProfile.capacity; index++)
            _profile(identifier(index)),
        ],
      ).hasValidRemoteData,
      isTrue,
    );
    expect(
      SettingsDocument(
        remoteProfiles: [
          for (var index = 0; index <= RemoteHostProfile.capacity; index++)
            _profile(identifier(index)),
        ],
      ).hasValidRemoteData,
      isFalse,
    );
    // A local file the application opens is never remote.
    expect(
      SettingsDocument(
        repositoryAppearances: [
          RepositoryAppearance(
            identity: _local('/work'),
            image: _remote('/srv/icon.png'),
          ),
        ],
      ).hasValidRemoteData,
      isFalse,
    );
    // Orphaned remote entries stay valid after their profile is deleted.
    expect(
      SettingsDocument(
        openWorktrees: valid.openWorktrees,
        worktrees: valid.worktrees,
        activeWorktree: valid.activeWorktree,
      ).hasValidRemoteData,
      isTrue,
    );

    await expectLater(
      NativeSettingsRepository().save(
        SettingsDocument(remoteProfiles: [_profile('not-a-uuid')]),
      ),
      throwsA(
        isA<SettingsException>().having(
          (error) => error.code,
          'code',
          SettingsFailureCode.invalidDocument,
        ),
      ),
    );
  });
}
