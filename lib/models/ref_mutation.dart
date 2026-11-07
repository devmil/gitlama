enum RefMutationKind {
  createBranch,
  renameBranch,
  deleteBranch,
  checkoutBranch,
  checkoutCommit,
  setUpstream,
  unsetUpstream,
  createTag,
  deleteTag,
  addRemote,
  editRemote,
  renameRemote,
  removeRemote,
  reset,
}

enum RefResetMode { soft, mixed, hard }

enum RefMutationWarning {
  dirtyCheckout,
  detachedHead,
  publishedBranch,
  checkedOutElsewhere,
  destructiveReset,
}

enum RefMutationExecutionState {
  completed,
  stale,
  failed,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

final class RefMutationRequest {
  const RefMutationRequest({
    required this.kind,
    this.name,
    this.secondName,
    this.target,
    this.message,
    this.url,
    this.force = false,
    this.resetMode,
    this.remoteNames = const [],
    this.deleteUpstream,
    this.checkout = false,
  });

  final RefMutationKind kind;
  final String? name;
  final String? secondName;
  final String? target;
  final String? message;
  final String? url;
  final bool force;
  final RefResetMode? resetMode;

  /// Remotes on which a tag should also be deleted after confirmation.
  final List<String> remoteNames;

  /// The deleted branch's upstream, deleted on its remote after the local
  /// branch.
  final RefMutationUpstream? deleteUpstream;

  /// Switch to a newly created branch.
  final bool checkout;

  /// Whether the change deletes or discards something that may not be
  /// recoverable; its confirmation is marked as dangerous.
  bool get destructive => switch (kind) {
    RefMutationKind.deleteBranch ||
    RefMutationKind.deleteTag ||
    RefMutationKind.removeRemote => true,
    RefMutationKind.reset => resetMode != RefResetMode.soft,
    _ => false,
  };
}

/// A branch on a remote, as `remote`/`branch`.
final class RefMutationUpstream {
  const RefMutationUpstream({required this.remote, required this.branch});

  final String remote;
  final String branch;

  String get label => '$remote/$branch';
}

final class RefMutationPreview {
  const RefMutationPreview({
    required this.token,
    required this.kind,
    required this.arguments,
    required this.warnings,
  });

  final BigInt token;
  final RefMutationKind kind;
  final List<String> arguments;
  final List<RefMutationWarning> warnings;
}

final class RefMutationExecutionResult {
  const RefMutationExecutionResult({required this.state});

  final RefMutationExecutionState state;
}

/// What the Edit branch dialog returns: the branch's new name and the
/// remote branch (`remote/branch`) it should track, or none.
final class EditBranchResult {
  const EditBranchResult({required this.name, required this.upstream});

  final String name;
  final String? upstream;
}
