import '../../models/operation_center.dart';
import '../../models/repository_state.dart';
import '../../rust/api.dart' as native;
import '../operation_center_repository.dart';
import 'native_mappers.dart';
import 'native_enum_mappers.g.dart';

final class NativeOperationCenterRepository
    implements OperationCenterRepository {
  @override
  Future<OperationCenterSnapshot> snapshot({int maximumEntries = 256}) async {
    final result = await native.applicationOperationCenter(
      maximumEntries: maximumEntries,
    );
    if (result.failure case final failure?) {
      throw RepositorySessionException(
        RepositoryFailure(failure.kind.toModel()),
      );
    }
    final snapshot = result.snapshot;
    if (snapshot == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return operationCenterFromNative(snapshot);
  }

  @override
  Future<void> dismiss(OperationCenterEntry entry) async {
    final session = entry.session;
    final activityId = entry.activityId;
    if (session == null || activityId == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOptions),
      );
    }
    final result = await native.applicationOperationDismiss(
      sessionId: session.nativeId,
      generation: BigInt.from(session.generation),
      activityId: activityId,
    );
    throwRepositoryCommandFailure(result);
  }

  @override
  Future<void> dismissAll() async {
    final result = await native.applicationOperationDismissAll();
    throwRepositoryCommandFailure(result);
  }
}
