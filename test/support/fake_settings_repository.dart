import 'dart:async';

import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/settings_repository.dart';
import 'package:gitlama/services/settings_service.dart';

SettingsService fakeSettingsService() =>
    SettingsService(FakeSettingsRepository());

final class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({
    this.loaded = const LoadedSettings(
      state: SettingsLoadState.absent,
      document: SettingsDocument(),
    ),
  });

  final LoadedSettings loaded;
  final List<SettingsDocument> saves = [];
  Object? saveFailure;

  /// When set, a save waits for it before it succeeds or fails.
  Completer<void>? saveBarrier;

  @override
  Future<LoadedSettings> load() async => loaded;

  @override
  Future<void> save(SettingsDocument document) async {
    await saveBarrier?.future;
    final failure = saveFailure;
    if (failure != null) throw failure;
    saves.add(document);
  }
}
