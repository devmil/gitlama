final class RecentCommitMessage {
  const RecentCommitMessage({
    required this.objectId,
    required this.subject,
    required this.description,
  });

  final String objectId;
  final String subject;
  final String description;
}

final class CommitTools {
  const CommitTools({this.recent = const [], this.template});

  final List<RecentCommitMessage> recent;
  final String? template;
}

final class CommitRequest {
  const CommitRequest({
    required this.subject,
    this.description = '',
    this.coauthors = const [],
    this.author,
    this.amend = false,
    this.skipHooks = false,
    this.signing = CommitSigning.useGitConfiguration,
    this.signOff = false,
  });

  final String subject;
  final String description;
  final List<String> coauthors;
  final String? author;
  final bool amend;
  final bool skipHooks;
  final CommitSigning signing;
  final bool signOff;
}

enum CommitSigning { useGitConfiguration, require, disable }

enum CommitWarning { publishedAmend }

final class CommitPreview {
  const CommitPreview({
    required this.token,
    required this.warnings,
    required this.arguments,
  });

  final BigInt token;
  final List<CommitWarning> warnings;
  final List<String> arguments;
}

enum CommitExecutionState {
  completed,
  stale,
  failed,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

enum CommitFailureKind { hook, signing, other }

final class CommitExecutionResult {
  const CommitExecutionResult({
    required this.state,
    this.commit,
    this.failureKind,
    this.exitCode,
    this.output = const [],
  });

  final CommitExecutionState state;
  final String? commit;
  final CommitFailureKind? failureKind;
  final int? exitCode;
  final List<String> output;
}
