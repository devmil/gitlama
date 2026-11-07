import '../models/repository_state.dart';

/// The preview tokens a service issued, by family, each bound to the session
/// that previewed it. One registry forgets them all at once, so closing the
/// workspace or a session cannot leave a family behind.
final class PreviewRegistry {
  final List<PreviewTokens<Object?>> _families = [];

  /// A new family whose value names its session through [sessionOf].
  PreviewTokens<V> family<V>(
    RepositorySessionIdentity Function(V value) sessionOf,
  ) {
    final tokens = PreviewTokens<V>._(sessionOf);
    _families.add(tokens);
    return tokens;
  }

  /// A family whose value is the session itself.
  PreviewTokens<RepositorySessionIdentity> sessions() =>
      family<RepositorySessionIdentity>((session) => session);

  /// Drops every token of [session].
  void forgetSession(RepositorySessionIdentity session) {
    for (final family in _families) {
      family._forgetSession(session);
    }
  }

  /// Drops every token.
  void clear() {
    for (final family in _families) {
      family.clear();
    }
  }

  /// How many tokens are held, for tests.
  int get length =>
      _families.fold(0, (total, family) => total + family._entries.length);
}

/// One family's tokens.
final class PreviewTokens<V> {
  PreviewTokens._(this._sessionOf);

  final RepositorySessionIdentity Function(V value) _sessionOf;
  final Map<BigInt, V> _entries = {};

  V? operator [](BigInt token) => _entries[token];

  void operator []=(BigInt token, V value) => _entries[token] = value;

  /// Takes the token: it admits one execution.
  V? remove(BigInt token) => _entries.remove(token);

  void clear() => _entries.clear();

  void _forgetSession(RepositorySessionIdentity session) =>
      _entries.removeWhere((_, value) => _sessionOf(value) == session);
}
