import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/impl/native_repository_session_repository.dart';
import 'package:gitlama/repositories/impl/repository_session_calls.g.dart';

void main() {
  test('remote path never becomes a local path when opening', () async {
    final calls = _RecordingCalls();
    final repository = NativeRepositorySessionRepository(calls);
    final remote = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/srv/project'.codeUnits,
      remote: const RemoteAuthority(
        profileId: '123e4567-e89b-42d3-a456-426614174000',
        storeId: '0123456789abcdef0123456789abcdef',
        accountUid: '1000',
      ),
    );

    await expectLater(
      repository.openIdentity(remote, 1),
      throwsA(
        isA<RepositorySessionException>().having(
          (error) => error.failure.code,
          'code',
          RepositoryFailureCode.invalidOptions,
        ),
      ),
    );
    expect(calls.invoked, isEmpty);
  });

  test('a remote adapter refuses identities of another connection', () async {
    final calls = _RecordingCalls();
    const authority = RemoteAuthority(
      profileId: '123e4567-e89b-42d3-a456-426614174000',
      storeId: '0123456789abcdef0123456789abcdef',
      accountUid: '1000',
    );
    final repository = NativeRepositorySessionRepository.remote(
      calls,
      authority: authority,
    );
    for (final identity in [
      NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/srv/project'.codeUnits,
      ),
      NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/srv/project'.codeUnits,
        remote: const RemoteAuthority(
          profileId: '223e4567-e89b-42d3-a456-426614174000',
          storeId: '0123456789abcdef0123456789abcdef',
          accountUid: '1000',
        ),
      ),
    ]) {
      await expectLater(
        repository.openIdentity(identity, 1),
        throwsA(
          isA<RepositorySessionException>().having(
            (error) => error.failure.code,
            'code',
            RepositoryFailureCode.invalidOptions,
          ),
        ),
      );
    }
    expect(calls.invoked, isEmpty);
  });
}

/// Records every bridge call; none is expected.
final class _RecordingCalls implements RepositorySessionCalls {
  final List<Symbol> invoked = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    invoked.add(invocation.memberName);
    throw UnimplementedError();
  }
}
