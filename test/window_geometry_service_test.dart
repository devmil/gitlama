import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/window_geometry_repository.dart';
import 'package:gitlama/services/settings_service.dart';
import 'package:gitlama/services/window_geometry_service.dart';

import 'support/fake_settings_repository.dart';

void main() {
  test(
    'restores complete geometry and persists bounded window events',
    () async {
      final settings = SettingsService(
        FakeSettingsRepository(
          loaded: const LoadedSettings(
            state: SettingsLoadState.loaded,
            document: SettingsDocument(
              appearance: AppearanceSettings(
                windowX: 40,
                windowY: 60,
                windowWidth: 1200,
                windowHeight: 760,
                windowMaximized: true,
              ),
            ),
          ),
        ),
      );
      await settings.initialize();
      final repository = _WindowRepository();
      final service = WindowGeometryService(repository, settings);

      await service.initialize();
      expect(repository.restored?.width, 1200);
      expect(repository.restored?.maximized, isTrue);

      repository.current = const WindowGeometry(
        x: 100,
        y: 120,
        width: 1440,
        height: 900,
        maximized: false,
      );
      repository.events.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(settings.current.appearance.windowX, 100);
      expect(settings.current.appearance.windowWidth, 1440);

      await service.dispose();
      await settings.dispose();
    },
  );
}

final class _WindowRepository implements WindowGeometryRepository {
  final StreamController<void> events = StreamController<void>.broadcast();
  WindowGeometry? restored;
  WindowGeometry current = const WindowGeometry(
    x: 0,
    y: 0,
    width: 900,
    height: 600,
    maximized: false,
  );

  @override
  Stream<void> get changes => events.stream;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> restore(WindowGeometry? geometry) async => restored = geometry;

  @override
  Future<void> activate() async {}

  @override
  Future<WindowGeometry> read() async => current;

  @override
  Future<void> dispose() => events.close();
}
