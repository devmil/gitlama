import '../models/remote_workspace.dart';
import '../models/settings.dart';

/// What the main window answers when an inspector window inspects a
/// repository on a remote host through the main window's connection.
///
/// Values are wire values of the remote read surface. Failures throw
/// [RepositorySessionException]; only their typed code reaches the window.
abstract interface class RemoteInspectionServer {
  /// Opens a read-only session of [window] on the remote [repository];
  /// returns the wire open result.
  Future<Object?> open(
    String window,
    NativePathIdentity repository,
    BigInt generation,
  );

  /// Reads [method] of [window]'s [session].
  Future<Object?> read(
    String window,
    BigInt session,
    String method,
    Map<String, Object?> arguments,
  );

  /// Closes [window]'s [session].
  Future<void> close(String window, BigInt session, BigInt generation);
}

/// The channel on which inspector windows reach the main window's remote
/// connections, and the windows that are open (main window only).
abstract interface class RemoteInspectionHostRepository {
  /// Serves inspector windows' calls with [server].
  Future<void> serve(RemoteInspectionServer server);

  /// The identifiers of the open windows, each time a window opens or
  /// closes.
  Stream<Set<String>> get openWindows;

  Future<void> dispose();
}

/// Read-only helper sessions of one connection that no tab owns. An
/// inspector window reads through one of them while the main window holds
/// the connection; each is opened and closed independently of the tabs.
///
/// Values are the wire values of the remote read surface: JSON-shaped maps,
/// lists and scalars. Failures throw [RepositorySessionException].
abstract interface class RemoteDetachedReads {
  /// Opens a session of its own on the repository at the host [path].
  /// [session] is its connection-local identifier, null when the open
  /// failed; [result] is the wire open result under that identifier.
  Future<({BigInt? session, Object? result})> open(
    List<int> path,
    BigInt generation,
  );

  /// Sends the read [method] for [session]. The session argument of
  /// [arguments] is replaced with the helper's session.
  Future<Object?> read(
    BigInt session,
    String method,
    Map<String, Object?> arguments,
  );

  /// Closes [session]; closing an unknown session succeeds.
  Future<void> close(BigInt session, BigInt generation);
}

/// The detached reads of the live connection of [authority], or null when
/// it has none.
typedef RemoteConnectionReads =
    RemoteDetachedReads? Function(RemoteAuthority authority);
