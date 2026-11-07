import 'dart:io';
import 'dart:typed_data';

import '../../models/settings.dart';
import '../../rust/api.dart' as native_api;
import '../../rust/third_party/gitlama_contract/domain/path_identity.dart'
    as native;
import 'private_entry_store.dart';

/// The native private storage of the repository view cache and the hosting
/// link cache, each in its own folder.
final class NativeEntryStore implements PrivateEntryStore {
  /// Stores entries in [folder] beside the default `views` folder.
  NativeEntryStore({this.folder = 'views'});

  final String folder;
  Future<String?>? _directory;

  Future<String?> _cacheDirectory() => _directory ??= _resolveDirectory();

  Future<String?> _resolveDirectory() async {
    final views = await native_api.applicationViewCacheDefaultDirectory();
    if (views == null || folder == 'views') return views;
    return '${File(views).parent.path}${Platform.pathSeparator}$folder';
  }

  native.NativePathIdentity _identity(NativePathIdentity repository) =>
      native.NativePathIdentity(
        platform: switch (repository.platform) {
          NativePathPlatform.unix => native.NativePathPlatform.unix,
          NativePathPlatform.windows => native.NativePathPlatform.windows,
        },
        units: Uint16List.fromList(repository.units),
      );

  // The cache keeps local repositories only: a remote identity's units may
  // equal a local path's, and fetched remote content is never stored on disk.

  @override
  Future<Uint8List?> read(NativePathIdentity repository) async {
    if (repository.isRemote) return null;
    try {
      final directory = await _cacheDirectory();
      if (directory == null) return null;
      final result = await native_api.applicationViewCacheRead(
        directory: directory,
        identity: _identity(repository),
      );
      return result.failure == null ? result.bytes : null;
    } on Object {
      // An unreadable entry is an absent entry; the repository loads.
      return null;
    }
  }

  @override
  Future<void> write(NativePathIdentity repository, Uint8List bytes) async {
    if (repository.isRemote) return;
    try {
      final directory = await _cacheDirectory();
      if (directory == null) return;
      await native_api.applicationViewCacheWrite(
        directory: directory,
        identity: _identity(repository),
        bytes: bytes,
      );
    } on Object {
      // The next change writes again.
    }
  }

  @override
  Future<void> remove(NativePathIdentity repository) async {
    if (repository.isRemote) return;
    try {
      final directory = await _cacheDirectory();
      if (directory == null) return;
      await native_api.applicationViewCacheRemove(
        directory: directory,
        identity: _identity(repository),
      );
    } on Object {
      // A stale entry is rejected again when it is read.
    }
  }
}
