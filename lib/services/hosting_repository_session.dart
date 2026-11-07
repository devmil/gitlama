import 'dart:async';
import 'dart:collection';

import '../models/hosting.dart';
import '../models/hosting_link_cache.dart';
import '../models/settings.dart';
import 'hosting_connection_service.dart';
import '../models/git_names.dart';

/// Most branches one native lookup resolves; larger sets run as batches.
const hostingLookupBatchSize = 20;

/// Branches waiting for a lookup. Older requests are dropped first when rows
/// scroll past faster than lookups complete.
const _lookupQueueLimit = 200;

/// How long a branch whose open pull request is still running checks or
/// computing its mergeability keeps its answer before it is looked up again.
const hostingPendingRecheckDelay = Duration(seconds: 60);

/// How long a branch whose pull request's head is still at none of its
/// unchanged refs waits before it is looked up again. A provider updates a
/// pull request a little after a push, so the lookup right after it can still
/// answer the previous head.
const hostingMovedRecheckDelay = Duration(seconds: 10);

/// How often a branch is looked up again for unchanged refs its pull
/// request's head is still missing from.
const _movedRecheckLimit = 3;

/// Hosting state for one active repository, independent of panel visibility.
///
/// Besides the paged pull-request list, the session links pull requests to
/// branches on demand: views name the provider branches they show through
/// [requestBranches], and the session resolves them in small batches, plus the
/// open pull requests the bound account authored, once per binding. Links
/// learned before, also in an earlier run, show at once and are looked up
/// again the first time a view asks for them. Views name one commit, such as
/// the default branch's head, through [requestHeadChecks] to learn its CI
/// result, which no pull request carries.
final class HostingRepositorySession {
  HostingRepositorySession(
    this._hosting, {
    required this.showResources,
    this.pendingRecheckDelay = hostingPendingRecheckDelay,
    this.movedRecheckDelay = hostingMovedRecheckDelay,
  }) {
    _connections = _hosting.changes.listen((_) => unawaited(resolve()));
  }

  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );
  Stream<void> get changes => _changes.stream;
  void _notify() => _changes.add(null);

  final HostingConnectionService _hosting;
  final bool showResources;

  /// How long an unsettled answer stays before its branch is asked again.
  final Duration pendingRecheckDelay;

  /// How long a branch whose pull request's head is still missing from its
  /// unchanged refs waits before it is asked again.
  final Duration movedRecheckDelay;
  late final StreamSubscription<List<HostingConnection>> _connections;
  Timer? _poll;
  Future<void> _deactivation = Future.value();
  int _generation = 0;
  bool _disposed = false;
  NativePathIdentity? repository;
  List<HostingRemote> _remotes = const [];
  HostingBindingResolution? binding;
  HostingResources resources = const HostingResources();
  HostingResourceSnapshot? snapshot;
  Object? failure;
  bool busy = false;

  /// Known pull requests by branch, cached or looked up, least recent first.
  final Map<String, List<HostingChangeRequest>> _branchPulls = {};

  /// Branches looked up in this session; the others in [_branchPulls] came
  /// from the cache and are looked up again when asked for.
  final Set<String> _freshBranches = {};
  final LinkedHashSet<String> _queuedBranches = LinkedHashSet();
  final Set<String> _inFlightBranches = {};
  final Set<String> _failedBranches = {};
  List<HostingChangeRequest>? _authored;
  bool _authoredRequested = false;
  bool _authoredFresh = false;
  int? _lookupRequestId;
  int _lookupEpoch = 0;
  Timer? _lookupDebounce;
  Timer? _lookupPoll;
  Timer? _pendingRecheck;
  Timer? _movedRecheck;

  /// The branch refs a pull request's head was missing from when its branch
  /// was last looked up again, and how often it was asked since for them, so
  /// each change of those refs asks once at once and a few times later.
  final Map<String, ({String refs, int attempts})> _movedRefs = {};
  final Set<String> _movedBranches = {};
  List<HostingLinkedPullRequest>? _linked;

  /// The commit whose CI result views asked for, and that result once a
  /// lookup answered it.
  String? _head;
  HostingCheckState? _headChecks;
  bool _headQueued = false;
  bool _headInFlight = false;
  bool _headFailed = false;

  /// The failure of the latest pull-request lookup, if it failed.
  HostingResourceFailure? lookupFailure;

  /// Whether a pull-request lookup is queued or running.
  bool get lookingUp =>
      _lookupRequestId != null ||
      _queuedBranches.isNotEmpty ||
      _headQueued ||
      (_lookupsEnabled && !_authoredRequested && _authoredLogin != null);

  Future<void> update(
    NativePathIdentity? nextRepository,
    List<HostingRemote> remotes,
  ) async {
    if (_disposed ||
        (repository == nextRepository && _sameRemotes(_remotes, remotes))) {
      return;
    }
    repository = nextRepository;
    _remotes = List.unmodifiable(remotes);
    await resolve();
  }

  Future<void> resolve({bool refresh = true}) async {
    if (_disposed) return;
    final generation = ++_generation;
    _poll?.cancel();
    final previous = binding;
    binding = null;
    resources = const HostingResources();
    snapshot = null;
    failure = null;
    busy = false;
    _resetLookups();
    _notify();
    try {
      if (showResources && previous?.connectionId != null) {
        _deactivation = _deactivation.then(
          (_) => _hosting.deactivateResources(
            connectionId: previous!.connectionId!,
            providerRepository: previous.providerRepository!,
          ),
        );
      }
      await _deactivation;
      if (!_current(generation) || repository == null || _remotes.isEmpty) {
        return;
      }
      final override = _hosting.bindingFor(repository!);
      final resolution = override == null
          ? await _hosting.resolveBinding(remotes: _remotes)
          : HostingBindingResolution(
              state: HostingBindingState.bound,
              remote: override.remote,
              connectionId: override.connectionId,
              providerRepository: override.providerRepository,
            );
      if (!_current(generation)) return;
      binding = resolution;
      _notify();
      unawaited(_loadCachedLinks(generation));
      _scheduleLookups();
      if (showResources &&
          refresh &&
          resolution.state == HostingBindingState.bound) {
        await this.refresh(manual: false);
      }
    } on Object catch (error) {
      if (_current(generation)) {
        failure = error;
        _notify();
      }
    }
  }

  Future<void> refresh({required bool manual, int page = 1}) async {
    final connectionId = binding?.connectionId;
    final providerRepository = binding?.providerRepository;
    if (_disposed ||
        connectionId == null ||
        providerRepository == null ||
        busy) {
      return;
    }
    final generation = _generation;
    busy = true;
    failure = null;
    if (manual && page == 1) {
      // Visible branches ask again on the next build; what is known stays
      // shown meanwhile.
      _resetLookups(keepKnown: true);
      _scheduleLookups();
    }
    _notify();
    try {
      final next = await _hosting.refreshResources(
        connectionId: connectionId,
        providerRepository: providerRepository,
        page: page,
        manual: manual,
      );
      if (!_current(generation)) {
        await _hosting.cancelResourceRefresh(next.requestId);
        return;
      }
      _apply(next, append: page > 1);
      if (!next.isTerminal) _schedulePoll(next.requestId, page > 1);
    } on Object catch (error) {
      if (_current(generation)) failure = error;
    } finally {
      if (_current(generation)) {
        busy = false;
        _notify();
      }
    }
  }

  void _schedulePoll(int requestId, bool append) {
    _poll?.cancel();
    final generation = _generation;
    _poll = Timer(const Duration(milliseconds: 100), () async {
      try {
        final next = await _hosting.pollResourceRefresh(requestId);
        if (!_current(generation) || next == null) return;
        _apply(next, append: append);
        if (!next.isTerminal) _schedulePoll(requestId, append);
      } on Object catch (error) {
        if (_current(generation)) {
          failure = error;
          _notify();
        }
      }
    });
  }

  void _apply(HostingResourceSnapshot next, {required bool append}) {
    snapshot = next;
    if (!append) {
      resources = next.resources;
    } else if (next.state == HostingResourceLoadState.ready) {
      // A later page starts out showing the cached first page; only its own
      // finished rows are appended, once each.
      resources = HostingResources(
        changeRequests: _appendNew(
          resources.changeRequests,
          next.resources.changeRequests,
          (value) => value.stableId,
        ),
        issues: _appendNew(
          resources.issues,
          next.resources.issues,
          (value) => value.stableId,
        ),
        remoteReferences: _appendNew(
          resources.remoteReferences,
          next.resources.remoteReferences,
          (value) => '${value.kind.name}:${value.stableId}',
        ),
      );
    }
    _linked = null;
    failure = next.failure;
    _notify();
  }

  /// Open and merged pull requests whose source is provider branch [branch]
  /// of the bound repository, or null while that is unknown. A lookup or the
  /// cache answers for good, though a cached answer may be outdated; the
  /// loaded list only proves that an open pull request exists.
  List<HostingChangeRequest>? pullRequestsForBranch(String branch) {
    if (_branchPulls[branch] case final pulls?) return pulls;
    final repository = binding?.providerRepository;
    if (repository == null) return null;
    final listed = [
      for (final pull in resources.changeRequests)
        if (pull.sourceRepository == repository && pull.sourceBranch == branch)
          pull,
    ];
    return listed.isEmpty ? null : listed;
  }

  /// Asks for the pull requests of provider [branches]. Branches looked up in
  /// this session, queued or failed are skipped, so views may call this on
  /// every build of the rows that show them. A cached branch is looked up
  /// again while its cached answer stays shown.
  void requestBranches(Iterable<String> branches) {
    if (!_lookupsEnabled) return;
    var added = false;
    for (final branch in branches) {
      if (branch.isEmpty ||
          _freshBranches.contains(branch) ||
          _inFlightBranches.contains(branch) ||
          _failedBranches.contains(branch)) {
        continue;
      }
      // Re-adding moves a branch to the back: the latest rows go first.
      _queuedBranches.remove(branch);
      _queuedBranches.add(branch);
      added = true;
    }
    while (_queuedBranches.length > _lookupQueueLimit) {
      _queuedBranches.remove(_queuedBranches.first);
    }
    if (added) _scheduleLookups();
  }

  /// Looks [branch] up again when its pull request's head is at none of the
  /// branch's refs: the pull request or the refs moved since the answer.
  /// [refs] names the refs' current targets; each distinct value asks at once
  /// and, while the head stays missing, a few more times after
  /// [movedRecheckDelay], since the provider may not have caught up with a
  /// push yet. Then the provider is not called again until the refs move.
  void recheckBranch(String branch, String refs) {
    if (!_lookupsEnabled ||
        !_freshBranches.contains(branch) ||
        _inFlightBranches.contains(branch)) {
      return;
    }
    final moved = _movedRefs[branch];
    if (moved == null || moved.refs != refs) {
      _movedRefs[branch] = (refs: refs, attempts: 0);
      _movedBranches.remove(branch);
      _freshBranches.remove(branch);
      requestBranches([branch]);
      return;
    }
    if (moved.attempts >= _movedRecheckLimit || !_movedBranches.add(branch)) {
      return;
    }
    _scheduleMovedRecheck();
  }

  void _scheduleMovedRecheck() {
    if (_movedRecheck != null) return;
    final epoch = _lookupEpoch;
    _movedRecheck = Timer(movedRecheckDelay, () {
      _movedRecheck = null;
      if (_disposed || epoch != _lookupEpoch) return;
      final branches = [
        for (final branch in _movedBranches)
          if (_freshBranches.contains(branch)) branch,
      ];
      _movedBranches.clear();
      for (final branch in branches) {
        final moved = _movedRefs[branch]!;
        _movedRefs[branch] = (refs: moved.refs, attempts: moved.attempts + 1);
      }
      _freshBranches.removeAll(branches);
      requestBranches(branches);
    });
  }

  /// The CI result of commit [head] of the bound repository, or null while it
  /// is not known. Asks for it when it was not looked up yet, so views may
  /// call this on every build; asking for another commit forgets the previous
  /// one. A result whose checks are still running is asked again later.
  HostingCheckState? requestHeadChecks(String head) {
    if (!_headChecksEnabled || head.isEmpty) return null;
    if (head != _head) {
      _head = head;
      _headChecks = null;
      _headInFlight = false;
      _headFailed = false;
      _headQueued = true;
      _scheduleLookups();
    }
    return _headChecks;
  }

  /// Pull requests the bound account authored, then the open and then the
  /// merged ones linked to a looked-up branch, each once, newest first within
  /// each group.
  List<HostingLinkedPullRequest> get linkedPullRequests =>
      _linked ??= _computeLinked();

  List<HostingLinkedPullRequest> _computeLinked() {
    final login = _authoredLogin;
    final byNumber = <int, HostingLinkedPullRequest>{};
    for (final pull in _authored ?? const <HostingChangeRequest>[]) {
      byNumber[pull.number] = HostingLinkedPullRequest(
        pull: pull,
        authored: true,
      );
    }
    for (final pulls in _branchPulls.values) {
      for (final pull in pulls) {
        byNumber.putIfAbsent(
          pull.number,
          () => HostingLinkedPullRequest(
            pull: pull,
            authored: login != null && pull.author == login,
            viaBranch: true,
          ),
        );
      }
    }
    final linked = byNumber.values.toList()
      ..sort((left, right) {
        if (left.authored != right.authored) return left.authored ? -1 : 1;
        final leftMerged = left.pull.state == HostingChangeRequestState.merged;
        final rightMerged =
            right.pull.state == HostingChangeRequestState.merged;
        if (leftMerged != rightMerged) return leftMerged ? 1 : -1;
        return right.pull.number.compareTo(left.pull.number);
      });
    return List.unmodifiable(linked);
  }

  HostingConnection? get _connection => switch (binding?.connectionId) {
    final id? => _hosting.connectionFor(id),
    null => null,
  };

  String? get _authoredLogin => switch (_connection?.login) {
    final login? when login.isNotEmpty => login,
    _ => null,
  };

  bool get _lookupsEnabled =>
      _connectionLookups(HostingCapability.changeRequests);

  bool get _headChecksEnabled =>
      _connectionLookups(HostingCapability.commitStatuses) ||
      _connectionLookups(HostingCapability.checkRuns);

  bool _connectionLookups(HostingCapability capability) {
    final connection = _connection;
    return showResources &&
        !_disposed &&
        binding?.state == HostingBindingState.bound &&
        binding?.providerRepository != null &&
        connection != null &&
        connection.enabled &&
        connection.refreshEnabled &&
        connection.capabilities.contains(capability);
  }

  /// Stops lookups. With [keepKnown], what is known stays shown and is looked
  /// up again when asked for; otherwise it is forgotten.
  void _resetLookups({bool keepKnown = false}) {
    _lookupEpoch++;
    _lookupDebounce?.cancel();
    _lookupPoll?.cancel();
    _pendingRecheck?.cancel();
    _pendingRecheck = null;
    _movedRecheck?.cancel();
    _movedRecheck = null;
    _movedBranches.clear();
    if (_lookupRequestId case final requestId? when requestId >= 0) {
      unawaited(_hosting.cancelPullRequestLookup(requestId));
    }
    _lookupRequestId = null;
    _movedRefs.clear();
    if (!keepKnown) {
      _branchPulls.clear();
      _authored = null;
      _head = null;
      _headChecks = null;
    }
    // A known commit is asked again; its result stays shown meanwhile.
    _headQueued = _head != null;
    _headInFlight = false;
    _headFailed = false;
    _freshBranches.clear();
    _queuedBranches.clear();
    _inFlightBranches.clear();
    _failedBranches.clear();
    _authoredRequested = false;
    _authoredFresh = false;
    lookupFailure = null;
    _linked = null;
  }

  // Rows report their branches while they build; a short pause gathers one
  // scroll's worth into a batch.
  void _scheduleLookups() {
    if (_lookupDebounce?.isActive ?? false) return;
    _lookupDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_runLookup()),
    );
  }

  Future<void> _runLookup() async {
    if (_lookupRequestId != null) return;
    final lookups = _lookupsEnabled;
    final head = _headQueued && _headChecksEnabled ? _head : null;
    final authored = lookups && !_authoredRequested && _authoredLogin != null;
    final batch = lookups
        ? _queuedBranches.take(hostingLookupBatchSize).toList()
        : <String>[];
    if (batch.isEmpty && !authored && head == null) return;
    final generation = _generation;
    final epoch = _lookupEpoch;
    bool current() => _current(generation) && epoch == _lookupEpoch;
    final connectionId = binding!.connectionId!;
    final providerRepository = binding!.providerRepository!;
    _queuedBranches.removeAll(batch);
    _inFlightBranches.addAll(batch);
    if (lookups) _authoredRequested = true;
    if (head != null) {
      _headQueued = false;
      _headInFlight = true;
    }
    // Holds the slot while the native request starts.
    _lookupRequestId = -1;
    try {
      final next = await _hosting.lookupPullRequests(
        connectionId: connectionId,
        providerRepository: providerRepository,
        heads: [?head],
        branches: batch,
        authored: authored,
      );
      if (!current()) {
        await _hosting.cancelPullRequestLookup(next.requestId);
        return;
      }
      _lookupRequestId = next.requestId;
      _applyLookup(next, batch);
    } on HostingResourceException catch (error) {
      if (current()) _finishLookup(batch, error.failure);
    } on Object {
      if (current()) _finishLookup(batch, HostingResourceFailure.unavailable);
    }
  }

  void _applyLookup(HostingPullRequestLookupSnapshot next, List<String> batch) {
    var changed = false;
    if (next.heads[_head] case final checks? when _headInFlight) {
      _headInFlight = false;
      changed |= checks != _headChecks;
      _headChecks = checks;
    }
    for (final MapEntry(key: branch, value: pulls) in next.branches.entries) {
      if (!_freshBranches.add(branch)) continue;
      // Reinserting keeps the most recently learned branches last.
      final previous = _branchPulls.remove(branch);
      _branchPulls[branch] = pulls;
      _inFlightBranches.remove(branch);
      changed |= !_samePulls(previous, pulls);
    }
    if (next.authored case final authored? when !_authoredFresh) {
      _authoredFresh = true;
      changed |= !_samePulls(_authored, authored);
      _authored = authored;
    }
    if (changed) _linked = null;
    if (next.isTerminal) {
      _finishLookup(
        batch,
        next.state == HostingResourceLoadState.failed
            ? next.failure ?? HostingResourceFailure.unavailable
            : null,
      );
      return;
    }
    if (changed) _notify();
    _pollLookup(next.requestId, batch);
  }

  void _pollLookup(int requestId, List<String> batch) {
    final generation = _generation;
    _lookupPoll = Timer(const Duration(milliseconds: 150), () async {
      try {
        final next = await _hosting.pollPullRequestLookup(requestId);
        // A reset clears the slot, so a superseded poll stops here.
        if (!_current(generation) || _lookupRequestId != requestId) return;
        if (next == null) {
          _finishLookup(batch, HostingResourceFailure.unavailable);
          return;
        }
        _applyLookup(next, batch);
      } on Object {
        if (_current(generation) && _lookupRequestId == requestId) {
          _finishLookup(batch, HostingResourceFailure.unavailable);
        }
      }
    });
  }

  // Branches the lookup left unanswered are not asked again until the next
  // manual refresh, so a failing provider is not called for every row.
  void _finishLookup(List<String> batch, HostingResourceFailure? failure) {
    _lookupRequestId = null;
    lookupFailure = failure;
    for (final branch in batch) {
      if (_inFlightBranches.remove(branch)) _failedBranches.add(branch);
    }
    if (_headInFlight) {
      _headInFlight = false;
      _headFailed = true;
    }
    _linked = null;
    _rememberLinks();
    _notify();
    if (_queuedBranches.isNotEmpty || _headQueued) _scheduleLookups();
    _schedulePendingRecheck();
  }

  // Checks that are still running and mergeability the provider is still
  // computing settle on their own; their branches are asked again later.
  void _schedulePendingRecheck() {
    if (_pendingRecheck != null) return;
    if (!_headPending &&
        !_freshBranches.any((branch) => _unsettled(_branchPulls[branch]))) {
      return;
    }
    final epoch = _lookupEpoch;
    _pendingRecheck = Timer(pendingRecheckDelay, () {
      _pendingRecheck = null;
      if (_disposed || epoch != _lookupEpoch) return;
      if (_headPending) {
        _headQueued = true;
        _scheduleLookups();
      }
      final unsettled = [
        for (final branch in _freshBranches)
          if (_unsettled(_branchPulls[branch])) branch,
      ];
      _freshBranches.removeAll(unsettled);
      requestBranches(unsettled);
    });
  }

  bool get _headPending =>
      _headChecks == HostingCheckState.pending &&
      !_headQueued &&
      !_headInFlight &&
      !_headFailed;

  static bool _unsettled(List<HostingChangeRequest>? pulls) =>
      pulls?.any(
        (pull) =>
            pull.state == HostingChangeRequestState.open &&
            (pull.checks.state == HostingCheckState.pending ||
                pull.mergeability == HostingMergeability.checking),
      ) ??
      false;

  Future<void> _loadCachedLinks(int generation) async {
    final repository = this.repository;
    final connectionId = binding?.connectionId;
    final providerRepository = binding?.providerRepository;
    if (!showResources ||
        repository == null ||
        connectionId == null ||
        providerRepository == null) {
      return;
    }
    final entry = await _hosting.cachedLinks(
      repository,
      connectionId: connectionId,
      providerRepository: providerRepository,
    );
    if (entry == null || !_current(generation)) return;
    var changed = false;
    for (final MapEntry(key: branch, value: pulls) in entry.branches.entries) {
      // Lookups that finished first are newer than the cache.
      if (_branchPulls.containsKey(branch)) continue;
      _branchPulls[branch] = pulls;
      changed = true;
    }
    if (_authored == null && entry.authored != null) {
      _authored = entry.authored;
      changed = true;
    }
    if (changed) {
      _linked = null;
      _notify();
    }
  }

  void _rememberLinks() {
    final repository = this.repository;
    final connectionId = binding?.connectionId;
    final providerRepository = binding?.providerRepository;
    if (repository == null ||
        connectionId == null ||
        providerRepository == null) {
      return;
    }
    _hosting.rememberLinks(
      repository,
      HostingLinkCacheEntry(
        connectionId: connectionId,
        providerRepository: providerRepository,
        branches: Map.unmodifiable(_branchPulls),
        authored: _authored,
      ),
    );
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void dispose() {
    _disposed = true;
    _generation++;
    _poll?.cancel();
    _lookupDebounce?.cancel();
    _lookupPoll?.cancel();
    _pendingRecheck?.cancel();
    _movedRecheck?.cancel();
    if (_lookupRequestId case final requestId? when requestId >= 0) {
      unawaited(_hosting.cancelPullRequestLookup(requestId));
    }
    unawaited(_connections.cancel());
    final previous = binding;
    final deactivation = showResources && previous?.connectionId != null
        ? _hosting.deactivateResources(
            connectionId: previous!.connectionId!,
            providerRepository: previous.providerRepository!,
          )
        : Future<void>.value();
    unawaited(deactivation);
    unawaited(_changes.close());
  }
}

bool _samePulls(
  List<HostingChangeRequest>? left,
  List<HostingChangeRequest>? right,
) {
  if (left == null || right == null) return left == right;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a.number != b.number ||
        a.state != b.state ||
        a.draft != b.draft ||
        a.title != b.title ||
        a.headSha != b.headSha ||
        a.checks.state != b.checks.state ||
        a.mergeability != b.mergeability) {
      return false;
    }
  }
  return true;
}

List<T> _appendNew<T>(
  List<T> current,
  List<T> next,
  String Function(T value) identity,
) {
  final seen = {for (final value in current) identity(value)};
  return [
    ...current,
    for (final value in next)
      if (seen.add(identity(value))) value,
  ];
}

bool _sameRemotes(List<HostingRemote> left, List<HostingRemote> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].url != right[index].url ||
        !sameBytes(left[index].name, right[index].name)) {
      return false;
    }
  }
  return true;
}
