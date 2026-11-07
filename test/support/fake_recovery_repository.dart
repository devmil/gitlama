import 'package:gitlama/models/recovery.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/recovery_repository.dart';
import 'package:gitlama/services/recovery_service.dart';
import 'package:gitlama/services/settings_service.dart';

RecoveryService fakeRecoveryService(SettingsService settings) =>
    RecoveryService(FakeRecoveryRepository(), settings);

final class FakeRecoveryRepository implements RecoveryRepository {
  FakeRecoveryRepository({
    this.start = const StartupRecovery(
      previousShutdown: PreviousShutdown.clean,
      checkpoint: SettingsDocument(),
    ),
  });

  final StartupRecovery start;
  final List<SettingsDocument> checkpoints = [];
  final List<SettingsDocument> cleanFinishes = [];
  final Map<String, SequencerRecoveryState?> inspections = {};
  Object? beginFailure;
  Object? checkpointFailure;

  @override
  Future<StartupRecovery> begin() async {
    final failure = beginFailure;
    if (failure != null) throw failure;
    return start;
  }

  @override
  Future<void> checkpoint(SettingsDocument document) async {
    final failure = checkpointFailure;
    if (failure != null) throw failure;
    checkpoints.add(document);
  }

  @override
  Future<void> finishClean(SettingsDocument document) async {
    cleanFinishes.add(document);
  }

  @override
  Future<SequencerRecoveryState?> inspectRepository(String path) async =>
      inspections[path];
}
