import '../../models/activity.dart';
import '../../models/repository_state.dart';
import '../../repositories/activity_repository.dart';
import 'session_scope.dart';

/// What the application did in a repository, and undoing or redoing it.
final class ActivityCommands {
  ActivityCommands(this._repository, this._scope);

  final ActivityRepository _repository;
  final SessionScope _scope;

  Future<ActivityPage> activity({int maximumRecords = 20}) async => _repository
      .activity(_scope.requireCurrent(), maximumRecords: maximumRecords);

  Future<ActivityPage> activityFor(
    RepositorySessionIdentity identity, {
    int maximumRecords = 20,
  }) {
    _scope.ensureActive();
    return _repository.activity(identity, maximumRecords: maximumRecords);
  }

  Future<ActivityPage> activityRecordFor(
    RepositorySessionIdentity identity,
    BigInt activityId,
  ) {
    _scope.ensureActive();
    return _repository.activityRecord(identity, activityId);
  }
}
