import 'dart:async';

import '../repositories/window_geometry_repository.dart';
import 'settings_service.dart';

final class WindowGeometryService {
  WindowGeometryService(this._repository, this._settings);

  final WindowGeometryRepository _repository;
  final SettingsService _settings;
  StreamSubscription<void>? _subscription;
  Timer? _debounce;
  var _available = false;

  Future<void> initialize() async {
    _available = await _repository.initialize();
    if (!_available) return;
    final appearance = _settings.current.appearance;
    final complete =
        appearance.windowX != null &&
        appearance.windowY != null &&
        appearance.windowWidth != null &&
        appearance.windowHeight != null;
    await _repository.restore(
      complete
          ? WindowGeometry(
              x: appearance.windowX!,
              y: appearance.windowY!,
              width: appearance.windowWidth!,
              height: appearance.windowHeight!,
              maximized: appearance.windowMaximized,
            )
          : null,
    );
    _subscription = _repository.changes.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(_capture()),
      );
    });
  }

  Future<void> _capture() async {
    if (!_available) return;
    late final WindowGeometry geometry;
    try {
      geometry = await _repository.read();
    } on Object {
      return;
    }
    final current = _settings.current;
    _settings.updateView(
      current.copyWith(
        appearance: current.appearance.copyWith(
          windowX: geometry.x,
          windowY: geometry.y,
          windowWidth: geometry.width,
          windowHeight: geometry.height,
          windowMaximized: geometry.maximized,
        ),
      ),
    );
  }

  Future<void> activate() => _repository.activate();

  Future<void> dispose() async {
    _debounce?.cancel();
    await _capture();
    await _subscription?.cancel();
    await _repository.dispose();
  }
}
