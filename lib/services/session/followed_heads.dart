import '../../models/repository_state.dart';

/// The HEADs operations move to, so History selects and reveals them.
///
/// An operation records the HEAD it starts from; the first snapshot showing
/// another HEAD reveals it once. A HEAD that moved while its tab did not show
/// History is kept for that tab until History loads, if it is still HEAD.
final class FollowedHeads {
  /// Operations whose resulting HEAD History has not shown yet, by native
  /// session.
  final Map<BigInt, _FollowedHead> _followed = {};

  /// A HEAD an operation moved to while its tab did not show History, by tab.
  final Map<int, String> _reveals = {};

  /// Runs [operation] on [identity], which starts at [before]. The snapshot
  /// with the new HEAD can arrive before [operation] returns, so [before] is
  /// recorded first; an outcome that [moved] rejects forgets it.
  Future<T> follow<T>(
    RepositorySessionIdentity identity,
    String? before,
    Future<T> Function() operation,
    bool Function(T result) moved,
  ) async {
    final follow = _FollowedHead(before);
    _followed[identity.nativeId] = follow;
    final T result;
    try {
      result = await operation();
    } catch (_) {
      _forget(identity, follow);
      rethrow;
    }
    if (moved(result)) {
      // The next snapshot settles it, whether or not HEAD moved.
      follow.finished = true;
    } else {
      _forget(identity, follow);
    }
    return result;
  }

  void _forget(RepositorySessionIdentity identity, _FollowedHead follow) {
    if (identical(_followed[identity.nativeId], follow)) {
      _followed.remove(identity.nativeId);
    }
  }

  /// The HEAD an operation of [identity] moved to, once, when [snapshot] is
  /// the first to show it. An operation that left HEAD in place reveals
  /// nothing, and neither does a commit made after it.
  String? take(
    RepositorySessionIdentity identity,
    RepositorySnapshot snapshot,
  ) {
    final follow = _followed[identity.nativeId];
    final head = snapshot.status?.headObjectId;
    if (follow == null || head == null) return null;
    if (head == follow.before) {
      if (follow.finished) _followed.remove(identity.nativeId);
      return null;
    }
    _followed.remove(identity.nativeId);
    return head;
  }

  /// Keeps [head] for tab [tabId] until its History loads.
  void keepReveal(int tabId, String head) => _reveals[tabId] = head;

  /// The HEAD kept for [tabId], when it is still [currentHead].
  String? takeReveal(int tabId, String? currentHead) {
    final kept = _reveals.remove(tabId);
    return kept != null && kept == currentHead ? kept : null;
  }

  void forgetTab(int tabId) => _reveals.remove(tabId);
}

/// A HEAD-moving operation in flight or just finished, with the HEAD it
/// started from.
final class _FollowedHead {
  _FollowedHead(this.before);

  final String? before;
  bool finished = false;
}
