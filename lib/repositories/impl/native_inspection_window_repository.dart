import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../models/inspection_window.dart';
import '../inspection_window_repository.dart';

final class NativeInspectionWindowRepository
    implements InspectionWindowRepository {
  @override
  Future<void> open(InspectionWindowRequest request) async {
    final controller = await WindowController.create(
      WindowConfiguration(arguments: request.encode(), hiddenAtLaunch: true),
    );
    await controller.show();
  }
}
