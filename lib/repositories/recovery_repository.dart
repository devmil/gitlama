import '../models/recovery.dart';
import '../models/settings.dart';

abstract interface class RecoveryRepository {
  Future<StartupRecovery> begin();
  Future<void> checkpoint(SettingsDocument document);
  Future<void> finishClean(SettingsDocument document);
  Future<SequencerRecoveryState?> inspectRepository(String path);
}
