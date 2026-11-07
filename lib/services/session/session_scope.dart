import '../../models/repository_state.dart';

/// What a family of repository commands needs from the workspace: the
/// active session, whether a session is still open, a rescan, and History
/// following the HEAD an operation moves to.
///
/// Families never open, close or read the tabs themselves; the workspace is
/// the one owner of the session lifecycle.
abstract interface class SessionScope {
  /// The active tab's session. Throws [RepositorySessionException] with
  /// [RepositoryFailureCode.unknownSession] without one, and [StateError]
  /// once the workspace is disposed.
  RepositorySessionIdentity requireCurrent();

  /// Throws [StateError] once the workspace is disposed.
  void ensureActive();

  /// Whether [identity] is the session of an open tab.
  bool isOpen(RepositorySessionIdentity identity);

  /// Rescans [identity] when it is still open.
  Future<void> refreshIfOpen(RepositorySessionIdentity identity);

  /// Runs [operation] so that History selects and reveals the HEAD it moves
  /// [identity] to; [moved] tells whether the outcome may have moved it.
  Future<T> followingHead<T>(
    RepositorySessionIdentity identity,
    Future<T> Function() operation,
    bool Function(T result) moved,
  );
}

/// The failure of a command that needs an active session.
const unknownSessionFailure = RepositorySessionException(
  RepositoryFailure(RepositoryFailureCode.unknownSession),
);

/// The failure of a command whose preview token this workspace never
/// issued or already spent.
const unknownPreviewFailure = RepositorySessionException(
  RepositoryFailure(RepositoryFailureCode.invalidOptions),
);
