import '../models/activity.dart';
import '../models/repository_state.dart';

/// What the application did in a session.
abstract interface class ActivityRepository {
  Future<ActivityPage> activity(
    RepositorySessionIdentity identity, {
    int maximumRecords = 20,
  });

  Future<ActivityPage> activityRecord(
    RepositorySessionIdentity identity,
    BigInt activityId,
  );
}
