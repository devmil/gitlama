import '../models/inspector_reveal.dart';

/// The channel between inspector windows and the main window.
abstract interface class InspectorRevealRepository {
  /// Serves reveal requests in the main window. [onReveal] returns whether
  /// the repository was open there; the window is brought forward when it
  /// was.
  Future<void> listen(Future<bool> Function(InspectorRevealRequest) onReveal);

  /// Asks the main window to reveal [request]; false when no main window
  /// answers or the repository is not open there.
  Future<bool> reveal(InspectorRevealRequest request);

  Future<void> dispose();
}
