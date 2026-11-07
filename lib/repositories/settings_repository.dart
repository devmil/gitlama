import '../models/settings.dart';

abstract interface class SettingsRepository {
  Future<LoadedSettings> load();
  Future<void> save(SettingsDocument document);
}
