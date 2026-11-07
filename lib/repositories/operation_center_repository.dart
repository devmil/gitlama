import '../models/operation_center.dart';

abstract interface class OperationCenterRepository {
  Future<OperationCenterSnapshot> snapshot({int maximumEntries = 256});

  Future<void> dismiss(OperationCenterEntry entry);

  Future<void> dismissAll();
}
