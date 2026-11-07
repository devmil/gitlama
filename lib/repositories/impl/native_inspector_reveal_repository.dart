import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/inspector_reveal.dart';
import '../inspector_reveal_repository.dart';

final class NativeInspectorRevealRepository
    implements InspectorRevealRepository {
  static const _channel = WindowMethodChannel(
    'gitlama/inspector-reveal',
    mode: ChannelMode.unidirectional,
  );

  bool _listening = false;

  @override
  Future<void> listen(
    Future<bool> Function(InspectorRevealRequest) onReveal,
  ) async {
    _listening = true;
    await _channel.setMethodCallHandler((call) async {
      if (call.method != 'reveal') return false;
      final request = InspectorRevealRequest.decode(call.arguments);
      if (request == null) return false;
      final revealed = await onReveal(request);
      if (revealed) {
        try {
          await windowManager.show();
          await windowManager.focus();
        } on Object {
          // The graph is revealed even when the window cannot come forward.
        }
      }
      return revealed;
    });
  }

  @override
  Future<bool> reveal(InspectorRevealRequest request) async {
    try {
      return await _channel.invokeMethod<bool>('reveal', request.encode()) ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    if (!_listening) return;
    _listening = false;
    try {
      await _channel.setMethodCallHandler(null);
    } on Object {
      // The engine is going away.
    }
  }
}
