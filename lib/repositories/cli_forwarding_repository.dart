import '../models/cli_forwarding.dart';

abstract interface class CliForwardingRepository {
  Future<CliStartupResult> prepareProcessInvocation();
  Future<CliStartupResult> ensureOwner();
  Future<CliForwardedCommand?> poll();
  Future<bool> respond(BigInt requestId, CliForwardingResponse response);
  Future<void> dispose();
}
