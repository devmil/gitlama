/// Owns the process bridge handshake. Initialization is shared and retryable.
/// No Git repository, credential store, or subprocess is opened by this boundary.
abstract interface class CoreRepository {
  Future<void> initialize();
}
