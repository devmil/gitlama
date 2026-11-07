import '../models/repository_drop.dart';

abstract interface class RepositoryDropRepository {
  Stream<RepositoryDropEvent> get events;

  Future<void> initialize();

  Future<void> dispose();
}
