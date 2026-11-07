import 'dart:async';

import '../models/recovery.dart';
import '../models/settings.dart';
import '../repositories/recovery_repository.dart';
import 'settings_service.dart';

/// Owns the process run marker and safe, non-executable restart checkpoint.
final class RecoveryService {
  RecoveryService(this._repository, this._settings);

  final RecoveryRepository _repository;
  final SettingsService _settings;
  StreamSubscription<SettingsDocument>? _settingsSubscription;
  Future<void> _checkpointChain = Future.value();
  StartupRecovery? _startup;
  RecoveryFailureCode? _checkpointFailure;
  var _disposed = false;

  StartupRecovery get startup =>
      _startup ?? (throw StateError('recovery_service_unavailable'));
  RecoveryFailureCode? get checkpointFailure => _checkpointFailure;

  Future<void> initialize() async {
    if (_startup != null) return;
    _startup = await _repository.begin();
    _settingsSubscription = _settings.changes.listen(_queueCheckpoint);
  }

  Future<SequencerRecoveryState?> inspectRepository(String path) =>
      _repository.inspectRepository(path);

  Future<void> checkpointNow() {
    _queueCheckpoint(_settings.current);
    return _checkpointChain;
  }

  void _queueCheckpoint(SettingsDocument document) {
    final previous = _checkpointChain;
    _checkpointChain = Future<void>(() async {
      try {
        await previous;
      } on Object {
        // A newer safe snapshot may recover after a failed checkpoint.
      }
      try {
        await _repository.checkpoint(document);
        _checkpointFailure = null;
      } on RecoveryException catch (error) {
        _checkpointFailure = error.code;
        rethrow;
      }
    });
    unawaited(_checkpointChain.catchError((Object _) {}));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _settingsSubscription?.cancel();
    if (_startup == null) return;
    try {
      await _checkpointChain;
    } on Object {
      // The final clean transition below remains authoritative.
    }
    await _repository.finishClean(_settings.current);
  }
}
