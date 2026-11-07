import '../../models/cli_forwarding.dart';
import '../../models/settings.dart';
import '../../rust/api.dart' as api;
import '../../rust/third_party/gitlama_contract/cli_forwarding.dart' as native;
import '../cli_forwarding_repository.dart';
import 'native_mappers.dart';
import 'native_enum_mappers.g.dart';

final class NativeCliForwardingRepository implements CliForwardingRepository {
  @override
  Future<CliStartupResult> prepareProcessInvocation() async {
    await ensureNativeCoreLoaded();
    return _startup(await api.cliForwardingPrepareProcess());
  }

  @override
  Future<CliStartupResult> ensureOwner() async {
    await ensureNativeCoreLoaded();
    return _startup(await api.cliForwardingEnsureOwner());
  }

  @override
  Future<CliForwardedCommand?> poll() async {
    final result = await api.cliForwardingPoll();
    if (result.failure case final failure?) {
      throw CliForwardingException(_failure(failure));
    }
    final command = result.command;
    if (command == null) return null;
    final platform = switch (command.pathPlatform) {
      native.NativeCliPathPlatform.unix => NativePathPlatform.unix,
      native.NativeCliPathPlatform.windows => NativePathPlatform.windows,
      null => null,
    };
    return CliForwardedCommand(
      requestId: command.requestId,
      kind: command.kind.toModel(),
      path: platform == null
          ? null
          : NativePathIdentity(
              platform: platform,
              units: command.pathUnits.toList(growable: false),
            ),
      pullStrategy: command.pullStrategy?.toModel(),
      remoteAlias: command.remoteAlias,
    );
  }

  @override
  Future<bool> respond(BigInt requestId, CliForwardingResponse response) =>
      api.cliForwardingRespond(
        requestId: requestId,
        response: response.toNative(),
      );

  @override
  Future<void> dispose() => api.cliForwardingShutdown();
}

CliStartupResult _startup(native.NativeCliStartupResult result) =>
    CliStartupResult(
      state: result.state.toModel(),
      failure: result.failure == null ? null : _failure(result.failure!),
    );

CliForwardingFailureCode _failure(native.NativeCliFailureKind failure) =>
    failure.toModel();
