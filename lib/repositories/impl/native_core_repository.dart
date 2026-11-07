import '../../rust/api.dart' as api;
import '../core_repository.dart';
import 'native_mappers.dart';

/// Loads only the library shipped alongside the executable, never a cwd fallback.
/// FRB is process-owned; disposing a service must not unload its Dart ports.
final class NativeCoreRepository implements CoreRepository {
  @override
  Future<void> initialize() async {
    await ensureNativeCoreLoaded();
    final info = await api.coreInfo();
    if (info.protocolVersion != 1) {
      throw StateError('native_protocol_mismatch');
    }
  }
}
