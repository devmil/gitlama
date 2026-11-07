import '../../models/settings.dart';
import '../../rust/api.dart' as native_api;
import '../../rust/third_party/gitlama_contract/storage.dart' as native;
import '../settings_repository.dart';
import 'native_enum_mappers.g.dart';
import 'native_mappers.dart';

final class NativeSettingsRepository implements SettingsRepository {
  String? _path;

  @override
  Future<LoadedSettings> load() async {
    final path = await _settingsPath();
    final result = await native_api.applicationSettingsLoad(path: path);
    _throwFailure(result.failure);
    final document = result.document;
    if (document == null) {
      throw const SettingsException(SettingsFailureCode.invalidDocument);
    }
    return LoadedSettings(
      state: result.state.toModel(),
      document: settingsDocumentFromNative(document),
    );
  }

  @override
  Future<void> save(SettingsDocument document) async {
    if (!document.hasValidRemoteData) {
      throw const SettingsException(
        SettingsFailureCode.invalidDocument,
        rule: 'precheck_remote_data',
      );
    }
    final path = await _settingsPath();
    final result = await native_api.applicationSettingsSave(
      path: path,
      document: settingsDocumentToNative(document),
    );
    _throwFailure(result.failure);
    if (!result.saved) {
      throw const SettingsException(SettingsFailureCode.io);
    }
  }

  Future<String> _settingsPath() async {
    final existing = _path;
    if (existing != null) return existing;
    final result = await native_api.applicationSettingsDefaultPath();
    _throwFailure(result.failure);
    final path = result.path;
    if (path == null) throw const SettingsException(SettingsFailureCode.io);
    return _path = path;
  }

  void _throwFailure(native.NativeSettingsFailure? failure) {
    if (failure != null) {
      throw SettingsException(failure.kind.toModel(), rule: failure.rule);
    }
  }
}
