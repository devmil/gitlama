import 'dart:io';

import '../../models/remote_workspace.dart';
import '../../rust/api.dart' as native;
import '../remote_connection_repository.dart';
import 'remote/local_helper_connection_repository.dart';
import 'remote/ssh_remote_connection_repository.dart';

/// Connects through the installed OpenSSH client to the helper of the same
/// compatibility version as this application's native library.
///
/// Debug builds honour `GITLAMA_REMOTE_HELPER`, the path of a locally built
/// helper, and start it directly instead of through SSH. Release builds
/// ignore it.
final class NativeRemoteConnectionRepository
    implements RemoteConnectionRepository {
  RemoteConnectionRepository? _delegate;

  Future<RemoteConnectionRepository> _resolve() async {
    final existing = _delegate;
    if (existing != null) return existing;
    final buildId = await native.remoteHelperBuildId();
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(buildId) || buildId == '0' * 40) {
      // A build without a helper ID matches no published helper.
      throw const RemoteWorkspaceException(RemoteFailureCode.buildMismatch);
    }
    const release = bool.fromEnvironment('dart.vm.product');
    final local = Platform.environment['GITLAMA_REMOTE_HELPER'];
    final RemoteConnectionRepository created =
        !release && local != null && File(local).isAbsolute
        ? LocalHelperConnectionRepository(local, buildId)
        : SshRemoteConnectionRepository(buildId);
    return _delegate = created;
  }

  @override
  Future<String?> helperBuildId() async {
    final buildId = await native.remoteHelperBuildId();
    return RegExp(r'^[0-9a-f]{40}$').hasMatch(buildId) && buildId != '0' * 40
        ? buildId
        : null;
  }

  @override
  Future<RemoteHelperArtifact?> bundledHelper(RemoteHelperTarget target) async {
    try {
      return await (await _resolve()).bundledHelper(target);
    } on RemoteWorkspaceException {
      return null;
    }
  }

  @override
  Future<void> installHelper({
    required String alias,
    required RemoteHelperArtifact artifact,
    Future<void>? cancel,
  }) async => (await _resolve()).installHelper(
    alias: alias,
    artifact: artifact,
    cancel: cancel,
  );

  @override
  Future<RemoteChannel> open({
    required String alias,
    required Set<RemoteCapability> capabilities,
    Future<void>? cancel,
    void Function(RemoteConnectionPhase phase)? onPhase,
  }) async => (await _resolve()).open(
    alias: alias,
    capabilities: capabilities,
    cancel: cancel,
    onPhase: onPhase,
  );
}
