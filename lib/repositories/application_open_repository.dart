/// Paths delivered by the operating system to the main application instance.
abstract interface class ApplicationOpenRepository {
  /// Takes a bounded batch, retaining pending requests until the UI attaches.
  Future<List<String>> takePaths();
}
