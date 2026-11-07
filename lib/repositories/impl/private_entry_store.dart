import 'dart:typed_data';

import '../../models/settings.dart';

/// Bytes kept per repository in a bounded, owner-only private folder.
///
/// A failure to read is reported as an absent entry, and a failure to write
/// or remove is ignored: the stores are caches.
abstract interface class PrivateEntryStore {
  Future<Uint8List?> read(NativePathIdentity repository);
  Future<void> write(NativePathIdentity repository, Uint8List bytes);
  Future<void> remove(NativePathIdentity repository);
}
