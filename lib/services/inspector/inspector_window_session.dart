import 'dart:async';

import '../../models/inspection_window.dart';
import '../../models/repository_state.dart';
import '../../repositories/inspection_session_repository.dart';
import '../diff_syntax_service.dart';
import 'inspector_service.dart';

/// The independent, read-only Git session of one inspector window and the
/// inspector it serves.
final class InspectorWindowSession {
  /// Without [syntax] the window's diffs show plain text.
  InspectorWindowSession(
    this._repository,
    this.request, {
    DiffSyntaxService? syntax,
  }) : inspector = InspectorService(_repository, syntax: syntax);

  final InspectionSessionRepository _repository;
  final InspectionWindowRequest request;
  final InspectorService inspector;
  RepositorySessionIdentity? _identity;
  bool _closed = false;
  bool _failed = false;
  RepositoryFailureCode? _failure;

  /// Counts openings, so a late answer of an earlier one is dropped.
  int _attempt = 0;

  /// The repository could not be opened. The window says so and keeps
  /// running; a failure of the window itself fails its bootstrap instead.
  bool get failed => _failed;

  /// Why the repository could not be opened, when the session said so: a
  /// remote host the main window is not connected to, for example.
  RepositoryFailureCode? get failure => _failure;

  Future<void> initialize() async {
    final attempt = ++_attempt;
    try {
      final opened = await _repository.openIdentity(
        request.repository,
        DateTime.now().microsecondsSinceEpoch,
      );
      if (_closed || attempt != _attempt) {
        await _repository.close(opened.identity);
        return;
      }
      _identity = opened.identity;
      inspector.attach(opened.identity);
      await inspector.navigate(request.location);
    } on Object catch (error) {
      if (_closed || attempt != _attempt) return;
      _failed = true;
      _failure = error is RepositorySessionException
          ? error.failure.code
          : null;
    }
  }

  /// Opens the repository again after it could not be opened.
  Future<void> retry() async {
    if (_closed || !_failed) return;
    _failed = false;
    _failure = null;
    await initialize();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await inspector.dispose();
    if (_identity case final identity?) {
      _identity = null;
      try {
        await _repository.close(identity);
      } on Object {
        // The session ends with the window either way.
      }
    }
  }
}
