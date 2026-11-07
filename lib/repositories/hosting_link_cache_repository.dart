import '../models/hosting_link_cache.dart';
import '../models/settings.dart';

/// Private storage for the disposable pull-request links of each repository.
///
/// A failure to read, or an entry that cannot be decoded, is reported as an
/// absent entry, and a failure to write or remove is ignored: the links are
/// looked up again either way.
abstract interface class HostingLinkCacheRepository {
  Future<HostingLinkCacheEntry?> read(NativePathIdentity repository);
  Future<void> write(
    NativePathIdentity repository,
    HostingLinkCacheEntry entry,
  );
  Future<void> remove(NativePathIdentity repository);
}
