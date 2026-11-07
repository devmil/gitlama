import '../../models/remote_workspace.dart';
import '../../rust/api.dart' as native;
import '../../rust/third_party/gitlama_contract/remote_pending.dart'
    as native_pending;
import '../remote_session_repository.dart';

/// The pending remote write record beside the settings document.
final class NativeRemotePendingRepository implements RemotePendingRepository {
  NativeRemotePendingRepository({this._directory});

  String? _directory;

  Future<String> _resolve() async {
    final directory = _directory ??= await native
        .remotePendingDefaultDirectory();
    if (directory == null) {
      throw const RemoteWorkspaceException(RemoteFailureCode.internal);
    }
    return directory;
  }

  @override
  Future<List<RemotePendingOperation>> load() async {
    final result = await native.remotePendingLoad(directory: await _resolve());
    return switch (result.state) {
      native_pending.NativeRemotePendingLoadState.absent => const [],
      native_pending.NativeRemotePendingLoadState.loaded => [
        for (final operation in result.operations) fromNative(operation),
      ],
      _ => throw const RemoteWorkspaceException(RemoteFailureCode.internal),
    };
  }

  @override
  Future<void> save(List<RemotePendingOperation> operations) async {
    final result = await native.remotePendingSave(
      directory: await _resolve(),
      operations: [for (final operation in operations) toNative(operation)],
    );
    if (!result.saved) {
      throw const RemoteWorkspaceException(RemoteFailureCode.internal);
    }
  }

  static RemotePendingOperation fromNative(
    native_pending.NativeRemotePendingOperation operation,
  ) => RemotePendingOperation(
    operationId: operation.operationId,
    epoch: operation.epoch,
    digest: operation.digest,
    family:
        RemoteOperationFamily.values.asNameMap()[operation.family] ??
        (throw const RemoteWorkspaceException(RemoteFailureCode.internal)),
    authority: RemoteAuthority(
      profileId: operation.profileId,
      storeId: operation.storeId,
      accountUid: operation.accountUid,
    ),
    binding: operation.binding,
    pending: operation.state == 'pending',
    outcome: RemoteOperationOutcome.values
        .where((value) => value.name == operation.outcome)
        .firstOrNull,
    resultObjectId: operation.resultObjectId,
    summary: operation.summary,
    createdAtMs: operation.createdAtMs.toInt(),
    updatedAtMs: operation.updatedAtMs.toInt(),
  );

  static native_pending.NativeRemotePendingOperation toNative(
    RemotePendingOperation operation,
  ) => native_pending.NativeRemotePendingOperation(
    operationId: operation.operationId,
    epoch: operation.epoch,
    digest: operation.digest,
    family: operation.family.name,
    profileId: operation.authority.profileId,
    storeId: operation.authority.storeId,
    accountUid: operation.authority.accountUid,
    binding: operation.binding,
    state: operation.pending ? 'pending' : 'terminal',
    outcome: operation.outcome?.name,
    resultObjectId: operation.resultObjectId,
    summary: operation.summary,
    createdAtMs: BigInt.from(operation.createdAtMs),
    updatedAtMs: BigInt.from(operation.updatedAtMs),
  );
}
