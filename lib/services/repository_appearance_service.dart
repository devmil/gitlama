import 'dart:async';

import '../models/repository_appearance.dart';
import '../models/settings.dart';
import '../repositories/repository_icon_repository.dart';
import 'settings_service.dart';

/// Owns the icon, colour or image that identifies each repository's tab,
/// and the bounded images read for them. [changes] reports saved
/// appearances and finished image reads.
final class RepositoryAppearanceService {
  RepositoryAppearanceService(this._repository, this._settings);

  final RepositoryIconRepository _repository;
  final SettingsService _settings;
  final Map<NativePathIdentity, RepositoryIconImage?> _images = {};
  final Set<NativePathIdentity> _loading = {};
  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );
  StreamSubscription<SettingsDocument>? _subscription;
  List<RepositoryAppearance> _appearances = const [];
  var _disposed = false;

  Stream<void> get changes => _changes.stream;

  void initialize() {
    _appearances = _settings.current.repositoryAppearances;
    _subscription = _settings.changes.listen((document) {
      final next = document.repositoryAppearances;
      if (_sameAppearances(next, _appearances)) return;
      _appearances = next;
      _changes.add(null);
    });
  }

  RepositoryAppearance? appearanceFor(NativePathIdentity? identity) {
    if (identity == null) return null;
    for (final appearance in _appearances) {
      if (appearance.identity == identity) return appearance;
    }
    return null;
  }

  /// The name the user gave [identity]'s tab, or `null` for the folder's.
  String? nameFor(NativePathIdentity? identity) =>
      appearanceFor(identity)?.name;

  /// Names [identity]'s tab; a blank [name] restores the folder's name.
  Future<void> rename(NativePathIdentity identity, String? name) {
    final normalized = normalizeTabName(name);
    final current =
        appearanceFor(identity) ?? RepositoryAppearance(identity: identity);
    if (current.name == normalized) return Future.value();
    return save(current.withName(normalized));
  }

  /// The image at [path] once read; starts the read on first request and
  /// notifies when it finishes. `null` while reading or when unusable.
  RepositoryIconImage? imageAt(NativePathIdentity path) {
    if (_images.containsKey(path)) return _images[path];
    if (_loading.add(path)) unawaited(_load(path));
    return null;
  }

  /// Whether [path] was read and could not be used.
  bool imageFailed(NativePathIdentity path) =>
      _images.containsKey(path) && _images[path] == null;

  Future<void> _load(NativePathIdentity path) async {
    RepositoryIconImage? image;
    try {
      image = await _repository.loadImage(path);
    } on Object {
      image = null;
    }
    _loading.remove(path);
    if (_disposed) return;
    _images[path] = image;
    _changes.add(null);
  }

  /// Asks for an image file and reads it again even if it was read before,
  /// so an edited file shows its new content.
  Future<NativePathIdentity?> chooseImage() async {
    final path = await _repository.chooseImage();
    if (path != null) _images.remove(path);
    return path;
  }

  /// Saves [appearance]; an empty one removes the repository's entry.
  Future<void> save(RepositoryAppearance appearance) {
    return _settings.updateDurable(
      (current) => current.copyWith(
        repositoryAppearances: [
          for (final entry in current.repositoryAppearances)
            if (entry.identity != appearance.identity) entry,
          if (!appearance.isEmpty) appearance,
        ],
      ),
      restore: (current, previous) => current.copyWith(
        repositoryAppearances: previous.repositoryAppearances,
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _images.clear();
    // Both take effect at once for broadcast streams; awaiting them would
    // also wait for listeners in a still-mounted widget tree.
    unawaited(_subscription?.cancel());
    unawaited(_changes.close());
  }
}

bool _sameAppearances(
  List<RepositoryAppearance> a,
  List<RepositoryAppearance> b,
) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
