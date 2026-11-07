import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/impl/native_working_tree_path_repository.dart';
import 'package:gitlama/services/working_tree_paths.dart';

void main() {
  late Directory root;
  late NativePathIdentity identity;

  setUp(() {
    root = Directory.systemTemp.createTempSync('gitlama-working-tree-');
    identity = NativePathIdentity(
      platform: Platform.isWindows
          ? NativePathPlatform.windows
          : NativePathPlatform.unix,
      units: root.path.codeUnits,
    );
    File('${root.path}/present.txt').writeAsStringSync('x');
    Directory('${root.path}/nested').createSync();
    File('${root.path}/nested/deep.txt').writeAsStringSync('x');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('files and folders of the working tree are found', () async {
    final paths = WorkingTreePaths(const NativeWorkingTreePathRepository());
    expect(await paths.exists(identity, 'present.txt'.codeUnits), isTrue);
    expect(await paths.exists(identity, 'nested/deep.txt'.codeUnits), isTrue);
    expect(await paths.exists(identity, 'nested'.codeUnits), isTrue);
    expect(await paths.exists(identity, 'gone.txt'.codeUnits), isFalse);
  });

  test('a dangling symbolic link is present', () async {
    if (Platform.isWindows) return;
    Link('${root.path}/link').createSync('${root.path}/missing');
    const repository = NativeWorkingTreePathRepository();
    expect(await repository.exists(identity, 'link'.codeUnits), isTrue);
  });

  test('a path that cannot be checked counts as present', () async {
    const repository = NativeWorkingTreePathRepository();
    expect(await repository.exists(identity, [0xff, 0xfe]), isNull);
    final paths = WorkingTreePaths(repository);
    expect(await paths.exists(identity, [0xff, 0xfe]), isTrue);
    expect(
      await WorkingTreePaths.unchecked().exists(identity, 'gone'.codeUnits),
      isTrue,
    );
  });

  test('a remote repository has no local working tree', () async {
    final remote = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: identity.units,
      remote: const RemoteAuthority(
        profileId: '123e4567-e89b-42d3-a456-426614174000',
        storeId: '0123456789abcdef0123456789abcdef',
        accountUid: '1000',
      ),
    );
    final paths = WorkingTreePaths(const NativeWorkingTreePathRepository());
    expect(await paths.exists(remote, 'present.txt'.codeUnits), isFalse);
  });
}
