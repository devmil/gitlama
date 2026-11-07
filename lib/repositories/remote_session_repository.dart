import '../models/operation_center.dart';
import '../models/remote_workspace.dart';
import '../models/repository_state.dart';
import 'remote_connection_repository.dart';
import 'remote_inspection_host_repository.dart';
import 'repository_session_repository.dart';

export 'remote_inspection_host_repository.dart' show RemoteDetachedReads;

/// Records remote writes durably before they are sent and when they resolve.
abstract interface class RemoteOperationLedger {
  /// Persists [operation]. A failure must stop the write before any byte of
  /// it is sent.
  Future<void> record(RemotePendingOperation operation);
}

/// One connection's repository sessions on a remote helper.
abstract interface class RemoteSessionSurface {
  /// The remote read surface, plus staging and normal commits when the
  /// connection negotiated them. Every other call fails with an unsupported
  /// failure before anything is sent.
  RepositorySessionRepository get sessions;

  /// The workspace binding the helper reported when [session] opened.
  String? bindingOf(RepositorySessionIdentity session);

  /// Looks up the helper's receipt for [operation] without executing it.
  Future<RemotePendingOperation> lookup(RemotePendingOperation operation);

  /// Reads one page of a remote directory.
  Future<RemoteDirectoryPage> listDirectory({
    List<int>? directory,
    String? cursor,
  });

  /// Creates a repository at the host [path], a missing folder or an empty
  /// one, without opening it. Throws [RepositorySessionException] with the
  /// reason the host created nothing (an existing repository, a folder that
  /// is not empty, ...) and [RemoteWorkspaceException] when the call could
  /// not be made, with [RemoteFailureCode.writeNotPermitted] when the
  /// connection may not create repositories.
  Future<void> initializeRepository({
    required List<int> path,
    required String initialBranch,
    required bool bare,
  });

  /// Progress and results of this connection's operations on the helper,
  /// under local remote session identities. Asks the helper only while an
  /// operation runs or a write was sent recently, and otherwise every few
  /// seconds; in between it answers from the last result.
  Future<OperationCenterSnapshot> operations();

  /// Dismisses a finished remote operation.
  Future<void> dismissOperation(OperationCenterEntry entry);

  /// Read-only sessions this connection serves to inspector windows, which
  /// cannot reach the connection themselves.
  RemoteDetachedReads get detachedReads;
}

/// Creates the session surface of an open channel.
abstract interface class RemoteSessionFactory {
  /// [expectedBinding] names the workspace binding a path had when it was
  /// last opened this run; [rememberBinding] learns the binding the helper
  /// reports when a session opens.
  RemoteSessionSurface create(
    RemoteChannel channel, {
    required RemoteAuthority authority,
    required RemoteOperationLedger ledger,
    required BigInt Function() allocateSessionId,
    required String? Function(List<int> path) expectedBinding,
    required void Function(List<int> path, String binding) rememberBinding,
  });
}

/// The session surfaces of the window's live remote connections.
///
/// The remote workspace service owns the connections and publishes each
/// ready one here; the session backend router reads them to route remote
/// sessions. No service receives a surface from another.
abstract interface class RemoteSessionDirectory {
  /// The surface of [authority]'s connection while it is ready.
  RemoteSessionSurface? surfaceFor(RemoteAuthority authority);

  /// Publishes [surface] for [authority]; [live] tells whether the
  /// connection still serves it.
  void publish(
    RemoteAuthority authority,
    RemoteSessionSurface surface, {
    required bool Function() live,
  });

  /// Withdraws the surface of [authority]'s connection.
  void withdraw(RemoteAuthority authority);
}

/// The local durable record of remote writes.
abstract interface class RemotePendingRepository {
  /// Loads every recorded operation. Throws [RemoteWorkspaceException] with
  /// [RemoteFailureCode.internal] when the record exists but is unreadable
  /// or corrupt; such a record is never replaced.
  Future<List<RemotePendingOperation>> load();

  /// Atomically replaces the record.
  Future<void> save(List<RemotePendingOperation> operations);
}
