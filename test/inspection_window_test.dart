import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/inspection_window.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/settings.dart';

void main() {
  test(
    'inspection window request preserves native repository and file units',
    () {
      final request = InspectionWindowRequest(
        repository: NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: [47, 116, 109, 112, 47, 255],
        ),
        location: InspectorLocation(
          target: CommitTarget('a' * 40),
          path: [108, 105, 98, 47, 255],
          lens: InspectorLens.blame,
        ),
      );
      final restored = InspectionWindowRequest.decode(request.encode());
      expect(restored?.location.lens, InspectorLens.blame);
      expect(restored?.repository, request.repository);
      expect(restored?.location.target.commit, 'a' * 40);
      expect(restored?.location.path, request.location.path);
    },
  );

  test('inspection window request rejects malformed launch data', () {
    expect(InspectionWindowRequest.decode('{"schema":2}'), isNull);
    expect(
      InspectionWindowRequest.decode('{"schema":1,"kind":"blame"}'),
      isNull,
    );
    expect(InspectionWindowRequest.decode('x' * 65537), isNull);
  });

  group('remote repositories', () {
    const authority = RemoteAuthority(
      profileId: '0f8fad5b-d9cb-469f-a165-70867728950e',
      storeId: '0123456789abcdef0123456789abcdef',
      accountUid: '1000',
    );
    final remote = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/srv/notelama'.codeUnits,
      remote: authority,
    );
    final location = InspectorLocation(target: CommitTarget('a' * 40));

    test('keep their authority, so the window opens the remote one', () {
      final request = InspectionWindowRequest(
        repository: remote,
        location: location,
      );
      final restored = InspectionWindowRequest.decode(request.encode())!;
      expect(restored.repository.remote, authority);
      expect(restored.repository, remote);
    });

    test('a local request stays local', () {
      final local = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/srv/notelama'.codeUnits,
      );
      final restored = InspectionWindowRequest.decode(
        InspectionWindowRequest(repository: local, location: location).encode(),
      )!;
      expect(restored.repository.isRemote, isFalse);
      expect(restored.repository, local);
    });

    test('a schema 2 request is a local repository', () {
      final restored = InspectionWindowRequest.decode(
        '{"schema":2,"platform":"unix","units":[47,119],'
        '"location":${_json(location)}}',
      );
      expect(restored?.repository.isRemote, isFalse);
    });

    test('a malformed authority is rejected, never opened locally', () {
      String request(String remote, {int schema = 3}) =>
          '{"schema":$schema,"platform":"unix","units":[47,119],'
          '"location":${_json(location)},"remote":$remote}';
      const valid =
          '{"profileId":"0f8fad5b-d9cb-469f-a165-70867728950e",'
          '"storeId":"0123456789abcdef0123456789abcdef","accountUid":"1000"}';
      expect(InspectionWindowRequest.decode(request(valid)), isNotNull);
      // An older schema cannot name a remote repository.
      expect(InspectionWindowRequest.decode(request(valid, schema: 2)), isNull);
      for (final malformed in [
        '"x"',
        '{}',
        '{"profileId":"p","storeId":"0123456789abcdef0123456789abcdef",'
            '"accountUid":"1000"}',
        '{"profileId":"0f8fad5b-d9cb-469f-a165-70867728950e",'
            '"storeId":"0123456789abcdef0123456789abcdef","accountUid":1000}',
        '{"profileId":"0f8fad5b-d9cb-469f-a165-70867728950e",'
            '"storeId":"XYZ","accountUid":"1000"}',
      ]) {
        expect(InspectionWindowRequest.decode(request(malformed)), isNull);
      }
      // A remote path is absolute.
      expect(
        InspectionWindowRequest.decode(
          '{"schema":3,"platform":"unix","units":[119],'
          '"location":${_json(location)},"remote":$valid}',
        ),
        isNull,
      );
    });
  });
}

String _json(InspectorLocation location) => jsonEncode(location.toJson());
