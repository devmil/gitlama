import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_appearance.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/impl/native_repository_icon_repository.dart';
import 'package:gitlama/services/repository_appearance_service.dart';
import 'package:gitlama/services/settings_service.dart';

import 'support/fake_repository_icon_repository.dart';
import 'support/fake_settings_repository.dart';

void main() {
  final repository = FakeRepositoryIconRepository.path('/work/app');
  final other = FakeRepositoryIconRepository.path('/work/other');

  Future<
    (
      RepositoryAppearanceService,
      FakeSettingsRepository,
      FakeRepositoryIconRepository,
    )
  >
  service({FakeRepositoryIconRepository? icons}) async {
    final store = FakeSettingsRepository();
    final settings = SettingsService(store);
    await settings.initialize();
    final files = icons ?? FakeRepositoryIconRepository();
    final appearances = RepositoryAppearanceService(files, settings)
      ..initialize();
    addTearDown(() async {
      await appearances.dispose();
      await settings.dispose();
    });
    return (appearances, store, files);
  }

  test('saves, replaces and removes one appearance per repository', () async {
    final (appearances, store, _) = await service();
    var changes = 0;
    appearances.changes.listen((_) => changes++);

    await appearances.save(
      RepositoryAppearance(identity: repository, icon: 'box', color: 'teal'),
    );
    await appearances.save(
      RepositoryAppearance(identity: other, color: 'rose'),
    );
    await appearances.save(
      RepositoryAppearance(identity: repository, icon: 'bug'),
    );
    await pumpEventQueue();

    expect(appearances.appearanceFor(repository)?.icon, 'bug');
    expect(appearances.appearanceFor(repository)?.color, isNull);
    expect(appearances.appearanceFor(other)?.color, 'rose');
    expect(store.saves.last.repositoryAppearances, hasLength(2));
    expect(changes, 3);

    await appearances.save(RepositoryAppearance(identity: repository));
    expect(appearances.appearanceFor(repository), isNull);
    expect(store.saves.last.repositoryAppearances.single.identity, other);
  });

  test('names a tab, keeps its mark and restores the folder name', () async {
    final (appearances, store, _) = await service();
    await appearances.save(
      RepositoryAppearance(identity: repository, icon: 'box'),
    );

    await appearances.rename(repository, '  Website\n  ');
    expect(appearances.nameFor(repository), 'Website');
    expect(appearances.appearanceFor(repository)?.icon, 'box');

    // Removing the icon keeps the name; removing the name too drops the
    // entry.
    await appearances.save(
      appearances.appearanceFor(repository)!.withoutMark(),
    );
    expect(appearances.nameFor(repository), 'Website');
    expect(appearances.appearanceFor(repository)?.hasMark, isFalse);
    await appearances.rename(repository, '   ');
    expect(appearances.appearanceFor(repository), isNull);
    expect(store.saves.last.repositoryAppearances, isEmpty);
  });

  test('tab names are one bounded line', () {
    expect(normalizeTabName(null), isNull);
    expect(normalizeTabName(' \t '), isNull);
    expect(normalizeTabName('a\nb\u0007c'), 'a b c');
    final long = normalizeTabName('ä' * 200)!;
    expect(utf8.encode(long).length, lessThanOrEqualTo(maxTabNameBytes));
    expect(long, 'ä' * (maxTabNameBytes ~/ 2));
  });

  test('reads an image once, reports it and remembers failures', () async {
    final icons = FakeRepositoryIconRepository(
      files: {'/icons/app.png': fakePngBytes},
    );
    final (appearances, _, _) = await service(icons: icons);
    final image = FakeRepositoryIconRepository.path('/icons/app.png');
    final missing = FakeRepositoryIconRepository.path('/icons/missing.png');
    final changed = appearances.changes.first;

    expect(appearances.imageAt(image), isNull);
    expect(appearances.imageAt(image), isNull);
    await changed;
    expect(appearances.imageAt(image)?.bytes, fakePngBytes);
    expect(icons.loads, ['/icons/app.png']);

    appearances.imageAt(missing);
    await appearances.changes.first;
    expect(appearances.imageAt(missing), isNull);
    expect(appearances.imageFailed(missing), isTrue);
    expect(appearances.imageFailed(image), isFalse);
  });

  test('choosing an image again rereads the file', () async {
    final image = FakeRepositoryIconRepository.path('/icons/app.png');
    final icons = FakeRepositoryIconRepository(
      chosen: image,
      files: {'/icons/app.png': fakePngBytes},
    );
    final (appearances, _, _) = await service(icons: icons);
    appearances.imageAt(image);
    await appearances.changes.first;

    expect(await appearances.chooseImage(), image);
    appearances.imageAt(image);
    await appearances.changes.first;
    expect(icons.loads, ['/icons/app.png', '/icons/app.png']);
  });

  group('repositoryIconFromBytes', () {
    Uint8List bytes(List<int> values) => Uint8List.fromList(values);

    test('recognises raster formats by their signature', () {
      for (final header in [
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A],
        [0xFF, 0xD8, 0xFF, 0xE0],
        ascii.encode('GIF89a'),
        [...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBP')],
        ascii.encode('BM....'),
        [0x00, 0x00, 0x01, 0x00, 0x01],
      ]) {
        expect(
          repositoryIconFromBytes(bytes(header))?.format,
          RepositoryIconFormat.raster,
          reason: '$header',
        );
      }
    });

    test('recognises SVG documents and rejects other files', () {
      expect(
        repositoryIconFromBytes(
          utf8.encode('  <?xml version="1.0"?>\n<svg viewBox="0 0 1 1"/>'),
        )?.format,
        RepositoryIconFormat.svg,
      );
      expect(repositoryIconFromBytes(utf8.encode('<html></html>')), isNull);
      expect(repositoryIconFromBytes(utf8.encode('plain text')), isNull);
    });
  });

  test('a remote image path is never read as a local file', () async {
    final directory = await Directory.systemTemp.createTemp('gitlama-icon');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/icon.png');
    await file.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
    final local = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: utf8.encode(file.path),
    );
    final remote = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: local.units,
      remote: const RemoteAuthority(
        profileId: '123e4567-e89b-42d3-a456-426614174000',
        storeId: '0123456789abcdef0123456789abcdef',
        accountUid: '1000',
      ),
    );
    final repository = NativeRepositoryIconRepository();
    expect(await repository.loadImage(local), isNotNull);
    expect(await repository.loadImage(remote), isNull);
  }, skip: Platform.isWindows ? 'Unix path identities' : false);
}
