final class WindowGeometry {
  const WindowGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.maximized,
  });

  final int x;
  final int y;
  final int width;
  final int height;
  final bool maximized;
}

abstract interface class WindowGeometryRepository {
  Stream<void> get changes;

  Future<bool> initialize();
  Future<void> restore(WindowGeometry? geometry);
  Future<void> activate();
  Future<WindowGeometry> read();
  Future<void> dispose();
}
