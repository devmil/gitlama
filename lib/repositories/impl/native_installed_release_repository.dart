import '../../models/app_update.dart';
import '../../rust/api.dart' as api;
import '../installed_release_repository.dart';
import 'native_mappers.dart';

final class NativeInstalledReleaseRepository
    implements InstalledReleaseRepository {
  @override
  Future<InstalledRelease> load() async {
    await ensureNativeCoreLoaded();
    final release = await api.applicationRelease();
    return InstalledRelease(version: release.version, build: release.build);
  }
}
