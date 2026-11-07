import '../models/clone_attempt.dart';
import '../models/repository_state.dart';
import '../models/settings.dart';
import 'inspection_repository.dart';

export 'inspection_repository.dart';

/// A read-only session of its own for one inspector window: it opens a
/// repository, inspects it and closes it.
abstract interface class InspectionSessionRepository
    implements InspectionRepository {
  Future<OpenedRepositorySession> openIdentity(
    NativePathIdentity identity,
    int generation,
  );

  Future<bool> close(RepositorySessionIdentity identity);
}
