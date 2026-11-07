import '../../models/remote_workspace.dart';

/// What the workspace needs of remote host connections: their states, and
/// connecting, disconnecting and creating repositories on them.
abstract interface class WorkspaceRemotes {
  /// Whether this window offers remote workspaces at all.
  bool get available;

  Stream<RemoteConnectionState> get states;

  RemoteHostProfile? profile(String id);

  RemoteConnectionState state(String profileId);

  /// Whether [authority]'s connection is ready and serves sessions.
  bool isLive(RemoteAuthority authority);

  Future<RemoteConnectionState> connect(String profileId);

  Future<void> disconnect(String profileId);

  /// Forgets the workspace binding [path] on [authority]'s host was opened
  /// with, after the user chose to trust the repository found there now.
  void forgetBinding(RemoteAuthority authority, List<int> path);

  /// Creates a repository at [path] on [authority]'s connected host without
  /// opening it.
  Future<void> initializeRepository(
    RemoteAuthority authority,
    List<int> path, {
    required String initialBranch,
    required bool bare,
  });
}

/// A window without remote workspaces.
final class NoWorkspaceRemotes implements WorkspaceRemotes {
  const NoWorkspaceRemotes();

  @override
  bool get available => false;

  @override
  Stream<RemoteConnectionState> get states => const Stream.empty();

  @override
  RemoteHostProfile? profile(String id) => null;

  @override
  RemoteConnectionState state(String profileId) => RemoteConnectionState(
    profileId: profileId,
    phase: RemoteConnectionPhase.idle,
  );

  @override
  bool isLive(RemoteAuthority authority) => false;

  @override
  Future<RemoteConnectionState> connect(String profileId) => Future.error(
    const RemoteWorkspaceException(RemoteFailureCode.unsupported),
  );

  @override
  Future<void> disconnect(String profileId) async {}

  @override
  void forgetBinding(RemoteAuthority authority, List<int> path) {}

  @override
  Future<void> initializeRepository(
    RemoteAuthority authority,
    List<int> path, {
    required String initialBranch,
    required bool bare,
  }) => Future.error(
    const RemoteWorkspaceException(RemoteFailureCode.unsupported),
  );
}
