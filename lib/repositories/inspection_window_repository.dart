import '../models/inspection_window.dart';

abstract interface class InspectionWindowRepository {
  Future<void> open(InspectionWindowRequest request);
}
