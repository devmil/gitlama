import 'dart:async';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../window_geometry_repository.dart';

final class NativeWindowGeometryRepository
    with WindowListener
    implements WindowGeometryRepository {
  final StreamController<void> _changes = StreamController<void>.broadcast();
  var _available = false;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<bool> initialize() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setMinimumSize(const Size(900, 600));
      windowManager.addListener(this);
      return _available = true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> restore(WindowGeometry? geometry) async {
    if (!_available) return;
    try {
      await _restoreAvailable(geometry);
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    }
  }

  @override
  Future<void> activate() async {
    if (!_available) return;
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    }
  }

  Future<void> _restoreAvailable(WindowGeometry? geometry) async {
    if (geometry == null) {
      await windowManager.setSize(const Size(1280, 800));
      await windowManager.center();
      return;
    }
    final bounds = Rect.fromLTWH(
      geometry.x.toDouble(),
      geometry.y.toDouble(),
      geometry.width.toDouble(),
      geometry.height.toDouble(),
    );
    final displays = await screenRetriever.getAllDisplays();
    final visible = displays.any((display) {
      final position = display.visiblePosition ?? Offset.zero;
      final size = display.visibleSize ?? display.size;
      final intersection = bounds.intersect(position & size);
      return intersection.width >= 100 && intersection.height >= 100;
    });
    if (visible) {
      await windowManager.setBounds(bounds);
    } else {
      await windowManager.setSize(bounds.size);
      await windowManager.center();
    }
    if (geometry.maximized) await windowManager.maximize();
  }

  @override
  Future<WindowGeometry> read() async {
    final bounds = await windowManager.getBounds();
    return WindowGeometry(
      x: bounds.left.round(),
      y: bounds.top.round(),
      width: bounds.width.round().clamp(900, 16384),
      height: bounds.height.round().clamp(600, 16384),
      maximized: await windowManager.isMaximized(),
    );
  }

  @override
  void onWindowMoved() => _changes.add(null);

  @override
  void onWindowResized() => _changes.add(null);

  @override
  void onWindowMaximize() => _changes.add(null);

  @override
  void onWindowUnmaximize() => _changes.add(null);

  @override
  Future<void> dispose() async {
    if (_available) windowManager.removeListener(this);
    await _changes.close();
  }
}
