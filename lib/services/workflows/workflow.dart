import '../../models/remote_workspace.dart';
import '../../models/repository_state.dart';
import '../../models/workspace.dart';

/// What every workflow asks of the window it runs in. Each workflow family
/// extends this with the decisions only the user can make; the window answers
/// them with its dialogs and shows the outcomes the workflow reports.
abstract interface class WorkflowInteraction {
  /// Whether the window that started the workflow still shows it. A workflow
  /// stops asking and reporting once it does not.
  bool get active;
}

/// A failure every workflow reports the same way, whatever it was doing.
sealed class WorkflowFailure {
  const WorkflowFailure();

  /// The failure [error] stands for, or null for an error the workflow
  /// handles itself. Handlers test their own exception types first.
  static WorkflowFailure? of(Object error) => switch (error) {
    RemoteOutcomeUnknownException() => const OutcomeUnknownFailure(),
    RemoteWorkspaceException(:final code) => RemoteConnectionFailure(code),
    RepositorySessionException(:final failure) => SessionFailure(failure.code),
    _ => null,
  };
}

/// An unexpected failure reported without exposing exception text or stack traces.
final class UnexpectedFailure extends WorkflowFailure {
  const UnexpectedFailure();
}

/// A remote write whose outcome could not be established. It waits for
/// review under Remote changes and is never retried.
final class OutcomeUnknownFailure extends WorkflowFailure {
  const OutcomeUnknownFailure();
}

/// The connection to the repository's host failed.
final class RemoteConnectionFailure extends WorkflowFailure {
  const RemoteConnectionFailure(this.code);

  final RemoteFailureCode code;
}

/// The repository session refused or failed the request.
final class SessionFailure extends WorkflowFailure {
  const SessionFailure(this.code);

  final RepositoryFailureCode code;
}

/// Whether [tab] shows a repository on another computer.
bool isRemoteTab(RepositoryTabState? tab) =>
    (tab?.canonicalIdentity ?? tab?.requestedIdentity)?.remote != null;
