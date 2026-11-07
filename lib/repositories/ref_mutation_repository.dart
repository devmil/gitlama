import '../models/ref_mutation.dart';
import '../models/repository_state.dart';

/// Creating, renaming, moving and deleting branches and tags.
abstract interface class RefMutationRepository {
  Future<RefMutationPreview> previewRefMutation(
    RepositorySessionIdentity identity,
    RefMutationRequest request,
  );

  Future<RefMutationExecutionResult> executeRefMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  );
}
