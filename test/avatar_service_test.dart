import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/avatar_repository.dart';
import 'package:gitlama/services/avatar_service.dart';
import 'package:gitlama/services/settings_service.dart';

import 'support/fake_settings_repository.dart';

final class _AvatarRepository implements AvatarRepository {
  final List<Completer<Uint8List?>> responses = [];
  int requests = 0;
  int clears = 0;

  @override
  Future<Uint8List?> load(String hash, {required bool enabled}) {
    requests += 1;
    final response = Completer<Uint8List?>();
    responses.add(response);
    return response.future;
  }

  @override
  Future<void> clearCache() async {
    clears += 1;
  }
}

void main() {
  test(
    'opt-in gates requests, coalesces one author, and discards late images',
    () async {
      final settings = SettingsService(FakeSettingsRepository());
      await settings.initialize();
      final repository = _AvatarRepository();
      final avatars = AvatarService(repository, settings)..initialize();
      const hash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

      expect(await avatars.imageFor(hash), isNull);
      expect(repository.requests, 0);

      await avatars.setEnabled(true);
      final first = avatars.imageFor(hash);
      final second = avatars.imageFor(hash);
      expect(repository.requests, 1);
      await avatars.setEnabled(false);
      repository.responses.single.complete(Uint8List.fromList([1, 2, 3]));
      expect(await first, isNull);
      expect(await second, isNull);
      expect(repository.clears, 1);
      expect(await avatars.imageFor(hash), isNull);
      expect(repository.requests, 1);

      await avatars.dispose();
      await settings.dispose();
    },
  );

  test(
    'an old request cannot remove a newer request for the same author',
    () async {
      final settings = SettingsService(FakeSettingsRepository());
      await settings.initialize();
      final repository = _AvatarRepository();
      final avatars = AvatarService(repository, settings)..initialize();
      const hash =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

      await avatars.setEnabled(true);
      final old = avatars.imageFor(hash);
      await avatars.setEnabled(false);
      await avatars.setEnabled(true);
      final current = avatars.imageFor(hash);
      repository.responses.first.complete(Uint8List.fromList([1]));
      expect(await old, isNull);
      expect(identical(avatars.imageFor(hash), current), isTrue);
      expect(repository.requests, 2);
      repository.responses.last.complete(Uint8List.fromList([2]));
      expect(await current, [2]);

      await avatars.dispose();
      await settings.dispose();
    },
  );
}
