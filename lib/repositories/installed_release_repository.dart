import '../models/app_update.dart';

/// Owns the release identity compiled into the native core.
abstract interface class InstalledReleaseRepository {
  Future<InstalledRelease> load();
}
