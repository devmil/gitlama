import '../../../models/remote_workspace.dart';
import '../../remote_session_repository.dart';

/// The live remote session surfaces of one window, in memory.
final class LiveRemoteSessions implements RemoteSessionDirectory {
  final Map<
    String,
    ({
      RemoteAuthority authority,
      RemoteSessionSurface surface,
      bool Function() live,
    })
  >
  _surfaces = {};

  @override
  RemoteSessionSurface? surfaceFor(RemoteAuthority authority) {
    final entry = _surfaces[authority.profileId];
    if (entry == null || entry.authority != authority || !entry.live()) {
      return null;
    }
    return entry.surface;
  }

  @override
  void publish(
    RemoteAuthority authority,
    RemoteSessionSurface surface, {
    required bool Function() live,
  }) => _surfaces[authority.profileId] = (
    authority: authority,
    surface: surface,
    live: live,
  );

  @override
  void withdraw(RemoteAuthority authority) {
    if (_surfaces[authority.profileId]?.authority == authority) {
      _surfaces.remove(authority.profileId);
    }
  }
}
