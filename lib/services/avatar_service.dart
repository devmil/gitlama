import 'dart:async';
import 'dart:typed_data';

import '../models/settings.dart';
import '../repositories/avatar_repository.dart';
import 'settings_service.dart';

/// Owns image requests and applies the current opt-in setting at both ends.
final class AvatarService {
  AvatarService(this._repository, this._settings, {this.canEnable = true});

  final AvatarRepository _repository;
  final SettingsService _settings;
  final bool canEnable;
  final Map<String, Future<Uint8List?>> _pending = {};
  StreamSubscription<SettingsDocument>? _subscription;
  var _enabled = false;
  var _generation = 0;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool enabled) {
    if (!canEnable) return Future.value();
    return _settings.saveAppearance(
      (appearance) => appearance.copyWith(gravatarEnabled: enabled),
    );
  }

  void initialize() {
    _enabled = _settings.current.appearance.gravatarEnabled;
    _subscription = _settings.changes.listen((document) {
      final enabled = document.appearance.gravatarEnabled;
      if (enabled == _enabled) return;
      _enabled = enabled;
      _generation += 1;
      _pending.clear();
      if (!enabled) unawaited(_repository.clearCache());
    });
  }

  Future<Uint8List?> imageFor(String hash) {
    if (!_enabled || hash.length != 64) return Future.value();
    return _pending.putIfAbsent(hash, () {
      final generation = _generation;
      late final Future<Uint8List?> request;
      request = _repository
          .load(hash, enabled: true)
          .then(
            (image) => generation == _generation && _enabled ? image : null,
            onError: (Object _) => null,
          );
      unawaited(
        request.whenComplete(() {
          if (identical(_pending[hash], request)) _pending.remove(hash);
        }),
      );
      return request;
    });
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _generation += 1;
    _enabled = false;
    _pending.clear();
  }
}
