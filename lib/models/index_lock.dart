enum IndexLockFailureCode {
  missing,
  changed,
  unsafeFile,
  io,
  activeOperation,
  repositoryNotReady,
  invalidToken,
  staleGeneration,
  unknownSession,
  retiredSession,
}

final class IndexLockInspection {
  const IndexLockInspection({
    required this.present,
    this.token,
    this.sizeBytes,
  });

  final bool present;
  final BigInt? token;
  final BigInt? sizeBytes;
}

final class IndexLockException implements Exception {
  const IndexLockException(this.code);
  final IndexLockFailureCode code;

  @override
  String toString() => 'IndexLockException(${code.name})';
}
