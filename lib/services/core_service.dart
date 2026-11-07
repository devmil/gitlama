import '../repositories/core_repository.dart';

/// Owns native readiness for one application bootstrap attempt.
/// Initialization fails before the ready UI appears if the native ABI disagrees.
final class CoreService {
  CoreService(this._repository);
  final CoreRepository _repository;
  Future<void> initialize() => _repository.initialize();
}
