import '../../models/recovery.dart';
import '../../models/settings.dart';
import '../../rust/api.dart' as native_api;
import '../../rust/third_party/gitlama_contract/recovery.dart' as native;
import '../recovery_repository.dart';
import 'native_mappers.dart';
import 'native_enum_mappers.g.dart';

final class NativeRecoveryRepository implements RecoveryRepository {
  String? _directory;

  @override
  Future<StartupRecovery> begin() async {
    final result = await native_api.applicationRecoveryBegin(
      directory: await _recoveryDirectory(),
    );
    _throwFailure(result.failure);
    final previous = result.previousShutdown;
    final checkpoint = result.checkpoint;
    if (previous == null || checkpoint == null) {
      throw const RecoveryException(RecoveryFailureCode.invalidCheckpoint);
    }
    return StartupRecovery(
      previousShutdown: previous.toModel(),
      checkpoint: settingsDocumentFromNative(checkpoint),
    );
  }

  @override
  Future<void> checkpoint(SettingsDocument document) async {
    final result = await native_api.applicationRecoveryCheckpoint(
      directory: await _recoveryDirectory(),
      document: settingsDocumentToNative(document),
    );
    _complete(result);
  }

  @override
  Future<void> finishClean(SettingsDocument document) async {
    final result = await native_api.applicationRecoveryFinishClean(
      directory: await _recoveryDirectory(),
      document: settingsDocumentToNative(document),
    );
    _complete(result);
  }

  @override
  Future<SequencerRecoveryState?> inspectRepository(String path) async {
    final result = await native_api.applicationRecoveryInspectRepository(
      path: path,
    );
    _throwFailure(result.failure);
    final state = result.state;
    if (state == null) return null;
    return SequencerRecoveryState(
      kind: state.kind.toModel(),
      current: state.current,
      total: state.total,
      indexHasConflicts: state.indexHasConflicts,
      canContinue: state.canContinue,
      canAbort: state.canAbort,
    );
  }

  Future<String> _recoveryDirectory() async {
    final existing = _directory;
    if (existing != null) return existing;
    final result = await native_api.applicationRecoveryDefaultDirectory();
    _throwFailure(result.failure);
    final path = result.path;
    if (path == null) throw const RecoveryException(RecoveryFailureCode.io);
    return _directory = path;
  }

  void _complete(native.NativeRecoveryCommandResult result) {
    _throwFailure(result.failure);
    if (!result.completed) {
      throw const RecoveryException(RecoveryFailureCode.io);
    }
  }

  void _throwFailure(native.NativeRecoveryFailure? failure) {
    if (failure != null) {
      throw RecoveryException(failure.kind.toModel());
    }
  }
}
