import 'hosting.dart';

/// Pull requests a repository's branches were last found to have, kept so a
/// branch shows its link at once while the lookup runs again.
///
/// The entry is disposable and may be outdated. It names the hosting binding
/// it was learned under and stands in only for that binding.
final class HostingLinkCacheEntry {
  const HostingLinkCacheEntry({
    required this.connectionId,
    required this.providerRepository,
    this.branches = const {},
    this.authored,
  });

  final String connectionId;
  final String providerRepository;

  /// Pull requests by provider branch, least recently learned first.
  final Map<String, List<HostingChangeRequest>> branches;

  /// The open pull requests the account authored, when known.
  final List<HostingChangeRequest>? authored;

  bool matches(String connectionId, String providerRepository) =>
      this.connectionId == connectionId &&
      this.providerRepository == providerRepository;
}

/// Branches an entry keeps; the least recently learned go first.
const hostingLinkCacheBranchLimit = 300;
